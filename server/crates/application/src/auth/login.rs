// application/src/auth/login.rs (comentários em pt-br)
use contracts::{Envelope, MessageKind};
use error_core::AppError;
use std::time::Duration;
use uuid::Uuid;

use crate::jwt::{self, Claims};
use crate::tokens::{gerar_refresh_token, hash_refresh_token};

/// Dependências necessárias para a execução do fluxo de autenticação.
pub struct AuthDeps {
    /// Cliente multiplexado para chamadas ao data_postgres.
    pub pg: transport::MuxClient,
    /// Cliente multiplexado para chamadas ao data_redis.
    pub redis: transport::MuxClient,
    /// Cliente do `data_storage` (N9/E1). A borda precisa dele para compor o
    /// upload de mídia: o `data_postgres` valida o atendimento e a quota, e o
    /// `data_storage` assina a URL — são duas portas de dados distintas, e quem
    /// as combina para atender uma tela é a borda, não uma delas.
    ///
    /// `Option` porque o `control_plane` e os testes montam `AuthDeps` sem
    /// storage; nesses casos o caminho de mídia responde "indisponível" em vez
    /// de exigir um serviço que aquele processo não usa.
    pub storage: Option<transport::MuxClient>,
    /// Tempo de expiração em segundos do access token (JWT).
    pub access_ttl_s: i64,
    /// Tempo de expiração em segundos do refresh token.
    pub refresh_ttl_s: u64,
    /// Máximo de tentativas de login por janela (rate limiting, doc 09 §6.5).
    pub login_rate_max: u64,
    /// Janela do rate limiting de login, em segundos.
    pub login_rate_window_s: u64,
}

/// Helper para criar envelopes de requisição RPC síncronos padrão.
pub fn montar_envelope_request(
    tenant_id: Uuid,
    traceparent: &str,
    method: &str,
    payload: &serde_json::Value,
) -> Envelope {
    Envelope {
        tenant_id: tenant_id.to_string(),
        schema_version: 1,
        message_id: Uuid::now_v7().to_string(),
        causation_id: "".to_string(),
        traceparent: traceparent.to_string(),
        occurred_at: chrono::Utc::now().timestamp_millis(),
        kind: MessageKind::Request as i32,
        method: method.to_string(),
        payload: serde_json::to_vec(payload).unwrap_or_default(),
        error: None,
        // Campos de identidade aditivos iniciam em zero/vazio
        auth_user_id: 0,
        auth_scopes: vec![],
        auth_is_superuser: false,
        flow_permissions: vec![],
        user_agent: String::new(),
    }
}

/// Identidade resolvida de um usuário que acabou de provar quem é.
///
/// É o resultado de [`autenticar`], compartilhado por dois consumidores que
/// precisam **exatamente** dos mesmos escopos: o login do painel e a tela de
/// consentimento do authorization server OAuth (N13.1). Se cada um derivasse os
/// escopos por conta própria, a regra do subconjunto do MCP passaria a comparar
/// dois catálogos que poderiam divergir — e divergiriam, na primeira mudança.
#[derive(Debug, Clone)]
pub struct UsuarioAutenticado {
    pub user_id: i32,
    /// `Uuid::nil()` para superusuário (contexto global, sem tenant).
    pub tenant_id: Uuid,
    pub is_superuser: bool,
    pub scopes: Vec<String>,
    /// De onde os escopos vieram. Instrumento da D4 (plano
    /// `regras-do-bot-e-permissoes`): sem ele, o caminho OAuth do MCP — que
    /// renova token a cada 15 minutos — ficaria fora da medição.
    pub origem_escopos: OrigemEscopos,
}

/// Verifica credenciais e resolve identidade + escopos, sem emitir token nenhum.
///
/// Inclui o rate limit por e-mail: qualquer caminho que aceite senha passa por
/// aqui, então a proteção contra força bruta não depende de o chamador lembrar
/// de aplicá-la.
// `email`/`password` ficam fora do span (PII/credencial); a correlação é pelo traceparent.
// `origem_escopos` é o instrumento da D4 (plano `regras-do-bot-e-permissoes`),
// que mede quantas sessões dependem do fallback pelo `role` antes de fechá-lo.
// Ele fica AQUI, e não no `login`, porque a derivação de escopos desceu para
// `autenticar` — e assim o fluxo OAuth do MCP, que renova token a cada 15
// minutos, também é medido. Se o campo tivesse ficado só no `login`, a medição
// da D4 ignoraria justamente o caminho de maior volume.
#[tracing::instrument(skip_all, fields(traceparent = %traceparent, origem_escopos = tracing::field::Empty))]
pub async fn autenticar(
    deps: &AuthDeps,
    traceparent: &str,
    email: &str,
    password: &str,
) -> Result<UsuarioAutenticado, AppError> {
    // 0. Rate limiting por e-mail (INCR+EXPIRE via data_redis, doc 09 §6.5).
    // Falha fechada: o login já depende do data_redis para persistir a sessão,
    // então uma indisponibilidade aqui não abre brecha para força bruta.
    let rate_key = crate::tokens::hash_sha256_hex(&email.trim().to_lowercase());
    let rate_payload = serde_json::json!({
        "key_hash": rate_key,
        "window_s": deps.login_rate_window_s,
    });
    let rate_req = montar_envelope_request(
        Uuid::nil(),
        traceparent,
        "RegisterLoginAttempt",
        &rate_payload,
    );

    let rate_resp = deps
        .redis
        .call(rate_req, Duration::from_secs(5))
        .await
        .map_err(|e| AppError::Cache(format!("RPC RegisterLoginAttempt falhou: {:?}", e)))?;

    if rate_resp.kind == MessageKind::Error as i32 {
        return Err(rate_resp
            .error
            .map(|e| AppError::from_envelope(&e))
            .unwrap_or_else(|| {
                AppError::Cache("falha ao registrar tentativa de login".to_string())
            }));
    }

    let attempts = serde_json::from_slice::<serde_json::Value>(&rate_resp.payload)
        .ok()
        .and_then(|v| v.get("attempts").and_then(|a| a.as_u64()))
        .unwrap_or(u64::MAX); // resposta malformada conta como estouro (falha fechada)

    if attempts > deps.login_rate_max {
        // O identificador fica fora do log (PII); o hash permite correlacionar tentativas.
        tracing::warn!(
            attempts,
            limite = deps.login_rate_max,
            janela_s = deps.login_rate_window_s,
            key_hash = %rate_key,
            "rate limit de login excedido"
        );
        return Err(AppError::RateLimit(
            "muitas tentativas de login; aguarde antes de tentar novamente".to_string(),
        ));
    }

    // 1. Verificar as credenciais chamando a RPC VerifyCredentials no data_postgres
    let verify_payload = serde_json::json!({
        "email": email,
        "password": password,
    });
    let verify_req = montar_envelope_request(
        Uuid::nil(),
        traceparent,
        "VerifyCredentials",
        &verify_payload,
    );

    let verify_resp = deps
        .pg
        .call(verify_req, Duration::from_secs(5))
        .await
        .map_err(|e| AppError::Database(format!("RPC VerifyCredentials falhou: {:?}", e)))?;

    if verify_resp.kind == MessageKind::Error as i32 {
        return Err(verify_resp
            .error
            .map(|e| AppError::from_envelope(&e))
            .unwrap_or_else(|| AppError::Auth("credenciais inválidas".to_string())));
    }

    let user_info: serde_json::Value =
        serde_json::from_slice(&verify_resp.payload).map_err(|e| {
            AppError::Internal(format!(
                "erro ao desserializar resposta de credenciais: {e}"
            ))
        })?;

    // Resposta sem `id` (ou com `id` zero) significa que o `data_postgres`
    // devolveu algo que não é um usuário. Antes isso virava `unwrap_or(0)` e
    // seguia adiante, emitindo um JWT com `sub = "0"` — uma sessão que existe
    // sem dono. Agora falha fechado: nenhum caminho a jusante (nem o login, nem
    // o consentimento OAuth) precisa lidar com um usuário inexistente.
    let user_id = match user_info.get("id").and_then(|v| v.as_i64()) {
        Some(id) if id > 0 => id as i32,
        _ => {
            return Err(AppError::Auth(
                "resposta de credenciais sem identificador de usuário".to_string(),
            ))
        }
    };
    let is_superuser = user_info
        .get("is_superuser")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    // 2. Resolver o tenant_id do usuário (superusuário = Uuid::nil())
    let tenant_str = user_info
        .get("tenant_id")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let tenant_opt = Uuid::parse_str(tenant_str).ok().filter(|_| !is_superuser);

    // Se o usuário comum não tiver um tenant associado, rejeitar o login
    if !is_superuser && tenant_opt.is_none() {
        return Err(AppError::Auth("usuário sem tenant associado".to_string()));
    }

    let tenant_id = tenant_opt.unwrap_or_else(Uuid::nil);

    let (scopes, origem_escopos) = derivar_escopos(is_superuser, &user_info);
    // O instrumento da D4: sem este campo não há como saber quantas sessões
    // dependem do fallback, e sem esse número fechar o fallback é chute.
    tracing::Span::current().record("origem_escopos", origem_escopos.como_str());

    Ok(UsuarioAutenticado {
        user_id,
        tenant_id,
        is_superuser,
        scopes,
        origem_escopos,
    })
}

/// Realiza o login real do usuário validando as credenciais no Postgres
/// e persistindo a sessão (refresh token) no Redis.
// `email`/`password` ficam fora do span (PII/credencial); a correlação é pelo traceparent.
#[tracing::instrument(skip_all, fields(traceparent = %traceparent))]
pub async fn login(
    deps: &AuthDeps,
    traceparent: &str,
    email: &str,
    password: &str,
) -> Result<serde_json::Value, AppError> {
    let usuario = autenticar(deps, traceparent, email, password).await?;
    let UsuarioAutenticado {
        user_id,
        tenant_id,
        is_superuser,
        scopes,
        // A origem já foi registrada no span de `autenticar`, que é o mesmo
        // trace desta chamada — não se registra de novo aqui.
        origem_escopos: _,
    } = usuario;

    // 3. Montar as claims e gerar o access token (JWT)
    let agora = chrono::Utc::now().timestamp() as usize;
    let jti = Uuid::now_v7().to_string();
    let family_id = Uuid::now_v7().to_string();

    let claims = Claims {
        sub: user_id.to_string(),
        tenant_id: if is_superuser {
            "".to_string()
        } else {
            tenant_id.to_string()
        },
        scopes,
        is_superuser,
        jti,
        iat: agora,
        exp: agora + deps.access_ttl_s as usize,
    };

    let access_token = jwt::gerar_access_token(&claims)?;

    // 4. Gerar o token de refresh opaco e seu hash correspondente
    let refresh_token = gerar_refresh_token();
    let refresh_hash = hash_refresh_token(&refresh_token);

    // 5. Salvar o refresh token no cache do Redis chamando StoreRefreshToken no data_redis
    let store_payload = serde_json::json!({
        "token_hash": refresh_hash,
        "user_id": user_id,
        "family_id": family_id,
        "ttl": deps.refresh_ttl_s,
    });

    // O request de persistência do token é enviado no contexto do tenant dele
    let store_req =
        montar_envelope_request(tenant_id, traceparent, "StoreRefreshToken", &store_payload);

    let store_resp = deps
        .redis
        .call(store_req, Duration::from_secs(5))
        .await
        .map_err(|e| AppError::Cache(format!("RPC StoreRefreshToken falhou: {:?}", e)))?;

    if store_resp.kind == MessageKind::Error as i32 {
        return Err(store_resp
            .error
            .map(|e| AppError::from_envelope(&e))
            .unwrap_or_else(|| AppError::Cache("falha ao salvar refresh token".to_string())));
    }

    tracing::info!(
        user_id,
        is_superuser,
        tenant_id = %claims.tenant_id,
        "login bem-sucedido"
    );

    // `user_id`/`tenant_id` já constam nas claims do JWT devolvido; expô-los aqui
    // permite à borda auditar `login_success` sem decodificar o token.
    Ok(serde_json::json!({
        "access_token": access_token,
        "refresh_token": refresh_token,
        "expires_in": deps.access_ttl_s,
        "user_id": user_id,
        "tenant_id": claims.tenant_id,
    }))
}

/// Deriva a lista de escopos do usuário com base no seu status de superusuário
/// ou informações de permissão explícitas.
/// De onde vieram os escopos de uma sessão.
///
/// Existe para **medir antes de apertar**. O fallback pelo `role` (ver
/// [`derivar_escopos`]) dá escrita a qualquer não-admin, e não há papel
/// somente-leitura enquanto ele for assim. Fechá-lo às cegas derrubaria o acesso
/// de quem já trabalha — então o primeiro passo é descobrir **quantos** dependem
/// dele, com este campo no span de login.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OrigemEscopos {
    /// Superusuário: `["*"]`.
    Superusuario,
    /// `module_permissions` explícito — o caminho desejado.
    ModulePermissions,
    /// Caiu no `role`. É este que precisa acabar.
    FallbackRole,
}

impl OrigemEscopos {
    pub fn como_str(self) -> &'static str {
        match self {
            Self::Superusuario => "superusuario",
            Self::ModulePermissions => "module_permissions",
            Self::FallbackRole => "fallback_role",
        }
    }
}

/// Escopos de leitura, sem nenhuma escrita.
///
/// Base do papel `viewer` da v1, que a v2 não tinha como representar.
fn escopos_somente_leitura() -> Vec<String> {
    vec!["atendimentos:read".into()]
}

/// `pub`, e não `pub(crate)`: o authorization server OAuth do MCP (N13.1) vive
/// em outra crate (`control_plane`) e precisa **reler** os escopos atuais do
/// usuário a cada emissão de access token, a partir da resposta de
/// `GetUserIdentity` — que tem exatamente este formato. Se o AS derivasse por
/// conta própria, um rebaixamento no painel poderia encolher a sessão web e não
/// o agente, ou o contrário.
pub fn derivar_escopos(
    is_superuser: bool,
    user_info: &serde_json::Value,
) -> (Vec<String>, OrigemEscopos) {
    if is_superuser {
        // Superusuário possui acesso administrativo global.
        return (vec!["*".to_string()], OrigemEscopos::Superusuario);
    }

    // Tenta obter permissões explícitas em module_permissions.
    //
    // Lista vazia **não** conta como explícita: um `[]` gravado por engano
    // deixaria a sessão sem escopo nenhum, e o usuário não conseguiria abrir uma
    // tela sequer. Nesse caso o fallback abaixo ainda é a rede de proteção — e é
    // exatamente por isso que fechá-lo exige medir antes.
    if let Some(perms) = user_info.get("module_permissions") {
        if let Some(arr) = perms.as_array() {
            let escopos: Vec<String> = arr
                .iter()
                .filter_map(|v| v.as_str().map(|s| s.to_string()))
                .collect();
            if !escopos.is_empty() {
                return (escopos, OrigemEscopos::ModulePermissions);
            }
        }
        if let Some(obj) = perms.as_object() {
            let escopos: Vec<String> = obj
                .iter()
                .filter(|(_, v)| v.as_bool().unwrap_or(false))
                .map(|(k, _)| k.clone())
                .collect();
            if !escopos.is_empty() {
                return (escopos, OrigemEscopos::ModulePermissions);
            }
        }
    }

    // Fallback pelo cargo (role) do usuário no tenant.
    //
    // 🚩 **Este bloco é o problema conhecido**, registrado no plano
    // `regras-do-bot-e-permissoes` (D4): quem não tem `module_permissions`
    // explícito nasce podendo **escrever**. Não dá para apertá-lo sem antes
    // migrar quem depende dele — daí o `origem_escopos` no span de login, que
    // mede exatamente isso.
    //
    // O que já é seguro fazer, e está feito: `viewer` ganha o arco somente
    // leitura. Ele não muda nada para ninguém hoje (nenhum usuário tem esse
    // papel) e é o que torna o papel **representável** quando a migração
    // acontecer.
    let role = user_info
        .get("role")
        .and_then(|v| v.as_str())
        .unwrap_or("atendente");
    let escopos = match role {
        "admin" | "owner" => vec![
            "atendimentos:read".into(),
            "atendimentos:write".into(),
            "clientes:write".into(),
            "tenant:admin".into(),
        ],
        "viewer" => escopos_somente_leitura(),
        _ => vec![
            "atendimentos:read".into(),
            "atendimentos:write".into(),
            "clientes:write".into(),
        ],
    };
    (escopos, OrigemEscopos::FallbackRole)
}

#[cfg(test)]
mod tests {
    use super::*;

    // -- derivar_escopos --------------------------------------------------

    #[test]
    fn derivar_escopos_superusuario_ignora_module_permissions_e_role() {
        let info = serde_json::json!({
            "module_permissions": ["atendimentos:read"],
            "role": "atendente",
        });
        assert_eq!(derivar_escopos(true, &info).0, vec!["*".to_string()]);
    }

    #[test]
    fn derivar_escopos_usa_module_permissions_quando_e_array() {
        let info = serde_json::json!({
            "module_permissions": ["atendimentos:read", "clientes:write"],
        });
        assert_eq!(
            derivar_escopos(false, &info).0,
            vec![
                "atendimentos:read".to_string(),
                "clientes:write".to_string()
            ]
        );
    }

    #[test]
    fn derivar_escopos_usa_module_permissions_quando_e_objeto_de_flags() {
        let info = serde_json::json!({
            "module_permissions": {
                "atendimentos:read": true,
                "clientes:write": false,
                "tenant:admin": true,
            },
        });
        let (mut escopos, _) = derivar_escopos(false, &info);
        escopos.sort();
        assert_eq!(
            escopos,
            vec!["atendimentos:read".to_string(), "tenant:admin".to_string()]
        );
    }

    #[test]
    fn derivar_escopos_fallback_para_admin_inclui_tenant_admin() {
        let info = serde_json::json!({ "role": "admin" });
        let (escopos, _) = derivar_escopos(false, &info);
        assert!(escopos.contains(&"tenant:admin".to_string()));
    }

    #[test]
    fn derivar_escopos_fallback_para_owner_inclui_tenant_admin() {
        let info = serde_json::json!({ "role": "owner" });
        let (escopos, _) = derivar_escopos(false, &info);
        assert!(escopos.contains(&"tenant:admin".to_string()));
    }

    #[test]
    fn derivar_escopos_fallback_para_role_desconhecida_e_restrito() {
        let info = serde_json::json!({ "role": "atendente" });
        let (escopos, _) = derivar_escopos(false, &info);
        assert!(!escopos.contains(&"tenant:admin".to_string()));
        assert_eq!(
            escopos,
            vec![
                "atendimentos:read".to_string(),
                "atendimentos:write".to_string(),
                "clientes:write".to_string(),
            ]
        );
    }

    #[test]
    fn derivar_escopos_sem_role_nem_permissoes_usa_o_fallback_padrao() {
        let info = serde_json::json!({});
        let (escopos, _) = derivar_escopos(false, &info);
        assert_eq!(
            escopos,
            vec![
                "atendimentos:read".to_string(),
                "atendimentos:write".to_string(),
                "clientes:write".to_string(),
            ]
        );
    }

    // -- D4: instrumento e papel somente-leitura ----------------------------

    #[test]
    fn origem_declara_de_onde_vieram_os_escopos() {
        // O instrumento da D4: sem distinguir estas três origens não há como
        // medir quantas sessões dependem do fallback antes de fechá-lo.
        assert_eq!(
            derivar_escopos(true, &serde_json::json!({})).1,
            OrigemEscopos::Superusuario
        );
        assert_eq!(
            derivar_escopos(
                false,
                &serde_json::json!({ "module_permissions": ["atendimentos:read"] })
            )
            .1,
            OrigemEscopos::ModulePermissions
        );
        assert_eq!(
            derivar_escopos(false, &serde_json::json!({ "role": "admin" })).1,
            OrigemEscopos::FallbackRole
        );
    }

    #[test]
    fn origem_vira_rotulo_estavel_para_o_span() {
        // Os valores vão para o span de login e serão agregados em consulta;
        // mudá-los invalidaria a medição em curso.
        assert_eq!(OrigemEscopos::Superusuario.como_str(), "superusuario");
        assert_eq!(
            OrigemEscopos::ModulePermissions.como_str(),
            "module_permissions"
        );
        assert_eq!(OrigemEscopos::FallbackRole.como_str(), "fallback_role");
    }

    #[test]
    fn module_permissions_vazio_nao_conta_como_explicito() {
        // Um `[]` gravado por engano deixaria a sessão sem escopo nenhum, e o
        // usuário não abriria uma tela sequer. Cai no fallback e é CONTADO como
        // fallback — é justamente o caso que a migração precisa enxergar.
        let (escopos, origem) =
            derivar_escopos(false, &serde_json::json!({ "module_permissions": [] }));
        assert_eq!(origem, OrigemEscopos::FallbackRole);
        assert!(!escopos.is_empty());

        let (_, origem_obj) = derivar_escopos(
            false,
            &serde_json::json!({ "module_permissions": { "tenant:admin": false } }),
        );
        assert_eq!(origem_obj, OrigemEscopos::FallbackRole);
    }

    #[test]
    fn viewer_nao_escreve_em_lugar_nenhum() {
        // O papel `viewer` da v1, que a v2 não tinha como representar. Hoje
        // ninguém o tem — o arco existe para a migração poder atribuí-lo.
        let (escopos, _) = derivar_escopos(false, &serde_json::json!({ "role": "viewer" }));
        assert_eq!(escopos, vec!["atendimentos:read".to_string()]);
        assert!(!escopos.iter().any(|e| e.ends_with(":write")));
        assert!(!escopos.contains(&"tenant:admin".to_string()));
    }

    #[test]
    fn o_fallback_atual_ainda_da_escrita_a_quem_nao_e_admin() {
        // Este teste **documenta o problema**, não o comportamento desejado. Ele
        // deve falhar (e ser reescrito) no dia em que o passo 3 da D4 fechar o
        // fallback — é o alarme de que a mudança aconteceu de propósito.
        let (escopos, origem) = derivar_escopos(false, &serde_json::json!({ "role": "atendente" }));
        assert_eq!(origem, OrigemEscopos::FallbackRole);
        assert!(
            escopos.contains(&"atendimentos:write".to_string()),
            "se este assert quebrou, o fallback foi fechado: confirme que a \
             migração dos usuários existentes foi feita antes"
        );
    }

    // -- montar_envelope_request -------------------------------------------

    #[test]
    fn montar_envelope_request_preenche_campos_basicos_do_envelope() {
        let tenant_id = Uuid::now_v7();
        let payload = serde_json::json!({ "chave": "valor" });

        let envelope = montar_envelope_request(tenant_id, "trace-abc", "MinhaRpc", &payload);

        assert_eq!(envelope.tenant_id, tenant_id.to_string());
        assert_eq!(envelope.schema_version, 1);
        assert_eq!(envelope.traceparent, "trace-abc");
        assert_eq!(envelope.method, "MinhaRpc");
        assert_eq!(envelope.kind, MessageKind::Request as i32);
        assert!(envelope.error.is_none());
        assert_eq!(envelope.auth_user_id, 0);
        assert!(envelope.auth_scopes.is_empty());
        assert!(!envelope.auth_is_superuser);

        let payload_de_volta: serde_json::Value =
            serde_json::from_slice(&envelope.payload).unwrap();
        assert_eq!(payload_de_volta, payload);
    }

    #[test]
    fn montar_envelope_request_gera_message_id_unico_por_chamada() {
        let payload = serde_json::json!({});
        let e1 = montar_envelope_request(Uuid::nil(), "t", "M", &payload);
        let e2 = montar_envelope_request(Uuid::nil(), "t", "M", &payload);
        assert_ne!(e1.message_id, e2.message_id);
    }
}
