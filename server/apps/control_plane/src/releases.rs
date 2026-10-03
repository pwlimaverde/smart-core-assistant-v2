//! Releases do app Windows: emissão do link de download assinado (RPC
//! `IssueReleaseDownloadTicket`, chamado pelo `runtime_api` em
//! `AdminService.GetWindowsDownloadLink`).
//!
//! Fluxo: lê o `installers.json` do canal no `releases_server`, escolhe a versão,
//! assina o ticket (crate `release_ticket`, segredo `RELEASES_DOWNLOAD_SECRET`) e
//! publica `release_download_link_issued` no `security:stream`.
//!
//! Ambiente:
//! - `RELEASES_DOWNLOAD_SECRET` — sem ele a rota recusa (fechado) e o resto do
//!   control_plane segue no ar.
//! - `RELEASES_PUBLIC_URL`   — base da URL entregue ao navegador.
//! - `RELEASES_INTERNAL_URL` — de onde ler o manifesto (padrão: a pública).

use contracts::{Envelope, MessageKind, TenantEnvelope};
use error_core::AppError;
use release_ticket::manifesto::{Instalador, ManifestoInstaladores};
use release_ticket::{Claims, TTL_SEGUNDOS, VERSAO_FORMATO};
use std::sync::OnceLock;
use std::time::Duration;
use uuid::Uuid;

const URL_PADRAO: &str = "https://releases.smartcoreassistant.com.br";
const METODO_REPLY: &str = "IssueReleaseDownloadTicketReply";
/// Identificador da chave atual (rotação futura do segredo).
const KID: &str = "rel-1";

/// Link emitido — o que volta para o `runtime_api`. O ticket só existe dentro da URL.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct LinkEmitido {
    pub url: String,
    pub version: String,
    pub file_name: String,
    pub size_bytes: i64,
    pub sha256: String,
    pub release_notes_md: String,
    pub expires_at_ms: i64,
    /// Vai para a auditoria; nunca o ticket inteiro.
    #[serde(skip)]
    pub jti: String,
}

/// Canal aceito nesta entrega: só `beta` (o `stable` fica para a v1.0.0).
pub fn validar_canal(canal: &str) -> Result<(), AppError> {
    if canal == "beta" {
        Ok(())
    } else {
        Err(AppError::Validation(format!(
            "canal '{canal}' não suportado (use 'beta')"
        )))
    }
}

/// Monta a URL assinada para um instalador. Pura: tempo e `jti` vêm de fora.
pub fn montar_link(
    inst: &Instalador,
    canal: &str,
    user_id: i32,
    segredo: &[u8],
    base_url: &str,
    agora: i64,
    jti: String,
) -> Result<LinkEmitido, AppError> {
    let claims = Claims {
        v: VERSAO_FORMATO,
        kid: KID.to_string(),
        jti: jti.clone(),
        sub: user_id,
        ver: inst.version.clone(),
        file: inst.file_name.clone(),
        ch: canal.to_string(),
        iat: agora,
        exp: agora + TTL_SEGUNDOS,
    };
    let ticket = release_ticket::assinar(&claims, segredo)
        .map_err(|e| AppError::Internal(format!("falha ao assinar ticket: {e}")))?;
    Ok(LinkEmitido {
        url: format!(
            "{}/download/{}/{}?t={}",
            base_url.trim_end_matches('/'),
            inst.version,
            inst.file_name,
            ticket
        ),
        version: inst.version.clone(),
        file_name: inst.file_name.clone(),
        size_bytes: inst.size_bytes,
        sha256: inst.sha256.clone(),
        release_notes_md: inst.release_notes_md.clone(),
        expires_at_ms: claims.exp * 1000,
        jti,
    })
}

fn cliente_http() -> &'static reqwest::Client {
    static CLIENTE: OnceLock<reqwest::Client> = OnceLock::new();
    CLIENTE.get_or_init(|| {
        reqwest::Client::builder()
            .timeout(Duration::from_secs(5))
            .build()
            .unwrap_or_default()
    })
}

async fn buscar_manifesto(base: &str, canal: &str) -> Result<ManifestoInstaladores, AppError> {
    let url = format!("{}/api/installers/{canal}", base.trim_end_matches('/'));
    let resp = cliente_http()
        .get(&url)
        .send()
        .await
        .map_err(|e| AppError::Internal(format!("releases_server inacessível: {e}")))?;
    if !resp.status().is_success() {
        return Err(AppError::Internal(format!(
            "releases_server respondeu {} em {url}",
            resp.status()
        )));
    }
    resp.json::<ManifestoInstaladores>()
        .await
        .map_err(|e| AppError::Internal(format!("installers.json inválido: {e}")))
}

/// Executa o pedido completo (sem auditoria).
async fn emitir(canal: &str, versao: &str, user_id: i32) -> Result<LinkEmitido, AppError> {
    validar_canal(canal)?;
    let segredo = std::env::var("RELEASES_DOWNLOAD_SECRET").unwrap_or_default();
    if segredo.is_empty() {
        // CONFLICT → FAILED_PRECONDITION na borda: o serviço existe, falta configurar.
        return Err(AppError::Conflict(
            "downloads de release não configurados".to_string(),
        ));
    }
    let publica = std::env::var("RELEASES_PUBLIC_URL").unwrap_or_else(|_| URL_PADRAO.to_string());
    let interna = std::env::var("RELEASES_INTERNAL_URL").unwrap_or_else(|_| publica.clone());

    let manifesto = buscar_manifesto(&interna, canal).await?;
    let inst = manifesto.escolher(versao).ok_or_else(|| {
        // "não encontrado" → STORAGE_NOT_FOUND → NOT_FOUND na borda.
        AppError::Storage(format!(
            "release não encontrado: canal {canal}, versão '{versao}'"
        ))
    })?;
    montar_link(
        inst,
        canal,
        user_id,
        segredo.as_bytes(),
        &publica,
        chrono::Utc::now().timestamp(),
        Uuid::now_v7().to_string(),
    )
}

fn erro(env: Envelope, e: AppError) -> Envelope {
    let err_env = e.to_error_envelope(&env.traceparent, "control_plane");
    Envelope {
        kind: MessageKind::Error as i32,
        method: METODO_REPLY.to_string(),
        error: Some(err_env),
        ..env
    }
}

/// Handler RPC `IssueReleaseDownloadTicket`. Entrada `{channel, version}`
/// (`version` vazia = a mais recente). Só superusuário: a borda já exige, e aqui
/// a checagem se repete para o RPC interno não virar porta lateral.
#[tracing::instrument(
    skip_all,
    fields(service = "control_plane", rpc = "IssueReleaseDownloadTicket", traceparent = %env.traceparent)
)]
pub async fn handler_issue_release_download_ticket(
    mut redis_conn: redis::aio::ConnectionManager,
    env: Envelope,
) -> Envelope {
    if !env.auth_is_superuser {
        return erro(
            env,
            AppError::Auth("permissão insuficiente: requer superusuário".to_string()),
        );
    }
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(env, AppError::Validation(e.to_string())),
    };
    let texto = |campo: &str| {
        payload
            .get(campo)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .trim()
            .to_string()
    };
    let canal = texto("channel");
    let versao = texto("version");

    let link = match emitir(&canal, &versao, env.auth_user_id).await {
        Ok(l) => l,
        Err(e) => return erro(env, e),
    };

    // Auditoria (catálogo: release_download_link_issued). Só identificadores:
    // jti, usuário, canal, versão e arquivo — nunca o ticket.
    let audit_payload = observability::AuditLogPayload {
        tenant_id: None,
        level: "INFO".to_string(),
        service: "control_plane".to_string(),
        trace_id: Some(env.traceparent.clone()),
        event: "release_download_link_issued".to_string(),
        message: format!(
            "Link de download do instalador {} ({canal}) emitido",
            link.version
        ),
        context: serde_json::json!({
            "jti": link.jti,
            "channel": canal,
            "version": link.version,
            "file_name": link.file_name,
            "expires_at_ms": link.expires_at_ms,
        }),
        user_id: (env.auth_user_id > 0).then_some(env.auth_user_id),
        ip_address: None,
        user_agent: None,
    };
    let evento = TenantEnvelope::novo(Uuid::nil(), "security.audit", audit_payload)
        .com_traceparent(env.traceparent.clone());
    if let Err(e) = transport::bus::publicar_evento_seguranca(&mut redis_conn, &evento).await {
        tracing::warn!(erro = %e, "falha ao publicar auditoria de link de release");
    }

    let corpo = serde_json::to_vec(&link).unwrap_or_default();
    Envelope {
        kind: MessageKind::Reply as i32,
        method: METODO_REPLY.to_string(),
        payload: corpo,
        error: None,
        ..env
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn inst() -> Instalador {
        Instalador {
            version: "0.2.0-beta.1".into(),
            file_name: "SmartCoreTenant-beta-Setup.exe".into(),
            sha256: "ab".repeat(32),
            size_bytes: 42,
            release_notes_md: "notas".into(),
            published_at_ms: 1,
        }
    }

    #[test]
    fn so_o_canal_beta_e_aceito() {
        assert!(validar_canal("beta").is_ok());
        assert!(validar_canal("stable").is_err());
        assert!(validar_canal("").is_err());
    }

    #[test]
    fn link_traz_ticket_verificavel_pelo_releases_server() {
        let segredo = b"segredo-de-teste";
        let link = montar_link(
            &inst(),
            "beta",
            7,
            segredo,
            "https://rel.exemplo/",
            1_000,
            "jti-1".into(),
        )
        .unwrap();
        let prefixo = "https://rel.exemplo/download/0.2.0-beta.1/SmartCoreTenant-beta-Setup.exe?t=";
        assert!(link.url.starts_with(prefixo), "{}", link.url);
        assert_eq!(link.expires_at_ms, (1_000 + TTL_SEGUNDOS) * 1000);

        // O mesmo crate do outro lado aceita o ticket e devolve as claims certas.
        let ticket = &link.url[prefixo.len()..];
        let claims = release_ticket::verificar(ticket, segredo, 1_010).unwrap();
        assert_eq!(claims.sub, 7);
        assert_eq!(claims.ver, "0.2.0-beta.1");
        assert_eq!(claims.file, "SmartCoreTenant-beta-Setup.exe");
        assert_eq!(claims.ch, "beta");
        assert_eq!(claims.jti, "jti-1");
    }

    #[test]
    fn json_de_resposta_nao_carrega_o_jti() {
        let link = montar_link(&inst(), "beta", 1, b"s", URL_PADRAO, 0, "jti-x".into()).unwrap();
        let v = serde_json::to_value(&link).unwrap();
        assert!(v.get("jti").is_none());
        assert_eq!(v["size_bytes"], 42);
    }

    #[tokio::test]
    async fn canal_invalido_recusa_antes_de_ler_ambiente_ou_rede() {
        // Canal inválido é recusado antes de qualquer leitura de ambiente/rede.
        assert!(matches!(
            emitir("stable", "", 1).await,
            Err(AppError::Validation(_))
        ));
    }
}
