//! Serviço data_postgres: provê RPC síncrono e pub/sub assíncrono sujeito a políticas RLS.
//! Contém o Relay de Outbox e o Consumidor de Auditoria integrados.

use contracts::{Envelope, MessageKind};
use infrastructure_postgres::{inserir_audit_log, NewAuditLogEntry, RequestContext};
use redis::aio::ConnectionManager;
use redis::AsyncCommands;
use sqlx::PgPool;
use transport::Server;
use uuid::Uuid;

fn contexto_do_envelope(env: &Envelope) -> RequestContext {
    RequestContext {
        tenant_id: Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil()),
        user_id: env.auth_user_id,
        user_scopes: env.auth_scopes.clone(),
        flow_permissions: vec![],
    }
}

mod outbox_relay;
use outbox_relay::OutboxRelay;

#[derive(Clone)]
struct AppState {
    pool: PgPool,
    /// Pool administrativo (DATABASE_ADMIN_URL) com BYPASSRLS, mantido vivo após as
    /// migrations para servir consultas cross-tenant do superusuário operacional
    /// (ex.: AdminListAllConnectedInstances). `None` quando DATABASE_ADMIN_URL não
    /// está configurada — nesse caso o handler recai no pool de aplicação (RLS ativa).
    admin_pool: Option<PgPool>,
    redis_conn: ConnectionManager,
    cipher: std::sync::Arc<infrastructure_postgres::crypto::CipherManager>,
    config_cache: std::sync::Arc<infrastructure_postgres::TenantConfigCache>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // 1. Inicializa observabilidade
    observability::init_telemetry("data_postgres", "production")
        .map_err(|e| anyhow::anyhow!(e.to_string()))?;
    tracing::info!("Iniciando serviço data_postgres...");

    // 2. Conecta ao banco de dados e roda migrations.
    //    Migrations exigem DDL: rodam com o pool administrativo (DATABASE_ADMIN_URL)
    //    quando disponível; o runtime de negócio usa sempre o pool da aplicação
    //    (DATABASE_URL + RLS).
    let pool_config = infrastructure_postgres::PoolConfig::from_env("SMARTCORE_PG");
    let pool = infrastructure_postgres::criar_pool_config(pool_config).await?;
    // Mantemos o admin_pool vivo (não fechamos após as migrations): além do DDL, ele
    // é o único pool com BYPASSRLS e serve as consultas cross-tenant do superusuário
    // operacional em runtime (ex.: AdminListAllConnectedInstances).
    let admin_pool = if std::env::var("DATABASE_ADMIN_URL").is_ok() {
        let ap = infrastructure_postgres::criar_admin_pool(2).await?;
        infrastructure_postgres::inicializar_banco_dados(&ap).await?;
        Some(ap)
    } else {
        infrastructure_postgres::inicializar_banco_dados(&pool).await?;
        None
    };
    tracing::info!("Banco de dados PostgreSQL conectado e migrations executadas.");

    // Inicia monitoramento das métricas do pool PostgreSQL (M1)
    let metrics_interval_s = std::env::var("SMARTCORE_POOL_METRICS_INTERVAL_S")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(10u64);
    observability::monitorar_pool(
        pool.clone(),
        std::time::Duration::from_secs(metrics_interval_s),
    );

    // 3. Conecta ao Redis (Cache e Bus separados) com timeouts (P4)
    let redis_url =
        std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
    let redis_bus_url = std::env::var("REDIS_BUS_URL").unwrap_or_else(|_| redis_url.clone());

    // Conexão multiplexada para Publicação no Bus (REDIS_BUS_URL) com timeouts
    let bus_conn = infrastructure_redis::criar_conexao_com_timeouts(&redis_bus_url).await?;
    let bus_client = infrastructure_redis::criar_cliente(&redis_bus_url)?;
    tracing::info!("Conexão com Redis Cache e Redis Bus estabelecidas.");

    let cipher =
        std::sync::Arc::new(infrastructure_postgres::crypto::CipherManager::new_from_env()?);
    let config_cache = std::sync::Arc::new(infrastructure_postgres::TenantConfigCache::new(
        pool.clone(),
        cipher.clone(),
    ));

    let state = AppState {
        pool: pool.clone(),
        admin_pool: admin_pool.clone(),
        redis_conn: bus_conn.clone(),
        cipher,
        config_cache,
    };

    // 4. Inicia o Relay de Outbox em background
    let relay = OutboxRelay::new(pool.clone(), bus_conn.clone());
    let relay_handle = tokio::spawn(async move {
        if let Err(e) = relay.run().await {
            tracing::error!("Outbox Relay parou com erro crítico: {:?}", e);
        }
    });

    // 5. Inicia o Consumidor de Auditoria (Consolidação) em background
    let pool_clone = pool.clone();
    let audit_consumer = transport::bus::Consumer::new(
        transport::bus::STREAM_SEGURANCA,
        "data_postgres_audit_group",
        "data_postgres_audit_consumer",
        bus_client.clone(), // passa o Client para abrir conexão dedicada (C2)
    );
    let audit_handle = tokio::spawn(async move {
        if let Err(e) = audit_consumer
            .run_batch(move |evts| {
                let pool = pool_clone.clone();
                async move { processar_eventos_auditoria_lote(pool, evts).await }
            })
            .await
        {
            tracing::error!("Consumidor de auditoria parou com erro crítico: {:?}", e);
        }
    });

    // 5b. Reprocessamento periódico da PEL (a cada 60s) (C4)
    let pool_retry = pool.clone();
    let bus_client_retry = bus_client;
    tokio::spawn(async move {
        let mut tick = tokio::time::interval(std::time::Duration::from_secs(60));
        loop {
            tick.tick().await;
            let pool_c = pool_retry.clone();
            let handler = move |evts| {
                let pool = pool_c.clone();
                async move { processar_eventos_auditoria_lote(pool, evts).await }
            };
            if let Err(e) = transport::bus::reprocessar_pendentes_uma_vez_batch(
                &bus_client_retry,
                transport::bus::STREAM_SEGURANCA,
                "data_postgres_audit_group",
                "data_postgres_audit_consumer",
                handler,
            )
            .await
            {
                tracing::warn!("Falha no reprocessamento periódico da PEL: {:?}", e);
            }
        }
    });

    // 5c. Task periódica de amostragem de lag das filas (M4)
    let pool_lag = pool.clone();
    let bus_conn_lag = bus_conn.clone();

    use std::sync::atomic::AtomicU64;
    let atomic_bus_pending = std::sync::Arc::new(AtomicU64::new(0));
    let atomic_outbox_backlog = std::sync::Arc::new(AtomicU64::new(0));

    let meter_lag = observability::opentelemetry::global::meter("data_postgres");

    let bus_pending_gauge = atomic_bus_pending.clone();
    let _g_bus_pending = meter_lag
        .u64_observable_gauge("smartcore_bus_pending")
        .with_description("Mensagens pendentes na PEL do Redis bus")
        .with_callback(move |obs| {
            obs.observe(
                bus_pending_gauge.load(std::sync::atomic::Ordering::Relaxed),
                &[],
            );
        })
        .init();

    let outbox_backlog_gauge = atomic_outbox_backlog.clone();
    let _g_outbox_backlog = meter_lag
        .u64_observable_gauge("smartcore_outbox_backlog")
        .with_description("Mensagens acumuladas na tabela de outbox do PostgreSQL")
        .with_callback(move |obs| {
            obs.observe(
                outbox_backlog_gauge.load(std::sync::atomic::Ordering::Relaxed),
                &[],
            );
        })
        .init();

    tokio::spawn(async move {
        let mut con = bus_conn_lag;
        let mut tick = tokio::time::interval(std::time::Duration::from_secs(30));
        let _keep_alive = (_g_bus_pending, _g_outbox_backlog);
        loop {
            tick.tick().await;

            // 1. Coleta o lag da PEL do Redis
            let count: u64 = match con
                .xpending::<_, _, redis::streams::StreamPendingReply>(
                    transport::bus::STREAM_SEGURANCA,
                    "data_postgres_audit_group",
                )
                .await
            {
                Ok(reply) => reply.count() as u64,
                Err(e) => {
                    tracing::warn!("Falha ao ler XPENDING do Redis Bus: {:?}", e);
                    0
                }
            };
            atomic_bus_pending.store(count, std::sync::atomic::Ordering::Relaxed);

            // 2. Coleta o backlog de outbox do Postgres
            let query_res: Result<(i64,), sqlx::Error> =
                sqlx::query_as("SELECT count(*) FROM outbox WHERE published_at IS NULL")
                    .fetch_one(&pool_lag)
                    .await;

            let backlog = match query_res {
                Ok((val,)) => val as u64,
                Err(e) => {
                    tracing::warn!("Falha ao contar backlog da outbox no Postgres: {:?}", e);
                    0
                }
            };
            atomic_outbox_backlog.store(backlog, std::sync::atomic::Ordering::Relaxed);

            tracing::debug!(
                target: "metrics::lag",
                bus_pending = count,
                outbox_backlog = backlog,
                "amostra periodica de lag das filas coletada"
            );
        }
    });

    // 6. Inicia o Servidor RPC síncrono nos 3 protocolos
    let state_clone = state.clone();
    let state_for_get_thread = state_clone.clone();
    let state_for_persist = state_clone.clone();
    let state_for_verify = state_clone.clone();
    let state_for_upsert = state_clone.clone();
    let state_for_list = state_clone.clone();
    let state_for_create_tenant = state_clone.clone();
    let state_for_create_superuser = state_clone.clone();
    let state_for_list_superusers = state_clone.clone();
    let state_for_delete_superuser = state_clone.clone();
    let state_for_get_user_identity = state_clone.clone();
    let state_for_list_core_settings = state_clone.clone();
    let state_for_upsert_core_setting = state_clone.clone();
    let state_for_delete_core_setting = state_clone.clone();
    let state_for_get_tenant_config = state_clone.clone();
    let state_for_update_tenant_config = state_clone.clone();
    let state_for_list_tenants = state_clone.clone();
    let state_for_get_tenant = state_clone.clone();
    let state_for_update_tenant = state_clone.clone();
    let state_for_set_tenant_active = state_clone.clone();
    let state_for_generate_access_code = state_clone.clone();
    let state_for_list_plans = state_clone.clone();
    let state_for_create_plan = state_clone.clone();
    let state_for_update_plan = state_clone.clone();
    let state_for_list_subscriptions = state_clone.clone();
    let state_for_register_payment = state_clone.clone();
    let state_for_get_evolution_instance_by_tenant = state_clone.clone();
    let state_for_list_feature_flags = state_clone.clone();
    let state_for_set_feature_flag = state_clone.clone();
    let state_for_set_feature_flag_override = state_clone.clone();
    let state_for_query_audit_log = state_clone.clone();
    let state_for_list_payments = state_clone.clone();
    let state_for_get_service_health = state_clone.clone();
    let state_for_get_dashboard_summary = state_clone.clone();
    let state_for_export_tenants_csv = state_clone.clone();
    let state_for_create_whatsapp_instance_record = state_clone.clone();
    let state_for_get_whatsapp_instance = state_clone.clone();
    let state_for_list_whatsapp_instances = state_clone.clone();
    let state_for_admin_list_all_connected_instances = state_clone.clone();
    let state_for_admin_deletar_instancia = state_clone.clone();
    let state_for_atualizar_estado_instancia = state_clone.clone();
    let state_for_atualizar_instancia_provider_id = state_clone;

    let server = Server::from_env("DATA_POSTGRES")
        .route("GetThread", move |env| {
            let state = state_for_get_thread.clone();
            Box::pin(async move { handler_get_thread(state.pool, env).await })
        })
        .route("PersistMessage", move |env| {
            let state = state_for_persist.clone();
            Box::pin(async move { handler_persist_message(state.pool, env).await })
        })
        .route("VerifyCredentials", move |env| {
            let state = state_for_verify.clone();
            Box::pin(
                async move { handler_verify_credentials(state.pool, state.redis_conn, env).await },
            )
        })
        .route("UpsertContact", move |env| {
            let state = state_for_upsert.clone();
            Box::pin(async move { handler_upsert_contact(state.pool, env).await })
        })
        .route("ListAtendimentos", move |env| {
            let state = state_for_list.clone();
            Box::pin(async move { handler_list_atendimentos(state.pool, env).await })
        })
        .route("CreateTenant", move |env| {
            let state = state_for_create_tenant.clone();
            Box::pin(async move { handler_create_tenant(state.pool, state.redis_conn, env).await })
        })
        .route("CreateSuperuser", move |env| {
            let state = state_for_create_superuser.clone();
            Box::pin(
                async move { handler_create_superuser(state.pool, state.redis_conn, env).await },
            )
        })
        .route("ListSuperusers", move |env| {
            let state = state_for_list_superusers.clone();
            Box::pin(async move { handler_list_superusers(state.pool, env).await })
        })
        .route("DeleteSuperuser", move |env| {
            let state = state_for_delete_superuser.clone();
            Box::pin(
                async move { handler_delete_superuser(state.pool, state.redis_conn, env).await },
            )
        })
        .route("GetUserIdentity", move |env| {
            let state = state_for_get_user_identity.clone();
            Box::pin(async move { handler_get_user_identity(state.pool, env).await })
        })
        .route("ListCoreSettings", move |env| {
            let state = state_for_list_core_settings.clone();
            Box::pin(async move { handler_list_core_settings(state.pool, env).await })
        })
        .route("UpsertCoreSetting", move |env| {
            let state = state_for_upsert_core_setting.clone();
            Box::pin(async move {
                handler_upsert_core_setting(state.pool, state.cipher, state.redis_conn, env).await
            })
        })
        .route("DeleteCoreSetting", move |env| {
            let state = state_for_delete_core_setting.clone();
            Box::pin(
                async move { handler_delete_core_setting(state.pool, state.redis_conn, env).await },
            )
        })
        .route("GetTenantConfig", move |env| {
            let state = state_for_get_tenant_config.clone();
            Box::pin(async move { handler_get_tenant_config(state.pool, state.cipher, env).await })
        })
        .route("UpdateTenantConfig", move |env| {
            let state = state_for_update_tenant_config.clone();
            Box::pin(async move {
                handler_update_tenant_config(
                    state.pool,
                    state.cipher,
                    state.config_cache,
                    state.redis_conn,
                    env,
                )
                .await
            })
        })
        .route("ListTenants", move |env| {
            let state = state_for_list_tenants.clone();
            Box::pin(async move { handler_list_tenants(state.pool, env).await })
        })
        .route("GetTenant", move |env| {
            let state = state_for_get_tenant.clone();
            Box::pin(async move { handler_get_tenant(state.pool, env).await })
        })
        .route("UpdateTenant", move |env| {
            let state = state_for_update_tenant.clone();
            Box::pin(async move { handler_update_tenant(state.pool, state.redis_conn, env).await })
        })
        .route("SetTenantActive", move |env| {
            let state = state_for_set_tenant_active.clone();
            Box::pin(
                async move { handler_set_tenant_active(state.pool, state.redis_conn, env).await },
            )
        })
        .route("GenerateAccessCode", move |env| {
            let state = state_for_generate_access_code.clone();
            Box::pin(async move {
                handler_generate_access_code(state.pool, state.redis_conn, env).await
            })
        })
        .route("ListPlans", move |env| {
            let state = state_for_list_plans.clone();
            Box::pin(async move { handler_list_plans(state.pool, env).await })
        })
        .route("CreatePlan", move |env| {
            let state = state_for_create_plan.clone();
            Box::pin(async move { handler_create_plan(state.pool, state.redis_conn, env).await })
        })
        .route("UpdatePlan", move |env| {
            let state = state_for_update_plan.clone();
            Box::pin(async move { handler_update_plan(state.pool, state.redis_conn, env).await })
        })
        .route("ListSubscriptions", move |env| {
            let state = state_for_list_subscriptions.clone();
            Box::pin(async move { handler_list_subscriptions(state.pool, env).await })
        })
        .route("RegisterPayment", move |env| {
            let state = state_for_register_payment.clone();
            Box::pin(
                async move { handler_register_payment(state.pool, state.redis_conn, env).await },
            )
        })
        .route("ListPayments", move |env| {
            let state = state_for_list_payments.clone();
            Box::pin(async move { handler_list_payments(state.pool, env).await })
        })
        .route("GetEvolutionInstanceByTenant", move |env| {
            let state = state_for_get_evolution_instance_by_tenant.clone();
            Box::pin(async move { handler_get_evolution_instance_by_tenant(state.pool, env).await })
        })
        .route("ListFeatureFlags", move |env| {
            let state = state_for_list_feature_flags.clone();
            Box::pin(async move { handler_list_feature_flags(state.pool, env).await })
        })
        .route("SetFeatureFlag", move |env| {
            let state = state_for_set_feature_flag.clone();
            Box::pin(
                async move { handler_set_feature_flag(state.pool, state.redis_conn, env).await },
            )
        })
        .route("SetFeatureFlagOverride", move |env| {
            let state = state_for_set_feature_flag_override.clone();
            Box::pin(async move {
                handler_set_feature_flag_override(state.pool, state.redis_conn, env).await
            })
        })
        .route("QueryAuditLog", move |env| {
            let state = state_for_query_audit_log.clone();
            Box::pin(async move { handler_query_audit_log(state.pool, env).await })
        })
        .route("GetServiceHealth", move |env| {
            let state = state_for_get_service_health.clone();
            Box::pin(
                async move { handler_get_service_health(state.pool, state.redis_conn, env).await },
            )
        })
        .route("GetDashboardSummary", move |env| {
            let state = state_for_get_dashboard_summary.clone();
            Box::pin(async move {
                handler_get_dashboard_summary(state.pool, state.redis_conn, env).await
            })
        })
        .route("ExportTenantsCsv", move |env| {
            let state = state_for_export_tenants_csv.clone();
            Box::pin(async move { handler_export_tenants_csv(state.pool, env).await })
        })
        .route("CreateWhatsappInstanceRecord", move |env| {
            let state = state_for_create_whatsapp_instance_record.clone();
            Box::pin(async move { handler_create_whatsapp_instance_record(state.pool, env).await })
        })
        .route("GetWhatsappInstance", move |env| {
            let state = state_for_get_whatsapp_instance.clone();
            Box::pin(async move { handler_get_whatsapp_instance(state.pool, env).await })
        })
        .route("ListWhatsappInstances", move |env| {
            let state = state_for_list_whatsapp_instances.clone();
            Box::pin(async move { handler_list_whatsapp_instances(state.pool, env).await })
        })
        .route("AdminListAllConnectedInstances", move |env| {
            let state = state_for_admin_list_all_connected_instances.clone();
            Box::pin(async move {
                handler_admin_list_all_connected_instances(state.pool, state.admin_pool, env).await
            })
        })
        .route("AdminDeletarInstancia", move |env| {
            let state = state_for_admin_deletar_instancia.clone();
            Box::pin(async move { handler_admin_deletar_instancia(state.pool, env).await })
        })
        .route("AtualizarEstadoInstancia", move |env| {
            let state = state_for_atualizar_estado_instancia.clone();
            Box::pin(async move { handler_atualizar_estado_instancia(state.pool, env).await })
        })
        .route("AtualizarInstanciaProviderId", move |env| {
            let state = state_for_atualizar_instancia_provider_id.clone();
            Box::pin(async move { handler_atualizar_instancia_provider_id(state.pool, env).await })
        });

    tracing::info!("Servidor RPC configurado e pronto.");

    // Aguarda execução
    tokio::select! {
        res = server.run() => {
            if let Err(e) = res {
                tracing::error!("Servidor RPC parou com erro crítico: {:?}", e);
            }
        }
        _ = relay_handle => {}
        _ = audit_handle => {}
    }

    Ok(())
}

/// Consolida múltiplos eventos de auditoria vindos do barramento de segurança no banco de dados em lote.
/// Agrupa os eventos por inquilino e os insere sob uma transação por inquilino (ou transação global).
/// Retorna a lista de IDs de stream que foram gravados com sucesso.
async fn processar_eventos_auditoria_lote(
    pool: PgPool,
    eventos: Vec<transport::bus::EventoBruto>,
) -> anyhow::Result<Vec<String>> {
    use sqlx::Row;
    use std::collections::HashMap;

    let mut agrupamento_tenant: HashMap<Uuid, Vec<(String, NewAuditLogEntry)>> = HashMap::new();
    let mut globais: Vec<(String, NewAuditLogEntry)> = Vec::new();
    let mut sucessos = Vec::with_capacity(eventos.len());

    for evt in eventos {
        // Tentamos desserializar. Se der erro, descartamos o evento e marcamos como sucesso para receber XACK e não travar a fila.
        let envelope = match evt.desserializar::<observability::AuditLogPayload>() {
            Ok(env) => env,
            Err(e) => {
                tracing::error!(
                    "Falha ao desserializar evento de auditoria no lote (id={}): {:?}",
                    evt.stream_id,
                    e
                );
                sucessos.push(evt.stream_id);
                continue;
            }
        };

        let entry = NewAuditLogEntry {
            tenant_id: envelope.payload.tenant_id,
            level: envelope.payload.level,
            service: envelope.payload.service,
            trace_id: envelope.payload.trace_id,
            event: envelope.payload.event,
            message: envelope.payload.message,
            context: envelope.payload.context,
            user_id: envelope.payload.user_id,
            ip_address: envelope.payload.ip_address,
        };

        if let Some(tenant_id) = envelope.payload.tenant_id {
            agrupamento_tenant
                .entry(tenant_id)
                .or_default()
                .push((evt.stream_id, entry));
        } else {
            globais.push((evt.stream_id, entry));
        }
    }

    // 1. Processa inquilinos (1 transação por inquilino)
    for (tenant_id, entries) in agrupamento_tenant {
        let result = infrastructure_postgres::run_in_tenant_transaction(
            &pool,
            tenant_id,
            |mut tx| async move {
                let mut ids = Vec::new();
                for (stream_id, entry) in &entries {
                    match inserir_audit_log(&mut tx, entry).await {
                        Ok(_) => ids.push(stream_id.clone()),
                        Err(e) => {
                            // Se falhar a inserção de um log específico de auditoria, interrompe a transação
                            return Err(e);
                        }
                    }
                }
                Ok((ids, tx))
            },
        )
        .await;

        match result {
            Ok(ids) => {
                sucessos.extend(ids);
            }
            Err(e) => {
                tracing::error!(
                    "Falha na transação de auditoria para o tenant {}: {:?}",
                    tenant_id,
                    e
                );
            }
        }
    }

    // 2. Processa globais (1 transação global para bypass de RLS)
    if !globais.is_empty() {
        let tx_result: Result<Vec<String>, sqlx::Error> = async {
            let mut tx = pool.begin().await?;
            let mut ids = Vec::new();
            for (stream_id, entry) in &globais {
                let row = sqlx::query(
                    r#"
                    INSERT INTO audit_log (tenant_id, level, service, trace_id, event, message, context, user_id, ip_address)
                    VALUES (NULL, $1, $2, $3, $4, $5, $6, $7, $8)
                    RETURNING id
                    "#
                )
                .bind(&entry.level)
                .bind(&entry.service)
                .bind(&entry.trace_id)
                .bind(&entry.event)
                .bind(&entry.message)
                .bind(&entry.context)
                .bind(entry.user_id)
                .bind(&entry.ip_address)
                .fetch_one(&mut *tx)
                .await?;

                let _id: Uuid = row.get("id");
                ids.push(stream_id.clone());
            }
            tx.commit().await?;
            Ok(ids)
        }.await;

        match tx_result {
            Ok(ids) => {
                sucessos.extend(ids);
            }
            Err(e) => {
                tracing::error!(
                    "Falha ao consolidar logs de auditoria globais no Postgres: {:?}",
                    e
                );
            }
        }
    }

    Ok(sucessos)
}

/// Carrega a thread (mensagens) de um atendimento, respeitando o RLS do tenant.
async fn handler_get_thread(pool: PgPool, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let tenant_id = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());
    let atendimento_id = payload_json
        .get("atendimento_id")
        .and_then(|v| v.as_i64())
        .map(|v| v as i32)
        .unwrap_or(1);
    let limit = payload_json
        .get("limit")
        .and_then(|v| v.as_i64())
        .unwrap_or(50);
    let offset = payload_json
        .get("offset")
        .and_then(|v| v.as_i64())
        .unwrap_or(0);

    let ctx = contexto_do_envelope(&env);
    let repo = infrastructure_postgres::atendimentos::mensagens::PostgresMensagemRepository;

    let result =
        infrastructure_postgres::run_in_tenant_transaction(&pool, tenant_id, |mut tx| async move {
            use infrastructure_postgres::atendimentos::mensagens::MensagemRepository;
            let mensagens = repo
                .listar_por_atendimento(&mut tx, &ctx, atendimento_id, limit, offset)
                .await?;
            Ok((mensagens, tx))
        })
        .await;

    match result {
        Ok(mensagens) => {
            let reply = serde_json::json!({
                "atendimento_id": atendimento_id,
                "mensagens": mensagens,
            });
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "GetThreadReply".to_string(),
                payload: serde_json::to_vec(&reply).unwrap_or_default(),
                error: None,
                ..env
            }
        }
        Err(err) => {
            let app_err = error_core::AppError::Database(err.to_string());
            let err_env = app_err.to_error_envelope(&env.traceparent, "data_postgres");
            Envelope {
                kind: MessageKind::Error as i32,
                method: "GetThreadReply".to_string(),
                error: Some(err_env),
                ..env
            }
        }
    }
}

/// Lista atendimentos por status (snapshot de realtime), respeitando o RLS do tenant.
async fn handler_list_atendimentos(pool: PgPool, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let tenant_id = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());
    let status = payload_json
        .get("status")
        .and_then(|v| v.as_str())
        .unwrap_or("em_atendimento")
        .to_string();
    let departamento_id = payload_json
        .get("departamento_id")
        .and_then(|v| v.as_i64())
        .map(|v| v as i32);
    let limit = payload_json
        .get("limit")
        .and_then(|v| v.as_i64())
        .unwrap_or(50);

    let ctx = contexto_do_envelope(&env);
    let repo = infrastructure_postgres::atendimentos::atendimentos::PostgresAtendimentoRepository;

    let result =
        infrastructure_postgres::run_in_tenant_transaction(&pool, tenant_id, |mut tx| async move {
            use infrastructure_postgres::atendimentos::atendimentos::AtendimentoRepository;
            let atendimentos = repo
                .listar_por_status(&mut tx, &ctx, &status, departamento_id, limit)
                .await?;
            Ok((atendimentos, tx))
        })
        .await;

    match result {
        Ok(atendimentos) => {
            let reply = serde_json::json!({ "atendimentos": atendimentos });
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "ListAtendimentosReply".to_string(),
                payload: serde_json::to_vec(&reply).unwrap_or_default(),
                error: None,
                ..env
            }
        }
        Err(err) => {
            let app_err = error_core::AppError::Database(err.to_string());
            let err_env = app_err.to_error_envelope(&env.traceparent, "data_postgres");
            Envelope {
                kind: MessageKind::Error as i32,
                method: "ListAtendimentosReply".to_string(),
                error: Some(err_env),
                ..env
            }
        }
    }
}

/// Cria um novo tenant (operação administrativa do control_plane). A própria
/// `TenantRepository::criar` configura `app.current_tenant` para satisfazer o RLS.
async fn handler_create_tenant(
    pool: PgPool,
    mut redis_conn: ConnectionManager,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let name = payload_json
        .get("name")
        .and_then(|v| v.as_str())
        .unwrap_or("Novo Tenant")
        .to_string();
    let slug_in = payload_json
        .get("slug")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let slug = if slug_in.is_empty() {
        name.to_lowercase().replace(' ', "-")
    } else {
        slug_in
    };
    let email = payload_json
        .get("email")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());
    let phone = payload_json
        .get("phone")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());

    use infrastructure_postgres::tenants::tenants::{PostgresTenantRepository, TenantRepository};
    let repo = PostgresTenantRepository;

    let resultado: Result<_, infrastructure_postgres::DbError> = async {
        let mut tx = pool.begin().await?;
        let tenant = repo
            .criar(
                &mut tx,
                &name,
                &slug,
                None,
                email.as_deref(),
                phone.as_deref(),
            )
            .await?;
        tx.commit().await?;
        Ok(tenant)
    }
    .await;

    match resultado {
        Ok(tenant) => {
            // Auditoria obrigatória: criação de tenant é alteração cadastral sensível
            // (diretriz de segurança §4.2). O `context` registra apenas identificadores,
            // nunca segredos (a api_key gerada não entra no evento).
            publicar_auditoria(
                &mut redis_conn,
                &env,
                "tenant_created",
                format!("Tenant '{}' criado", name),
                serde_json::json!({ "id": tenant.id.to_string(), "name": name, "slug": slug }),
            )
            .await;

            let reply = serde_json::json!({ "status": "success", "tenant": tenant });
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "CreateTenantReply".to_string(),
                payload: serde_json::to_vec(&reply).unwrap_or_default(),
                error: None,
                ..env
            }
        }
        Err(err) => {
            let app_err = error_core::AppError::Database(err.to_string());
            let err_env = app_err.to_error_envelope(&env.traceparent, "data_postgres");
            Envelope {
                kind: MessageKind::Error as i32,
                method: "CreateTenantReply".to_string(),
                error: Some(err_env),
                ..env
            }
        }
    }
}

/// Cria o superusuário padrão do sistema (operação administrativa do control_plane).
///
/// `auth_user` é uma tabela **global, sem RLS**: usa o pool direto. A senha chega em
/// claro pelo Envelope (transporte local) e é **tratada aqui** (hash argon2id) antes
/// de gravar. Duplicidade de username/email devolve erro `Conflict` indicando o campo
/// em conflito. Ao criar, dispara um log de auditoria global.
async fn handler_create_superuser(
    pool: PgPool,
    mut redis_conn: ConnectionManager,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let username = payload_json
        .get("username")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .to_string();
    let email = payload_json
        .get("email")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let password = payload_json
        .get("password")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    // Validação de entrada (regra mínima do bootstrap).
    if username.is_empty() || password.chars().count() < 8 {
        let app_err = error_core::AppError::Validation(
            "username obrigatório e senha com ao menos 8 caracteres".to_string(),
        );
        let err_env = app_err.to_error_envelope(&env.traceparent, "data_postgres");
        return Envelope {
            kind: MessageKind::Error as i32,
            method: "CreateSuperuserReply".to_string(),
            error: Some(err_env),
            ..env
        };
    }

    use infrastructure_postgres::AuthUserRepository;
    let repo = infrastructure_postgres::PostgresAuthUserRepository;

    // Helper para responder erro mantendo o método de resposta.
    let erro = |app_err: error_core::AppError, env: &Envelope| -> Envelope {
        let err_env = app_err.to_error_envelope(&env.traceparent, "data_postgres");
        Envelope {
            kind: MessageKind::Error as i32,
            method: "CreateSuperuserReply".to_string(),
            error: Some(err_env),
            ..env.clone()
        }
    };

    // Duplicidade é um conflito explícito (erro), indicando QUAL campo já existe —
    // o username e o email têm UNIQUE no banco.
    match repo.buscar_por_username(&pool, &username).await {
        Ok(Some(_)) => {
            return erro(
                error_core::AppError::Conflict(format!(
                    "já existe um usuário com o username '{username}'"
                )),
                &env,
            );
        }
        Ok(None) => {}
        Err(err) => return erro(error_core::AppError::Database(err.to_string()), &env),
    }
    if !email.is_empty() {
        match repo.buscar_por_email(&pool, &email).await {
            Ok(Some(_)) => {
                return erro(
                    error_core::AppError::Conflict(format!(
                        "já existe um usuário com o email '{email}'"
                    )),
                    &env,
                );
            }
            Ok(None) => {}
            Err(err) => return erro(error_core::AppError::Database(err.to_string()), &env),
        }
    }

    // A senha em claro é tratada aqui (hash argon2id) — nunca é logada nem persistida.
    let hash = match infrastructure_postgres::hash_password_async(password.to_string()).await {
        Ok(h) => h,
        Err(err) => {
            let app_err = error_core::AppError::Internal(err.to_string());
            let err_env = app_err.to_error_envelope(&env.traceparent, "data_postgres");
            return Envelope {
                kind: MessageKind::Error as i32,
                method: "CreateSuperuserReply".to_string(),
                error: Some(err_env),
                ..env
            };
        }
    };

    // O último argumento (is_superuser) é `true`: cria com privilégio de superusuário.
    let user = match repo.criar(&pool, &username, &email, &hash, true).await {
        Ok(u) => u,
        Err(err) => {
            let app_err = error_core::AppError::Database(err.to_string());
            let err_env = app_err.to_error_envelope(&env.traceparent, "data_postgres");
            return Envelope {
                kind: MessageKind::Error as i32,
                method: "CreateSuperuserReply".to_string(),
                error: Some(err_env),
                ..env
            };
        }
    };

    tracing::info!(id = user.id, username = %user.username, "superusuário criado");

    // Auditoria global (sem tenant): publica no barramento de segurança; o consumidor
    // de auditoria deste mesmo serviço consolida em `audit_log` (bypass RLS).
    let audit_payload = observability::AuditLogPayload {
        tenant_id: None,
        level: "INFO".to_string(),
        service: "data_postgres".to_string(),
        trace_id: Some(env.traceparent.clone()),
        event: "superuser_created".to_string(),
        message: format!("Superusuário '{}' criado (id={})", user.username, user.id),
        context: serde_json::json!({ "username": user.username, "user_id": user.id }),
        user_id: Some(user.id),
        ip_address: None,
    };
    let envelope_auditoria =
        contracts::TenantEnvelope::novo(Uuid::nil(), "security.audit", audit_payload)
            .com_traceparent(env.traceparent.clone());
    if let Err(e) =
        transport::bus::publicar_evento_seguranca(&mut redis_conn, &envelope_auditoria).await
    {
        tracing::error!("Falha ao publicar auditoria de superuser_created: {:?}", e);
    }

    let reply = serde_json::json!({
        "status": "created",
        "id": user.id,
        "username": user.username,
        "email": user.email,
        "is_superuser": user.is_superuser,
    });
    Envelope {
        kind: MessageKind::Reply as i32,
        method: "CreateSuperuserReply".to_string(),
        payload: serde_json::to_vec(&reply).unwrap_or_default(),
        error: None,
        ..env
    }
}

/// Lista os superusuários do sistema (operação administrativa, tabela global).
async fn handler_list_superusers(pool: PgPool, env: Envelope) -> Envelope {
    use infrastructure_postgres::AuthUserRepository;
    let repo = infrastructure_postgres::PostgresAuthUserRepository;

    match repo.listar_superusers(&pool).await {
        Ok(usuarios) => {
            let lista: Vec<serde_json::Value> = usuarios
                .iter()
                .map(|u| {
                    serde_json::json!({
                        "id": u.id,
                        "username": u.username,
                        "email": u.email,
                        "is_active": u.is_active,
                    })
                })
                .collect();
            let reply = serde_json::json!({ "superusers": lista });
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "ListSuperusersReply".to_string(),
                payload: serde_json::to_vec(&reply).unwrap_or_default(),
                error: None,
                ..env
            }
        }
        Err(err) => {
            let app_err = error_core::AppError::Database(err.to_string());
            let err_env = app_err.to_error_envelope(&env.traceparent, "data_postgres");
            Envelope {
                kind: MessageKind::Error as i32,
                method: "ListSuperusersReply".to_string(),
                error: Some(err_env),
                ..env
            }
        }
    }
}

/// Exclui (hard delete) um superusuário pelo id (operação administrativa).
/// Só remove se o registro for de fato superusuário; dispara auditoria global.
async fn handler_delete_superuser(
    pool: PgPool,
    mut redis_conn: ConnectionManager,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let user_id = payload_json.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;

    let erro = |app_err: error_core::AppError, env: &Envelope| -> Envelope {
        let err_env = app_err.to_error_envelope(&env.traceparent, "data_postgres");
        Envelope {
            kind: MessageKind::Error as i32,
            method: "DeleteSuperuserReply".to_string(),
            error: Some(err_env),
            ..env.clone()
        }
    };

    if user_id <= 0 {
        return erro(
            error_core::AppError::Validation("id de superusuário inválido".to_string()),
            &env,
        );
    }

    use infrastructure_postgres::AuthUserRepository;
    let repo = infrastructure_postgres::PostgresAuthUserRepository;

    match repo.deletar_superuser(&pool, user_id).await {
        Ok(0) => erro(
            error_core::AppError::Conflict(format!(
                "nenhum superusuário com id {user_id} (ou o registro não é superusuário)"
            )),
            &env,
        ),
        Ok(_) => {
            tracing::info!(id = user_id, "superusuário excluído");

            // Auditoria global do evento de exclusão.
            let audit_payload = observability::AuditLogPayload {
                tenant_id: None,
                level: "WARN".to_string(),
                service: "data_postgres".to_string(),
                trace_id: Some(env.traceparent.clone()),
                event: "superuser_deleted".to_string(),
                message: format!("Superusuário id={user_id} excluído"),
                context: serde_json::json!({ "user_id": user_id }),
                user_id: Some(user_id),
                ip_address: None,
            };
            let envelope_auditoria =
                contracts::TenantEnvelope::novo(Uuid::nil(), "security.audit", audit_payload)
                    .com_traceparent(env.traceparent.clone());
            if let Err(e) =
                transport::bus::publicar_evento_seguranca(&mut redis_conn, &envelope_auditoria)
                    .await
            {
                tracing::error!("Falha ao publicar auditoria de superuser_deleted: {:?}", e);
            }

            let reply = serde_json::json!({ "status": "deleted", "id": user_id });
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "DeleteSuperuserReply".to_string(),
                payload: serde_json::to_vec(&reply).unwrap_or_default(),
                error: None,
                ..env
            }
        }
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_persist_message(pool: PgPool, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(_) => {
            let s = String::from_utf8_lossy(&env.payload);
            serde_json::json!({ "content": s })
        }
    };

    let tenant_id = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());
    let repo = infrastructure_postgres::atendimentos::mensagens::PostgresMensagemRepository;
    let ctx = contexto_do_envelope(&env);

    // Captura o traceparent da requisição para persistir no outbox e manter o trace
    // distribuído vivo até o relay republicar o evento no barramento.
    let traceparent = env.traceparent.clone();

    let result =
        infrastructure_postgres::run_in_tenant_transaction(&pool, tenant_id, |mut tx| async move {
            let atendimento_id = payload_json
                .get("atendimento_id")
                .and_then(|v| v.as_i64())
                .map(|v| v as i32)
                .unwrap_or(1);
            let conteudo = payload_json
                .get("content")
                .and_then(|v| v.as_str())
                .unwrap_or("Mensagem padrão");
            let tipo = payload_json
                .get("tipo")
                .and_then(|v| v.as_str())
                .unwrap_or("texto");
            let remetente = payload_json
                .get("sender_id")
                .and_then(|v| v.as_str())
                .unwrap_or("usuario");

            use infrastructure_postgres::atendimentos::mensagens::MensagemRepository;
            let msg = repo
                .criar(
                    &mut tx,
                    &ctx,
                    atendimento_id,
                    tipo,
                    conteudo,
                    remetente,
                    None,
                    None,
                )
                .await?;

            // Padrão OUTBOX: insere o evento de domínio na mesma transação ACID
            let event_payload = serde_json::json!({
                "message_id": msg.id.to_string(),
                "sender_id": msg.remetente,
                "content": msg.conteudo,
                "timestamp": msg.timestamp.timestamp_millis(),
            });
            let event_payload_bytes = serde_json::to_vec(&event_payload)
                .map_err(|e| infrastructure_postgres::DbError::ConfigError(e.to_string()))?;

            sqlx::query(
                "INSERT INTO outbox (tenant_id, event_type, payload, traceparent) VALUES ($1, $2, $3, $4)",
            )
            .bind(tenant_id)
            .bind("message.persisted")
            .bind(event_payload_bytes)
            .bind(&traceparent)
            .execute(&mut *tx)
            .await?;

            Ok((msg, tx))
        })
        .await;

    match result {
        Ok(msg) => {
            let reply_payload = serde_json::json!({
                "status": "success",
                "message_id": msg.id,
            });
            let payload_bytes = serde_json::to_vec(&reply_payload).unwrap_or_default();
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "PersistMessageReply".to_string(),
                payload: payload_bytes,
                error: None,
                ..env
            }
        }
        Err(err) => {
            let app_err = error_core::AppError::Database(err.to_string());
            let err_envelope = app_err.to_error_envelope(&env.traceparent, "data_postgres");
            Envelope {
                kind: MessageKind::Error as i32,
                method: "PersistMessageReply".to_string(),
                error: Some(err_envelope),
                ..env
            }
        }
    }
}

async fn handler_upsert_contact(pool: PgPool, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(_) => serde_json::json!({}),
    };

    let tenant_id = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());
    let repo = infrastructure_postgres::clientes::contatos::PostgresContatoRepository;
    let ctx = contexto_do_envelope(&env);

    let telefone = payload_json
        .get("phone")
        .and_then(|v| v.as_str())
        .unwrap_or("5511999999999");
    let nome = payload_json.get("name").and_then(|v| v.as_str());

    let result =
        infrastructure_postgres::run_in_tenant_transaction(&pool, tenant_id, |mut tx| async move {
            use infrastructure_postgres::clientes::contatos::ContatoRepository;
            let contato = repo.salvar(&mut tx, &ctx, telefone, nome).await?;
            Ok((contato, tx))
        })
        .await;

    match result {
        Ok(contato) => {
            let reply_payload = serde_json::to_vec(&contato).unwrap_or_default();
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "UpsertContactReply".to_string(),
                payload: reply_payload,
                ..env
            }
        }
        Err(err) => {
            let app_err = error_core::AppError::Database(err.to_string());
            let err_envelope = app_err.to_error_envelope(&env.traceparent, "data_postgres");
            Envelope {
                kind: MessageKind::Error as i32,
                method: "UpsertContactReply".to_string(),
                error: Some(err_envelope),
                ..env
            }
        }
    }
}

async fn handler_verify_credentials(
    pool: PgPool,
    mut redis_conn: ConnectionManager,
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

    use infrastructure_postgres::AuthUserRepository;
    let repo = infrastructure_postgres::PostgresAuthUserRepository;

    // Busca o usuário por e-mail ou username no banco
    let user_opt = match repo.buscar_por_email(&pool, email).await {
        Ok(Some(u)) => Ok(Some(u)),
        Ok(None) => repo.buscar_por_username(&pool, email).await,
        Err(err) => Err(err),
    };

    let user_opt = match user_opt {
        Ok(opt) => opt,
        Err(err) => {
            let app_err = error_core::AppError::Database(err.to_string());
            let err_env = app_err.to_error_envelope(&env.traceparent, "data_postgres");
            return Envelope {
                kind: MessageKind::Error as i32,
                method: "VerifyCredentialsReply".to_string(),
                error: Some(err_env),
                ..env
            };
        }
    };

    // Hash dummy computado uma única vez: quando o e-mail não existe, a verificação
    // roda contra ele mesmo assim, igualando o tempo de resposta ao caso de e-mail
    // existente (mitiga enumeração de e-mails por timing).
    static DUMMY_HASH: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let dummy_hash = DUMMY_HASH
        .get_or_init(|| {
            infrastructure_postgres::hash_password("senha_dummy_anti_timing").unwrap_or_default()
        })
        .clone();

    let login_sucesso = if let Some(user) = &user_opt {
        let senha_ok = infrastructure_postgres::verify_password_async(
            password.to_string(),
            user.password_hash.clone(),
        )
        .await;
        // Usuário desativado é rejeitado como credencial inválida (não revela o motivo).
        senha_ok && user.is_active
    } else {
        let _ =
            infrastructure_postgres::verify_password_async(password.to_string(), dummy_hash).await;
        false
    };

    if login_sucesso {
        let user = user_opt.unwrap();

        let mut tenant_id_str = String::new();
        let mut role = serde_json::Value::Null;
        let mut module_permissions = serde_json::Value::Null;

        // Se não for superusuário, precisamos obter a associação de tenant dele
        if !user.is_superuser {
            use infrastructure_postgres::tenants::tenants::TenantUserRepository;
            let tenant_user_repo =
                infrastructure_postgres::tenants::tenants::PostgresTenantUserRepository;
            match tenant_user_repo.buscar_por_user_id(&pool, user.id).await {
                Ok(Some(tu)) => {
                    // Se o vínculo estiver inativo, bloquear o login
                    if !tu.is_active {
                        let app_err =
                            error_core::AppError::Auth("vínculo inativo com o tenant".to_string());
                        let err_env = app_err.to_error_envelope(&env.traceparent, "data_postgres");
                        return Envelope {
                            kind: MessageKind::Error as i32,
                            method: "VerifyCredentialsReply".to_string(),
                            error: Some(err_env),
                            ..env
                        };
                    }
                    tenant_id_str = tu.tenant_id.to_string();
                    role = serde_json::Value::String(tu.role);
                    module_permissions = tu.module_permissions;
                }
                Ok(None) => {
                    let app_err =
                        error_core::AppError::Auth("usuário sem tenant associado".to_string());
                    let err_env = app_err.to_error_envelope(&env.traceparent, "data_postgres");
                    return Envelope {
                        kind: MessageKind::Error as i32,
                        method: "VerifyCredentialsReply".to_string(),
                        error: Some(err_env),
                        ..env
                    };
                }
                Err(err) => {
                    let app_err = error_core::AppError::Database(err.to_string());
                    let err_env = app_err.to_error_envelope(&env.traceparent, "data_postgres");
                    return Envelope {
                        kind: MessageKind::Error as i32,
                        method: "VerifyCredentialsReply".to_string(),
                        error: Some(err_env),
                        ..env
                    };
                }
            }
        }

        // Atualiza a data do último login em background
        let pool_clone = pool.clone();
        let user_id = user.id;
        tokio::spawn(async move {
            let _ = repo.atualizar_ultimo_login(&pool_clone, user_id).await;
        });

        let reply_payload = serde_json::json!({
            "id": user.id,
            "username": user.username,
            "email": user.email,
            "is_superuser": user.is_superuser,
            "tenant_id": tenant_id_str,
            "role": role,
            "module_permissions": module_permissions,
        });

        Envelope {
            kind: MessageKind::Reply as i32,
            method: "VerifyCredentialsReply".to_string(),
            payload: serde_json::to_vec(&reply_payload).unwrap_or_default(),
            error: None,
            ..env
        }
    } else {
        // Credenciais inválidas: dispara erros e publica evento de segurança
        let app_err = error_core::AppError::Auth("Credenciais inválidas".to_string());
        let err_env = app_err.to_error_envelope(&env.traceparent, "data_postgres");

        tracing::warn!(
            email = %email,
            traceparent = %env.traceparent,
            "Tentativa de login falhou: credenciais inválidas"
        );

        let tenant_id = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());
        let audit_payload = observability::AuditLogPayload {
            tenant_id: Some(tenant_id),
            level: "WARN".to_string(),
            service: "data_postgres".to_string(),
            trace_id: Some(env.traceparent.clone()),
            event: "login_failed".to_string(),
            message: format!("Tentativa de login falhou para o email: {}", email),
            context: serde_json::json!({ "email": email }),
            user_id: None,
            ip_address: None,
        };

        let envelope_auditoria =
            contracts::TenantEnvelope::novo(tenant_id, "security.audit", audit_payload)
                .com_traceparent(env.traceparent.clone());

        if let Err(e) =
            transport::bus::publicar_evento_seguranca(&mut redis_conn, &envelope_auditoria).await
        {
            tracing::error!(
                "Falha ao publicar evento de auditoria de login_failed: {:?}",
                e
            );
        }

        Envelope {
            kind: MessageKind::Error as i32,
            method: "VerifyCredentialsReply".to_string(),
            error: Some(err_env),
            ..env
        }
    }
}

// --- Helpers e Utilitários para os Handlers Admin ---

fn erro(app_err: error_core::AppError, env: &Envelope) -> Envelope {
    // Ponto único de saída de erro dos handlers admin: registra no tracing com
    // severidade e correlação (trace/tenant) antes de devolver o Envelope de erro.
    error_core::registrar(
        &app_err,
        &error_core::ErrorContext {
            trace_id: env.traceparent.clone(),
            tenant_id: env.tenant_id.clone(),
        },
    );
    let err_env = app_err.to_error_envelope(&env.traceparent, "data_postgres");
    Envelope {
        kind: MessageKind::Error as i32,
        method: format!("{}Reply", env.method),
        error: Some(err_env),
        ..env.clone()
    }
}

/// Resolve o tenant alvo de uma operação admin de configuração.
///
/// O interceptor da runtime_api zera o `tenant_id` do Envelope para superusuários
/// (claims > body), então o tenant a ser configurado é informado no payload
/// (`tenant_id`). Caímos no `tenant_id` do Envelope apenas quando o payload não o traz
/// (compatibilidade com chamadas tenant-scoped não-superusuário).
fn resolver_tenant_alvo(env: &Envelope, payload: &serde_json::Value) -> Uuid {
    if let Some(alvo) = payload
        .get("tenant_id")
        .and_then(|v| v.as_str())
        .and_then(|s| Uuid::parse_str(s).ok())
    {
        return alvo;
    }
    Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil())
}

fn ok_reply(env: &Envelope, method_reply: &str, payload: serde_json::Value) -> Envelope {
    Envelope {
        kind: MessageKind::Reply as i32,
        method: method_reply.to_string(),
        payload: serde_json::to_vec(&payload).unwrap_or_default(),
        error: None,
        ..env.clone()
    }
}

async fn publicar_auditoria(
    redis_conn: &mut ConnectionManager,
    env: &Envelope,
    event: &str,
    message: String,
    context: serde_json::Value,
) {
    let tenant_id = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());
    let audit_payload = observability::AuditLogPayload {
        tenant_id: Some(tenant_id),
        level: "WARN".to_string(),
        service: "data_postgres".to_string(),
        trace_id: Some(env.traceparent.clone()),
        event: event.to_string(),
        message,
        context,
        user_id: Some(env.auth_user_id),
        ip_address: None,
    };

    let envelope_auditoria =
        contracts::TenantEnvelope::novo(tenant_id, "security.audit", audit_payload)
            .com_traceparent(env.traceparent.clone());

    if let Err(e) = transport::bus::publicar_evento_seguranca(redis_conn, &envelope_auditoria).await
    {
        tracing::error!("Falha ao publicar auditoria de '{}': {:?}", event, e);
    }
}

// --- Novos Handlers Admin e Identidade ---

async fn handler_get_user_identity(pool: PgPool, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id = payload_json.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;

    use infrastructure_postgres::AuthUserRepository;
    let repo = infrastructure_postgres::PostgresAuthUserRepository;

    match repo.buscar_por_id(&pool, id).await {
        Ok(Some(user)) => {
            let mut tenant_id_str = String::new();
            let mut role = serde_json::Value::Null;
            let mut module_permissions = serde_json::Value::Null;

            if !user.is_superuser {
                use infrastructure_postgres::tenants::tenants::TenantUserRepository;
                let tenant_user_repo =
                    infrastructure_postgres::tenants::tenants::PostgresTenantUserRepository;
                if let Ok(Some(tu)) = tenant_user_repo.buscar_por_user_id(&pool, user.id).await {
                    tenant_id_str = tu.tenant_id.to_string();
                    role = serde_json::Value::String(tu.role);
                    module_permissions = tu.module_permissions;
                }
            }

            let reply = serde_json::json!({
                "id": user.id,
                "username": user.username,
                "email": user.email,
                "is_active": user.is_active,
                "is_superuser": user.is_superuser,
                "tenant_id": tenant_id_str,
                "role": role,
                "module_permissions": module_permissions,
            });
            ok_reply(&env, "GetUserIdentityReply", reply)
        }
        Ok(None) => erro(
            error_core::AppError::Auth("usuário não encontrado".to_string()),
            &env,
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_list_core_settings(pool: PgPool, env: Envelope) -> Envelope {
    let result = sqlx::query!(
        "SELECT key, value, encrypted, description FROM settings_manager_coresettings ORDER BY key"
    )
    .fetch_all(&pool)
    .await;

    match result {
        Ok(rows) => {
            let list: Vec<serde_json::Value> = rows
                .into_iter()
                .map(|row| {
                    let val_masked = if row.encrypted {
                        "••••••••".to_string()
                    } else {
                        row.value
                    };
                    serde_json::json!({
                        "key": row.key,
                        "value": val_masked,
                        "encrypted": row.encrypted,
                        "description": row.description,
                    })
                })
                .collect();

            ok_reply(
                &env,
                "ListCoreSettingsReply",
                serde_json::json!({ "settings": list }),
            )
        }
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_upsert_core_setting(
    pool: PgPool,
    cipher: std::sync::Arc<infrastructure_postgres::crypto::CipherManager>,
    mut redis_conn: ConnectionManager,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let key = payload_json
        .get("key")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let raw_value = payload_json
        .get("value")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let encrypted = payload_json
        .get("encrypted")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let description = payload_json
        .get("description")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    if key.is_empty() {
        return erro(
            error_core::AppError::Validation("chave não pode ser vazia".to_string()),
            &env,
        );
    }

    let final_value = if encrypted {
        match cipher.encrypt(raw_value.as_bytes()) {
            Ok((ct, nonce, tag)) => format!("{}:{}:{}", ct, nonce, tag),
            Err(err) => {
                return erro(
                    error_core::AppError::Internal(format!("erro de criptografia: {}", err)),
                    &env,
                )
            }
        }
    } else {
        raw_value.to_string()
    };

    match infrastructure_postgres::tenants::settings::upsert_setting(
        &pool,
        key,
        &final_value,
        encrypted,
        description,
    )
    .await
    {
        Ok(_) => {
            publicar_auditoria(
                &mut redis_conn,
                &env,
                "core_setting_upserted",
                format!("Configuração global '{}' cadastrada ou atualizada", key),
                serde_json::json!({ "key": key, "encrypted": encrypted }),
            )
            .await;

            ok_reply(
                &env,
                "UpsertCoreSettingReply",
                serde_json::json!({ "status": "success" }),
            )
        }
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_delete_core_setting(
    pool: PgPool,
    mut redis_conn: ConnectionManager,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let key = payload_json
        .get("key")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    if key.is_empty() {
        return erro(
            error_core::AppError::Validation("chave não pode ser vazia".to_string()),
            &env,
        );
    }

    let result = sqlx::query!(
        "DELETE FROM settings_manager_coresettings WHERE key = $1",
        key
    )
    .execute(&pool)
    .await;

    match result {
        Ok(res) => {
            if res.rows_affected() == 0 {
                return erro(
                    error_core::AppError::Validation("configuração inexistente".to_string()),
                    &env,
                );
            }

            publicar_auditoria(
                &mut redis_conn,
                &env,
                "core_setting_deleted",
                format!("Configuração global '{}' excluída", key),
                serde_json::json!({ "key": key }),
            )
            .await;

            ok_reply(
                &env,
                "DeleteCoreSettingReply",
                serde_json::json!({ "status": "success" }),
            )
        }
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_get_tenant_config(
    pool: PgPool,
    cipher: std::sync::Arc<infrastructure_postgres::crypto::CipherManager>,
    env: Envelope,
) -> Envelope {
    // O superusuário gerencia a config de um tenant ALVO informado no payload.
    // Como o interceptor zera o tenant_id do Envelope para superusuários (claims > body),
    // o tenant alvo precisa vir do payload; só recaímos no Envelope se ausente.
    let payload_json: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let tenant_id = resolver_tenant_alvo(&env, &payload_json);
    if tenant_id.is_nil() {
        return erro(
            error_core::AppError::Validation("tenant_id alvo não informado".to_string()),
            &env,
        );
    }

    let result = pool.begin().await;
    let mut tx = match result {
        Ok(tx) => tx,
        Err(err) => return erro(error_core::AppError::Database(err.to_string()), &env),
    };

    let set_rls = sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
        .bind(tenant_id.to_string())
        .execute(&mut *tx)
        .await;

    if let Err(err) = set_rls {
        return erro(error_core::AppError::Database(err.to_string()), &env);
    }

    let tc_row = sqlx::query!(
        r#"SELECT dados_empresa, persona_bot, bot_agent_name,
                  msg_fallback, msg_sem_info, msg_transferencia,
                  llm_class, model, llm_temperature,
                  transcription_provider, transcription_model,
                  vision_provider, vision_model,
                  embeddings_class, embeddings_model,
                  chunk_size, chunk_overlap,
                  similarity_threshold, vector_distance_threshold,
                  api_keys
           FROM tenants_tenantconfig
           WHERE tenant_id = $1"#,
        tenant_id
    )
    .fetch_optional(&mut *tx)
    .await;

    let _ = tx.commit().await;

    match tc_row {
        Ok(Some(row)) => {
            let mut api_keys_masked = serde_json::Map::new();
            for key_name in &["openai_api_key", "groq_api_key", "google_api_key"] {
                let val = cipher
                    .decrypt_from_jsonb(&row.api_keys, key_name)
                    .unwrap_or_default();
                let masked = if val.is_empty() {
                    ""
                } else {
                    "••••••••"
                };
                api_keys_masked.insert(
                    key_name.to_string(),
                    serde_json::Value::String(masked.to_string()),
                );
            }

            let reply = serde_json::json!({
                "dados_empresa": row.dados_empresa.unwrap_or_default(),
                "persona_bot": row.persona_bot.unwrap_or_default(),
                "bot_agent_name": row.bot_agent_name.unwrap_or_default(),
                "msg_fallback": row.msg_fallback.unwrap_or_default(),
                "msg_sem_info": row.msg_sem_info.unwrap_or_default(),
                "msg_transferencia": row.msg_transferencia.unwrap_or_default(),
                "llm_class": row.llm_class.unwrap_or_default(),
                "model": row.model.unwrap_or_default(),
                "llm_temperature": row.llm_temperature.unwrap_or_default(),
                "transcription_provider": row.transcription_provider.unwrap_or_default(),
                "transcription_model": row.transcription_model.unwrap_or_default(),
                "vision_provider": row.vision_provider.unwrap_or_default(),
                "vision_model": row.vision_model.unwrap_or_default(),
                "embeddings_class": row.embeddings_class.unwrap_or_default(),
                "embeddings_model": row.embeddings_model.unwrap_or_default(),
                "chunk_size": row.chunk_size.unwrap_or(0),
                "chunk_overlap": row.chunk_overlap.unwrap_or(0),
                "similarity_threshold": row.similarity_threshold.unwrap_or_default(),
                "vector_distance_threshold": row.vector_distance_threshold.unwrap_or_default(),
                "api_keys": serde_json::Value::Object(api_keys_masked),
            });

            ok_reply(&env, "GetTenantConfigReply", reply)
        }
        Ok(None) => ok_reply(&env, "GetTenantConfigReply", serde_json::json!({})),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_update_tenant_config(
    pool: PgPool,
    cipher: std::sync::Arc<infrastructure_postgres::crypto::CipherManager>,
    config_cache: std::sync::Arc<infrastructure_postgres::TenantConfigCache>,
    mut redis_conn: ConnectionManager,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    // Tenant alvo informado pelo superusuário no payload (ver handler_get_tenant_config).
    let tenant_id = resolver_tenant_alvo(&env, &payload_json);
    if tenant_id.is_nil() {
        return erro(
            error_core::AppError::Validation("tenant_id alvo não informado".to_string()),
            &env,
        );
    }

    let mut tx = match pool.begin().await {
        Ok(tx) => tx,
        Err(err) => return erro(error_core::AppError::Database(err.to_string()), &env),
    };

    if let Err(err) = sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
        .bind(tenant_id.to_string())
        .execute(&mut *tx)
        .await
    {
        return erro(error_core::AppError::Database(err.to_string()), &env);
    }

    let keys_existente_res = sqlx::query!(
        "SELECT api_keys FROM tenants_tenantconfig WHERE tenant_id = $1",
        tenant_id
    )
    .fetch_optional(&mut *tx)
    .await;

    let api_keys_atual = match keys_existente_res {
        Ok(Some(row)) => row.api_keys,
        _ => serde_json::Value::Object(Default::default()),
    };

    let mut novas_keys = serde_json::Map::new();
    // Coleta apenas os NOMES das chaves de API efetivamente alteradas, para auditoria
    // dedicada (`tenant_api_key_changed`). NUNCA registramos o valor, só o nome da chave.
    let mut chaves_alteradas: Vec<String> = Vec::new();
    if let Some(req_keys) = payload_json.get("api_keys").and_then(|v| v.as_object()) {
        for key_name in &["openai_api_key", "groq_api_key", "google_api_key"] {
            if let Some(val_str) = req_keys.get(*key_name).and_then(|v| v.as_str()) {
                if val_str == "••••••••" {
                    // Máscara enviada no update preserva o valor existente (sem alteração).
                    if let Some(existente) = api_keys_atual.get(*key_name) {
                        novas_keys.insert(key_name.to_string(), existente.clone());
                    }
                } else if val_str.is_empty() {
                    // Remoção da chave conta como alteração.
                    if api_keys_atual.get(*key_name).is_some_and(|v| !v.is_null()) {
                        chaves_alteradas.push(key_name.to_string());
                    }
                    novas_keys.insert(key_name.to_string(), serde_json::Value::Null);
                } else {
                    match cipher.encrypt(val_str.as_bytes()) {
                        Ok((ct, nonce, tag)) => {
                            let key_obj = serde_json::json!({
                                "ciphertext": ct,
                                "nonce": nonce,
                                "tag": tag
                            });
                            novas_keys.insert(key_name.to_string(), key_obj);
                            chaves_alteradas.push(key_name.to_string());
                        }
                        Err(err) => {
                            return erro(
                                error_core::AppError::Internal(format!(
                                    "erro ao cifrar chaves: {}",
                                    err
                                )),
                                &env,
                            )
                        }
                    }
                }
            }
        }
    }

    let dados_empresa = payload_json.get("dados_empresa").and_then(|v| v.as_str());
    let persona_bot = payload_json.get("persona_bot").and_then(|v| v.as_str());
    let bot_agent_name = payload_json.get("bot_agent_name").and_then(|v| v.as_str());
    let msg_fallback = payload_json.get("msg_fallback").and_then(|v| v.as_str());
    let msg_sem_info = payload_json.get("msg_sem_info").and_then(|v| v.as_str());
    let msg_transferencia = payload_json
        .get("msg_transferencia")
        .and_then(|v| v.as_str());
    let llm_class = payload_json.get("llm_class").and_then(|v| v.as_str());
    let model = payload_json.get("model").and_then(|v| v.as_str());

    let llm_temperature = payload_json
        .get("llm_temperature")
        .and_then(|v| v.as_str())
        .and_then(|s| s.parse::<rust_decimal::Decimal>().ok());
    let transcription_provider = payload_json
        .get("transcription_provider")
        .and_then(|v| v.as_str());
    let transcription_model = payload_json
        .get("transcription_model")
        .and_then(|v| v.as_str());
    let vision_provider = payload_json.get("vision_provider").and_then(|v| v.as_str());
    let vision_model = payload_json.get("vision_model").and_then(|v| v.as_str());
    let embeddings_class = payload_json
        .get("embeddings_class")
        .and_then(|v| v.as_str());
    let embeddings_model = payload_json
        .get("embeddings_model")
        .and_then(|v| v.as_str());

    let chunk_size = payload_json
        .get("chunk_size")
        .and_then(|v| v.as_i64())
        .map(|v| v as i32);
    let chunk_overlap = payload_json
        .get("chunk_overlap")
        .and_then(|v| v.as_i64())
        .map(|v| v as i32);

    let similarity_threshold = payload_json
        .get("similarity_threshold")
        .and_then(|v| v.as_str())
        .and_then(|s| s.parse::<rust_decimal::Decimal>().ok());
    let vector_distance_threshold = payload_json
        .get("vector_distance_threshold")
        .and_then(|v| v.as_str())
        .and_then(|s| s.parse::<rust_decimal::Decimal>().ok());

    let api_keys_json = serde_json::Value::Object(novas_keys);

    let query_res = sqlx::query!(
        r#"INSERT INTO tenants_tenantconfig (
            tenant_id, dados_empresa, persona_bot, bot_agent_name,
            msg_fallback, msg_sem_info, msg_transferencia,
            llm_class, model, llm_temperature,
            transcription_provider, transcription_model,
            vision_provider, vision_model,
            embeddings_class, embeddings_model,
            chunk_size, chunk_overlap,
            similarity_threshold, vector_distance_threshold,
            api_keys, updated_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, NOW())
        ON CONFLICT (tenant_id) DO UPDATE SET
            dados_empresa = COALESCE(EXCLUDED.dados_empresa, tenants_tenantconfig.dados_empresa),
            persona_bot = COALESCE(EXCLUDED.persona_bot, tenants_tenantconfig.persona_bot),
            bot_agent_name = COALESCE(EXCLUDED.bot_agent_name, tenants_tenantconfig.bot_agent_name),
            msg_fallback = COALESCE(EXCLUDED.msg_fallback, tenants_tenantconfig.msg_fallback),
            msg_sem_info = COALESCE(EXCLUDED.msg_sem_info, tenants_tenantconfig.msg_sem_info),
            msg_transferencia = COALESCE(EXCLUDED.msg_transferencia, tenants_tenantconfig.msg_transferencia),
            llm_class = COALESCE(EXCLUDED.llm_class, tenants_tenantconfig.llm_class),
            model = COALESCE(EXCLUDED.model, tenants_tenantconfig.model),
            llm_temperature = COALESCE(EXCLUDED.llm_temperature, tenants_tenantconfig.llm_temperature),
            transcription_provider = COALESCE(EXCLUDED.transcription_provider, tenants_tenantconfig.transcription_provider),
            transcription_model = COALESCE(EXCLUDED.transcription_model, tenants_tenantconfig.transcription_model),
            vision_provider = COALESCE(EXCLUDED.vision_provider, tenants_tenantconfig.vision_provider),
            vision_model = COALESCE(EXCLUDED.vision_model, tenants_tenantconfig.vision_model),
            embeddings_class = COALESCE(EXCLUDED.embeddings_class, tenants_tenantconfig.embeddings_class),
            embeddings_model = COALESCE(EXCLUDED.embeddings_model, tenants_tenantconfig.embeddings_model),
            chunk_size = COALESCE(EXCLUDED.chunk_size, tenants_tenantconfig.chunk_size),
            chunk_overlap = COALESCE(EXCLUDED.chunk_overlap, tenants_tenantconfig.chunk_overlap),
            similarity_threshold = COALESCE(EXCLUDED.similarity_threshold, tenants_tenantconfig.similarity_threshold),
            vector_distance_threshold = COALESCE(EXCLUDED.vector_distance_threshold, tenants_tenantconfig.vector_distance_threshold),
            api_keys = EXCLUDED.api_keys,
            updated_at = NOW()"#,
        tenant_id, dados_empresa, persona_bot, bot_agent_name,
        msg_fallback, msg_sem_info, msg_transferencia,
        llm_class, model, llm_temperature,
        transcription_provider, transcription_model,
        vision_provider, vision_model,
        embeddings_class, embeddings_model,
        chunk_size, chunk_overlap,
        similarity_threshold, vector_distance_threshold,
        api_keys_json
    )
    .execute(&mut *tx)
    .await;

    if let Err(err) = query_res {
        let _ = tx.rollback().await;
        return erro(error_core::AppError::Database(err.to_string()), &env);
    }

    if let Err(err) = tx.commit().await {
        return erro(error_core::AppError::Database(err.to_string()), &env);
    }

    config_cache.invalidate(&tenant_id);

    publicar_auditoria(
        &mut redis_conn,
        &env,
        "tenant_config_updated",
        "Configurações do tenant atualizadas".to_string(),
        serde_json::json!({}),
    )
    .await;

    // Evento dedicado e mais severo (WARN) quando chaves de API mudam (catálogo §12 +
    // diretriz de segurança §4.2). Registra apenas os NOMES das chaves, nunca os valores.
    if !chaves_alteradas.is_empty() {
        publicar_auditoria(
            &mut redis_conn,
            &env,
            "tenant_api_key_changed",
            "Chaves de API do tenant foram alteradas".to_string(),
            serde_json::json!({ "chaves_alteradas": chaves_alteradas }),
        )
        .await;
    }

    ok_reply(
        &env,
        "UpdateTenantConfigReply",
        serde_json::json!({ "status": "success" }),
    )
}

// --- FASE 2: Handlers de Tenants ---

async fn handler_list_tenants(pool: PgPool, env: Envelope) -> Envelope {
    use sqlx::Row;
    let result = sqlx::query(
        r#"SELECT id, name, slug, api_key, owner_id, email, phone, active, setup_completed, onboarding_step, access_code, created_at, updated_at
           FROM tenants_tenant ORDER BY name"#
    )
    .fetch_all(&pool)
    .await;

    match result {
        Ok(rows) => {
            let list: Vec<serde_json::Value> = rows
                .into_iter()
                .map(|row| {
                    let id: Uuid = row.get("id");
                    let name: String = row.get("name");
                    let slug: String = row.get("slug");
                    let api_key: String = row.get("api_key");
                    let owner_id: i32 = row.get("owner_id");
                    let email: String = row.get("email");
                    let phone: Option<String> = row.get("phone");
                    let active: bool = row.get("active");
                    let setup_completed: bool = row.get("setup_completed");
                    let onboarding_step: i32 = row.get("onboarding_step");
                    let access_code: Option<String> = row.get("access_code");
                    let created_at: chrono::DateTime<chrono::Utc> = row.get("created_at");
                    let updated_at: chrono::DateTime<chrono::Utc> = row.get("updated_at");

                    serde_json::json!({
                        "id": id.to_string(),
                        "name": name,
                        "slug": slug,
                        "api_key": api_key,
                        "owner_id": owner_id,
                        "email": email,
                        "phone": phone.unwrap_or_default(),
                        "active": active,
                        "setup_completed": setup_completed,
                        "onboarding_step": onboarding_step,
                        "access_code": access_code.unwrap_or_default(),
                        "created_at": created_at.timestamp_millis(),
                        "updated_at": updated_at.timestamp_millis(),
                    })
                })
                .collect();
            ok_reply(
                &env,
                "ListTenantsReply",
                serde_json::json!({ "tenants": list }),
            )
        }
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_get_tenant(pool: PgPool, env: Envelope) -> Envelope {
    use sqlx::Row;
    let payload_json: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id_str = payload_json
        .get("id")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let tenant_id = match Uuid::parse_str(id_str) {
        Ok(u) => u,
        Err(_) => {
            return erro(
                error_core::AppError::Validation("ID do tenant inválido".to_string()),
                &env,
            )
        }
    };

    let result = sqlx::query(
        r#"SELECT id, name, slug, api_key, owner_id, email, phone, active, setup_completed, onboarding_step, access_code, created_at, updated_at
           FROM tenants_tenant WHERE id = $1"#,
    )
    .bind(tenant_id)
    .fetch_optional(&pool)
    .await;

    match result {
        Ok(Some(row)) => {
            let id: Uuid = row.get("id");
            let name: String = row.get("name");
            let slug: String = row.get("slug");
            let api_key: String = row.get("api_key");
            let owner_id: i32 = row.get("owner_id");
            let email: String = row.get("email");
            let phone: Option<String> = row.get("phone");
            let active: bool = row.get("active");
            let setup_completed: bool = row.get("setup_completed");
            let onboarding_step: i32 = row.get("onboarding_step");
            let access_code: Option<String> = row.get("access_code");
            let created_at: chrono::DateTime<chrono::Utc> = row.get("created_at");
            let updated_at: chrono::DateTime<chrono::Utc> = row.get("updated_at");

            let tenant = serde_json::json!({
                "id": id.to_string(),
                "name": name,
                "slug": slug,
                "api_key": api_key,
                "owner_id": owner_id,
                "email": email,
                "phone": phone.unwrap_or_default(),
                "active": active,
                "setup_completed": setup_completed,
                "onboarding_step": onboarding_step,
                "access_code": access_code.unwrap_or_default(),
                "created_at": created_at.timestamp_millis(),
                "updated_at": updated_at.timestamp_millis(),
            });
            ok_reply(
                &env,
                "GetTenantReply",
                serde_json::json!({ "tenant": tenant }),
            )
        }
        Ok(None) => erro(
            error_core::AppError::Validation("Tenant não encontrado".to_string()),
            &env,
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_update_tenant(
    pool: PgPool,
    mut redis_conn: ConnectionManager,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id_str = payload_json
        .get("id")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let tenant_id = match Uuid::parse_str(id_str) {
        Ok(u) => u,
        Err(_) => {
            return erro(
                error_core::AppError::Validation("ID do tenant inválido".to_string()),
                &env,
            )
        }
    };
    let name = payload_json
        .get("name")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let slug = payload_json
        .get("slug")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let owner_id = payload_json
        .get("owner_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(1) as i32;
    let email = payload_json
        .get("email")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let phone = payload_json
        .get("phone")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());

    if name.is_empty() || slug.is_empty() {
        return erro(
            error_core::AppError::Validation("Nome e Slug não podem ser vazios".to_string()),
            &env,
        );
    }

    let result = sqlx::query(
        r#"UPDATE tenants_tenant
           SET name = $1, slug = $2, owner_id = $3, email = $4, phone = $5, updated_at = NOW()
           WHERE id = $6"#,
    )
    .bind(name)
    .bind(slug)
    .bind(owner_id)
    .bind(email)
    .bind(phone)
    .bind(tenant_id)
    .execute(&pool)
    .await;

    match result {
        Ok(res) => {
            if res.rows_affected() == 0 {
                return erro(
                    error_core::AppError::Validation("Tenant inexistente".to_string()),
                    &env,
                );
            }
            publicar_auditoria(
                &mut redis_conn,
                &env,
                "tenant_updated",
                format!("Cadastro do tenant '{}' atualizado", name),
                serde_json::json!({ "id": id_str, "name": name }),
            )
            .await;
            ok_reply(
                &env,
                "UpdateTenantReply",
                serde_json::json!({ "status": "success" }),
            )
        }
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_set_tenant_active(
    pool: PgPool,
    mut redis_conn: ConnectionManager,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id_str = payload_json
        .get("id")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let tenant_id = match Uuid::parse_str(id_str) {
        Ok(u) => u,
        Err(_) => {
            return erro(
                error_core::AppError::Validation("ID do tenant inválido".to_string()),
                &env,
            )
        }
    };
    let active = payload_json
        .get("active")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);

    let result =
        sqlx::query("UPDATE tenants_tenant SET active = $1, updated_at = NOW() WHERE id = $2")
            .bind(active)
            .bind(tenant_id)
            .execute(&pool)
            .await;

    match result {
        Ok(res) => {
            if res.rows_affected() == 0 {
                return erro(
                    error_core::AppError::Validation("Tenant inexistente".to_string()),
                    &env,
                );
            }
            let status_str = if active { "ativado" } else { "desativado" };
            publicar_auditoria(
                &mut redis_conn,
                &env,
                "tenant_active_changed",
                format!("Tenant '{}' foi {}", id_str, status_str),
                serde_json::json!({ "id": id_str, "active": active }),
            )
            .await;
            ok_reply(
                &env,
                "SetTenantActiveReply",
                serde_json::json!({ "status": "success" }),
            )
        }
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_generate_access_code(
    pool: PgPool,
    mut redis_conn: ConnectionManager,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id_str = payload_json
        .get("id")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let tenant_id = match Uuid::parse_str(id_str) {
        Ok(u) => u,
        Err(_) => {
            return erro(
                error_core::AppError::Validation("ID do tenant inválido".to_string()),
                &env,
            )
        }
    };

    let code = Uuid::new_v4().simple().to_string()[..20]
        .to_string()
        .to_uppercase();

    let result =
        sqlx::query("UPDATE tenants_tenant SET access_code = $1, updated_at = NOW() WHERE id = $2")
            .bind(&code)
            .bind(tenant_id)
            .execute(&pool)
            .await;

    match result {
        Ok(res) => {
            if res.rows_affected() == 0 {
                return erro(
                    error_core::AppError::Validation("Tenant inexistente".to_string()),
                    &env,
                );
            }
            publicar_auditoria(
                &mut redis_conn,
                &env,
                "tenant_access_code_generated",
                format!("Código de acesso do tenant '{}' gerado", id_str),
                serde_json::json!({ "id": id_str }),
            )
            .await;
            ok_reply(
                &env,
                "GenerateAccessCodeReply",
                serde_json::json!({ "access_code": code }),
            )
        }
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

// --- FASE 2: Handlers de Billing ---

async fn handler_list_plans(pool: PgPool, env: Envelope) -> Envelope {
    use sqlx::Row;
    let result = sqlx::query(
        "SELECT id, name, description, price, max_instances, max_departments, active, created_at FROM tenants_plan ORDER BY id"
    )
    .fetch_all(&pool)
    .await;

    match result {
        Ok(rows) => {
            let list: Vec<serde_json::Value> = rows
                .into_iter()
                .map(|row| {
                    let id: i32 = row.get("id");
                    let name: String = row.get("name");
                    let description: String = row.get("description");
                    let price: Option<rust_decimal::Decimal> = row.get("price");
                    let max_instances: i32 = row.get("max_instances");
                    let max_departments: i32 = row.get("max_departments");
                    let active: bool = row.get("active");
                    let created_at: chrono::DateTime<chrono::Utc> = row.get("created_at");

                    serde_json::json!({
                        "id": id,
                        "name": name,
                        "description": description,
                        "price": price.map(|p| p.to_string()).unwrap_or_default(),
                        "max_instances": max_instances,
                        "max_departments": max_departments,
                        "active": active,
                        "created_at": created_at.timestamp_millis(),
                    })
                })
                .collect();
            ok_reply(&env, "ListPlansReply", serde_json::json!({ "plans": list }))
        }
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_create_plan(
    pool: PgPool,
    mut redis_conn: ConnectionManager,
    env: Envelope,
) -> Envelope {
    use sqlx::Row;
    use std::str::FromStr;
    let payload_json: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let name = payload_json
        .get("name")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let description = payload_json
        .get("description")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let price_str = payload_json
        .get("price")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let max_instances = payload_json
        .get("max_instances")
        .and_then(|v| v.as_i64())
        .unwrap_or(1) as i32;
    let max_departments = payload_json
        .get("max_departments")
        .and_then(|v| v.as_i64())
        .unwrap_or(1) as i32;

    if name.is_empty() {
        return erro(
            error_core::AppError::Validation("Nome do plano não pode ser vazio".to_string()),
            &env,
        );
    }

    let price_dec = if !price_str.is_empty() {
        match rust_decimal::Decimal::from_str(price_str) {
            Ok(d) => Some(d),
            Err(e) => {
                return erro(
                    error_core::AppError::Validation(format!("Preço inválido: {}", e)),
                    &env,
                )
            }
        }
    } else {
        None
    };

    let result = sqlx::query(
        r#"INSERT INTO tenants_plan (name, description, price, max_instances, max_departments)
           VALUES ($1, $2, $3, $4, $5)
           RETURNING id, name, description, price, max_instances, max_departments, active, created_at"#,
    )
    .bind(name)
    .bind(description)
    .bind(price_dec)
    .bind(max_instances)
    .bind(max_departments)
    .fetch_one(&pool)
    .await;

    match result {
        Ok(row) => {
            publicar_auditoria(
                &mut redis_conn,
                &env,
                "billing_plan_created",
                format!("Plano de faturamento '{}' criado", name),
                serde_json::json!({ "id": row.get::<i32, _>("id"), "name": name }),
            )
            .await;

            let plan = serde_json::json!({
                "id": row.get::<i32, _>("id"),
                "name": row.get::<String, _>("name"),
                "description": row.get::<String, _>("description"),
                "price": row.get::<Option<rust_decimal::Decimal>, _>("price").map(|p| p.to_string()).unwrap_or_default(),
                "max_instances": row.get::<i32, _>("max_instances"),
                "max_departments": row.get::<i32, _>("max_departments"),
                "active": row.get::<bool, _>("active"),
                "created_at": row.get::<chrono::DateTime<chrono::Utc>, _>("created_at").timestamp_millis(),
            });

            ok_reply(&env, "CreatePlanReply", serde_json::json!({ "plan": plan }))
        }
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_update_plan(
    pool: PgPool,
    mut redis_conn: ConnectionManager,
    env: Envelope,
) -> Envelope {
    use std::str::FromStr;
    let payload_json: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id = payload_json.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
    let name = payload_json
        .get("name")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let description = payload_json
        .get("description")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let price_str = payload_json
        .get("price")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let max_instances = payload_json
        .get("max_instances")
        .and_then(|v| v.as_i64())
        .unwrap_or(1) as i32;
    let max_departments = payload_json
        .get("max_departments")
        .and_then(|v| v.as_i64())
        .unwrap_or(1) as i32;
    let active = payload_json
        .get("active")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);

    if id <= 0 || name.is_empty() {
        return erro(
            error_core::AppError::Validation("Dados do plano inválidos".to_string()),
            &env,
        );
    }

    let price_dec = if !price_str.is_empty() {
        match rust_decimal::Decimal::from_str(price_str) {
            Ok(d) => Some(d),
            Err(e) => {
                return erro(
                    error_core::AppError::Validation(format!("Preço inválido: {}", e)),
                    &env,
                )
            }
        }
    } else {
        None
    };

    let result = sqlx::query(
        r#"UPDATE tenants_plan
           SET name = $1, description = $2, price = $3, max_instances = $4, max_departments = $5, active = $6
           WHERE id = $7"#,
    )
    .bind(name)
    .bind(description)
    .bind(price_dec)
    .bind(max_instances)
    .bind(max_departments)
    .bind(active)
    .bind(id)
    .execute(&pool)
    .await;

    match result {
        Ok(res) => {
            if res.rows_affected() == 0 {
                return erro(
                    error_core::AppError::Validation("Plano inexistente".to_string()),
                    &env,
                );
            }
            publicar_auditoria(
                &mut redis_conn,
                &env,
                "billing_plan_updated",
                format!("Plano de faturamento '{}' atualizado", name),
                serde_json::json!({ "id": id, "name": name }),
            )
            .await;
            ok_reply(
                &env,
                "UpdatePlanReply",
                serde_json::json!({ "status": "success" }),
            )
        }
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_list_subscriptions(pool: PgPool, env: Envelope) -> Envelope {
    use sqlx::Row;
    let result = sqlx::query(
        r#"SELECT id, tenant_id, plan_id, status, current_period_start, current_period_end, payment_gateway, external_customer_id, external_subscription_id, updated_at
           FROM tenants_subscription ORDER BY id"#
    )
    .fetch_all(&pool)
    .await;

    match result {
        Ok(rows) => {
            let list: Vec<serde_json::Value> = rows
                .into_iter()
                .map(|row| {
                    let id: i32 = row.get("id");
                    let tenant_id: Uuid = row.get("tenant_id");
                    let plan_id: Option<i32> = row.get("plan_id");
                    let status: String = row.get("status");
                    let current_period_start: Option<chrono::DateTime<chrono::Utc>> = row.get("current_period_start");
                    let current_period_end: Option<chrono::DateTime<chrono::Utc>> = row.get("current_period_end");
                    let payment_gateway: String = row.get("payment_gateway");
                    let external_customer_id: String = row.get("external_customer_id");
                    let external_subscription_id: String = row.get("external_subscription_id");
                    let updated_at: chrono::DateTime<chrono::Utc> = row.get("updated_at");

                    serde_json::json!({
                        "id": id,
                        "tenant_id": tenant_id.to_string(),
                        "plan_id": plan_id.unwrap_or(0),
                        "status": status,
                        "current_period_start": current_period_start.map(|d| d.timestamp_millis()).unwrap_or(0),
                        "current_period_end": current_period_end.map(|d| d.timestamp_millis()).unwrap_or(0),
                        "payment_gateway": payment_gateway,
                        "external_customer_id": external_customer_id,
                        "external_subscription_id": external_subscription_id,
                        "updated_at": updated_at.timestamp_millis(),
                    })
                })
                .collect();
            ok_reply(
                &env,
                "ListSubscriptionsReply",
                serde_json::json!({ "subscriptions": list }),
            )
        }
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_register_payment(
    pool: PgPool,
    mut redis_conn: ConnectionManager,
    env: Envelope,
) -> Envelope {
    use sqlx::Row;
    use std::str::FromStr;
    let payload_json: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let tenant_id_str = payload_json
        .get("tenant_id")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let tenant_id = match Uuid::parse_str(tenant_id_str) {
        Ok(u) => u,
        Err(_) => {
            return erro(
                error_core::AppError::Validation("ID do tenant inválido".to_string()),
                &env,
            )
        }
    };
    let amount_str = payload_json
        .get("amount")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let payment_method = payload_json
        .get("payment_method")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let payment_date_str = payload_json
        .get("payment_date")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let period_start_str = payload_json
        .get("period_start")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let period_end_str = payload_json
        .get("period_end")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let notes = payload_json
        .get("notes")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    let amount = match rust_decimal::Decimal::from_str(amount_str) {
        Ok(d) => d,
        Err(e) => {
            return erro(
                error_core::AppError::Validation(format!("Valor do pagamento inválido: {}", e)),
                &env,
            )
        }
    };

    let payment_date = match chrono::NaiveDate::parse_from_str(payment_date_str, "%Y-%m-%d") {
        Ok(d) => d,
        Err(e) => {
            return erro(
                error_core::AppError::Validation(format!("Data de pagamento inválida: {}", e)),
                &env,
            )
        }
    };

    let period_start = match chrono::NaiveDate::parse_from_str(period_start_str, "%Y-%m-%d") {
        Ok(d) => d,
        Err(e) => {
            return erro(
                error_core::AppError::Validation(format!("Início do período inválido: {}", e)),
                &env,
            )
        }
    };

    let period_end = match chrono::NaiveDate::parse_from_str(period_end_str, "%Y-%m-%d") {
        Ok(d) => d,
        Err(e) => {
            return erro(
                error_core::AppError::Validation(format!("Fim do período inválido: {}", e)),
                &env,
            )
        }
    };

    let user_id = env.auth_user_id;

    let result = sqlx::query(
        r#"INSERT INTO tenants_paymentrecord (tenant_id, amount, payment_date, payment_method, period_start, period_end, notes, recorded_by_id)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
           RETURNING id, tenant_id, amount, payment_date, payment_method, period_start, period_end, notes, recorded_by_id, created_at"#,
    )
    .bind(tenant_id)
    .bind(amount)
    .bind(payment_date)
    .bind(payment_method)
    .bind(period_start)
    .bind(period_end)
    .bind(notes)
    .bind(if user_id > 0 { Some(user_id) } else { None })
    .fetch_one(&pool)
    .await;

    match result {
        Ok(row) => {
            publicar_auditoria(
                &mut redis_conn,
                &env,
                "payment_registered",
                format!(
                    "Pagamento de R$ {} registrado para o tenant '{}'",
                    amount, tenant_id_str
                ),
                serde_json::json!({ "tenant_id": tenant_id_str, "amount": amount.to_string() }),
            )
            .await;

            let payment = serde_json::json!({
                "id": row.get::<i32, _>("id"),
                "tenant_id": row.get::<Uuid, _>("tenant_id").to_string(),
                "amount": row.get::<rust_decimal::Decimal, _>("amount").to_string(),
                "payment_date": row.get::<chrono::NaiveDate, _>("payment_date").to_string(),
                "payment_method": row.get::<String, _>("payment_method"),
                "period_start": row.get::<chrono::NaiveDate, _>("period_start").to_string(),
                "period_end": row.get::<chrono::NaiveDate, _>("period_end").to_string(),
                "notes": row.get::<String, _>("notes"),
                "recorded_by_id": row.get::<Option<i32>, _>("recorded_by_id").unwrap_or(0),
                "created_at": row.get::<chrono::DateTime<chrono::Utc>, _>("created_at").timestamp_millis(),
            });

            ok_reply(
                &env,
                "RegisterPaymentReply",
                serde_json::json!({ "payment": payment }),
            )
        }
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_list_payments(pool: PgPool, env: Envelope) -> Envelope {
    use sqlx::Row;
    let payload_json: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let tenant_id_str = payload_json
        .get("tenant_id")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    let result = if !tenant_id_str.is_empty() {
        let tenant_id = match Uuid::parse_str(tenant_id_str) {
            Ok(u) => u,
            Err(_) => {
                return erro(
                    error_core::AppError::Validation("ID do tenant inválido".to_string()),
                    &env,
                )
            }
        };
        sqlx::query(
            r#"SELECT id, tenant_id, amount, payment_date, payment_method, period_start, period_end, notes, recorded_by_id, created_at
               FROM tenants_paymentrecord WHERE tenant_id = $1 ORDER BY payment_date DESC"#,
        )
        .bind(tenant_id)
        .fetch_all(&pool)
        .await
    } else {
        sqlx::query(
            r#"SELECT id, tenant_id, amount, payment_date, payment_method, period_start, period_end, notes, recorded_by_id, created_at
               FROM tenants_paymentrecord ORDER BY payment_date DESC"#
        )
        .fetch_all(&pool)
        .await
    };

    match result {
        Ok(rows) => {
            let list: Vec<serde_json::Value> = rows
                .into_iter()
                .map(|row| {
                    let id: i32 = row.get("id");
                    let tenant_id: Uuid = row.get("tenant_id");
                    let amount: rust_decimal::Decimal = row.get("amount");
                    let payment_date: chrono::NaiveDate = row.get("payment_date");
                    let payment_method: String = row.get("payment_method");
                    let period_start: chrono::NaiveDate = row.get("period_start");
                    let period_end: chrono::NaiveDate = row.get("period_end");
                    let notes: String = row.get("notes");
                    let recorded_by_id: Option<i32> = row.get("recorded_by_id");
                    let created_at: chrono::DateTime<chrono::Utc> = row.get("created_at");

                    serde_json::json!({
                        "id": id,
                        "tenant_id": tenant_id.to_string(),
                        "amount": amount.to_string(),
                        "payment_date": payment_date.to_string(),
                        "payment_method": payment_method,
                        "period_start": period_start.to_string(),
                        "period_end": period_end.to_string(),
                        "notes": notes,
                        "recorded_by_id": recorded_by_id.unwrap_or(0),
                        "created_at": created_at.timestamp_millis(),
                    })
                })
                .collect();
            ok_reply(
                &env,
                "ListPaymentsReply",
                serde_json::json!({ "payments": list }),
            )
        }
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_get_evolution_instance_by_tenant(pool: PgPool, env: Envelope) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let tenant_id_str = match payload.get("tenant_id").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("tenant_id ausente".to_string()),
                &env,
            )
        }
    };
    let tenant_uuid = match Uuid::parse_str(tenant_id_str) {
        Ok(u) => u,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let result = sqlx::query(
        "SELECT name, api_key FROM whatsapp_instance WHERE tenant_id = $1 AND active = true LIMIT 1"
    )
    .bind(tenant_uuid)
    .fetch_optional(&pool)
    .await;

    match result {
        Ok(Some(row)) => {
            use sqlx::Row;
            let name: String = row.get("name");
            let api_key: String = row.get("api_key");
            ok_reply(
                &env,
                "GetEvolutionInstanceByTenantReply",
                serde_json::json!({
                    "name": name,
                    "api_key": api_key
                }),
            )
        }
        Ok(None) => ok_reply(
            &env,
            "GetEvolutionInstanceByTenantReply",
            serde_json::json!({
                "name": "",
                "api_key": ""
            }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

async fn handler_list_feature_flags(pool: PgPool, env: Envelope) -> Envelope {
    let flags_res =
        sqlx::query("SELECT key, description, enabled_globally FROM feature_flags ORDER BY key")
            .fetch_all(&pool)
            .await;

    let overrides_res =
        sqlx::query("SELECT feature_key, tenant_id, enabled FROM feature_flag_overrides")
            .fetch_all(&pool)
            .await;

    match (flags_res, overrides_res) {
        (Ok(flags_rows), Ok(overrides_rows)) => {
            use sqlx::Row;
            use std::collections::HashMap;
            let mut overrides_map: HashMap<String, Vec<serde_json::Value>> = HashMap::new();
            for row in overrides_rows {
                let f_key: String = row.get("feature_key");
                let tenant_id: Uuid = row.get("tenant_id");
                let enabled: bool = row.get("enabled");
                overrides_map
                    .entry(f_key)
                    .or_default()
                    .push(serde_json::json!({
                        "tenant_id": tenant_id.to_string(),
                        "enabled": enabled,
                    }));
            }

            let flags_list: Vec<serde_json::Value> = flags_rows
                .into_iter()
                .map(|row| {
                    let key: String = row.get("key");
                    let description: String = row.get("description");
                    let enabled_globally: bool = row.get("enabled_globally");
                    let ovs = overrides_map.get(&key).cloned().unwrap_or_default();
                    serde_json::json!({
                        "key": key,
                        "description": description,
                        "enabled_globally": enabled_globally,
                        "overrides": ovs,
                    })
                })
                .collect();

            ok_reply(
                &env,
                "ListFeatureFlagsReply",
                serde_json::json!({ "flags": flags_list }),
            )
        }
        (Err(e), _) | (_, Err(e)) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

async fn handler_set_feature_flag(
    pool: PgPool,
    mut redis_conn: ConnectionManager,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let key = match payload.get("key").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("key ausente".to_string()),
                &env,
            )
        }
    };
    let enabled_globally = match payload.get("enabled_globally").and_then(|v| v.as_bool()) {
        Some(b) => b,
        None => {
            return erro(
                error_core::AppError::Validation("enabled_globally ausente".to_string()),
                &env,
            )
        }
    };

    let res = sqlx::query("UPDATE feature_flags SET enabled_globally = $1 WHERE key = $2")
        .bind(enabled_globally)
        .bind(key)
        .execute(&pool)
        .await;

    match res {
        Ok(_) => {
            let channel = format!("feature_flag:invalidate:{}", key);
            let _: Result<(), redis::RedisError> = redis::AsyncCommands::publish(
                &mut redis_conn,
                channel,
                enabled_globally.to_string(),
            )
            .await;

            // Auditoria obrigatória: toda mutação de feature flag gera evento (catálogo §12).
            // O `context` registra apenas a chave, o escopo e o novo valor — nunca segredos.
            publicar_auditoria(
                &mut redis_conn,
                &env,
                "feature_flag_set",
                format!(
                    "Feature flag global '{}' definida como {}",
                    key, enabled_globally
                ),
                serde_json::json!({
                    "flag_key": key,
                    "escopo": "global",
                    "enabled_globally": enabled_globally,
                }),
            )
            .await;

            ok_reply(
                &env,
                "SetFeatureFlagReply",
                serde_json::json!({ "success": true }),
            )
        }
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

async fn handler_set_feature_flag_override(
    pool: PgPool,
    mut redis_conn: ConnectionManager,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let key = match payload.get("key").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("key ausente".to_string()),
                &env,
            )
        }
    };
    let tenant_id_str = match payload.get("tenant_id").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("tenant_id ausente".to_string()),
                &env,
            )
        }
    };
    let tenant_uuid = match Uuid::parse_str(tenant_id_str) {
        Ok(u) => u,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let enabled = payload
        .get("enabled")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let remove_override = payload
        .get("remove_override")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    let res = if remove_override {
        sqlx::query("DELETE FROM feature_flag_overrides WHERE feature_key = $1 AND tenant_id = $2")
            .bind(key)
            .bind(tenant_uuid)
            .execute(&pool)
            .await
    } else {
        sqlx::query(
            "INSERT INTO feature_flag_overrides (feature_key, tenant_id, enabled) \
             VALUES ($1, $2, $3) \
             ON CONFLICT (feature_key, tenant_id) DO UPDATE SET enabled = EXCLUDED.enabled",
        )
        .bind(key)
        .bind(tenant_uuid)
        .bind(enabled)
        .execute(&pool)
        .await
    };

    match res {
        Ok(_) => {
            let channel = format!("feature_flag_override:invalidate:{}:{}", key, tenant_id_str);
            let val_str = if remove_override {
                "deleted".to_string()
            } else {
                enabled.to_string()
            };
            let _: Result<(), redis::RedisError> =
                redis::AsyncCommands::publish(&mut redis_conn, channel, val_str).await;

            // Auditoria obrigatória: override de feature flag por tenant também é mutação (catálogo §12).
            let descricao = if remove_override {
                format!(
                    "Override da feature flag '{}' removido do tenant '{}'",
                    key, tenant_id_str
                )
            } else {
                format!(
                    "Feature flag '{}' definida como {} para o tenant '{}'",
                    key, enabled, tenant_id_str
                )
            };
            publicar_auditoria(
                &mut redis_conn,
                &env,
                "feature_flag_set",
                descricao,
                serde_json::json!({
                    "flag_key": key,
                    "escopo": "tenant",
                    "tenant_id": tenant_id_str,
                    "enabled": enabled,
                    "remove_override": remove_override,
                }),
            )
            .await;

            ok_reply(
                &env,
                "SetFeatureFlagOverrideReply",
                serde_json::json!({ "success": true }),
            )
        }
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

async fn handler_query_audit_log(pool: PgPool, env: Envelope) -> Envelope {
    use sqlx::Row;
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let tenant_id_str = payload
        .get("tenant_id")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let event_type = payload
        .get("event_type")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let limit = payload.get("limit").and_then(|v| v.as_i64()).unwrap_or(50) as i32;
    let offset = payload.get("offset").and_then(|v| v.as_i64()).unwrap_or(0) as i32;

    let mut query_str = "SELECT id, tenant_id, timestamp, level, service, trace_id, event, message, context, user_id, ip_address FROM audit_log WHERE 1=1".to_string();
    let mut count_str = "SELECT COUNT(*) FROM audit_log WHERE 1=1".to_string();

    let mut bind_tenant = false;
    let mut tenant_uuid = Uuid::nil();
    if !tenant_id_str.is_empty() {
        if let Ok(u) = Uuid::parse_str(tenant_id_str) {
            tenant_uuid = u;
            query_str.push_str(" AND tenant_id = $1");
            count_str.push_str(" AND tenant_id = $1");
            bind_tenant = true;
        }
    }

    let mut bind_event = false;
    let mut event_index = 1;
    if bind_tenant {
        event_index = 2;
    }
    if !event_type.is_empty() {
        query_str.push_str(&format!(" AND event = ${}", event_index));
        count_str.push_str(&format!(" AND event = ${}", event_index));
        bind_event = true;
    }

    let limit_index = if bind_tenant && bind_event {
        3
    } else if bind_tenant || bind_event {
        2
    } else {
        1
    };
    let offset_index = limit_index + 1;
    query_str.push_str(&format!(
        " ORDER BY timestamp DESC LIMIT ${} OFFSET ${}",
        limit_index, offset_index
    ));

    let mut q = sqlx::query(sqlx::AssertSqlSafe(query_str));
    let mut c = sqlx::query(sqlx::AssertSqlSafe(count_str));

    if bind_tenant {
        q = q.bind(tenant_uuid);
        c = c.bind(tenant_uuid);
    }
    if bind_event {
        q = q.bind(event_type);
        c = c.bind(event_type);
    }

    q = q.bind(limit).bind(offset);

    let rows_res = q.fetch_all(&pool).await;
    let count_res = c.fetch_one(&pool).await;

    match (rows_res, count_res) {
        (Ok(rows), Ok(count_row)) => {
            let total_count: i64 = count_row.get(0);
            let list: Vec<serde_json::Value> = rows
                .into_iter()
                .map(|row| {
                    let id: Uuid = row.get("id");
                    let tenant_id: Option<Uuid> = row.get("tenant_id");
                    let timestamp: chrono::DateTime<chrono::Utc> = row.get("timestamp");
                    let level: String = row.get("level");
                    let service: String = row.get("service");
                    let trace_id: Option<String> = row.get("trace_id");
                    let event: String = row.get("event");
                    let message: String = row.get("message");
                    let context: serde_json::Value = row.get("context");
                    let user_id: Option<i32> = row.get("user_id");
                    let ip_address: Option<String> = row.get("ip_address");

                    serde_json::json!({
                        "id": id.to_string(),
                        "tenant_id": tenant_id.map(|u| u.to_string()).unwrap_or_default(),
                        "created_at": timestamp.timestamp_millis(),
                        "level": level,
                        "service": service,
                        "trace_id": trace_id.unwrap_or_default(),
                        "event_type": event,
                        "description": message,
                        "context": context,
                        "user_id": user_id.unwrap_or(0),
                        "ip_address": ip_address.unwrap_or_default(),
                    })
                })
                .collect();

            ok_reply(
                &env,
                "QueryAuditLogReply",
                serde_json::json!({
                    "entries": list,
                    "total_count": total_count as i32
                }),
            )
        }
        (Err(e), _) | (_, Err(e)) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

async fn handler_get_service_health(
    pool: PgPool,
    mut redis_conn: ConnectionManager,
    env: Envelope,
) -> Envelope {
    let mut services = Vec::new();

    // 1. Testar Postgres
    let start_pg = std::time::Instant::now();
    let pg_res = sqlx::query("SELECT 1").execute(&pool).await;
    let duration_pg = start_pg.elapsed().as_millis() as i64;
    let pg_health = if pg_res.is_ok() {
        serde_json::json!({
            "service_name": "PostgreSQL",
            "status": "healthy",
            "message": "Conectado com sucesso",
            "response_time_ms": duration_pg,
        })
    } else {
        serde_json::json!({
            "service_name": "PostgreSQL",
            "status": "unhealthy",
            "message": pg_res.err().unwrap().to_string(),
            "response_time_ms": duration_pg,
        })
    };
    services.push(pg_health);

    // 2. Testar Redis
    let start_redis = std::time::Instant::now();
    let redis_res: Result<String, redis::RedisError> =
        redis::cmd("PING").query_async(&mut redis_conn).await;
    let duration_redis = start_redis.elapsed().as_millis() as i64;
    let redis_health = if redis_res.is_ok() {
        serde_json::json!({
            "service_name": "Redis",
            "status": "healthy",
            "message": "Conectado com sucesso",
            "response_time_ms": duration_redis,
        })
    } else {
        serde_json::json!({
            "service_name": "Redis",
            "status": "unhealthy",
            "message": redis_res.err().unwrap().to_string(),
            "response_time_ms": duration_redis,
        })
    };
    services.push(redis_health);

    ok_reply(
        &env,
        "GetServiceHealthReply",
        serde_json::json!({ "services": services }),
    )
}

async fn handler_get_dashboard_summary(
    pool: PgPool,
    mut redis_conn: ConnectionManager,
    env: Envelope,
) -> Envelope {
    use sqlx::Row;

    let total_tenants_res = sqlx::query("SELECT COUNT(*) FROM tenants_tenant")
        .fetch_one(&pool)
        .await;

    let active_tenants_res = sqlx::query("SELECT COUNT(*) FROM tenants_tenant WHERE active = true")
        .fetch_one(&pool)
        .await;

    let total_subs_res =
        sqlx::query("SELECT COUNT(*) FROM tenants_subscription WHERE status = 'active'")
            .fetch_one(&pool)
            .await;

    let mrr_res = sqlx::query(
        "SELECT COALESCE(SUM(p.price), 0) FROM tenants_subscription s JOIN tenants_plan p ON s.plan_id = p.id WHERE s.status = 'active'"
    )
    .fetch_one(&pool)
    .await;

    match (
        total_tenants_res,
        active_tenants_res,
        total_subs_res,
        mrr_res,
    ) {
        (Ok(tt_row), Ok(at_row), Ok(ts_row), Ok(mrr_row)) => {
            let total_tenants: i64 = tt_row.get(0);
            let active_tenants: i64 = at_row.get(0);
            let total_subscriptions: i64 = ts_row.get(0);
            let mrr: rust_decimal::Decimal = mrr_row.get(0);

            let mut services = Vec::new();

            let start_pg = std::time::Instant::now();
            let pg_res = sqlx::query("SELECT 1").execute(&pool).await;
            let duration_pg = start_pg.elapsed().as_millis() as i64;
            services.push(serde_json::json!({
                "service_name": "PostgreSQL",
                "status": if pg_res.is_ok() { "healthy" } else { "unhealthy" },
                "message": pg_res.err().map(|e| e.to_string()).unwrap_or_else(|| "Conectado".to_string()),
                "response_time_ms": duration_pg,
            }));

            let start_redis = std::time::Instant::now();
            let redis_res: Result<String, redis::RedisError> =
                redis::cmd("PING").query_async(&mut redis_conn).await;
            let duration_redis = start_redis.elapsed().as_millis() as i64;
            services.push(serde_json::json!({
                "service_name": "Redis",
                "status": if redis_res.is_ok() { "healthy" } else { "unhealthy" },
                "message": redis_res.err().map(|e| e.to_string()).unwrap_or_else(|| "Conectado".to_string()),
                "response_time_ms": duration_redis,
            }));

            ok_reply(
                &env,
                "GetDashboardSummaryReply",
                serde_json::json!({
                    "total_tenants": total_tenants as i32,
                    "active_tenants": active_tenants as i32,
                    "total_subscriptions": total_subscriptions as i32,
                    "monthly_recurring_revenue": mrr.to_string(),
                    "health": services,
                }),
            )
        }
        (tt_err, at_err, ts_err, mrr_err) => {
            let err_msg = format!(
                "Erro ao carregar resumo do dashboard: tt={:?}, at={:?}, ts={:?}, mrr={:?}",
                tt_err.err(),
                at_err.err(),
                ts_err.err(),
                mrr_err.err()
            );
            erro(error_core::AppError::Database(err_msg), &env)
        }
    }
}

async fn handler_export_tenants_csv(pool: PgPool, env: Envelope) -> Envelope {
    use sqlx::Row;
    let result = sqlx::query(
        "SELECT id, name, slug, email, phone, active, created_at FROM tenants_tenant ORDER BY name",
    )
    .fetch_all(&pool)
    .await;

    match result {
        Ok(rows) => {
            let mut csv_string = String::new();
            csv_string.push_str("id,name,slug,email,phone,active,created_at\n");
            for row in rows {
                let id: Uuid = row.get("id");
                let name: String = row.get("name");
                let slug: String = row.get("slug");
                let email: String = row.get("email");
                let phone: Option<String> = row.get("phone");
                let active: bool = row.get("active");
                let created_at: chrono::DateTime<chrono::Utc> = row.get("created_at");

                let escaped_name = name.replace("\"", "\"\"");

                csv_string.push_str(&format!(
                    "{},\"{}\",{},{},{},{},{}\n",
                    id,
                    escaped_name,
                    slug,
                    email,
                    phone.unwrap_or_default(),
                    active,
                    created_at.to_rfc3339()
                ));
            }

            ok_reply(
                &env,
                "ExportTenantsCsvReply",
                serde_json::json!({
                    "csv_data": csv_string
                }),
            )
        }
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

async fn handler_create_whatsapp_instance_record(pool: PgPool, env: Envelope) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let name = match payload.get("name").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("name ausente".into()),
                &env,
            )
        }
    };

    let api_key = match payload.get("api_key").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("api_key ausente".into()),
                &env,
            )
        }
    };

    let provider = match payload.get("provider").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("provider ausente".into()),
                &env,
            )
        }
    };

    let tenant_id = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());
    let ctx = contexto_do_envelope(&env);
    let repo = infrastructure_postgres::integracoes::whatsapp::PostgresWhatsappInstanceRepository;

    let result =
        infrastructure_postgres::run_in_tenant_transaction(&pool, tenant_id, |mut tx| async move {
            use infrastructure_postgres::integracoes::whatsapp::WhatsappInstanceRepository;
            let inst = repo.criar(&mut tx, &ctx, name, api_key, provider).await?;
            Ok((inst, tx))
        })
        .await;

    match result {
        Ok(inst) => ok_reply(
            &env,
            "CreateWhatsappInstanceRecordReply",
            serde_json::to_value(&inst).unwrap_or_default(),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

async fn handler_get_whatsapp_instance(pool: PgPool, env: Envelope) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let id = match payload.get("id").and_then(|v| v.as_i64()) {
        Some(i) => i as i32,
        None => return erro(error_core::AppError::Validation("id ausente".into()), &env),
    };

    let tenant_id = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());
    let ctx = contexto_do_envelope(&env);
    let repo = infrastructure_postgres::integracoes::whatsapp::PostgresWhatsappInstanceRepository;

    let result =
        infrastructure_postgres::run_in_tenant_transaction(&pool, tenant_id, |mut tx| async move {
            use infrastructure_postgres::integracoes::whatsapp::WhatsappInstanceRepository;
            let inst = repo.buscar_por_id(&mut tx, &ctx, id).await?;
            Ok((inst, tx))
        })
        .await;

    match result {
        Ok(Some(inst)) => ok_reply(
            &env,
            "GetWhatsappInstanceReply",
            serde_json::to_value(&inst).unwrap_or_default(),
        ),
        Ok(None) => erro(
            error_core::AppError::Database("não encontrado: Instância não encontrada".into()),
            &env,
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

async fn handler_list_whatsapp_instances(pool: PgPool, env: Envelope) -> Envelope {
    let tenant_id = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());
    let ctx = contexto_do_envelope(&env);
    let repo = infrastructure_postgres::integracoes::whatsapp::PostgresWhatsappInstanceRepository;

    let result =
        infrastructure_postgres::run_in_tenant_transaction(&pool, tenant_id, |mut tx| async move {
            use infrastructure_postgres::integracoes::whatsapp::WhatsappInstanceRepository;
            let list = repo.listar_ativas(&mut tx, &ctx).await?;
            Ok((list, tx))
        })
        .await;

    match result {
        Ok(list) => ok_reply(
            &env,
            "ListWhatsappInstancesReply",
            serde_json::json!({ "instances": list }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

async fn handler_admin_list_all_connected_instances(
    pool: PgPool,
    admin_pool: Option<PgPool>,
    env: Envelope,
) -> Envelope {
    let ctx = contexto_do_envelope(&env);
    let repo = infrastructure_postgres::integracoes::whatsapp::PostgresWhatsappInstanceRepository;

    // A consulta cross-tenant exige BYPASSRLS: usamos o admin_pool quando disponível.
    // Sem ele, recaímos no pool de aplicação (RLS ativa) e a query retorna 0 linhas —
    // por isso registramos um aviso para tornar a degradação observável.
    if admin_pool.is_none() {
        tracing::warn!(
            "AdminListAllConnectedInstances sem DATABASE_ADMIN_URL: a RLS bloqueará a \
             consulta cross-tenant e a lista virá vazia"
        );
    }
    let effective_pool = admin_pool.as_ref().unwrap_or(&pool);

    let result: Result<Vec<_>, infrastructure_postgres::DbError> = async {
        let mut tx = effective_pool.begin().await?;
        use infrastructure_postgres::integracoes::whatsapp::WhatsappInstanceRepository;
        let list = repo.admin_listar_todas_conectadas(&mut tx, &ctx).await?;
        tx.commit().await?;
        Ok(list)
    }
    .await;

    match result {
        Ok(list) => ok_reply(
            &env,
            "AdminListAllConnectedInstancesReply",
            serde_json::json!({ "instances": list }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

async fn handler_admin_deletar_instancia(pool: PgPool, env: Envelope) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let id = match payload.get("id").and_then(|v| v.as_i64()) {
        Some(i) => i as i32,
        None => return erro(error_core::AppError::Validation("id ausente".into()), &env),
    };

    let tenant_id = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());
    let ctx = contexto_do_envelope(&env);
    let repo = infrastructure_postgres::integracoes::whatsapp::PostgresWhatsappInstanceRepository;

    let result =
        infrastructure_postgres::run_in_tenant_transaction(&pool, tenant_id, |mut tx| async move {
            use infrastructure_postgres::integracoes::whatsapp::WhatsappInstanceRepository;
            repo.admin_deletar_instancia(&mut tx, &ctx, id).await?;
            Ok(((), tx))
        })
        .await;

    match result {
        Ok(_) => ok_reply(
            &env,
            "AdminDeletarInstanciaReply",
            serde_json::json!({ "status": "success" }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

async fn handler_atualizar_estado_instancia(pool: PgPool, env: Envelope) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let id = match payload.get("id").and_then(|v| v.as_i64()) {
        Some(i) => i as i32,
        None => return erro(error_core::AppError::Validation("id ausente".into()), &env),
    };

    let connection_state = match payload.get("connection_state").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("connection_state ausente".into()),
                &env,
            )
        }
    };

    let tenant_id = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());
    let ctx = contexto_do_envelope(&env);
    let repo = infrastructure_postgres::integracoes::whatsapp::PostgresWhatsappInstanceRepository;

    let result =
        infrastructure_postgres::run_in_tenant_transaction(&pool, tenant_id, |mut tx| async move {
            use infrastructure_postgres::integracoes::whatsapp::WhatsappInstanceRepository;
            repo.atualizar_estado(&mut tx, &ctx, id, connection_state)
                .await?;
            Ok(((), tx))
        })
        .await;

    match result {
        Ok(_) => ok_reply(
            &env,
            "AtualizarEstadoInstanciaReply",
            serde_json::json!({ "status": "success" }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

async fn handler_atualizar_instancia_provider_id(pool: PgPool, env: Envelope) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let id = match payload.get("id").and_then(|v| v.as_i64()) {
        Some(i) => i as i32,
        None => return erro(error_core::AppError::Validation("id ausente".into()), &env),
    };

    let instance_id = match payload.get("instance_id").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("instance_id ausente".into()),
                &env,
            )
        }
    };

    let phone_number = payload.get("phone_number").and_then(|v| v.as_str());

    let tenant_id = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());
    let ctx = contexto_do_envelope(&env);
    let repo = infrastructure_postgres::integracoes::whatsapp::PostgresWhatsappInstanceRepository;

    let result =
        infrastructure_postgres::run_in_tenant_transaction(&pool, tenant_id, |mut tx| async move {
            use infrastructure_postgres::integracoes::whatsapp::WhatsappInstanceRepository;
            repo.atualizar_instancia_provider_id(&mut tx, &ctx, id, instance_id, phone_number)
                .await?;
            Ok(((), tx))
        })
        .await;

    match result {
        Ok(_) => ok_reply(
            &env,
            "AtualizarInstanciaProviderIdReply",
            serde_json::json!({ "status": "success" }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    async fn processar_evento_auditoria(
        pool: PgPool,
        evt: transport::bus::EventoBruto,
    ) -> anyhow::Result<()> {
        let _ = processar_eventos_auditoria_lote(pool, vec![evt]).await?;
        Ok(())
    }
    use contracts::{Envelope, MessageKind};
    use redis::aio::ConnectionManager;
    use sqlx::PgPool;
    use uuid::Uuid;

    fn carregar_env_teste() {
        test_support::ensure_tunnel();
        let caminhos = vec![
            ".env",
            "../.env",
            "../../.env",
            "apps/data_postgres/.env",
            "../data_postgres/.env",
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

    async fn setup_teste() -> (PgPool, ConnectionManager) {
        carregar_env_teste();
        let admin_url = std::env::var("DATABASE_ADMIN_URL").expect("DATABASE_ADMIN_URL ausente");
        let pool = PgPool::connect(&admin_url)
            .await
            .expect("Falha ao conectar Postgres");

        infrastructure_postgres::inicializar_banco_dados(&pool)
            .await
            .unwrap();

        semear_auth_user_padrao(&pool).await;

        let redis_url = std::env::var("REDIS_BUS_URL")
            .or_else(|_| std::env::var("REDIS_URL"))
            .unwrap_or_else(|_| "redis://127.0.0.1:6380".to_string());
        let redis_client = redis::Client::open(redis_url).unwrap();
        let redis_conn = ConnectionManager::new(redis_client).await.unwrap();

        (pool, redis_conn)
    }

    /// Garante o `auth_user` id=1 — owner padrão usado pelos fixtures de tenant
    /// (vários testes inserem `tenants_tenant.owner_id = 1`). Idempotente: no banco
    /// compartilhado o usuário já existe; no banco limpo do CI é criado aqui. A
    /// sequence do SERIAL é avançada para não colidir com inserts de id automático.
    async fn semear_auth_user_padrao(pool: &PgPool) {
        sqlx::query(
            "INSERT INTO auth_user (id, username, email, password_hash, is_superuser, is_staff) \
             VALUES (1, 'ci_seed_admin', 'ci-seed@local', '', TRUE, TRUE) \
             ON CONFLICT (id) DO NOTHING",
        )
        .execute(pool)
        .await
        .expect("falha ao semear auth_user padrão");

        sqlx::query(
            "SELECT setval(pg_get_serial_sequence('auth_user','id'), \
             GREATEST((SELECT COALESCE(MAX(id), 1) FROM auth_user), 1))",
        )
        .execute(pool)
        .await
        .expect("falha ao ajustar a sequence de auth_user");
    }

    #[tokio::test]
    async fn test_handler_create_tenant() {
        let (pool, redis_conn) = setup_teste().await;

        let tenant_name = format!("Tenant Teste {}", Uuid::new_v4());
        let payload = serde_json::json!({
            "name": tenant_name,
            "slug": format!("slug-{}", Uuid::new_v4()),
            "email": "tenant@teste.com",
            "phone": "5511999999999",
        });

        let req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: "".to_string(),
            traceparent: "00-trace1-span1-01".to_string(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "CreateTenant".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            error: None,
            ..Default::default()
        };

        let resp = handler_create_tenant(pool.clone(), redis_conn, req).await;
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        assert_eq!(resp.method, "CreateTenantReply");

        let resp_payload: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(
            resp_payload.get("status").unwrap().as_str().unwrap(),
            "success"
        );

        let tenant_json = resp_payload.get("tenant").unwrap();
        let tenant_id_str = tenant_json.get("id").unwrap().as_str().unwrap();
        let tenant_id = Uuid::parse_str(tenant_id_str).unwrap();

        // Limpeza
        sqlx::query("DELETE FROM tenants_tenant WHERE id = $1")
            .bind(tenant_id)
            .execute(&pool)
            .await
            .unwrap();
    }

    #[tokio::test]
    async fn test_handler_verify_credentials() {
        let (pool, redis_conn) = setup_teste().await;

        use infrastructure_postgres::AuthUserRepository;
        let auth_repo = infrastructure_postgres::PostgresAuthUserRepository;
        let test_username = format!("user_{}", Uuid::new_v4().to_string().replace('-', ""));
        let test_email = format!("teste_{}@auth.com", Uuid::new_v4());
        let hash = infrastructure_postgres::hash_password("minhasenha123").unwrap();

        let user = auth_repo
            .criar(&pool, &test_username, &test_email, &hash, true)
            .await
            .expect("Erro ao criar usuário");

        // 1. Testa credenciais válidas
        let payload_valido = serde_json::json!({
            "email": test_email,
            "password": "minhasenha123",
        });
        let req_valido = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: "".to_string(),
            traceparent: "00-trace2-span2-01".to_string(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "VerifyCredentials".to_string(),
            payload: serde_json::to_vec(&payload_valido).unwrap(),
            error: None,
            ..Default::default()
        };

        let resp_valido =
            handler_verify_credentials(pool.clone(), redis_conn.clone(), req_valido).await;
        assert_eq!(resp_valido.kind, MessageKind::Reply as i32);
        let resp_valido_payload: serde_json::Value =
            serde_json::from_slice(&resp_valido.payload).unwrap();
        assert_eq!(
            resp_valido_payload.get("id").unwrap().as_i64().unwrap(),
            user.id as i64
        );

        // 2. Testa credenciais inválidas
        let payload_invalido = serde_json::json!({
            "email": test_email,
            "password": "senha_errada",
        });
        let req_invalido = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: "".to_string(),
            traceparent: "00-trace2-span2-01".to_string(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "VerifyCredentials".to_string(),
            payload: serde_json::to_vec(&payload_invalido).unwrap(),
            error: None,
            ..Default::default()
        };

        let resp_invalido =
            handler_verify_credentials(pool.clone(), redis_conn.clone(), req_invalido).await;
        assert_eq!(resp_invalido.kind, MessageKind::Error as i32);
        assert!(resp_invalido.error.is_some());

        // Limpeza
        sqlx::query("DELETE FROM auth_user WHERE id = $1")
            .bind(user.id)
            .execute(&pool)
            .await
            .unwrap();
    }

    #[tokio::test]
    async fn test_handler_verify_credentials_usuario_desativado() {
        let (pool, redis_conn) = setup_teste().await;

        use infrastructure_postgres::AuthUserRepository;
        let auth_repo = infrastructure_postgres::PostgresAuthUserRepository;
        let test_username = format!("user_{}", Uuid::new_v4().to_string().replace('-', ""));
        let test_email = format!("inativo_{}@auth.com", Uuid::new_v4());
        let hash = infrastructure_postgres::hash_password("minhasenha123").unwrap();

        let user = auth_repo
            .criar(&pool, &test_username, &test_email, &hash, false)
            .await
            .expect("Erro ao criar usuário");

        // Desativa o usuário: mesmo com a senha correta o login deve ser rejeitado.
        auth_repo
            .desativar(&pool, user.id)
            .await
            .expect("Erro ao desativar usuário");

        let payload = serde_json::json!({
            "email": test_email,
            "password": "minhasenha123",
        });
        let req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: "".to_string(),
            traceparent: "00-trace2b-span2b-01".to_string(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "VerifyCredentials".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            error: None,
            ..Default::default()
        };

        let resp = handler_verify_credentials(pool.clone(), redis_conn.clone(), req).await;
        assert_eq!(resp.kind, MessageKind::Error as i32);
        assert!(resp.error.is_some());

        // Limpeza
        sqlx::query("DELETE FROM auth_user WHERE id = $1")
            .bind(user.id)
            .execute(&pool)
            .await
            .unwrap();
    }

    #[tokio::test]
    async fn test_handler_persist_and_get_message_flow() {
        let (pool, _) = setup_teste().await;

        let tenant_id = Uuid::new_v4();
        let slug = format!("tenant-{}", Uuid::new_v4());
        sqlx::query(
            "INSERT INTO tenants_tenant (id, name, slug, api_key, owner_id) VALUES ($1, $2, $3, $4, 1)"
        )
        .bind(tenant_id)
        .bind("Tenant Message Flow Test")
        .bind(slug)
        .bind(Uuid::new_v4().to_string())
        .execute(&pool)
        .await
        .unwrap();

        let contato_id: (i32,) = sqlx::query_as(
            "INSERT INTO oraculo_contato (tenant_id, telefone, nome_contato) VALUES ($1, '5511988888888', 'Contato Teste') RETURNING id"
        )
        .bind(tenant_id)
        .fetch_one(&pool)
        .await
        .unwrap();

        let atendimento_id: (i32,) = sqlx::query_as(
            "INSERT INTO oraculo_atendimento (tenant_id, contato_id, status) VALUES ($1, $2, 'em_atendimento') RETURNING id"
        )
        .bind(tenant_id)
        .bind(contato_id.0)
        .fetch_one(&pool)
        .await
        .unwrap();

        let payload_msg = serde_json::json!({
            "atendimento_id": atendimento_id.0,
            "content": "Minha mensagem persistida de teste",
            "tipo": "texto",
            "sender_id": "operator",
        });

        let req_msg = Envelope {
            tenant_id: tenant_id.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: "".to_string(),
            traceparent: "00-trace3-span3-01".to_string(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "PersistMessage".to_string(),
            payload: serde_json::to_vec(&payload_msg).unwrap(),
            error: None,
            auth_user_id: 1,
            auth_scopes: vec!["tenant:admin".to_string()],
            ..Default::default()
        };

        let resp_msg = handler_persist_message(pool.clone(), req_msg).await;
        assert_eq!(resp_msg.kind, MessageKind::Reply as i32);

        let resp_msg_payload: serde_json::Value =
            serde_json::from_slice(&resp_msg.payload).unwrap();
        assert_eq!(
            resp_msg_payload.get("status").unwrap().as_str().unwrap(),
            "success"
        );
        let msg_id = resp_msg_payload
            .get("message_id")
            .unwrap()
            .as_i64()
            .unwrap() as i32;

        let payload_thread = serde_json::json!({
            "atendimento_id": atendimento_id.0,
            "limit": 10,
            "offset": 0
        });

        let req_thread = Envelope {
            tenant_id: tenant_id.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: "".to_string(),
            traceparent: "00-trace3-span3-01".to_string(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "GetThread".to_string(),
            payload: serde_json::to_vec(&payload_thread).unwrap(),
            error: None,
            auth_user_id: 1,
            auth_scopes: vec!["tenant:admin".to_string()],
            ..Default::default()
        };

        let resp_thread = handler_get_thread(pool.clone(), req_thread).await;
        assert_eq!(resp_thread.kind, MessageKind::Reply as i32);

        let resp_thread_payload: serde_json::Value =
            serde_json::from_slice(&resp_thread.payload).unwrap();
        let mensagens_arr = resp_thread_payload
            .get("mensagens")
            .unwrap()
            .as_array()
            .unwrap();
        assert!(!mensagens_arr.is_empty());

        let encontrada = mensagens_arr
            .iter()
            .any(|m| m.get("id").unwrap().as_i64().unwrap() == msg_id as i64);
        assert!(encontrada, "Mensagem persistida não encontrada na thread");

        // Limpeza
        sqlx::query("DELETE FROM tenants_tenant WHERE id = $1")
            .bind(tenant_id)
            .execute(&pool)
            .await
            .unwrap();
    }

    #[tokio::test]
    async fn test_handler_upsert_contact_and_list_atendimentos() {
        let (pool, _) = setup_teste().await;

        let tenant_id = Uuid::new_v4();
        let slug = format!("tenant-{}", Uuid::new_v4());
        sqlx::query(
            "INSERT INTO tenants_tenant (id, name, slug, api_key, owner_id) VALUES ($1, $2, $3, $4, 1)"
        )
        .bind(tenant_id)
        .bind("Tenant Contact Test")
        .bind(slug)
        .bind(Uuid::new_v4().to_string())
        .execute(&pool)
        .await
        .unwrap();

        let payload_contato = serde_json::json!({
            "phone": "5511977777777",
            "name": "Contato Upserted",
        });

        let req_contato = Envelope {
            tenant_id: tenant_id.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: "".to_string(),
            traceparent: "00-trace4-span4-01".to_string(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "UpsertContact".to_string(),
            payload: serde_json::to_vec(&payload_contato).unwrap(),
            error: None,
            auth_user_id: 1,
            auth_scopes: vec!["tenant:admin".to_string()],
            ..Default::default()
        };

        let resp_contato = handler_upsert_contact(pool.clone(), req_contato).await;
        assert_eq!(resp_contato.kind, MessageKind::Reply as i32);

        let resp_contato_payload: serde_json::Value =
            serde_json::from_slice(&resp_contato.payload).unwrap();
        let contato_id = resp_contato_payload.get("id").unwrap().as_i64().unwrap() as i32;

        sqlx::query(
            "INSERT INTO oraculo_atendimento (tenant_id, contato_id, status) VALUES ($1, $2, 'em_atendimento')"
        )
        .bind(tenant_id)
        .bind(contato_id)
        .execute(&pool)
        .await
        .unwrap();

        let payload_list = serde_json::json!({
            "status": "em_atendimento",
            "limit": 10
        });

        let req_list = Envelope {
            tenant_id: tenant_id.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: "".to_string(),
            traceparent: "00-trace4-span4-01".to_string(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "ListAtendimentos".to_string(),
            payload: serde_json::to_vec(&payload_list).unwrap(),
            error: None,
            auth_user_id: 1,
            auth_scopes: vec!["tenant:admin".to_string()],
            ..Default::default()
        };

        let resp_list = handler_list_atendimentos(pool.clone(), req_list).await;
        assert_eq!(resp_list.kind, MessageKind::Reply as i32);

        let resp_list_payload: serde_json::Value =
            serde_json::from_slice(&resp_list.payload).unwrap();
        let atendimentos_arr = resp_list_payload
            .get("atendimentos")
            .unwrap()
            .as_array()
            .unwrap();
        assert!(!atendimentos_arr.is_empty());

        // Limpeza
        sqlx::query("DELETE FROM tenants_tenant WHERE id = $1")
            .bind(tenant_id)
            .execute(&pool)
            .await
            .unwrap();
    }

    #[tokio::test]
    async fn test_processar_evento_auditoria() {
        let (pool, _) = setup_teste().await;

        let tenant_id = Uuid::new_v4();
        let slug = format!("tenant-{}", Uuid::new_v4());
        sqlx::query(
            "INSERT INTO tenants_tenant (id, name, slug, api_key, owner_id) VALUES ($1, $2, $3, $4, 1)"
        )
        .bind(tenant_id)
        .bind("Tenant Audit Test")
        .bind(slug)
        .bind(Uuid::new_v4().to_string())
        .execute(&pool)
        .await
        .unwrap();

        let audit_payload = observability::AuditLogPayload {
            tenant_id: Some(tenant_id),
            level: "INFO".to_string(),
            service: "data_postgres_test".to_string(),
            trace_id: Some("00-trace5-span5-01".to_string()),
            event: "test_event".to_string(),
            message: "Evento de auditoria de teste integrado".to_string(),
            context: serde_json::json!({}),
            user_id: Some(1),
            ip_address: Some("127.0.0.1".to_string()),
        };

        let payload_json_str = serde_json::to_string(&audit_payload).unwrap();

        let evt = transport::bus::EventoBruto {
            stream_id: "12345-0".to_string(),
            tenant_id: tenant_id.to_string(),
            event_id: Uuid::now_v7().to_string(),
            event_type: "security.audit".to_string(),
            timestamp: chrono::Utc::now().to_rfc3339(),
            traceparent: "00-trace5-span5-01".to_string(),
            payload: payload_json_str,
        };

        let processou = processar_evento_auditoria(pool.clone(), evt).await;
        assert!(processou.is_ok());

        let count: (i64,) = sqlx::query_as(
            "SELECT COUNT(*) FROM audit_log WHERE tenant_id = $1 AND event = 'test_event'",
        )
        .bind(tenant_id)
        .fetch_one(&pool)
        .await
        .unwrap();
        assert_eq!(count.0, 1);

        // Limpeza
        sqlx::query("DELETE FROM tenants_tenant WHERE id = $1")
            .bind(tenant_id)
            .execute(&pool)
            .await
            .unwrap();
    }

    #[tokio::test]
    async fn test_handler_get_user_identity() {
        let (pool, _) = setup_teste().await;

        use infrastructure_postgres::AuthUserRepository;
        let auth_repo = infrastructure_postgres::PostgresAuthUserRepository;
        let test_username = format!("user_{}", Uuid::new_v4().to_string().replace('-', ""));
        let test_email = format!("teste_{}@identity.com", Uuid::new_v4());
        let hash = infrastructure_postgres::hash_password("minhasenha123").unwrap();

        let user = auth_repo
            .criar(&pool, &test_username, &test_email, &hash, false)
            .await
            .expect("Erro ao criar usuário");

        // Cria tenant e associa usuario
        let tenant_id = Uuid::new_v4();
        let slug = format!("tenant-{}", Uuid::new_v4());
        sqlx::query(
            "INSERT INTO tenants_tenant (id, name, slug, api_key, owner_id) VALUES ($1, $2, $3, $4, 1)"
        )
        .bind(tenant_id)
        .bind("Tenant Identity Test")
        .bind(slug)
        .bind(Uuid::new_v4().to_string())
        .execute(&pool)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO tenants_tenantuser (tenant_id, user_id, role, is_active, module_permissions) VALUES ($1, $2, 'admin', true, $3)"
        )
        .bind(tenant_id)
        .bind(user.id)
        .bind(serde_json::json!(["atendimentos:read", "clientes:write"]))
        .execute(&pool)
        .await
        .unwrap();

        // 1. Caso de sucesso
        let payload = serde_json::json!({ "id": user.id });
        let req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: "".to_string(),
            traceparent: "00-trace-id1-span1-01".to_string(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "GetUserIdentity".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            error: None,
            ..Default::default()
        };

        let resp = handler_get_user_identity(pool.clone(), req).await;
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        assert_eq!(resp.method, "GetUserIdentityReply");

        let resp_payload: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(
            resp_payload.get("id").unwrap().as_i64().unwrap(),
            user.id as i64
        );
        assert_eq!(
            resp_payload.get("tenant_id").unwrap().as_str().unwrap(),
            tenant_id.to_string()
        );
        assert_eq!(resp_payload.get("role").unwrap().as_str().unwrap(), "admin");
        let perms = resp_payload
            .get("module_permissions")
            .unwrap()
            .as_array()
            .unwrap();
        assert_eq!(perms.len(), 2);

        // 2. Caso de usuário não encontrado
        let payload_err = serde_json::json!({ "id": 999999 });
        let req_err = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: "".to_string(),
            traceparent: "00-trace-id2-span2-01".to_string(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "GetUserIdentity".to_string(),
            payload: serde_json::to_vec(&payload_err).unwrap(),
            error: None,
            ..Default::default()
        };
        let resp_err = handler_get_user_identity(pool.clone(), req_err).await;
        assert_eq!(resp_err.kind, MessageKind::Error as i32);

        // Limpeza
        sqlx::query("DELETE FROM tenants_tenantuser WHERE user_id = $1")
            .bind(user.id)
            .execute(&pool)
            .await
            .unwrap();
        sqlx::query("DELETE FROM tenants_tenant WHERE id = $1")
            .bind(tenant_id)
            .execute(&pool)
            .await
            .unwrap();
        sqlx::query("DELETE FROM auth_user WHERE id = $1")
            .bind(user.id)
            .execute(&pool)
            .await
            .unwrap();
    }

    #[tokio::test]
    async fn test_handler_list_core_settings() {
        let (pool, _) = setup_teste().await;

        // Limpa configs de teste anteriores se existirem
        let _ = sqlx::query("DELETE FROM settings_manager_coresettings WHERE key IN ('test_key_normal', 'test_key_enc')")
            .execute(&pool)
            .await;

        sqlx::query(
            "INSERT INTO settings_manager_coresettings (key, value, encrypted, description) VALUES \
             ('test_key_normal', 'val_normal', false, 'normal config'), \
             ('test_key_enc', 'val_enc_encrypted', true, 'encrypted config')"
        )
        .execute(&pool)
        .await
        .unwrap();

        let req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: "".to_string(),
            traceparent: "00-trace-list-span-01".to_string(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "ListCoreSettings".to_string(),
            payload: vec![],
            error: None,
            ..Default::default()
        };

        let resp = handler_list_core_settings(pool.clone(), req).await;
        assert_eq!(resp.kind, MessageKind::Reply as i32);

        let resp_payload: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        let settings = resp_payload.get("settings").unwrap().as_array().unwrap();

        let normal = settings
            .iter()
            .find(|s| s.get("key").unwrap().as_str().unwrap() == "test_key_normal")
            .unwrap();
        let enc = settings
            .iter()
            .find(|s| s.get("key").unwrap().as_str().unwrap() == "test_key_enc")
            .unwrap();

        assert_eq!(normal.get("value").unwrap().as_str().unwrap(), "val_normal");
        assert_eq!(enc.get("value").unwrap().as_str().unwrap(), "••••••••"); // Criptografado mascarado
        assert!(enc.get("encrypted").unwrap().as_bool().unwrap());

        // Limpeza
        sqlx::query("DELETE FROM settings_manager_coresettings WHERE key IN ('test_key_normal', 'test_key_enc')")
            .execute(&pool)
            .await
            .unwrap();
    }

    #[tokio::test]
    async fn test_handler_upsert_delete_core_setting() {
        let (pool, redis_conn) = setup_teste().await;
        let cipher = std::sync::Arc::new(
            infrastructure_postgres::crypto::CipherManager::new_from_env().unwrap(),
        );

        let key = "test_key_upserted";
        let _ = sqlx::query("DELETE FROM settings_manager_coresettings WHERE key = $1")
            .bind(key)
            .execute(&pool)
            .await;

        // 1. Testa Upsert criptografado
        let payload = serde_json::json!({
            "key": key,
            "value": "meusegredomuitolongo",
            "encrypted": true,
            "description": "teste upsert"
        });

        let req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: "".to_string(),
            traceparent: "00-trace-upsert-span-01".to_string(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "UpsertCoreSetting".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            error: None,
            auth_user_id: 1,
            ..Default::default()
        };

        let resp =
            handler_upsert_core_setting(pool.clone(), cipher.clone(), redis_conn.clone(), req)
                .await;
        assert_eq!(resp.kind, MessageKind::Reply as i32);

        // Verifica no banco se foi salvo de forma criptografada
        use sqlx::Row;
        let row = sqlx::query(
            "SELECT value, encrypted FROM settings_manager_coresettings WHERE key = $1",
        )
        .bind(key)
        .fetch_one(&pool)
        .await
        .unwrap();
        let val_str: String = row.get("value");
        let is_enc: bool = row.get("encrypted");
        assert!(is_enc);
        assert_ne!(val_str, "meusegredomuitolongo"); // Criptografado!
        assert!(val_str.contains(':')); // Formato ct:nonce:tag

        // Descriptografa para testar consistência
        let partes: Vec<&str> = val_str.split(':').collect();
        let decrypted = cipher.decrypt(partes[0], partes[1], partes[2]).unwrap();
        assert_eq!(
            String::from_utf8(decrypted).unwrap(),
            "meusegredomuitolongo"
        );

        // 2. Testa Delete
        let payload_del = serde_json::json!({ "key": key });
        let req_del = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: "".to_string(),
            traceparent: "00-trace-del-span-01".to_string(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "DeleteCoreSetting".to_string(),
            payload: serde_json::to_vec(&payload_del).unwrap(),
            error: None,
            auth_user_id: 1,
            ..Default::default()
        };

        let resp_del = handler_delete_core_setting(pool.clone(), redis_conn.clone(), req_del).await;
        assert_eq!(resp_del.kind, MessageKind::Reply as i32);

        // Verifica que sumiu do banco
        let row_opt = sqlx::query("SELECT key FROM settings_manager_coresettings WHERE key = $1")
            .bind(key)
            .fetch_optional(&pool)
            .await
            .unwrap();
        assert!(row_opt.is_none());
    }

    #[tokio::test]
    async fn test_handler_tenant_config_flow() {
        let (pool, redis_conn) = setup_teste().await;
        let cipher = std::sync::Arc::new(
            infrastructure_postgres::crypto::CipherManager::new_from_env().unwrap(),
        );
        let config_cache = std::sync::Arc::new(infrastructure_postgres::TenantConfigCache::new(
            pool.clone(),
            cipher.clone(),
        ));

        let tenant_id = Uuid::new_v4();
        let slug = format!("tenant-{}", Uuid::new_v4());
        sqlx::query(
            "INSERT INTO tenants_tenant (id, name, slug, api_key, owner_id) VALUES ($1, $2, $3, $4, 1)"
        )
        .bind(tenant_id)
        .bind("Tenant Config Test")
        .bind(slug)
        .bind(Uuid::new_v4().to_string())
        .execute(&pool)
        .await
        .unwrap();

        // 1. Atualiza a configuração do tenant definindo novas API Keys
        let payload_update = serde_json::json!({
            "tenant_id": tenant_id.to_string(),
            "dados_empresa": "Minha Empresa Teste",
            "api_keys": {
                "openai_api_key": "openai-key-original-123",
                "groq_api_key": "groq-key-original-456",
                "google_api_key": ""
            }
        });

        let req_update = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: "".to_string(),
            traceparent: "00-trace-cfg-span-01".to_string(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "UpdateTenantConfig".to_string(),
            payload: serde_json::to_vec(&payload_update).unwrap(),
            error: None,
            auth_user_id: 1,
            ..Default::default()
        };

        let resp_update = handler_update_tenant_config(
            pool.clone(),
            cipher.clone(),
            config_cache.clone(),
            redis_conn.clone(),
            req_update,
        )
        .await;
        assert_eq!(resp_update.kind, MessageKind::Reply as i32);

        // 2. Consulta a configuração do tenant e valida se as chaves vêm mascaradas
        let payload_get = serde_json::json!({ "tenant_id": tenant_id.to_string() });
        let req_get = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: "".to_string(),
            traceparent: "00-trace-cfg-span-02".to_string(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "GetTenantConfig".to_string(),
            payload: serde_json::to_vec(&payload_get).unwrap(),
            error: None,
            ..Default::default()
        };

        let resp_get = handler_get_tenant_config(pool.clone(), cipher.clone(), req_get).await;
        assert_eq!(resp_get.kind, MessageKind::Reply as i32);

        let resp_payload: serde_json::Value = serde_json::from_slice(&resp_get.payload).unwrap();
        assert_eq!(
            resp_payload.get("dados_empresa").unwrap().as_str().unwrap(),
            "Minha Empresa Teste"
        );

        let api_keys = resp_payload.get("api_keys").unwrap().as_object().unwrap();
        assert_eq!(
            api_keys.get("openai_api_key").unwrap().as_str().unwrap(),
            "••••••••"
        );
        assert_eq!(
            api_keys.get("groq_api_key").unwrap().as_str().unwrap(),
            "••••••••"
        );
        assert_eq!(
            api_keys.get("google_api_key").unwrap().as_str().unwrap(),
            ""
        );

        // 3. Atualiza enviando a máscara "••••••••" (deve preservar o valor original no banco)
        // e enviando nova chave em claro para google_api_key
        let payload_update2 = serde_json::json!({
            "tenant_id": tenant_id.to_string(),
            "api_keys": {
                "openai_api_key": "••••••••", // Preservar
                "groq_api_key": "groq-key-alterada-789", // Alterar
                "google_api_key": "google-nova-key" // Criar
            }
        });

        let req_update2 = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: "".to_string(),
            traceparent: "00-trace-cfg-span-03".to_string(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "UpdateTenantConfig".to_string(),
            payload: serde_json::to_vec(&payload_update2).unwrap(),
            error: None,
            auth_user_id: 1,
            ..Default::default()
        };

        let resp_update2 = handler_update_tenant_config(
            pool.clone(),
            cipher.clone(),
            config_cache.clone(),
            redis_conn.clone(),
            req_update2,
        )
        .await;
        assert_eq!(resp_update2.kind, MessageKind::Reply as i32);

        // Verifica os segredos no banco via decriptação direta para confirmar preservação/alteração
        let tc_row = sqlx::query!(
            "SELECT api_keys FROM tenants_tenantconfig WHERE tenant_id = $1",
            tenant_id
        )
        .fetch_one(&pool)
        .await
        .unwrap();

        let openai_dec = cipher
            .decrypt_from_jsonb(&tc_row.api_keys, "openai_api_key")
            .unwrap();
        let groq_dec = cipher
            .decrypt_from_jsonb(&tc_row.api_keys, "groq_api_key")
            .unwrap();
        let google_dec = cipher
            .decrypt_from_jsonb(&tc_row.api_keys, "google_api_key")
            .unwrap();

        assert_eq!(openai_dec, "openai-key-original-123"); // Preservado
        assert_eq!(groq_dec, "groq-key-alterada-789"); // Alterado
        assert_eq!(google_dec, "google-nova-key"); // Criado

        // Limpeza
        sqlx::query("DELETE FROM tenants_tenantconfig WHERE tenant_id = $1")
            .bind(tenant_id)
            .execute(&pool)
            .await
            .unwrap();
        sqlx::query("DELETE FROM tenants_tenant WHERE id = $1")
            .bind(tenant_id)
            .execute(&pool)
            .await
            .unwrap();
    }
}
