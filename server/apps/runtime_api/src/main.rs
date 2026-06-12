//! Serviço runtime_api: Borda de API cliente servindo FlatBuffers e fallback gRPC.
//!
//! Expõe rotas RPC de autenticação (Login, Refresh, Logout) e administração/realtime protegidas.

use application::auth::login::AuthDeps;
use contracts::{Envelope, MessageKind};
use std::time::Duration;
use transport::Server;
use uuid::Uuid;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // 1. Inicializa observabilidade
    observability::init_telemetry("runtime_api", "production")
        .map_err(|e| anyhow::anyhow!(e.to_string()))?;
    tracing::info!("Iniciando serviço runtime_api...");

    // 2. Inicializa chaves JWT — JWT_SECRET é obrigatória (doc 09 §4): sem fallback,
    // um segredo padrão conhecido permitiria forjar tokens em produção.
    let jwt_secret = std::env::var("JWT_SECRET")
        .map_err(|_| anyhow::anyhow!("JWT_SECRET não configurada (obrigatória, ≥ 32 bytes)"))?;
    application::jwt::inicializar_chaves(&jwt_secret)?;

    let access_ttl_s = std::env::var("AUTH_ACCESS_TTL_S")
        .ok()
        .and_then(|s| s.parse::<i64>().ok())
        .unwrap_or(900); // 15 minutos

    let refresh_ttl_s = std::env::var("AUTH_REFRESH_TTL_S")
        .ok()
        .and_then(|s| s.parse::<u64>().ok())
        .unwrap_or(604800); // 7 dias

    // 3. Conecta clientes multiplexados
    let pg_client = transport::conectar_cliente("data_postgres").await?;
    let redis_client = transport::conectar_cliente("data_redis").await?;

    // Conexão com o barramento Redis para publicar eventos de segurança (auditoria de reuso).
    let bus_url = std::env::var("REDIS_BUS_URL")
        .or_else(|_| std::env::var("REDIS_URL"))
        .unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
    let bus = infrastructure_redis::criar_conexao_com_timeouts(&bus_url)
        .await
        .map_err(|e| anyhow::anyhow!("falha ao conectar no barramento Redis: {e}"))?;

    let deps = std::sync::Arc::new(AuthDeps {
        pg: pg_client,
        redis: redis_client,
        access_ttl_s,
        refresh_ttl_s,
    });

    // 4. Inicia o Servidor RPC síncrono nos 3 protocolos
    let server = Server::from_env("RUNTIME_API")
        .route("Login", {
            let deps = deps.clone();
            move |env| {
                let deps = deps.clone();
                Box::pin(async move { handler_login(deps, env).await })
            }
        })
        .route("Refresh", {
            let deps = deps.clone();
            let bus = bus.clone();
            move |env| {
                let deps = deps.clone();
                let bus = bus.clone();
                Box::pin(async move { handler_refresh(deps, bus, env).await })
            }
        })
        .route(
            "Logout",
            exigir_auth(deps.clone(), false, move |deps, env| {
                Box::pin(async move { handler_logout(deps, env).await })
            }),
        )
        .route(
            "StreamAtendimentos",
            exigir_auth(deps.clone(), false, move |deps, env| {
                Box::pin(async move { handler_stream_atendimentos(deps, env).await })
            }),
        )
        .route(
            "GetUserIdentity",
            exigir_auth(deps.clone(), true, move |deps, env| {
                Box::pin(async move {
                    handler_admin_forward(deps, env, "GetUserIdentity", "GetUserIdentityReply")
                        .await
                })
            }),
        )
        .route(
            "ListCoreSettings",
            exigir_auth(deps.clone(), true, move |deps, env| {
                Box::pin(async move {
                    handler_admin_forward(deps, env, "ListCoreSettings", "ListCoreSettingsReply")
                        .await
                })
            }),
        )
        .route(
            "UpsertCoreSetting",
            exigir_auth(deps.clone(), true, move |deps, env| {
                Box::pin(async move {
                    handler_admin_forward(deps, env, "UpsertCoreSetting", "UpsertCoreSettingReply")
                        .await
                })
            }),
        )
        .route(
            "DeleteCoreSetting",
            exigir_auth(deps.clone(), true, move |deps, env| {
                Box::pin(async move {
                    handler_admin_forward(deps, env, "DeleteCoreSetting", "DeleteCoreSettingReply")
                        .await
                })
            }),
        )
        .route(
            "GetTenantConfig",
            exigir_auth(deps.clone(), true, move |deps, env| {
                Box::pin(async move {
                    handler_admin_forward(deps, env, "GetTenantConfig", "GetTenantConfigReply")
                        .await
                })
            }),
        )
        .route(
            "UpdateTenantConfig",
            exigir_auth(deps.clone(), true, move |deps, env| {
                Box::pin(async move {
                    handler_admin_forward(
                        deps,
                        env,
                        "UpdateTenantConfig",
                        "UpdateTenantConfigReply",
                    )
                    .await
                })
            }),
        );

    tracing::info!("Servidor RPC da runtime_api configurado e pronto.");

    if let Err(e) = server.run().await {
        tracing::error!(
            "Servidor RPC da runtime_api parou com erro crítico: {:?}",
            e
        );
    }

    Ok(())
}

// --- Funções Auxiliares de Erro ---

/// Extrai o access token JWT do `Envelope`.
///
/// Convenção de transporte: o cliente envia o token no campo `causation_id`,
/// opcionalmente prefixado por `"Bearer "`. Retorna `None` quando ausente
/// (não há token a validar). Nunca faz fatiamento por índice sem checar o
/// tamanho, evitando panics em entradas malformadas.
fn extrair_bearer(env: &Envelope) -> Option<&str> {
    let bruto = env.causation_id.trim();
    if let Some(token) = bruto.strip_prefix("Bearer ") {
        let token = token.trim();
        if token.is_empty() {
            return None;
        }
        return Some(token);
    }
    // Compatibilidade: alguns clientes enviam o token cru (sem prefixo) no causation_id.
    // Um JWT tem ao menos dois pontos separando header.payload.signature.
    if bruto.matches('.').count() >= 2 {
        return Some(bruto);
    }
    None
}

fn erro_unauthorized(msg: &str, env: &Envelope) -> Envelope {
    let app_err = error_core::AppError::Auth(msg.to_string());
    let err_env = app_err.to_error_envelope(&env.traceparent, "runtime_api");
    Envelope {
        kind: MessageKind::Error as i32,
        method: format!("{}Reply", env.method),
        error: Some(err_env),
        ..env.clone()
    }
}

fn erro_forbidden(msg: &str, env: &Envelope) -> Envelope {
    let app_err = error_core::AppError::Auth(msg.to_string());
    let mut err_env = app_err.to_error_envelope(&env.traceparent, "runtime_api");
    err_env.code = "AUTH_INSUFFICIENT_SCOPE".to_string();
    err_env.user_message = "errors.auth.insufficient.scope".to_string();
    err_env.user_message_fallback = "Acesso negado devido a escopos insuficientes.".to_string();
    Envelope {
        kind: MessageKind::Error as i32,
        method: format!("{}Reply", env.method),
        error: Some(err_env),
        ..env.clone()
    }
}

fn erro_internal(msg: &str, env: &Envelope) -> Envelope {
    let app_err = error_core::AppError::Internal(msg.to_string());
    let err_env = app_err.to_error_envelope(&env.traceparent, "runtime_api");
    Envelope {
        kind: MessageKind::Error as i32,
        method: format!("{}Reply", env.method),
        error: Some(err_env),
        ..env.clone()
    }
}

// --- Wrapper / Interceptor de Autenticação na Camada de Transporte ---

fn exigir_auth<F>(
    deps: std::sync::Arc<AuthDeps>,
    exigir_superuser: bool,
    handler: F,
) -> impl Fn(Envelope) -> futures_util::future::BoxFuture<'static, Envelope>
       + Clone
       + Send
       + Sync
       + 'static
where
    F: Fn(std::sync::Arc<AuthDeps>, Envelope) -> futures_util::future::BoxFuture<'static, Envelope>
        + Clone
        + Send
        + Sync
        + 'static,
{
    move |mut env| {
        let deps = deps.clone();
        let handler = handler.clone();
        Box::pin(async move {
            // 1. Extrair token de acesso JWT do Envelope (causation_id, com ou sem "Bearer ")
            let token = match extrair_bearer(&env) {
                Some(t) => t.to_string(),
                None => return erro_unauthorized("Token de acesso JWT ausente", &env),
            };

            // 2. Validar assinatura e expiração do access token
            let claims = match application::jwt::validar_access_token(&token) {
                Ok(c) => c,
                Err(e) => {
                    return erro_unauthorized(&format!("Token inválido ou expirado: {:?}", e), &env)
                }
            };

            // 3. Verificar blocklist no Redis (para tokens revogados via Logout)
            let blocked_payload = serde_json::json!({ "jti": claims.jti });
            let block_req = application::auth::login::montar_envelope_request(
                Uuid::nil(),
                &env.traceparent,
                "IsTokenBlocked",
                &blocked_payload,
            );

            match deps.redis.call(block_req, Duration::from_secs(3)).await {
                Ok(resp) => {
                    if resp.kind == MessageKind::Error as i32 {
                        let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                        return erro_unauthorized(&format!("Token revogado: {}", err_msg), &env);
                    }
                    if let Ok(res_json) = serde_json::from_slice::<serde_json::Value>(&resp.payload)
                    {
                        if res_json
                            .get("blocked")
                            .and_then(|v| v.as_bool())
                            .unwrap_or(false)
                        {
                            return erro_unauthorized(
                                "Sessão encerrada. Token na blocklist.",
                                &env,
                            );
                        }
                    }
                }
                Err(e) => {
                    return erro_internal(
                        &format!("Falha ao validar revogação do token: {:?}", e),
                        &env,
                    );
                }
            }

            // 4. Impor relação de superusuário se a rota for administrativa
            if exigir_superuser && !claims.is_superuser {
                return erro_forbidden("Acesso negado: exige privilégios de superusuário", &env);
            }

            // 5. Injetar metadados autenticados no Envelope
            env.auth_user_id = claims.sub.parse::<i32>().unwrap_or(0);
            env.auth_scopes = claims.scopes.clone();
            env.auth_is_superuser = claims.is_superuser;

            // Se for superusuário, o tenant_id no Envelope deve ser sobrescrito para Uuid::nil() (global)
            // Caso contrário, herda o tenant_id das claims do token.
            if claims.is_superuser {
                env.tenant_id = Uuid::nil().to_string();
            } else {
                env.tenant_id = claims.tenant_id.clone();
            }

            // 6. Encaminhar para o handler de destino
            handler(deps, env).await
        })
    }
}

// --- Handlers de Operações ---

/// Handler de Login: extrai as credenciais e chama a lógica de negócio na crate application
async fn handler_login(deps: std::sync::Arc<AuthDeps>, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(_) => serde_json::json!({}),
    };

    let email = payload_json
        .get("email")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let password = payload_json
        .get("password")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    match application::auth::login::login(&deps, &env.traceparent, email, password).await {
        Ok(tokens) => Envelope {
            kind: MessageKind::Reply as i32,
            method: "LoginReply".to_string(),
            payload: serde_json::to_vec(&tokens).unwrap_or_default(),
            error: None,
            ..env
        },
        Err(err) => {
            let err_env = err.to_error_envelope(&env.traceparent, "runtime_api");
            Envelope {
                kind: MessageKind::Error as i32,
                method: "LoginReply".to_string(),
                error: Some(err_env),
                ..env
            }
        }
    }
}

/// Handler de Refresh: realiza a rotação de tokens
async fn handler_refresh(
    deps: std::sync::Arc<AuthDeps>,
    mut bus: redis::aio::ConnectionManager,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(_) => serde_json::json!({}),
    };

    let refresh_token = payload_json
        .get("refresh_token")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    match application::auth::refresh::refresh(&deps, &env.traceparent, refresh_token).await {
        Ok(tokens) => Envelope {
            kind: MessageKind::Reply as i32,
            method: "RefreshReply".to_string(),
            payload: serde_json::to_vec(&tokens).unwrap_or_default(),
            error: None,
            ..env
        },
        Err(err) => {
            // Reuso de refresh rotacionado: a família já foi revogada pelo data_redis.
            // Aqui publicamos o evento de segurança `token_reuse_detected` no security:stream.
            if matches!(&err, error_core::AppError::Auth(m) if m == application::auth::refresh::REUSE_MARKER)
            {
                publicar_reuso_detectado(&mut bus, &env).await;
            }
            let err_env = err.to_error_envelope(&env.traceparent, "runtime_api");
            Envelope {
                kind: MessageKind::Error as i32,
                method: "RefreshReply".to_string(),
                error: Some(err_env),
                ..env
            }
        }
    }
}

/// Publica o evento de auditoria `token_reuse_detected` no stream de segurança.
/// Nunca registra o token em si — apenas o traceparent para correlação.
async fn publicar_reuso_detectado(bus: &mut redis::aio::ConnectionManager, env: &Envelope) {
    let audit_payload = observability::AuditLogPayload {
        tenant_id: None,
        level: "WARN".to_string(),
        service: "runtime_api".to_string(),
        trace_id: Some(env.traceparent.clone()),
        event: "token_reuse_detected".to_string(),
        message: "Reuso de refresh token rotacionado detectado; família revogada.".to_string(),
        context: serde_json::json!({}),
        user_id: None,
        ip_address: None,
    };
    let envelope_auditoria =
        contracts::TenantEnvelope::novo(Uuid::nil(), "security.audit", audit_payload)
            .com_traceparent(env.traceparent.clone());

    if let Err(e) = transport::bus::publicar_evento_seguranca(bus, &envelope_auditoria).await {
        tracing::error!("Falha ao publicar evento token_reuse_detected: {:?}", e);
    }
}

/// Handler de Logout: invalida a sessão
async fn handler_logout(deps: std::sync::Arc<AuthDeps>, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(_) => serde_json::json!({}),
    };

    let refresh_token = payload_json.get("refresh_token").and_then(|v| v.as_str());

    let token = match extrair_bearer(&env) {
        Some(t) => t.to_string(),
        None => return erro_unauthorized("Token de acesso JWT ausente", &env),
    };

    let claims = match application::jwt::validar_access_token(&token) {
        Ok(c) => c,
        Err(e) => return erro_unauthorized(&format!("Token inválido: {:?}", e), &env),
    };

    match application::auth::logout::logout(&deps, &env.traceparent, &claims, refresh_token).await {
        Ok(res) => Envelope {
            kind: MessageKind::Reply as i32,
            method: "LogoutReply".to_string(),
            payload: serde_json::to_vec(&res).unwrap_or_default(),
            error: None,
            ..env
        },
        Err(err) => {
            let err_env = err.to_error_envelope(&env.traceparent, "runtime_api");
            Envelope {
                kind: MessageKind::Error as i32,
                method: "LogoutReply".to_string(),
                error: Some(err_env),
                ..env
            }
        }
    }
}

/// Handler de StreamAtendimentos: repassa a solicitação ao data_postgres
async fn handler_stream_atendimentos(deps: std::sync::Arc<AuthDeps>, env: Envelope) -> Envelope {
    let req = Envelope {
        kind: MessageKind::Request as i32,
        method: "ListAtendimentos".to_string(),
        // Causalidade correta (a request interna é causada pela mensagem de borda) e,
        // sobretudo, não repassa o JWT — que trafega no causation_id da borda — aos
        // serviços internos.
        causation_id: env.message_id.clone(),
        ..env.clone()
    };

    match deps.pg.call(req, Duration::from_secs(5)).await {
        Ok(resp) => Envelope {
            method: "StreamAtendimentosReply".to_string(),
            ..resp
        },
        Err(e) => {
            let app_err =
                error_core::AppError::Internal(format!("RPC ListAtendimentos falhou: {e}"));
            let err_env = app_err.to_error_envelope(&env.traceparent, "runtime_api");
            Envelope {
                kind: MessageKind::Error as i32,
                method: "StreamAtendimentosReply".to_string(),
                error: Some(err_env),
                ..env
            }
        }
    }
}

/// Handler de Encaminhamento Admin: repassa a operação para o data_postgres preservando o envelope autenticado
async fn handler_admin_forward(
    deps: std::sync::Arc<AuthDeps>,
    env: Envelope,
    target_method: &'static str,
    reply_method: &'static str,
) -> Envelope {
    let req = Envelope {
        kind: MessageKind::Request as i32,
        method: target_method.to_string(),
        // Não repassa o JWT (transportado no causation_id da borda) aos serviços internos;
        // registra a causalidade real da chamada.
        causation_id: env.message_id.clone(),
        ..env.clone()
    };

    match deps.pg.call(req, Duration::from_secs(5)).await {
        Ok(resp) => Envelope {
            method: reply_method.to_string(),
            ..resp
        },
        Err(e) => {
            let app_err =
                error_core::AppError::Internal(format!("RPC {} falhou: {}", target_method, e));
            let err_env = app_err.to_error_envelope(&env.traceparent, "runtime_api");
            Envelope {
                kind: MessageKind::Error as i32,
                method: reply_method.to_string(),
                error: Some(err_env),
                ..env
            }
        }
    }
}
