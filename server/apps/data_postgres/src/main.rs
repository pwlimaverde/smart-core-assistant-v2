//! Serviço data_postgres: provê RPC síncrono e pub/sub assíncrono sujeito a políticas RLS.
//! Contém o Relay de Outbox e o Consumidor de Auditoria integrados.

use contracts::{Envelope, MessageKind};
use data_postgres::processar_eventos_auditoria_lote;
use infrastructure_postgres::RequestContext;
use redis::aio::ConnectionManager;
use redis::AsyncCommands;
use sqlx::PgPool;
use transport::Server;
use uuid::Uuid;

/// Subscriber dedicado do canal `core:settings:invalidate` (WS-7.2). `payload.tenant_id`
/// ausente ou nulo sinaliza invalidação global (mudança em CoreSettings); presente,
/// invalida só a entrada daquele tenant. Retorna `Ok(())` quando o stream de mensagens
/// encerra (Redis derrubou a conexão); o chamador decide se/quando reconectar.
#[allow(deprecated)]
async fn rodar_subscriber_invalidacao_cache(
    redis_bus_url: &str,
    config_cache: &infrastructure_postgres::TenantConfigCache,
) -> anyhow::Result<()> {
    use futures_util::StreamExt;

    let client = infrastructure_redis::criar_cliente(redis_bus_url)?;
    let con = client.get_async_connection().await?;
    let mut pubsub = con.into_pubsub();
    pubsub.subscribe("core:settings:invalidate").await?;
    tracing::info!("Subscriber de invalidação do TenantConfigCache conectado");

    let mut stream = pubsub.on_message();
    while let Some(msg) = stream.next().await {
        let payload_str: String = match msg.get_payload() {
            Ok(p) => p,
            Err(e) => {
                tracing::warn!("Falha ao ler payload de core:settings:invalidate: {:?}", e);
                continue;
            }
        };
        let payload: serde_json::Value = match serde_json::from_str(&payload_str) {
            Ok(v) => v,
            Err(e) => {
                tracing::warn!("Payload inválido em core:settings:invalidate: {:?}", e);
                continue;
            }
        };
        let tenant_id = payload
            .get("tenant_id")
            .and_then(|v| v.as_str())
            .and_then(|s| Uuid::parse_str(s).ok());
        match tenant_id {
            Some(id) => {
                config_cache.invalidate(&id);
                tracing::debug!(tenant_id = %id, "TenantConfigCache invalidado via Pub/Sub");
            }
            None => {
                config_cache.invalidate_all();
                tracing::debug!("TenantConfigCache invalidado por completo via Pub/Sub");
            }
        }
    }

    Ok(())
}

fn contexto_do_envelope(env: &Envelope) -> RequestContext {
    RequestContext {
        tenant_id: Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil()),
        user_id: env.auth_user_id,
        user_scopes: env.auth_scopes.clone(),
        flow_permissions: env.flow_permissions.clone(),
    }
}

mod outbox_relay;
use outbox_relay::OutboxRelay;

mod adapters;
mod ports;

#[derive(Clone)]
#[allow(dead_code)]
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
    whatsapp: std::sync::Arc<dyn ports::WhatsappStore>,
    tenant: std::sync::Arc<dyn ports::TenantStore>,
    auth: std::sync::Arc<dyn ports::AuthStore>,
    atendimento: std::sync::Arc<dyn ports::AtendimentoStore>,
    cliente: std::sync::Arc<dyn ports::ClienteStore>,
    operacional: std::sync::Arc<dyn ports::OperacionalStore>,
    plans: std::sync::Arc<dyn ports::PlansStore>,
    quota: std::sync::Arc<dyn ports::QuotaStore>,
    audit: std::sync::Arc<dyn ports::AuditPort>,
    treinamento: std::sync::Arc<dyn ports::TreinamentoStore>,
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

    // WS-7.2: subscriber dedicado de invalidação do TenantConfigCache (Redis Pub/Sub).
    // Conexão SEPARADA da usada para publish (regra do realtime.rs: subscribe bloqueia
    // a conexão até a próxima mensagem). Permite que outras réplicas do data_postgres
    // descartem a entrada local quando UpdateTenantConfig/UpsertCoreSetting/
    // DeleteCoreSetting mudam a configuração em outra instância.
    {
        let config_cache = config_cache.clone();
        let redis_bus_url = redis_bus_url.clone();
        tokio::spawn(async move {
            loop {
                match rodar_subscriber_invalidacao_cache(&redis_bus_url, &config_cache).await {
                    Ok(()) => tracing::warn!(
                        "Subscriber de invalidação do TenantConfigCache encerrado; reconectando em 5s"
                    ),
                    Err(e) => tracing::error!(
                        "Erro no subscriber de invalidação do TenantConfigCache: {:?}; reconectando em 5s",
                        e
                    ),
                }
                tokio::time::sleep(std::time::Duration::from_secs(5)).await;
            }
        });
    }

    let whatsapp_store: std::sync::Arc<dyn ports::WhatsappStore> = std::sync::Arc::new(
        adapters::PgWhatsappStore::new(pool.clone(), admin_pool.clone()),
    );
    let audit_port: std::sync::Arc<dyn ports::AuditPort> =
        std::sync::Arc::new(adapters::RedisAuditPort::new(bus_conn.clone()));
    let tenant_store: std::sync::Arc<dyn ports::TenantStore> =
        std::sync::Arc::new(adapters::PgTenantStore::new(pool.clone()));
    let auth_store: std::sync::Arc<dyn ports::AuthStore> =
        std::sync::Arc::new(adapters::PgAuthStore::new(pool.clone()));
    let atendimento_store: std::sync::Arc<dyn ports::AtendimentoStore> = std::sync::Arc::new(
        adapters::PgAtendimentoStore::new(pool.clone(), admin_pool.clone()),
    );
    let cliente_store: std::sync::Arc<dyn ports::ClienteStore> =
        std::sync::Arc::new(adapters::PgClienteStore::new(pool.clone()));
    let operacional_store: std::sync::Arc<dyn ports::OperacionalStore> =
        std::sync::Arc::new(adapters::PgOperacionalStore::new(
            pool.clone(),
            cipher.clone(),
            config_cache.clone(),
            bus_conn.clone(),
        ));
    let plans_store: std::sync::Arc<dyn ports::PlansStore> = std::sync::Arc::new(
        adapters::PgPlansStore::new(pool.clone(), admin_pool.clone()),
    );
    let quota_store: std::sync::Arc<dyn ports::QuotaStore> =
        std::sync::Arc::new(adapters::PgQuotaStore::new(pool.clone()));
    let treinamento_store: std::sync::Arc<dyn ports::TreinamentoStore> =
        std::sync::Arc::new(adapters::PgTreinamentoStore::new(pool.clone()));

    let state = AppState {
        pool: pool.clone(),
        admin_pool: admin_pool.clone(),
        redis_conn: bus_conn.clone(),
        cipher,
        config_cache,
        whatsapp: whatsapp_store,
        tenant: tenant_store,
        auth: auth_store,
        atendimento: atendimento_store,
        cliente: cliente_store,
        operacional: operacional_store,
        plans: plans_store,
        quota: quota_store,
        audit: audit_port,
        treinamento: treinamento_store,
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
    let state_for_create_invite = state_clone.clone();
    let state_for_accept_invite = state_clone.clone();
    let state_for_list_tenant_users = state_clone.clone();
    let state_for_list_invites = state_clone.clone();
    let state_for_revoke_invite = state_clone.clone();
    let state_for_update_tenant_user = state_clone.clone();
    let state_for_create_superuser = state_clone.clone();
    let state_for_list_superusers = state_clone.clone();
    let state_for_delete_superuser = state_clone.clone();
    let state_for_get_user_identity = state_clone.clone();
    let state_for_get_user_flow_permissions = state_clone.clone();
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
    let state_for_check_quota = state_clone.clone();
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
    let state_for_atualizar_instancia_provider_id = state_clone.clone();
    let state_for_verify_whatsapp_instance_token = state_clone.clone();
    let state_for_is_phone_whitelisted = state_clone.clone();
    let state_for_resolve_atendimento = state_clone.clone();
    let state_for_aplicar_politica = state_clone.clone();
    let state_for_move_atendimento_etapa = state_clone.clone();
    let state_for_send_outbound_message = state_clone.clone();
    let state_for_listar_feedback_vencido = state_clone.clone();
    let state_for_marcar_feedback_expirado = state_clone.clone();
    let state_for_listar_midias_expiradas = state_clone.clone();
    let state_for_marcar_midia_purgada = state_clone.clone();
    let state_for_resolver_destino_envio = state_clone.clone();
    let state_for_marcar_mensagem_enviada = state_clone.clone();
    let state_for_marcar_mensagem_falha_envio = state_clone.clone();
    let state_for_anexar_analise_midia = state_clone.clone();
    let state_for_listar_fluxos_tenant = state_clone.clone();
    let state_for_transferir_fluxo = state_clone.clone();
    let state_for_resolver_campos_atendimento = state_clone.clone();
    let state_for_query_compose = state_clone.clone();
    let state_for_resolver_config_ia = state_clone.clone();
    let state_for_update_status = state_clone;

    let server = Server::from_env("DATA_POSTGRES")
        .route("GetThread", move |env| {
            let state = state_for_get_thread.clone();
            Box::pin(async move { handler_get_thread(state.atendimento.as_ref(), env).await })
        })
        .route("PersistMessage", move |env| {
            let state = state_for_persist.clone();
            Box::pin(async move { handler_persist_message(state.atendimento.as_ref(), env).await })
        })
        .route("ResolveAtendimentoParaContato", move |env| {
            let state = state_for_resolve_atendimento.clone();
            Box::pin(async move {
                handler_resolve_atendimento_para_contato(state.atendimento.as_ref(), env).await
            })
        })
        .route("UpdateMessageStatus", move |env| {
            let state = state_for_update_status.clone();
            Box::pin(
                async move { handler_update_message_status(state.atendimento.as_ref(), env).await },
            )
        })
        .route("AplicarPoliticaTicketKanban", move |env| {
            let state = state_for_aplicar_politica.clone();
            Box::pin(async move {
                handler_aplicar_politica_ticket_kanban(state.atendimento.as_ref(), env).await
            })
        })
        .route("MoveAtendimentoEtapa", move |env| {
            let state = state_for_move_atendimento_etapa.clone();
            Box::pin(async move {
                handler_move_atendimento_etapa(state.atendimento.as_ref(), env).await
            })
        })
        .route("SendOutboundMessage", move |env| {
            let state = state_for_send_outbound_message.clone();
            Box::pin(
                async move { handler_send_outbound_message(state.atendimento.as_ref(), env).await },
            )
        })
        .route("ListarAtendimentosFeedbackVencido", move |env| {
            let state = state_for_listar_feedback_vencido.clone();
            Box::pin(async move {
                handler_listar_feedback_vencido(state.atendimento.as_ref(), env).await
            })
        })
        .route("MarcarFeedbackExpirado", move |env| {
            let state = state_for_marcar_feedback_expirado.clone();
            Box::pin(async move {
                handler_marcar_feedback_expirado(state.atendimento.as_ref(), env).await
            })
        })
        .route("ListarMidiasExpiradas", move |env| {
            let state = state_for_listar_midias_expiradas.clone();
            Box::pin(async move {
                handler_listar_midias_expiradas(state.atendimento.as_ref(), env).await
            })
        })
        .route("MarcarMidiaPurgada", move |env| {
            let state = state_for_marcar_midia_purgada.clone();
            Box::pin(
                async move { handler_marcar_midia_purgada(state.atendimento.as_ref(), env).await },
            )
        })
        .route("ResolverDestinoEnvioOutbound", move |env| {
            let state = state_for_resolver_destino_envio.clone();
            Box::pin(async move {
                handler_resolver_destino_envio_outbound(state.atendimento.as_ref(), env).await
            })
        })
        .route("AnexarAnaliseMidia", move |env| {
            let state = state_for_anexar_analise_midia.clone();
            Box::pin(
                async move { handler_anexar_analise_midia(state.atendimento.as_ref(), env).await },
            )
        })
        .route("ListarFluxosDoTenant", move |env| {
            let state = state_for_listar_fluxos_tenant.clone();
            Box::pin(async move {
                handler_listar_fluxos_do_tenant(state.atendimento.as_ref(), env).await
            })
        })
        .route("TransferirAtendimentoParaFluxo", move |env| {
            let state = state_for_transferir_fluxo.clone();
            Box::pin(async move {
                handler_transferir_atendimento_para_fluxo(state.atendimento.as_ref(), env).await
            })
        })
        .route("ResolverCamposAtendimento", move |env| {
            let state = state_for_resolver_campos_atendimento.clone();
            Box::pin(async move {
                handler_resolver_campos_atendimento(state.atendimento.as_ref(), env).await
            })
        })
        .route("MarcarMensagemEnviada", move |env| {
            let state = state_for_marcar_mensagem_enviada.clone();
            Box::pin(async move {
                handler_marcar_mensagem_enviada(state.atendimento.as_ref(), env).await
            })
        })
        .route("MarcarMensagemFalhaEnvio", move |env| {
            let state = state_for_marcar_mensagem_falha_envio.clone();
            Box::pin(async move {
                handler_marcar_mensagem_falha_envio(state.atendimento.as_ref(), env).await
            })
        })
        .route("QueryCompose", move |env| {
            let state = state_for_query_compose.clone();
            Box::pin(async move { handler_query_compose(state.treinamento.as_ref(), env).await })
        })
        .route("VerifyCredentials", move |env| {
            let state = state_for_verify.clone();
            Box::pin(async move {
                handler_verify_credentials(state.auth.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("UpsertContact", move |env| {
            let state = state_for_upsert.clone();
            Box::pin(async move { handler_upsert_contact(state.cliente.as_ref(), env).await })
        })
        .route("ListAtendimentos", move |env| {
            let state = state_for_list.clone();
            Box::pin(
                async move { handler_list_atendimentos(state.atendimento.as_ref(), env).await },
            )
        })
        .route("CreateTenant", move |env| {
            let state = state_for_create_tenant.clone();
            Box::pin(async move {
                handler_create_tenant(state.tenant.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("CreateInvite", move |env| {
            let state = state_for_create_invite.clone();
            Box::pin(async move {
                handler_create_invite(state.tenant.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("AcceptInvite", move |env| {
            let state = state_for_accept_invite.clone();
            Box::pin(async move {
                handler_accept_invite(state.tenant.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("ListTenantUsers", move |env| {
            let state = state_for_list_tenant_users.clone();
            Box::pin(async move { handler_list_tenant_users(state.tenant.as_ref(), env).await })
        })
        .route("ListInvites", move |env| {
            let state = state_for_list_invites.clone();
            Box::pin(async move { handler_list_invites(state.tenant.as_ref(), env).await })
        })
        .route("RevokeInvite", move |env| {
            let state = state_for_revoke_invite.clone();
            Box::pin(async move {
                handler_revoke_invite(state.tenant.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("UpdateTenantUser", move |env| {
            let state = state_for_update_tenant_user.clone();
            Box::pin(async move {
                handler_update_tenant_user(state.tenant.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("CreateSuperuser", move |env| {
            let state = state_for_create_superuser.clone();
            Box::pin(async move {
                handler_create_superuser(state.auth.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("ListSuperusers", move |env| {
            let state = state_for_list_superusers.clone();
            Box::pin(async move { handler_list_superusers(state.auth.as_ref(), env).await })
        })
        .route("DeleteSuperuser", move |env| {
            let state = state_for_delete_superuser.clone();
            Box::pin(async move {
                handler_delete_superuser(state.auth.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("GetUserIdentity", move |env| {
            let state = state_for_get_user_identity.clone();
            Box::pin(async move { handler_get_user_identity(state.auth.as_ref(), env).await })
        })
        .route("GetUserFlowPermissions", move |env| {
            let state = state_for_get_user_flow_permissions.clone();
            Box::pin(
                async move { handler_get_user_flow_permissions(state.auth.as_ref(), env).await },
            )
        })
        .route("ListCoreSettings", move |env| {
            let state = state_for_list_core_settings.clone();
            Box::pin(
                async move { handler_list_core_settings(state.operacional.as_ref(), env).await },
            )
        })
        .route("UpsertCoreSetting", move |env| {
            let state = state_for_upsert_core_setting.clone();
            Box::pin(async move {
                handler_upsert_core_setting(state.operacional.as_ref(), state.audit.as_ref(), env)
                    .await
            })
        })
        .route("DeleteCoreSetting", move |env| {
            let state = state_for_delete_core_setting.clone();
            Box::pin(async move {
                handler_delete_core_setting(state.operacional.as_ref(), state.audit.as_ref(), env)
                    .await
            })
        })
        .route("GetTenantConfig", move |env| {
            let state = state_for_get_tenant_config.clone();
            Box::pin(
                async move { handler_get_tenant_config(state.operacional.as_ref(), env).await },
            )
        })
        .route("UpdateTenantConfig", move |env| {
            let state = state_for_update_tenant_config.clone();
            Box::pin(async move {
                handler_update_tenant_config(state.operacional.as_ref(), state.audit.as_ref(), env)
                    .await
            })
        })
        .route("ResolverConfigIa", move |env| {
            let state = state_for_resolver_config_ia.clone();
            Box::pin(
                async move { handler_resolver_config_ia(state.operacional.as_ref(), env).await },
            )
        })
        .route("ListTenants", move |env| {
            let state = state_for_list_tenants.clone();
            Box::pin(async move { handler_list_tenants(state.tenant.as_ref(), env).await })
        })
        .route("GetTenant", move |env| {
            let state = state_for_get_tenant.clone();
            Box::pin(async move { handler_get_tenant(state.tenant.as_ref(), env).await })
        })
        .route("UpdateTenant", move |env| {
            let state = state_for_update_tenant.clone();
            Box::pin(async move {
                handler_update_tenant(state.tenant.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("SetTenantActive", move |env| {
            let state = state_for_set_tenant_active.clone();
            Box::pin(async move {
                handler_set_tenant_active(state.tenant.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("GenerateAccessCode", move |env| {
            let state = state_for_generate_access_code.clone();
            Box::pin(async move {
                handler_generate_access_code(state.tenant.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("ListPlans", move |env| {
            let state = state_for_list_plans.clone();
            Box::pin(async move { handler_list_plans(state.plans.as_ref(), env).await })
        })
        .route("CheckQuota", move |env| {
            let state = state_for_check_quota.clone();
            Box::pin(async move {
                handler_check_quota(state.quota.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("CreatePlan", move |env| {
            let state = state_for_create_plan.clone();
            Box::pin(async move {
                handler_create_plan(state.plans.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("UpdatePlan", move |env| {
            let state = state_for_update_plan.clone();
            Box::pin(async move {
                handler_update_plan(state.plans.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("ListSubscriptions", move |env| {
            let state = state_for_list_subscriptions.clone();
            Box::pin(async move { handler_list_subscriptions(state.plans.as_ref(), env).await })
        })
        .route("RegisterPayment", move |env| {
            let state = state_for_register_payment.clone();
            Box::pin(async move {
                handler_register_payment(state.plans.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("ListPayments", move |env| {
            let state = state_for_list_payments.clone();
            Box::pin(async move { handler_list_payments(state.plans.as_ref(), env).await })
        })
        .route("GetEvolutionInstanceByTenant", move |env| {
            let state = state_for_get_evolution_instance_by_tenant.clone();
            Box::pin(async move {
                handler_get_evolution_instance_by_tenant(state.operacional.as_ref(), env).await
            })
        })
        .route("ListFeatureFlags", move |env| {
            let state = state_for_list_feature_flags.clone();
            Box::pin(
                async move { handler_list_feature_flags(state.operacional.as_ref(), env).await },
            )
        })
        .route("SetFeatureFlag", move |env| {
            let state = state_for_set_feature_flag.clone();
            Box::pin(async move {
                handler_set_feature_flag(state.operacional.as_ref(), state.audit.as_ref(), env)
                    .await
            })
        })
        .route("SetFeatureFlagOverride", move |env| {
            let state = state_for_set_feature_flag_override.clone();
            Box::pin(async move {
                handler_set_feature_flag_override(
                    state.operacional.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("QueryAuditLog", move |env| {
            let state = state_for_query_audit_log.clone();
            Box::pin(async move { handler_query_audit_log(state.operacional.as_ref(), env).await })
        })
        .route("GetServiceHealth", move |env| {
            let state = state_for_get_service_health.clone();
            Box::pin(
                async move { handler_get_service_health(state.operacional.as_ref(), env).await },
            )
        })
        .route("GetDashboardSummary", move |env| {
            let state = state_for_get_dashboard_summary.clone();
            Box::pin(
                async move { handler_get_dashboard_summary(state.operacional.as_ref(), env).await },
            )
        })
        .route("ExportTenantsCsv", move |env| {
            let state = state_for_export_tenants_csv.clone();
            Box::pin(async move { handler_export_tenants_csv(state.tenant.as_ref(), env).await })
        })
        .route("CreateWhatsappInstanceRecord", move |env| {
            let state = state_for_create_whatsapp_instance_record.clone();
            Box::pin(async move {
                handler_create_whatsapp_instance_record(
                    state.whatsapp.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("GetWhatsappInstance", move |env| {
            let state = state_for_get_whatsapp_instance.clone();
            Box::pin(
                async move { handler_get_whatsapp_instance(state.whatsapp.as_ref(), env).await },
            )
        })
        .route("ListWhatsappInstances", move |env| {
            let state = state_for_list_whatsapp_instances.clone();
            Box::pin(
                async move { handler_list_whatsapp_instances(state.whatsapp.as_ref(), env).await },
            )
        })
        .route("AdminListAllConnectedInstances", move |env| {
            let state = state_for_admin_list_all_connected_instances.clone();
            Box::pin(async move {
                handler_admin_list_all_connected_instances(state.whatsapp.as_ref(), env).await
            })
        })
        .route("AdminDeletarInstancia", move |env| {
            let state = state_for_admin_deletar_instancia.clone();
            Box::pin(async move {
                handler_admin_deletar_instancia(state.whatsapp.as_ref(), state.audit.as_ref(), env)
                    .await
            })
        })
        .route("AtualizarEstadoInstancia", move |env| {
            let state = state_for_atualizar_estado_instancia.clone();
            Box::pin(async move {
                handler_atualizar_estado_instancia(
                    state.whatsapp.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("AtualizarInstanciaProviderId", move |env| {
            let state = state_for_atualizar_instancia_provider_id.clone();
            Box::pin(async move {
                handler_atualizar_instancia_provider_id(
                    state.whatsapp.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("VerifyWhatsappInstanceToken", move |env| {
            let state = state_for_verify_whatsapp_instance_token.clone();
            Box::pin(async move {
                handler_verify_whatsapp_instance_token(state.whatsapp.as_ref(), env).await
            })
        })
        .route("IsPhoneWhitelisted", move |env| {
            let state = state_for_is_phone_whitelisted.clone();
            Box::pin(
                async move { handler_is_phone_whitelisted(state.whatsapp.as_ref(), env).await },
            )
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

/// Carrega a thread (mensagens) de um atendimento, respeitando o RLS do tenant.
async fn handler_get_thread(store: &dyn ports::AtendimentoStore, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
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
    match store
        .listar_mensagens(&ctx, atendimento_id, limit, offset)
        .await
    {
        Ok(mensagens) => ok_reply(
            &env,
            "GetThreadReply",
            serde_json::json!({ "atendimento_id": atendimento_id, "mensagens": mensagens }),
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

/// Lista atendimentos por status (snapshot de realtime), respeitando o RLS do tenant.
async fn handler_list_atendimentos(store: &dyn ports::AtendimentoStore, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
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
    match store
        .listar_atendimentos(&ctx, &status, departamento_id, limit)
        .await
    {
        Ok(atendimentos) => ok_reply(
            &env,
            "ListAtendimentosReply",
            serde_json::json!({ "atendimentos": atendimentos }),
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

/// Serializa um Tenant no formato JSON estável esperado pelos clientes admin
/// (timestamps em epoch ms; phone/access_code como string vazia quando ausentes).
fn tenant_to_json(t: &infrastructure_postgres::tenants::tenants::Tenant) -> serde_json::Value {
    serde_json::json!({
        "id": t.id.to_string(),
        "name": t.name,
        "slug": t.slug,
        "api_key": t.api_key,
        "owner_id": t.owner_id,
        "email": t.email,
        "phone": t.phone.clone().unwrap_or_default(),
        "active": t.active,
        "setup_completed": t.setup_completed,
        "onboarding_step": t.onboarding_step,
        "access_code": t.access_code.clone().unwrap_or_default(),
        "created_at": t.created_at.timestamp_millis(),
        "updated_at": t.updated_at.timestamp_millis(),
    })
}

/// Cria um novo tenant (operação administrativa do control_plane). Depende SOMENTE
/// das ports (DIP): a transação/SQL e a configuração de `app.current_tenant` para
/// satisfazer o RLS vivem no adapter.
async fn handler_create_tenant(
    store: &dyn ports::TenantStore,
    audit: &dyn ports::AuditPort,
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

    match store.criar(&name, &slug, email, phone).await {
        Ok(tenant) => {
            // Auditoria obrigatória: criação de tenant é alteração cadastral sensível
            // (diretriz de segurança §4.2). O `context` registra apenas identificadores,
            // nunca segredos (a api_key gerada não entra no evento).
            audit
                .publish(
                    &env,
                    "tenant_created",
                    format!("Tenant '{}' criado", name),
                    serde_json::json!({ "id": tenant.id.to_string(), "name": name, "slug": slug }),
                )
                .await;

            // Bootstrap do primeiro admin: cria o TenantUser do owner com os escopos
            // iniciais. Roda em transação própria (o `criar` já commitou o tenant); uma
            // falha aqui não faz rollback do tenant — apenas loga erro (o admin pode ser
            // recriado via convite). `user_id` = owner_id autoritativo do tenant criado.
            let escopos_admin = serde_json::json!([
                "tenant:admin",
                "atendimentos:read",
                "atendimentos:write",
                "clientes:write"
            ]);
            match store
                .criar_primeiro_admin(tenant.id, tenant.owner_id, escopos_admin)
                .await
            {
                Ok(_) => {
                    // Auditoria obrigatória: a concessão do primeiro conjunto de permissões
                    // (papel `admin` + escopos `tenant:admin`) é evento crítico de `TenantUser`
                    // (diretriz de segurança §4.2). O `context` registra apenas identificadores,
                    // nunca segredos.
                    audit
                        .publish(
                            &env,
                            "tenant_user_bootstrap_admin",
                            "Primeiro admin do tenant provisionado (bootstrap do CreateTenant)"
                                .to_string(),
                            serde_json::json!({
                                "tenant_id": tenant.id.to_string(),
                                "user_id": tenant.owner_id,
                            }),
                        )
                        .await;
                }
                Err(err) => {
                    tracing::error!(
                        tenant_id = %tenant.id,
                        owner_id = tenant.owner_id,
                        erro = %err,
                        "falha ao criar o primeiro TenantUser admin do tenant recém-criado"
                    );
                }
            }

            ok_reply(
                &env,
                "CreateTenantReply",
                serde_json::json!({ "status": "success", "tenant": tenant }),
            )
        }
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_create_invite(
    store: &dyn ports::TenantStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));

    let email = match payload_json.get("email").and_then(|v| v.as_str()) {
        Some(e) => e,
        None => {
            return erro(
                error_core::AppError::Validation("email ausente".to_string()),
                &env,
            )
        }
    };
    let name = match payload_json.get("name").and_then(|v| v.as_str()) {
        Some(n) => n,
        None => {
            return erro(
                error_core::AppError::Validation("name ausente".to_string()),
                &env,
            )
        }
    };
    let role = payload_json
        .get("role")
        .and_then(|v| v.as_str())
        .unwrap_or("staff");
    // Permissões que o convidado receberá no aceite: `module_permissions` é a lista
    // direta de escopos (mesmo formato de `derivar_escopos` no login); `flow_permissions`
    // são os ids de fluxo do Kanban. Persistidas no convite e herdadas pelo TenantUser.
    // Sem escopos explícitos, cai no default por role (espelha o fallback de
    // `derivar_escopos`) — um convidado nunca deve nascer sem nenhum escopo.
    let module_permissions = match payload_json.get("module_permissions") {
        Some(v) if v.as_array().is_some_and(|a| !a.is_empty()) => v.clone(),
        _ => match role {
            "admin" | "owner" => serde_json::json!([
                "tenant:admin",
                "atendimentos:read",
                "atendimentos:write",
                "clientes:write"
            ]),
            _ => serde_json::json!(["atendimentos:read", "atendimentos:write", "clientes:write"]),
        },
    };
    let flow_permissions = payload_json
        .get("flow_permissions")
        .cloned()
        .unwrap_or_else(|| serde_json::json!([]));

    // Gera token URL-safe seguro de 64 caracteres
    let token = format!(
        "{}{}",
        uuid::Uuid::new_v4().simple(),
        uuid::Uuid::new_v4().simple()
    );
    let expires_at = chrono::Utc::now() + chrono::Duration::days(7);
    let ctx = contexto_do_envelope(&env);

    match store
        .criar_convite(
            &ctx,
            email,
            name,
            role,
            module_permissions,
            flow_permissions,
            &token,
            expires_at,
        )
        .await
    {
        Ok(invite) => {
            audit
                .publish(
                    &env,
                    "tenant_invite_created",
                    format!("Convite criado para '{}' <{}>", name, email),
                    serde_json::json!({ "id": invite.id.to_string(), "email": email, "role": role }),
                )
                .await;

            ok_reply(
                &env,
                "CreateInviteReply",
                serde_json::json!({
                    "status": "success",
                    "invite": {
                        "id": invite.id.to_string(),
                        "tenant_id": invite.tenant_id.to_string(),
                        "email": invite.email,
                        "name": invite.name,
                        "role": invite.role,
                        "token": invite.token,
                        "expires_at": invite.expires_at.timestamp_millis(),
                        "used": invite.used,
                        "created_at": invite.created_at.timestamp_millis(),
                    }
                }),
            )
        }
        // `err.into()` preserva a semântica do DbError (PermissionDenied →
        // AUTH_INSUFFICIENT_SCOPE) em vez de achatar tudo em erro de banco.
        Err(err) => erro(err.into(), &env),
    }
}

async fn handler_accept_invite(
    store: &dyn ports::TenantStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));

    let token = match payload_json.get("token").and_then(|v| v.as_str()) {
        Some(t) => t,
        None => {
            return erro(
                error_core::AppError::Validation("token ausente".to_string()),
                &env,
            )
        }
    };
    let username = match payload_json.get("username").and_then(|v| v.as_str()) {
        Some(u) => u,
        None => {
            return erro(
                error_core::AppError::Validation("username ausente".to_string()),
                &env,
            )
        }
    };
    let email = match payload_json.get("email").and_then(|v| v.as_str()) {
        Some(e) => e,
        None => {
            return erro(
                error_core::AppError::Validation("email ausente".to_string()),
                &env,
            )
        }
    };
    let password = match payload_json.get("password").and_then(|v| v.as_str()) {
        Some(p) => p,
        None => {
            return erro(
                error_core::AppError::Validation("password ausente".to_string()),
                &env,
            )
        }
    };

    // 1. Validar convite buscando pelo token (bypass RLS)
    let invite_opt = match store.buscar_convite_por_token(token).await {
        Ok(opt) => opt,
        Err(err) => return erro(err.into(), &env),
    };

    let invite = match invite_opt {
        Some(i) => i,
        None => {
            return erro(
                error_core::AppError::Validation("Convite não encontrado".to_string()),
                &env,
            )
        }
    };

    if invite.used {
        return erro(
            error_core::AppError::Conflict("Convite já utilizado".to_string()),
            &env,
        );
    }

    if invite.expires_at < chrono::Utc::now() {
        return erro(
            error_core::AppError::Validation("Convite expirado".to_string()),
            &env,
        );
    }

    // Hash da senha usando argon2id
    let password_hash = match infrastructure_postgres::hash_password(password) {
        Ok(h) => h,
        Err(err) => return erro(error_core::AppError::Validation(err.to_string()), &env),
    };

    // 2. Aceitar o convite transacionalmente — o TenantUser herda as permissões
    //    definidas no convite (module_permissions/flow_permissions).
    match store
        .aceitar_convite(
            invite.id,
            username,
            email,
            &password_hash,
            invite.tenant_id,
            &invite.role,
            invite.module_permissions.clone(),
            invite.flow_permissions.clone(),
        )
        .await
    {
        Ok(tenant_user) => {
            audit
                .publish(
                    &env,
                    "tenant_invite_accepted",
                    format!("Convite aceito pelo usuário '{}'", username),
                    serde_json::json!({ "invite_id": invite.id.to_string(), "tenant_id": invite.tenant_id.to_string(), "username": username }),
                )
                .await;

            ok_reply(
                &env,
                "AcceptInviteReply",
                serde_json::json!({
                    "status": "success",
                    "tenant_user": {
                        "id": tenant_user.id,
                        "user_id": tenant_user.user_id,
                        "tenant_id": tenant_user.tenant_id.to_string(),
                        "role": tenant_user.role,
                        "module_permissions": tenant_user.module_permissions,
                        "flow_permissions": tenant_user.flow_permissions,
                        "is_active": tenant_user.is_active,
                    }
                }),
            )
        }
        Err(err) => erro(err.into(), &env),
    }
}

/// Lista os TenantUser do tenant do requisitante (painel do tenant, N3).
/// RBAC `tenant:admin` aplicado no repositório. Nunca expõe senha/hash.
async fn handler_list_tenant_users(store: &dyn ports::TenantStore, env: Envelope) -> Envelope {
    let ctx = contexto_do_envelope(&env);
    match store.listar_usuarios(&ctx).await {
        Ok(users) => {
            let list: Vec<serde_json::Value> = users
                .iter()
                .map(|u| {
                    serde_json::json!({
                        "id": u.id,
                        "user_id": u.user_id,
                        "role": u.role,
                        "module_permissions": u.module_permissions,
                        "flow_permissions": u.flow_permissions,
                        "is_active": u.is_active,
                        "created_at": u.created_at.timestamp_millis(),
                    })
                })
                .collect();
            ok_reply(
                &env,
                "ListTenantUsersReply",
                serde_json::json!({ "users": list }),
            )
        }
        Err(err) => erro(err.into(), &env),
    }
}

/// Lista os convites do tenant do requisitante (painel do tenant, N3).
/// RBAC `tenant:admin` no repositório. Nunca expõe o `token` do convite.
async fn handler_list_invites(store: &dyn ports::TenantStore, env: Envelope) -> Envelope {
    let ctx = contexto_do_envelope(&env);
    match store.listar_convites(&ctx).await {
        Ok(invites) => {
            let list: Vec<serde_json::Value> = invites
                .iter()
                .map(|i| {
                    serde_json::json!({
                        "id": i.id.to_string(),
                        "email": i.email,
                        "name": i.name,
                        "role": i.role,
                        "module_permissions": i.module_permissions,
                        "flow_permissions": i.flow_permissions,
                        "expires_at": i.expires_at.timestamp_millis(),
                        "used": i.used,
                        "revoked": i.revoked,
                        "created_at": i.created_at.timestamp_millis(),
                    })
                })
                .collect();
            ok_reply(
                &env,
                "ListInvitesReply",
                serde_json::json!({ "invites": list }),
            )
        }
        Err(err) => erro(err.into(), &env),
    }
}

/// Revoga um convite ainda não usado/revogado/expirado (painel do tenant, N3).
/// RBAC `tenant:admin` no repositório. Auditoria WARN (convite é evento crítico);
/// contexto só com `invite_id` (nunca e-mail/token).
async fn handler_revoke_invite(
    store: &dyn ports::TenantStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let invite_id = match payload_json
        .get("invite_id")
        .and_then(|v| v.as_str())
        .and_then(|s| Uuid::parse_str(s).ok())
    {
        Some(id) => id,
        None => {
            return erro(
                error_core::AppError::Validation("invite_id inválido ou ausente".to_string()),
                &env,
            )
        }
    };
    let ctx = contexto_do_envelope(&env);

    match store.revogar_convite(&ctx, invite_id).await {
        Ok(true) => {
            audit
                .publish(
                    &env,
                    "tenant_invite_revoked",
                    "Convite revogado".to_string(),
                    serde_json::json!({ "invite_id": invite_id.to_string() }),
                )
                .await;
            ok_reply(
                &env,
                "RevokeInviteReply",
                serde_json::json!({ "status": "success" }),
            )
        }
        Ok(false) => erro(
            error_core::AppError::Validation(
                "convite inexistente, já usado, revogado ou expirado".to_string(),
            ),
            &env,
        ),
        Err(err) => erro(err.into(), &env),
    }
}

/// Atualiza role/permissões de um TenantUser do tenant (painel do tenant, N3).
/// RBAC `tenant:admin` no repositório. `module_permissions` é a lista direta de
/// escopos (array de strings) — mesmo formato consumido por `derivar_escopos` no login.
/// Auditoria WARN por campo alterado; contexto só com ids (nunca nomes/telefones/e-mails).
async fn handler_update_tenant_user(
    store: &dyn ports::TenantStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let user_id = match payload_json.get("user_id").and_then(|v| v.as_i64()) {
        Some(id) => id as i32,
        None => {
            return erro(
                error_core::AppError::Validation("user_id ausente".to_string()),
                &env,
            )
        }
    };
    let role = payload_json
        .get("role")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());
    let module_permissions = payload_json.get("module_permissions").cloned();
    let flow_permissions = payload_json.get("flow_permissions").cloned();

    if role.is_none() && module_permissions.is_none() && flow_permissions.is_none() {
        return erro(
            error_core::AppError::Validation("nenhum campo para atualizar".to_string()),
            &env,
        );
    }

    let ctx = contexto_do_envelope(&env);
    let mudou_role_ou_modulos = role.is_some() || module_permissions.is_some();
    let mudou_fluxos = flow_permissions.is_some();

    match store
        .atualizar_usuario(
            &ctx,
            user_id,
            role.clone(),
            module_permissions.clone(),
            flow_permissions.clone(),
        )
        .await
    {
        Ok(true) => {
            if mudou_role_ou_modulos {
                audit
                    .publish(
                        &env,
                        "tenant_user_role_change",
                        "Role/permissões de módulo do usuário do tenant alteradas".to_string(),
                        serde_json::json!({
                            "user_id": user_id,
                            "role_alterada": role.is_some(),
                            "module_permissions_alteradas": module_permissions.is_some(),
                        }),
                    )
                    .await;
            }
            if mudou_fluxos {
                audit
                    .publish(
                        &env,
                        "tenant_user_flow_permissions_alteradas",
                        "flow_permissions do usuário do tenant alteradas".to_string(),
                        serde_json::json!({ "user_id": user_id }),
                    )
                    .await;
            }
            ok_reply(
                &env,
                "UpdateTenantUserReply",
                serde_json::json!({ "status": "success" }),
            )
        }
        Ok(false) => erro(
            error_core::AppError::Validation("usuário inexistente no tenant".to_string()),
            &env,
        ),
        Err(err) => erro(err.into(), &env),
    }
}

/// Cria o superusuário padrão do sistema (operação administrativa do control_plane).
///
/// `auth_user` é uma tabela **global, sem RLS**: usa o pool direto. A senha chega em
/// claro pelo Envelope (transporte local) e é **tratada aqui** (hash argon2id) antes
/// de gravar. Duplicidade de username/email devolve erro `Conflict` indicando o campo
/// em conflito. Ao criar, dispara um log de auditoria global.
async fn handler_create_superuser(
    store: &dyn ports::AuthStore,
    audit: &dyn ports::AuditPort,
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
        return erro(
            error_core::AppError::Validation(
                "username obrigatório e senha com ao menos 8 caracteres".to_string(),
            ),
            &env,
        );
    }

    // Duplicidade é um conflito explícito (erro), indicando QUAL campo já existe —
    // o username e o email têm UNIQUE no banco.
    match store.buscar_por_username(&username).await {
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
        match store.buscar_por_email(&email).await {
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
        Err(err) => return erro(error_core::AppError::Internal(err.to_string()), &env),
    };

    let user = match store.criar_superuser(&username, &email, &hash).await {
        Ok(u) => u,
        Err(err) => return erro(error_core::AppError::Database(err.to_string()), &env),
    };

    tracing::info!(id = user.id, username = %user.username, "superusuário criado");

    // Auditoria global (sem tenant), nível INFO: a port publica no barramento de
    // segurança e o consumidor deste serviço consolida em `audit_log` (bypass RLS).
    audit
        .publish_security(
            &env.traceparent,
            None,
            "INFO",
            "superuser_created",
            format!("Superusuário '{}' criado (id={})", user.username, user.id),
            serde_json::json!({ "username": user.username, "user_id": user.id }),
            Some(user.id),
        )
        .await;

    ok_reply(
        &env,
        "CreateSuperuserReply",
        serde_json::json!({
            "status": "created",
            "id": user.id,
            "username": user.username,
            "email": user.email,
            "is_superuser": user.is_superuser,
        }),
    )
}

/// Lista os superusuários do sistema (operação administrativa, tabela global).
async fn handler_list_superusers(store: &dyn ports::AuthStore, env: Envelope) -> Envelope {
    match store.listar_superusers().await {
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
            ok_reply(
                &env,
                "ListSuperusersReply",
                serde_json::json!({ "superusers": lista }),
            )
        }
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

/// Exclui (hard delete) um superusuário pelo id (operação administrativa).
/// Só remove se o registro for de fato superusuário; dispara auditoria global.
async fn handler_delete_superuser(
    store: &dyn ports::AuthStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let user_id = payload_json.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;

    if user_id <= 0 {
        return erro(
            error_core::AppError::Validation("id de superusuário inválido".to_string()),
            &env,
        );
    }

    match store.deletar_superuser(user_id).await {
        Ok(0) => erro(
            error_core::AppError::Conflict(format!(
                "nenhum superusuário com id {user_id} (ou o registro não é superusuário)"
            )),
            &env,
        ),
        Ok(_) => {
            tracing::info!(id = user_id, "superusuário excluído");

            // Auditoria global (sem tenant), nível WARN do evento de exclusão.
            audit
                .publish_security(
                    &env.traceparent,
                    None,
                    "WARN",
                    "superuser_deleted",
                    format!("Superusuário id={user_id} excluído"),
                    serde_json::json!({ "user_id": user_id }),
                    Some(user_id),
                )
                .await;

            ok_reply(
                &env,
                "DeleteSuperuserReply",
                serde_json::json!({ "status": "deleted", "id": user_id }),
            )
        }
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_persist_message(store: &dyn ports::AtendimentoStore, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(_) => {
            let s = String::from_utf8_lossy(&env.payload);
            serde_json::json!({ "content": s })
        }
    };

    let ctx = contexto_do_envelope(&env);
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

    // O traceparent é persistido no outbox para manter o trace distribuído vivo
    // até o relay republicar o evento no barramento.
    match store
        .persistir_mensagem(
            &ctx,
            atendimento_id,
            tipo,
            conteudo,
            remetente,
            &env.traceparent,
        )
        .await
    {
        Ok(msg) => ok_reply(
            &env,
            "PersistMessageReply",
            serde_json::json!({ "status": "success", "message_id": msg.id }),
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_resolve_atendimento_para_contato(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let phone = match payload_json.get("phone").and_then(|v| v.as_str()) {
        Some(p) => p,
        None => {
            return erro(
                error_core::AppError::Validation("phone ausente".into()),
                &env,
            )
        }
    };

    let push_name = payload_json
        .get("push_name")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());

    let ctx = contexto_do_envelope(&env);
    match store
        .resolver_atendimento_para_contato(&ctx, phone, push_name)
        .await
    {
        Ok((contato_id, atendimento, is_new)) => ok_reply(
            &env,
            "ResolveAtendimentoParaContatoReply",
            serde_json::json!({
                "status": "success",
                "contato_id": contato_id,
                "atendimento_id": atendimento.id,
                "bot_pode_atender": atendimento.bot_pode_atender,
                "atendente_humano_id": atendimento.atendente_humano_id,
                "is_new": is_new,
            }),
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_update_message_status(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let message_id_whatsapp = match payload_json
        .get("message_id_whatsapp")
        .and_then(|v| v.as_str())
    {
        Some(m) => m,
        None => {
            return erro(
                error_core::AppError::Validation("message_id_whatsapp ausente".into()),
                &env,
            )
        }
    };

    let status = match payload_json.get("status").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("status ausente".into()),
                &env,
            )
        }
    };

    let ctx = contexto_do_envelope(&env);
    match store
        .atualizar_status_mensagem(&ctx, message_id_whatsapp, status)
        .await
    {
        Ok(_) => ok_reply(
            &env,
            "UpdateMessageStatusReply",
            serde_json::json!({ "status": "success" }),
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_aplicar_politica_ticket_kanban(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let atendimento_id = match payload_json.get("atendimento_id").and_then(|v| v.as_i64()) {
        Some(id) => id as i32,
        None => {
            return erro(
                error_core::AppError::Validation("atendimento_id ausente".into()),
                &env,
            )
        }
    };

    let ctx = contexto_do_envelope(&env);
    match store
        .aplicar_politica_ticket_kanban(&ctx, atendimento_id)
        .await
    {
        Ok(outcome) => ok_reply(
            &env,
            "AplicarPoliticaTicketKanbanReply",
            serde_json::json!({
                "status": "success",
                "moved": outcome.moved,
                "ticket_status": outcome.status,
                "etapa_id": outcome.etapa_id,
                "etapa_nome": outcome.etapa_nome,
                "fluxo_id": outcome.fluxo_id,
                "reason": outcome.reason,
            }),
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

/// Move manualmente um atendimento para outra etapa do Kanban (drag-and-drop — WS-6.2).
/// O RBAC fino por fluxo (WS-5a) é aplicado dentro do adapter (`exigir_fluxo`).
async fn handler_move_atendimento_etapa(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let atendimento_id = match payload_json.get("atendimento_id").and_then(|v| v.as_i64()) {
        Some(id) => id as i32,
        None => {
            return erro(
                error_core::AppError::Validation("atendimento_id ausente".into()),
                &env,
            )
        }
    };
    let etapa_destino_id = match payload_json
        .get("etapa_destino_id")
        .and_then(|v| v.as_i64())
    {
        Some(id) => id as i32,
        None => {
            return erro(
                error_core::AppError::Validation("etapa_destino_id ausente".into()),
                &env,
            )
        }
    };
    let motivo = payload_json
        .get("motivo")
        .and_then(|v| v.as_str())
        .unwrap_or_default();

    let ctx = contexto_do_envelope(&env);
    match store
        .mover_etapa_atendimento(&ctx, atendimento_id, etapa_destino_id, motivo)
        .await
    {
        Ok(()) => ok_reply(
            &env,
            "MoveAtendimentoEtapaReply",
            serde_json::json!({ "status": "success" }),
        ),
        // `.into()` preserva o ErrorCode (ex.: PermissionDenied → AuthInsufficientScope),
        // permitindo à borda gRPC-Web diferenciar RBAC negado de erro de banco genérico.
        Err(err) => erro(err.into(), &env),
    }
}

/// Envia (persiste) uma mensagem outbound do atendente humano no thread do atendimento
/// (WS-6.3). Reaproveita `persistir_mensagem` (padrão Outbox já existente); o disparo do
/// envio real ao WhatsApp é feito pelo worker ao consumir "message.persisted" com
/// sender_id="atendente" (N1.3 — ver `resolver_destino_envio_outbound` abaixo).
async fn handler_send_outbound_message(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let atendimento_id = match payload_json.get("atendimento_id").and_then(|v| v.as_i64()) {
        Some(id) => id as i32,
        None => {
            return erro(
                error_core::AppError::Validation("atendimento_id ausente".into()),
                &env,
            )
        }
    };
    // Conteúdo é PII/mensagem do usuário: nunca logar em claro (mesma cautela de PersistMessage).
    let conteudo = payload_json
        .get("conteudo")
        .and_then(|v| v.as_str())
        .unwrap_or_default();
    if conteudo.is_empty() {
        return erro(
            error_core::AppError::Validation("conteudo ausente".into()),
            &env,
        );
    }
    let tipo = payload_json
        .get("tipo")
        .and_then(|v| v.as_str())
        .filter(|t| !t.is_empty())
        .unwrap_or("texto");

    let ctx = contexto_do_envelope(&env);
    match store
        .persistir_mensagem(
            &ctx,
            atendimento_id,
            tipo,
            conteudo,
            "atendente",
            &env.traceparent,
        )
        .await
    {
        Ok(msg) => ok_reply(
            &env,
            "SendOutboundMessageReply",
            serde_json::json!({ "message_id": msg.id }),
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

/// Varredura cross-tenant (scheduler do worker, F4.3b): atendimentos com feedback vencido.
/// `limite`/`ttl_horas` vêm do payload; sem eles, usa defaults conservadores.
async fn handler_listar_feedback_vencido(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let limite = payload_json
        .get("limite")
        .and_then(|v| v.as_i64())
        .unwrap_or(100);
    let ttl_horas = payload_json
        .get("ttl_horas")
        .and_then(|v| v.as_i64())
        .unwrap_or(48);

    let ctx = contexto_do_envelope(&env);
    match store.listar_feedback_vencido(&ctx, limite, ttl_horas).await {
        Ok(list) => ok_reply(
            &env,
            "ListarAtendimentosFeedbackVencidoReply",
            serde_json::json!({ "atendimentos": list }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// Marca um atendimento (tenant-scoped) como tendo o feedback expirado (idempotente).
async fn handler_marcar_feedback_expirado(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let atendimento_id = match payload_json.get("atendimento_id").and_then(|v| v.as_i64()) {
        Some(id) => id as i32,
        None => {
            return erro(
                error_core::AppError::Validation("atendimento_id ausente".into()),
                &env,
            )
        }
    };

    let ctx = contexto_do_envelope(&env);
    match store.marcar_feedback_expirado(&ctx, atendimento_id).await {
        Ok(()) => ok_reply(
            &env,
            "MarcarFeedbackExpiradoReply",
            serde_json::json!({ "status": "ok" }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// Varredura cross-tenant (scheduler do worker, F4.3b): mensagens com mídia vencida.
async fn handler_listar_midias_expiradas(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let limite = payload_json
        .get("limite")
        .and_then(|v| v.as_i64())
        .unwrap_or(100);
    let idade_max_dias = payload_json
        .get("idade_max_dias")
        .and_then(|v| v.as_i64())
        .unwrap_or(30);

    let ctx = contexto_do_envelope(&env);
    match store
        .listar_midias_expiradas(&ctx, limite, idade_max_dias)
        .await
    {
        Ok(list) => ok_reply(
            &env,
            "ListarMidiasExpiradasReply",
            serde_json::json!({ "mensagens": list }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// Marca a mídia de uma mensagem (tenant-scoped) como purga solicitada (idempotente).
async fn handler_marcar_midia_purgada(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let mensagem_id = match payload_json.get("mensagem_id").and_then(|v| v.as_i64()) {
        Some(id) => id as i32,
        None => {
            return erro(
                error_core::AppError::Validation("mensagem_id ausente".into()),
                &env,
            )
        }
    };

    let ctx = contexto_do_envelope(&env);
    match store.marcar_midia_purgada(&ctx, mensagem_id).await {
        Ok(()) => ok_reply(
            &env,
            "MarcarMidiaPurgadaReply",
            serde_json::json!({ "status": "ok" }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// Anexa análise/resumo de mídia + ponteiro do arquivo a uma mensagem já
/// persistida (pipeline de mídia do worker, N6.1). `analise`/`resumo` podem conter
/// transcrição/interpretação (PII): nunca são logados aqui.
async fn handler_anexar_analise_midia(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let mensagem_id = match payload_json.get("mensagem_id").and_then(|v| v.as_i64()) {
        Some(id) => id as i32,
        None => {
            return erro(
                error_core::AppError::Validation("mensagem_id ausente".into()),
                &env,
            )
        }
    };
    let arquivo_midia = payload_json
        .get("arquivo_midia")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let analise_midia = payload_json
        .get("analise")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let resumo_midia = payload_json
        .get("resumo")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    let ctx = contexto_do_envelope(&env);
    match store
        .anexar_analise_midia(
            &ctx,
            mensagem_id,
            arquivo_midia,
            analise_midia,
            resumo_midia,
        )
        .await
    {
        Ok(()) => ok_reply(
            &env,
            "AnexarAnaliseMidiaReply",
            serde_json::json!({ "status": "ok" }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// Lista os fluxos ativos do tenant (setor/nome/descrição) para o worker montar
/// `fluxos_disponiveis` do Responder (N6.3).
async fn handler_listar_fluxos_do_tenant(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let ctx = contexto_do_envelope(&env);
    match store.listar_fluxos_do_tenant(&ctx).await {
        Ok(fluxos) => ok_reply(
            &env,
            "ListarFluxosDoTenantReply",
            serde_json::json!({ "fluxos": fluxos }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// Transfere o atendimento para outro fluxo (transferência automática pela IA, N6.3).
async fn handler_transferir_atendimento_para_fluxo(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let atendimento_id = match payload_json.get("atendimento_id").and_then(|v| v.as_i64()) {
        Some(id) => id as i32,
        None => {
            return erro(
                error_core::AppError::Validation("atendimento_id ausente".into()),
                &env,
            )
        }
    };
    let fluxo_id = match payload_json.get("fluxo_id").and_then(|v| v.as_i64()) {
        Some(id) => id as i32,
        None => {
            return erro(
                error_core::AppError::Validation("fluxo_id ausente".into()),
                &env,
            )
        }
    };

    let ctx = contexto_do_envelope(&env);
    match store
        .transferir_atendimento_para_fluxo(&ctx, atendimento_id, fluxo_id)
        .await
    {
        Ok(outcome) => ok_reply(
            &env,
            "TransferirAtendimentoParaFluxoReply",
            serde_json::json!({
                "transferido": outcome.transferido,
                "fluxo_id": outcome.fluxo_id,
                "fluxo_nome": outcome.fluxo_nome,
                "etapa_id": outcome.etapa_id,
                "etapa_nome": outcome.etapa_nome,
                "reason": outcome.reason,
            }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// Resolve campos personalizados (coletados + pendentes obrigatórios) do
/// atendimento para o Responder — input-only, sem write-back (N6.3).
async fn handler_resolver_campos_atendimento(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let atendimento_id = match payload_json.get("atendimento_id").and_then(|v| v.as_i64()) {
        Some(id) => id as i32,
        None => {
            return erro(
                error_core::AppError::Validation("atendimento_id ausente".into()),
                &env,
            )
        }
    };

    let ctx = contexto_do_envelope(&env);
    match store
        .resolver_campos_atendimento(&ctx, atendimento_id)
        .await
    {
        Ok(campos) => ok_reply(
            &env,
            "ResolverCamposAtendimentoReply",
            serde_json::json!({
                "coletados": campos.coletados,
                "pendentes": campos.pendentes,
            }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// Resolve instância/telefone de destino para o envio outbound de uma mensagem do
/// atendente (elo outbox->outbound, N1.3).
async fn handler_resolver_destino_envio_outbound(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let mensagem_id = match payload_json.get("mensagem_id").and_then(|v| v.as_i64()) {
        Some(id) => id as i32,
        None => {
            return erro(
                error_core::AppError::Validation("mensagem_id ausente".into()),
                &env,
            )
        }
    };

    let ctx = contexto_do_envelope(&env);
    match store
        .resolver_destino_envio_outbound(&ctx, mensagem_id)
        .await
    {
        Ok(Some(destino)) => ok_reply(
            &env,
            "ResolverDestinoEnvioOutboundReply",
            serde_json::to_value(&destino).unwrap_or_default(),
        ),
        Ok(None) => erro(
            error_core::AppError::Database("não encontrado: destino de envio".into()),
            &env,
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// Marca a mensagem outbound (tenant-scoped) como enviada com sucesso ao provedor.
async fn handler_marcar_mensagem_enviada(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let mensagem_id = match payload_json.get("mensagem_id").and_then(|v| v.as_i64()) {
        Some(id) => id as i32,
        None => {
            return erro(
                error_core::AppError::Validation("mensagem_id ausente".into()),
                &env,
            )
        }
    };
    let message_id_whatsapp = payload_json
        .get("message_id_whatsapp")
        .and_then(|v| v.as_str())
        .unwrap_or_default();

    let ctx = contexto_do_envelope(&env);
    match store
        .marcar_mensagem_enviada(&ctx, mensagem_id, message_id_whatsapp)
        .await
    {
        Ok(()) => ok_reply(
            &env,
            "MarcarMensagemEnviadaReply",
            serde_json::json!({ "status": "ok" }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// Marca falha definitiva no envio outbound (tenant-scoped), após esgotar retries.
async fn handler_marcar_mensagem_falha_envio(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let mensagem_id = match payload_json.get("mensagem_id").and_then(|v| v.as_i64()) {
        Some(id) => id as i32,
        None => {
            return erro(
                error_core::AppError::Validation("mensagem_id ausente".into()),
                &env,
            )
        }
    };

    let ctx = contexto_do_envelope(&env);
    match store.marcar_mensagem_falha_envio(&ctx, mensagem_id).await {
        Ok(()) => ok_reply(
            &env,
            "MarcarMensagemFalhaEnvioReply",
            serde_json::json!({ "status": "ok" }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

async fn handler_upsert_contact(store: &dyn ports::ClienteStore, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(_) => serde_json::json!({}),
    };

    let ctx = contexto_do_envelope(&env);
    let telefone = payload_json
        .get("phone")
        .and_then(|v| v.as_str())
        .unwrap_or("5511999999999");
    let nome = payload_json
        .get("name")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());

    match store.salvar_contato(&ctx, telefone, nome).await {
        Ok(contato) => ok_reply(
            &env,
            "UpsertContactReply",
            serde_json::to_value(&contato).unwrap_or_default(),
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_verify_credentials(
    store: &dyn ports::AuthStore,
    audit: &dyn ports::AuditPort,
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

    // Busca o usuário por e-mail ou username (fallback) via port.
    let user_opt = match store.buscar_por_login(email).await {
        Ok(opt) => opt,
        Err(err) => return erro(error_core::AppError::Database(err.to_string()), &env),
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

        // Se não for superusuário, precisamos obter a associação de tenant dele.
        if !user.is_superuser {
            match store.buscar_tenant_user(user.id).await {
                Ok(Some(tu)) => {
                    // Se o vínculo estiver inativo, bloquear o login.
                    if !tu.is_active {
                        return erro(
                            error_core::AppError::Auth("vínculo inativo com o tenant".to_string()),
                            &env,
                        );
                    }
                    tenant_id_str = tu.tenant_id.to_string();
                    role = serde_json::Value::String(tu.role);
                    module_permissions = tu.module_permissions;
                }
                Ok(None) => {
                    return erro(
                        error_core::AppError::Auth("usuário sem tenant associado".to_string()),
                        &env,
                    );
                }
                Err(err) => return erro(error_core::AppError::Database(err.to_string()), &env),
            }
        }

        // Atualiza a data do último login (best-effort; erro apenas logado).
        if let Err(e) = store.registrar_ultimo_login(user.id).await {
            tracing::warn!(
                "Falha ao atualizar último login do usuário {}: {:?}",
                user.id,
                e
            );
        }

        let reply_payload = serde_json::json!({
            "id": user.id,
            "username": user.username,
            "email": user.email,
            "is_superuser": user.is_superuser,
            "tenant_id": tenant_id_str,
            "role": role,
            "module_permissions": module_permissions,
        });
        ok_reply(&env, "VerifyCredentialsReply", reply_payload)
    } else {
        // Credenciais inválidas: registra warning e publica evento de segurança.
        tracing::warn!(
            email = %email,
            traceparent = %env.traceparent,
            "Tentativa de login falhou: credenciais inválidas"
        );

        let tenant_id = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());
        audit
            .publish_security(
                &env.traceparent,
                Some(tenant_id),
                "WARN",
                "login_failed",
                format!("Tentativa de login falhou para o email: {}", email),
                serde_json::json!({ "email": email }),
                None,
            )
            .await;

        erro(
            error_core::AppError::Auth("Credenciais inválidas".to_string()),
            &env,
        )
    }
}

/// RAG (fase N2, `ia_engine`): compõe o contexto de treinamento para uma mensagem
/// já embedada pelo worker (via `ia_engine.Embed`) — busca vetorial pgvector sob
/// RLS de tenant. `distance_threshold` default 0.3 (cosseno), `chunk_top_k` default 3.
async fn handler_query_compose(store: &dyn ports::TreinamentoStore, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let query_embedding: Vec<f32> = match payload_json
        .get("query_embedding")
        .and_then(|v| v.as_array())
    {
        Some(arr) => arr
            .iter()
            .filter_map(|v| v.as_f64())
            .map(|v| v as f32)
            .collect(),
        None => {
            return erro(
                error_core::AppError::Validation("query_embedding ausente ou inválido".into()),
                &env,
            )
        }
    };
    let distance_threshold = payload_json
        .get("distance_threshold")
        .and_then(|v| v.as_f64())
        .unwrap_or(0.3);
    let chunk_top_k = payload_json
        .get("chunk_top_k")
        .and_then(|v| v.as_i64())
        .unwrap_or(3);

    let ctx = contexto_do_envelope(&env);
    match store
        .query_compose(&ctx, query_embedding, distance_threshold, chunk_top_k)
        .await
    {
        Ok(resultado) => ok_reply(
            &env,
            "QueryComposeReply",
            serde_json::json!({
                "comportamento": resultado.comportamento,
                "documentos": resultado.documentos,
            }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
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
        user_agent: (!env.user_agent.is_empty()).then(|| env.user_agent.clone()),
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

async fn handler_get_user_identity(store: &dyn ports::AuthStore, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id = payload_json.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;

    match store.buscar_por_id(id).await {
        Ok(Some(user)) => {
            let mut tenant_id_str = String::new();
            let mut role = serde_json::Value::Null;
            let mut module_permissions = serde_json::Value::Null;

            if !user.is_superuser {
                if let Ok(Some(tu)) = store.buscar_tenant_user(user.id).await {
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

/// Resolve os `flow_permissions` (IDs de fluxo Kanban) do vínculo TenantUser de um usuário.
/// Fonte de verdade para o `FlowPermissionsProvider` do runtime_api (RPC + cache curto).
async fn handler_get_user_flow_permissions(
    store: &dyn ports::AuthStore,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let user_id = payload_json
        .get("user_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;

    match store.buscar_tenant_user(user_id).await {
        Ok(Some(tu)) => {
            let permissions: Vec<i32> = tu
                .flow_permissions
                .as_array()
                .map(|arr| {
                    arr.iter()
                        .filter_map(|v| v.as_i64())
                        .map(|v| v as i32)
                        .collect()
                })
                .unwrap_or_default();
            ok_reply(
                &env,
                "GetUserFlowPermissionsReply",
                serde_json::json!({ "permissions": permissions }),
            )
        }
        Ok(None) => ok_reply(
            &env,
            "GetUserFlowPermissionsReply",
            serde_json::json!({ "permissions": Vec::<i32>::new() }),
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_list_core_settings(
    store: &dyn ports::OperacionalStore,
    env: Envelope,
) -> Envelope {
    match store.listar_core_settings().await {
        Ok(settings) => {
            let list: Vec<serde_json::Value> = settings
                .iter()
                .map(|s| {
                    serde_json::json!({
                        "key": s.key,
                        "value": s.value,
                        "encrypted": s.encrypted,
                        "description": s.description,
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
    store: &dyn ports::OperacionalStore,
    audit: &dyn ports::AuditPort,
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

    match store
        .upsert_core_setting(key, raw_value, encrypted, description)
        .await
    {
        Ok(()) => {
            audit
                .publish(
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
    store: &dyn ports::OperacionalStore,
    audit: &dyn ports::AuditPort,
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

    match store.deletar_core_setting(key).await {
        Ok(true) => {
            audit
                .publish(
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
        Ok(false) => erro(
            error_core::AppError::Validation("configuração inexistente".to_string()),
            &env,
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_get_tenant_config(store: &dyn ports::OperacionalStore, env: Envelope) -> Envelope {
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

    match store.obter_tenant_config(tenant_id).await {
        Ok(Some(cfg)) => ok_reply(&env, "GetTenantConfigReply", cfg),
        Ok(None) => ok_reply(&env, "GetTenantConfigReply", serde_json::json!({})),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

/// RPC interno (fase N2, `ia_engine`): resolve a config de IA do tenant DA
/// CONVERSA (não um tenant alvo arbitrário — ao contrário de `GetTenantConfig`,
/// que é o CRUD do painel admin). A api_key vem descriptografada de verdade; este
/// RPC nunca deve ser exposto ao painel/browser (só worker↔data_postgres).
async fn handler_resolver_config_ia(
    store: &dyn ports::OperacionalStore,
    env: Envelope,
) -> Envelope {
    let ctx = contexto_do_envelope(&env);
    match store.resolver_config_ia(ctx.tenant_id).await {
        Ok(cfg) => ok_reply(
            &env,
            "ResolverConfigIaReply",
            serde_json::json!({
                "dados_empresa": cfg.dados_empresa,
                "persona_bot": cfg.persona_bot,
                "llm_provider": cfg.llm_provider,
                "llm_model": cfg.llm_model,
                "llm_temperature": cfg.llm_temperature,
                "embeddings_provider": cfg.embeddings_provider,
                "embeddings_model": cfg.embeddings_model,
                "similarity_threshold": cfg.similarity_threshold,
                "vector_distance_threshold": cfg.vector_distance_threshold,
                "api_key": cfg.api_key,
                "embeddings_api_key": cfg.embeddings_api_key,
            }),
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_update_tenant_config(
    store: &dyn ports::OperacionalStore,
    audit: &dyn ports::AuditPort,
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

    // O adapter encapsula a transação, a cifragem das chaves e a invalidação do cache;
    // retorna apenas os NOMES das chaves de API alteradas (nunca os valores).
    match store.atualizar_tenant_config(tenant_id, payload_json).await {
        Ok(chaves_alteradas) => {
            audit
                .publish(
                    &env,
                    "tenant_config_updated",
                    "Configurações do tenant atualizadas".to_string(),
                    serde_json::json!({}),
                )
                .await;

            // Evento dedicado e mais severo (WARN) quando chaves de API mudam (catálogo §12
            // + diretriz de segurança §4.2). Registra apenas os NOMES, nunca os valores.
            if !chaves_alteradas.is_empty() {
                audit
                    .publish(
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
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

// --- FASE 2: Handlers de Tenants ---

async fn handler_list_tenants(store: &dyn ports::TenantStore, env: Envelope) -> Envelope {
    match store.listar_todos().await {
        Ok(tenants) => {
            let list: Vec<serde_json::Value> = tenants.iter().map(tenant_to_json).collect();
            ok_reply(
                &env,
                "ListTenantsReply",
                serde_json::json!({ "tenants": list }),
            )
        }
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_get_tenant(store: &dyn ports::TenantStore, env: Envelope) -> Envelope {
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

    match store.buscar_por_id(tenant_id).await {
        Ok(Some(t)) => ok_reply(
            &env,
            "GetTenantReply",
            serde_json::json!({ "tenant": tenant_to_json(&t) }),
        ),
        Ok(None) => erro(
            error_core::AppError::Validation("Tenant não encontrado".to_string()),
            &env,
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_update_tenant(
    store: &dyn ports::TenantStore,
    audit: &dyn ports::AuditPort,
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

    match store
        .atualizar_cadastro(tenant_id, name, slug, owner_id, email, phone)
        .await
    {
        Ok(true) => {
            audit
                .publish(
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
        Ok(false) => erro(
            error_core::AppError::Validation("Tenant inexistente".to_string()),
            &env,
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_set_tenant_active(
    store: &dyn ports::TenantStore,
    audit: &dyn ports::AuditPort,
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

    match store.definir_ativo(tenant_id, active).await {
        Ok(true) => {
            let status_str = if active { "ativado" } else { "desativado" };
            audit
                .publish(
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
        Ok(false) => erro(
            error_core::AppError::Validation("Tenant inexistente".to_string()),
            &env,
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_generate_access_code(
    store: &dyn ports::TenantStore,
    audit: &dyn ports::AuditPort,
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

    match store.gerar_access_code(tenant_id, &code).await {
        Ok(true) => {
            audit
                .publish(
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
        Ok(false) => erro(
            error_core::AppError::Validation("Tenant inexistente".to_string()),
            &env,
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

// --- FASE 2: Handlers de Billing ---

async fn handler_list_plans(store: &dyn ports::PlansStore, env: Envelope) -> Envelope {
    match store.listar_planos().await {
        Ok(plans) => ok_reply(
            &env,
            "ListPlansReply",
            serde_json::json!({ "plans": plans }),
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

// --- N4.2: verificação de quota/inadimplência (chamado internamente por
// webhook_ingress/data_whatsapp via QuotaGuard antes de ingestão/envio) ---

#[tracing::instrument(skip_all, fields(rpc = "CheckQuota", tenant_id = %env.tenant_id))]
async fn handler_check_quota(
    store: &dyn ports::QuotaStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let recurso = payload_json
        .get("recurso")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    // `auditar` = a chamada é um ponto de ENFORCEMENT (ex.: provisionamento de
    // instância no data_whatsapp), onde `quota.excedida`/`tenant.bloqueado_inadimplencia`
    // são eventos pontuais legítimos. O caminho quente de ingestão (webhook_ingress)
    // chama CheckQuota só para LER `inadimplente` e envia `auditar=false` — do
    // contrário um tenant saudável no limite do plano geraria uma linha de auditoria
    // por mensagem recebida (inundação da trilha, contra doc 08 §4.2).
    let auditar = payload_json
        .get("auditar")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    let tenant_id = match Uuid::parse_str(&env.tenant_id) {
        Ok(u) => u,
        Err(_) => {
            return erro(
                error_core::AppError::Validation("tenant_id inválido".to_string()),
                &env,
            )
        }
    };

    match store.verificar_quota(tenant_id, recurso).await {
        Ok(status) => {
            let excedido = status
                .get("excedido")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            let inadimplente = status
                .get("inadimplente")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);

            if excedido && auditar {
                tracing::warn!(tenant_id = %env.tenant_id, recurso, "quota excedida");
                audit
                    .publish(
                        &env,
                        "quota.excedida",
                        format!("Quota de '{}' excedida", recurso),
                        status.clone(),
                    )
                    .await;
            }
            if inadimplente && auditar {
                tracing::warn!(tenant_id = %env.tenant_id, "assinatura inadimplente");
                audit
                    .publish(
                        &env,
                        "tenant.bloqueado_inadimplencia",
                        "Assinatura fora de dia; ingestão/envio sujeitos a bloqueio".to_string(),
                        status.clone(),
                    )
                    .await;
            }
            ok_reply(&env, "CheckQuotaReply", status)
        }
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_create_plan(
    store: &dyn ports::PlansStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
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

    match store
        .criar_plano(name, description, price_dec, max_instances, max_departments)
        .await
    {
        Ok(plan) => {
            audit
                .publish(
                    &env,
                    "billing_plan_created",
                    format!("Plano de faturamento '{}' criado", name),
                    serde_json::json!({ "id": plan.get("id").cloned().unwrap_or_default(), "name": name }),
                )
                .await;
            ok_reply(&env, "CreatePlanReply", serde_json::json!({ "plan": plan }))
        }
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_update_plan(
    store: &dyn ports::PlansStore,
    audit: &dyn ports::AuditPort,
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

    match store
        .atualizar_plano(
            id,
            name,
            description,
            price_dec,
            max_instances,
            max_departments,
            active,
        )
        .await
    {
        Ok(true) => {
            audit
                .publish(
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
        Ok(false) => erro(
            error_core::AppError::Validation("Plano inexistente".to_string()),
            &env,
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_list_subscriptions(store: &dyn ports::PlansStore, env: Envelope) -> Envelope {
    match store.listar_subscriptions().await {
        Ok(subs) => ok_reply(
            &env,
            "ListSubscriptionsReply",
            serde_json::json!({ "subscriptions": subs }),
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_register_payment(
    store: &dyn ports::PlansStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
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
    let recorded_by = if user_id > 0 { Some(user_id) } else { None };

    match store
        .registrar_pagamento(
            tenant_id,
            amount,
            payment_date,
            payment_method,
            period_start,
            period_end,
            notes,
            recorded_by,
        )
        .await
    {
        Ok(payment) => {
            // Auditoria de pagamento registra apenas metadados (id/valor/tenant),
            // nunca dados sensíveis de pagamento (diretriz de segurança §4.2).
            audit
                .publish(
                    &env,
                    "payment_registered",
                    format!(
                        "Pagamento de R$ {} registrado para o tenant '{}'",
                        amount, tenant_id_str
                    ),
                    serde_json::json!({ "tenant_id": tenant_id_str, "amount": amount.to_string() }),
                )
                .await;
            ok_reply(
                &env,
                "RegisterPaymentReply",
                serde_json::json!({ "payment": payment }),
            )
        }
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_list_payments(store: &dyn ports::PlansStore, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let tenant_id_str = payload_json
        .get("tenant_id")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    let tenant_id = if tenant_id_str.is_empty() {
        None
    } else {
        match Uuid::parse_str(tenant_id_str) {
            Ok(u) => Some(u),
            Err(_) => {
                return erro(
                    error_core::AppError::Validation("ID do tenant inválido".to_string()),
                    &env,
                )
            }
        }
    };

    match store.listar_pagamentos(tenant_id).await {
        Ok(payments) => ok_reply(
            &env,
            "ListPaymentsReply",
            serde_json::json!({ "payments": payments }),
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_get_evolution_instance_by_tenant(
    store: &dyn ports::OperacionalStore,
    env: Envelope,
) -> Envelope {
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

    match store.obter_evolution_instance(tenant_uuid).await {
        Ok(Some((name, api_key))) => ok_reply(
            &env,
            "GetEvolutionInstanceByTenantReply",
            serde_json::json!({ "name": name, "api_key": api_key }),
        ),
        Ok(None) => ok_reply(
            &env,
            "GetEvolutionInstanceByTenantReply",
            serde_json::json!({ "name": "", "api_key": "" }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

async fn handler_list_feature_flags(
    store: &dyn ports::OperacionalStore,
    env: Envelope,
) -> Envelope {
    match store.listar_feature_flags().await {
        Ok(flags) => ok_reply(
            &env,
            "ListFeatureFlagsReply",
            serde_json::json!({ "flags": flags }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

async fn handler_set_feature_flag(
    store: &dyn ports::OperacionalStore,
    audit: &dyn ports::AuditPort,
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

    match store.set_feature_flag(key, enabled_globally).await {
        Ok(()) => {
            // Auditoria obrigatória: toda mutação de feature flag gera evento (catálogo §12).
            // O `context` registra apenas a chave, o escopo e o novo valor — nunca segredos.
            audit
                .publish(
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
    store: &dyn ports::OperacionalStore,
    audit: &dyn ports::AuditPort,
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

    match store
        .set_feature_flag_override(key, tenant_uuid, enabled, remove_override)
        .await
    {
        Ok(()) => {
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
            audit
                .publish(
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

async fn handler_query_audit_log(store: &dyn ports::OperacionalStore, env: Envelope) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let tenant_id = payload
        .get("tenant_id")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .and_then(|s| Uuid::parse_str(s).ok());
    let event_type = payload
        .get("event_type")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());
    let limit = payload.get("limit").and_then(|v| v.as_i64()).unwrap_or(50) as i32;
    let offset = payload.get("offset").and_then(|v| v.as_i64()).unwrap_or(0) as i32;

    match store
        .query_audit_log(tenant_id, event_type, limit, offset)
        .await
    {
        Ok((list, total_count)) => ok_reply(
            &env,
            "QueryAuditLogReply",
            serde_json::json!({
                "entries": list,
                "total_count": total_count as i32
            }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

async fn handler_get_service_health(
    store: &dyn ports::OperacionalStore,
    env: Envelope,
) -> Envelope {
    let services = store.service_health().await;
    ok_reply(
        &env,
        "GetServiceHealthReply",
        serde_json::json!({ "services": services }),
    )
}

async fn handler_get_dashboard_summary(
    store: &dyn ports::OperacionalStore,
    env: Envelope,
) -> Envelope {
    match store.dashboard_summary().await {
        Ok(summary) => ok_reply(&env, "GetDashboardSummaryReply", summary),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

async fn handler_export_tenants_csv(store: &dyn ports::TenantStore, env: Envelope) -> Envelope {
    match store.listar_todos().await {
        Ok(tenants) => {
            let mut csv_string = String::new();
            csv_string.push_str("id,name,slug,email,phone,active,created_at\n");
            for t in &tenants {
                let escaped_name = t.name.replace('"', "\"\"");
                csv_string.push_str(&format!(
                    "{},\"{}\",{},{},{},{},{}\n",
                    t.id,
                    escaped_name,
                    t.slug,
                    t.email,
                    t.phone.clone().unwrap_or_default(),
                    t.active,
                    t.created_at.to_rfc3339()
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
/// Resultado puro do parse do payload de criação de instância (sem I/O).
struct CreateWhatsappInput {
    name: String,
    api_key: String,
    provider: String,
}

/// Parse PURO do payload de criação — testável sem datastore.
fn parse_create_whatsapp(env: &Envelope) -> Result<CreateWhatsappInput, error_core::AppError> {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload)
        .map_err(|e| error_core::AppError::Validation(e.to_string()))?;

    let name = payload
        .get("name")
        .and_then(|v| v.as_str())
        .ok_or_else(|| error_core::AppError::Validation("name ausente".into()))?
        .to_string();
    let api_key = payload
        .get("api_key")
        .and_then(|v| v.as_str())
        .ok_or_else(|| error_core::AppError::Validation("api_key ausente".into()))?
        .to_string();
    let provider = payload
        .get("provider")
        .and_then(|v| v.as_str())
        .ok_or_else(|| error_core::AppError::Validation("provider ausente".into()))?
        .to_string();

    Ok(CreateWhatsappInput {
        name,
        api_key,
        provider,
    })
}

/// Handler refatorado: depende SOMENTE das ports (DIP). Sem pool, sem transação.
async fn handler_create_whatsapp_instance_record(
    store: &dyn ports::WhatsappStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let input = match parse_create_whatsapp(&env) {
        Ok(v) => v,
        Err(e) => return erro(e, &env),
    };
    let ctx = contexto_do_envelope(&env);

    match store
        .criar_instancia(&ctx, &input.name, &input.api_key, &input.provider)
        .await
    {
        Ok(inst) => {
            audit
                .publish(
                    &env,
                    "whatsapp_instance.created",
                    format!("instância '{}' criada", input.name),
                    serde_json::json!({ "instance_name": input.name, "provider": input.provider }),
                )
                .await;
            tracing::info!(instance_name = %input.name, "instância WhatsApp criada");
            ok_reply(
                &env,
                "CreateWhatsappInstanceRecordReply",
                serde_json::to_value(&inst).unwrap_or_default(),
            )
        }
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

async fn handler_get_whatsapp_instance(
    store: &dyn ports::WhatsappStore,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let id = match payload.get("id").and_then(|v| v.as_i64()) {
        Some(i) => i as i32,
        None => return erro(error_core::AppError::Validation("id ausente".into()), &env),
    };

    let ctx = contexto_do_envelope(&env);
    match store.buscar_instancia(&ctx, id).await {
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

async fn handler_list_whatsapp_instances(
    store: &dyn ports::WhatsappStore,
    env: Envelope,
) -> Envelope {
    let ctx = contexto_do_envelope(&env);
    match store.listar_ativas(&ctx).await {
        Ok(list) => ok_reply(
            &env,
            "ListWhatsappInstancesReply",
            serde_json::json!({ "instances": list }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

async fn handler_admin_list_all_connected_instances(
    store: &dyn ports::WhatsappStore,
    env: Envelope,
) -> Envelope {
    let ctx = contexto_do_envelope(&env);
    match store.admin_listar_conectadas(&ctx).await {
        Ok(list) => ok_reply(
            &env,
            "AdminListAllConnectedInstancesReply",
            serde_json::json!({ "instances": list }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

async fn handler_admin_deletar_instancia(
    store: &dyn ports::WhatsappStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let id = match payload.get("id").and_then(|v| v.as_i64()) {
        Some(i) => i as i32,
        None => return erro(error_core::AppError::Validation("id ausente".into()), &env),
    };

    let ctx = contexto_do_envelope(&env);
    match store.admin_deletar_instancia(&ctx, id).await {
        Ok(_) => {
            audit
                .publish(
                    &env,
                    "whatsapp_instance.deleted",
                    format!("instância '{}' deletada pelo admin", id),
                    serde_json::json!({ "instance_id": id }),
                )
                .await;
            ok_reply(
                &env,
                "AdminDeletarInstanciaReply",
                serde_json::json!({ "status": "success" }),
            )
        }
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

async fn handler_atualizar_estado_instancia(
    store: &dyn ports::WhatsappStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
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

    let ctx = contexto_do_envelope(&env);
    match store.atualizar_estado(&ctx, id, connection_state).await {
        Ok(_) => {
            audit
                .publish(
                    &env,
                    "whatsapp_instance.state_updated",
                    format!(
                        "estado da instância '{}' atualizado para '{}'",
                        id, connection_state
                    ),
                    serde_json::json!({ "instance_id": id, "connection_state": connection_state }),
                )
                .await;
            ok_reply(
                &env,
                "AtualizarEstadoInstanciaReply",
                serde_json::json!({ "status": "success" }),
            )
        }
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

async fn handler_atualizar_instancia_provider_id(
    store: &dyn ports::WhatsappStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
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

    let phone_number = payload
        .get("phone_number")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());

    let ctx = contexto_do_envelope(&env);
    match store
        .atualizar_provider_id(&ctx, id, instance_id, phone_number.clone())
        .await
    {
        Ok(_) => {
            audit
                .publish(
                    &env,
                    "whatsapp_instance.provider_updated",
                    format!("provider id da instância '{}' atualizado para '{}'", id, instance_id),
                    serde_json::json!({ "instance_id": id, "provider_id": instance_id, "phone_number": phone_number }),
                )
                .await;
            ok_reply(
                &env,
                "AtualizarInstanciaProviderIdReply",
                serde_json::json!({ "status": "success" }),
            )
        }
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

async fn handler_verify_whatsapp_instance_token(
    store: &dyn ports::WhatsappStore,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let id = match payload.get("id").and_then(|v| v.as_i64()) {
        Some(i) => i as i32,
        None => return erro(error_core::AppError::Validation("id ausente".into()), &env),
    };

    let token = match payload.get("token").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("token ausente".into()),
                &env,
            )
        }
    };

    let ctx = contexto_do_envelope(&env);
    match store.verificar_token(&ctx, id, token).await {
        Ok(Some(inst)) => ok_reply(
            &env,
            "VerifyWhatsappInstanceTokenReply",
            serde_json::json!({
                "valid": true,
                "phone_number": inst.phone_number,
            }),
        ),
        Ok(None) => ok_reply(
            &env,
            "VerifyWhatsappInstanceTokenReply",
            serde_json::json!({
                "valid": false,
                "phone_number": serde_json::Value::Null,
            }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

async fn handler_is_phone_whitelisted(store: &dyn ports::WhatsappStore, env: Envelope) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let phone = match payload.get("phone").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("phone ausente".into()),
                &env,
            )
        }
    };

    let ctx = contexto_do_envelope(&env);
    match store.verificar_telefone_whitelist(&ctx, phone).await {
        Ok(whitelisted) => ok_reply(
            &env,
            "IsPhoneWhitelistedReply",
            serde_json::json!({ "whitelisted": whitelisted }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// Testes unitários do domínio WhatsApp (Fase 1, piloto Ports & Adapters).
///
/// Substituem o antigo `test_handler_whatsapp_instance_flow` (que abria o banco
/// real via `setup_teste()`): aqui os handlers dependem apenas das ports e usam
/// mocks `mockall`, então rodam no caminho rápido `--lib --bins` SEM túnel SSH.
/// A cobertura de SQL/RLS real vive em
/// `crates/infrastructure_postgres/tests/integracoes/`.
#[cfg(test)]
mod tests_whatsapp_unit {
    use super::*;
    use crate::ports::{MockAuditPort, MockWhatsappStore};
    use contracts::{Envelope, MessageKind};
    use infrastructure_postgres::integracoes::whatsapp::WhatsappInstance;

    /// Helper: monta um Envelope mínimo com payload arbitrário.
    fn envelope_com_payload(method: &str, payload: serde_json::Value) -> Envelope {
        Envelope {
            kind: MessageKind::Request as i32,
            method: method.to_string(),
            tenant_id: uuid::Uuid::new_v4().to_string(),
            traceparent: "00-trace-span-01".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            ..Default::default()
        }
    }

    /// Instância fake retornada pelo mock no happy path.
    fn instancia_fake(name: &str) -> WhatsappInstance {
        WhatsappInstance {
            id: 1,
            tenant_id: uuid::Uuid::nil(),
            name: name.to_string(),
            instance_id: None,
            api_key: "k".to_string(),
            phone_number: None,
            active: true,
            connection_state: "close".to_string(),
            last_state_check: None,
            media_storage_backend: "r2".to_string(),
            provider: "evolution".to_string(),
            subscribed_events: serde_json::json!([]),
            last_connection_state: None,
            created_at: chrono::Utc::now(),
        }
    }

    /// FAIL-CLOSED: payload sem api_key deve retornar erro de validação
    /// e a port NUNCA pode ser chamada (não toca o banco).
    #[tokio::test]
    async fn create_instance_rejects_missing_api_key() {
        // Arrange
        let mut store = MockWhatsappStore::new();
        store.expect_criar_instancia().never(); // fail-closed: persistência não pode ocorrer
        let mut audit = MockAuditPort::new();
        audit.expect_publish().never(); // sem auditoria em payload inválido
        let env = envelope_com_payload(
            "CreateWhatsappInstanceRecord",
            serde_json::json!({ "name": "inst1", "provider": "evolution" }), // api_key ausente
        );

        // Act
        let resp = handler_create_whatsapp_instance_record(&store, &audit, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Error as i32);
        let err = resp.error.expect("deveria ter envelope de erro");
        // Valida a VARIANTE/código do erro, não apenas is_err().
        assert_eq!(
            err.code, "VALIDATION_FAILED",
            "esperava erro de validação, veio: {err:?}"
        );
        assert!(
            err.message.contains("api_key"),
            "mensagem deveria citar o campo ausente: {err:?}"
        );
    }

    /// HAPPY PATH: payload válido chama a port uma vez, publica auditoria com o
    /// event_type estável e devolve Reply com a instância serializada.
    #[tokio::test]
    async fn create_instance_persists_and_audits_on_valid_payload() {
        // Arrange
        let mut store = MockWhatsappStore::new();
        store
            .expect_criar_instancia()
            .times(1)
            .returning(|_ctx, name, _api_key, _provider| Ok(instancia_fake(name)));
        let mut audit = MockAuditPort::new();
        audit
            .expect_publish()
            .withf(|_, event, _, _| event == "whatsapp_instance.created")
            .times(1)
            .returning(|_, _, _, _| ());
        let env = envelope_com_payload(
            "CreateWhatsappInstanceRecord",
            serde_json::json!({ "name": "inst1", "api_key": "secret", "provider": "evolution" }),
        );

        // Act
        let resp = handler_create_whatsapp_instance_record(&store, &audit, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        assert_eq!(resp.method, "CreateWhatsappInstanceRecordReply");
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(body["name"], "inst1");
    }

    /// FAIL-CLOSED: erro de persistência da port vira erro de banco no envelope,
    /// e a auditoria NUNCA é publicada (mutação não confirmada).
    #[tokio::test]
    async fn create_instance_maps_store_error_and_skips_audit() {
        // Arrange
        let mut store = MockWhatsappStore::new();
        store
            .expect_criar_instancia()
            .times(1)
            .returning(|_, _, _, _| {
                // Qualquer DbError é mapeado pelo handler para AppError::Database;
                // ConfigError serve como falha de persistência simulada.
                Err(infrastructure_postgres::DbError::ConfigError(
                    "falha simulada".to_string(),
                ))
            });
        let mut audit = MockAuditPort::new();
        audit.expect_publish().never(); // sem auditoria quando a persistência falha
        let env = envelope_com_payload(
            "CreateWhatsappInstanceRecord",
            serde_json::json!({ "name": "inst1", "api_key": "secret", "provider": "evolution" }),
        );

        // Act
        let resp = handler_create_whatsapp_instance_record(&store, &audit, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Error as i32);
        let err = resp.error.expect("deveria ter envelope de erro");
        assert_eq!(
            err.category,
            contracts::ErrorCategory::Internal as i32,
            "erro de banco deveria mapear para categoria interna: {err:?}"
        );
    }

    /// HAPPY PATH de leitura: list não publica auditoria e devolve a lista.
    #[tokio::test]
    async fn list_instances_returns_reply_without_audit() {
        // Arrange
        let mut store = MockWhatsappStore::new();
        store
            .expect_listar_ativas()
            .times(1)
            .returning(|_ctx| Ok(vec![instancia_fake("inst1")]));
        let env = envelope_com_payload("ListWhatsappInstances", serde_json::json!({}));

        // Act
        let resp = handler_list_whatsapp_instances(&store, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(body["instances"].as_array().unwrap().len(), 1);
    }

    /// HAPPY PATH: delete admin confirma persistência e publica o evento de auditoria.
    #[tokio::test]
    async fn admin_delete_persists_and_audits() {
        // Arrange
        let mut store = MockWhatsappStore::new();
        store
            .expect_admin_deletar_instancia()
            .times(1)
            .returning(|_ctx, _id| Ok(()));
        let mut audit = MockAuditPort::new();
        audit
            .expect_publish()
            .withf(|_, event, _, _| event == "whatsapp_instance.deleted")
            .times(1)
            .returning(|_, _, _, _| ());
        let env = envelope_com_payload("AdminDeletarInstancia", serde_json::json!({ "id": 7 }));

        // Act
        let resp = handler_admin_deletar_instancia(&store, &audit, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Reply as i32);
    }

    /// FAIL-CLOSED: delete admin sem id retorna validação e NÃO chama a port nem audita.
    #[tokio::test]
    async fn admin_delete_rejects_missing_id() {
        // Arrange
        let mut store = MockWhatsappStore::new();
        store.expect_admin_deletar_instancia().never();
        let mut audit = MockAuditPort::new();
        audit.expect_publish().never();
        let env = envelope_com_payload("AdminDeletarInstancia", serde_json::json!({}));

        // Act
        let resp = handler_admin_deletar_instancia(&store, &audit, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Error as i32);
        let err = resp.error.expect("deveria ter envelope de erro");
        assert_eq!(err.code, "VALIDATION_FAILED", "veio: {err:?}");
    }

    #[tokio::test]
    async fn verify_token_success() {
        let mut store = MockWhatsappStore::new();
        store
            .expect_verificar_token()
            .times(1)
            .returning(|_ctx, id, token| {
                assert_eq!(id, 1);
                assert_eq!(token, "meu-token");
                Ok(Some(instancia_fake("inst1")))
            });

        let env = envelope_com_payload(
            "VerifyWhatsappInstanceToken",
            serde_json::json!({ "id": 1, "token": "meu-token" }),
        );
        let resp = handler_verify_whatsapp_instance_token(&store, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert!(body["valid"].as_bool().unwrap());
    }

    #[tokio::test]
    async fn is_phone_whitelisted_true() {
        let mut store = MockWhatsappStore::new();
        store
            .expect_verificar_telefone_whitelist()
            .times(1)
            .returning(|_ctx, phone| {
                assert_eq!(phone, "5511999999999");
                Ok(true)
            });

        let env = envelope_com_payload(
            "IsPhoneWhitelisted",
            serde_json::json!({ "phone": "5511999999999" }),
        );
        let resp = handler_is_phone_whitelisted(&store, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert!(body["whitelisted"].as_bool().unwrap());
    }
}

/// Testes unitários do domínio Tenant (handlers via ports, SEM banco). A cobertura
/// de SQL/RLS real vive em `crates/infrastructure_postgres/tests/integracoes/`.
#[cfg(test)]
mod tests_tenant_unit {
    use super::*;
    use crate::ports::{MockAuditPort, MockTenantStore};
    use contracts::{Envelope, MessageKind};
    use infrastructure_postgres::tenants::tenants::{Tenant, TenantUser};

    /// Helper: monta um Envelope mínimo com payload arbitrário.
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

    /// Tenant fake retornado pelo mock no happy path.
    fn tenant_fake(name: &str) -> Tenant {
        Tenant {
            id: uuid::Uuid::nil(),
            name: name.to_string(),
            slug: "slug".to_string(),
            api_key: "k".to_string(),
            owner_id: 1,
            email: "t@e.com".to_string(),
            phone: None,
            active: true,
            setup_completed: false,
            onboarding_step: 0,
            access_code: None,
            created_at: chrono::Utc::now(),
            updated_at: chrono::Utc::now(),
        }
    }

    fn tenant_user_fake(tenant_id: uuid::Uuid, user_id: i32) -> TenantUser {
        TenantUser {
            id: 1,
            user_id,
            tenant_id,
            role: "admin".to_string(),
            module_permissions: serde_json::json!([]),
            flow_permissions: serde_json::json!([]),
            is_active: true,
            created_at: chrono::Utc::now(),
            created_by_id: None,
        }
    }

    /// HAPPY PATH: criação chama a port uma vez, publica `tenant_created` e devolve Reply.
    #[tokio::test]
    async fn create_tenant_persists_and_audits() {
        // Arrange
        let mut store = MockTenantStore::new();
        store
            .expect_criar()
            .times(1)
            .returning(|name, _slug, _email, _phone| Ok(tenant_fake(name)));
        // O handler cria o primeiro TenantUser admin do tenant recém-criado.
        store
            .expect_criar_primeiro_admin()
            .times(1)
            .returning(|tenant_id, owner_id, _perms| Ok(tenant_user_fake(tenant_id, owner_id)));
        let mut audit = MockAuditPort::new();
        audit
            .expect_publish()
            .withf(|_, event, _, _| event == "tenant_created")
            .times(1)
            .returning(|_, _, _, _| ());
        // O bootstrap do 1º admin também é evento crítico auditado (doc 08 §4.2).
        audit
            .expect_publish()
            .withf(|_, event, _, _| event == "tenant_user_bootstrap_admin")
            .times(1)
            .returning(|_, _, _, _| ());
        let env = envelope_com_payload(
            "CreateTenant",
            serde_json::json!({ "name": "Acme", "slug": "acme", "email": "a@b.com" }),
        );

        // Act
        let resp = handler_create_tenant(&store, &audit, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        assert_eq!(resp.method, "CreateTenantReply");
    }

    /// FAIL-CLOSED: erro de persistência vira erro interno e NÃO publica auditoria.
    #[tokio::test]
    async fn create_tenant_maps_store_error_and_skips_audit() {
        // Arrange
        let mut store = MockTenantStore::new();
        store.expect_criar().times(1).returning(|_, _, _, _| {
            Err(infrastructure_postgres::DbError::ConfigError(
                "falha simulada".to_string(),
            ))
        });
        let mut audit = MockAuditPort::new();
        audit.expect_publish().never();
        let env = envelope_com_payload("CreateTenant", serde_json::json!({ "name": "Acme" }));

        // Act
        let resp = handler_create_tenant(&store, &audit, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Error as i32);
        let err = resp.error.expect("deveria ter envelope de erro");
        assert_eq!(err.category, contracts::ErrorCategory::Internal as i32);
    }

    /// FAIL-CLOSED: tenant inexistente no update retorna validação e NÃO audita.
    #[tokio::test]
    async fn update_tenant_missing_returns_validation_without_audit() {
        // Arrange
        let mut store = MockTenantStore::new();
        store
            .expect_atualizar_cadastro()
            .times(1)
            .returning(|_, _, _, _, _, _| Ok(false));
        let mut audit = MockAuditPort::new();
        audit.expect_publish().never();
        let env = envelope_com_payload(
            "UpdateTenant",
            serde_json::json!({ "id": uuid::Uuid::nil().to_string(), "name": "X", "slug": "x" }),
        );

        // Act
        let resp = handler_update_tenant(&store, &audit, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Error as i32);
        let err = resp.error.expect("deveria ter envelope de erro");
        assert_eq!(err.code, "VALIDATION_FAILED", "veio: {err:?}");
    }

    /// FAIL-CLOSED: id inválido em get_tenant nunca chama a port.
    #[tokio::test]
    async fn get_tenant_rejects_invalid_id() {
        // Arrange
        let mut store = MockTenantStore::new();
        store.expect_buscar_por_id().never();
        let env = envelope_com_payload("GetTenant", serde_json::json!({ "id": "nao-eh-uuid" }));

        // Act
        let resp = handler_get_tenant(&store, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Error as i32);
        let err = resp.error.expect("deveria ter envelope de erro");
        assert_eq!(err.code, "VALIDATION_FAILED", "veio: {err:?}");
    }
}

/// Testes unitários do domínio Auth (handlers via ports, SEM banco). A cobertura
/// de SQL/RLS real vive em `crates/infrastructure_postgres/tests/integracoes/`.
#[cfg(test)]
mod tests_auth_unit {
    use super::*;
    use crate::ports::{MockAuditPort, MockAuthStore};
    use contracts::{Envelope, MessageKind};

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

    /// FAIL-CLOSED: usuário inexistente → erro de credenciais e auditoria de
    /// `login_failed` publicada (segurança), sem registrar último login.
    #[tokio::test]
    async fn verify_rejects_unknown_user_and_audits() {
        // Arrange
        let mut store = MockAuthStore::new();
        store
            .expect_buscar_por_login()
            .times(1)
            .returning(|_| Ok(None));
        store.expect_registrar_ultimo_login().never();
        let mut audit = MockAuditPort::new();
        audit
            .expect_publish_security()
            .withf(|_, _, _, event, _, _, _| event == "login_failed")
            .times(1)
            .returning(|_, _, _, _, _, _, _| ());
        let env = envelope_com_payload(
            "VerifyCredentials",
            serde_json::json!({ "email": "x@y.com", "password": "errada" }),
        );

        // Act
        let resp = handler_verify_credentials(&store, &audit, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Error as i32);
        assert!(resp.error.is_some(), "deveria ter envelope de erro");
    }

    /// FAIL-CLOSED: senha curta nem chega a consultar a base nem audita.
    #[tokio::test]
    async fn create_superuser_rejects_short_password() {
        // Arrange
        let mut store = MockAuthStore::new();
        store.expect_buscar_por_username().never();
        store.expect_criar_superuser().never();
        let mut audit = MockAuditPort::new();
        audit.expect_publish_security().never();
        let env = envelope_com_payload(
            "CreateSuperuser",
            serde_json::json!({ "username": "root", "password": "123" }),
        );

        // Act
        let resp = handler_create_superuser(&store, &audit, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Error as i32);
        let err = resp.error.expect("deveria ter envelope de erro");
        assert_eq!(err.code, "VALIDATION_FAILED", "veio: {err:?}");
    }

    /// FAIL-CLOSED: delete de id inexistente devolve conflito e NÃO audita.
    #[tokio::test]
    async fn delete_superuser_not_found_returns_conflict() {
        // Arrange
        let mut store = MockAuthStore::new();
        store
            .expect_deletar_superuser()
            .times(1)
            .returning(|_| Ok(0));
        let mut audit = MockAuditPort::new();
        audit.expect_publish_security().never();
        let env = envelope_com_payload("DeleteSuperuser", serde_json::json!({ "id": 42 }));

        // Act
        let resp = handler_delete_superuser(&store, &audit, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Error as i32);
        assert!(resp.error.is_some(), "deveria ter envelope de erro");
    }

    /// FAIL-CLOSED: identidade de usuário inexistente vira erro.
    #[tokio::test]
    async fn get_user_identity_not_found_returns_error() {
        // Arrange
        let mut store = MockAuthStore::new();
        store
            .expect_buscar_por_id()
            .times(1)
            .returning(|_| Ok(None));
        let env = envelope_com_payload("GetUserIdentity", serde_json::json!({ "id": 999 }));

        // Act
        let resp = handler_get_user_identity(&store, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Error as i32);
        assert!(resp.error.is_some(), "deveria ter envelope de erro");
    }
}

/// Testes unitários dos domínios Atendimento e Cliente (handlers via ports, SEM
/// banco). A cobertura de SQL/RLS real vive em
/// `crates/infrastructure_postgres/tests/integracoes/`.
#[cfg(test)]
mod tests_atendimento_cliente_unit {
    use super::*;
    use crate::ports::{MockAtendimentoStore, MockClienteStore};
    use contracts::{Envelope, MessageKind};
    use infrastructure_postgres::atendimentos::mensagens::Mensagem;
    use infrastructure_postgres::clientes::contatos::Contato;

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

    /// Mensagem fake retornada pelos mocks no happy path.
    fn mensagem_fake(id: i32) -> Mensagem {
        Mensagem {
            id,
            tenant_id: uuid::Uuid::nil(),
            atendimento_id: 1,
            tipo: "texto".to_string(),
            conteudo: "oi".to_string(),
            remetente: "u".to_string(),
            timestamp: chrono::Utc::now(),
            message_id_whatsapp: None,
            metadados: serde_json::json!({}),
            respondida: false,
            lido: false,
            resposta_bot: None,
            intent_detectado: serde_json::json!({}),
            entidades_extraidas: serde_json::json!({}),
            confianca_resposta: None,
            arquivo_midia: None,
            analise_midia: None,
            resumo_midia: None,
            gerado_por_ia: false,
            mensagem_citada_id: None,
            quoted_preview: None,
            status_envio: "enviado".to_string(),
            data_entregue: None,
            data_lida: None,
        }
    }

    /// Contato fake retornado pelo mock no happy path.
    fn contato_fake(id: i32) -> Contato {
        Contato {
            id,
            tenant_id: uuid::Uuid::nil(),
            telefone: Some("5511".to_string()),
            nome_contato: Some("n".to_string()),
            slug: "s".to_string(),
            email: None,
            nome_perfil_whatsapp: None,
            data_cadastro: chrono::Utc::now(),
            ultima_interacao: chrono::Utc::now(),
            ativo: true,
            metadados: serde_json::json!({}),
            foto_perfil: None,
            foto_perfil_url_origem: None,
        }
    }

    /// HAPPY PATH: get_thread devolve as mensagens da thread.
    #[tokio::test]
    async fn get_thread_returns_messages() {
        // Arrange
        let mut store = MockAtendimentoStore::new();
        store
            .expect_listar_mensagens()
            .times(1)
            .returning(|_, _, _, _| Ok(vec![mensagem_fake(1)]));
        let env = envelope_com_payload("GetThread", serde_json::json!({ "atendimento_id": 1 }));

        // Act
        let resp = handler_get_thread(&store, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(body["mensagens"].as_array().unwrap().len(), 1);
    }

    /// HAPPY PATH: persist_message confirma persistência e devolve o id da mensagem.
    #[tokio::test]
    async fn persist_message_returns_message_id() {
        // Arrange
        let mut store = MockAtendimentoStore::new();
        store
            .expect_persistir_mensagem()
            .times(1)
            .returning(|_, _, _, _, _, _| Ok(mensagem_fake(7)));
        let env = envelope_com_payload(
            "PersistMessage",
            serde_json::json!({ "atendimento_id": 1, "content": "oi" }),
        );

        // Act
        let resp = handler_persist_message(&store, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(body["message_id"].as_i64().unwrap(), 7);
    }

    /// HAPPY PATH: anexar_analise_midia repassa os campos ao store e confirma ok.
    #[tokio::test]
    async fn anexar_analise_midia_repassa_ao_store() {
        // Arrange
        let mut store = MockAtendimentoStore::new();
        store
            .expect_anexar_analise_midia()
            .times(1)
            .withf(|_, mensagem_id, arquivo, analise, resumo| {
                *mensagem_id == 7
                    && arquivo == "media/t/1/audio/hash"
                    && analise.is_empty()
                    && resumo == "resumo do áudio"
            })
            .returning(|_, _, _, _, _| Ok(()));
        let env = envelope_com_payload(
            "AnexarAnaliseMidia",
            serde_json::json!({
                "mensagem_id": 7,
                "arquivo_midia": "media/t/1/audio/hash",
                "resumo": "resumo do áudio",
            }),
        );

        // Act
        let resp = handler_anexar_analise_midia(&store, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(body["status"].as_str(), Some("ok"));
    }

    /// FAIL-CLOSED: mensagem_id ausente vira erro de validação.
    #[tokio::test]
    async fn anexar_analise_midia_sem_mensagem_id_valida() {
        let store = MockAtendimentoStore::new();
        let env = envelope_com_payload(
            "AnexarAnaliseMidia",
            serde_json::json!({ "arquivo_midia": "x" }),
        );

        let resp = handler_anexar_analise_midia(&store, env).await;

        assert_eq!(resp.kind, MessageKind::Error as i32);
    }

    /// HAPPY PATH: listar_fluxos_do_tenant devolve os fluxos no envelope de reply.
    #[tokio::test]
    async fn listar_fluxos_do_tenant_retorna_fluxos() {
        use infrastructure_postgres::operacional::fluxos::FluxoDisponivel;
        let mut store = MockAtendimentoStore::new();
        store
            .expect_listar_fluxos_do_tenant()
            .times(1)
            .returning(|_| {
                Ok(vec![FluxoDisponivel {
                    id: 3,
                    setor: "Vendas".to_string(),
                    nome: "Funil".to_string(),
                    descricao: Some("negociação".to_string()),
                }])
            });
        let env = envelope_com_payload("ListarFluxosDoTenant", serde_json::json!({}));

        let resp = handler_listar_fluxos_do_tenant(&store, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(body["fluxos"].as_array().unwrap().len(), 1);
        assert_eq!(body["fluxos"][0]["setor"].as_str(), Some("Vendas"));
    }

    /// HAPPY PATH: transferir repassa os ids ao store e devolve o outcome.
    #[tokio::test]
    async fn transferir_atendimento_para_fluxo_repassa_ao_store() {
        use crate::ports::TransferenciaFluxoOutcome;
        let mut store = MockAtendimentoStore::new();
        store
            .expect_transferir_atendimento_para_fluxo()
            .times(1)
            .withf(|_, atendimento_id, fluxo_id| *atendimento_id == 42 && *fluxo_id == 7)
            .returning(|_, _, _| {
                Ok(TransferenciaFluxoOutcome {
                    transferido: true,
                    fluxo_id: Some(7),
                    fluxo_nome: Some("Suporte".to_string()),
                    etapa_id: Some(11),
                    etapa_nome: Some("Fila".to_string()),
                    reason: None,
                })
            });
        let env = envelope_com_payload(
            "TransferirAtendimentoParaFluxo",
            serde_json::json!({ "atendimento_id": 42, "fluxo_id": 7 }),
        );

        let resp = handler_transferir_atendimento_para_fluxo(&store, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(body["transferido"].as_bool(), Some(true));
        assert_eq!(body["etapa_id"].as_i64(), Some(11));
    }

    /// FAIL-CLOSED: transferir sem fluxo_id vira erro de validação.
    #[tokio::test]
    async fn transferir_atendimento_sem_fluxo_id_valida() {
        let store = MockAtendimentoStore::new();
        let env = envelope_com_payload(
            "TransferirAtendimentoParaFluxo",
            serde_json::json!({ "atendimento_id": 42 }),
        );
        let resp = handler_transferir_atendimento_para_fluxo(&store, env).await;
        assert_eq!(resp.kind, MessageKind::Error as i32);
    }

    /// HAPPY PATH: resolver_campos_atendimento devolve coletados/pendentes no reply.
    #[tokio::test]
    async fn resolver_campos_atendimento_retorna_coletados_e_pendentes() {
        use crate::ports::{CampoColetadoDto, CampoPendenteDto, CamposAtendimentoDto};
        let mut store = MockAtendimentoStore::new();
        store
            .expect_resolver_campos_atendimento()
            .times(1)
            .withf(|_, atendimento_id| *atendimento_id == 42)
            .returning(|_, _| {
                Ok(CamposAtendimentoDto {
                    coletados: vec![CampoColetadoDto {
                        slug: "nome".to_string(),
                        nome: "Nome".to_string(),
                        valor: "Maria".to_string(),
                    }],
                    pendentes: vec![CampoPendenteDto {
                        slug: "cpf".to_string(),
                        nome: "CPF".to_string(),
                        descricao: "Documento".to_string(),
                        hint: "número do CPF".to_string(),
                    }],
                })
            });
        let env = envelope_com_payload(
            "ResolverCamposAtendimento",
            serde_json::json!({ "atendimento_id": 42 }),
        );

        let resp = handler_resolver_campos_atendimento(&store, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(body["coletados"].as_array().unwrap().len(), 1);
        assert_eq!(body["coletados"][0]["slug"].as_str(), Some("nome"));
        assert_eq!(body["pendentes"][0]["slug"].as_str(), Some("cpf"));
    }

    /// FAIL-CLOSED: resolver_campos_atendimento sem atendimento_id vira erro de validação.
    #[tokio::test]
    async fn resolver_campos_atendimento_sem_atendimento_id_valida() {
        let store = MockAtendimentoStore::new();
        let env = envelope_com_payload("ResolverCamposAtendimento", serde_json::json!({}));
        let resp = handler_resolver_campos_atendimento(&store, env).await;
        assert_eq!(resp.kind, MessageKind::Error as i32);
    }

    /// FAIL-CLOSED: erro de persistência da mensagem vira erro interno no envelope.
    #[tokio::test]
    async fn persist_message_maps_store_error() {
        // Arrange
        let mut store = MockAtendimentoStore::new();
        store
            .expect_persistir_mensagem()
            .times(1)
            .returning(|_, _, _, _, _, _| {
                Err(infrastructure_postgres::DbError::ConfigError(
                    "falha simulada".to_string(),
                ))
            });
        let env = envelope_com_payload("PersistMessage", serde_json::json!({ "content": "x" }));

        // Act
        let resp = handler_persist_message(&store, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Error as i32);
        let err = resp.error.expect("deveria ter envelope de erro");
        assert_eq!(err.category, contracts::ErrorCategory::Internal as i32);
    }

    /// HAPPY PATH: list_atendimentos devolve Reply com o array de atendimentos.
    #[tokio::test]
    async fn list_atendimentos_returns_reply() {
        // Arrange
        let mut store = MockAtendimentoStore::new();
        store
            .expect_listar_atendimentos()
            .times(1)
            .returning(|_, _, _, _| Ok(vec![]));
        let env = envelope_com_payload("ListAtendimentos", serde_json::json!({}));

        // Act
        let resp = handler_list_atendimentos(&store, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert!(body["atendimentos"].is_array());
    }

    /// HAPPY PATH: upsert_contact devolve o contato salvo.
    #[tokio::test]
    async fn upsert_contact_returns_contato() {
        // Arrange
        let mut store = MockClienteStore::new();
        store
            .expect_salvar_contato()
            .times(1)
            .returning(|_, _, _| Ok(contato_fake(3)));
        let env = envelope_com_payload(
            "UpsertContact",
            serde_json::json!({ "phone": "5511", "name": "n" }),
        );

        // Act
        let resp = handler_upsert_contact(&store, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(body["id"].as_i64().unwrap(), 3);
    }
}

/// Testes unitários do domínio Operacional (handlers via ports, SEM banco). A
/// cobertura de SQL/cifragem real vive em
/// `crates/infrastructure_postgres/tests/integracoes/`.
#[cfg(test)]
mod tests_operacional_unit {
    use super::*;
    use crate::ports::operacional::CoreSetting;
    use crate::ports::{MockAuditPort, MockOperacionalStore};
    use contracts::{Envelope, MessageKind};

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

    /// HAPPY PATH: list_core_settings mascara o valor cifrado já no adapter.
    #[tokio::test]
    async fn list_core_settings_returns_reply() {
        // Arrange
        let mut store = MockOperacionalStore::new();
        store.expect_listar_core_settings().times(1).returning(|| {
            Ok(vec![CoreSetting {
                key: "k".to_string(),
                value: "••••••••".to_string(),
                encrypted: true,
                description: String::new(),
            }])
        });
        let env = envelope_com_payload("ListCoreSettings", serde_json::json!({}));

        // Act
        let resp = handler_list_core_settings(&store, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(body["settings"].as_array().unwrap().len(), 1);
    }

    /// FAIL-CLOSED: chave vazia nem chega à port nem audita.
    #[tokio::test]
    async fn upsert_core_setting_rejects_empty_key() {
        // Arrange
        let mut store = MockOperacionalStore::new();
        store.expect_upsert_core_setting().never();
        let mut audit = MockAuditPort::new();
        audit.expect_publish().never();
        let env = envelope_com_payload("UpsertCoreSetting", serde_json::json!({ "value": "v" }));

        // Act
        let resp = handler_upsert_core_setting(&store, &audit, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Error as i32);
        let err = resp.error.expect("deveria ter envelope de erro");
        assert_eq!(err.code, "VALIDATION_FAILED", "veio: {err:?}");
    }

    /// FAIL-CLOSED: set_feature_flag sem `key` é rejeitado antes da port/auditoria.
    #[tokio::test]
    async fn set_feature_flag_rejects_missing_key() {
        // Arrange
        let mut store = MockOperacionalStore::new();
        store.expect_set_feature_flag().never();
        let mut audit = MockAuditPort::new();
        audit.expect_publish().never();
        let env = envelope_com_payload(
            "SetFeatureFlag",
            serde_json::json!({ "enabled_globally": true }),
        );

        // Act
        let resp = handler_set_feature_flag(&store, &audit, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Error as i32);
        assert!(resp.error.is_some(), "deveria ter envelope de erro");
    }

    /// FAIL-CLOSED: get_tenant_config sem tenant alvo é rejeitado sem tocar a port.
    #[tokio::test]
    async fn get_tenant_config_rejects_missing_tenant() {
        // Arrange
        let mut store = MockOperacionalStore::new();
        store.expect_obter_tenant_config().never();
        let env = envelope_com_payload("GetTenantConfig", serde_json::json!({}));

        // Act
        let resp = handler_get_tenant_config(&store, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Error as i32);
        let err = resp.error.expect("deveria ter envelope de erro");
        assert_eq!(err.code, "VALIDATION_FAILED", "veio: {err:?}");
    }
}

/// Testes unitários do domínio Plans/Billing (handlers via ports, SEM banco). A
/// cobertura de SQL real vive em `crates/infrastructure_postgres/tests/integracoes/`.
#[cfg(test)]
mod tests_plans_unit {
    use super::*;
    use crate::ports::{MockAuditPort, MockPlansStore};
    use contracts::{Envelope, MessageKind};

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

    /// HAPPY PATH: list_plans devolve a lista de planos.
    #[tokio::test]
    async fn list_plans_returns_reply() {
        // Arrange
        let mut store = MockPlansStore::new();
        store
            .expect_listar_planos()
            .times(1)
            .returning(|| Ok(vec![serde_json::json!({ "id": 1, "name": "Pro" })]));
        let env = envelope_com_payload("ListPlans", serde_json::json!({}));

        // Act
        let resp = handler_list_plans(&store, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(body["plans"].as_array().unwrap().len(), 1);
    }

    /// FAIL-CLOSED: criar plano sem nome nem chega à port nem audita.
    #[tokio::test]
    async fn create_plan_rejects_empty_name() {
        // Arrange
        let mut store = MockPlansStore::new();
        store.expect_criar_plano().never();
        let mut audit = MockAuditPort::new();
        audit.expect_publish().never();
        let env = envelope_com_payload("CreatePlan", serde_json::json!({ "price": "10" }));

        // Act
        let resp = handler_create_plan(&store, &audit, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Error as i32);
        let err = resp.error.expect("deveria ter envelope de erro");
        assert_eq!(err.code, "VALIDATION_FAILED", "veio: {err:?}");
    }

    /// FAIL-CLOSED: plano inexistente no update retorna validação e NÃO audita.
    #[tokio::test]
    async fn update_plan_missing_returns_validation_without_audit() {
        // Arrange
        let mut store = MockPlansStore::new();
        store
            .expect_atualizar_plano()
            .times(1)
            .returning(|_, _, _, _, _, _, _| Ok(false));
        let mut audit = MockAuditPort::new();
        audit.expect_publish().never();
        let env = envelope_com_payload("UpdatePlan", serde_json::json!({ "id": 99, "name": "X" }));

        // Act
        let resp = handler_update_plan(&store, &audit, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Error as i32);
        assert!(resp.error.is_some(), "deveria ter envelope de erro");
    }

    /// FAIL-CLOSED: valor de pagamento inválido é rejeitado antes da port/auditoria.
    #[tokio::test]
    async fn register_payment_rejects_invalid_amount() {
        // Arrange
        let mut store = MockPlansStore::new();
        store.expect_registrar_pagamento().never();
        let mut audit = MockAuditPort::new();
        audit.expect_publish().never();
        let env = envelope_com_payload(
            "RegisterPayment",
            serde_json::json!({ "tenant_id": uuid::Uuid::nil().to_string(), "amount": "nao-numero" }),
        );

        // Act
        let resp = handler_register_payment(&store, &audit, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Error as i32);
        let err = resp.error.expect("deveria ter envelope de erro");
        assert_eq!(err.code, "VALIDATION_FAILED", "veio: {err:?}");
    }
}

#[cfg(test)]
mod tests_quota_unit {
    use super::*;
    use crate::ports::{MockAuditPort, MockQuotaStore};
    use contracts::{Envelope, MessageKind};

    /// Helper: monta um Envelope mínimo com método e payload arbitrários, com um
    /// `tenant_id` válido (a rota exige contexto de tenant).
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

    /// FAIL-CLOSED: `tenant_id` inválido no envelope nem chega a consultar a store.
    #[tokio::test]
    async fn check_quota_rejects_tenant_id_invalido_sem_tocar_a_store() {
        let mut store = MockQuotaStore::new();
        store.expect_verificar_quota().never();
        let audit = MockAuditPort::new();
        let env = Envelope {
            tenant_id: "nao-e-um-uuid".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({ "recurso": "instancias" })).unwrap(),
            ..Default::default()
        };

        let resp = handler_check_quota(&store, &audit, env).await;

        assert_eq!(resp.kind, MessageKind::Error as i32);
        let err = resp.error.expect("deveria ter envelope de erro");
        assert_eq!(err.code, "VALIDATION_FAILED", "veio: {err:?}");
    }

    /// Quota excedida COM `auditar=true` publica o evento `quota.excedida`.
    #[tokio::test]
    async fn check_quota_excedida_com_auditar_publica_evento() {
        let mut store = MockQuotaStore::new();
        store
            .expect_verificar_quota()
            .times(1)
            .returning(|_, _| Ok(serde_json::json!({ "excedido": true, "inadimplente": false })));
        let mut audit = MockAuditPort::new();
        audit
            .expect_publish()
            .withf(|_, event, _, _| event == "quota.excedida")
            .times(1)
            .returning(|_, _, _, _| ());
        let env = envelope_com_payload(
            "CheckQuota",
            serde_json::json!({ "recurso": "instancias", "auditar": true }),
        );

        let resp = handler_check_quota(&store, &audit, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
    }

    /// Quota excedida SEM `auditar` (default false) NÃO publica — regra que evita
    /// inundar a trilha de auditoria no caminho quente de ingestão (doc 08 §4.2).
    #[tokio::test]
    async fn check_quota_excedida_sem_auditar_nao_publica_evento() {
        let mut store = MockQuotaStore::new();
        store
            .expect_verificar_quota()
            .times(1)
            .returning(|_, _| Ok(serde_json::json!({ "excedido": true, "inadimplente": false })));
        let mut audit = MockAuditPort::new();
        audit.expect_publish().never();
        let env =
            envelope_com_payload("CheckQuota", serde_json::json!({ "recurso": "instancias" }));

        let resp = handler_check_quota(&store, &audit, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
    }

    /// Tenant inadimplente COM `auditar=true` publica o evento
    /// `tenant.bloqueado_inadimplencia`, distinto do evento de quota.
    #[tokio::test]
    async fn check_quota_inadimplente_com_auditar_publica_evento_distinto() {
        let mut store = MockQuotaStore::new();
        store
            .expect_verificar_quota()
            .times(1)
            .returning(|_, _| Ok(serde_json::json!({ "excedido": false, "inadimplente": true })));
        let mut audit = MockAuditPort::new();
        audit
            .expect_publish()
            .withf(|_, event, _, _| event == "tenant.bloqueado_inadimplencia")
            .times(1)
            .returning(|_, _, _, _| ());
        let env = envelope_com_payload(
            "CheckQuota",
            serde_json::json!({ "recurso": "departamentos", "auditar": true }),
        );

        let resp = handler_check_quota(&store, &audit, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
    }

    /// Nem excedido nem inadimplente: nunca audita, mesmo com `auditar=true`.
    #[tokio::test]
    async fn check_quota_dentro_do_limite_nunca_publica_mesmo_com_auditar() {
        let mut store = MockQuotaStore::new();
        store
            .expect_verificar_quota()
            .times(1)
            .returning(|_, _| Ok(serde_json::json!({ "excedido": false, "inadimplente": false })));
        let mut audit = MockAuditPort::new();
        audit.expect_publish().never();
        let env = envelope_com_payload(
            "CheckQuota",
            serde_json::json!({ "recurso": "instancias", "auditar": true }),
        );

        let resp = handler_check_quota(&store, &audit, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
    }

    /// Falha da store vira `AppError::Database` — a rota não audita nesse caminho.
    #[tokio::test]
    async fn check_quota_erro_da_store_retorna_database_error() {
        let mut store = MockQuotaStore::new();
        store
            .expect_verificar_quota()
            .times(1)
            .returning(|_, _| Err(infrastructure_postgres::DbError::NotFound));
        let mut audit = MockAuditPort::new();
        audit.expect_publish().never();
        let env =
            envelope_com_payload("CheckQuota", serde_json::json!({ "recurso": "instancias" }));

        let resp = handler_check_quota(&store, &audit, env).await;

        assert_eq!(resp.kind, MessageKind::Error as i32);
        assert!(resp.error.is_some());
    }
}
