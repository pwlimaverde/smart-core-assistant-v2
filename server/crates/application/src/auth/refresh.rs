// application/src/auth/refresh.rs (comentários em pt-br)
use contracts::MessageKind;
use error_core::AppError;
use std::time::Duration;
use uuid::Uuid;

use crate::auth::login::montar_envelope_request;
use crate::jwt::{self, Claims};
use crate::tokens::{gerar_refresh_token, hash_refresh_token};

/// Marcador estável usado entre data_redis -> application -> runtime_api para sinalizar
/// reuso de refresh token rotacionado (possível roubo de sessão). A runtime_api detecta
/// este marcador e publica o evento de segurança `token_reuse_detected`.
pub const REUSE_MARKER: &str = "token_reuse_detected";

/// Realiza a rotação do token de refresh (Refresh Token Rotation).
/// Valida o token atual no Redis, invalida-o, gera um novo par (access + refresh)
/// mantendo a mesma família de rotação e prevenindo ataques de replay.
pub async fn refresh(
    deps: &crate::auth::login::AuthDeps,
    traceparent: &str,
    refresh_token: &str,
) -> Result<serde_json::Value, AppError> {
    // 1. Gerar hash do refresh token fornecido pelo cliente
    let refresh_hash = hash_refresh_token(refresh_token);

    // 2. Chamar a RPC ValidateAndRotate no data_redis
    let val_payload = serde_json::json!({
        "token_hash": refresh_hash,
    });

    // Rotação de token é tratada no escopo global (Uuid::nil())
    let val_req =
        montar_envelope_request(Uuid::nil(), traceparent, "ValidateAndRotate", &val_payload);

    let val_resp = deps
        .redis
        .call(val_req, Duration::from_secs(5))
        .await
        .map_err(|e| AppError::Cache(format!("RPC ValidateAndRotate falhou: {:?}", e)))?;

    if val_resp.kind == MessageKind::Error as i32 {
        // O data_redis sinaliza reuso de refresh rotacionado com o marcador estável
        // "token_reuse_detected" (AppError::Auth). A runtime_api detecta esse marcador
        // e publica o evento de segurança `token_reuse_detected` no security:stream.
        if let Some(ref e) = val_resp.error {
            if e.message.contains(REUSE_MARKER) {
                return Err(AppError::Auth(REUSE_MARKER.to_string()));
            }
        }
        let err = val_resp
            .error
            .map(|e| AppError::from_envelope(&e))
            .unwrap_or_else(|| AppError::Auth("sessão expirada ou inválida".to_string()));
        return Err(err);
    }

    let reg_refresh: serde_json::Value =
        serde_json::from_slice(&val_resp.payload).map_err(|e| {
            AppError::Internal(format!("erro ao desserializar registro do refresh: {e}"))
        })?;

    let user_id = reg_refresh
        .get("user_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;
    let tenant_str = reg_refresh
        .get("tenant_id")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    // O tenant nil (Uuid::nil) é o marcador de contexto global do superusuário (foi assim
    // que o login persistiu o refresh). Tratamos nil/vazio como "sem tenant" para não
    // emitir um JWT com tenant_id falso para superusuários.
    let tenant_opt = Uuid::parse_str(tenant_str).ok().filter(|u| !u.is_nil());
    let family_id = reg_refresh
        .get("family_id")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    // Como os escopos precisam vir do usuário ativo, fazemos um lookup no data_postgres
    // buscando as informações do usuário atualizado (evita emitir JWT novo para usuário
    // inativo/removido ou com permissões alteradas).
    let user_req_payload = serde_json::json!({ "id": user_id });
    let user_req = montar_envelope_request(
        tenant_opt.unwrap_or_else(Uuid::nil),
        traceparent,
        "GetUserIdentity",
        &user_req_payload,
    );

    // Busca informações de escopo/permissão do usuário
    let verify_resp = deps
        .pg
        .call(user_req, Duration::from_secs(5))
        .await
        .map_err(|e| {
            AppError::Database(format!(
                "falha ao resolver identidade para refresh: {:?}",
                e
            ))
        })?;

    // Falha fechada: sem identidade autoritativa (ex.: usuário removido) não se emite
    // token novo — jamais conceder escopos de fallback a uma sessão não confirmada.
    if verify_resp.kind != MessageKind::Reply as i32 {
        return Err(AppError::Auth("sessão inválida".to_string()));
    }
    let user_info: serde_json::Value = serde_json::from_slice(&verify_resp.payload)
        .map_err(|e| AppError::Internal(format!("erro ao desserializar identidade: {e}")))?;

    // Se o usuário foi desativado no meio tempo, bloquear a rotação (default fechado).
    let is_active = user_info
        .get("is_active")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    if !is_active {
        return Err(AppError::Auth("usuário desativado".to_string()));
    }

    // Fonte da verdade sobre superusuário é a identidade, não o tenant do refresh.
    let is_superuser = user_info
        .get("is_superuser")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    // Espelha a regra do login: usuário comum sem tenant associado não recebe token.
    if !is_superuser && tenant_opt.is_none() {
        return Err(AppError::Auth("usuário sem tenant associado".to_string()));
    }

    let scopes = derivar_escopos_refresh(is_superuser, &user_info);

    // 3. Gerar novo par de tokens
    let agora = chrono::Utc::now().timestamp() as usize;
    let new_jti = Uuid::now_v7().to_string();

    let claims = Claims {
        sub: user_id.to_string(),
        tenant_id: tenant_opt.map(|t| t.to_string()).unwrap_or_default(),
        scopes,
        is_superuser,
        jti: new_jti,
        iat: agora,
        exp: agora + deps.access_ttl_s as usize,
    };

    let access_token = jwt::gerar_access_token(&claims)?;
    let new_refresh_token = gerar_refresh_token();
    let new_refresh_hash = hash_refresh_token(&new_refresh_token);

    // 4. Salvar o novo refresh token na mesma família e com o mesmo TTL remanescente
    let store_payload = serde_json::json!({
        "token_hash": new_refresh_hash,
        "user_id": user_id,
        "family_id": family_id,
        "ttl": deps.refresh_ttl_s,
    });

    let store_req = montar_envelope_request(
        tenant_opt.unwrap_or_else(Uuid::nil),
        traceparent,
        "StoreRefreshToken",
        &store_payload,
    );

    let store_resp = deps
        .redis
        .call(store_req, Duration::from_secs(5))
        .await
        .map_err(|e| {
            AppError::Cache(format!("RPC StoreRefreshToken falhou no refresh: {:?}", e))
        })?;

    if store_resp.kind == MessageKind::Error as i32 {
        return Err(store_resp
            .error
            .map(|e| AppError::from_envelope(&e))
            .unwrap_or_else(|| AppError::Cache("falha ao salvar novo refresh token".to_string())));
    }

    Ok(serde_json::json!({
        "access_token": access_token,
        "refresh_token": new_refresh_token,
        "expires_in": deps.access_ttl_s,
    }))
}

/// Helper local para derivar escopos no refresh.
fn derivar_escopos_refresh(is_superuser: bool, user_info: &serde_json::Value) -> Vec<String> {
    if is_superuser {
        return vec!["*".to_string()];
    }
    if let Some(perms) = user_info.get("module_permissions") {
        if let Some(arr) = perms.as_array() {
            return arr
                .iter()
                .filter_map(|v| v.as_str().map(|s| s.to_string()))
                .collect();
        }
    }
    vec!["atendimentos:read".into(), "clientes:write".into()]
}
