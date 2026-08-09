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

    let user_id = user_info.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
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

    // 3. Montar as claims e gerar o access token (JWT)
    let agora = chrono::Utc::now().timestamp() as usize;
    let jti = Uuid::now_v7().to_string();
    let family_id = Uuid::now_v7().to_string();
    let scopes = derivar_escopos(is_superuser, &user_info);

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
fn derivar_escopos(is_superuser: bool, user_info: &serde_json::Value) -> Vec<String> {
    if is_superuser {
        // Superusuário possui acesso administrativo global.
        return vec!["*".to_string()];
    }

    // Tenta obter permissões explícitas em module_permissions
    if let Some(perms) = user_info.get("module_permissions") {
        if let Some(arr) = perms.as_array() {
            return arr
                .iter()
                .filter_map(|v| v.as_str().map(|s| s.to_string()))
                .collect();
        }
        if let Some(obj) = perms.as_object() {
            return obj
                .iter()
                .filter(|(_, v)| v.as_bool().unwrap_or(false))
                .map(|(k, _)| k.clone())
                .collect();
        }
    }

    // Fallback com base no cargo (role) do usuário no tenant
    let role = user_info
        .get("role")
        .and_then(|v| v.as_str())
        .unwrap_or("atendente");
    match role {
        "admin" | "owner" => vec![
            "atendimentos:read".into(),
            "atendimentos:write".into(),
            "clientes:write".into(),
            "tenant:admin".into(),
        ],
        _ => vec![
            "atendimentos:read".into(),
            "atendimentos:write".into(),
            "clientes:write".into(),
        ],
    }
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
        assert_eq!(derivar_escopos(true, &info), vec!["*".to_string()]);
    }

    #[test]
    fn derivar_escopos_usa_module_permissions_quando_e_array() {
        let info = serde_json::json!({
            "module_permissions": ["atendimentos:read", "clientes:write"],
        });
        assert_eq!(
            derivar_escopos(false, &info),
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
        let mut escopos = derivar_escopos(false, &info);
        escopos.sort();
        assert_eq!(
            escopos,
            vec!["atendimentos:read".to_string(), "tenant:admin".to_string()]
        );
    }

    #[test]
    fn derivar_escopos_fallback_para_admin_inclui_tenant_admin() {
        let info = serde_json::json!({ "role": "admin" });
        let escopos = derivar_escopos(false, &info);
        assert!(escopos.contains(&"tenant:admin".to_string()));
    }

    #[test]
    fn derivar_escopos_fallback_para_owner_inclui_tenant_admin() {
        let info = serde_json::json!({ "role": "owner" });
        let escopos = derivar_escopos(false, &info);
        assert!(escopos.contains(&"tenant:admin".to_string()));
    }

    #[test]
    fn derivar_escopos_fallback_para_role_desconhecida_e_restrito() {
        let info = serde_json::json!({ "role": "atendente" });
        let escopos = derivar_escopos(false, &info);
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
        let escopos = derivar_escopos(false, &info);
        assert_eq!(
            escopos,
            vec![
                "atendimentos:read".to_string(),
                "atendimentos:write".to_string(),
                "clientes:write".to_string(),
            ]
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
