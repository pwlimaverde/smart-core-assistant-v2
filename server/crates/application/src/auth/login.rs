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
    }
}

/// Realiza o login real do usuário validando as credenciais no Postgres
/// e persistindo a sessão (refresh token) no Redis.
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

    Ok(serde_json::json!({
        "access_token": access_token,
        "refresh_token": refresh_token,
        "expires_in": deps.access_ttl_s,
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
