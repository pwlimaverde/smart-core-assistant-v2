// application/src/auth/logout.rs (comentários em pt-br)
use contracts::MessageKind;
use error_core::AppError;
use std::time::Duration;
use uuid::Uuid;

use crate::auth::login::montar_envelope_request;
use crate::jwt::Claims;
use crate::tokens::hash_refresh_token;

/// Executa o fluxo de logout de forma a revogar a sessão atual.
///
/// Invalida a família de refresh tokens correspondente no Redis e adiciona
/// o `jti` do token de acesso atual na blocklist pelo tempo de vida restante.
pub async fn logout(
    deps: &crate::auth::login::AuthDeps,
    traceparent: &str,
    claims: &Claims,
    refresh_token: Option<&str>,
) -> Result<serde_json::Value, AppError> {
    // 1. Se fornecido o refresh token, invalida a família inteira
    if let Some(token) = refresh_token {
        let hash = hash_refresh_token(token);

        // Chama ValidateAndRotate para obter o family_id daquele refresh
        let val_payload = serde_json::json!({
            "token_hash": hash,
        });
        let val_req =
            montar_envelope_request(Uuid::nil(), traceparent, "ValidateAndRotate", &val_payload);

        if let Ok(val_resp) = deps.redis.call(val_req, Duration::from_secs(3)).await {
            if val_resp.kind == MessageKind::Reply as i32 {
                if let Ok(reg) = serde_json::from_slice::<serde_json::Value>(&val_resp.payload) {
                    if let Some(family_id) = reg.get("family_id").and_then(|v| v.as_str()) {
                        // Revoga todos os tokens da família
                        let revoke_payload = serde_json::json!({
                            "family_id": family_id,
                        });
                        let revoke_req = montar_envelope_request(
                            Uuid::nil(),
                            traceparent,
                            "RevokeFamily",
                            &revoke_payload,
                        );
                        let _ = deps.redis.call(revoke_req, Duration::from_secs(3)).await;
                    }
                }
            }
        }
    }

    // 2. Coloca o jti do access token na blocklist
    let agora = chrono::Utc::now().timestamp() as usize;
    let ttl = if claims.exp > agora {
        (claims.exp - agora) as u64
    } else {
        1 // Já expirado, expira em 1s no Redis
    };

    let block_payload = serde_json::json!({
        "jti": claims.jti,
        "ttl": ttl,
    });
    let block_req = montar_envelope_request(Uuid::nil(), traceparent, "BlockToken", &block_payload);

    let block_resp = deps
        .redis
        .call(block_req, Duration::from_secs(5))
        .await
        .map_err(|e| AppError::Cache(format!("RPC BlockToken falhou: {:?}", e)))?;

    if block_resp.kind == MessageKind::Error as i32 {
        return Err(block_resp
            .error
            .map(|e| AppError::from_envelope(&e))
            .unwrap_or_else(|| AppError::Cache("falha ao bloquear token".to_string())));
    }

    Ok(serde_json::json!({
        "status": "success",
    }))
}
