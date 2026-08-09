//! Serviço runtime_api: Borda de API cliente servindo FlatBuffers e fallback gRPC.
//!
//! Expõe rotas RPC de autenticação (Login, Refresh, Logout) e administração/realtime protegidas.

use application::auth::login::AuthDeps;
use contracts::{Envelope, MessageKind};
use std::time::Duration;
use transport::Server;
use uuid::Uuid;

mod audit;
mod grpc_web;
mod onboarding_web;
mod realtime;

use audit::{publicar_auditoria_borda, publicar_reuso_detectado};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // 1. Inicializa observabilidade
    observability::init_telemetry("runtime_api", "production")
        .map_err(|e| anyhow::anyhow!(e.to_string()))?;
    // Panic em task de background mata so a task: o processo segue vivo e a
    // funcionalidade some sem deixar rastro. O hook garante o registro estruturado.
    observability::instalar_hook_de_panic("runtime_api");
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

    // Rate limiting de login: formato "N/Ms" (N tentativas por M segundos), padrão 5/60s.
    let (login_rate_max, login_rate_window_s) = std::env::var("AUTH_LOGIN_RATE_LIMIT")
        .ok()
        .and_then(|s| parse_rate_limit(&s))
        .unwrap_or((5, 60));

    // 3. Conecta clientes multiplexados
    let pg_client = transport::conectar_cliente("data_postgres").await?;
    let redis_client = transport::conectar_cliente("data_redis").await?;
    // N9/E1: a borda compõe pg (valida atendimento e quota) + storage (assina a
    // URL de upload). Nenhuma das duas portas de dados chama a outra.
    let storage_client = transport::conectar_cliente("data_storage").await?;

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
        login_rate_max,
        login_rate_window_s,
        // N9/E1: composicao do upload de midia (presign no data_storage).
        storage: Some(storage_client),
    });

    // 4. Inicia o Servidor RPC síncrono nos 3 protocolos
    let server = Server::from_env("RUNTIME_API")
        .route("Login", {
            let deps = deps.clone();
            let bus = bus.clone();
            move |env| {
                let deps = deps.clone();
                let bus = bus.clone();
                Box::pin(async move { handler_login(deps, bus, env).await })
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
        .route("Logout", {
            let bus = bus.clone();
            exigir_auth(deps.clone(), bus.clone(), false, move |deps, env| {
                let bus = bus.clone();
                Box::pin(async move { handler_logout(deps, bus, env).await })
            })
        })
        .route(
            "StreamAtendimentos",
            exigir_auth(deps.clone(), bus.clone(), false, move |deps, env| {
                Box::pin(async move { handler_stream_atendimentos(deps, env).await })
            }),
        )
        .route(
            "GetUserIdentity",
            exigir_auth(deps.clone(), bus.clone(), true, move |deps, env| {
                Box::pin(async move {
                    handler_admin_forward(deps, env, "GetUserIdentity", "GetUserIdentityReply")
                        .await
                })
            }),
        )
        .route(
            "ListCoreSettings",
            exigir_auth(deps.clone(), bus.clone(), true, move |deps, env| {
                Box::pin(async move {
                    handler_admin_forward(deps, env, "ListCoreSettings", "ListCoreSettingsReply")
                        .await
                })
            }),
        )
        .route(
            "UpsertCoreSetting",
            exigir_auth(deps.clone(), bus.clone(), true, move |deps, env| {
                Box::pin(async move {
                    handler_admin_forward(deps, env, "UpsertCoreSetting", "UpsertCoreSettingReply")
                        .await
                })
            }),
        )
        .route(
            "DeleteCoreSetting",
            exigir_auth(deps.clone(), bus.clone(), true, move |deps, env| {
                Box::pin(async move {
                    handler_admin_forward(deps, env, "DeleteCoreSetting", "DeleteCoreSettingReply")
                        .await
                })
            }),
        )
        .route(
            "GetTenantConfig",
            exigir_auth(deps.clone(), bus.clone(), true, move |deps, env| {
                Box::pin(async move {
                    handler_admin_forward(deps, env, "GetTenantConfig", "GetTenantConfigReply")
                        .await
                })
            }),
        )
        .route(
            "UpdateTenantConfig",
            exigir_auth(deps.clone(), bus.clone(), true, move |deps, env| {
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
        )
        // --- WS-5.1: gestão de convites (tenant admin; RBAC fino aplicado no data_postgres) ---
        .route(
            "CreateInvite",
            exigir_auth(deps.clone(), bus.clone(), false, move |deps, env| {
                Box::pin(async move {
                    handler_admin_forward(deps, env, "CreateInvite", "CreateInviteReply").await
                })
            }),
        )
        .route(
            "AcceptInvite",
            exigir_auth(deps.clone(), bus.clone(), false, move |deps, env| {
                Box::pin(async move {
                    handler_admin_forward(deps, env, "AcceptInvite", "AcceptInviteReply").await
                })
            }),
        )
        // --- N3: painel do tenant (gestão de usuários/convites; RBAC fino no data_postgres) ---
        .route(
            "ListTenantUsers",
            exigir_auth(deps.clone(), bus.clone(), false, move |deps, env| {
                Box::pin(async move {
                    handler_admin_forward(deps, env, "ListTenantUsers", "ListTenantUsersReply")
                        .await
                })
            }),
        )
        .route(
            "ListInvites",
            exigir_auth(deps.clone(), bus.clone(), false, move |deps, env| {
                Box::pin(async move {
                    handler_admin_forward(deps, env, "ListInvites", "ListInvitesReply").await
                })
            }),
        )
        .route(
            "RevokeInvite",
            exigir_auth(deps.clone(), bus.clone(), false, move |deps, env| {
                Box::pin(async move {
                    handler_admin_forward(deps, env, "RevokeInvite", "RevokeInviteReply").await
                })
            }),
        )
        .route(
            "UpdateTenantUser",
            exigir_auth(deps.clone(), bus.clone(), false, move |deps, env| {
                Box::pin(async move {
                    handler_admin_forward(deps, env, "UpdateTenantUser", "UpdateTenantUserReply")
                        .await
                })
            }),
        )
        // --- WS-5.2: comandos de leitura operacional (fila, histórico) ---
        .route(
            "ListAtendimentos",
            exigir_auth(deps.clone(), bus.clone(), false, move |deps, env| {
                Box::pin(async move {
                    handler_admin_forward(deps, env, "ListAtendimentos", "ListAtendimentosReply")
                        .await
                })
            }),
        )
        .route(
            "GetThread",
            exigir_auth(deps.clone(), bus.clone(), false, move |deps, env| {
                Box::pin(async move {
                    handler_admin_forward(deps, env, "GetThread", "GetThreadReply").await
                })
            }),
        )
        // --- WS-6.2/6.3: fila/Kanban (mover etapa) e chat (envio outbound) ---
        .route(
            "MoveAtendimentoEtapa",
            exigir_auth(deps.clone(), bus.clone(), false, move |deps, env| {
                Box::pin(async move {
                    handler_admin_forward(
                        deps,
                        env,
                        "MoveAtendimentoEtapa",
                        "MoveAtendimentoEtapaReply",
                    )
                    .await
                })
            }),
        )
        .route(
            "SendOutboundMessage",
            exigir_auth(deps.clone(), bus.clone(), false, move |deps, env| {
                Box::pin(async move {
                    handler_admin_forward(
                        deps,
                        env,
                        "SendOutboundMessage",
                        "SendOutboundMessageReply",
                    )
                    .await
                })
            }),
        );

    // --- WS-7: CRUD administrativo (superusuário). O painel admin fala somente com a
    // runtime_api (decisão de arquitetura), que encaminha para os handlers já
    // existentes do data_postgres. Cada rota exige superusuário no interceptor. ---
    let server = registrar_rotas_admin(server, deps.clone(), bus.clone());

    tracing::info!("Servidor RPC da runtime_api configurado e pronto.");

    // Fachada gRPC-Web da borda do browser (Flutter Web/WASM): roda em task paralela,
    // numa porta HTTP própria, reaproveitando os mesmos `deps`/`bus` e delegando para
    // `application::auth::*`. Não interfere no `transport::Server` (IPC interno).
    {
        let facade_deps = deps.clone();
        let facade_bus = bus.clone();
        tokio::spawn(async move {
            if let Err(e) = grpc_web::serve(facade_deps, facade_bus).await {
                tracing::error!("Fachada gRPC-Web parou com erro: {:?}", e);
            }
        });
    }

    // Ver a nota em `data_redis`: SIGTERM precisa ser tratado, senão todo deploy
    // mata o processo no meio do que estava em voo.
    tokio::select! {
        res = server.run() => {
            if let Err(e) = res {
                tracing::error!(
                    "Servidor RPC da runtime_api parou com erro crítico: {:?}",
                    e
                );
            }
        }
        _ = observability::aguardar_sinal_de_parada() => {}
    }

    observability::shutdown_telemetry();
    Ok(())
}

/// Registra o catálogo de rotas de administração (superusuário) que encaminham
/// para os handlers já existentes do `data_postgres`. Mantém o `main` enxuto e
/// centraliza o RBAC de borda (todas exigem superusuário no interceptor) — WS-7.
/// Convenção: o nome da rota == método encaminhado; o reply == método + "Reply".
fn registrar_rotas_admin(
    mut server: Server,
    deps: std::sync::Arc<AuthDeps>,
    bus: redis::aio::ConnectionManager,
) -> Server {
    const ROTAS_ADMIN: &[&str] = &[
        // Tenants
        "ListTenants",
        "GetTenant",
        "UpdateTenant",
        "SetTenantActive",
        "GenerateAccessCode",
        // Planos / assinatura
        "ListPlans",
        "CreatePlan",
        "UpdatePlan",
        "ListSubscriptions",
        "RegisterPayment",
        "ListPayments",
        // Vouchers de ativação
        "ListVouchers",
        "CreateVoucher",
        "RevokeVoucher",
        "ListVoucherRedemptions",
        // Observabilidade administrativa
        "QueryAuditLog",
        "GetServiceHealth",
        "GetDashboardSummary",
        "ExportTenantsCsv",
        // Feature flags
        "ListFeatureFlags",
        "SetFeatureFlag",
        "SetFeatureFlagOverride",
    ];

    for metodo in ROTAS_ADMIN {
        let metodo: &'static str = metodo;
        // reply estático (`<Metodo>Reply`); o vazamento é único no boot do serviço.
        let reply: &'static str = Box::leak(format!("{metodo}Reply").into_boxed_str());
        let deps = deps.clone();
        let bus = bus.clone();
        server = server.route(
            metodo,
            exigir_auth(deps, bus, true, move |deps, env| {
                Box::pin(async move { handler_admin_forward(deps, env, metodo, reply).await })
            }),
        );
    }

    server
}

/// Interpreta o formato "N/Ms" de `AUTH_LOGIN_RATE_LIMIT` (ex.: "5/60s").
/// Retorna `None` para entradas malformadas (o caller aplica o padrão 5/60s).
fn parse_rate_limit(s: &str) -> Option<(u64, u64)> {
    let (max, janela) = s.split_once('/')?;
    let max = max.trim().parse::<u64>().ok()?;
    let janela = janela.trim().trim_end_matches('s').parse::<u64>().ok()?;
    if max == 0 || janela == 0 {
        return None;
    }
    Some((max, janela))
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

/// Registra o erro no tracing (ponto único da borda: todo Envelope de erro emitido
/// pela `runtime_api` passa pelos helpers `erro_*` e fica visível nos logs).
fn registrar_erro_borda(app_err: &error_core::AppError, env: &Envelope) {
    error_core::registrar(
        app_err,
        &error_core::ErrorContext {
            trace_id: env.traceparent.clone(),
            tenant_id: env.tenant_id.clone(),
        },
    );
}

fn erro_unauthorized(msg: &str, env: &Envelope) -> Envelope {
    let app_err = error_core::AppError::Auth(msg.to_string());
    registrar_erro_borda(&app_err, env);
    tracing::warn!(method = %env.method, motivo = %msg, "requisição rejeitada: não autenticada");
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
    registrar_erro_borda(&app_err, env);
    tracing::warn!(
        method = %env.method,
        user_id = env.auth_user_id,
        motivo = %msg,
        "requisição rejeitada: escopo/privilégio insuficiente"
    );
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

fn erro_rate_limit(msg: &str, env: &Envelope) -> Envelope {
    let app_err = error_core::AppError::RateLimit(msg.to_string());
    registrar_erro_borda(&app_err, env);
    tracing::warn!(method = %env.method, user_id = env.auth_user_id, "requisição rejeitada: rate limit excedido");
    let err_env = app_err.to_error_envelope(&env.traceparent, "runtime_api");
    Envelope {
        kind: MessageKind::Error as i32,
        method: format!("{}Reply", env.method),
        error: Some(err_env),
        ..env.clone()
    }
}

fn erro_internal(msg: &str, env: &Envelope) -> Envelope {
    let app_err = error_core::AppError::Internal(msg.to_string());
    registrar_erro_borda(&app_err, env);
    let err_env = app_err.to_error_envelope(&env.traceparent, "runtime_api");
    Envelope {
        kind: MessageKind::Error as i32,
        method: format!("{}Reply", env.method),
        error: Some(err_env),
        ..env.clone()
    }
}

// --- Provider de flow_permissions (RBAC fino por fluxo — WS-5a) ---
//
// Decisão (confirmada com o dono): RPC ao data_postgres como fonte de verdade,
// com cache curto (TTL ~30s) no data_redis no caminho quente. Evita revogação
// atrasada de acesso a fluxo (vs. claim estático no JWT) e mantém "banco só via
// infra/RPC". Cache-aside: tenta o cache, na falta consulta o banco e repovoa.
async fn resolver_flow_permissions(
    deps: &AuthDeps,
    tenant_id: &str,
    user_id: i32,
    traceparent: &str,
) -> Vec<i32> {
    let tenant_uuid = Uuid::parse_str(tenant_id).unwrap_or_else(|_| Uuid::nil());
    let lookup_payload = serde_json::json!({ "user_id": user_id });

    let cache_req = application::auth::login::montar_envelope_request(
        tenant_uuid,
        traceparent,
        "GetCache",
        &lookup_payload,
    );
    if let Ok(resp) = deps.redis.call(cache_req, Duration::from_secs(2)).await {
        if resp.kind != MessageKind::Error as i32 {
            if let Some(perms) = extrair_permissoes(&resp.payload) {
                return perms;
            }
        }
    }

    // Cache miss (ou data_redis indisponível): consulta a fonte de verdade.
    let db_req = application::auth::login::montar_envelope_request(
        tenant_uuid,
        traceparent,
        "GetUserFlowPermissions",
        &lookup_payload,
    );
    let permissions = match deps.pg.call(db_req, Duration::from_secs(3)).await {
        Ok(resp) if resp.kind != MessageKind::Error as i32 => {
            extrair_permissoes(&resp.payload).unwrap_or_default()
        }
        _ => Vec::new(),
    };

    // Repovoa o cache (best-effort, TTL curto — não atrasa a resposta em caso de falha).
    let set_payload = serde_json::json!({
        "user_id": user_id,
        "permissions": permissions,
        "ttl": 30,
    });
    let set_req = application::auth::login::montar_envelope_request(
        tenant_uuid,
        traceparent,
        "SetCache",
        &set_payload,
    );
    let _ = deps.redis.call(set_req, Duration::from_secs(2)).await;

    permissions
}

fn extrair_permissoes(payload: &[u8]) -> Option<Vec<i32>> {
    let json: serde_json::Value = serde_json::from_slice(payload).ok()?;
    let arr = json.get("permissions")?.as_array()?;
    Some(
        arr.iter()
            .filter_map(|v| v.as_i64())
            .map(|v| v as i32)
            .collect(),
    )
}

// --- Wrapper / Interceptor de Autenticação na Camada de Transporte ---

fn exigir_auth<F>(
    deps: std::sync::Arc<AuthDeps>,
    bus: redis::aio::ConnectionManager,
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
        let mut bus = bus.clone();
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

            // 4. Impor relação de superusuário se a rota for administrativa.
            // Tentativa de acesso admin sem privilégio é evento de segurança auditável.
            if exigir_superuser && !claims.is_superuser {
                publicar_auditoria_borda(
                    &mut bus,
                    Uuid::parse_str(&claims.tenant_id)
                        .ok()
                        .filter(|u| !u.is_nil()),
                    "WARN",
                    "auth_access_denied",
                    format!("Acesso à rota administrativa '{}' negado.", env.method),
                    serde_json::json!({ "method": env.method }),
                    claims.sub.parse::<i32>().ok(),
                    &env.traceparent,
                    None,
                    None,
                )
                .await;
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

            // 5b. RBAC fino por fluxo (WS-5a): popula flow_permissions via RPC+cache curto.
            // Superusuário não tem TenantUser; bypass de fluxo já ocorre via escopo
            // (kanban:admin/tenant:admin) em RequestContext::has_flow_permission.
            if !claims.is_superuser {
                env.flow_permissions = resolver_flow_permissions(
                    &deps,
                    &claims.tenant_id,
                    env.auth_user_id,
                    &env.traceparent,
                )
                .await;
            }

            // 5c. Rate limiting amplo por usuário autenticado (N4.4). Fail-open: erro
            // na checagem não bloqueia a requisição (mesmo espírito do QuotaGuard).
            let rl_max = std::env::var("RUNTIME_API_RATE_LIMIT_MAX")
                .ok()
                .and_then(|s| s.parse::<u64>().ok())
                .unwrap_or(300);
            let rl_window_s = std::env::var("RUNTIME_API_RATE_LIMIT_WINDOW_S")
                .ok()
                .and_then(|s| s.parse::<u64>().ok())
                .unwrap_or(60);
            let rl_id = format!("{}:{}", env.tenant_id, env.auth_user_id);
            let rl_payload = serde_json::json!({ "recurso": "runtime_api", "id": rl_id, "window_s": rl_window_s });
            let rl_req = application::auth::login::montar_envelope_request(
                Uuid::nil(),
                &env.traceparent,
                "RegisterRateLimitAttempt",
                &rl_payload,
            );
            match deps.redis.call(rl_req, Duration::from_secs(3)).await {
                Ok(resp) if resp.kind != MessageKind::Error as i32 => {
                    if let Ok(body) = serde_json::from_slice::<serde_json::Value>(&resp.payload) {
                        let attempts = body.get("attempts").and_then(|v| v.as_u64()).unwrap_or(0);
                        if attempts > rl_max {
                            publicar_auditoria_borda(
                                &mut bus,
                                Uuid::parse_str(&env.tenant_id).ok().filter(|u| !u.is_nil()),
                                "WARN",
                                "rate_limit_exceeded",
                                format!("Rate limit excedido na rota '{}'", env.method),
                                serde_json::json!({ "method": env.method, "attempts": attempts, "max": rl_max }),
                                claims.sub.parse::<i32>().ok(),
                                &env.traceparent,
                                None,
                                None,
                            )
                            .await;
                            return erro_rate_limit(
                                "Muitas requisições; aguarde antes de tentar novamente",
                                &env,
                            );
                        }
                    }
                }
                Ok(_) => {
                    tracing::warn!(method = %env.method, "falha ao registrar rate limit (fail-open)");
                }
                Err(e) => {
                    tracing::warn!(method = %env.method, "erro RPC no rate limit (fail-open): {:?}", e);
                }
            }

            // 6. Encaminhar para o handler de destino
            handler(deps, env).await
        })
    }
}

// --- Handlers de Operações ---

/// Handler de Login: extrai as credenciais e chama a lógica de negócio na crate application.
/// Audita `login_success` (INFO) e `login_rate_limited` (WARN) no security:stream;
/// o `login_failed` (credencial inválida) já é auditado pelo `data_postgres`.
async fn handler_login(
    deps: std::sync::Arc<AuthDeps>,
    mut bus: redis::aio::ConnectionManager,
    env: Envelope,
) -> Envelope {
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
        Ok(tokens) => {
            let user_id = tokens
                .get("user_id")
                .and_then(|v| v.as_i64())
                .map(|v| v as i32);
            let tenant_id = tokens
                .get("tenant_id")
                .and_then(|v| v.as_str())
                .and_then(|s| Uuid::parse_str(s).ok())
                .filter(|u| !u.is_nil());
            publicar_auditoria_borda(
                &mut bus,
                tenant_id,
                "INFO",
                "login_success",
                "Login bem-sucedido.".to_string(),
                serde_json::json!({}),
                user_id,
                &env.traceparent,
                None,
                None,
            )
            .await;
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "LoginReply".to_string(),
                payload: serde_json::to_vec(&tokens).unwrap_or_default(),
                error: None,
                ..env
            }
        }
        Err(err) => {
            // Rate limit estourado é evento de segurança auditável (possível força bruta).
            if matches!(&err, error_core::AppError::RateLimit(_)) {
                publicar_auditoria_borda(
                    &mut bus,
                    None,
                    "WARN",
                    "login_rate_limited",
                    "Tentativas de login acima do limite na janela.".to_string(),
                    serde_json::json!({}),
                    None,
                    &env.traceparent,
                    None,
                    None,
                )
                .await;
            }
            registrar_erro_borda(&err, &env);
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
                publicar_reuso_detectado(&mut bus, &env.traceparent, None, None).await;
            }
            registrar_erro_borda(&err, &env);
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

/// Handler de Logout: invalida a sessão e audita o evento `logout` no security:stream.
async fn handler_logout(
    deps: std::sync::Arc<AuthDeps>,
    mut bus: redis::aio::ConnectionManager,
    env: Envelope,
) -> Envelope {
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
        Ok(res) => {
            let tenant_id = Uuid::parse_str(&claims.tenant_id)
                .ok()
                .filter(|u| !u.is_nil());
            publicar_auditoria_borda(
                &mut bus,
                tenant_id,
                "INFO",
                "logout",
                "Sessão encerrada pelo usuário (jti bloqueado e família revogada).".to_string(),
                serde_json::json!({ "jti": claims.jti }),
                claims.sub.parse::<i32>().ok(),
                &env.traceparent,
                None,
                None,
            )
            .await;
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "LogoutReply".to_string(),
                payload: serde_json::to_vec(&res).unwrap_or_default(),
                error: None,
                ..env
            }
        }
        Err(err) => {
            registrar_erro_borda(&err, &env);
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

#[cfg(test)]
mod tests {
    use super::*;
    use contracts::{Envelope, MessageKind};
    use std::time::Duration;
    use transport::runtime::{Endpoint, Server};
    use uuid::Uuid;

    // Mutex estático local para serializar testes de integração da runtime_api
    // que modificam variáveis de ambiente globais.
    static RUNTIME_TEST_MUTEX: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

    /// Sobe um stub TCP minimalista do protocolo RESP (responde `+PONG`/`+OK`)
    /// e devolve um `ConnectionManager` apontando para ele — suficiente para os
    /// publishes de auditoria best-effort dos handlers em teste.
    async fn fake_bus(porta: u16) -> redis::aio::ConnectionManager {
        let listener = tokio::net::TcpListener::bind(("127.0.0.1", porta))
            .await
            .unwrap();
        tokio::spawn(async move {
            loop {
                let Ok((mut socket, _)) = listener.accept().await else {
                    break;
                };
                tokio::spawn(async move {
                    use tokio::io::{AsyncReadExt, AsyncWriteExt};
                    let mut buf = [0u8; 4096];
                    while let Ok(n) = socket.read(&mut buf).await {
                        if n == 0 {
                            break;
                        }
                        // Responde UMA vez por comando RESP (arrays começam com '*'),
                        // garantindo que o cliente nunca fique aguardando resposta.
                        let req = String::from_utf8_lossy(&buf[..n]);
                        for parte in req.split('*') {
                            if parte.is_empty() {
                                continue;
                            }
                            if parte.to_uppercase().contains("PING") {
                                let _ = socket.write_all(b"+PONG\r\n").await;
                            } else {
                                let _ = socket.write_all(b"+OK\r\n").await;
                            }
                        }
                    }
                });
            }
        });
        let client = redis::Client::open(format!("redis://127.0.0.1:{porta}")).unwrap();
        redis::aio::ConnectionManager::new(client).await.unwrap()
    }

    #[test]
    fn test_runtime_api_extrair_bearer() {
        let env1 = Envelope {
            causation_id: "Bearer meu_token_jwt".to_string(),
            ..Default::default()
        };
        assert_eq!(extrair_bearer(&env1), Some("meu_token_jwt"));

        let env2 = Envelope {
            causation_id: "Bearer   token_espacos  ".to_string(),
            ..Default::default()
        };
        assert_eq!(extrair_bearer(&env2), Some("token_espacos"));

        let env3 = Envelope {
            causation_id: "Bearer ".to_string(),
            ..Default::default()
        };
        assert_eq!(extrair_bearer(&env3), None);

        // Sem prefixo, mas com formato JWT (2 pontos)
        let env4 = Envelope {
            causation_id: "abc.def.ghi".to_string(),
            ..Default::default()
        };
        assert_eq!(extrair_bearer(&env4), Some("abc.def.ghi"));

        // Sem prefixo, sem formato JWT
        let env5 = Envelope {
            causation_id: "token_invalido".to_string(),
            ..Default::default()
        };
        assert_eq!(extrair_bearer(&env5), None);
    }

    #[tokio::test]
    async fn test_runtime_api_exigir_auth_interceptor() {
        let _guard = RUNTIME_TEST_MUTEX.lock().await;
        let _ =
            application::jwt::inicializar_chaves("segredo_de_teste_de_pelo_menos_32_bytes_longo");

        let pg_addr = "tcp://127.0.0.1:29141";
        let redis_addr = "tcp://127.0.0.1:29142";

        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
        std::env::set_var("SMARTCORE_DATA_REDIS_ENDPOINT", redis_addr);

        // Stub Redis
        let redis_endpoint = Endpoint::parse(redis_addr).unwrap();
        let redis_server =
            Server::new(redis_endpoint, "flatbuffers").route("IsTokenBlocked", |env| {
                Box::pin(async move {
                    let payload_json: serde_json::Value =
                        serde_json::from_slice(&env.payload).unwrap();
                    let jti = payload_json.get("jti").unwrap().as_str().unwrap();

                    let blocked = jti == "token_bloqueado";
                    let reply = serde_json::json!({ "blocked": blocked });

                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "IsTokenBlockedReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            });
        let redis_handle = tokio::spawn(async move {
            redis_server.run().await.unwrap();
        });

        // Stub Postgres
        let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
        let pg_server = Server::new(pg_endpoint, "flatbuffers");
        let pg_handle = tokio::spawn(async move {
            let _ = pg_server.run().await;
        });

        tokio::time::sleep(Duration::from_millis(150)).await;

        let pg_client = transport::conectar_cliente("data_postgres").await.unwrap();
        let redis_client = transport::conectar_cliente("data_redis").await.unwrap();

        let deps = std::sync::Arc::new(AuthDeps {
            pg: pg_client,
            redis: redis_client,
            access_ttl_s: 900,
            refresh_ttl_s: 604800,
            login_rate_max: 5,
            login_rate_window_s: 60,
            storage: None,
        });
        let bus = fake_bus(29150).await;

        // 1. Testa token ausente
        let env_ausente = Envelope {
            method: "Logout".to_string(),
            ..Default::default()
        };
        let res = exigir_auth(deps.clone(), bus.clone(), false, |_, env| {
            Box::pin(async move {
                Envelope {
                    method: "Ok".to_string(),
                    ..env
                }
            })
        })(env_ausente)
        .await;
        assert_eq!(res.kind, MessageKind::Error as i32);
        let err = res.error.unwrap();
        assert_eq!(err.code, "AUTH_MISSING_TOKEN");

        // 2. Testa token inválido / expirado
        let env_invalido = Envelope {
            method: "Logout".to_string(),
            causation_id: "Bearer token.invalido.assinado".to_string(),
            ..Default::default()
        };
        let res = exigir_auth(deps.clone(), bus.clone(), false, |_, env| {
            Box::pin(async move {
                Envelope {
                    method: "Ok".to_string(),
                    ..env
                }
            })
        })(env_invalido)
        .await;
        assert_eq!(res.kind, MessageKind::Error as i32);

        // Gera token válido para testes subsequentes
        let claims = application::jwt::Claims {
            sub: "42".to_string(),
            tenant_id: Uuid::new_v4().to_string(),
            scopes: vec!["atendimentos:read".to_string()],
            is_superuser: false,
            jti: "token_jti_ok".to_string(),
            iat: chrono::Utc::now().timestamp() as usize,
            exp: (chrono::Utc::now().timestamp() + 300) as usize,
        };
        let token_valido = application::jwt::gerar_access_token(&claims).unwrap();

        // 3. Testa token bloqueado na blocklist
        let mut claims_bloqueado = claims.clone();
        claims_bloqueado.jti = "token_bloqueado".to_string();
        let token_bloqueado = application::jwt::gerar_access_token(&claims_bloqueado).unwrap();

        let env_bloqueado = Envelope {
            method: "Logout".to_string(),
            causation_id: format!("Bearer {}", token_bloqueado),
            ..Default::default()
        };
        let res = exigir_auth(deps.clone(), bus.clone(), false, |_, env| {
            Box::pin(async move {
                Envelope {
                    method: "Ok".to_string(),
                    ..env
                }
            })
        })(env_bloqueado)
        .await;
        assert_eq!(res.kind, MessageKind::Error as i32);
        assert_eq!(
            res.error.unwrap().message,
            "Erro de autenticação: Sessão encerrada. Token na blocklist."
        );

        // 4. Testa token de usuário comum acessando rota de superusuário (guard)
        let env_guard = Envelope {
            method: "ListCoreSettings".to_string(),
            causation_id: format!("Bearer {}", token_valido),
            ..Default::default()
        };
        let res = exigir_auth(deps.clone(), bus.clone(), true, |_, env| {
            Box::pin(async move {
                Envelope {
                    method: "Ok".to_string(),
                    ..env
                }
            })
        })(env_guard)
        .await;
        assert_eq!(res.kind, MessageKind::Error as i32);
        assert_eq!(res.error.unwrap().code, "AUTH_INSUFFICIENT_SCOPE");

        // 5. Testa token válido passando no interceptor e sobrescrevendo tenant e identidade
        let env_feliz = Envelope {
            method: "Logout".to_string(),
            causation_id: format!("Bearer {}", token_valido),
            ..Default::default()
        };
        let res = exigir_auth(deps.clone(), bus.clone(), false, |_, env| {
            Box::pin(async move {
                Envelope {
                    method: "Ok".to_string(),
                    ..env
                }
            })
        })(env_feliz)
        .await;

        assert_eq!(res.method, "Ok");
        assert_eq!(res.auth_user_id, 42);
        assert_eq!(res.auth_scopes, vec!["atendimentos:read".to_string()]);
        assert!(!res.auth_is_superuser);
        assert_eq!(res.tenant_id, claims.tenant_id);

        redis_handle.abort();
        pg_handle.abort();
    }

    #[tokio::test]
    async fn test_runtime_api_handler_login() {
        let _guard = RUNTIME_TEST_MUTEX.lock().await;
        let _ =
            application::jwt::inicializar_chaves("segredo_de_teste_de_pelo_menos_32_bytes_longo");

        let pg_addr = "tcp://127.0.0.1:29143";
        let redis_addr = "tcp://127.0.0.1:29144";

        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
        std::env::set_var("SMARTCORE_DATA_REDIS_ENDPOINT", redis_addr);

        let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
        let pg_server = Server::new(pg_endpoint, "flatbuffers").route("VerifyCredentials", |env| {
            Box::pin(async move {
                let user_payload = serde_json::json!({
                    "id": 42,
                    "username": "usuario_teste",
                    "email": "test@domain.com",
                    "is_superuser": false,
                    "tenant_id": Uuid::new_v4().to_string()
                });
                Envelope {
                    kind: MessageKind::Reply as i32,
                    method: "VerifyCredentialsReply".to_string(),
                    payload: serde_json::to_vec(&user_payload).unwrap(),
                    ..env
                }
            })
        });
        let pg_handle = tokio::spawn(async move {
            pg_server.run().await.unwrap();
        });

        let redis_endpoint = Endpoint::parse(redis_addr).unwrap();
        let redis_server = Server::new(redis_endpoint, "flatbuffers")
            .route("RegisterLoginAttempt", |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({ "attempts": 1 });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "RegisterLoginAttemptReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            })
            .route("StoreRefreshToken", |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({ "status": "success" });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "StoreRefreshTokenReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            });
        let redis_handle = tokio::spawn(async move {
            redis_server.run().await.unwrap();
        });

        tokio::time::sleep(Duration::from_millis(150)).await;

        let pg_client = transport::conectar_cliente("data_postgres").await.unwrap();
        let redis_client = transport::conectar_cliente("data_redis").await.unwrap();

        let deps = std::sync::Arc::new(AuthDeps {
            pg: pg_client,
            redis: redis_client,
            access_ttl_s: 900,
            refresh_ttl_s: 604800,
            login_rate_max: 5,
            login_rate_window_s: 60,
            storage: None,
        });
        let bus = fake_bus(29151).await;

        let payload = serde_json::json!({
            "email": "test@domain.com",
            "password": "senha"
        });
        let env = Envelope {
            method: "Login".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            ..Default::default()
        };

        let res = handler_login(deps, bus.clone(), env).await;
        assert_eq!(res.kind, MessageKind::Reply as i32);
        assert_eq!(res.method, "LoginReply");

        let res_payload: serde_json::Value = serde_json::from_slice(&res.payload).unwrap();
        assert!(res_payload.get("access_token").is_some());
        assert!(res_payload.get("refresh_token").is_some());

        pg_handle.abort();
        redis_handle.abort();
    }

    #[tokio::test]
    async fn test_runtime_api_handler_refresh_e_auditoria() {
        let _guard = RUNTIME_TEST_MUTEX.lock().await;
        let _ =
            application::jwt::inicializar_chaves("segredo_de_teste_de_pelo_menos_32_bytes_longo");

        let pg_addr = "tcp://127.0.0.1:29145";
        let redis_addr = "tcp://127.0.0.1:29146";

        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
        std::env::set_var("SMARTCORE_DATA_REDIS_ENDPOINT", redis_addr);

        let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
        let pg_server =
            Server::new(pg_endpoint.clone(), "flatbuffers").route("GetUserIdentity", |env| {
                Box::pin(async move {
                    let user_payload = serde_json::json!({
                        "id": 42,
                        "username": "usuario_teste",
                        "email": "test@domain.com",
                        "is_active": true,
                        "is_superuser": false,
                        "tenant_id": Uuid::new_v4().to_string(),
                        "module_permissions": []
                    });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "GetUserIdentityReply".to_string(),
                        payload: serde_json::to_vec(&user_payload).unwrap(),
                        ..env
                    }
                })
            });
        let pg_handle = tokio::spawn(async move {
            pg_server.run().await.unwrap();
        });

        let redis_endpoint = Endpoint::parse(redis_addr).unwrap();
        let contador = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let contador_clone = contador.clone();
        let redis_server = Server::new(redis_endpoint.clone(), "flatbuffers")
            .route("ValidateAndRotate", move |env| {
                let cnt = contador_clone.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                Box::pin(async move {
                    if cnt == 0 {
                        let reply = serde_json::json!({
                            "user_id": 42,
                            "tenant_id": Uuid::new_v4().to_string(),
                            "family_id": "fam_123",
                            "rotacionado": false
                        });
                        Envelope {
                            kind: MessageKind::Reply as i32,
                            method: "ValidateAndRotateReply".to_string(),
                            payload: serde_json::to_vec(&reply).unwrap(),
                            ..env
                        }
                    } else {
                        let error_env = contracts::ErrorEnvelope {
                            code: "TOKEN_REUSE".to_string(),
                            message: "token_reuse_detected".to_string(),
                            ..Default::default()
                        };
                        Envelope {
                            kind: MessageKind::Error as i32,
                            method: "ValidateAndRotateReply".to_string(),
                            error: Some(error_env),
                            ..env
                        }
                    }
                })
            })
            .route("StoreRefreshToken", |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({ "status": "success" });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "StoreRefreshTokenReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            });
        let redis_handle = tokio::spawn(async move {
            redis_server.run().await.unwrap();
        });

        tokio::time::sleep(Duration::from_millis(150)).await;

        let pg_client = transport::conectar_cliente("data_postgres").await.unwrap();
        let redis_client = transport::conectar_cliente("data_redis").await.unwrap();

        let deps = std::sync::Arc::new(AuthDeps {
            pg: pg_client,
            redis: redis_client,
            access_ttl_s: 900,
            refresh_ttl_s: 604800,
            login_rate_max: 5,
            login_rate_window_s: 60,
            storage: None,
        });

        // 1. Testa refresh feliz
        let payload = serde_json::json!({ "refresh_token": "token_valido" });
        let env = Envelope {
            method: "Refresh".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            ..Default::default()
        };

        // Stub TCP para o Redis bus para aceitar conexão e responder sucessos simples (+OK\r\n ou +PONG\r\n) a comandos
        let bus_listener = tokio::net::TcpListener::bind("127.0.0.1:29999")
            .await
            .unwrap();
        let bus_handle = tokio::spawn(async move {
            use tokio::io::{AsyncReadExt, AsyncWriteExt};
            while let Ok((mut socket, _)) = bus_listener.accept().await {
                tokio::spawn(async move {
                    let mut buf = [0u8; 1024];
                    while let Ok(n) = socket.read(&mut buf).await {
                        if n == 0 {
                            break;
                        }
                        let req = String::from_utf8_lossy(&buf[..n]);
                        let partes = req.split('*');
                        for parte in partes {
                            if parte.is_empty() {
                                continue;
                            }
                            if parte.to_uppercase().contains("PING") {
                                let _ = socket.write_all(b"+PONG\r\n").await;
                            } else {
                                let _ = socket.write_all(b"+OK\r\n").await;
                            }
                        }
                    }
                });
            }
        });

        // Passamos uma conexao de teste para o bus de auditoria conectando no nosso stub TCP.
        let redis_bus_client = redis::Client::open("redis://127.0.0.1:29999").unwrap();
        let bus_conn = redis::aio::ConnectionManager::new(redis_bus_client)
            .await
            .unwrap();

        let res = handler_refresh(deps.clone(), bus_conn.clone(), env).await;
        assert_eq!(res.kind, MessageKind::Reply as i32);

        let res_payload: serde_json::Value = serde_json::from_slice(&res.payload).unwrap();
        assert!(res_payload.get("access_token").is_some());
        assert!(res_payload.get("refresh_token").is_some());

        // 2. Testa refresh com reuso (o ValidateAndRotate agora retornará erro de reuso na segunda chamada)
        let env_reuse = Envelope {
            method: "Refresh".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            ..Default::default()
        };

        let res_reuse = handler_refresh(deps, bus_conn, env_reuse).await;
        assert_eq!(res_reuse.kind, MessageKind::Error as i32);
        assert_eq!(res_reuse.error.unwrap().code, "AUTH_INVALID_TOKEN");

        pg_handle.abort();
        redis_handle.abort();
        bus_handle.abort();
    }

    #[tokio::test]
    async fn test_runtime_api_handler_logout() {
        let _guard = RUNTIME_TEST_MUTEX.lock().await;
        let _ =
            application::jwt::inicializar_chaves("segredo_de_teste_de_pelo_menos_32_bytes_longo");

        let pg_addr = "tcp://127.0.0.1:29147";
        let redis_addr = "tcp://127.0.0.1:29148";

        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
        std::env::set_var("SMARTCORE_DATA_REDIS_ENDPOINT", redis_addr);

        let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
        let pg_server = Server::new(pg_endpoint, "flatbuffers");
        let pg_handle = tokio::spawn(async move {
            let _ = pg_server.run().await;
        });

        let redis_endpoint = Endpoint::parse(redis_addr).unwrap();
        let redis_server = Server::new(redis_endpoint, "flatbuffers").route("BlockToken", |env| {
            Box::pin(async move {
                let reply = serde_json::json!({ "status": "blocked" });
                Envelope {
                    kind: MessageKind::Reply as i32,
                    method: "BlockTokenReply".to_string(),
                    payload: serde_json::to_vec(&reply).unwrap(),
                    ..env
                }
            })
        });
        let redis_handle = tokio::spawn(async move {
            redis_server.run().await.unwrap();
        });

        tokio::time::sleep(Duration::from_millis(150)).await;

        let pg_client = transport::conectar_cliente("data_postgres").await.unwrap();
        let redis_client = transport::conectar_cliente("data_redis").await.unwrap();

        let deps = std::sync::Arc::new(AuthDeps {
            pg: pg_client,
            redis: redis_client,
            access_ttl_s: 900,
            refresh_ttl_s: 604800,
            login_rate_max: 5,
            login_rate_window_s: 60,
            storage: None,
        });
        let bus = fake_bus(29153).await;

        // Gera token válido para desempacotar as claims
        let claims = application::jwt::Claims {
            sub: "42".to_string(),
            tenant_id: Uuid::new_v4().to_string(),
            scopes: vec![],
            is_superuser: false,
            jti: "logout_jti".to_string(),
            iat: chrono::Utc::now().timestamp() as usize,
            exp: (chrono::Utc::now().timestamp() + 300) as usize,
        };
        let token = application::jwt::gerar_access_token(&claims).unwrap();

        let payload = serde_json::json!({});
        let env = Envelope {
            method: "Logout".to_string(),
            causation_id: format!("Bearer {}", token),
            payload: serde_json::to_vec(&payload).unwrap(),
            ..Default::default()
        };

        let res = handler_logout(deps, bus.clone(), env).await;
        assert_eq!(res.kind, MessageKind::Reply as i32);
        assert_eq!(res.method, "LogoutReply");

        pg_handle.abort();
        redis_handle.abort();
    }

    #[tokio::test]
    async fn test_runtime_api_handler_encaminhamento() {
        let _guard = RUNTIME_TEST_MUTEX.lock().await;

        let pg_addr = "tcp://127.0.0.1:29149";
        let redis_addr = "tcp://127.0.0.1:29150";

        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
        std::env::set_var("SMARTCORE_DATA_REDIS_ENDPOINT", redis_addr);

        let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
        let pg_server = Server::new(pg_endpoint, "flatbuffers")
            .route("ListAtendimentos", |env| {
                Box::pin(async move {
                    assert_eq!(env.causation_id, "mensagem_origem_123"); // Verifica causalidade
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "ListAtendimentosReply".to_string(),
                        payload: b"[]".to_vec(),
                        ..env
                    }
                })
            })
            .route("ListCoreSettings", |env| {
                Box::pin(async move {
                    assert_eq!(env.causation_id, "mensagem_origem_456");
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "ListCoreSettingsReply".to_string(),
                        payload: b"{}".to_vec(),
                        ..env
                    }
                })
            });
        let pg_handle = tokio::spawn(async move {
            pg_server.run().await.unwrap();
        });

        let redis_endpoint = Endpoint::parse(redis_addr).unwrap();
        let redis_server = Server::new(redis_endpoint, "flatbuffers");
        let redis_handle = tokio::spawn(async move {
            let _ = redis_server.run().await;
        });

        tokio::time::sleep(Duration::from_millis(150)).await;

        let pg_client = transport::conectar_cliente("data_postgres").await.unwrap();
        let redis_client = transport::conectar_cliente("data_redis").await.unwrap();

        let deps = std::sync::Arc::new(AuthDeps {
            pg: pg_client,
            redis: redis_client,
            access_ttl_s: 900,
            refresh_ttl_s: 604800,
            login_rate_max: 5,
            login_rate_window_s: 60,
            storage: None,
        });

        // 1. Testa handler_stream_atendimentos
        let env_stream = Envelope {
            message_id: "mensagem_origem_123".to_string(),
            method: "StreamAtendimentos".to_string(),
            causation_id: "Bearer JWT_SECRETO_QUE_NAO_DEVE_VAZAR".to_string(), // jwt na borda
            ..Default::default()
        };
        let res_stream = handler_stream_atendimentos(deps.clone(), env_stream).await;
        assert_eq!(res_stream.method, "StreamAtendimentosReply");
        assert_eq!(res_stream.kind, MessageKind::Reply as i32);

        // 2. Testa handler_admin_forward
        let env_admin = Envelope {
            message_id: "mensagem_origem_456".to_string(),
            method: "ListCoreSettings".to_string(),
            causation_id: "Bearer JWT_SECRETO_QUE_NAO_DEVE_VAZAR".to_string(),
            ..Default::default()
        };
        let res_admin =
            handler_admin_forward(deps, env_admin, "ListCoreSettings", "ListCoreSettingsReply")
                .await;
        assert_eq!(res_admin.method, "ListCoreSettingsReply");
        assert_eq!(res_admin.kind, MessageKind::Reply as i32);

        pg_handle.abort();
        redis_handle.abort();
    }
}
