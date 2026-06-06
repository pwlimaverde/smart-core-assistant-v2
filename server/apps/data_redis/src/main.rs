//! Serviço data_redis: provê RPC síncrono para cache de configurações, permissões e tokens de autenticação.

use contracts::{Envelope, MessageKind};
use redis::aio::ConnectionManager;
use transport::Server;
use uuid::Uuid;

#[derive(Clone)]
struct AppState {
    redis_conn: ConnectionManager,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // 1. Inicializa observabilidade
    observability::init_telemetry("data_redis", "production")
        .map_err(|e| anyhow::anyhow!(e.to_string()))?;
    tracing::info!("Iniciando serviço data_redis...");

    // 2. Conecta ao Redis
    let redis_url =
        std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
    let redis_client = redis::Client::open(redis_url)?;
    let redis_conn = ConnectionManager::new(redis_client).await?;
    tracing::info!("Conexão com Redis estabelecida.");

    let state = AppState { redis_conn };

    // 3. Inicia o Servidor RPC síncrono nos 3 protocolos
    let state_clone = state.clone();
    let state_for_get = state_clone.clone();
    let state_for_set = state_clone.clone();
    let state_for_store = state_clone.clone();
    let state_for_validate = state_clone.clone();
    let state_for_revoke = state_clone.clone();
    let state_for_block = state_clone.clone();
    let state_for_is_blocked = state_clone;

    let server = Server::from_env("DATA_REDIS")
        .route("GetCache", move |env| {
            let state = state_for_get.clone();
            Box::pin(async move { handler_get_cache(state.redis_conn, env).await })
        })
        .route("SetCache", move |env| {
            let state = state_for_set.clone();
            Box::pin(async move { handler_set_cache(state.redis_conn, env).await })
        })
        .route("StoreRefreshToken", move |env| {
            let state = state_for_store.clone();
            Box::pin(async move { handler_store_refresh_token(state.redis_conn, env).await })
        })
        .route("ValidateAndRotate", move |env| {
            let state = state_for_validate.clone();
            Box::pin(async move { handler_validate_and_rotate(state.redis_conn, env).await })
        })
        .route("RevokeFamily", move |env| {
            let state = state_for_revoke.clone();
            Box::pin(async move { handler_revoke_family(state.redis_conn, env).await })
        })
        .route("BlockToken", move |env| {
            let state = state_for_block.clone();
            Box::pin(async move { handler_block_token(state.redis_conn, env).await })
        })
        .route("IsTokenBlocked", move |env| {
            let state = state_for_is_blocked.clone();
            Box::pin(async move { handler_is_token_blocked(state.redis_conn, env).await })
        });

    tracing::info!("Servidor RPC do data_redis configurado e pronto.");

    if let Err(e) = server.run().await {
        tracing::error!("Servidor RPC parou com erro crítico: {:?}", e);
    }

    Ok(())
}

async fn handler_get_cache(con: ConnectionManager, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(_) => serde_json::json!({}),
    };
    let user_id = payload_json
        .get("user_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;
    let tenant_id = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());

    let mut store = infrastructure_redis::CachePermissoes::new(con);
    match store.obter_flow_permissions(tenant_id, user_id).await {
        Ok(Some(val)) => {
            let res = serde_json::json!({ "permissions": val });
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "GetCacheReply".to_string(),
                payload: serde_json::to_vec(&res).unwrap_or_default(),
                error: None,
                ..env
            }
        }
        Ok(None) => {
            let app_err = error_core::AppError::Cache("Chave não encontrada no cache".to_string());
            let err_env = app_err.to_error_envelope(&env.traceparent, "data_redis");
            Envelope {
                kind: MessageKind::Error as i32,
                method: "GetCacheReply".to_string(),
                error: Some(err_env),
                ..env
            }
        }
        Err(e) => {
            let app_err = error_core::AppError::Cache(e.to_string());
            let err_env = app_err.to_error_envelope(&env.traceparent, "data_redis");
            Envelope {
                kind: MessageKind::Error as i32,
                method: "GetCacheReply".to_string(),
                error: Some(err_env),
                ..env
            }
        }
    }
}

async fn handler_set_cache(con: ConnectionManager, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(_) => serde_json::json!({}),
    };
    let user_id = payload_json
        .get("user_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;
    let permissions: Vec<i32> = payload_json
        .get("permissions")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|x| x.as_i64().map(|y| y as i32))
                .collect()
        })
        .unwrap_or_default();
    let ttl = payload_json
        .get("ttl")
        .and_then(|v| v.as_u64())
        .unwrap_or(60);
    let tenant_id = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());

    let mut store = infrastructure_redis::CachePermissoes::new(con);
    match store
        .definir_flow_permissions(tenant_id, user_id, &permissions, ttl)
        .await
    {
        Ok(_) => {
            let res = serde_json::json!({ "status": "success" });
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "SetCacheReply".to_string(),
                payload: serde_json::to_vec(&res).unwrap_or_default(),
                error: None,
                ..env
            }
        }
        Err(e) => {
            let app_err = error_core::AppError::Cache(e.to_string());
            let err_env = app_err.to_error_envelope(&env.traceparent, "data_redis");
            Envelope {
                kind: MessageKind::Error as i32,
                method: "SetCacheReply".to_string(),
                error: Some(err_env),
                ..env
            }
        }
    }
}

async fn handler_store_refresh_token(con: ConnectionManager, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(_) => serde_json::json!({}),
    };
    let token_hash = payload_json
        .get("token_hash")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let user_id = payload_json
        .get("user_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;
    let tenant_id = Uuid::parse_str(&env.tenant_id).ok();
    let family_id = payload_json
        .get("family_id")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let ttl = payload_json
        .get("ttl")
        .and_then(|v| v.as_u64())
        .unwrap_or(86400);

    let mut store = infrastructure_redis::RefreshTokenStore::new(con);
    match store
        .armazenar(token_hash, user_id, tenant_id, family_id, ttl)
        .await
    {
        Ok(_) => {
            let res = serde_json::json!({ "status": "success" });
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "StoreRefreshTokenReply".to_string(),
                payload: serde_json::to_vec(&res).unwrap_or_default(),
                error: None,
                ..env
            }
        }
        Err(e) => {
            let app_err = error_core::AppError::Cache(e.to_string());
            let err_env = app_err.to_error_envelope(&env.traceparent, "data_redis");
            Envelope {
                kind: MessageKind::Error as i32,
                method: "StoreRefreshTokenReply".to_string(),
                error: Some(err_env),
                ..env
            }
        }
    }
}

async fn handler_validate_and_rotate(con: ConnectionManager, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(_) => serde_json::json!({}),
    };
    let token_hash = payload_json
        .get("token_hash")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    let mut store = infrastructure_redis::RefreshTokenStore::new(con);
    match store.validar_e_rotacionar(token_hash).await {
        Ok(reg) => {
            let res = serde_json::to_value(&reg).unwrap_or_default();
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "ValidateAndRotateReply".to_string(),
                payload: serde_json::to_vec(&res).unwrap_or_default(),
                error: None,
                ..env
            }
        }
        Err(e) => {
            let app_err = error_core::AppError::Cache(e.to_string());
            let err_env = app_err.to_error_envelope(&env.traceparent, "data_redis");
            Envelope {
                kind: MessageKind::Error as i32,
                method: "ValidateAndRotateReply".to_string(),
                error: Some(err_env),
                ..env
            }
        }
    }
}

async fn handler_revoke_family(con: ConnectionManager, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(_) => serde_json::json!({}),
    };
    let family_id = payload_json
        .get("family_id")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    let mut store = infrastructure_redis::RefreshTokenStore::new(con);
    match store.revogar_familia(family_id).await {
        Ok(_) => {
            let res = serde_json::json!({ "status": "success" });
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "RevokeFamilyReply".to_string(),
                payload: serde_json::to_vec(&res).unwrap_or_default(),
                error: None,
                ..env
            }
        }
        Err(e) => {
            let app_err = error_core::AppError::Cache(e.to_string());
            let err_env = app_err.to_error_envelope(&env.traceparent, "data_redis");
            Envelope {
                kind: MessageKind::Error as i32,
                method: "RevokeFamilyReply".to_string(),
                error: Some(err_env),
                ..env
            }
        }
    }
}

async fn handler_block_token(con: ConnectionManager, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(_) => serde_json::json!({}),
    };
    let jti = payload_json
        .get("jti")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let ttl = payload_json
        .get("ttl")
        .and_then(|v| v.as_u64())
        .unwrap_or(3600);

    let mut blocklist = infrastructure_redis::TokenBlocklist::new(con);
    match blocklist.bloquear(jti, ttl).await {
        Ok(_) => {
            let res = serde_json::json!({ "status": "success" });
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "BlockTokenReply".to_string(),
                payload: serde_json::to_vec(&res).unwrap_or_default(),
                error: None,
                ..env
            }
        }
        Err(e) => {
            let app_err = error_core::AppError::Cache(e.to_string());
            let err_env = app_err.to_error_envelope(&env.traceparent, "data_redis");
            Envelope {
                kind: MessageKind::Error as i32,
                method: "BlockTokenReply".to_string(),
                error: Some(err_env),
                ..env
            }
        }
    }
}

async fn handler_is_token_blocked(con: ConnectionManager, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(_) => serde_json::json!({}),
    };
    let jti = payload_json
        .get("jti")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    let mut blocklist = infrastructure_redis::TokenBlocklist::new(con);
    match blocklist.esta_bloqueado(jti).await {
        Ok(blocked) => {
            let res = serde_json::json!({ "blocked": blocked });
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "IsTokenBlockedReply".to_string(),
                payload: serde_json::to_vec(&res).unwrap_or_default(),
                error: None,
                ..env
            }
        }
        Err(e) => {
            let app_err = error_core::AppError::Cache(e.to_string());
            let err_env = app_err.to_error_envelope(&env.traceparent, "data_redis");
            Envelope {
                kind: MessageKind::Error as i32,
                method: "IsTokenBlockedReply".to_string(),
                error: Some(err_env),
                ..env
            }
        }
    }
}
