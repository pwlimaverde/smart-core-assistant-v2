//! Serviço data_redis: provê RPC síncrono para cache de configurações, permissões e
//! tokens de autenticação. Aplica Ports & Adapters (ISP): os handlers dependem apenas
//! de traits por capacidade (cache, refresh token, blocklist, rate limiter); os
//! adapters concretos encapsulam o acesso ao Redis.

use contracts::{Envelope, MessageKind};
use redis::aio::ConnectionManager;
use uuid::Uuid;

mod adapters;
mod ports;

/// Monta um Envelope de Reply com o payload serializado.
fn ok_reply(env: &Envelope, method: &str, payload: serde_json::Value) -> Envelope {
    Envelope {
        kind: MessageKind::Reply as i32,
        method: method.to_string(),
        payload: serde_json::to_vec(&payload).unwrap_or_default(),
        error: None,
        ..env.clone()
    }
}

/// Monta um Envelope de erro a partir de um AppError, preservando o método de resposta.
fn erro(env: &Envelope, method: &str, app_err: error_core::AppError) -> Envelope {
    let err_env = app_err.to_error_envelope(&env.traceparent, "data_redis");
    Envelope {
        kind: MessageKind::Error as i32,
        method: method.to_string(),
        error: Some(err_env),
        ..env.clone()
    }
}

#[derive(Clone)]
struct AppState {
    cache: std::sync::Arc<dyn ports::CacheStore>,
    refresh_token: std::sync::Arc<dyn ports::RefreshTokenPort>,
    blocklist: std::sync::Arc<dyn ports::TokenBlocklist>,
    rate_limiter: std::sync::Arc<dyn ports::LoginRateLimiter>,
    rate_limiter_generico: std::sync::Arc<dyn ports::RateLimiter>,
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

    // 3. Injeta as ports (DIP): adapters concretos encapsulam o ConnectionManager.
    let cache: std::sync::Arc<dyn ports::CacheStore> =
        std::sync::Arc::new(adapters::RedisCacheStore::new(redis_conn.clone()));
    let refresh_token: std::sync::Arc<dyn ports::RefreshTokenPort> =
        std::sync::Arc::new(adapters::RedisRefreshTokenStore::new(redis_conn.clone()));
    let blocklist: std::sync::Arc<dyn ports::TokenBlocklist> =
        std::sync::Arc::new(adapters::RedisTokenBlocklist::new(redis_conn.clone()));
    let rate_limiter: std::sync::Arc<dyn ports::LoginRateLimiter> =
        std::sync::Arc::new(adapters::RedisLoginRateLimiter::new(redis_conn.clone()));
    let rate_limiter_generico: std::sync::Arc<dyn ports::RateLimiter> =
        std::sync::Arc::new(adapters::RedisRateLimiter::new(redis_conn.clone()));

    let state = AppState {
        cache,
        refresh_token,
        blocklist,
        rate_limiter,
        rate_limiter_generico,
    };

    // 4. Inicia o Servidor RPC síncrono nos 3 protocolos
    let state_clone = state.clone();
    let state_for_get = state_clone.clone();
    let state_for_set = state_clone.clone();
    let state_for_store = state_clone.clone();
    let state_for_validate = state_clone.clone();
    let state_for_revoke = state_clone.clone();
    let state_for_block = state_clone.clone();
    let state_for_is_blocked = state_clone.clone();
    let state_for_login_attempt = state_clone.clone();
    let state_for_rate_limit_attempt = state_clone;

    let server = transport::Server::from_env("DATA_REDIS")
        .route("GetCache", move |env| {
            let state = state_for_get.clone();
            Box::pin(async move { handler_get_cache(state.cache.as_ref(), env).await })
        })
        .route("SetCache", move |env| {
            let state = state_for_set.clone();
            Box::pin(async move { handler_set_cache(state.cache.as_ref(), env).await })
        })
        .route("StoreRefreshToken", move |env| {
            let state = state_for_store.clone();
            Box::pin(
                async move { handler_store_refresh_token(state.refresh_token.as_ref(), env).await },
            )
        })
        .route("ValidateAndRotate", move |env| {
            let state = state_for_validate.clone();
            Box::pin(
                async move { handler_validate_and_rotate(state.refresh_token.as_ref(), env).await },
            )
        })
        .route("RevokeFamily", move |env| {
            let state = state_for_revoke.clone();
            Box::pin(async move { handler_revoke_family(state.refresh_token.as_ref(), env).await })
        })
        .route("BlockToken", move |env| {
            let state = state_for_block.clone();
            Box::pin(async move { handler_block_token(state.blocklist.as_ref(), env).await })
        })
        .route("IsTokenBlocked", move |env| {
            let state = state_for_is_blocked.clone();
            Box::pin(async move { handler_is_token_blocked(state.blocklist.as_ref(), env).await })
        })
        .route("RegisterLoginAttempt", move |env| {
            let state = state_for_login_attempt.clone();
            Box::pin(async move {
                handler_register_login_attempt(state.rate_limiter.as_ref(), env).await
            })
        })
        .route("RegisterRateLimitAttempt", move |env| {
            let state = state_for_rate_limit_attempt.clone();
            Box::pin(async move {
                handler_register_rate_limit_attempt(state.rate_limiter_generico.as_ref(), env).await
            })
        });

    tracing::info!("Servidor RPC do data_redis configurado e pronto.");

    if let Err(e) = server.run().await {
        tracing::error!("Servidor RPC parou com erro crítico: {:?}", e);
    }

    Ok(())
}

async fn handler_get_cache(cache: &dyn ports::CacheStore, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let user_id = payload_json
        .get("user_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;
    let tenant_id = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());

    match cache.get_flow_permissions(tenant_id, user_id).await {
        Ok(Some(val)) => ok_reply(
            &env,
            "GetCacheReply",
            serde_json::json!({ "permissions": val }),
        ),
        Ok(None) => erro(
            &env,
            "GetCacheReply",
            error_core::AppError::Cache("Chave não encontrada no cache".to_string()),
        ),
        Err(e) => erro(
            &env,
            "GetCacheReply",
            error_core::AppError::Cache(e.to_string()),
        ),
    }
}

async fn handler_set_cache(cache: &dyn ports::CacheStore, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
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

    match cache
        .set_flow_permissions(tenant_id, user_id, permissions, ttl)
        .await
    {
        Ok(()) => ok_reply(
            &env,
            "SetCacheReply",
            serde_json::json!({ "status": "success" }),
        ),
        Err(e) => erro(
            &env,
            "SetCacheReply",
            error_core::AppError::Cache(e.to_string()),
        ),
    }
}

async fn handler_store_refresh_token(
    store: &dyn ports::RefreshTokenPort,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
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

    match store
        .store(token_hash, user_id, tenant_id, family_id, ttl)
        .await
    {
        Ok(()) => ok_reply(
            &env,
            "StoreRefreshTokenReply",
            serde_json::json!({ "status": "success" }),
        ),
        Err(e) => erro(
            &env,
            "StoreRefreshTokenReply",
            error_core::AppError::Cache(e.to_string()),
        ),
    }
}

async fn handler_validate_and_rotate(
    store: &dyn ports::RefreshTokenPort,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let token_hash = payload_json
        .get("token_hash")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    match store.validate_and_rotate(token_hash).await {
        Ok(reg) => ok_reply(
            &env,
            "ValidateAndRotateReply",
            serde_json::to_value(&reg).unwrap_or_default(),
        ),
        Err(e) => {
            // Reuso de token rotacionado é falha de autenticação (possível roubo de sessão),
            // não um simples miss de cache. Mapeia para AppError::Auth com marcador estável
            // ("token_reuse_detected") para que a runtime_api audite o evento de segurança.
            let app_err = match e {
                infrastructure_redis::RedisError::TokenReuse => {
                    error_core::AppError::Auth("token_reuse_detected".to_string())
                }
                outro => error_core::AppError::Cache(outro.to_string()),
            };
            erro(&env, "ValidateAndRotateReply", app_err)
        }
    }
}

async fn handler_revoke_family(store: &dyn ports::RefreshTokenPort, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let family_id = payload_json
        .get("family_id")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    match store.revoke_family(family_id).await {
        Ok(()) => ok_reply(
            &env,
            "RevokeFamilyReply",
            serde_json::json!({ "status": "success" }),
        ),
        Err(e) => erro(
            &env,
            "RevokeFamilyReply",
            error_core::AppError::Cache(e.to_string()),
        ),
    }
}

async fn handler_block_token(blocklist: &dyn ports::TokenBlocklist, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let jti = payload_json
        .get("jti")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let ttl = payload_json
        .get("ttl")
        .and_then(|v| v.as_u64())
        .unwrap_or(3600);

    match blocklist.block(jti, ttl).await {
        Ok(()) => ok_reply(
            &env,
            "BlockTokenReply",
            serde_json::json!({ "status": "success" }),
        ),
        Err(e) => erro(
            &env,
            "BlockTokenReply",
            error_core::AppError::Cache(e.to_string()),
        ),
    }
}

async fn handler_is_token_blocked(
    blocklist: &dyn ports::TokenBlocklist,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let jti = payload_json
        .get("jti")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    match blocklist.is_blocked(jti).await {
        Ok(blocked) => ok_reply(
            &env,
            "IsTokenBlockedReply",
            serde_json::json!({ "blocked": blocked }),
        ),
        Err(e) => erro(
            &env,
            "IsTokenBlockedReply",
            error_core::AppError::Cache(e.to_string()),
        ),
    }
}

/// Registra uma tentativa de login (rate limiting, doc 09 §6.5) e devolve o total
/// acumulado na janela. Payload: `{ key_hash, window_s }` — `key_hash` é o hash do
/// identificador (nunca o e-mail em claro). Reply: `{ attempts }`.
async fn handler_register_login_attempt(
    rate_limiter: &dyn ports::LoginRateLimiter,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let key_hash = payload_json
        .get("key_hash")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let window_s = payload_json
        .get("window_s")
        .and_then(|v| v.as_u64())
        .unwrap_or(60);

    if key_hash.is_empty() {
        return erro(
            &env,
            "RegisterLoginAttemptReply",
            error_core::AppError::Validation("key_hash é obrigatório".to_string()),
        );
    }

    match rate_limiter
        .register_login_attempt(key_hash, window_s)
        .await
    {
        Ok(attempts) => ok_reply(
            &env,
            "RegisterLoginAttemptReply",
            serde_json::json!({ "attempts": attempts }),
        ),
        Err(e) => erro(
            &env,
            "RegisterLoginAttemptReply",
            error_core::AppError::Cache(e.to_string()),
        ),
    }
}

/// N4.4 — rate limiting amplo (recurso genérico, ex.: webhook por instância/tenant,
/// rotas quentes do `runtime_api`). Payload: `{ recurso, id, window_s }` — `id` deve
/// ser um identificador opaco. Reply: `{ attempts }`.
async fn handler_register_rate_limit_attempt(
    rate_limiter: &dyn ports::RateLimiter,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let recurso = payload_json
        .get("recurso")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let id = payload_json
        .get("id")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let window_s = payload_json
        .get("window_s")
        .and_then(|v| v.as_u64())
        .unwrap_or(60);

    if recurso.is_empty() || id.is_empty() {
        return erro(
            &env,
            "RegisterRateLimitAttemptReply",
            error_core::AppError::Validation("recurso e id são obrigatórios".to_string()),
        );
    }

    match rate_limiter.register_attempt(recurso, id, window_s).await {
        Ok(attempts) => ok_reply(
            &env,
            "RegisterRateLimitAttemptReply",
            serde_json::json!({ "attempts": attempts }),
        ),
        Err(e) => erro(
            &env,
            "RegisterRateLimitAttemptReply",
            error_core::AppError::Cache(e.to_string()),
        ),
    }
}

/// Testes unitários dos handlers via ports `mockall` (SEM Redis). Rodam no caminho
/// rápido `--bins` sem túnel. A cobertura de Redis real vive nos testes de integração
/// de `crates/infrastructure_redis/`.
#[cfg(test)]
mod tests {
    use super::*;
    use crate::ports::{
        MockCacheStore, MockLoginRateLimiter, MockRefreshTokenPort, MockTokenBlocklist,
    };
    use infrastructure_redis::{RedisError, RegistroRefresh};

    /// Helper: monta um Envelope mínimo com método e payload arbitrários.
    fn envelope_com_payload(method: &str, payload: serde_json::Value) -> Envelope {
        Envelope {
            kind: MessageKind::Request as i32,
            method: method.to_string(),
            tenant_id: uuid::Uuid::nil().to_string(),
            traceparent: "00-trace-span-01".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            ..Default::default()
        }
    }

    /// HAPPY PATH: cache hit devolve as permissões.
    #[tokio::test]
    async fn get_cache_returns_permissions_on_hit() {
        // Arrange
        let mut cache = MockCacheStore::new();
        cache
            .expect_get_flow_permissions()
            .times(1)
            .returning(|_, _| Ok(Some(vec![1, 2, 3])));
        let env = envelope_com_payload("GetCache", serde_json::json!({ "user_id": 1 }));

        // Act
        let resp = handler_get_cache(&cache, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(body["permissions"].as_array().unwrap().len(), 3);
    }

    /// FAIL-CLOSED: cache miss vira erro (chave não encontrada).
    #[tokio::test]
    async fn get_cache_miss_returns_error() {
        // Arrange
        let mut cache = MockCacheStore::new();
        cache
            .expect_get_flow_permissions()
            .times(1)
            .returning(|_, _| Ok(None));
        let env = envelope_com_payload("GetCache", serde_json::json!({ "user_id": 1 }));

        // Act
        let resp = handler_get_cache(&cache, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Error as i32);
        assert!(resp.error.is_some(), "deveria ter envelope de erro");
    }

    /// FAIL-CLOSED: reuso de token detectado vira erro de AUTENTICAÇÃO com marcador
    /// estável `token_reuse_detected`, não um erro de cache.
    #[tokio::test]
    async fn validate_and_rotate_maps_token_reuse_to_auth_error() {
        // Arrange: a port reporta reuso de token (família comprometida).
        let mut store = MockRefreshTokenPort::new();
        store
            .expect_validate_and_rotate()
            .times(1)
            .returning(|_| Err(RedisError::TokenReuse));
        let env = envelope_com_payload(
            "ValidateAndRotate",
            serde_json::json!({ "token_hash": "h" }),
        );

        // Act
        let resp = handler_validate_and_rotate(&store, env).await;

        // Assert: erro de AUTENTICAÇÃO com marcador estável, não erro de cache.
        assert_eq!(resp.kind, MessageKind::Error as i32);
        let err = resp.error.expect("deveria ter erro");
        assert!(
            err.message.contains("token_reuse_detected"),
            "esperava marcador de reuso, veio: {err:?}"
        );
    }

    /// HAPPY PATH: validate_and_rotate devolve o registro do token rotacionado.
    #[tokio::test]
    async fn validate_and_rotate_returns_registro_on_success() {
        // Arrange
        let mut store = MockRefreshTokenPort::new();
        store.expect_validate_and_rotate().times(1).returning(|_| {
            Ok(RegistroRefresh {
                user_id: 42,
                tenant_id: None,
                family_id: "fam".to_string(),
                rotacionado: false,
            })
        });
        let env = envelope_com_payload(
            "ValidateAndRotate",
            serde_json::json!({ "token_hash": "h" }),
        );

        // Act
        let resp = handler_validate_and_rotate(&store, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(body["user_id"].as_i64().unwrap(), 42);
    }

    /// HAPPY PATH: is_token_blocked devolve o booleano de bloqueio.
    #[tokio::test]
    async fn is_token_blocked_returns_flag() {
        // Arrange
        let mut blocklist = MockTokenBlocklist::new();
        blocklist
            .expect_is_blocked()
            .times(1)
            .returning(|_| Ok(true));
        let env = envelope_com_payload("IsTokenBlocked", serde_json::json!({ "jti": "j" }));

        // Act
        let resp = handler_is_token_blocked(&blocklist, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert!(body["blocked"].as_bool().unwrap());
    }

    /// FAIL-CLOSED: register_login_attempt sem key_hash é rejeitado sem tocar a port.
    #[tokio::test]
    async fn register_login_attempt_rejects_empty_key() {
        // Arrange
        let mut rate_limiter = MockLoginRateLimiter::new();
        rate_limiter.expect_register_login_attempt().never();
        let env = envelope_com_payload(
            "RegisterLoginAttempt",
            serde_json::json!({ "window_s": 60 }),
        );

        // Act
        let resp = handler_register_login_attempt(&rate_limiter, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Error as i32);
        let err = resp.error.expect("deveria ter envelope de erro");
        assert_eq!(err.code, "VALIDATION_FAILED", "veio: {err:?}");
    }

    /// HAPPY PATH: register_login_attempt devolve o total acumulado.
    #[tokio::test]
    async fn register_login_attempt_returns_count() {
        // Arrange
        let mut rate_limiter = MockLoginRateLimiter::new();
        rate_limiter
            .expect_register_login_attempt()
            .times(1)
            .returning(|_, _| Ok(3));
        let env = envelope_com_payload(
            "RegisterLoginAttempt",
            serde_json::json!({ "key_hash": "h", "window_s": 60 }),
        );

        // Act
        let resp = handler_register_login_attempt(&rate_limiter, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(body["attempts"].as_u64().unwrap(), 3);
    }
}
