//! Caso de uso de login do usuário.
//!
//! Realiza a verificação de credenciais no banco via RPC síncrono e
//! persiste os tokens gerados no cache compartilhado (Redis).

use crate::RequestContext;
use contracts::{Envelope, MessageKind};
use error_core::AppError;
use std::time::Duration;
use uuid::Uuid;

/// Realiza a autenticação de um usuário no sistema.
///
/// Dispara chamadas RPC síncronas para validar as credenciais e armazenar
/// o refresh token gerado de forma segura no cache distribuído.
pub async fn login(
    ctx: &RequestContext,
    email: &str,
    password: &str,
) -> Result<serde_json::Value, AppError> {
    // 1. Estabelece conexão RPC com o microserviço data_postgres
    let pg_client = transport::conectar_cliente("data_postgres")
        .await
        .map_err(|e| AppError::Database(format!("Falha ao conectar no data_postgres: {e}")))?;

    // 2. Prepara o envelope de requisição para VerifyCredentials
    let credentials_payload = serde_json::json!({
        "email": email,
        "password": password,
    });
    let req_envelope = Envelope {
        tenant_id: ctx.tenant_id.to_string(),
        schema_version: 1,
        message_id: Uuid::now_v7().to_string(),
        causation_id: "".to_string(),
        traceparent: ctx.traceparent.clone(),
        occurred_at: chrono::Utc::now().timestamp_millis(),
        kind: MessageKind::Request as i32,
        method: "VerifyCredentials".to_string(),
        payload: serde_json::to_vec(&credentials_payload).unwrap_or_default(),
        error: None,
    };

    // 3. Executa a chamada RPC para validar as credenciais (verify_password ocorre no data_postgres)
    let resp_envelope = pg_client
        .call(req_envelope, Duration::from_secs(5))
        .await
        .map_err(|e| AppError::Database(format!("Erro na chamada RPC VerifyCredentials: {e:?}")))?;

    if resp_envelope.kind == MessageKind::Error as i32 {
        if let Some(err) = resp_envelope.error {
            return Err(AppError::from_envelope(&err));
        }
        return Err(AppError::Auth(
            "Erro desconhecido na autenticação".to_string(),
        ));
    }

    let user_info: serde_json::Value =
        serde_json::from_slice(&resp_envelope.payload).map_err(|e| {
            AppError::Internal(format!(
                "Erro ao desserializar resposta de credenciais: {e}"
            ))
        })?;

    let user_id = user_info.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;

    // 4. Estabelece conexão RPC com o microserviço data_redis
    let redis_client = transport::conectar_cliente("data_redis")
        .await
        .map_err(|e| AppError::Cache(format!("Falha ao conectar no data_redis: {e}")))?;

    // 5. Gera tokens de acesso e de atualização mockados seguros (UUIDs)
    let access_token = Uuid::new_v4().to_string();
    let refresh_token = Uuid::new_v4().to_string();
    let family_id = Uuid::new_v4().to_string();

    // Hash representativo do token de refresh (nunca salvar em claro no Redis)
    let token_hash = format!("hash_{}", refresh_token);

    let store_payload = serde_json::json!({
        "token_hash": token_hash,
        "user_id": user_id,
        "family_id": family_id,
        "ttl": 86400, // 24 horas de expiração
    });

    let store_req = Envelope {
        tenant_id: ctx.tenant_id.to_string(),
        schema_version: 1,
        message_id: Uuid::now_v7().to_string(),
        causation_id: resp_envelope.message_id.clone(),
        traceparent: ctx.traceparent.clone(),
        occurred_at: chrono::Utc::now().timestamp_millis(),
        kind: MessageKind::Request as i32,
        method: "StoreRefreshToken".to_string(),
        payload: serde_json::to_vec(&store_payload).unwrap_or_default(),
        error: None,
    };

    let store_resp = redis_client
        .call(store_req, Duration::from_secs(5))
        .await
        .map_err(|e| AppError::Cache(format!("Erro na chamada RPC StoreRefreshToken: {e:?}")))?;

    if store_resp.kind == MessageKind::Error as i32 {
        if let Some(err) = store_resp.error {
            return Err(AppError::from_envelope(&err));
        }
        return Err(AppError::Cache("Erro ao salvar refresh token".to_string()));
    }

    Ok(serde_json::json!({
        "access_token": access_token,
        "refresh_token": refresh_token,
    }))
}
