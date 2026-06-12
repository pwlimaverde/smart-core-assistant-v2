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
            // Reuso de token rotacionado é uma falha de autenticação (possível roubo de sessão),
            // não um simples miss de cache. Mapeamos para AppError::Auth com marcador estável
            // ("token_reuse_detected") para que a runtime_api possa auditar o evento de segurança.
            let app_err = match e {
                infrastructure_redis::RedisError::TokenReuse => {
                    error_core::AppError::Auth("token_reuse_detected".to_string())
                }
                outro => error_core::AppError::Cache(outro.to_string()),
            };
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

#[cfg(test)]
mod tests {
    use super::*;
    use contracts::{Envelope, MessageKind};
    use redis::aio::ConnectionManager;
    use uuid::Uuid;

    fn carregar_env_teste() {
        test_support::ensure_tunnel();
        let caminhos = vec![
            ".env",
            "../.env",
            "../../.env",
            "apps/data_redis/.env",
            "../data_redis/.env",
        ];
        for caminho in caminhos {
            if let Ok(conteudo) = std::fs::read_to_string(caminho) {
                for linha in conteudo.lines() {
                    let linha_limpa = linha.trim();
                    if linha_limpa.is_empty() || linha_limpa.starts_with('#') {
                        continue;
                    }
                    if let Some((chave, valor)) = linha_limpa.split_once('=') {
                        let chave = chave.trim();
                        let valor = valor.trim().trim_matches('"').trim_matches('\'');
                        if std::env::var(chave).is_err() {
                            std::env::set_var(chave, valor);
                        }
                    }
                }
                break;
            }
        }
    }

    async fn setup_redis() -> ConnectionManager {
        carregar_env_teste();
        let redis_url =
            std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6380".to_string());
        let redis_client = redis::Client::open(redis_url).unwrap();
        ConnectionManager::new(redis_client).await.unwrap()
    }

    #[tokio::test]
    async fn test_handler_cache_permissions() {
        let con = setup_redis().await;

        let tenant_id = Uuid::new_v4();
        let user_id = 12345;
        let permissions = vec![1, 2, 3];

        // 1. Define o cache via handler_set_cache
        let set_payload = serde_json::json!({
            "user_id": user_id,
            "permissions": permissions,
            "ttl": 60
        });

        let set_req = Envelope {
            tenant_id: tenant_id.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: "".to_string(),
            traceparent: "00-trace-redis1-01".to_string(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "SetCache".to_string(),
            payload: serde_json::to_vec(&set_payload).unwrap(),
            error: None,
            ..Default::default()
        };

        let set_resp = handler_set_cache(con.clone(), set_req).await;
        assert_eq!(set_resp.kind, MessageKind::Reply as i32);

        // 2. Obtém do cache via handler_get_cache
        let get_payload = serde_json::json!({
            "user_id": user_id
        });

        let get_req = Envelope {
            tenant_id: tenant_id.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: "".to_string(),
            traceparent: "00-trace-redis1-01".to_string(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "GetCache".to_string(),
            payload: serde_json::to_vec(&get_payload).unwrap(),
            error: None,
            ..Default::default()
        };

        let get_resp = handler_get_cache(con.clone(), get_req).await;
        assert_eq!(get_resp.kind, MessageKind::Reply as i32);

        let get_resp_payload: serde_json::Value =
            serde_json::from_slice(&get_resp.payload).unwrap();
        let perms: Vec<i32> = get_resp_payload
            .get("permissions")
            .unwrap()
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v.as_i64().unwrap() as i32)
            .collect();
        assert_eq!(perms, permissions);
    }

    #[tokio::test]
    async fn test_handler_refresh_token_flow() {
        let con = setup_redis().await;

        let tenant_id = Uuid::new_v4();
        let token_hash = format!("hash_{}", Uuid::new_v4());
        let user_id = 999;
        let family_id = Uuid::new_v4().to_string();

        // 1. Armazena o Refresh Token
        let store_payload = serde_json::json!({
            "token_hash": &token_hash,
            "user_id": user_id,
            "family_id": &family_id,
            "ttl": 120
        });

        let store_req = Envelope {
            tenant_id: tenant_id.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: "".to_string(),
            traceparent: "00-trace-redis2-01".to_string(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "StoreRefreshToken".to_string(),
            payload: serde_json::to_vec(&store_payload).unwrap(),
            error: None,
            ..Default::default()
        };

        let store_resp = handler_store_refresh_token(con.clone(), store_req).await;
        assert_eq!(store_resp.kind, MessageKind::Reply as i32);

        // 2. Valida e Rotaciona o Token
        let val_payload = serde_json::json!({
            "token_hash": &token_hash
        });

        let val_req = Envelope {
            tenant_id: tenant_id.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: "".to_string(),
            traceparent: "00-trace-redis2-01".to_string(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "ValidateAndRotate".to_string(),
            payload: serde_json::to_vec(&val_payload).unwrap(),
            error: None,
            ..Default::default()
        };

        let val_resp = handler_validate_and_rotate(con.clone(), val_req).await;
        assert_eq!(val_resp.kind, MessageKind::Reply as i32);

        let val_resp_payload: serde_json::Value =
            serde_json::from_slice(&val_resp.payload).unwrap();
        assert_eq!(
            val_resp_payload.get("user_id").unwrap().as_i64().unwrap() as i32,
            user_id
        );
        assert_eq!(
            val_resp_payload.get("family_id").unwrap().as_str().unwrap(),
            family_id
        );

        // 3. Revoga a Família de Tokens
        let revoke_payload = serde_json::json!({
            "family_id": &family_id
        });

        let revoke_req = Envelope {
            tenant_id: tenant_id.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: "".to_string(),
            traceparent: "00-trace-redis2-01".to_string(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "RevokeFamily".to_string(),
            payload: serde_json::to_vec(&revoke_payload).unwrap(),
            error: None,
            ..Default::default()
        };

        let revoke_resp = handler_revoke_family(con.clone(), revoke_req).await;
        assert_eq!(revoke_resp.kind, MessageKind::Reply as i32);
    }

    #[tokio::test]
    async fn test_handler_token_blocklist() {
        let con = setup_redis().await;

        let tenant_id = Uuid::new_v4();
        let jti = Uuid::new_v4().to_string();

        // 1. Verifica se não está bloqueado inicialmente
        let check_payload = serde_json::json!({
            "jti": &jti
        });

        let check_req = Envelope {
            tenant_id: tenant_id.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: "".to_string(),
            traceparent: "00-trace-redis3-01".to_string(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "IsTokenBlocked".to_string(),
            payload: serde_json::to_vec(&check_payload).unwrap(),
            error: None,
            ..Default::default()
        };

        let check_resp = handler_is_token_blocked(con.clone(), check_req.clone()).await;
        assert_eq!(check_resp.kind, MessageKind::Reply as i32);
        let check_resp_payload: serde_json::Value =
            serde_json::from_slice(&check_resp.payload).unwrap();
        assert!(!check_resp_payload
            .get("blocked")
            .unwrap()
            .as_bool()
            .unwrap());

        // 2. Bloqueia o token
        let block_payload = serde_json::json!({
            "jti": &jti,
            "ttl": 120
        });

        let block_req = Envelope {
            tenant_id: tenant_id.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: "".to_string(),
            traceparent: "00-trace-redis3-01".to_string(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "BlockToken".to_string(),
            payload: serde_json::to_vec(&block_payload).unwrap(),
            error: None,
            ..Default::default()
        };

        let block_resp = handler_block_token(con.clone(), block_req).await;
        assert_eq!(block_resp.kind, MessageKind::Reply as i32);

        // 3. Verifica se agora está bloqueado
        let check_resp2 = handler_is_token_blocked(con.clone(), check_req).await;
        assert_eq!(check_resp2.kind, MessageKind::Reply as i32);
        let check_resp_payload2: serde_json::Value =
            serde_json::from_slice(&check_resp2.payload).unwrap();
        assert!(check_resp_payload2
            .get("blocked")
            .unwrap()
            .as_bool()
            .unwrap());
    }
}
