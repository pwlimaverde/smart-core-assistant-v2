//! Serviço data_postgres: provê RPC síncrono e pub/sub assíncrono sujeito a políticas RLS.
//! Contém o Relay de Outbox e o Consumidor de Auditoria integrados.

// Os handlers deste binário encadeiam muitos `async` (RPC -> adapter -> cache de
// config -> sqlx), e o tipo de cada future embute o do future aninhado. Ao ligar
// a republicação de config no Redis, o cálculo de layout passou de 128 no perfil
// `release` — em `debug` ainda cabia, então o CI ficava verde e só o build da
// imagem quebrava. Limite sugerido pelo próprio rustc na mensagem de erro.
#![recursion_limit = "256"]

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

/// N7.2 — extrai o `action_id` opcional (uuid v7, sync offline) do payload JSON.
/// Ausente ou vazio: `None` (dedupe desligado, comportamento pré-N7.2 preservado
/// para clientes antigos). Malformado: `None` com WARN — nunca falha a
/// requisição por causa de um campo aditivo de otimização.
fn extrair_action_id_opcional(payload_json: &serde_json::Value) -> Option<Uuid> {
    let raw = payload_json.get("action_id").and_then(|v| v.as_str())?;
    if raw.is_empty() {
        return None;
    }
    match Uuid::parse_str(raw) {
        Ok(id) => Some(id),
        Err(e) => {
            tracing::warn!(erro = %e, "action_id malformado; seguindo sem dedupe");
            None
        }
    }
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
mod mcp_grants;
mod onboarding;
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
    signup: std::sync::Arc<dyn ports::SignupStore>,
    vouchers: std::sync::Arc<dyn ports::VoucherStore>,
    /// Consentimentos OAuth 2.1 dos clientes MCP (N13.2).
    mcp_grants: std::sync::Arc<dyn ports::McpGrantStore>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // 1. Inicializa observabilidade
    observability::init_telemetry("data_postgres", "production")
        .map_err(|e| anyhow::anyhow!(e.to_string()))?;
    // Panic em task de background mata so a task: o processo segue vivo e a
    // funcionalidade some sem deixar rastro. O hook garante o registro estruturado.
    observability::instalar_hook_de_panic("data_postgres");
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
    // Conexão de CACHE (REDIS_URL) — instância distinta do bus. É onde vive o
    // `tenant:config:<uuid>` que o `ia_engine` lê: ele se conecta por `REDIS_URL`
    // (ver ia_engine/settings.py). Publicar isso no bus faria a config existir
    // no Redis errado — presente, íntegra e invisível para quem a consome.
    let cache_conn = infrastructure_redis::criar_conexao_com_timeouts(&redis_url).await?;
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

    // Pre-warm das configs no Redis para o `ia_engine` (seção 3.4 do
    // `gerenciamento_configuracoes_ia.md`). Sem isto, depois de um deploy o
    // Redis está vazio e a PRIMEIRA mensagem de cada tenant falha — a config só
    // apareceria quando alguém salvasse algo no painel.
    //
    // Em background: o serviço não deve atrasar o `listen` por causa de um
    // Redis lento, e o `ia_engine` degrada com erro explícito enquanto isso.
    {
        // admin_pool (BYPASSRLS): listar todos os tenants é consulta cross-tenant
        // e `tenants_tenant` tem RLS com FORCE — no pool de runtime a política
        // fail-closed devolveria zero linhas, sem erro nenhum.
        let admin_pool = admin_pool.clone();
        let config_cache = config_cache.clone();
        let cache_conn = cache_conn.clone();
        tokio::spawn(async move {
            match data_postgres::config_publisher::prewarm_configs(
                admin_pool.as_ref(),
                &config_cache,
                &cache_conn,
            )
            .await
            {
                Ok(n) => tracing::info!("Pre-warm de config publicou {n} tenant(s) no Redis"),
                Err(e) => tracing::error!("Falha no pre-warm de config para o ia_engine: {e:?}"),
            }
        });
    }

    let whatsapp_store: std::sync::Arc<dyn ports::WhatsappStore> = std::sync::Arc::new(
        adapters::PgWhatsappStore::new(pool.clone(), admin_pool.clone(), cipher.clone()),
    );
    let audit_port: std::sync::Arc<dyn ports::AuditPort> =
        std::sync::Arc::new(adapters::RedisAuditPort::new(bus_conn.clone()));
    let tenant_store: std::sync::Arc<dyn ports::TenantStore> =
        std::sync::Arc::new(adapters::PgTenantStore::new(pool.clone()));
    let auth_store: std::sync::Arc<dyn ports::AuthStore> =
        std::sync::Arc::new(adapters::PgAuthStore::new(pool.clone(), admin_pool.clone()));
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
            cache_conn.clone(),
            admin_pool.clone(),
        ));
    let plans_store: std::sync::Arc<dyn ports::PlansStore> = std::sync::Arc::new(
        adapters::PgPlansStore::new(pool.clone(), admin_pool.clone()),
    );
    let quota_store: std::sync::Arc<dyn ports::QuotaStore> =
        std::sync::Arc::new(adapters::PgQuotaStore::new(pool.clone()));
    let treinamento_store: std::sync::Arc<dyn ports::TreinamentoStore> = std::sync::Arc::new(
        adapters::PgTreinamentoStore::new(pool.clone(), admin_pool.clone()),
    );
    // O cadastro público opera sem contexto de tenant: precisa do pool sem RLS.
    let signup_store: std::sync::Arc<dyn ports::SignupStore> = std::sync::Arc::new(
        adapters::PgSignupStore::new(pool.clone(), admin_pool.clone()),
    );
    let voucher_store: std::sync::Arc<dyn ports::VoucherStore> =
        std::sync::Arc::new(adapters::PgVoucherStore::new(pool.clone()));
    let mcp_grant_store: std::sync::Arc<dyn ports::McpGrantStore> =
        std::sync::Arc::new(adapters::PgMcpGrantStore::new(pool.clone()));

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
        signup: signup_store,
        vouchers: voucher_store,
        mcp_grants: mcp_grant_store,
    };

    // Logger dedicado à supervisão das tasks de background. O `AuditPort` acima
    // serve aos handlers (que sempre têm um Envelope em mãos); aqui não há
    // requisição nenhuma por trás do evento — é o próprio serviço relatando que
    // perdeu uma engrenagem.
    let audit_supervisao =
        observability::AuditLogger::new_with_redis(bus_conn.clone(), "data_postgres");

    // 4. Inicia o Relay de Outbox em background
    //
    // Supervisionado: sem isso, um panic aqui matava só a task. O processo
    // continuava `running`, o Docker via tudo bem, e os eventos paravam de sair
    // do outbox — a stack de pé sem publicar nada.
    let relay = OutboxRelay::new(pool.clone(), bus_conn.clone());
    observability::supervisionar("outbox_relay", "data_postgres", audit_supervisao.clone(), {
        async move {
            if let Err(e) = relay.run().await {
                tracing::error!("Outbox Relay parou com erro crítico: {:?}", e);
            }
        }
    });

    // 5. Inicia o Consumidor de Auditoria (Consolidação) em background
    let pool_clone = pool.clone();
    let consumidor_audit = transport::bus::nome_consumidor("data_postgres_audit_consumer");
    let audit_consumer = transport::bus::Consumer::new(
        transport::bus::STREAM_SEGURANCA,
        "data_postgres_audit_group",
        consumidor_audit.clone(),
        bus_client.clone(), // passa o Client para abrir conexão dedicada (C2)
    );
    observability::supervisionar(
        "consumidor_auditoria",
        "data_postgres",
        audit_supervisao.clone(),
        async move {
            if let Err(e) = audit_consumer
                .run_batch(move |evts| {
                    let pool = pool_clone.clone();
                    async move { processar_eventos_auditoria_lote(pool, evts).await }
                })
                .await
            {
                tracing::error!("Consumidor de auditoria parou com erro crítico: {:?}", e);
            }
        },
    );

    // 5b. Reprocessamento periódico da PEL (a cada 60s) (C4).
    //
    // Piso de inatividade (`MIN_IDLE_REPROCESSAMENTO_MS`): este tick roda em
    // paralelo ao `run_batch` acima e a PEL não distingue lote em voo de lote
    // abandonado — sem o piso, o mesmo lote de auditoria seria consolidado duas
    // vezes, duplicando linhas em `audit_log`.
    let pool_retry = pool.clone();
    let bus_client_retry = bus_client;
    let consumidor_audit_retry = consumidor_audit.clone();
    // Supervisionado pelo mesmo motivo do relay: este loop é quem resgata o lote
    // de auditoria abandonado. Se ele morresse em silêncio — e morria, num
    // `tokio::spawn` que ninguém observava — os eventos ficariam presos na PEL
    // sem nunca chegar ao `audit_log`, e nada acusaria.
    observability::supervisionar(
        "reprocessamento_pel",
        "data_postgres",
        audit_supervisao.clone(),
        async move {
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
                    &consumidor_audit_retry,
                    transport::bus::MIN_IDLE_REPROCESSAMENTO_MS,
                    handler,
                )
                .await
                {
                    tracing::warn!("Falha no reprocessamento periódico da PEL: {:?}", e);
                }
            }
        },
    );

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
    let state_for_reenviar_convite = state_clone.clone();
    let state_for_solicitar_redefinicao = state_clone.clone();
    let state_for_redefinir_senha = state_clone.clone();
    let state_for_update_tenant_user = state_clone.clone();
    let state_for_create_superuser = state_clone.clone();
    let state_for_list_superusers = state_clone.clone();
    let state_for_admin_list_users = state_clone.clone();
    let state_for_admin_set_user_active = state_clone.clone();
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
    let state_for_register_storage_usage = state_clone.clone();
    let s_dep_listar = state_clone.clone();
    let s_dep_update = state_clone.clone();
    let s_dep_desativar = state_clone.clone();
    let s_atendentes = state_clone.clone();
    let s_painel = state_clone.clone();
    let s_contatos = state_clone.clone();
    let s_contato_criar = state_clone.clone();
    let s_contato_update = state_clone.clone();
    let s_contato_ativo = state_clone.clone();
    let s_clientes_listar = state_clone.clone();
    let s_cliente_criar = state_clone.clone();
    let s_cliente_atualizar = state_clone.clone();
    let s_cliente_ativo = state_clone.clone();
    let s_cliente_contatos = state_clone.clone();
    let s_cliente_vincular = state_clone.clone();
    let s_fluxo_listar = state_clone.clone();
    let s_campo_listar = state_clone.clone();
    let s_campo_criar = state_clone.clone();
    let s_campo_update = state_clone.clone();
    let s_campo_desativar = state_clone.clone();
    let s_valor_campo = state_clone.clone();
    let s_fluxo_criar = state_clone.clone();
    let s_fluxo_update = state_clone.clone();
    let s_fluxo_desativar = state_clone.clone();
    let s_etapa_listar = state_clone.clone();
    let s_etapa_criar = state_clone.clone();
    let s_etapa_update = state_clone.clone();
    let s_etapa_desativar = state_clone.clone();
    let s_etapa_mover = state_clone.clone();
    let s_atendente_criar = state_clone.clone();
    let s_atendente_update = state_clone.clone();
    let s_atendente_desativar = state_clone.clone();
    let s_status_atendimento = state_clone.clone();
    let s_detalhe = state_clone.clone();
    let s_etiqueta_criar = state_clone.clone();
    let s_etiqueta_alternar = state_clone.clone();
    let s_nota_criar = state_clone.clone();
    let s_vetor_pendentes = state_clone.clone();
    let s_vetor_salvar = state_clone.clone();
    let s_intent_pendentes = state_clone.clone();
    let s_intent_embedding = state_clone.clone();
    let s_intent_listar = state_clone.clone();
    let s_intent_criar = state_clone.clone();
    let s_intent_atualizar = state_clone.clone();
    let s_intent_remover = state_clone.clone();
    let state_for_create_departamento = state_clone.clone();
    let state_for_create_plan = state_clone.clone();
    let state_for_update_plan = state_clone.clone();
    let state_for_list_subscriptions = state_clone.clone();
    let state_for_suspender_vencidas = state_clone.clone();
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
    let state_for_listar_numeros_ignorados = state_clone.clone();
    let state_for_criar_numero_ignorado = state_clone.clone();
    let state_for_atualizar_numero_ignorado = state_clone.clone();
    let state_for_remover_numero_ignorado = state_clone.clone();
    let state_for_definir_departamento_conexao = state_clone.clone();
    let state_for_detalhe_conexao = state_clone.clone();
    let state_for_departamentos_das_conexoes = state_clone.clone();
    let state_for_resolve_atendimento = state_clone.clone();
    let state_for_iniciar_manual = state_clone.clone();
    let state_for_toggle_bot = state_clone.clone();
    let state_for_toggle_bot_conversa = state_clone.clone();
    let state_for_marcar_lido = state_clone.clone();
    let state_for_aplicar_reacao = state_clone.clone();
    let state_for_contato_do_atendimento = state_clone.clone();
    let state_for_revisao_pendente = state_clone.clone();
    let state_for_registrar_foto = state_clone.clone();
    let state_for_listar_nao_entregues = state_clone.clone();
    let state_for_atualizar_perfil_contato = state_clone.clone();
    let state_for_aplicar_politica = state_clone.clone();
    let state_for_move_atendimento_etapa = state_clone.clone();
    let state_for_send_outbound_message = state_clone.clone();
    let state_for_listar_feedback_vencido = state_clone.clone();
    let state_for_listar_inativos = state_clone.clone();
    let state_for_encerrar_inatividade = state_clone.clone();
    let state_for_marcar_feedback_expirado = state_clone.clone();
    let state_for_aguardando_avaliacao = state_clone.clone();
    let state_for_registrar_avaliacao = state_clone.clone();
    let state_for_autorizar_upload_midia = state_clone.clone();
    let state_for_enviar_midia = state_clone.clone();
    let state_for_listar_midias = state_clone.clone();
    let state_for_listar_midias_expiradas = state_clone.clone();
    let state_for_marcar_midia_purgada = state_clone.clone();
    let state_for_resolver_destino_envio = state_clone.clone();
    let state_for_resolver_destino_atendimento = state_clone.clone();
    let state_for_ativo_por_telefone = state_clone.clone();
    let state_for_atribuir = state_clone.clone();
    let state_for_exportar_quadro = state_clone.clone();
    let state_for_timeline = state_clone.clone();
    let state_for_do_contato = state_clone.clone();
    let state_for_remover_nota = state_clone.clone();
    let state_for_update_etiqueta = state_clone.clone();
    let state_for_desativar_etiqueta = state_clone.clone();
    let state_for_prioridade = state_clone.clone();
    let state_for_reprocessar_dead_letter = state_clone.clone();
    let state_for_marcar_mensagem_enviada = state_clone.clone();
    let state_for_marcar_mensagem_falha_envio = state_clone.clone();
    let state_for_anexar_analise_midia = state_clone.clone();
    let state_for_anexar_analise_mensagem = state_clone.clone();
    let state_for_listar_fluxos_tenant = state_clone.clone();
    let state_for_transferir_fluxo = state_clone.clone();
    let state_for_resolver_campos_atendimento = state_clone.clone();
    let state_for_gravar_campos_extraidos = state_clone.clone();
    let state_for_atualizar_sentimento = state_clone.clone();
    let state_for_query_compose = state_clone.clone();
    let s_trn_criar = state_clone.clone();
    let s_trn_feedback = state_clone.clone();
    let s_trn_avaliacoes = state_clone.clone();
    let s_trn_tratada = state_clone.clone();
    let s_trn_autorizar_arquivo = state_clone.clone();
    let s_trn_criar_arquivo = state_clone.clone();
    let s_trn_extracoes = state_clone.clone();
    let s_trn_registrar_extracao = state_clone.clone();
    let s_trn_listar = state_clone.clone();
    let s_trn_obter = state_clone.clone();
    let s_trn_finalizar = state_clone.clone();
    let s_trn_remover = state_clone.clone();
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
        .route("IniciarAtendimentoManual", move |env| {
            let state = state_for_iniciar_manual.clone();
            Box::pin(async move {
                handler_iniciar_atendimento_manual(
                    state.atendimento.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("ResolveAtendimentoParaContato", move |env| {
            let state = state_for_resolve_atendimento.clone();
            Box::pin(async move {
                handler_resolve_atendimento_para_contato(
                    state.atendimento.as_ref(),
                    state.whatsapp.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("DefinirBotDaConversa", move |env| {
            let state = state_for_toggle_bot_conversa.clone();
            Box::pin(async move {
                handler_definir_bot_da_conversa(
                    state.atendimento.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("MarcarAtendimentoLido", move |env| {
            let state = state_for_marcar_lido.clone();
            Box::pin(async move {
                handler_marcar_atendimento_lido(state.atendimento.as_ref(), env).await
            })
        })
        .route("DefinirRespostaBotInstancia", move |env| {
            let state = state_for_toggle_bot.clone();
            Box::pin(async move {
                handler_definir_resposta_bot_instancia(
                    state.whatsapp.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("UpdateMessageStatus", move |env| {
            let state = state_for_update_status.clone();
            Box::pin(
                async move { handler_update_message_status(state.atendimento.as_ref(), env).await },
            )
        })
        .route("ListMensagensNaoEntregues", move |env| {
            let state = state_for_listar_nao_entregues.clone();
            Box::pin(
                async move { handler_listar_nao_entregues(state.atendimento.as_ref(), env).await },
            )
        })
        .route("DefinirRevisaoPendente", move |env| {
            let state = state_for_revisao_pendente.clone();
            Box::pin(async move {
                handler_definir_revisao_pendente(
                    state.atendimento.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("ContatoDoAtendimento", move |env| {
            let state = state_for_contato_do_atendimento.clone();
            Box::pin(async move {
                handler_contato_do_atendimento(state.atendimento.as_ref(), env).await
            })
        })
        .route("RegistrarFotoDoContato", move |env| {
            let state = state_for_registrar_foto.clone();
            Box::pin(async move {
                handler_registrar_foto_do_contato(state.atendimento.as_ref(), env).await
            })
        })
        .route("AplicarReacaoMensagem", move |env| {
            let state = state_for_aplicar_reacao.clone();
            Box::pin(async move { handler_aplicar_reacao(state.atendimento.as_ref(), env).await })
        })
        .route("AtualizarPerfilDoContato", move |env| {
            let state = state_for_atualizar_perfil_contato.clone();
            Box::pin(async move {
                handler_atualizar_perfil_do_contato(state.atendimento.as_ref(), env).await
            })
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
        .route("GetDetalheAtendimento", move |env| {
            let state = s_detalhe.clone();
            Box::pin(
                async move { handler_detalhe_atendimento(state.atendimento.as_ref(), env).await },
            )
        })
        .route("CreateEtiqueta", move |env| {
            let state = s_etiqueta_criar.clone();
            Box::pin(async move {
                handler_create_etiqueta(state.atendimento.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("AlternarEtiqueta", move |env| {
            let state = s_etiqueta_alternar.clone();
            Box::pin(
                async move { handler_alternar_etiqueta(state.atendimento.as_ref(), env).await },
            )
        })
        .route("CreateNota", move |env| {
            let state = s_nota_criar.clone();
            Box::pin(async move { handler_create_nota(state.atendimento.as_ref(), env).await })
        })
        .route("SetAtendimentoStatus", move |env| {
            let state = s_status_atendimento.clone();
            Box::pin(async move {
                handler_set_atendimento_status(
                    state.atendimento.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("SendOutboundMessage", move |env| {
            let state = state_for_send_outbound_message.clone();
            Box::pin(
                async move { handler_send_outbound_message(state.atendimento.as_ref(), env).await },
            )
        })
        .route("ListarAtendimentosInativos", move |env| {
            let state = state_for_listar_inativos.clone();
            Box::pin(async move { handler_listar_inativos(state.atendimento.as_ref(), env).await })
        })
        .route("EncerrarAtendimentoPorInatividade", move |env| {
            let state = state_for_encerrar_inatividade.clone();
            Box::pin(async move {
                handler_encerrar_por_inatividade(state.atendimento.as_ref(), env).await
            })
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
        // N9/E1 — mídia na conversa: autorizar (banco), enviar (banco) e listar.
        // A assinatura da URL fica no data_storage; a borda compõe os dois.
        .route("AutorizarUploadMidia", move |env| {
            let state = state_for_autorizar_upload_midia.clone();
            Box::pin(async move {
                handler_autorizar_upload_midia(state.atendimento.as_ref(), env).await
            })
        })
        .route("EnviarMidiaAtendimento", move |env| {
            let state = state_for_enviar_midia.clone();
            Box::pin(async move {
                handler_enviar_midia_atendimento(
                    state.atendimento.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("ListarMidiasAtendimento", move |env| {
            let state = state_for_listar_midias.clone();
            Box::pin(async move {
                handler_listar_midias_atendimento(state.atendimento.as_ref(), env).await
            })
        })
        // N8.5/E3 — ciclo da pesquisa de satisfação: o worker pergunta se o
        // atendimento aguarda nota antes de tratar a mensagem como conversa nova.
        .route("AtendimentoAguardandoAvaliacao", move |env| {
            let state = state_for_aguardando_avaliacao.clone();
            Box::pin(
                async move { handler_aguardando_avaliacao(state.atendimento.as_ref(), env).await },
            )
        })
        .route("RegistrarAvaliacaoAtendimento", move |env| {
            let state = state_for_registrar_avaliacao.clone();
            Box::pin(async move {
                handler_registrar_avaliacao(state.atendimento.as_ref(), state.audit.as_ref(), env)
                    .await
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
        .route("ListarTimelineAtendimento", move |env| {
            let state = state_for_timeline.clone();
            Box::pin(async move { handler_listar_timeline(state.atendimento.as_ref(), env).await })
        })
        .route("ListarAtendimentosDoContato", move |env| {
            let state = state_for_do_contato.clone();
            Box::pin(async move {
                handler_listar_atendimentos_do_contato(state.atendimento.as_ref(), env).await
            })
        })
        .route("RemoverNota", move |env| {
            let state = state_for_remover_nota.clone();
            Box::pin(async move { handler_remover_nota(state.atendimento.as_ref(), env).await })
        })
        .route("UpdateEtiqueta", move |env| {
            let state = state_for_update_etiqueta.clone();
            Box::pin(async move { handler_update_etiqueta(state.atendimento.as_ref(), env).await })
        })
        .route("DesativarEtiqueta", move |env| {
            let state = state_for_desativar_etiqueta.clone();
            Box::pin(
                async move { handler_desativar_etiqueta(state.atendimento.as_ref(), env).await },
            )
        })
        .route("ExportarQuadro", move |env| {
            let state = state_for_exportar_quadro.clone();
            Box::pin(async move {
                handler_exportar_quadro(state.atendimento.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("AtribuirAtendimento", move |env| {
            let state = state_for_atribuir.clone();
            Box::pin(async move {
                handler_atribuir_atendimento(state.atendimento.as_ref(), state.audit.as_ref(), env)
                    .await
            })
        })
        .route("DefinirPrioridade", move |env| {
            let state = state_for_prioridade.clone();
            Box::pin(
                async move { handler_definir_prioridade(state.atendimento.as_ref(), env).await },
            )
        })
        .route("BuscarAtendimentoAtivoPorTelefone", move |env| {
            let state = state_for_ativo_por_telefone.clone();
            Box::pin(async move {
                handler_buscar_atendimento_ativo_por_telefone(state.atendimento.as_ref(), env).await
            })
        })
        .route("ResolverDestinoDoAtendimento", move |env| {
            let state = state_for_resolver_destino_atendimento.clone();
            Box::pin(async move {
                handler_resolver_destino_do_atendimento(state.atendimento.as_ref(), env).await
            })
        })
        .route("ResolverDestinoEnvioOutbound", move |env| {
            let state = state_for_resolver_destino_envio.clone();
            Box::pin(async move {
                handler_resolver_destino_envio_outbound(
                    state.atendimento.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("ReprocessarDeadLetter", move |env| {
            let state = state_for_reprocessar_dead_letter.clone();
            Box::pin(async move {
                handler_reprocessar_dead_letter(
                    state.atendimento.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("AnexarAnaliseMensagem", move |env| {
            let state = state_for_anexar_analise_mensagem.clone();
            Box::pin(async move {
                handler_anexar_analise_mensagem(
                    state.atendimento.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
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
        .route("GravarCamposExtraidos", move |env| {
            let state = state_for_gravar_campos_extraidos.clone();
            Box::pin(async move {
                handler_gravar_campos_extraidos(
                    state.atendimento.as_ref(),
                    state.audit.as_ref(),
                    state.config_cache.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("ResolverCamposAtendimento", move |env| {
            let state = state_for_resolver_campos_atendimento.clone();
            Box::pin(async move {
                handler_resolver_campos_atendimento(state.atendimento.as_ref(), env).await
            })
        })
        .route("AtualizarSentimentoAtendimento", move |env| {
            let state = state_for_atualizar_sentimento.clone();
            Box::pin(
                async move { handler_atualizar_sentimento(state.atendimento.as_ref(), env).await },
            )
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
        .route("CreateTreinamento", move |env| {
            let state = s_trn_criar.clone();
            Box::pin(async move {
                handler_create_treinamento(state.treinamento.as_ref(), state.audit.as_ref(), env)
                    .await
            })
        })
        .route("AutorizarUploadTreinamento", move |env| {
            let state = s_trn_autorizar_arquivo.clone();
            Box::pin(async move {
                handler_autorizar_upload_treinamento(state.treinamento.as_ref(), env).await
            })
        })
        .route("CriarTreinamentoComArquivo", move |env| {
            let state = s_trn_criar_arquivo.clone();
            Box::pin(async move {
                handler_criar_treinamento_com_arquivo(
                    state.treinamento.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("ListarExtracoesPendentes", move |env| {
            let state = s_trn_extracoes.clone();
            Box::pin(async move {
                handler_listar_extracoes_pendentes(state.treinamento.as_ref(), env).await
            })
        })
        .route("RegistrarExtracaoTreinamento", move |env| {
            let state = s_trn_registrar_extracao.clone();
            Box::pin(async move {
                handler_registrar_extracao_treinamento(
                    state.treinamento.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("RegistrarFeedbackTeste", move |env| {
            let state = s_trn_feedback.clone();
            Box::pin(async move {
                handler_registrar_feedback_teste(
                    state.treinamento.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("ListAvaliacoesDeTeste", move |env| {
            let state = s_trn_avaliacoes.clone();
            Box::pin(async move {
                handler_listar_avaliacoes_de_teste(state.treinamento.as_ref(), env).await
            })
        })
        .route("MarcarAvaliacaoTratada", move |env| {
            let state = s_trn_tratada.clone();
            Box::pin(async move {
                handler_marcar_avaliacao_tratada(
                    state.treinamento.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("ListarTreinamentosPendentes", move |env| {
            let state = s_vetor_pendentes.clone();
            Box::pin(async move {
                handler_listar_pendentes_vetorizacao(state.treinamento.as_ref(), env).await
            })
        })
        .route("SalvarChunksVetorizados", move |env| {
            let state = s_vetor_salvar.clone();
            Box::pin(async move {
                handler_salvar_chunks_vetorizados(state.treinamento.as_ref(), env).await
            })
        })
        .route("ListarIntentsSemEmbedding", move |env| {
            let state = s_intent_pendentes.clone();
            Box::pin(async move {
                handler_listar_intents_sem_embedding(state.treinamento.as_ref(), env).await
            })
        })
        .route("DefinirEmbeddingIntent", move |env| {
            let state = s_intent_embedding.clone();
            Box::pin(async move {
                handler_definir_embedding_intent(state.treinamento.as_ref(), env).await
            })
        })
        .route("ListIntents", move |env| {
            let state = s_intent_listar.clone();
            Box::pin(async move { handler_list_intents(state.treinamento.as_ref(), env).await })
        })
        .route("CreateIntent", move |env| {
            let state = s_intent_criar.clone();
            Box::pin(async move {
                handler_create_intent(state.treinamento.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("UpdateIntent", move |env| {
            let state = s_intent_atualizar.clone();
            Box::pin(async move {
                handler_update_intent(state.treinamento.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("RemoveIntent", move |env| {
            let state = s_intent_remover.clone();
            Box::pin(async move {
                handler_remove_intent(state.treinamento.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("ListTreinamentos", move |env| {
            let state = s_trn_listar.clone();
            Box::pin(
                async move { handler_list_treinamentos(state.treinamento.as_ref(), env).await },
            )
        })
        .route("GetTreinamento", move |env| {
            let state = s_trn_obter.clone();
            Box::pin(async move { handler_get_treinamento(state.treinamento.as_ref(), env).await })
        })
        .route("FinalizarTreinamento", move |env| {
            let state = s_trn_finalizar.clone();
            Box::pin(async move {
                handler_finalizar_treinamento(state.treinamento.as_ref(), state.audit.as_ref(), env)
                    .await
            })
        })
        .route("RemoverTreinamento", move |env| {
            let state = s_trn_remover.clone();
            Box::pin(async move {
                handler_remover_treinamento(state.treinamento.as_ref(), state.audit.as_ref(), env)
                    .await
            })
        })
        .route("VerifyCredentials", move |env| {
            let state = state_for_verify.clone();
            Box::pin(async move {
                handler_verify_credentials(state.auth.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("UpsertContact", move |env| {
            let state = state_for_upsert.clone();
            Box::pin(async move {
                handler_upsert_contact(state.cliente.as_ref(), state.audit.as_ref(), env).await
            })
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
        .route("ReenviarConvite", move |env| {
            let state = state_for_reenviar_convite.clone();
            Box::pin(async move {
                handler_reenviar_convite(state.tenant.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("SolicitarRedefinicaoSenha", move |env| {
            let state = state_for_solicitar_redefinicao.clone();
            Box::pin(async move {
                handler_solicitar_redefinicao_senha(state.auth.as_ref(), state.audit.as_ref(), env)
                    .await
            })
        })
        .route("RedefinirSenha", move |env| {
            let state = state_for_redefinir_senha.clone();
            Box::pin(async move {
                handler_redefinir_senha(state.auth.as_ref(), state.audit.as_ref(), env).await
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
        .route("AdminListUsers", move |env| {
            let state = state_for_admin_list_users.clone();
            Box::pin(async move { handler_admin_list_users(state.auth.as_ref(), env).await })
        })
        .route("AdminSetUserActive", move |env| {
            let state = state_for_admin_set_user_active.clone();
            Box::pin(async move {
                handler_admin_set_user_active(state.auth.as_ref(), state.audit.as_ref(), env).await
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
        .route("RegisterStorageUsage", move |env| {
            let state = state_for_register_storage_usage.clone();
            Box::pin(async move { handler_register_storage_usage(state.quota.as_ref(), env).await })
        })
        .route("ListDepartamentos", move |env| {
            let state = s_dep_listar.clone();
            Box::pin(
                async move { handler_list_departamentos(state.operacional.as_ref(), env).await },
            )
        })
        .route("UpdateDepartamento", move |env| {
            let state = s_dep_update.clone();
            Box::pin(async move {
                handler_update_departamento(state.operacional.as_ref(), state.audit.as_ref(), env)
                    .await
            })
        })
        .route("DesativarDepartamento", move |env| {
            let state = s_dep_desativar.clone();
            Box::pin(async move {
                handler_desativar_departamento(
                    state.operacional.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("ListContatos", move |env| {
            let state = s_contatos.clone();
            Box::pin(async move { handler_list_contatos(state.cliente.as_ref(), env).await })
        })
        // C4 — o cadastro de contatos, que até aqui só a ingestão criava.
        .route("CreateContato", move |env| {
            let state = s_contato_criar.clone();
            Box::pin(async move {
                handler_create_contato(state.cliente.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("UpdateContato", move |env| {
            let state = s_contato_update.clone();
            Box::pin(async move {
                handler_update_contato(state.cliente.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("DefinirContatoAtivo", move |env| {
            let state = s_contato_ativo.clone();
            Box::pin(async move {
                handler_definir_contato_ativo(state.cliente.as_ref(), state.audit.as_ref(), env)
                    .await
            })
        })
        // B10 (N11 E5) — clientes (PJ/PF) e o vínculo com os contatos.
        .route("ListClientes", move |env| {
            let state = s_clientes_listar.clone();
            Box::pin(async move { handler_list_clientes(state.cliente.as_ref(), env).await })
        })
        .route("CreateCliente", move |env| {
            let state = s_cliente_criar.clone();
            Box::pin(async move {
                handler_create_cliente(state.cliente.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("UpdateCliente", move |env| {
            let state = s_cliente_atualizar.clone();
            Box::pin(async move {
                handler_update_cliente(state.cliente.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("DefinirClienteAtivo", move |env| {
            let state = s_cliente_ativo.clone();
            Box::pin(async move {
                handler_definir_cliente_ativo(state.cliente.as_ref(), state.audit.as_ref(), env)
                    .await
            })
        })
        .route("ListContatosDoCliente", move |env| {
            let state = s_cliente_contatos.clone();
            Box::pin(
                async move { handler_list_contatos_do_cliente(state.cliente.as_ref(), env).await },
            )
        })
        .route("VincularContatoCliente", move |env| {
            let state = s_cliente_vincular.clone();
            Box::pin(async move {
                handler_vincular_contato_cliente(state.cliente.as_ref(), state.audit.as_ref(), env)
                    .await
            })
        })
        .route("GetPainelTenant", move |env| {
            let state = s_painel.clone();
            Box::pin(async move { handler_painel_tenant(state.operacional.as_ref(), env).await })
        })
        .route("CreateAtendente", move |env| {
            let state = s_atendente_criar.clone();
            Box::pin(async move {
                handler_create_atendente(state.operacional.as_ref(), state.audit.as_ref(), env)
                    .await
            })
        })
        .route("UpdateAtendente", move |env| {
            let state = s_atendente_update.clone();
            Box::pin(async move {
                handler_update_atendente(state.operacional.as_ref(), state.audit.as_ref(), env)
                    .await
            })
        })
        .route("DesativarAtendente", move |env| {
            let state = s_atendente_desativar.clone();
            Box::pin(async move {
                handler_desativar_atendente(state.operacional.as_ref(), state.audit.as_ref(), env)
                    .await
            })
        })
        // N9 E13 — catálogo de campos do cartão.
        .route("ListCamposPersonalizados", move |env| {
            let state = s_campo_listar.clone();
            Box::pin(async move { handler_list_campos(state.operacional.as_ref(), env).await })
        })
        .route("CreateCampoPersonalizado", move |env| {
            let state = s_campo_criar.clone();
            Box::pin(async move {
                handler_create_campo(state.operacional.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("UpdateCampoPersonalizado", move |env| {
            let state = s_campo_update.clone();
            Box::pin(async move {
                handler_update_campo(state.operacional.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("DesativarCampoPersonalizado", move |env| {
            let state = s_campo_desativar.clone();
            Box::pin(async move {
                handler_desativar_campo(state.operacional.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("SetValorCampo", move |env| {
            let state = s_valor_campo.clone();
            Box::pin(async move { handler_set_valor_campo(state.operacional.as_ref(), env).await })
        })
        .route("ListFluxos", move |env| {
            let state = s_fluxo_listar.clone();
            Box::pin(async move { handler_list_fluxos(state.operacional.as_ref(), env).await })
        })
        .route("CreateFluxo", move |env| {
            let state = s_fluxo_criar.clone();
            Box::pin(async move {
                handler_create_fluxo(
                    state.quota.as_ref(),
                    state.operacional.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("UpdateFluxo", move |env| {
            let state = s_fluxo_update.clone();
            Box::pin(async move {
                handler_update_fluxo(state.operacional.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("DesativarFluxo", move |env| {
            let state = s_fluxo_desativar.clone();
            Box::pin(async move {
                handler_desativar_fluxo(state.operacional.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("ListEtapasFluxo", move |env| {
            let state = s_etapa_listar.clone();
            Box::pin(async move { handler_list_etapas(state.operacional.as_ref(), env).await })
        })
        .route("CreateEtapaFluxo", move |env| {
            let state = s_etapa_criar.clone();
            Box::pin(async move {
                handler_create_etapa(state.operacional.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("UpdateEtapaFluxo", move |env| {
            let state = s_etapa_update.clone();
            Box::pin(async move {
                handler_update_etapa(state.operacional.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("DesativarEtapaFluxo", move |env| {
            let state = s_etapa_desativar.clone();
            Box::pin(async move {
                handler_desativar_etapa(state.operacional.as_ref(), state.audit.as_ref(), env).await
            })
        })
        .route("MoverEtapaFluxo", move |env| {
            let state = s_etapa_mover.clone();
            Box::pin(async move { handler_mover_etapa(state.operacional.as_ref(), env).await })
        })
        .route("ListAtendentes", move |env| {
            let state = s_atendentes.clone();
            Box::pin(async move { handler_list_atendentes(state.operacional.as_ref(), env).await })
        })
        .route("CreateDepartamento", move |env| {
            let state = state_for_create_departamento.clone();
            Box::pin(async move {
                handler_create_departamento(
                    state.quota.as_ref(),
                    state.operacional.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
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
        .route("SuspenderAssinaturasVencidas", move |env| {
            let state = state_for_suspender_vencidas.clone();
            Box::pin(async move {
                handler_suspender_assinaturas_vencidas(
                    state.plans.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
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
            Box::pin(async move {
                handler_query_audit_log(state.operacional.as_ref(), state.audit.as_ref(), env).await
            })
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
        .route("ListNumerosIgnorados", move |env| {
            let state = state_for_listar_numeros_ignorados.clone();
            Box::pin(
                async move { handler_listar_numeros_ignorados(state.whatsapp.as_ref(), env).await },
            )
        })
        .route("CriarNumeroIgnorado", move |env| {
            let state = state_for_criar_numero_ignorado.clone();
            Box::pin(async move {
                handler_criar_numero_ignorado(state.whatsapp.as_ref(), state.audit.as_ref(), env)
                    .await
            })
        })
        .route("AtualizarNumeroIgnorado", move |env| {
            let state = state_for_atualizar_numero_ignorado.clone();
            Box::pin(async move {
                handler_atualizar_numero_ignorado(
                    state.whatsapp.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("RemoverNumeroIgnorado", move |env| {
            let state = state_for_remover_numero_ignorado.clone();
            Box::pin(async move {
                handler_remover_numero_ignorado(state.whatsapp.as_ref(), state.audit.as_ref(), env)
                    .await
            })
        })
        .route("DefinirDepartamentoDaConexao", move |env| {
            let state = state_for_definir_departamento_conexao.clone();
            Box::pin(async move {
                handler_definir_departamento_conexao(
                    state.whatsapp.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("DetalheDaConexao", move |env| {
            let state = state_for_detalhe_conexao.clone();
            Box::pin(async move { handler_detalhe_da_conexao(state.whatsapp.as_ref(), env).await })
        })
        .route("ListDepartamentosDasConexoes", move |env| {
            let state = state_for_departamentos_das_conexoes.clone();
            Box::pin(async move {
                handler_departamentos_das_conexoes(state.whatsapp.as_ref(), env).await
            })
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

    // Cadastro público de tenant e gestão de vouchers: registradas à parte para
    // não alongar ainda mais a cadeia acima (ver `registrar_rotas_onboarding`).
    let server = registrar_rotas_onboarding(server, state.clone());

    // Consentimentos OAuth dos clientes MCP (N13.2) — mesmo motivo de estarem à
    // parte: seis rotas novas não cabem na cadeia acima sem torná-la ilegível.
    let server = registrar_rotas_mcp(server, state.clone());

    tracing::info!("Servidor RPC configurado e pronto.");

    // Aguarda execução.
    //
    // O relay e o consumidor de auditoria não aparecem mais aqui: eles passaram
    // para `observability::supervisionar`, que derruba o processo com código 1 se
    // qualquer um deles cair. Antes, o término de um deles fazia este `select`
    // sair e o `main` retornar `Ok(())` — saída com código **0**, indistinguível
    // de parada limpa, e o motivo da queda se perdia.
    tokio::select! {
        res = server.run() => {
            if let Err(e) = res {
                tracing::error!("Servidor RPC parou com erro crítico: {:?}", e);
            }
        }
        _ = observability::aguardar_sinal_de_parada() => {}
    }

    observability::shutdown_telemetry();
    Ok(())
}

/// Registra as rotas dos consentimentos OAuth 2.1 dos clientes MCP (N13.2).
///
/// Duas delas (`ListMcpGrants`, `RevokeMcpGrant`) chegam da borda a pedido do
/// usuário; as outras quatro vêm do `control_plane` durante o fluxo OAuth e não
/// são alcançáveis de fora da rede interna.
fn registrar_rotas_mcp(server: Server, state: AppState) -> Server {
    let s_registrar = state.clone();
    let s_listar = state.clone();
    let s_revogar = state.clone();
    let s_ajustar = state.clone();
    let s_atividade = state.clone();
    let s_hash = state.clone();
    let s_buscar = state.clone();
    let s_reuso = state;

    server
        .route("RegisterMcpGrant", move |env| {
            let state = s_registrar.clone();
            Box::pin(async move {
                mcp_grants::handler_register_mcp_grant(
                    state.mcp_grants.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("ListMcpGrants", move |env| {
            let state = s_listar.clone();
            Box::pin(async move {
                mcp_grants::handler_list_mcp_grants(state.mcp_grants.as_ref(), env).await
            })
        })
        .route("ListMyAuditLog", move |env| {
            let state = s_atividade.clone();
            Box::pin(async move {
                mcp_grants::handler_list_my_audit_log(
                    state.mcp_grants.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("RevokeMcpGrant", move |env| {
            let state = s_revogar.clone();
            Box::pin(async move {
                mcp_grants::handler_revoke_mcp_grant(
                    state.mcp_grants.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("AjustarEscoposMcpGrant", move |env| {
            let state = s_ajustar.clone();
            Box::pin(async move {
                mcp_grants::handler_ajustar_escopos_mcp_grant(
                    state.mcp_grants.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("SetMcpGrantRefreshHash", move |env| {
            let state = s_hash.clone();
            Box::pin(async move {
                mcp_grants::handler_set_mcp_grant_refresh_hash(state.mcp_grants.as_ref(), env).await
            })
        })
        .route("GetMcpGrantComSegredo", move |env| {
            let state = s_buscar.clone();
            Box::pin(async move {
                mcp_grants::handler_get_mcp_grant_com_segredo(state.mcp_grants.as_ref(), env).await
            })
        })
        .route("RevokeMcpGrantPorReuso", move |env| {
            let state = s_reuso.clone();
            Box::pin(async move {
                mcp_grants::handler_revoke_mcp_grant_por_reuso(
                    state.mcp_grants.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
}

/// Registra as rotas do cadastro público e da gestão de vouchers.
///
/// As sete primeiras são a espinha do wizard e chegam aqui **sem sessão** — quem
/// as filtra é a borda (`runtime_api`), com rate limit por IP. As quatro últimas
/// são de superusuário e entram no catálogo `ROTAS_ADMIN` de lá.
fn registrar_rotas_onboarding(server: Server, state: AppState) -> Server {
    let s_check = state.clone();
    let s_planos = state.clone();
    let s_start = state.clone();
    let s_plano = state.clone();
    let s_redeem = state.clone();
    let s_ativar = state.clone();
    let s_status = state.clone();
    let s_progresso = state.clone();
    let s_progresso_get = state.clone();
    let s_criar_v = state.clone();
    let s_listar_v = state.clone();
    let s_revogar_v = state.clone();
    let s_resgates_v = state;

    server
        .route("CheckTenantSlug", move |env| {
            let state = s_check.clone();
            Box::pin(
                async move { onboarding::handler_check_slug(state.signup.as_ref(), env).await },
            )
        })
        .route("ListPublicPlans", move |env| {
            let state = s_planos.clone();
            Box::pin(async move {
                onboarding::handler_list_public_plans(state.signup.as_ref(), env).await
            })
        })
        .route("StartSignup", move |env| {
            let state = s_start.clone();
            Box::pin(async move {
                onboarding::handler_start_signup(state.signup.as_ref(), state.audit.as_ref(), env)
                    .await
            })
        })
        .route("SelectSignupPlan", move |env| {
            let state = s_plano.clone();
            Box::pin(async move {
                onboarding::handler_select_signup_plan(
                    state.signup.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("RedeemVoucher", move |env| {
            let state = s_redeem.clone();
            Box::pin(async move {
                onboarding::handler_redeem_voucher(
                    state.vouchers.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("ActivateSignup", move |env| {
            let state = s_ativar.clone();
            Box::pin(async move {
                onboarding::handler_activate_signup(
                    state.signup.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("GetSignupStatus", move |env| {
            let state = s_status.clone();
            Box::pin(async move {
                onboarding::handler_get_signup_status(state.signup.as_ref(), env).await
            })
        })
        .route("SetOnboardingProgress", move |env| {
            let state = s_progresso.clone();
            Box::pin(async move {
                onboarding::handler_set_onboarding_progress(
                    state.tenant.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("GetOnboardingProgress", move |env| {
            let state = s_progresso_get.clone();
            Box::pin(async move {
                onboarding::handler_get_onboarding_progress(state.tenant.as_ref(), env).await
            })
        })
        .route("CreateVoucher", move |env| {
            let state = s_criar_v.clone();
            Box::pin(async move {
                onboarding::handler_create_voucher(
                    state.vouchers.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("ListVouchers", move |env| {
            let state = s_listar_v.clone();
            Box::pin(async move {
                onboarding::handler_list_vouchers(
                    state.vouchers.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("RevokeVoucher", move |env| {
            let state = s_revogar_v.clone();
            Box::pin(async move {
                onboarding::handler_revoke_voucher(
                    state.vouchers.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("ListVoucherRedemptions", move |env| {
            let state = s_resgates_v.clone();
            Box::pin(async move {
                onboarding::handler_list_voucher_redemptions(
                    state.vouchers.as_ref(),
                    state.audit.as_ref(),
                    env,
                )
                .await
            })
        })
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
    // P2 — cursor da rolagem para trás; quando vem, manda no `offset`.
    let before_id = payload_json
        .get("before_id")
        .and_then(|v| v.as_i64())
        .filter(|v| *v > 0)
        .map(|v| v as i32);

    let ctx = contexto_do_envelope(&env);
    match store
        .listar_mensagens(&ctx, atendimento_id, limit, offset, before_id)
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
    // P1 — o mesmo recorte da v1. Campo ausente = sem filtro.
    let texto = |chave: &str| {
        payload_json
            .get(chave)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .trim()
            .to_string()
    };
    let filtro = infrastructure_postgres::atendimentos::atendimentos::FiltroDoQuadro {
        busca: texto("busca"),
        atendente_id: payload_json
            .get("atendente_id")
            .and_then(|v| v.as_i64())
            .filter(|v| *v != 0)
            .map(|v| v as i32),
        somente_nao_lidos: payload_json
            .get("somente_nao_lidos")
            .and_then(|v| v.as_bool())
            .unwrap_or(false),
        prioridade: texto("prioridade"),
        somente_meus: payload_json
            .get("somente_meus")
            .and_then(|v| v.as_bool())
            .unwrap_or(false),
        etiqueta_id: payload_json
            .get("etiqueta_id")
            .and_then(|v| v.as_i64())
            .filter(|v| *v > 0),
    };

    let ctx = contexto_do_envelope(&env);
    match store
        .listar_atendimentos(&ctx, &status, departamento_id, filtro, limit)
        .await
    {
        Ok(atendimentos) => {
            // B6 (N9 E4) — não lidas por conversa. A contagem falhar não esconde
            // o quadro: o cartão só fica sem o número.
            let ids: Vec<i32> = atendimentos.iter().map(|a| a.id).collect();
            let contagem = if ids.is_empty() {
                std::collections::HashMap::new()
            } else {
                store
                    .contar_nao_lidas(&ctx, ids.clone())
                    .await
                    .unwrap_or_else(|e| {
                        tracing::warn!(erro = %e, "falha ao contar mensagens não lidas");
                        std::collections::HashMap::new()
                    })
            };
            // P13 — o contato de cada cartão. O cartão mostrava `Contato #id`;
            // falhar aqui também não esconde o quadro.
            let contatos = if ids.is_empty() {
                std::collections::HashMap::new()
            } else {
                store
                    .contatos_do_quadro(&ctx, ids.clone())
                    .await
                    .unwrap_or_else(|e| {
                        tracing::warn!(erro = %e, "falha ao ler os contatos do quadro");
                        std::collections::HashMap::new()
                    })
            };
            let itens: Vec<serde_json::Value> = atendimentos
                .iter()
                .map(|a| {
                    let mut item = serde_json::to_value(a).unwrap_or_default();
                    if let Some(obj) = item.as_object_mut() {
                        obj.insert(
                            "nao_lidas".to_string(),
                            serde_json::json!(contagem.get(&a.id).copied().unwrap_or(0)),
                        );
                        if let Some(c) = contatos.get(&a.id) {
                            obj.insert("contato_nome".into(), serde_json::json!(c.nome));
                            obj.insert("contato_telefone".into(), serde_json::json!(c.telefone));
                            obj.insert("contato_foto_url".into(), serde_json::json!(c.foto_url));
                            obj.insert(
                                "revisao_pendente".into(),
                                serde_json::json!(c.revisao_pendente),
                            );
                        }
                    }
                    item
                })
                .collect();
            ok_reply(
                &env,
                "ListAtendimentosReply",
                serde_json::json!({ "atendimentos": itens }),
            )
        }
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

/// B6 (N9 E4) — marca como lidas as mensagens do contato numa conversa.
///
/// Sem auditoria, de propósito (plano N9): estado operacional trivial e de
/// altíssimo volume; o `data_lida` na mensagem já é o registro. Devolve o que
/// espelhar no WhatsApp — quem fala com o provedor é o runtime, não o banco.
async fn handler_marcar_atendimento_lido(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let atendimento_id = match payload_json.get("atendimento_id").and_then(|v| v.as_i64()) {
        Some(i) if i > 0 => i as i32,
        _ => {
            return erro(
                error_core::AppError::Validation("atendimento_id ausente".into()),
                &env,
            )
        }
    };

    let ctx = contexto_do_envelope(&env);
    match store.marcar_atendimento_lido(&ctx, atendimento_id).await {
        Ok(leitura) => ok_reply(
            &env,
            "MarcarAtendimentoLidoReply",
            serde_json::json!({
                "marcadas": leitura.marcadas,
                "whatsapp": espelho_da_leitura(&leitura),
            }),
        ),
        Err(infrastructure_postgres::DbError::NotFound) => erro(
            error_core::AppError::Validation("atendimento não encontrado".into()),
            &env,
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

/// B6 — o pedido para o WhatsApp, no formato do `MarkWhatsappMessageRead`;
/// `null` quando não há o que espelhar (nada novo lido, ou conversa sem
/// WhatsApp ativo).
fn espelho_da_leitura(
    leitura: &infrastructure_postgres::atendimentos::mensagens::LeituraMarcada,
) -> serde_json::Value {
    match (&leitura.instance_id, &leitura.telefone) {
        (Some(instancia), Some(telefone)) if !leitura.message_ids_whatsapp.is_empty() => {
            serde_json::json!({
                "id": instancia,
                "chat": telefone,
                "message_ids": leitura.message_ids_whatsapp,
            })
        }
        _ => serde_json::Value::Null,
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

            // O nome da empresa acompanha o convite porque quem manda o e-mail
            // é a borda, e ela não tem como descobri-lo sem uma volta extra ao
            // banco — enquanto aqui ele está a uma consulta de distância, na
            // transação que já está aberta. Sem o nome, o convidado receberia
            // "alguém criou um acesso para você", que é a cara de golpe.
            let empresa = store
                .buscar_por_id(invite.tenant_id)
                .await
                .ok()
                .flatten()
                .map(|t| t.name)
                .unwrap_or_default();

            ok_reply(
                &env,
                "CreateInviteReply",
                serde_json::json!({
                    "status": "success",
                    "invite": {
                        "id": invite.id.to_string(),
                        "tenant_name": empresa,
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

/// N11 E8 — manda de novo um convite que não foi aceito.
///
/// Renova a validade (o vencido inclusive: é o caso de quem não abriu o e-mail
/// a tempo) e devolve o convite com o token, para a borda reenviar o mesmo
/// link. Aceito ou revogado não volta — revogar é uma decisão, e reenviar por
/// cima dela a desfaria sem ninguém perceber.
async fn handler_reenviar_convite(
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
    // Espelha a validade da criação (`handler_create_invite`).
    let expira_em = chrono::Utc::now() + chrono::Duration::days(7);

    match store.renovar_convite(&ctx, invite_id, expira_em).await {
        Ok(Some(invite)) => {
            audit
                .publish(
                    &env,
                    "tenant_invite_resent",
                    "Convite reenviado".to_string(),
                    serde_json::json!({ "invite_id": invite_id.to_string() }),
                )
                .await;

            // O nome da empresa vai junto pelo mesmo motivo da criação: sem ele
            // o e-mail diz "alguém criou um acesso para você", que é a cara de
            // golpe.
            let empresa = store
                .buscar_por_id(invite.tenant_id)
                .await
                .ok()
                .flatten()
                .map(|t| t.name)
                .unwrap_or_default();

            ok_reply(
                &env,
                "ReenviarConviteReply",
                serde_json::json!({
                    "invite": {
                        "id": invite.id.to_string(),
                        "tenant_name": empresa,
                        "email": invite.email,
                        "name": invite.name,
                        "token": invite.token,
                        "expires_at": invite.expires_at.timestamp_millis(),
                    }
                }),
            )
        }
        Ok(None) => erro(
            error_core::AppError::Conflict(
                "convite inexistente, já aceito ou revogado".to_string(),
            ),
            &env,
        ),
        Err(err) => erro(err.into(), &env),
    }
}

/// Validade do link de redefinição de senha.
///
/// Curta de propósito: o link é uma senha temporária que mora numa caixa de
/// entrada, e caixa de entrada vaza. Uma hora cobre quem pediu e foi abrir o
/// e-mail em seguida, que é praticamente todo mundo.
const VALIDADE_REDEFINICAO_MIN: i64 = 60;

/// O hash que a borda manda: SHA-256 em hexadecimal. Qualquer outra coisa é
/// chamador quebrado, e aceitar gravaria um token que ninguém conseguiria usar.
fn hash_de_token_valido(hash: &str) -> bool {
    hash.len() == 64 && hash.bytes().all(|b| b.is_ascii_hexdigit())
}

/// N11 E8 — alguém esqueceu a senha.
///
/// **Nunca diz ao cliente se a conta existe.** O `enviar` da resposta é lido só
/// pela borda, que responde "aceito" nos dois casos e decide se manda o e-mail.
/// O token nasce na borda e chega aqui já como hash: o banco nunca vê o token.
async fn handler_solicitar_redefinicao_senha(
    store: &dyn ports::AuthStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let login = payload
        .get("login")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    let token_hash = payload
        .get("token_hash")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    if login.is_empty() || !hash_de_token_valido(token_hash) {
        return erro(
            error_core::AppError::Validation("login e token_hash obrigatórios".to_string()),
            &env,
        );
    }

    let nao_enviar = || {
        ok_reply(
            &env,
            "SolicitarRedefinicaoSenhaReply",
            serde_json::json!({ "enviar": false }),
        )
    };

    // Conta desativada não recebe link: trocar a senha de quem foi bloqueado
    // não pode ser o caminho de volta para dentro.
    let usuario = match store.buscar_por_login(login).await {
        Ok(Some(u)) if u.is_active && !u.email.trim().is_empty() => u,
        Ok(_) => return nao_enviar(),
        Err(err) => return erro(err.into(), &env),
    };

    let expira_em = chrono::Utc::now() + chrono::Duration::minutes(VALIDADE_REDEFINICAO_MIN);
    if let Err(err) = store
        .registrar_redefinicao_senha(usuario.id, token_hash, expira_em)
        .await
    {
        return erro(err.into(), &env);
    }

    audit
        .publish_security(
            &env.traceparent,
            None,
            "INFO",
            "password_reset_requested",
            "Redefinição de senha solicitada".to_string(),
            serde_json::json!({ "user_id": usuario.id }),
            Some(usuario.id),
        )
        .await;

    let nome = if usuario.first_name.trim().is_empty() {
        usuario.username.clone()
    } else {
        usuario.first_name.clone()
    };
    ok_reply(
        &env,
        "SolicitarRedefinicaoSenhaReply",
        serde_json::json!({
            "enviar": true,
            "email": usuario.email,
            "nome": nome,
            "validade_min": VALIDADE_REDEFINICAO_MIN,
        }),
    )
}

/// N11 E8 — troca a senha com o token do e-mail.
///
/// Senha fraca é `Validation` e link que não vale é `Conflict`: a tela precisa
/// dizer coisas diferentes nos dois casos ("escolha outra senha" contra "peça
/// um link novo").
async fn handler_redefinir_senha(
    store: &dyn ports::AuthStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let token_hash = payload
        .get("token_hash")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let senha = payload
        .get("password")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    if !hash_de_token_valido(token_hash) {
        return erro(
            error_core::AppError::Conflict("link de redefinição inválido".to_string()),
            &env,
        );
    }
    // A mesma regra do cadastro e do superusuário.
    if senha.chars().count() < 8 {
        return erro(
            error_core::AppError::Validation(
                "a senha precisa ter ao menos 8 caracteres".to_string(),
            ),
            &env,
        );
    }

    // O hash vem antes de consumir o token: se o argon2 falhasse depois, o
    // link já estaria gasto e a senha, intacta.
    let password_hash = match infrastructure_postgres::hash_password_async(senha.to_string()).await
    {
        Ok(h) => h,
        Err(err) => return erro(error_core::AppError::Internal(err.to_string()), &env),
    };

    match store.redefinir_senha(token_hash, &password_hash).await {
        Ok(Some(user_id)) => {
            audit
                .publish_security(
                    &env.traceparent,
                    None,
                    "INFO",
                    "password_reset_completed",
                    "Senha redefinida pelo link de recuperação".to_string(),
                    serde_json::json!({ "user_id": user_id }),
                    Some(user_id),
                )
                .await;
            ok_reply(
                &env,
                "RedefinirSenhaReply",
                serde_json::json!({ "user_id": user_id }),
            )
        }
        Ok(None) => erro(
            error_core::AppError::Conflict(
                "Este link de redefinição não vale mais. Peça um novo.".to_string(),
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
/// D7 — lista usuários de todos os tenants (painel do superusuário).
///
/// A v1 tinha isto no admin do Django; a v2 só tinha `ListTenantUsers`, que
/// resolve o tenant a partir de quem chama e nunca enxerga além do próprio.
async fn handler_admin_list_users(store: &dyn ports::AuthStore, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let busca = payload_json
        .get("busca")
        .and_then(|v| v.as_str())
        .unwrap_or_default();
    // Teto de 200: a listagem é paginada e um pedido sem limite traria a base de
    // usuários inteira num único envelope.
    let limite = payload_json
        .get("limite")
        .and_then(|v| v.as_i64())
        .unwrap_or(50)
        .clamp(1, 200);
    let offset = payload_json
        .get("offset")
        .and_then(|v| v.as_i64())
        .unwrap_or(0)
        .max(0);

    match store.listar_usuarios_global(busca, limite, offset).await {
        Ok(usuarios) => {
            let lista: Vec<serde_json::Value> = usuarios
                .iter()
                .map(|u| {
                    serde_json::json!({
                        "id": u.id,
                        "username": u.username,
                        "email": u.email,
                        "nome": format!("{} {}", u.first_name, u.last_name).trim().to_string(),
                        "is_active": u.is_active,
                        "is_superuser": u.is_superuser,
                        "last_login": u.last_login.map(|d| d.timestamp_millis()),
                        "date_joined": u.date_joined.timestamp_millis(),
                        "tenant_dono": u.tenant_dono,
                        "tenant_membro": u.tenant_membro,
                        "papel": u.papel,
                    })
                })
                .collect();
            ok_reply(
                &env,
                "AdminListUsersReply",
                serde_json::json!({ "usuarios": lista }),
            )
        }
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

/// D7 — bloqueia/desbloqueia o acesso de um usuário.
///
/// **O superusuário não pode se bloquear.** Não é zelo: `is_active = false`
/// derruba o login, e o único caminho de volta seria um `UPDATE` manual no
/// banco. A recusa acontece aqui, com o autor vindo do envelope — o cliente não
/// tem como ser a única defesa contra isso.
async fn handler_admin_set_user_active(
    store: &dyn ports::AuthStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let user_id = payload_json
        .get("user_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;
    let ativo = payload_json
        .get("ativo")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);

    if user_id <= 0 {
        return erro(
            error_core::AppError::Validation("id de usuário inválido".to_string()),
            &env,
        );
    }
    if !ativo && user_id == env.auth_user_id {
        return erro(
            error_core::AppError::Validation(
                "não é possível bloquear o próprio acesso".to_string(),
            ),
            &env,
        );
    }

    match store.definir_usuario_ativo(user_id, ativo).await {
        Ok(false) => erro(
            error_core::AppError::Validation("usuário não encontrado".to_string()),
            &env,
        ),
        Ok(true) => {
            // Evento crítico: mexer em acesso é o que a trilha de auditoria
            // existe para registrar. Sem e-mail nem nome — o id basta para
            // reconstituir quem foi.
            audit
                .publish(
                    &env,
                    "usuario.acesso_alterado",
                    if ativo {
                        "Acesso do usuario DESBLOQUEADO pelo superusuario".to_string()
                    } else {
                        "Acesso do usuario BLOQUEADO pelo superusuario".to_string()
                    },
                    serde_json::json!({ "user_id": user_id, "ativo": ativo }),
                )
                .await;
            ok_reply(
                &env,
                "AdminSetUserActiveReply",
                serde_json::json!({ "ativo": ativo }),
            )
        }
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

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
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let ctx = contexto_do_envelope(&env);
    // `atendimento_id` e `sender_id` são OBRIGATÓRIOS. Antes havia default
    // silencioso (`atendimento_id = 1`, `sender_id = "usuario"`): um payload
    // truncado gravava a mensagem de um contato dentro da conversa alheia de
    // id 1 do tenant, sem erro nenhum. Falhar é o comportamento correto — o
    // chamador é sempre um serviço interno, e a reentrega da PEL o traz de volta.
    let atendimento_id = match payload_json.get("atendimento_id").and_then(|v| v.as_i64()) {
        Some(id) => id as i32,
        None => {
            return erro(
                error_core::AppError::Validation("atendimento_id ausente".into()),
                &env,
            )
        }
    };
    let remetente = match payload_json
        .get("sender_id")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
    {
        Some(r) => r,
        None => {
            return erro(
                error_core::AppError::Validation("sender_id ausente".into()),
                &env,
            )
        }
    };
    // Conteúdo vazio é legítimo (mídia sem legenda: o texto útil vem depois, em
    // `analise_midia`), então aqui o default é a string vazia da própria coluna.
    let conteudo = payload_json
        .get("content")
        .and_then(|v| v.as_str())
        .unwrap_or_default();
    let tipo = payload_json
        .get("tipo")
        .and_then(|v| v.as_str())
        .filter(|t| !t.is_empty())
        .unwrap_or("texto");

    let origem = ports::OrigemMensagem {
        message_id_whatsapp: payload_json
            .get("message_id_whatsapp")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .map(|s| s.to_string()),
        citando_message_id_whatsapp: payload_json
            .get("citando_message_id_whatsapp")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .map(|s| s.to_string()),
        ja_entregue: payload_json
            .get("ja_entregue")
            .and_then(|v| v.as_bool())
            .unwrap_or(false),
        // Só o bot manda este campo; para os demais remetentes fica nulo.
        confianca_resposta: payload_json
            .get("confianca")
            .and_then(|v| v.as_f64())
            .filter(|c| c.is_finite()),
        // P8 — opções da enquete, itens da lista, rótulos dos botões, vCard.
        // Objeto vazio não é gravado: sujar toda linha do thread com `{}` de
        // chaves seria desperdício, e a coluna já tem esse default.
        metadados: payload_json
            .get("metadados")
            .filter(|v| v.as_object().is_some_and(|o| !o.is_empty()))
            .cloned(),
    };

    // O traceparent é persistido no outbox para manter o trace distribuído vivo
    // até o relay republicar o evento no barramento. Ingestão inbound/bot: sem
    // action_id (dedupe é só para o envio outbound do atendente via sync offline);
    // a idempotência aqui vem do stanzaId em `origem`, quando informado.
    match store
        .persistir_mensagem(
            &ctx,
            atendimento_id,
            tipo,
            conteudo,
            remetente,
            &env.traceparent,
            None,
            origem,
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

/// Teto diário de conversas abertas pelo painel, por tenant (C3).
///
/// A evolution-go é whatsmeow: aceita qualquer JID, sem a janela de 24 h da
/// Cloud API. Iniciar conversa é tecnicamente trivial — e é o caminho mais
/// curto para o número do tenant ser denunciado e o WhatsApp derrubá-lo.
///
/// 50 é folgado para uso humano (um operador não abre cinquenta fichas à mão
/// num dia) e apertado para disparo em massa, que é o único uso que esbarra
/// aqui. Constante por ora; se algum tenant legítimo bater no teto, ele vira
/// plano — e aí é um número por plano, não um por instalação.
const TETO_DIARIO_CONVERSAS_MANUAIS: i64 = 50;

/// C3 — alguém no painel decide falar primeiro com um cliente cadastrado.
///
/// Até aqui um atendimento só nascia de uma mensagem que chegou. Quem queria
/// procurar o cliente tinha de abrir o WhatsApp por fora, mandar a mensagem e
/// esperar a resposta cair no quadro — e o histórico dessa conversa começava
/// pela metade.
async fn handler_iniciar_atendimento_manual(
    store: &dyn ports::AtendimentoStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let inteiro = |chave: &str| {
        payload
            .get(chave)
            .and_then(|v| v.as_i64())
            .map(|v| v as i32)
    };

    let (contato_id, fluxo_id, etapa_inicial_id) = match (
        inteiro("contato_id"),
        inteiro("fluxo_id"),
        inteiro("etapa_inicial_id"),
    ) {
        (Some(c), Some(f), Some(e)) => (c, f, e),
        _ => {
            // A etapa é exigida junto com o fluxo, e não preenchida por
            // padrão: um atendimento sem etapa não aparece em coluna nenhuma
            // do quadro. Nascer invisível é pior que recusar.
            return erro(
                error_core::AppError::Validation(
                    "contato_id, fluxo_id e etapa_inicial_id são obrigatórios".into(),
                ),
                &env,
            );
        }
    };

    let assunto = payload
        .get("assunto")
        .and_then(|v| v.as_str())
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string());

    let ctx = contexto_do_envelope(&env);

    // O teto vem antes da criação, e a contagem ignora conversas que já
    // trocaram mensagem: quem responde a quem escreveu não é limitado por
    // nada. Uma falha ao contar não barra ninguém — o teto protege de abuso,
    // e transformá-lo em ponto único de falha impediria o uso legítimo por um
    // problema que não é do usuário.
    if let Ok(abertas) = store.contar_conversas_abertas_hoje(&ctx).await {
        if abertas >= TETO_DIARIO_CONVERSAS_MANUAIS {
            return erro(
                error_core::AppError::Conflict(format!(
                    "Você já abriu {abertas} conversas hoje sem trocar mensagem \
                     (o limite é {TETO_DIARIO_CONVERSAS_MANUAIS}). O limite existe \
                     para o WhatsApp não denunciar o seu número por disparo em \
                     massa. Amanhã ele reinicia."
                )),
                &env,
            );
        }
    }

    match store
        .iniciar_atendimento_manual(
            &ctx,
            contato_id,
            fluxo_id,
            etapa_inicial_id,
            inteiro("departamento_id"),
            assunto,
        )
        .await
    {
        Ok((atendimento, ja_existia)) => {
            // Só audita o que de fato criou. Reabrir a conversa que já estava
            // aberta não é um ato novo, e registrá-lo encheria a trilha de
            // ruído justamente onde ela serve para responder "quem começou a
            // falar com este cliente?".
            if !ja_existia {
                audit
                    .publish(
                        &env,
                        "atendimento.iniciado_manualmente",
                        format!("Atendimento #{} iniciado pelo painel", atendimento.id),
                        // Sem o assunto e sem a mensagem: a trilha diz quem
                        // falou com quem, não o que foi dito.
                        serde_json::json!({
                            "atendimento_id": atendimento.id,
                            "contato_id": contato_id,
                            "fluxo_id": fluxo_id,
                        }),
                    )
                    .await;
            }

            ok_reply(
                &env,
                "IniciarAtendimentoManualReply",
                serde_json::json!({
                    "atendimento_id": atendimento.id,
                    "ja_existia": ja_existia,
                }),
            )
        }
        Err(err) => erro(err.into(), &env),
    }
}

async fn handler_resolve_atendimento_para_contato(
    store: &dyn ports::AtendimentoStore,
    whatsapp: &dyn ports::WhatsappStore,
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

    // D3: a barreira mais externa do bot é a da INSTÂNCIA, e ela é resolvida
    // aqui — no mesmo RPC que já roda uma vez por mensagem — para não custar uma
    // ida extra ao banco no caminho quente. Ausente ou ilegível resolve para
    // "responde": a instância nasce com `resposta_bot = TRUE` e uma falha de
    // leitura não pode calar o bot de quem nunca o desligou.
    let instancia_responde_bot = match payload_json.get("instance_id").and_then(|v| v.as_i64()) {
        Some(id) => whatsapp
            .buscar_instancia(&contexto_do_envelope(&env), id as i32)
            .await
            .ok()
            .flatten()
            .map(|i| i.resposta_bot)
            .unwrap_or(true),
        None => true,
    };

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
                "instancia_responde_bot": instancia_responde_bot,
                "atendente_humano_id": atendimento.atendente_humano_id,
                "is_new": is_new,
            }),
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

/// D3 — liga/desliga a resposta automática da IA **nesta conversa**.
///
/// O caminho de volta que faltava. `assumir_atendimento` desliga o bot ao alguém
/// assumir o cartão, e nada no servidor devolvia o valor para `true`: uma
/// conversa que passou por um humano ficava sem bot para sempre.
///
/// A tranca do `desatribuir` continua de pé — devolver o cartão não religa
/// sozinho. O que muda é existir uma ação deliberada para religar.
async fn handler_definir_bot_da_conversa(
    store: &dyn ports::AtendimentoStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let atendimento_id = match payload_json.get("atendimento_id").and_then(|v| v.as_i64()) {
        Some(i) => i as i32,
        None => {
            return erro(
                error_core::AppError::Validation("atendimento_id ausente".into()),
                &env,
            )
        }
    };
    let habilitado = match payload_json.get("habilitado").and_then(|v| v.as_bool()) {
        Some(h) => h,
        None => {
            return erro(
                error_core::AppError::Validation("habilitado ausente".into()),
                &env,
            )
        }
    };

    let ctx = contexto_do_envelope(&env);
    match store
        .definir_bot_da_conversa(&ctx, atendimento_id, habilitado)
        .await
    {
        Ok(true) => {
            audit
                .publish(
                    &env,
                    "atendimento.bot_alterado",
                    if habilitado {
                        "Resposta automatica da IA LIGADA para o atendimento".to_string()
                    } else {
                        "Resposta automatica da IA DESLIGADA para o atendimento".to_string()
                    },
                    serde_json::json!({
                        "atendimento_id": atendimento_id,
                        "habilitado": habilitado,
                    }),
                )
                .await;
            ok_reply(
                &env,
                "DefinirBotDaConversaReply",
                serde_json::json!({ "habilitado": habilitado }),
            )
        }
        Ok(false) => erro(
            error_core::AppError::Validation("atendimento não encontrado".into()),
            &env,
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

/// D3 — liga/desliga a resposta automática da IA para a instância inteira.
///
/// Equivale ao `InstanceToggleBotView` da v1. A v2 tinha perdido a capacidade:
/// só existia o desligamento por conversa (`bot_pode_atender`), que além de tudo
/// não tem controle em tela nenhuma e só desliga — nunca religa.
///
/// Auditado sempre que efetiva: "por que o bot parou de responder?" precisa ter
/// resposta, e sem trilha a pergunta fica sem dono.
async fn handler_definir_resposta_bot_instancia(
    store: &dyn ports::WhatsappStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let id = match payload_json.get("id").and_then(|v| v.as_i64()) {
        Some(i) => i as i32,
        None => {
            return erro(
                error_core::AppError::Validation("id da instância ausente".into()),
                &env,
            )
        }
    };
    // Sem default: "não mandou o campo" é erro de contrato, não "desligue".
    let habilitado = match payload_json.get("habilitado").and_then(|v| v.as_bool()) {
        Some(h) => h,
        None => {
            return erro(
                error_core::AppError::Validation("habilitado ausente".into()),
                &env,
            )
        }
    };

    let ctx = contexto_do_envelope(&env);
    match store.definir_resposta_bot(&ctx, id, habilitado).await {
        Ok(true) => {
            audit
                .publish(
                    &env,
                    "instancia.bot_alterado",
                    if habilitado {
                        "Resposta automatica da IA LIGADA para a conexao".to_string()
                    } else {
                        "Resposta automatica da IA DESLIGADA para a conexao".to_string()
                    },
                    serde_json::json!({ "instance_id": id, "habilitado": habilitado }),
                )
                .await;
            ok_reply(
                &env,
                "DefinirRespostaBotInstanciaReply",
                serde_json::json!({ "alterado": true, "habilitado": habilitado }),
            )
        }
        // Instância de outro tenant (ou inexistente) responde o mesmo: quem
        // chuta um id não descobre se ele existe.
        Ok(false) => erro(
            error_core::AppError::Validation("conexão não encontrada".into()),
            &env,
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

/// P16 — liga (worker) ou desliga (atendente) a marca "revisar".
///
/// Só a conclusão por uma pessoa é auditada: ligar é consequência automática
/// de uma decisão que já está no evento `bot.respondeu`.
async fn handler_definir_revisao_pendente(
    store: &dyn ports::AtendimentoStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let Some(atendimento_id) = payload
        .get("atendimento_id")
        .and_then(|v| v.as_i64())
        .map(|v| v as i32)
    else {
        return erro(
            error_core::AppError::Validation("atendimento_id ausente".into()),
            &env,
        );
    };
    let Some(pendente) = payload.get("pendente").and_then(|v| v.as_bool()) else {
        return erro(
            error_core::AppError::Validation("pendente ausente".into()),
            &env,
        );
    };
    let ctx = contexto_do_envelope(&env);
    match store
        .definir_revisao_pendente(&ctx, atendimento_id, pendente)
        .await
    {
        Ok(mudou) => {
            if mudou && !pendente {
                audit
                    .publish(
                        &env,
                        "atendimento.revisao_concluida",
                        format!("resposta da IA no atendimento #{atendimento_id} revisada"),
                        serde_json::json!({ "atendimento_id": atendimento_id }),
                    )
                    .await;
            }
            ok_reply(
                &env,
                "DefinirRevisaoPendenteReply",
                serde_json::json!({ "mudou": mudou }),
            )
        }
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// P13 — o contato do atendimento, com a data da última consulta da foto.
async fn handler_contato_do_atendimento(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let Some(atendimento_id) = payload
        .get("atendimento_id")
        .and_then(|v| v.as_i64())
        .map(|v| v as i32)
    else {
        return erro(
            error_core::AppError::Validation("atendimento_id ausente".into()),
            &env,
        );
    };
    let ctx = contexto_do_envelope(&env);
    match store.contato_do_atendimento(&ctx, atendimento_id).await {
        Ok(Some(c)) => ok_reply(&env, "ContatoDoAtendimentoReply", serde_json::json!(c)),
        Ok(None) => erro(
            error_core::AppError::Database("atendimento não encontrado".into()),
            &env,
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// P13 — grava o resultado da consulta da foto. Sem auditoria, de propósito:
/// é enriquecimento derivado (decisão da N11 E6).
async fn handler_registrar_foto_do_contato(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let Some(contato_id) = payload
        .get("contato_id")
        .and_then(|v| v.as_i64())
        .map(|v| v as i32)
    else {
        return erro(
            error_core::AppError::Validation("contato_id ausente".into()),
            &env,
        );
    };
    let foto_url = payload
        .get("foto_url")
        .and_then(|v| v.as_str())
        .filter(|s| !s.trim().is_empty())
        .map(|s| s.to_string());
    let ctx = contexto_do_envelope(&env);
    match store
        .registrar_foto_do_contato(&ctx, contato_id, foto_url)
        .await
    {
        Ok(()) => ok_reply(
            &env,
            "RegistrarFotoDoContatoReply",
            serde_json::json!({ "sucesso": true }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// P9 — as mensagens do atendente que ficaram sem destino.
async fn handler_listar_nao_entregues(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let ctx = contexto_do_envelope(&env);
    match store.listar_nao_entregues(&ctx).await {
        Ok(itens) => ok_reply(
            &env,
            "ListMensagensNaoEntreguesReply",
            serde_json::json!({ "itens": itens }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// P8 — grava (ou apaga) a reação de alguém numa mensagem.
///
/// Alvo desconhecido responde `aplicou: false`, e não erro: reagir a uma
/// conversa anterior à integração é comum, e transformar isso em falha faria o
/// worker reprocessar o evento para sempre.
async fn handler_aplicar_reacao(store: &dyn ports::AtendimentoStore, env: Envelope) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let alvo = match payload
        .get("message_id_whatsapp")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
    {
        Some(a) => a,
        None => {
            return erro(
                error_core::AppError::Validation("message_id_whatsapp ausente".into()),
                &env,
            )
        }
    };
    // Vazio é remoção, e por isso não há validação de "emoji obrigatório".
    let emoji = payload
        .get("emoji")
        .and_then(|v| v.as_str())
        .unwrap_or_default();
    let de = payload
        .get("de")
        .and_then(|v| v.as_str())
        .unwrap_or("contato");

    let ctx = contexto_do_envelope(&env);
    match store.aplicar_reacao(&ctx, alvo, emoji, de).await {
        Ok(aplicou) => ok_reply(
            &env,
            "AplicarReacaoMensagemReply",
            serde_json::json!({ "aplicou": aplicou }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// P8 — nome de perfil e foto do evento `CONTACTS`.
async fn handler_atualizar_perfil_do_contato(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let telefone = match payload
        .get("telefone")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
    {
        Some(t) => t,
        None => {
            return erro(
                error_core::AppError::Validation("telefone ausente".into()),
                &env,
            )
        }
    };
    let nome = payload
        .get("nome_perfil")
        .and_then(|v| v.as_str())
        .unwrap_or_default();
    let foto = payload
        .get("foto_url")
        .and_then(|v| v.as_str())
        .unwrap_or_default();

    let ctx = contexto_do_envelope(&env);
    match store
        .atualizar_perfil_do_contato(&ctx, telefone, nome, foto)
        .await
    {
        // `false` = ninguém com esse telefone no tenant. É o caso comum quando o
        // provedor manda a agenda inteira do aparelho, e não é erro.
        Ok(atualizou) => ok_reply(
            &env,
            "AtualizarPerfilDoContatoReply",
            serde_json::json!({ "atualizou": atualizou }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
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

    // P7 — a conexão por onde a conversa entrou decide o departamento, e com
    // ele o fluxo. Ausente (0) preserva o comportamento anterior: primeiro fluxo
    // ativo do tenant. Um worker defasado não pode deixar a conversa fora do
    // quadro só por não mandar o campo novo.
    let instance_id = payload_json
        .get("instance_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;

    let ctx = contexto_do_envelope(&env);
    match store
        .aplicar_politica_ticket_kanban(&ctx, atendimento_id, instance_id)
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
    let action_id = extrair_action_id_opcional(&payload_json);

    let ctx = contexto_do_envelope(&env);
    match store
        .mover_etapa_atendimento(&ctx, atendimento_id, etapa_destino_id, motivo, action_id)
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

/// Vocabulário de `oraculo_atendimento.status`, herdado da v1.
///
/// A coluna é `VARCHAR(20)`: um status inventado passaria e sumiria de toda a
/// lógica que filtra por ele (painel, quadro, relatórios) sem erro nenhum.
const STATUS_DE_ATENDIMENTO: [&str; 6] = [
    "fila",
    "em_atendimento",
    "pendencia",
    "resolvido",
    "cancelado",
    "arquivado",
];

// --- Detalhe do atendimento: etiquetas e notas ---
//
// As tabelas existiam desde o começo e nenhum app as alcançava. São o que
// transforma o cartão numa ficha: por que a conversa está parada, o que já foi
// tentado, e o que ela tem em comum com outras.

#[tracing::instrument(skip_all, fields(rpc = "GetDetalheAtendimento", tenant_id = %env.tenant_id))]
async fn handler_detalhe_atendimento(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let atendimento_id = payload
        .get("atendimento_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;

    let ctx = contexto_do_envelope(&env);
    match store.detalhe_atendimento(&ctx, atendimento_id).await {
        Ok(detalhe) => ok_reply(&env, "GetDetalheAtendimentoReply", detalhe),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "CreateEtiqueta", tenant_id = %env.tenant_id))]
async fn handler_create_etiqueta(
    store: &dyn ports::AtendimentoStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let nome = payload
        .get("nome")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .trim()
        .to_string();
    let cor = payload
        .get("cor")
        .and_then(|v| v.as_str())
        .unwrap_or("#a98f71")
        .to_string();

    if nome.is_empty() {
        return erro(
            error_core::AppError::Validation("informe o nome da etiqueta".into()),
            &env,
        );
    }

    let ctx = contexto_do_envelope(&env);
    match store.criar_etiqueta(&ctx, nome.clone(), cor).await {
        Ok(etiqueta) => {
            audit
                .publish(
                    &env,
                    "etiqueta_criada",
                    format!("Etiqueta '{nome}' criada"),
                    etiqueta.clone(),
                )
                .await;
            ok_reply(&env, "CreateEtiquetaReply", etiqueta)
        }
        Err(err) => erro(err.into(), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "AlternarEtiqueta", tenant_id = %env.tenant_id))]
async fn handler_alternar_etiqueta(store: &dyn ports::AtendimentoStore, env: Envelope) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let atendimento_id = payload
        .get("atendimento_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;
    let etiqueta_id = payload
        .get("etiqueta_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(0);
    let aplicar = payload
        .get("aplicar")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);

    let ctx = contexto_do_envelope(&env);
    match store
        .alternar_etiqueta(&ctx, atendimento_id, etiqueta_id, aplicar)
        .await
    {
        Ok(ok) => ok_reply(
            &env,
            "AlternarEtiquetaReply",
            serde_json::json!({ "sucesso": ok }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "CreateNota", tenant_id = %env.tenant_id))]
async fn handler_create_nota(store: &dyn ports::AtendimentoStore, env: Envelope) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let atendimento_id = payload
        .get("atendimento_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;
    // A nota é texto livre do operador: PII. Não entra em log nem em auditoria.
    let texto = payload
        .get("texto")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .trim()
        .to_string();

    if texto.is_empty() {
        return erro(
            error_core::AppError::Validation("escreva a anotação".into()),
            &env,
        );
    }

    let ctx = contexto_do_envelope(&env);
    match store.criar_nota(&ctx, atendimento_id, texto).await {
        Ok(nota) => ok_reply(&env, "CreateNotaReply", nota),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "SetAtendimentoStatus", tenant_id = %env.tenant_id))]
async fn handler_set_atendimento_status(
    store: &dyn ports::AtendimentoStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let atendimento_id = payload
        .get("atendimento_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;
    let novo_status = payload
        .get("status")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_string();
    let motivo = payload
        .get("motivo")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_string();

    if !STATUS_DE_ATENDIMENTO.contains(&novo_status.as_str()) {
        return erro(
            error_core::AppError::Validation(format!("status desconhecido: '{novo_status}'")),
            &env,
        );
    }

    let ctx = contexto_do_envelope(&env);
    match store
        .definir_status_atendimento(&ctx, atendimento_id, novo_status.clone(), motivo)
        .await
    {
        Ok(resultado) => {
            audit
                .publish(
                    &env,
                    "atendimento_status_alterado",
                    format!("Atendimento {atendimento_id} → {novo_status}"),
                    resultado.clone(),
                )
                .await;

            // N8.5/E3: evento próprio para a solicitação da pesquisa. Sem ele não
            // dá para responder "quantos clientes chegamos a perguntar" — que é
            // metade da métrica de satisfação (a outra é quantos responderam).
            if resultado
                .get("pesquisa_solicitada")
                .and_then(|v| v.as_bool())
                .unwrap_or(false)
            {
                audit
                    .publish(
                        &env,
                        "atendimento.pesquisa_solicitada",
                        format!("pesquisa de satisfação enviada no atendimento {atendimento_id}"),
                        serde_json::json!({ "atendimento_id": atendimento_id }),
                    )
                    .await;
            }
            ok_reply(&env, "SetAtendimentoStatusReply", resultado)
        }
        // `.into()` preserva o ErrorCode: RBAC de fluxo negado não pode virar
        // erro de banco genérico na borda.
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
    let action_id = extrair_action_id_opcional(&payload_json);

    let ctx = contexto_do_envelope(&env);
    match store
        .persistir_mensagem(
            &ctx,
            atendimento_id,
            tipo,
            conteudo,
            "atendente",
            &env.traceparent,
            action_id,
            // Mensagem redigida no painel: ainda não passou pelo WhatsApp (o worker
            // é que a envia, drenando o outbox), então nasce sem stanzaId e pendente.
            ports::OrigemMensagem::default(),
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
/// D5 — varredura cross-tenant das conversas paradas (scheduler).
async fn handler_listar_inativos(store: &dyn ports::AtendimentoStore, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let limite = payload_json
        .get("limite")
        .and_then(|v| v.as_i64())
        .unwrap_or(100);
    let minutos_padrao = payload_json
        .get("minutos_padrao")
        .and_then(|v| v.as_i64())
        .unwrap_or(30);

    let ctx = contexto_do_envelope(&env);
    match store.listar_inativos(&ctx, limite, minutos_padrao).await {
        Ok(list) => {
            let itens: Vec<serde_json::Value> = list
                .into_iter()
                .map(|a| serde_json::json!({ "id": a.id, "tenant_id": a.tenant_id.to_string() }))
                .collect();
            ok_reply(
                &env,
                "ListarAtendimentosInativosReply",
                serde_json::json!({ "atendimentos": itens }),
            )
        }
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// D5 — arquiva uma conversa abandonada (tenant-scoped).
async fn handler_encerrar_por_inatividade(
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
    match store.encerrar_por_inatividade(&ctx, atendimento_id).await {
        // `encerrado: false` não é erro: entre a varredura e a escrita o cliente
        // pode ter voltado a escrever, e a recheca de status recusou. O job só
        // não conta essa linha.
        Ok(encerrado) => ok_reply(
            &env,
            "EncerrarAtendimentoPorInatividadeReply",
            serde_json::json!({ "encerrado": encerrado }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

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

/// N9/E1 — passo 1: o atendimento aceita esta mídia? Devolve a chave do objeto.
///
/// Não toca no bucket: só responde o que o banco sabe (atendimento do tenant,
/// permissão de fluxo, quota). A assinatura da URL é do `data_storage`, e quem
/// combina os dois é a borda.
async fn handler_autorizar_upload_midia(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let atendimento_id = match payload.get("atendimento_id").and_then(|v| v.as_i64()) {
        Some(id) => id as i32,
        None => {
            return erro(
                error_core::AppError::Validation("atendimento_id ausente".into()),
                &env,
            )
        }
    };
    let bytes = payload.get("bytes").and_then(|v| v.as_i64()).unwrap_or(0);

    let ctx = contexto_do_envelope(&env);
    match store
        .autorizar_upload_midia(&ctx, atendimento_id, bytes)
        .await
    {
        Ok(chave) => ok_reply(
            &env,
            "AutorizarUploadMidiaReply",
            serde_json::json!({ "chave": chave }),
        ),
        // `.into()` preserva o ErrorCode: quota estourada e RBAC negado não podem
        // virar erro de banco genérico na borda — a tela precisa distinguir.
        Err(err) => erro(err.into(), &env),
    }
}

/// N9/E1 — passo 3: põe na conversa a mídia já conferida.
///
/// **Auditado**: enviar arquivo ao contato é ação de operador com efeito externo
/// irreversível (o cliente recebe). A trilha registra quem, para qual
/// atendimento, tipo e tamanho — **nunca** o nome do arquivo (pode conter PII)
/// nem a legenda.
async fn handler_enviar_midia_atendimento(
    store: &dyn ports::AtendimentoStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let campo_texto = |nome: &str| {
        payload
            .get(nome)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string()
    };

    let atendimento_id = match payload.get("atendimento_id").and_then(|v| v.as_i64()) {
        Some(id) => id as i32,
        None => {
            return erro(
                error_core::AppError::Validation("atendimento_id ausente".into()),
                &env,
            )
        }
    };
    let chave = campo_texto("chave");
    if chave.is_empty() {
        return erro(
            error_core::AppError::Validation("chave do objeto ausente".into()),
            &env,
        );
    }
    let categoria = campo_texto("categoria");
    if categoria.is_empty() {
        return erro(
            // A categoria vem da conferência de conteúdo; sem ela, este handler
            // estaria confiando de novo no que o cliente declarou.
            error_core::AppError::Validation(
                "categoria ausente (mídia não passou pela conferência)".into(),
            ),
            &env,
        );
    }
    let bytes = payload.get("bytes").and_then(|v| v.as_i64()).unwrap_or(0);

    let midia = ports::atendimento::MidiaEnviada {
        atendimento_id,
        chave,
        mimetype: campo_texto("mimetype"),
        nome_arquivo: campo_texto("nome_arquivo"),
        legenda: campo_texto("legenda"),
        is_ptt: payload
            .get("is_ptt")
            .and_then(|v| v.as_bool())
            .unwrap_or(false),
        bytes,
        categoria: categoria.clone(),
    };

    let action_id = extrair_action_id_opcional(&payload);
    let ctx = contexto_do_envelope(&env);
    match store
        .enviar_midia(&ctx, midia, &env.traceparent, action_id)
        .await
    {
        Ok(msg) => {
            audit
                .publish(
                    &env,
                    "mensagem.midia_enviada",
                    format!(
                        "mídia ({categoria}, {bytes} bytes) enviada no atendimento {atendimento_id}"
                    ),
                    serde_json::json!({
                        "atendimento_id": atendimento_id,
                        "mensagem_id": msg.id,
                        "categoria": categoria,
                        "bytes": bytes,
                    }),
                )
                .await;
            ok_reply(
                &env,
                "EnviarMidiaAtendimentoReply",
                serde_json::json!({ "message_id": msg.id }),
            )
        }
        Err(err) => erro(err.into(), &env),
    }
}

/// N9/E2 — mídias do atendimento para a galeria da ficha.
///
/// Devolve os ponteiros e metadados; **não** assina URLs — quem faz isso é o
/// `data_storage`, e a borda compõe. Assinar aqui exigiria que o dono do banco
/// falasse S3.
async fn handler_listar_midias_atendimento(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let atendimento_id = match payload.get("atendimento_id").and_then(|v| v.as_i64()) {
        Some(id) => id as i32,
        None => {
            return erro(
                error_core::AppError::Validation("atendimento_id ausente".into()),
                &env,
            )
        }
    };
    let limit = payload
        .get("limit")
        .and_then(|v| v.as_i64())
        .unwrap_or(50)
        .clamp(1, 200);
    let offset = payload
        .get("offset")
        .and_then(|v| v.as_i64())
        .unwrap_or(0)
        .max(0);

    let ctx = contexto_do_envelope(&env);
    match store
        .listar_midias(&ctx, atendimento_id, limit, offset)
        .await
    {
        Ok(msgs) => {
            let midias: Vec<serde_json::Value> = msgs
                .iter()
                .map(|m| {
                    serde_json::json!({
                        "mensagem_id": m.id,
                        "chave": m.arquivo_midia,
                        "mimetype": m.mimetype_midia,
                        "filename": m.nome_arquivo_midia,
                        "size_bytes": m.tamanho_midia,
                        "timestamp": m.timestamp.timestamp_millis(),
                    })
                })
                .collect();
            ok_reply(
                &env,
                "ListarMidiasAtendimentoReply",
                serde_json::json!({ "midias": midias }),
            )
        }
        Err(err) => erro(err.into(), &env),
    }
}

/// N8.5/E3 — o atendimento aguarda resposta da pesquisa de satisfação?
///
/// O worker consulta antes de tratar a mensagem do contato como conversa nova:
/// dentro da janela, um "5" solto é a nota; fora dela, é uma pergunta.
async fn handler_aguardando_avaliacao(
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
    // Mesma janela do expirador: fora dela a conversa recomeça.
    let ttl_horas = payload_json
        .get("ttl_horas")
        .and_then(|v| v.as_i64())
        .unwrap_or(48);

    let ctx = contexto_do_envelope(&env);
    match store
        .aguardando_avaliacao(&ctx, atendimento_id, ttl_horas)
        .await
    {
        Ok(aguardando) => ok_reply(
            &env,
            "AtendimentoAguardandoAvaliacaoReply",
            serde_json::json!({ "aguardando": aguardando }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// N8.5/E3 — grava a nota e o comentário que o contato mandou.
///
/// **Auditado**: a avaliação vira métrica de operação e pode embasar decisão
/// sobre atendente; alteração desse dado precisa de trilha. A descrição carrega
/// só a NOTA — o comentário é texto livre do cliente (PII) e fica na coluna.
async fn handler_registrar_avaliacao(
    store: &dyn ports::AtendimentoStore,
    audit: &dyn ports::AuditPort,
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
    let nota = match payload_json.get("nota").and_then(|v| v.as_i64()) {
        // A escala é 1..5 (v1). Nota fora dela é erro de extração, não avaliação:
        // gravá-la contaminaria a média com valor que o cliente nunca deu.
        Some(n) if (1..=5).contains(&n) => n as i32,
        _ => {
            return erro(
                error_core::AppError::Validation("nota ausente ou fora de 1..5".into()),
                &env,
            )
        }
    };
    let comentario = payload_json
        .get("feedback")
        .and_then(|v| v.as_str())
        .unwrap_or_default();

    let ctx = contexto_do_envelope(&env);
    match store
        .registrar_avaliacao(&ctx, atendimento_id, nota, comentario)
        .await
    {
        Ok(gravou) => {
            if gravou {
                audit
                    .publish(
                        &env,
                        "atendimento.avaliado",
                        format!("atendimento '{atendimento_id}' avaliado com nota {nota}"),
                        serde_json::json!({ "atendimento_id": atendimento_id, "nota": nota }),
                    )
                    .await;
            }
            ok_reply(
                &env,
                "RegistrarAvaliacaoAtendimentoReply",
                serde_json::json!({ "gravado": gravou }),
            )
        }
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

/// B9 (N10 E2) — o assunto que a análise sugere: a intenção de maior confiança.
///
/// A v1 faz o mesmo e não inventa resumo por LLM — mais barato e previsível.
/// É rótulo de intenção, vocabulário fechado do tenant, e não texto do cliente:
/// por isso não é PII. Se um dia o assunto virar resumo gerado, passa a ser.
/// Nunca vazio; truncado nos 200 caracteres da coluna.
fn assunto_da_analise(intents: &serde_json::Value) -> Option<String> {
    intents
        .as_array()?
        .iter()
        .filter_map(|i| {
            let tipo = i.get("tipo")?.as_str()?.trim();
            let confianca = i.get("confianca").and_then(|c| c.as_f64()).unwrap_or(0.0);
            Some((tipo, confianca))
        })
        .filter(|(tipo, _)| !tipo.is_empty())
        .max_by(|a, b| a.1.total_cmp(&b.1))
        .map(|(tipo, _)| tipo.chars().take(200).collect())
}

/// B9 (N10 E1+E2) — grava a análise prévia de uma mensagem do contato e, na
/// primeira de um atendimento sem assunto, o assunto.
///
/// Sem auditoria, de propósito (plano N10): anotar análise numa mensagem não é
/// mutação sensível, e o assunto é enriquecimento derivado — editar à mão, sim,
/// seria auditável. Os valores de entidade podem ser PII e não entram em log.
async fn handler_anexar_analise_mensagem(
    store: &dyn ports::AtendimentoStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let Some(mensagem_id) = payload_json
        .get("mensagem_id")
        .and_then(|v| v.as_i64())
        .map(|v| v as i32)
    else {
        return erro(
            error_core::AppError::Validation("mensagem_id ausente".into()),
            &env,
        );
    };
    let atendimento_id = payload_json
        .get("atendimento_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;
    let lista = |chave: &str| {
        payload_json
            .get(chave)
            .filter(|v| v.is_array())
            .cloned()
            .unwrap_or_else(|| serde_json::json!([]))
    };
    let intents = lista("intents");
    let entidades = lista("entidades");
    let assunto = assunto_da_analise(&intents);

    let ctx = contexto_do_envelope(&env);
    match store
        .anexar_analise_mensagem(
            &ctx,
            mensagem_id,
            atendimento_id,
            intents,
            entidades,
            assunto,
        )
        .await
    {
        Ok(assunto_definido) => {
            // P14 — as etiquetas das intenções. Em transação própria: falhar
            // aqui não pode desfazer a análise, que já é útil sozinha.
            let piso = payload_json
                .get("piso_confianca")
                .and_then(|v| v.as_f64())
                .filter(|p| (0.0..=1.0).contains(p))
                .unwrap_or(crate::adapters::campos_extraidos::PISO_CONFIANCA_PADRAO);
            let intencoes: Vec<(String, f64)> = payload_json
                .get("intents")
                .and_then(|v| v.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|i| {
                            Some((
                                i.get("tipo")?.as_str()?.to_string(),
                                i.get("confianca")?.as_f64()?,
                            ))
                        })
                        .collect()
                })
                .unwrap_or_default();
            let mut etiquetas_aplicadas = 0usize;
            if atendimento_id > 0 && !intencoes.is_empty() {
                match store
                    .aplicar_etiquetas_da_analise(&ctx, atendimento_id, intencoes, piso)
                    .await
                {
                    Ok(aplicadas) => {
                        etiquetas_aplicadas = aplicadas.len();
                        for e in aplicadas {
                            // Mutação visível ao operador: a trilha responde
                            // "quem colou isso aqui". Nome de etiqueta não é PII.
                            audit
                                .publish(
                                    &env,
                                    "etiqueta.aplicada_por_ia",
                                    format!(
                                        "IA aplicou a etiqueta '{}' no atendimento #{}",
                                        e.nome, atendimento_id
                                    ),
                                    serde_json::json!({
                                        "atendimento_id": atendimento_id,
                                        "etiqueta_id": e.id,
                                        "confianca": e.confianca,
                                    }),
                                )
                                .await;
                        }
                    }
                    Err(e) => tracing::warn!(erro = %e, "falha ao aplicar etiquetas por intenção"),
                }
            }
            // P15 — as entidades completam o cadastro do contato, só no que está
            // vazio. Também em transação própria, pelo mesmo motivo das etiquetas.
            let entidades: Vec<(String, String, f64)> = payload_json
                .get("entidades")
                .and_then(|v| v.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|e| {
                            Some((
                                e.get("tipo")?.as_str()?.to_string(),
                                e.get("valor")?.as_str()?.to_string(),
                                e.get("confianca")?.as_f64()?,
                            ))
                        })
                        .collect()
                })
                .unwrap_or_default();
            let valores = infrastructure_postgres::clientes::contatos::valores_para_o_contato(
                &entidades, piso,
            );
            let mut campos_contato = 0usize;
            if atendimento_id > 0 && valores != Default::default() {
                match store
                    .enriquecer_contato(&ctx, atendimento_id, valores)
                    .await
                {
                    Ok((contato_id, campos)) if !campos.is_empty() => {
                        campos_contato = campos.len();
                        // Mutação de cadastro por agente automático: a trilha é
                        // o que permite desfazer. Só os NOMES dos campos — nome,
                        // e-mail e documento são PII direta.
                        audit
                            .publish(
                                &env,
                                "contato.enriquecido_por_ia",
                                format!(
                                    "IA completou {} campo(s) do contato #{}",
                                    campos.len(),
                                    contato_id
                                ),
                                serde_json::json!({
                                    "contato_id": contato_id,
                                    "atendimento_id": atendimento_id,
                                    "campos": campos,
                                }),
                            )
                            .await;
                    }
                    Ok(_) => {}
                    Err(e) => {
                        tracing::warn!(erro = %e, "falha ao completar o contato pela análise")
                    }
                }
            }
            ok_reply(
                &env,
                "AnexarAnaliseMensagemReply",
                serde_json::json!({
                    "assunto_definido": assunto_definido,
                    "etiquetas_aplicadas": etiquetas_aplicadas,
                    "campos_contato_preenchidos": campos_contato,
                }),
            )
        }
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
                "atendente_id": outcome.atendente_id,
                "atendente_nome": outcome.atendente_nome,
                "atendente_usuario_id": outcome.atendente_usuario_id,
            }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// Atualiza a última leitura de sentimento do atendimento (N6.5, best-effort).
async fn handler_atualizar_sentimento(
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
    let nota = payload_json
        .get("nota")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;
    let label = payload_json
        .get("label")
        .and_then(|v| v.as_str())
        .unwrap_or_default();

    let ctx = contexto_do_envelope(&env);
    match store
        .atualizar_sentimento(&ctx, atendimento_id, nota, label)
        .await
    {
        Ok(()) => ok_reply(
            &env,
            "AtualizarSentimentoAtendimentoReply",
            serde_json::json!({}),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// Resolve campos personalizados (coletados + pendentes obrigatórios) do
/// atendimento para o Responder — input-only, sem write-back (N6.3).
/// C1 — write-back do que a IA extraiu.
///
/// Chamado pelo worker depois de responder. As guardas ficam no adaptador; o
/// que este handler faz é traduzir o envelope e **registrar o desfecho** — que
/// é metade do valor da funcionalidade: sem o detalhamento por motivo, "a IA
/// não preenche" é indistinguível de "a IA preenche errado".
async fn handler_gravar_campos_extraidos(
    store: &dyn ports::AtendimentoStore,
    audit: &dyn ports::AuditPort,
    config_cache: &infrastructure_postgres::TenantConfigCache,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let atendimento_id = match payload.get("atendimento_id").and_then(|v| v.as_i64()) {
        Some(id) => id as i32,
        None => {
            return erro(
                error_core::AppError::Validation("atendimento_id ausente".into()),
                &env,
            )
        }
    };
    let campos: Vec<ports::CampoExtraidoDto> = payload
        .get("campos")
        .and_then(|v| serde_json::from_value(v.clone()).ok())
        .unwrap_or_default();
    let mensagem_origem_id = payload
        .get("mensagem_origem_id")
        .and_then(|v| v.as_i64())
        .map(|v| v as i32);

    let ctx = contexto_do_envelope(&env);
    // B4 — o piso é o do tenant. Sem conseguir ler a config, vale o padrão de
    // antes: ficar sem gravar nada seria pior, e gravar sem piso, muito pior.
    let piso = match config_cache.get_config(ctx.tenant_id).await {
        Ok(cfg) => cfg.confianca_minima_automatica,
        Err(e) => {
            tracing::warn!(erro = %e, "config do tenant indisponível; piso de extração padrão");
            crate::adapters::campos_extraidos::PISO_CONFIANCA_PADRAO
        }
    };
    match store
        .gravar_campos_extraidos(&ctx, atendimento_id, campos, mensagem_origem_id, piso)
        .await
    {
        Ok(resumo) => {
            // Só audita o que MUDOU a ficha. Um tick em que a IA não extraiu
            // nada é o caso comum, e registrá-lo encheria a trilha de ruído
            // justamente onde ela serve para responder "quem pôs isso aqui?".
            if resumo.gravados > 0 {
                audit
                    .publish(
                        &env,
                        "campo_personalizado.preenchido_pela_ia",
                        format!(
                            "{} campo(s) preenchido(s) pela IA no atendimento #{}",
                            resumo.gravados, atendimento_id
                        ),
                        // Nunca o valor: é livre, e pode ser CPF, endereço ou
                        // diagnóstico. Quantidade e atendimento bastam para a
                        // trilha; o conteúdo está na ficha, com controle de
                        // acesso próprio.
                        serde_json::json!({
                            "atendimento_id": atendimento_id,
                            "gravados": resumo.gravados,
                        }),
                    )
                    .await;
            }

            // O span leva os descartes por motivo — é com ele que se calibra o
            // piso de confiança depois. Nunca o `valor_json`.
            tracing::info!(
                atendimento_id,
                recebidos = resumo.recebidos,
                gravados = resumo.gravados,
                slug_desconhecido = resumo.slug_desconhecido,
                extracao_desligada = resumo.extracao_desligada,
                tipo_invalido = resumo.tipo_invalido,
                abaixo_do_piso = resumo.abaixo_do_piso,
                humano_no_caminho = resumo.humano_no_caminho,
                "ia.campos_extraidos"
            );

            ok_reply(
                &env,
                "GravarCamposExtraidosReply",
                serde_json::to_value(&resumo).unwrap_or_default(),
            )
        }
        Err(e) => erro(e.into(), &env),
    }
}

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
/// P5 — a linha do tempo do atendimento.
#[tracing::instrument(skip_all, fields(rpc = "ListarTimelineAtendimento", tenant_id = %env.tenant_id))]
async fn handler_listar_timeline(store: &dyn ports::AtendimentoStore, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
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
    match store.listar_timeline(&ctx, atendimento_id).await {
        Ok(eventos) => {
            let itens: Vec<serde_json::Value> = eventos
                .into_iter()
                .map(|e| {
                    serde_json::json!({
                        "tipo": e.tipo,
                        "quando": e.quando.timestamp_millis(),
                        // A descrição pode conter texto de nota (conteúdo do
                        // cliente): vai no payload, nunca no log.
                        "descricao": e.descricao,
                        "autor": e.autor.unwrap_or_default(),
                        "automatico": e.automatico,
                    })
                })
                .collect();
            ok_reply(
                &env,
                "ListarTimelineAtendimentoReply",
                serde_json::json!({ "eventos": itens }),
            )
        }
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// P5 — as outras conversas do mesmo contato.
#[tracing::instrument(skip_all, fields(rpc = "ListarAtendimentosDoContato", tenant_id = %env.tenant_id))]
async fn handler_listar_atendimentos_do_contato(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let contato_id = match payload_json.get("contato_id").and_then(|v| v.as_i64()) {
        Some(id) => id as i32,
        None => {
            return erro(
                error_core::AppError::Validation("contato_id ausente".into()),
                &env,
            )
        }
    };
    let limit = payload_json
        .get("limit")
        .and_then(|v| v.as_i64())
        .filter(|v| *v > 0)
        .unwrap_or(20);

    let ctx = contexto_do_envelope(&env);
    match store.listar_do_contato(&ctx, contato_id, limit).await {
        Ok(itens) => ok_reply(
            &env,
            "ListarAtendimentosDoContatoReply",
            serde_json::json!({ "atendimentos": itens }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// P5 — apaga uma nota interna.
#[tracing::instrument(skip_all, fields(rpc = "RemoverNota", tenant_id = %env.tenant_id))]
async fn handler_remover_nota(store: &dyn ports::AtendimentoStore, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let nota_id = payload_json.get("nota_id").and_then(|v| v.as_i64());
    let atendimento_id = payload_json
        .get("atendimento_id")
        .and_then(|v| v.as_i64())
        .map(|v| v as i32);
    let (Some(nota_id), Some(atendimento_id)) = (nota_id, atendimento_id) else {
        return erro(
            error_core::AppError::Validation("nota_id e atendimento_id são obrigatórios".into()),
            &env,
        );
    };

    let ctx = contexto_do_envelope(&env);
    match store.remover_nota(&ctx, nota_id, atendimento_id).await {
        Ok(removida) => ok_reply(
            &env,
            "RemoverNotaReply",
            serde_json::json!({ "ok": removida }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// P5 — renomeia/recolore uma etiqueta do catálogo.
#[tracing::instrument(skip_all, fields(rpc = "UpdateEtiqueta", tenant_id = %env.tenant_id))]
async fn handler_update_etiqueta(store: &dyn ports::AtendimentoStore, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let id = match payload_json.get("id").and_then(|v| v.as_i64()) {
        Some(id) => id,
        None => return erro(error_core::AppError::Validation("id ausente".into()), &env),
    };
    let texto = |chave: &str| {
        payload_json
            .get(chave)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .trim()
            .to_string()
    };
    let nome = texto("nome");
    if nome.is_empty() {
        return erro(
            error_core::AppError::Validation("a etiqueta precisa de um nome".into()),
            &env,
        );
    }
    let cor = texto("cor");
    let cor = if cor.is_empty() {
        "#a98f71".to_string()
    } else {
        cor
    };

    let ctx = contexto_do_envelope(&env);
    match store
        .atualizar_etiqueta(&ctx, id, &nome, &cor, &texto("descricao"))
        .await
    {
        Ok(Some(e)) => ok_reply(
            &env,
            "UpdateEtiquetaReply",
            serde_json::json!({
                "id": e.id, "nome": e.nome, "cor": e.cor,
                "descricao": e.descricao, "ativo": e.ativo,
            }),
        ),
        // Não existe (ou é de outro tenant): validação, não falha de banco.
        Ok(None) => erro(
            error_core::AppError::Validation("etiqueta não encontrada".into()),
            &env,
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// P5 — desativa a etiqueta no catálogo.
#[tracing::instrument(skip_all, fields(rpc = "DesativarEtiqueta", tenant_id = %env.tenant_id))]
async fn handler_desativar_etiqueta(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let id = match payload_json.get("id").and_then(|v| v.as_i64()) {
        Some(id) => id,
        None => return erro(error_core::AppError::Validation("id ausente".into()), &env),
    };

    let ctx = contexto_do_envelope(&env);
    match store.desativar_etiqueta(&ctx, id).await {
        Ok(ok) => ok_reply(
            &env,
            "DesativarEtiquetaReply",
            serde_json::json!({ "ok": ok }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// P4 — o quadro em CSV.
///
/// Sai com nome e telefone de cliente: é exportação de PII em massa, e por isso
/// é auditada com a contagem de linhas — a auditoria registra que saiu e
/// quanto saiu, nunca o conteúdo.
#[tracing::instrument(skip_all, fields(rpc = "ExportarQuadro", tenant_id = %env.tenant_id))]
async fn handler_exportar_quadro(
    store: &dyn ports::AtendimentoStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let departamento_id = payload_json
        .get("departamento_id")
        .and_then(|v| v.as_i64())
        .filter(|v| *v > 0)
        .map(|v| v as i32);
    let filtro = infrastructure_postgres::atendimentos::atendimentos::FiltroDoQuadro {
        busca: payload_json
            .get("busca")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .trim()
            .to_string(),
        atendente_id: None,
        somente_nao_lidos: payload_json
            .get("somente_nao_lidos")
            .and_then(|v| v.as_bool())
            .unwrap_or(false),
        prioridade: String::new(),
        etiqueta_id: None,
        somente_meus: payload_json
            .get("somente_meus")
            .and_then(|v| v.as_bool())
            .unwrap_or(false),
    };

    let ctx = contexto_do_envelope(&env);
    // Teto alto o bastante para a operação de um dia e baixo o bastante para a
    // exportação não virar um dump do banco inteiro.
    match store
        .exportar_quadro(&ctx, departamento_id, filtro, 5000)
        .await
    {
        Ok(linhas) => {
            let mut csv = String::from(
                "id;contato;telefone;assunto;status;prioridade;atendente;fluxo;etapa;                 aberto_em;ultima_mensagem;nao_lidas\n",
            );
            for l in &linhas {
                csv.push_str(&format!(
                    "{};{};{};{};{};{};{};{};{};{};{};{}\n",
                    l.id,
                    campo_csv(l.contato.as_deref()),
                    campo_csv(l.telefone.as_deref()),
                    campo_csv(l.assunto.as_deref()),
                    campo_csv(Some(&l.status)),
                    campo_csv(Some(&l.prioridade)),
                    campo_csv(l.atendente.as_deref()),
                    campo_csv(l.fluxo.as_deref()),
                    campo_csv(l.etapa.as_deref()),
                    l.data_inicio.to_rfc3339(),
                    l.data_ultima_mensagem
                        .map(|d| d.to_rfc3339())
                        .unwrap_or_default(),
                    l.nao_lidas,
                ));
            }
            audit
                .publish(
                    &env,
                    "atendimento.quadro_exportado",
                    format!("Quadro exportado: {} conversas", linhas.len()),
                    serde_json::json!({ "linhas": linhas.len() }),
                )
                .await;
            ok_reply(
                &env,
                "ExportarQuadroReply",
                serde_json::json!({ "csv": csv, "linhas": linhas.len() }),
            )
        }
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// Escapa um campo do CSV: o separador é `;` e o conteúdo é texto de cliente,
/// que tem ponto e vírgula, aspas e quebra de linha à vontade.
fn campo_csv(valor: Option<&str>) -> String {
    let bruto = valor.unwrap_or_default();
    if bruto.contains([';', '"', '\n', '\r']) {
        format!("\"{}\"", bruto.replace('"', "\"\""))
    } else {
        bruto.to_string()
    }
}

/// P4 — define (ou tira) o dono da conversa.
///
/// A atribuição é auditada: saber quem pôs uma conversa na mão de quem é o que
/// permite explicar, depois, por que um cliente ficou esperando.
#[tracing::instrument(skip_all, fields(rpc = "AtribuirAtendimento", tenant_id = %env.tenant_id))]
async fn handler_atribuir_atendimento(
    store: &dyn ports::AtendimentoStore,
    audit: &dyn ports::AuditPort,
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
    let devolver = payload_json
        .get("devolver_para_fila")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    let ctx = contexto_do_envelope(&env);
    let alvo = if devolver {
        None
    } else {
        match payload_json
            .get("atendente_id")
            .and_then(|v| v.as_i64())
            .filter(|v| *v > 0)
        {
            Some(id) => Some(id as i32),
            // Sem atendente explícito, é "atribuir a mim".
            None => match store.atendente_do_usuario(&ctx).await {
                Ok(Some(id)) => Some(id),
                Ok(None) => {
                    return erro(
                        error_core::AppError::Validation(
                            "seu usuário não está cadastrado como atendente".into(),
                        ),
                        &env,
                    )
                }
                Err(e) => return erro(error_core::AppError::Database(e.to_string()), &env),
            },
        }
    };

    match store.atribuir_atendimento(&ctx, atendimento_id, alvo).await {
        Ok(atribuido) => {
            audit
                .publish(
                    &env,
                    if devolver {
                        "atendimento.devolvido_para_fila"
                    } else {
                        "atendimento.atribuido"
                    },
                    format!("Atendimento {atendimento_id}: dono alterado"),
                    serde_json::json!({
                        "atendimento_id": atendimento_id,
                        "atendente_id": alvo,
                        "aplicado": atribuido,
                    }),
                )
                .await;
            ok_reply(
                &env,
                "AtribuirAtendimentoReply",
                serde_json::json!({
                    "atribuido": atribuido,
                    "motivo": if atribuido { "" } else { "a conversa já tem outro atendente" },
                }),
            )
        }
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// P4 — urgência do cartão.
#[tracing::instrument(skip_all, fields(rpc = "DefinirPrioridade", tenant_id = %env.tenant_id))]
async fn handler_definir_prioridade(
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
    let prioridade = payload_json
        .get("prioridade")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .trim()
        .to_lowercase();
    if !infrastructure_postgres::atendimentos::atendimentos::PRIORIDADES
        .contains(&prioridade.as_str())
    {
        return erro(
            error_core::AppError::Validation(format!("prioridade '{prioridade}' inválida")),
            &env,
        );
    }

    let ctx = contexto_do_envelope(&env);
    match store
        .definir_prioridade(&ctx, atendimento_id, &prioridade)
        .await
    {
        Ok(definida) => ok_reply(
            &env,
            "DefinirPrioridadeReply",
            serde_json::json!({ "definida": definida }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// P3 — o atendimento ativo de um telefone, para casar a presença que chega.
#[tracing::instrument(skip_all, fields(rpc = "BuscarAtendimentoAtivoPorTelefone", tenant_id = %env.tenant_id))]
async fn handler_buscar_atendimento_ativo_por_telefone(
    store: &dyn ports::AtendimentoStore,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    // O telefone é PII: entra no payload, nunca no span nem no log.
    let telefone = payload_json
        .get("telefone")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .trim()
        .to_string();
    if telefone.is_empty() {
        return erro(
            error_core::AppError::Validation("telefone ausente".into()),
            &env,
        );
    }

    let ctx = contexto_do_envelope(&env);
    match store
        .buscar_atendimento_ativo_por_telefone(&ctx, &telefone)
        .await
    {
        Ok(id) => ok_reply(
            &env,
            "BuscarAtendimentoAtivoPorTelefoneReply",
            serde_json::json!({ "atendimento_id": id }),
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

/// P3 — para onde mandar a presença do atendente nesta conversa.
#[tracing::instrument(skip_all, fields(rpc = "ResolverDestinoDoAtendimento", tenant_id = %env.tenant_id))]
async fn handler_resolver_destino_do_atendimento(
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
        .resolver_destino_do_atendimento(&ctx, atendimento_id)
        .await
    {
        Ok(Some((instance_id, telefone))) => ok_reply(
            &env,
            "ResolverDestinoDoAtendimentoReply",
            serde_json::json!({ "instance_id": instance_id, "to_number": telefone }),
        ),
        // Sem conexão ativa para o contato: quem chama decide o que fazer.
        Ok(None) => ok_reply(
            &env,
            "ResolverDestinoDoAtendimentoReply",
            serde_json::json!({}),
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

async fn handler_resolver_destino_envio_outbound(
    store: &dyn ports::AtendimentoStore,
    audit: &dyn ports::AuditPort,
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
        // N7.2: "dead_letter_novo" é o marcador interno de que ESTA chamada
        // acabou de registrar o dead-letter (repo já persistiu "dead_letter" na
        // mensagem) — só aqui publica o evento de auditoria (sem conteúdo/PII,
        // só ids e motivo); reentregas futuras vêm com "dead_letter" já
        // persistido e não reauditam. Normaliza o valor devolvido ao worker.
        Ok(Some(mut destino)) if destino.status_envio == "dead_letter_novo" => {
            destino.status_envio = "dead_letter".to_string();
            audit
                .publish(
                    &env,
                    "mensagem.dead_letter",
                    "Mensagem outbound sem destino resolvível; movida para dead-letter".to_string(),
                    serde_json::json!({
                        "atendimento_id": destino.atendimento_id,
                        "mensagem_id": mensagem_id,
                        "motivo": "sem_whatsapp_contact_ativo",
                    }),
                )
                .await;
            ok_reply(
                &env,
                "ResolverDestinoEnvioOutboundReply",
                serde_json::to_value(&destino).unwrap_or_default(),
            )
        }
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

/// Reprocessamento manual de um dead-letter de outbound (N7.2): RPC
/// administrativo simples, sob demanda do operador — sem harness automatizado.
async fn handler_reprocessar_dead_letter(
    store: &dyn ports::AtendimentoStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let dead_letter_id = match payload_json.get("dead_letter_id").and_then(|v| v.as_i64()) {
        Some(id) => id as i32,
        None => {
            return erro(
                error_core::AppError::Validation("dead_letter_id ausente".into()),
                &env,
            )
        }
    };

    let ctx = contexto_do_envelope(&env);
    match store
        .reprocessar_dead_letter(&ctx, dead_letter_id, &env.traceparent)
        .await
    {
        Ok(status) => {
            // Reinjeta no fluxo uma mensagem que já falhou: pode gerar envio ao
            // cliente. Operação manual e de efeito visível externamente, então
            // precisa dizer quem mandou reprocessar o quê.
            audit
                .publish(
                    &env,
                    "dead_letter_reprocessada",
                    format!("Dead-letter {dead_letter_id} reenviada para processamento"),
                    serde_json::json!({
                        "dead_letter_id": dead_letter_id,
                        "status": status,
                    }),
                )
                .await;
            ok_reply(
                &env,
                "ReprocessarDeadLetterReply",
                serde_json::json!({ "status": status }),
            )
        }
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

async fn handler_upsert_contact(
    store: &dyn ports::ClienteStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
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
        Ok(contato) => {
            // Cria ou altera dado pessoal de terceiro (nome e telefone de quem
            // conversa com o tenant). Era a única escrita desse tipo sem rastro.
            // O telefone NÃO vai no contexto: o evento registra que houve
            // gravação, não republica o dado que a LGPD quer proteger.
            audit
                .publish(
                    &env,
                    "contato_gravado",
                    "Contato criado ou atualizado".to_string(),
                    serde_json::json!({ "nome_informado": nome_foi_informado(&payload_json) }),
                )
                .await;
            ok_reply(
                &env,
                "UpsertContactReply",
                serde_json::to_value(&contato).unwrap_or_default(),
            )
        }
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

/// Se o chamador mandou um nome junto. Basta saber que veio: o valor em si é
/// dado pessoal e não precisa ser repetido no log de auditoria.
fn nome_foi_informado(payload: &serde_json::Value) -> bool {
    payload
        .get("name")
        .and_then(|v| v.as_str())
        .is_some_and(|s| !s.trim().is_empty())
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

        // VerifyCredentials é chamada por application::auth::login::login() ANTES do
        // tenant ser resolvido — env.tenant_id aqui é sempre o Uuid nulo. Sem o
        // .filter, Some(Uuid::nil()) violava audit_log_tenant_id_fkey e TODA
        // tentativa de login com credencial inválida perdia o próprio evento de
        // auditoria que deveria registrá-la (achado ao auditar o sistema de logs).
        let tenant_id = Uuid::parse_str(&env.tenant_id)
            .ok()
            .filter(|id| !id.is_nil());
        audit
            .publish_security(
                &env.traceparent,
                tenant_id,
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

// --- Departamentos e atendentes (estrutura do atendimento) ---
//
// Sem departamento a fila não tem para onde mandar conversa: o onboarding cria
// o primeiro e, até aqui, não havia como criar outro nem corrigir aquele.

#[tracing::instrument(skip_all, fields(rpc = "ListDepartamentos", tenant_id = %env.tenant_id))]
async fn handler_list_departamentos(
    store: &dyn ports::OperacionalStore,
    env: Envelope,
) -> Envelope {
    let ctx = contexto_do_envelope(&env);
    match store.listar_departamentos(&ctx).await {
        Ok(itens) => ok_reply(
            &env,
            "ListDepartamentosReply",
            serde_json::json!({ "departamentos": itens }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "UpdateDepartamento", tenant_id = %env.tenant_id))]
async fn handler_update_departamento(
    store: &dyn ports::OperacionalStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id = payload.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
    let nome = payload
        .get("nome")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .trim()
        .to_string();
    let descricao = payload
        .get("descricao")
        .and_then(|v| v.as_str())
        .map(str::to_string);
    let ativo = payload
        .get("ativo")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);

    if nome.is_empty() {
        return erro(
            error_core::AppError::Validation("informe o nome do departamento".into()),
            &env,
        );
    }

    let ctx = contexto_do_envelope(&env);
    match store
        .atualizar_departamento(&ctx, id, nome.clone(), descricao, ativo)
        .await
    {
        Ok(true) => {
            audit
                .publish(
                    &env,
                    "departamento_atualizado",
                    format!("Departamento '{nome}' atualizado"),
                    serde_json::json!({ "id": id, "ativo": ativo }),
                )
                .await;
            ok_reply(
                &env,
                "UpdateDepartamentoReply",
                serde_json::json!({ "sucesso": true }),
            )
        }
        Ok(false) => erro(
            error_core::AppError::Validation("departamento não encontrado".into()),
            &env,
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "DesativarDepartamento", tenant_id = %env.tenant_id))]
async fn handler_desativar_departamento(
    store: &dyn ports::OperacionalStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id = payload.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;

    let ctx = contexto_do_envelope(&env);
    match store.desativar_departamento(&ctx, id).await {
        Ok(true) => {
            audit
                .publish(
                    &env,
                    "departamento_desativado",
                    format!("Departamento {id} desativado"),
                    serde_json::json!({ "id": id }),
                )
                .await;
            ok_reply(
                &env,
                "DesativarDepartamentoReply",
                serde_json::json!({ "sucesso": true }),
            )
        }
        Ok(false) => erro(
            error_core::AppError::Validation("departamento não encontrado".into()),
            &env,
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "ListContatos", tenant_id = %env.tenant_id))]
async fn handler_list_contatos(store: &dyn ports::ClienteStore, env: Envelope) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let busca = payload
        .get("busca")
        .and_then(|v| v.as_str())
        .map(str::trim)
        // Busca vazia é "sem filtro", não "procure por string vazia" — que
        // casaria com tudo de qualquer forma, mas por acidente.
        .filter(|s| !s.is_empty())
        .map(str::to_string);
    let limite = payload.get("limite").and_then(|v| v.as_i64()).unwrap_or(50);

    let ctx = contexto_do_envelope(&env);
    match store.listar_contatos(&ctx, busca, limite).await {
        Ok(itens) => ok_reply(
            &env,
            "ListContatosReply",
            serde_json::json!({ "contatos": itens }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

// --- C4: o cadastro de contatos deixa de depender de alguém escrever -----
//
// Até aqui um contato só existia porque mandou mensagem. O operador que
// conhece o cliente por telefone não tinha como registrá-lo — e sem contato
// cadastrado, o "iniciar atendimento" do C3 não achava ninguém para escolher.

/// Põe o telefone digitado no mesmo formato em que a ingestão o grava.
///
/// O webhook deriva o número do JID (`5511999998888@s.whatsapp.net`): só
/// dígitos, com DDI, sem `+`. Um contato cadastrado à mão como
/// "(11) 99999-8888" ficaria numa linha diferente do mesmo telefone que chega
/// pelo WhatsApp — dois cadastros para uma pessoa, e a conversa aberta à mão
/// não receberia as respostas dela.
///
/// `None` quando o que sobrou não pode ser um telefone.
fn normalizar_telefone(bruto: &str) -> Option<String> {
    let digitos: String = bruto.chars().filter(char::is_ascii_digit).collect();

    match digitos.len() {
        // Formato nacional (DDD + 8 ou 9 dígitos): assume Brasil. É a mesma
        // suposição da v1, e a única possível — quem digita "11 99999-8888"
        // não está informando país nenhum.
        10 | 11 => Some(format!("55{digitos}")),
        // Já veio com DDI. Não se toca: prefixar de novo criaria um número que
        // não existe.
        12..=15 => Some(digitos),
        _ => None,
    }
}

/// Aceita e-mail vazio como "não informado" e recusa o que não é e-mail.
///
/// A conferência é frouxa de propósito — regra estrita erra em endereços
/// válidos e o campo é opcional. O que ela pega é o engano óbvio: texto sem
/// arroba, que quase sempre é um nome digitado na linha errada.
fn conferir_email(bruto: &str) -> Result<Option<String>, String> {
    let e = bruto.trim();
    if e.is_empty() {
        return Ok(None);
    }
    if !e.contains('@') || e.starts_with('@') || e.ends_with('@') {
        return Err("o e-mail informado não parece um endereço".into());
    }
    Ok(Some(e.to_string()))
}

#[tracing::instrument(skip_all, fields(rpc = "CreateContato", tenant_id = %env.tenant_id))]
async fn handler_create_contato(
    store: &dyn ports::ClienteStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let texto = |chave: &str| {
        payload
            .get(chave)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .trim()
            .to_string()
    };

    let Some(telefone) = normalizar_telefone(&texto("telefone")) else {
        return erro(
            error_core::AppError::Validation(
                "informe um telefone com DDD, por exemplo 11 99999-8888".into(),
            ),
            &env,
        );
    };
    let email = match conferir_email(&texto("email")) {
        Ok(e) => e,
        Err(msg) => return erro(error_core::AppError::Validation(msg), &env),
    };
    let nome = Some(texto("nome_contato")).filter(|s| !s.is_empty());

    let ctx = contexto_do_envelope(&env);
    match store
        .criar_contato(&ctx, telefone, nome.clone(), email)
        .await
    {
        Ok(contato) => {
            // Dado pessoal de terceiro: o evento registra que houve cadastro,
            // não o telefone — mesmo cuidado do `contato_gravado`.
            audit
                .publish(
                    &env,
                    "contato_cadastrado",
                    "Contato cadastrado manualmente".to_string(),
                    serde_json::json!({
                        "id": contato.id,
                        "nome_informado": nome.is_some(),
                    }),
                )
                .await;
            ok_reply(
                &env,
                "CreateContatoReply",
                serde_json::to_value(&contato).unwrap_or_default(),
            )
        }
        // O unique (tenant_id, telefone) vira Conflict, e a tela diz o que
        // houve: o contato já existe e está na lista.
        Err(infrastructure_postgres::DbError::UniqueViolation(_)) => erro(
            error_core::AppError::Conflict(
                "já existe um contato com este telefone — procure por ele na lista".into(),
            ),
            &env,
        ),
        Err(e) => erro(e.into(), &env),
    }
}

/// B10 (N11 E5) — lê e confere os campos de um cliente.
///
/// Documento vira só dígitos e precisa ter o tamanho certo (CNPJ 14, CPF 11);
/// UF vira maiúscula de duas letras; CEP, oito dígitos. Nada disso vai para log:
/// CNPJ/CPF e endereço são dado protegido.
fn dados_do_cliente(
    payload: &serde_json::Value,
) -> Result<infrastructure_postgres::clientes::clientes::DadosCliente, String> {
    let texto = |chave: &str| {
        payload
            .get(chave)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .trim()
            .to_string()
    };
    let opcional = |chave: &str, limite: usize, rotulo: &str| -> Result<Option<String>, String> {
        let valor = texto(chave);
        if valor.is_empty() {
            return Ok(None);
        }
        if valor.chars().count() > limite {
            return Err(format!("{rotulo}: no máximo {limite} caracteres"));
        }
        Ok(Some(valor))
    };
    let digitos = |chave: &str, tamanho: usize, rotulo: &str| -> Result<Option<String>, String> {
        let so_digitos: String = texto(chave)
            .chars()
            .filter(|c| c.is_ascii_digit())
            .collect();
        match so_digitos.len() {
            0 => Ok(None),
            n if n == tamanho => Ok(Some(so_digitos)),
            _ => Err(format!("{rotulo} precisa ter {tamanho} dígitos")),
        }
    };

    let nome_fantasia = texto("nome_fantasia");
    if nome_fantasia.is_empty() {
        return Err("informe o nome do cliente".into());
    }
    if nome_fantasia.chars().count() > 200 {
        return Err("nome: no máximo 200 caracteres".into());
    }
    let tipo = match texto("tipo").to_ascii_lowercase().as_str() {
        "" => None,
        t @ ("pj" | "pf") => Some(t.to_string()),
        _ => return Err("tipo deve ser pessoa jurídica (pj) ou física (pf)".into()),
    };
    let uf = match texto("uf").to_ascii_uppercase() {
        u if u.is_empty() => None,
        u if u.len() == 2 && u.chars().all(|c| c.is_ascii_alphabetic()) => Some(u),
        _ => return Err("UF deve ter duas letras".into()),
    };

    Ok(infrastructure_postgres::clientes::clientes::DadosCliente {
        nome_fantasia,
        razao_social: opcional("razao_social", 200, "razão social")?,
        tipo,
        cnpj: digitos("cnpj", 14, "CNPJ")?,
        cpf: digitos("cpf", 11, "CPF")?,
        telefone: opcional("telefone", 20, "telefone")?,
        site: opcional("site", 200, "site")?,
        ramo_atividade: opcional("ramo_atividade", 200, "ramo de atividade")?,
        observacoes: opcional("observacoes", 5000, "observações")?,
        cep: digitos("cep", 8, "CEP")?,
        logradouro: opcional("logradouro", 200, "logradouro")?,
        numero: opcional("numero", 10, "número")?,
        complemento: opcional("complemento", 100, "complemento")?,
        bairro: opcional("bairro", 100, "bairro")?,
        cidade: opcional("cidade", 100, "cidade")?,
        uf,
    })
}

#[tracing::instrument(skip_all, fields(rpc = "ListClientes", tenant_id = %env.tenant_id))]
async fn handler_list_clientes(store: &dyn ports::ClienteStore, env: Envelope) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let busca = payload
        .get("busca")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_string();
    let incluir_inativos = payload
        .get("incluir_inativos")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let limite = payload.get("limite").and_then(|v| v.as_i64()).unwrap_or(50);
    let ctx = contexto_do_envelope(&env);
    match store
        .listar_clientes(&ctx, busca, incluir_inativos, limite)
        .await
    {
        Ok(itens) => ok_reply(
            &env,
            "ListClientesReply",
            serde_json::json!({ "clientes": itens }),
        ),
        Err(e) => erro(e.into(), &env),
    }
}

/// Auditado (`cliente.criado`) só com o id e o tipo: nome, documento e endereço
/// são dado protegido.
#[tracing::instrument(skip_all, fields(rpc = "CreateCliente", tenant_id = %env.tenant_id))]
async fn handler_create_cliente(
    store: &dyn ports::ClienteStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let dados = match dados_do_cliente(&payload) {
        Ok(d) => d,
        Err(msg) => return erro(error_core::AppError::Validation(msg), &env),
    };
    let ctx = contexto_do_envelope(&env);
    match store.criar_cliente(&ctx, dados).await {
        Ok(cliente) => {
            audit
                .publish(
                    &env,
                    "cliente.criado",
                    "Cliente cadastrado".to_string(),
                    serde_json::json!({ "id": cliente.id, "tipo": cliente.tipo }),
                )
                .await;
            ok_reply(&env, "CreateClienteReply", serde_json::json!(cliente))
        }
        Err(e) => erro(e.into(), &env),
    }
}

/// Auditado (`cliente.alterado`) com os **campos** que mudaram — o valor, nunca.
#[tracing::instrument(skip_all, fields(rpc = "UpdateCliente", tenant_id = %env.tenant_id))]
async fn handler_update_cliente(
    store: &dyn ports::ClienteStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id = payload.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
    if id <= 0 {
        return erro(
            error_core::AppError::Validation("cliente não informado".into()),
            &env,
        );
    }
    let dados = match dados_do_cliente(&payload) {
        Ok(d) => d,
        Err(msg) => return erro(error_core::AppError::Validation(msg), &env),
    };
    let ctx = contexto_do_envelope(&env);
    match store.atualizar_cliente(&ctx, id, dados).await {
        Ok(Some(campos)) => {
            if !campos.is_empty() {
                audit
                    .publish(
                        &env,
                        "cliente.alterado",
                        format!("Cliente {id} alterado"),
                        serde_json::json!({ "id": id, "campos": campos }),
                    )
                    .await;
            }
            ok_reply(
                &env,
                "UpdateClienteReply",
                serde_json::json!({ "sucesso": true }),
            )
        }
        Ok(None) => erro(
            error_core::AppError::Validation("cliente não encontrado".into()),
            &env,
        ),
        Err(e) => erro(e.into(), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "DefinirClienteAtivo", tenant_id = %env.tenant_id))]
async fn handler_definir_cliente_ativo(
    store: &dyn ports::ClienteStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id = payload.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
    let ativo = payload
        .get("ativo")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    if id <= 0 {
        return erro(
            error_core::AppError::Validation("cliente não informado".into()),
            &env,
        );
    }
    let ctx = contexto_do_envelope(&env);
    match store.definir_cliente_ativo(&ctx, id, ativo).await {
        Ok(true) => {
            let evento = if ativo {
                "cliente.reativado"
            } else {
                "cliente.desativado"
            };
            audit
                .publish(
                    &env,
                    evento,
                    format!(
                        "Cliente {id} {}",
                        if ativo { "reativado" } else { "desativado" }
                    ),
                    serde_json::json!({ "id": id, "ativo": ativo }),
                )
                .await;
            ok_reply(
                &env,
                "DefinirClienteAtivoReply",
                serde_json::json!({ "sucesso": true }),
            )
        }
        Ok(false) => erro(
            error_core::AppError::Validation("cliente não encontrado".into()),
            &env,
        ),
        Err(e) => erro(e.into(), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "ListContatosDoCliente", tenant_id = %env.tenant_id))]
async fn handler_list_contatos_do_cliente(
    store: &dyn ports::ClienteStore,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id = payload.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
    let ctx = contexto_do_envelope(&env);
    match store.contatos_do_cliente(&ctx, id).await {
        Ok(itens) => ok_reply(
            &env,
            "ListContatosDoClienteReply",
            serde_json::json!({ "contatos": itens }),
        ),
        Err(e) => erro(e.into(), &env),
    }
}

/// Auditado (`contato.vinculado_cliente` / `.desvinculado_cliente`) com os dois
/// ids.
#[tracing::instrument(skip_all, fields(rpc = "VincularContatoCliente", tenant_id = %env.tenant_id))]
async fn handler_vincular_contato_cliente(
    store: &dyn ports::ClienteStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let cliente_id = payload
        .get("cliente_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;
    let contato_id = payload
        .get("contato_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;
    let vincular = payload
        .get("vincular")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);
    if cliente_id <= 0 || contato_id <= 0 {
        return erro(
            error_core::AppError::Validation("informe o cliente e o contato".into()),
            &env,
        );
    }
    let ctx = contexto_do_envelope(&env);
    match store
        .vincular_contato_cliente(&ctx, cliente_id, contato_id, vincular)
        .await
    {
        Ok(true) => {
            let evento = if vincular {
                "contato.vinculado_cliente"
            } else {
                "contato.desvinculado_cliente"
            };
            audit
                .publish(
                    &env,
                    evento,
                    format!(
                        "Contato {contato_id} {} cliente {cliente_id}",
                        if vincular {
                            "ligado ao"
                        } else {
                            "desligado do"
                        }
                    ),
                    serde_json::json!({ "cliente_id": cliente_id, "contato_id": contato_id }),
                )
                .await;
            ok_reply(
                &env,
                "VincularContatoClienteReply",
                serde_json::json!({ "sucesso": true }),
            )
        }
        Ok(false) => erro(
            error_core::AppError::Validation("cliente ou contato não encontrado".into()),
            &env,
        ),
        Err(e) => erro(e.into(), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "UpdateContato", tenant_id = %env.tenant_id))]
async fn handler_update_contato(
    store: &dyn ports::ClienteStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id = payload.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
    if id <= 0 {
        return erro(
            error_core::AppError::Validation("contato não informado".into()),
            &env,
        );
    }

    let texto = |chave: &str| {
        payload
            .get(chave)
            .and_then(|v| v.as_str())
            .map(|s| s.trim().to_string())
    };

    // Campo ausente é "não mexe". É isso que preserva o número de quem já tem
    // conversa sem a tela precisar conhecer a regra.
    let mut edicao = infrastructure_postgres::clientes::contatos::EdicaoContato {
        nome_contato: texto("nome_contato"),
        ..Default::default()
    };
    if let Some(bruto) = texto("email") {
        match conferir_email(&bruto) {
            // Vazio aqui é apagar o e-mail de propósito, e não "não mexe":
            // quem mandou o campo em branco quer limpá-lo.
            Ok(e) => edicao.email = Some(e.unwrap_or_default()),
            Err(msg) => return erro(error_core::AppError::Validation(msg), &env),
        }
    }
    if let Some(bruto) = texto("telefone").filter(|t| !t.is_empty()) {
        let Some(t) = normalizar_telefone(&bruto) else {
            return erro(
                error_core::AppError::Validation(
                    "informe um telefone com DDD, por exemplo 11 99999-8888".into(),
                ),
                &env,
            );
        };
        edicao.telefone = Some(t);
    }

    let ctx = contexto_do_envelope(&env);
    match store.atualizar_contato(&ctx, id, edicao).await {
        Ok(ports::DesfechoEdicaoContato::Atualizado) => {
            audit
                .publish(
                    &env,
                    "contato_editado",
                    format!("Contato {id} editado"),
                    serde_json::json!({ "id": id }),
                )
                .await;
            ok_reply(
                &env,
                "UpdateContatoReply",
                serde_json::json!({ "sucesso": true }),
            )
        }
        Ok(ports::DesfechoEdicaoContato::NaoEncontrado) => erro(
            error_core::AppError::Validation("contato não encontrado".into()),
            &env,
        ),
        Ok(ports::DesfechoEdicaoContato::TelefoneTravado { atendimentos }) => erro(
            error_core::AppError::Conflict(format!(
                "este contato já tem {atendimentos} conversa(s) no histórico. \
                 Trocar o telefone passaria essas mensagens para outra pessoa — \
                 cadastre o número novo como um contato à parte."
            )),
            &env,
        ),
        Err(infrastructure_postgres::DbError::UniqueViolation(_)) => erro(
            error_core::AppError::Conflict("já existe outro contato com este telefone".into()),
            &env,
        ),
        Err(e) => erro(e.into(), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "DefinirContatoAtivo", tenant_id = %env.tenant_id))]
async fn handler_definir_contato_ativo(
    store: &dyn ports::ClienteStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id = payload.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
    // Ausente = desativar. É a ação que a tela oferece; reativar é o caso raro
    // e manda o campo explicitamente.
    let ativo = payload
        .get("ativo")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    if id <= 0 {
        return erro(
            error_core::AppError::Validation("contato não informado".into()),
            &env,
        );
    }

    let ctx = contexto_do_envelope(&env);
    match store.definir_contato_ativo(&ctx, id, ativo).await {
        Ok(true) => {
            let acao = if ativo {
                "contato_reativado"
            } else {
                "contato_desativado"
            };
            audit
                .publish(
                    &env,
                    acao,
                    format!(
                        "Contato {id} {}",
                        if ativo { "reativado" } else { "desativado" }
                    ),
                    serde_json::json!({ "id": id, "ativo": ativo }),
                )
                .await;
            ok_reply(
                &env,
                "DefinirContatoAtivoReply",
                serde_json::json!({ "sucesso": true }),
            )
        }
        Ok(false) => erro(
            error_core::AppError::Validation("contato não encontrado".into()),
            &env,
        ),
        Err(e) => erro(e.into(), &env),
    }
}

// --- Fluxos de atendimento e suas etapas ---
//
// O fluxo é o quadro por onde a conversa anda; a etapa é a coluna. A camada de
// banco existia desde o começo (o roteamento já procura a etapa de entrada),
// mas nenhum RPC criava nada: todo tenant dependia de fluxo semeado à mão.

/// Vocabulário de `tipo_etapa`, herdado da v1 (`TipoEtapa`).
///
/// Não é enfeite: o roteamento procura `fila` para saber onde a conversa entra,
/// e a finalização fecha o atendimento. Um tipo inventado passaria pelo
/// `VARCHAR(20)` e sumiria da lógica sem erro nenhum.
const TIPOS_DE_ETAPA: [&str; 4] = ["fila", "trabalho", "espera", "finalizacao"];

// --- N9 E13: campos do cartão --------------------------------------------

/// Teto de campos ativos por tenant (N9 E13).
///
/// Todo campo com extração automática entra no prompt de **cada** mensagem: a
/// ficha cresce e o custo por conversa sobe junto, sem nada na tela dizendo
/// isso. 30 é bem mais do que qualquer ficha que uma pessoa consiga preencher,
/// e ainda assim um limite.
///
/// Conta os ativos: desativar um campo o tira do prompt e das fichas novas,
/// então ele deixa de custar — e essa é a saída de quem esbarra aqui.
const TETO_CAMPOS_ATIVOS: usize = 30;

/// O que impede um campo de nascer inútil.
///
/// Na borda, e não no adaptador: aqui existe `AppError::Validation`, e a
/// mensagem chega à tela dizendo o que corrigir. No adaptador viraria erro de
/// banco, que é outra coisa.
fn conferir_campo(p: &serde_json::Value, criando: bool) -> Result<(), String> {
    let texto = |k: &str| {
        p.get(k)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .trim()
            .to_string()
    };

    if texto("nome").is_empty() {
        return Err("o campo precisa de um nome".into());
    }
    // Nome só com pontuação não gera slug, e o slug é a identidade do campo —
    // é ele que vai gravado dentro de cada valor extraído.
    if !texto("nome").chars().any(|c| c.is_alphanumeric()) {
        return Err("o nome precisa ter ao menos uma letra ou número".into());
    }

    // Escopo e fluxo são a identidade do campo e só entram na criação; editar
    // não os move (ver `atualizar` no repositório).
    if criando && texto("escopo") == "FLUXO" && p.get("fluxo_id").and_then(|v| v.as_i64()).is_none()
    {
        return Err("campo de escopo FLUXO precisa dizer de qual quadro".into());
    }

    // Lista sem opções não é lista: quem preenche não teria o que escolher, e
    // a IA não teria contra o que validar o que extraiu.
    if texto("tipo") == "lista" {
        let vazia = p
            .get("opcoes")
            .and_then(|v| v.as_array())
            .is_none_or(|a| a.is_empty());
        if vazia {
            return Err("um campo de lista precisa de ao menos uma opção".into());
        }
    }

    Ok(())
}

#[tracing::instrument(skip_all, fields(rpc = "ListCamposPersonalizados", tenant_id = %env.tenant_id))]
async fn handler_list_campos(store: &dyn ports::OperacionalStore, env: Envelope) -> Envelope {
    let ctx = contexto_do_envelope(&env);
    match store.listar_campos(&ctx).await {
        Ok(itens) => ok_reply(
            &env,
            "ListCamposPersonalizadosReply",
            serde_json::json!({ "campos": itens }),
        ),
        Err(e) => erro(e.into(), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "CreateCampoPersonalizado", tenant_id = %env.tenant_id))]
async fn handler_create_campo(
    store: &dyn ports::OperacionalStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    if let Err(motivo) = conferir_campo(&payload, true) {
        return erro(error_core::AppError::Validation(motivo), &env);
    }

    let ctx = contexto_do_envelope(&env);

    // Reusa a listagem em vez de uma consulta de contagem: são no máximo
    // algumas dezenas de linhas, e uma query a mais no cache por causa de um
    // `COUNT` seria trocar clareza por nada. Falha ao listar não barra a
    // criação — o teto protege do crescimento silencioso, e negar o cadastro
    // por um erro de leitura seria um preço maior que o problema.
    if let Ok(existentes) = store.listar_campos(&ctx).await {
        let ativos = existentes
            .iter()
            .filter(|c| c.get("ativo").and_then(|v| v.as_bool()).unwrap_or(true))
            .count();
        if ativos >= TETO_CAMPOS_ATIVOS {
            return erro(
                error_core::AppError::Conflict(format!(
                    "Você já tem {ativos} campos ativos, que é o limite. Cada \
                     campo entra no que a IA lê em toda mensagem, então a conta \
                     sobe junto. Desative um que não use para abrir espaço."
                )),
                &env,
            );
        }
    }

    match store.criar_campo(&ctx, payload).await {
        Ok(campo) => {
            audit
                .publish(
                    &env,
                    "campo_personalizado.criado",
                    format!(
                        "Campo '{}' criado no cartão de atendimento",
                        campo.get("nome").and_then(|v| v.as_str()).unwrap_or("?")
                    ),
                    serde_json::json!({
                        "id": campo.get("id"),
                        "slug": campo.get("slug"),
                        "tipo": campo.get("tipo"),
                    }),
                )
                .await;
            ok_reply(
                &env,
                "CreateCampoPersonalizadoReply",
                serde_json::json!({ "campo": campo }),
            )
        }
        Err(e) => erro(e.into(), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "UpdateCampoPersonalizado", tenant_id = %env.tenant_id))]
async fn handler_update_campo(
    store: &dyn ports::OperacionalStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let id = match payload.get("id").and_then(|v| v.as_i64()) {
        Some(v) => v,
        None => return erro(error_core::AppError::Validation("id ausente".into()), &env),
    };
    if let Err(motivo) = conferir_campo(&payload, false) {
        return erro(error_core::AppError::Validation(motivo), &env);
    }

    let ctx = contexto_do_envelope(&env);
    match store.atualizar_campo(&ctx, id, payload).await {
        Ok(true) => {
            audit
                .publish(
                    &env,
                    "campo_personalizado.atualizado",
                    format!("Campo #{id} do cartão atualizado"),
                    serde_json::json!({ "id": id }),
                )
                .await;
            ok_reply(
                &env,
                "UpdateCampoPersonalizadoReply",
                serde_json::json!({ "sucesso": true }),
            )
        }
        Ok(false) => erro(
            error_core::AppError::Database("não encontrado: campo".into()),
            &env,
        ),
        Err(e) => erro(e.into(), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "DesativarCampoPersonalizado", tenant_id = %env.tenant_id))]
async fn handler_desativar_campo(
    store: &dyn ports::OperacionalStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id = match payload.get("id").and_then(|v| v.as_i64()) {
        Some(v) => v,
        None => return erro(error_core::AppError::Validation("id ausente".into()), &env),
    };
    let ctx = contexto_do_envelope(&env);
    match store.desativar_campo(&ctx, id).await {
        Ok(true) => {
            audit
                .publish(
                    &env,
                    "campo_personalizado.desativado",
                    format!("Campo #{id} do cartão desativado"),
                    serde_json::json!({ "id": id }),
                )
                .await;
            ok_reply(
                &env,
                "DesativarCampoPersonalizadoReply",
                serde_json::json!({ "sucesso": true }),
            )
        }
        Ok(false) => erro(
            error_core::AppError::Database("não encontrado: campo".into()),
            &env,
        ),
        Err(e) => erro(e.into(), &env),
    }
}

/// Preenchimento manual de um campo na ficha.
///
/// Sem auditoria de negócio: o valor é do atendimento e a ficha já registra
/// autor e horário. Auditar cada digitação encheria a trilha de segurança de
/// coisa que não é segurança — e o valor não pode ir para lá de qualquer
/// forma (é livre, pode ser CPF ou diagnóstico).
#[tracing::instrument(skip_all, fields(rpc = "SetValorCampo", tenant_id = %env.tenant_id))]
async fn handler_set_valor_campo(store: &dyn ports::OperacionalStore, env: Envelope) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let (Some(atendimento_id), Some(campo_id)) = (
        payload.get("atendimento_id").and_then(|v| v.as_i64()),
        payload.get("campo_id").and_then(|v| v.as_i64()),
    ) else {
        return erro(
            error_core::AppError::Validation("atendimento_id e campo_id são obrigatórios".into()),
            &env,
        );
    };
    // `valor` ausente é diferente de `null`: ausente é erro de chamada, `null`
    // é o apagamento deliberado que a IA precisa respeitar.
    let valor = match payload.get("valor") {
        Some(v) => v.clone(),
        None => {
            return erro(
                error_core::AppError::Validation("valor ausente".into()),
                &env,
            )
        }
    };

    let ctx = contexto_do_envelope(&env);
    match store
        .definir_valor_campo(&ctx, atendimento_id as i32, campo_id, valor)
        .await
    {
        Ok(_) => ok_reply(
            &env,
            "SetValorCampoReply",
            serde_json::json!({ "sucesso": true }),
        ),
        Err(e) => erro(e.into(), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "ListFluxos", tenant_id = %env.tenant_id))]
async fn handler_list_fluxos(store: &dyn ports::OperacionalStore, env: Envelope) -> Envelope {
    let ctx = contexto_do_envelope(&env);
    match store.listar_fluxos(&ctx).await {
        Ok(itens) => ok_reply(
            &env,
            "ListFluxosReply",
            serde_json::json!({"fluxos": itens}),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "CreateFluxo", tenant_id = %env.tenant_id))]
async fn handler_create_fluxo(
    quota: &dyn ports::QuotaStore,
    store: &dyn ports::OperacionalStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let departamento_id = payload
        .get("departamento_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;
    let nome = payload
        .get("nome")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .trim()
        .to_string();
    let descricao = payload
        .get("descricao")
        .and_then(|v| v.as_str())
        .map(str::to_string);

    if nome.is_empty() {
        return erro(
            error_core::AppError::Validation("informe o nome do fluxo".into()),
            &env,
        );
    }
    if departamento_id <= 0 {
        return erro(
            error_core::AppError::Validation("escolha o departamento do fluxo".into()),
            &env,
        );
    }

    let tenant_id = match Uuid::parse_str(&env.tenant_id) {
        Ok(u) => u,
        Err(_) => {
            return erro(
                error_core::AppError::Validation("tenant_id inválido".to_string()),
                &env,
            )
        }
    };

    // Mesmo desenho do `handler_create_departamento`: a quota é medida sempre e
    // só bloqueia com `SMARTCORE_QUOTA_ENFORCE=true`; falha de medição não
    // impede a criação (fail-open), porque quebrar o tenant por causa do
    // medidor seria pior que deixar passar um fluxo.
    match quota.verificar_quota(tenant_id, "fluxos").await {
        Ok(status) => {
            let excedido = status
                .get("excedido")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            if excedido {
                let enforce = std::env::var("SMARTCORE_QUOTA_ENFORCE")
                    .map(|v| v.eq_ignore_ascii_case("true"))
                    .unwrap_or(false);
                if enforce {
                    tracing::warn!(
                        tenant_id = %env.tenant_id,
                        "quota de fluxos excedida; bloqueando criação"
                    );
                    audit
                        .publish(
                            &env,
                            "quota.excedida",
                            "Quota de 'fluxos' excedida".to_string(),
                            status,
                        )
                        .await;
                    return erro(
                        error_core::AppError::RateLimit("quota de 'fluxos' excedida".to_string()),
                        &env,
                    );
                }
                tracing::warn!(
                    tenant_id = %env.tenant_id,
                    "quota de fluxos excedida (log-only; SMARTCORE_QUOTA_ENFORCE=false)"
                );
            }
        }
        Err(e) => {
            tracing::warn!(erro = %e, "falha ao verificar quota de fluxos; prosseguindo (fail-open)");
        }
    }

    let ctx = contexto_do_envelope(&env);
    match store
        .criar_fluxo(&ctx, departamento_id, nome.clone(), descricao)
        .await
    {
        Ok(fluxo) => {
            audit
                .publish(
                    &env,
                    "fluxo_criado",
                    format!("Fluxo '{nome}' criado"),
                    fluxo.clone(),
                )
                .await;
            ok_reply(&env, "CreateFluxoReply", fluxo)
        }
        Err(err) => erro(err.into(), &env),
    }
}

/// Traduz o `{sucesso, motivo}` do adapter em resposta ou recusa.
///
/// A recusa por regra de negócio vira `Validation`, não `Database`: ela é
/// explicável e o texto é para ser lido por quem opera.
///
/// `result_large_err` silenciado de propósito: os dois lados do `Result` são o
/// mesmo `Envelope` — é o tipo do protocolo, não um erro incidental. Boxar só o
/// `Err` deixaria a assinatura assimétrica sem ganho real.
#[allow(clippy::result_large_err)]
fn responder_resultado(
    env: &Envelope,
    reply: &str,
    resultado: serde_json::Value,
) -> Result<Envelope, Envelope> {
    let sucesso = resultado
        .get("sucesso")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    if sucesso {
        Ok(ok_reply(env, reply, resultado))
    } else {
        let motivo = resultado
            .get("motivo")
            .and_then(|v| v.as_str())
            .unwrap_or("operação recusada")
            .to_string();
        Err(erro(error_core::AppError::Validation(motivo), env))
    }
}

#[tracing::instrument(skip_all, fields(rpc = "UpdateFluxo", tenant_id = %env.tenant_id))]
async fn handler_update_fluxo(
    store: &dyn ports::OperacionalStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id = payload.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
    let nome = payload
        .get("nome")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .trim()
        .to_string();
    let descricao = payload
        .get("descricao")
        .and_then(|v| v.as_str())
        .map(str::to_string);
    let ativo = payload
        .get("ativo")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);

    if nome.is_empty() {
        return erro(
            error_core::AppError::Validation("informe o nome do fluxo".into()),
            &env,
        );
    }

    let ctx = contexto_do_envelope(&env);
    match store
        .atualizar_fluxo(&ctx, id, nome.clone(), descricao, ativo)
        .await
    {
        Ok(res) => match responder_resultado(&env, "UpdateFluxoReply", res) {
            Ok(resp) => {
                audit
                    .publish(
                        &env,
                        "fluxo_atualizado",
                        format!("Fluxo '{nome}' atualizado"),
                        serde_json::json!({ "id": id, "ativo": ativo }),
                    )
                    .await;
                resp
            }
            Err(recusa) => recusa,
        },
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "DesativarFluxo", tenant_id = %env.tenant_id))]
async fn handler_desativar_fluxo(
    store: &dyn ports::OperacionalStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id = payload.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;

    let ctx = contexto_do_envelope(&env);
    match store.desativar_fluxo(&ctx, id).await {
        Ok(res) => match responder_resultado(&env, "DesativarFluxoReply", res) {
            Ok(resp) => {
                audit
                    .publish(
                        &env,
                        "fluxo_desativado",
                        format!("Fluxo {id} desativado"),
                        serde_json::json!({ "id": id }),
                    )
                    .await;
                resp
            }
            Err(recusa) => recusa,
        },
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "ListEtapasFluxo", tenant_id = %env.tenant_id))]
async fn handler_list_etapas(store: &dyn ports::OperacionalStore, env: Envelope) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let fluxo_id = payload
        .get("fluxo_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;

    let ctx = contexto_do_envelope(&env);
    match store.listar_etapas(&ctx, fluxo_id).await {
        Ok(itens) => ok_reply(
            &env,
            "ListEtapasFluxoReply",
            serde_json::json!({ "etapas": itens }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "CreateEtapaFluxo", tenant_id = %env.tenant_id))]
async fn handler_create_etapa(
    store: &dyn ports::OperacionalStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let fluxo_id = payload
        .get("fluxo_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;
    let nome = payload
        .get("nome")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .trim()
        .to_string();
    let tipo_etapa = payload
        .get("tipo_etapa")
        .and_then(|v| v.as_str())
        .unwrap_or("trabalho")
        .to_string();
    let cor = payload
        .get("cor")
        .and_then(|v| v.as_str())
        .unwrap_or("#6B7280")
        .to_string();

    if nome.is_empty() {
        return erro(
            error_core::AppError::Validation("informe o nome da etapa".into()),
            &env,
        );
    }
    if !TIPOS_DE_ETAPA.contains(&tipo_etapa.as_str()) {
        return erro(
            error_core::AppError::Validation(format!("tipo de etapa desconhecido: '{tipo_etapa}'")),
            &env,
        );
    }

    let ctx = contexto_do_envelope(&env);
    match store
        .criar_etapa(&ctx, fluxo_id, nome.clone(), tipo_etapa, cor)
        .await
    {
        Ok(etapa) => {
            audit
                .publish(
                    &env,
                    "etapa_fluxo_criada",
                    format!("Etapa '{nome}' criada"),
                    etapa.clone(),
                )
                .await;
            ok_reply(&env, "CreateEtapaFluxoReply", etapa)
        }
        Err(err) => erro(err.into(), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "UpdateEtapaFluxo", tenant_id = %env.tenant_id))]
async fn handler_update_etapa(
    store: &dyn ports::OperacionalStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id = payload.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
    let nome = payload
        .get("nome")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .trim()
        .to_string();
    let descricao = payload
        .get("descricao")
        .and_then(|v| v.as_str())
        .map(str::to_string);
    let cor = payload
        .get("cor")
        .and_then(|v| v.as_str())
        .unwrap_or("#6B7280")
        .to_string();
    let tipo_etapa = payload
        .get("tipo_etapa")
        .and_then(|v| v.as_str())
        .unwrap_or("trabalho")
        .to_string();

    if nome.is_empty() {
        return erro(
            error_core::AppError::Validation("informe o nome da etapa".into()),
            &env,
        );
    }
    if !TIPOS_DE_ETAPA.contains(&tipo_etapa.as_str()) {
        return erro(
            error_core::AppError::Validation(format!("tipo de etapa desconhecido: '{tipo_etapa}'")),
            &env,
        );
    }

    let ctx = contexto_do_envelope(&env);
    match store
        .atualizar_etapa(&ctx, id, nome.clone(), descricao, cor, tipo_etapa)
        .await
    {
        Ok(true) => {
            audit
                .publish(
                    &env,
                    "etapa_fluxo_atualizada",
                    format!("Etapa '{nome}' atualizada"),
                    serde_json::json!({ "id": id }),
                )
                .await;
            ok_reply(
                &env,
                "UpdateEtapaFluxoReply",
                serde_json::json!({ "sucesso": true }),
            )
        }
        Ok(false) => erro(
            error_core::AppError::Validation("etapa não encontrada".into()),
            &env,
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "DesativarEtapaFluxo", tenant_id = %env.tenant_id))]
async fn handler_desativar_etapa(
    store: &dyn ports::OperacionalStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id = payload.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;

    let ctx = contexto_do_envelope(&env);
    match store.desativar_etapa(&ctx, id).await {
        Ok(res) => match responder_resultado(&env, "DesativarEtapaFluxoReply", res) {
            Ok(resp) => {
                audit
                    .publish(
                        &env,
                        "etapa_fluxo_removida",
                        format!("Etapa {id} removida"),
                        serde_json::json!({ "id": id }),
                    )
                    .await;
                resp
            }
            Err(recusa) => recusa,
        },
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "MoverEtapaFluxo", tenant_id = %env.tenant_id))]
async fn handler_mover_etapa(store: &dyn ports::OperacionalStore, env: Envelope) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id = payload.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
    let para_cima = payload
        .get("para_cima")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);

    let ctx = contexto_do_envelope(&env);
    match store.mover_etapa(&ctx, id, para_cima).await {
        // `false` é "já está na ponta", não erro: a tela só não muda.
        Ok(movida) => ok_reply(
            &env,
            "MoverEtapaFluxoReply",
            serde_json::json!({ "sucesso": movida }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "GetPainelTenant", tenant_id = %env.tenant_id))]
async fn handler_painel_tenant(store: &dyn ports::OperacionalStore, env: Envelope) -> Envelope {
    let ctx = contexto_do_envelope(&env);
    match store.painel_do_tenant(&ctx).await {
        Ok(painel) => ok_reply(&env, "GetPainelTenantReply", painel),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "ListAtendentes", tenant_id = %env.tenant_id))]
async fn handler_list_atendentes(store: &dyn ports::OperacionalStore, env: Envelope) -> Envelope {
    let ctx = contexto_do_envelope(&env);
    match store.listar_atendentes(&ctx).await {
        Ok(itens) => ok_reply(
            &env,
            "ListAtendentesReply",
            serde_json::json!({ "atendentes": itens }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// `0` no proto3 significa "não informado" — para `departamento_id`, isso é
/// "sem departamento" (a coluna aceita NULL), não o departamento de id zero.
fn opcional_positivo(payload: &serde_json::Value, chave: &str) -> Option<i32> {
    payload
        .get(chave)
        .and_then(|v| v.as_i64())
        .filter(|n| *n > 0)
        .map(|n| n as i32)
}

#[tracing::instrument(skip_all, fields(rpc = "CreateAtendente", tenant_id = %env.tenant_id))]
async fn handler_create_atendente(
    store: &dyn ports::OperacionalStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let texto = |chave: &str| {
        payload
            .get(chave)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .trim()
            .to_string()
    };
    let nome = texto("nome");
    let email = texto("email");
    let cargo = texto("cargo");
    let fluxo_id = payload
        .get("fluxo_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;

    if nome.is_empty() {
        return erro(
            error_core::AppError::Validation("informe o nome do atendente".into()),
            &env,
        );
    }
    if email.is_empty() {
        return erro(
            error_core::AppError::Validation("informe o e-mail do atendente".into()),
            &env,
        );
    }
    if fluxo_id <= 0 {
        // `fluxo_id` é NOT NULL: sem fluxo o INSERT falharia com erro de
        // constraint, que não diz nada a quem está cadastrando.
        return erro(
            error_core::AppError::Validation(
                "escolha o fluxo em que este atendente trabalha".into(),
            ),
            &env,
        );
    }

    let ctx = contexto_do_envelope(&env);
    match store
        .criar_atendente(
            &ctx,
            nome.clone(),
            email,
            cargo,
            fluxo_id,
            opcional_positivo(&payload, "departamento_id"),
        )
        .await
    {
        Ok(atendente) => {
            audit
                .publish(
                    &env,
                    "atendente_criado",
                    format!("Atendente '{nome}' criado"),
                    serde_json::json!({
                        "id": atendente.get("id").and_then(|v| v.as_i64()).unwrap_or(0),
                        "fluxo_id": fluxo_id,
                    }),
                )
                .await;
            ok_reply(&env, "CreateAtendenteReply", atendente)
        }
        Err(err) => erro(err.into(), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "UpdateAtendente", tenant_id = %env.tenant_id))]
async fn handler_update_atendente(
    store: &dyn ports::OperacionalStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id = payload.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
    let nome = payload
        .get("nome")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .trim()
        .to_string();
    let cargo = payload
        .get("cargo")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .trim()
        .to_string();
    let fluxo_id = payload
        .get("fluxo_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;
    let ativo = payload
        .get("ativo")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);
    let disponivel = payload
        .get("disponivel")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);
    // Teto de zero deixaria o atendente cadastrado e nunca elegível no
    // round-robin — inativo por acidente, sem parecer inativo.
    let max_simultaneos = payload
        .get("max_atendimentos_simultaneos")
        .and_then(|v| v.as_i64())
        .unwrap_or(5)
        .clamp(1, 100) as i32;

    if nome.is_empty() {
        return erro(
            error_core::AppError::Validation("informe o nome do atendente".into()),
            &env,
        );
    }
    if fluxo_id <= 0 {
        return erro(
            error_core::AppError::Validation(
                "escolha o fluxo em que este atendente trabalha".into(),
            ),
            &env,
        );
    }

    let ctx = contexto_do_envelope(&env);
    match store
        .atualizar_atendente(
            &ctx,
            id,
            nome.clone(),
            cargo,
            opcional_positivo(&payload, "departamento_id"),
            fluxo_id,
            ativo,
            disponivel,
            max_simultaneos,
        )
        .await
    {
        Ok(res) => match responder_resultado(&env, "UpdateAtendenteReply", res) {
            Ok(resp) => {
                audit
                    .publish(
                        &env,
                        "atendente_atualizado",
                        format!("Atendente '{nome}' atualizado"),
                        serde_json::json!({
                            "id": id, "ativo": ativo, "disponivel": disponivel,
                        }),
                    )
                    .await;
                resp
            }
            Err(recusa) => recusa,
        },
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "DesativarAtendente", tenant_id = %env.tenant_id))]
async fn handler_desativar_atendente(
    store: &dyn ports::OperacionalStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id = payload.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;

    let ctx = contexto_do_envelope(&env);
    match store.desativar_atendente(&ctx, id).await {
        Ok(res) => match responder_resultado(&env, "DesativarAtendenteReply", res) {
            Ok(resp) => {
                audit
                    .publish(
                        &env,
                        "atendente_desativado",
                        format!("Atendente {id} desativado"),
                        serde_json::json!({ "id": id }),
                    )
                    .await;
                resp
            }
            Err(recusa) => recusa,
        },
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

// --- Treinamento da IA (CRUD do tenant) ---
//
// A v1 tinha seis telas para isto; o v2 tinha a camada de banco pronta e
// nenhum caminho até ela — nem RPC, nem tela. Estes handlers abrem o caminho.

/// Cria (ou reaproveita) o treinamento de uma dupla tag+grupo.
#[tracing::instrument(skip_all, fields(rpc = "CreateTreinamento", tenant_id = %env.tenant_id))]
async fn handler_create_treinamento(
    store: &dyn ports::TreinamentoStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let tag = payload
        .get("tag")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .trim();
    let grupo = payload
        .get("grupo")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .trim();
    let conteudo = payload
        .get("conteudo")
        .and_then(|v| v.as_str())
        .unwrap_or_default();

    if tag.is_empty() || grupo.is_empty() {
        return erro(
            error_core::AppError::Validation("informe a tag e o grupo".into()),
            &env,
        );
    }
    if conteudo.trim().is_empty() {
        return erro(
            error_core::AppError::Validation("o conteúdo do treinamento está vazio".into()),
            &env,
        );
    }

    let ctx = contexto_do_envelope(&env);
    match store.criar_treinamento(&ctx, tag, grupo, conteudo).await {
        Ok(t) => {
            audit
                .publish(
                    &env,
                    "treinamento_criado",
                    format!("Treinamento '{}/{}' registrado", t.grupo, t.tag),
                    // O conteúdo NÃO entra na auditoria: é material do cliente e
                    // pode ser volumoso; o que importa aqui é o rastro do ato.
                    serde_json::json!({ "id": t.id, "tag": t.tag, "grupo": t.grupo }),
                )
                .await;
            ok_reply(&env, "CreateTreinamentoReply", serde_json::json!(t))
        }
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// B9 (N10 E6) — a avaliação de um ensaio de pergunta, com a resposta correta.
///
/// Auditada (`treinamento.feedback_registrado`): é insumo de curadoria com efeito
/// futuro no comportamento do bot. A auditoria e o span levam só a avaliação e se
/// houve correção — pergunta e correção são texto livre do operador e podem
/// citar dado de cliente.
#[tracing::instrument(
    skip_all,
    fields(
        rpc = "RegistrarFeedbackTeste",
        avaliacao = tracing::field::Empty,
        houve_correcao = tracing::field::Empty
    )
)]
/// P17 — as avaliações do teste ainda não tratadas. Sem auditoria: é leitura
/// da própria curadoria, e o conteúdo (que pode citar cliente) não vai a log.
async fn handler_listar_avaliacoes_de_teste(
    store: &dyn ports::TreinamentoStore,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let limite = payload.get("limite").and_then(|v| v.as_i64()).unwrap_or(50);
    let ctx = contexto_do_envelope(&env);
    match store.listar_avaliacoes_pendentes(&ctx, limite).await {
        Ok(itens) => {
            tracing::info!(quantidade = itens.len(), "avaliações pendentes listadas");
            ok_reply(
                &env,
                "ListAvaliacoesDeTesteReply",
                serde_json::json!({ "itens": itens }),
            )
        }
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// P17 — tira a avaliação da revisão (virou treinamento, ou foi dispensada).
async fn handler_marcar_avaliacao_tratada(
    store: &dyn ports::TreinamentoStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let Some(id) = payload.get("id").and_then(|v| v.as_i64()).map(|v| v as i32) else {
        return erro(error_core::AppError::Validation("id ausente".into()), &env);
    };
    let virou_treinamento = payload
        .get("virou_treinamento")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let ctx = contexto_do_envelope(&env);
    match store.marcar_avaliacao_tratada(&ctx, id).await {
        Ok(mudou) => {
            if mudou {
                audit
                    .publish(
                        &env,
                        if virou_treinamento {
                            "treinamento.correcao_promovida"
                        } else {
                            "treinamento.avaliacao_dispensada"
                        },
                        format!("avaliação de teste {id} tratada"),
                        serde_json::json!({ "avaliacao_id": id, "virou_treinamento": virou_treinamento }),
                    )
                    .await;
            }
            ok_reply(
                &env,
                "MarcarAvaliacaoTratadaReply",
                serde_json::json!({ "sucesso": mudou }),
            )
        }
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

async fn handler_registrar_feedback_teste(
    store: &dyn ports::TreinamentoStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let texto = |chave: &str| {
        payload
            .get(chave)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .trim()
            .to_string()
    };
    let pergunta = texto("pergunta");
    let resposta = texto("resposta_obtida");
    let correcao = texto("resposta_correta");
    let avaliacao = texto("avaliacao");

    if pergunta.is_empty() || resposta.is_empty() {
        return erro(
            error_core::AppError::Validation(
                "o feedback precisa da pergunta e da resposta avaliada".into(),
            ),
            &env,
        );
    }
    if avaliacao != "boa" && avaliacao != "ruim" {
        return erro(
            error_core::AppError::Validation("a avaliação deve ser boa ou ruim".into()),
            &env,
        );
    }
    let houve_correcao = !correcao.is_empty();
    let span = tracing::Span::current();
    span.record("avaliacao", avaliacao.as_str());
    span.record("houve_correcao", houve_correcao);

    let novo = infrastructure_postgres::treinamento::treinamentos::NovoFeedbackTeste {
        pergunta,
        resposta_bot: resposta,
        resposta_corrigida: houve_correcao.then_some(correcao),
        avaliacao: avaliacao.clone(),
        confiabilidade: payload
            .get("confiabilidade")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0),
        comportamento_aplicado: texto("comportamento_aplicado"),
    };

    let ctx = contexto_do_envelope(&env);
    match store.registrar_feedback_teste(&ctx, novo).await {
        Ok(id) => {
            audit
                .publish(
                    &env,
                    "treinamento.feedback_registrado",
                    format!("Avaliação de teste registrada ({avaliacao})"),
                    serde_json::json!({
                        "id": id,
                        "avaliacao": avaliacao,
                        "houve_correcao": houve_correcao,
                    }),
                )
                .await;
            ok_reply(
                &env,
                "RegistrarFeedbackTesteReply",
                serde_json::json!({ "id": id }),
            )
        }
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// B9 (N10 E5) — passo 1 do upload de arquivo de treinamento: quota e chave.
async fn handler_autorizar_upload_treinamento(
    store: &dyn ports::TreinamentoStore,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let bytes = payload.get("bytes").and_then(|v| v.as_i64()).unwrap_or(0);
    if bytes <= 0 {
        return erro(
            error_core::AppError::Validation("arquivo vazio".into()),
            &env,
        );
    }
    let ctx = contexto_do_envelope(&env);
    match store.autorizar_upload_treinamento(&ctx, bytes).await {
        Ok(chave) => ok_reply(
            &env,
            "AutorizarUploadTreinamentoReply",
            serde_json::json!({ "chave": chave }),
        ),
        Err(err) => erro(err.into(), &env),
    }
}

/// B9 (N10 E5) — passo 3: o arquivo já foi conferido no bucket pelo runtime;
/// cria o treinamento com a extração pendente.
///
/// Auditado (`treinamento.arquivo_enviado`): material de treinamento vira
/// comportamento do bot, e a trilha precisa responder "de onde saiu essa
/// resposta". O nome do arquivo vai para a trilha (é escolha de quem enviou); o
/// conteúdo, nunca.
#[tracing::instrument(skip_all, fields(rpc = "CriarTreinamentoComArquivo", tenant_id = %env.tenant_id))]
async fn handler_criar_treinamento_com_arquivo(
    store: &dyn ports::TreinamentoStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let texto = |chave: &str| {
        payload
            .get(chave)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .trim()
            .to_string()
    };
    let novo = infrastructure_postgres::treinamento::treinamentos::NovoTreinamentoComArquivo {
        tag: texto("tag"),
        grupo: texto("grupo"),
        chave: texto("chave"),
        nome_arquivo: texto("nome_arquivo"),
        mimetype: texto("mimetype"),
        bytes: payload.get("bytes").and_then(|v| v.as_i64()).unwrap_or(0),
    };
    if novo.tag.is_empty() || novo.grupo.is_empty() {
        return erro(
            error_core::AppError::Validation("informe a tag e o grupo".into()),
            &env,
        );
    }
    // A chave tem de ser das que o servidor gera: aceitar qualquer uma deixaria
    // o cliente apontar o treinamento para a mídia de uma conversa.
    if !novo.chave.starts_with("treinamento/") || novo.bytes <= 0 {
        return erro(
            error_core::AppError::Validation("arquivo de treinamento inválido".into()),
            &env,
        );
    }

    let ctx = contexto_do_envelope(&env);
    let (nome, bytes, mimetype) = (novo.nome_arquivo.clone(), novo.bytes, novo.mimetype.clone());
    match store.criar_treinamento_com_arquivo(&ctx, novo).await {
        Ok(t) => {
            audit
                .publish(
                    &env,
                    "treinamento.arquivo_enviado",
                    format!("Arquivo de treinamento '{}/{}' enviado", t.grupo, t.tag),
                    serde_json::json!({
                        "id": t.id,
                        "tag": t.tag,
                        "grupo": t.grupo,
                        "nome_arquivo": nome,
                        "bytes": bytes,
                        "mimetype": mimetype,
                    }),
                )
                .await;
            ok_reply(
                &env,
                "CriarTreinamentoComArquivoReply",
                serde_json::json!(t),
            )
        }
        Err(err) => erro(err.into(), &env),
    }
}

/// B9 (N10 E5) — a fila da extração, para o scheduler. Teto de 50 por lote: cada
/// item é um documento inteiro a baixar e ler.
async fn handler_listar_extracoes_pendentes(
    store: &dyn ports::TreinamentoStore,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let limite = payload
        .get("limite")
        .and_then(|v| v.as_i64())
        .unwrap_or(5)
        .clamp(1, 50);
    let ctx = contexto_do_envelope(&env);
    match store.listar_extracoes_pendentes(&ctx, limite).await {
        Ok(itens) => ok_reply(
            &env,
            "ListarExtracoesPendentesReply",
            serde_json::json!({ "pendentes": itens }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// B9 (N10 E5) — grava o que a extração devolveu. A falha é auditada
/// (`treinamento.extracao_falhou`) com o motivo; o texto extraído, nunca.
async fn handler_registrar_extracao_treinamento(
    store: &dyn ports::TreinamentoStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    use infrastructure_postgres::treinamento::treinamentos::ResultadoExtracao;

    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let Some(id) = payload
        .get("treinamento_id")
        .and_then(|v| v.as_i64())
        .map(|v| v as i32)
    else {
        return erro(
            error_core::AppError::Validation("treinamento_id ausente".into()),
            &env,
        );
    };
    let resultado = match (
        payload.get("texto").and_then(|v| v.as_str()),
        payload.get("erro").and_then(|v| v.as_str()),
    ) {
        (Some(texto), _) if !texto.trim().is_empty() => ResultadoExtracao::Texto(texto.to_string()),
        (_, Some(motivo)) if !motivo.trim().is_empty() => {
            ResultadoExtracao::Falha(motivo.trim().to_string())
        }
        _ => {
            return erro(
                error_core::AppError::Validation("informe o texto ou o erro".into()),
                &env,
            )
        }
    };
    let falhou = match &resultado {
        ResultadoExtracao::Falha(motivo) => Some(motivo.clone()),
        ResultadoExtracao::Texto(_) => None,
    };

    let ctx = contexto_do_envelope(&env);
    match store
        .registrar_extracao_treinamento(&ctx, id, resultado)
        .await
    {
        Ok(gravou) => {
            if let (true, Some(motivo)) = (gravou, falhou) {
                audit
                    .publish(
                        &env,
                        "treinamento.extracao_falhou",
                        "Não foi possível extrair o texto do arquivo de treinamento".to_string(),
                        serde_json::json!({ "id": id, "motivo": motivo }),
                    )
                    .await;
            }
            ok_reply(
                &env,
                "RegistrarExtracaoTreinamentoReply",
                serde_json::json!({ "registrado": gravou }),
            )
        }
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

// --- Vetorização (scheduler do worker) e curadoria de intenções ---
//
// Sem a fila de vetorização, o material treinado nunca vira vetor e o RAG
// consulta uma tabela vazia: a tela de treinamento gravava texto que a IA
// nunca lia.

#[tracing::instrument(skip_all, fields(rpc = "ListarTreinamentosPendentes"))]
async fn handler_listar_pendentes_vetorizacao(
    store: &dyn ports::TreinamentoStore,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    // Teto de 500: o lote vira uma rajada de chamadas ao ia_engine, e um número
    // solto no payload poderia derrubar o provedor de embeddings.
    let limite = payload
        .get("limite")
        .and_then(|v| v.as_i64())
        .unwrap_or(50)
        .clamp(1, 500);

    let ctx = contexto_do_envelope(&env);
    match store.listar_pendentes_vetorizacao(&ctx, limite).await {
        Ok(itens) => ok_reply(
            &env,
            "ListarTreinamentosPendentesReply",
            serde_json::json!({ "pendentes": itens }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "SalvarChunksVetorizados", tenant_id = %env.tenant_id))]
async fn handler_salvar_chunks_vetorizados(
    store: &dyn ports::TreinamentoStore,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let treinamento_id = payload
        .get("treinamento_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;
    let chunks: Vec<ports::treinamento::ChunkVetorizado> = payload
        .get("chunks")
        .and_then(|v| serde_json::from_value(v.clone()).ok())
        .unwrap_or_default();

    if chunks.is_empty() {
        // Marcar como vetorizado sem trecho nenhum tiraria o treinamento da
        // fila para sempre, deixando material que a IA nunca leria.
        return erro(
            error_core::AppError::Validation("nenhum trecho para gravar".into()),
            &env,
        );
    }

    let ctx = contexto_do_envelope(&env);
    match store
        .salvar_chunks_vetorizados(&ctx, treinamento_id, chunks)
        .await
    {
        Ok(ok) => ok_reply(
            &env,
            "SalvarChunksVetorizadosReply",
            serde_json::json!({ "sucesso": ok }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "ListarIntentsSemEmbedding"))]
async fn handler_listar_intents_sem_embedding(
    store: &dyn ports::TreinamentoStore,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let limite = payload
        .get("limite")
        .and_then(|v| v.as_i64())
        .unwrap_or(50)
        .clamp(1, 500);

    let ctx = contexto_do_envelope(&env);
    match store.listar_intents_sem_embedding(&ctx, limite).await {
        Ok(itens) => ok_reply(
            &env,
            "ListarIntentsSemEmbeddingReply",
            serde_json::json!({ "pendentes": itens }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "DefinirEmbeddingIntent", tenant_id = %env.tenant_id))]
async fn handler_definir_embedding_intent(
    store: &dyn ports::TreinamentoStore,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id = payload.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
    let embedding: Vec<f32> = payload
        .get("embedding")
        .and_then(|v| serde_json::from_value(v.clone()).ok())
        .unwrap_or_default();

    if embedding.is_empty() {
        return erro(
            error_core::AppError::Validation("embedding vazio".into()),
            &env,
        );
    }

    let ctx = contexto_do_envelope(&env);
    match store.definir_embedding_intent(&ctx, id, embedding).await {
        Ok(ok) => ok_reply(
            &env,
            "DefinirEmbeddingIntentReply",
            serde_json::json!({ "sucesso": ok }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "ListIntents", tenant_id = %env.tenant_id))]
async fn handler_list_intents(store: &dyn ports::TreinamentoStore, env: Envelope) -> Envelope {
    let ctx = contexto_do_envelope(&env);
    match store.listar_intents(&ctx).await {
        Ok(itens) => ok_reply(
            &env,
            "ListIntentsReply",
            serde_json::json!({ "intents": itens }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// Lê os cinco campos de uma intenção do payload, já aparados.
fn dados_da_intent(payload: &serde_json::Value) -> ports::treinamento::DadosIntent {
    let texto = |chave: &str| {
        payload
            .get(chave)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .trim()
            .to_string()
    };
    ports::treinamento::DadosIntent {
        tag: texto("tag"),
        grupo: texto("grupo"),
        descricao: texto("descricao"),
        exemplo: texto("exemplo"),
        comportamento: texto("comportamento"),
    }
}

/// Os três campos sem os quais a intenção não serve para nada.
///
/// `tag`+`descricao`+`exemplo` são o texto que vira vetor, e `comportamento` é
/// o que a IA passa a fazer quando ele casa. Sem comportamento, casar não muda
/// nada; sem descrição, nunca casa.
fn validar_intent(dados: &ports::treinamento::DadosIntent) -> Option<&'static str> {
    if dados.tag.is_empty() {
        return Some("informe a tag da intenção");
    }
    if dados.descricao.is_empty() {
        return Some("descreva quando esta intenção se aplica");
    }
    if dados.comportamento.is_empty() {
        return Some("informe o que a IA deve fazer nesta intenção");
    }
    None
}

#[tracing::instrument(skip_all, fields(rpc = "CreateIntent", tenant_id = %env.tenant_id))]
async fn handler_create_intent(
    store: &dyn ports::TreinamentoStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let dados = dados_da_intent(&payload);
    if let Some(motivo) = validar_intent(&dados) {
        return erro(error_core::AppError::Validation(motivo.into()), &env);
    }
    let tag = dados.tag.clone();

    let ctx = contexto_do_envelope(&env);
    match store.criar_intent(&ctx, dados).await {
        Ok(intent) => {
            audit
                .publish(
                    &env,
                    "intent_criada",
                    format!("Intenção '{tag}' criada"),
                    serde_json::json!({ "id": intent.id }),
                )
                .await;
            match serde_json::to_value(&intent) {
                Ok(json) => ok_reply(&env, "CreateIntentReply", json),
                Err(e) => erro(
                    error_core::AppError::Internal(format!("falha ao serializar: {e}")),
                    &env,
                ),
            }
        }
        Err(err) => erro(err.into(), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "UpdateIntent", tenant_id = %env.tenant_id))]
async fn handler_update_intent(
    store: &dyn ports::TreinamentoStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id = payload.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
    let dados = dados_da_intent(&payload);
    if let Some(motivo) = validar_intent(&dados) {
        return erro(error_core::AppError::Validation(motivo.into()), &env);
    }
    let tag = dados.tag.clone();

    let ctx = contexto_do_envelope(&env);
    match store.atualizar_intent(&ctx, id, dados).await {
        Ok(true) => {
            audit
                .publish(
                    &env,
                    "intent_atualizada",
                    format!("Intenção '{tag}' atualizada"),
                    serde_json::json!({ "id": id }),
                )
                .await;
            ok_reply(
                &env,
                "UpdateIntentReply",
                serde_json::json!({ "sucesso": true }),
            )
        }
        Ok(false) => erro(
            error_core::AppError::Validation("intenção não encontrada".into()),
            &env,
        ),
        Err(err) => erro(err.into(), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "RemoveIntent", tenant_id = %env.tenant_id))]
async fn handler_remove_intent(
    store: &dyn ports::TreinamentoStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id = payload.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;

    let ctx = contexto_do_envelope(&env);
    match store.remover_intent(&ctx, id).await {
        Ok(true) => {
            audit
                .publish(
                    &env,
                    "intent_removida",
                    format!("Intenção {id} removida"),
                    serde_json::json!({ "id": id }),
                )
                .await;
            ok_reply(
                &env,
                "RemoveIntentReply",
                serde_json::json!({ "sucesso": true }),
            )
        }
        Ok(false) => erro(
            error_core::AppError::Validation("intenção não encontrada".into()),
            &env,
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "ListTreinamentos", tenant_id = %env.tenant_id))]
async fn handler_list_treinamentos(store: &dyn ports::TreinamentoStore, env: Envelope) -> Envelope {
    let ctx = contexto_do_envelope(&env);
    match store.listar_treinamentos(&ctx).await {
        Ok(itens) => ok_reply(
            &env,
            "ListTreinamentosReply",
            serde_json::json!({ "treinamentos": itens }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "GetTreinamento", tenant_id = %env.tenant_id))]
async fn handler_get_treinamento(store: &dyn ports::TreinamentoStore, env: Envelope) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id = payload.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;

    let ctx = contexto_do_envelope(&env);
    match store.obter_treinamento(&ctx, id).await {
        Ok(Some(t)) => ok_reply(&env, "GetTreinamentoReply", serde_json::json!(t)),
        Ok(None) => erro(
            error_core::AppError::Validation("treinamento não encontrado".into()),
            &env,
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// Aceita a revisão: grava o texto e põe o treinamento na fila de vetorização.
#[tracing::instrument(skip_all, fields(rpc = "FinalizarTreinamento", tenant_id = %env.tenant_id))]
async fn handler_finalizar_treinamento(
    store: &dyn ports::TreinamentoStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let id = payload.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
    let conteudo = payload
        .get("conteudo")
        .and_then(|v| v.as_str())
        .unwrap_or_default();

    if conteudo.trim().is_empty() {
        return erro(
            error_core::AppError::Validation("o conteúdo revisado está vazio".into()),
            &env,
        );
    }

    let ctx = contexto_do_envelope(&env);
    match store.finalizar_treinamento(&ctx, id, conteudo).await {
        Ok(true) => {
            audit
                .publish(
                    &env,
                    "treinamento_finalizado",
                    format!("Treinamento {id} aceito e enviado para vetorização"),
                    serde_json::json!({ "id": id }),
                )
                .await;
            ok_reply(
                &env,
                "FinalizarTreinamentoReply",
                serde_json::json!({ "sucesso": true }),
            )
        }
        Ok(false) => erro(
            error_core::AppError::Validation("treinamento não encontrado".into()),
            &env,
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "RemoverTreinamento", tenant_id = %env.tenant_id))]
async fn handler_remover_treinamento(
    store: &dyn ports::TreinamentoStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let id = payload.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;

    let ctx = contexto_do_envelope(&env);
    match store.remover_treinamento(&ctx, id).await {
        Ok(true) => {
            audit
                .publish(
                    &env,
                    "treinamento_removido",
                    format!("Treinamento {id} removido"),
                    serde_json::json!({ "id": id }),
                )
                .await;
            ok_reply(
                &env,
                "RemoverTreinamentoReply",
                serde_json::json!({ "sucesso": true }),
            )
        }
        Ok(false) => erro(
            error_core::AppError::Validation("treinamento não encontrado".into()),
            &env,
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

/// Extrai o tenant do Envelope para o payload de auditoria. `None` quando
/// vazio, invalido ou nil — nunca `Some(Uuid::nil())`. `run_in_tenant_transaction`
/// nao trata nil como caso especial: ele configura a RLS para qualquer Uuid
/// recebido e tenta o INSERT, entao um payload com `Some(nil)` violava
/// `audit_log_tenant_id_fkey` (nao existe tenant "00000000-...").
fn tenant_id_para_auditoria(env: &Envelope) -> Option<Uuid> {
    Uuid::parse_str(&env.tenant_id)
        .ok()
        .filter(|id| !id.is_nil())
}

/// Extrai o user_id do Envelope para o payload de auditoria. `None` quando 0
/// (publico/nao autenticado — ver `auth_user_id` em envelope.proto) — nunca
/// `Some(0)`, que violava `audit_log_user_id_fkey` (nao existe auth_user id=0).
/// Mesmo idioma ja usado em `onboarding.rs` (`criado_por`).
fn user_id_para_auditoria(env: &Envelope) -> Option<i32> {
    (env.auth_user_id > 0).then_some(env.auth_user_id)
}

async fn publicar_auditoria(
    redis_conn: &mut ConnectionManager,
    env: &Envelope,
    event: &str,
    message: String,
    context: serde_json::Value,
) {
    let tenant_id = tenant_id_para_auditoria(env);
    let audit_payload = observability::AuditLogPayload {
        tenant_id,
        level: "WARN".to_string(),
        service: "data_postgres".to_string(),
        trace_id: Some(env.traceparent.clone()),
        event: event.to_string(),
        message,
        context,
        user_id: user_id_para_auditoria(env),
        ip_address: None,
        user_agent: (!env.user_agent.is_empty()).then(|| env.user_agent.clone()),
    };

    let envelope_auditoria = contracts::TenantEnvelope::novo(
        tenant_id.unwrap_or_else(Uuid::nil),
        "security.audit",
        audit_payload,
    )
    .com_traceparent(env.traceparent.clone());

    if let Err(e) = transport::bus::publicar_evento_seguranca(redis_conn, &envelope_auditoria).await
    {
        tracing::error!("Falha ao publicar auditoria de '{}': {:?}", event, e);
    }
}

#[cfg(test)]
mod tests_auditoria_unit {
    use super::*;

    fn envelope_com(tenant_id: &str, auth_user_id: i32) -> Envelope {
        Envelope {
            tenant_id: tenant_id.to_string(),
            auth_user_id,
            ..Default::default()
        }
    }

    // --- tenant_id_para_auditoria: regressao do audit_log_tenant_id_fkey ---

    #[test]
    fn tenant_id_para_auditoria_vazio_e_none() {
        assert!(tenant_id_para_auditoria(&envelope_com("", 0)).is_none());
    }

    #[test]
    fn tenant_id_para_auditoria_nil_e_none() {
        let env = envelope_com(&Uuid::nil().to_string(), 0);
        assert!(tenant_id_para_auditoria(&env).is_none());
    }

    #[test]
    fn tenant_id_para_auditoria_invalido_e_none_sem_falhar() {
        assert!(tenant_id_para_auditoria(&envelope_com("nao-e-um-uuid", 0)).is_none());
    }

    #[test]
    fn tenant_id_para_auditoria_valido_e_some() {
        let id = Uuid::now_v7();
        let env = envelope_com(&id.to_string(), 0);
        assert_eq!(tenant_id_para_auditoria(&env), Some(id));
    }

    // --- user_id_para_auditoria: regressao do audit_log_user_id_fkey ---

    #[test]
    fn user_id_para_auditoria_zero_e_none() {
        assert!(user_id_para_auditoria(&envelope_com("", 0)).is_none());
    }

    #[test]
    fn user_id_para_auditoria_positivo_e_some() {
        assert_eq!(user_id_para_auditoria(&envelope_com("", 42)), Some(42));
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
                "transcription_enabled": cfg.transcription_enabled,
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
    // `delta` (opcional) = quanto a operação em curso vai SOMAR ao uso, quando o
    // chamador já sabe o custo antes de executar (ex.: bytes do `PutFile` no
    // data_storage). Permite barrar quem estouraria o limite COM esta operação, e
    // não só quem já o estourou — sem ele, um único upload grande passa livre.
    let delta = payload_json
        .get("delta")
        .and_then(|v| v.as_i64())
        .unwrap_or(0);

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
        Ok(mut status) => {
            let excedido_acumulado = status
                .get("excedido")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);

            // Projeção com o custo da operação. `limite` ausente/nulo = sem
            // assinatura ou plano sem limite: não bloqueia (mesma postura
            // conservadora de `verificar_quota`).
            let limite = status.get("limite").and_then(|v| v.as_i64());
            let uso_atual = status
                .get("uso_atual")
                .and_then(|v| v.as_i64())
                .unwrap_or(0);
            let excedido_projetado = delta != 0
                && limite
                    .map(|l| uso_atual.saturating_add(delta) > l)
                    .unwrap_or(false);

            // O guard do chamador barra os dois casos, então a auditoria também —
            // e `excedido` no reply precisa refletir o veredito COMBINADO, senão o
            // chamador (que decide olhando esse campo) deixaria passar a projeção.
            let excedido = excedido_acumulado || excedido_projetado;
            if let Some(obj) = status.as_object_mut() {
                obj.insert("excedido".to_string(), excedido.into());
                obj.insert("excedido_projetado".to_string(), excedido_projetado.into());
                obj.insert("delta_avaliado".to_string(), delta.into());
            }
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

// --- N7.1: registro de uso de armazenamento (chamado pelo data_storage após um
// PutFile bem-sucedido, para alimentar a checagem de quota "storage" acima) ---

#[tracing::instrument(skip_all, fields(rpc = "RegisterStorageUsage", tenant_id = %env.tenant_id))]
async fn handler_register_storage_usage(store: &dyn ports::QuotaStore, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let delta_bytes = payload_json.get("delta_bytes").and_then(|v| v.as_i64());

    let tenant_id = match Uuid::parse_str(&env.tenant_id) {
        Ok(u) => u,
        Err(_) => {
            return erro(
                error_core::AppError::Validation("tenant_id inválido".to_string()),
                &env,
            )
        }
    };

    // Delta negativo é legítimo: a purga de mídia (retenção) devolve espaço ao
    // tenant. Zero é rejeitado por ser sempre chamada inútil (bug do caller).
    let Some(delta_bytes) = delta_bytes.filter(|d| *d != 0) else {
        return erro(
            error_core::AppError::Validation(
                "delta_bytes deve ser um inteiro diferente de zero".to_string(),
            ),
            &env,
        );
    };

    match store.registrar_uso_storage(tenant_id, delta_bytes).await {
        Ok(total_bytes) => ok_reply(
            &env,
            "RegisterStorageUsageReply",
            serde_json::json!({ "total_bytes": total_bytes }),
        ),
        Err(err) => erro(error_core::AppError::Database(err.to_string()), &env),
    }
}

// --- N7.1: caller de quota no CRUD de criação de departamento (o recurso
// "departamentos" já era reconhecido por `verificar_quota`; faltava só o ponto de
// chamada antes do INSERT). Guard local (sem RPC intermediário — já estamos no
// data_postgres): log-only por padrão, auditoria só quando o enforce real bloquear. ---

#[tracing::instrument(skip_all, fields(rpc = "CreateDepartamento", tenant_id = %env.tenant_id))]
async fn handler_create_departamento(
    quota: &dyn ports::QuotaStore,
    store: &dyn ports::OperacionalStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload_json: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let nome = payload_json
        .get("nome")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    let descricao = payload_json.get("descricao").and_then(|v| v.as_str());

    if nome.is_empty() {
        return erro(
            error_core::AppError::Validation("nome do departamento não pode ser vazio".to_string()),
            &env,
        );
    }

    let tenant_id = match Uuid::parse_str(&env.tenant_id) {
        Ok(u) => u,
        Err(_) => {
            return erro(
                error_core::AppError::Validation("tenant_id inválido".to_string()),
                &env,
            )
        }
    };

    match quota.verificar_quota(tenant_id, "departamentos").await {
        Ok(status) => {
            let excedido = status
                .get("excedido")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            if excedido {
                let enforce = std::env::var("SMARTCORE_QUOTA_ENFORCE")
                    .map(|v| v.eq_ignore_ascii_case("true"))
                    .unwrap_or(false);
                if enforce {
                    tracing::warn!(
                        tenant_id = %env.tenant_id,
                        "quota de departamentos excedida; bloqueando criação"
                    );
                    audit
                        .publish(
                            &env,
                            "quota.excedida",
                            "Quota de 'departamentos' excedida".to_string(),
                            status,
                        )
                        .await;
                    return erro(
                        error_core::AppError::RateLimit(
                            "quota de 'departamentos' excedida".to_string(),
                        ),
                        &env,
                    );
                }
                tracing::warn!(
                    tenant_id = %env.tenant_id,
                    "quota de departamentos excedida (log-only; SMARTCORE_QUOTA_ENFORCE=false)"
                );
            }
        }
        Err(e) => {
            tracing::warn!(
                erro = %e,
                "falha ao verificar quota de departamentos; prosseguindo (fail-open)"
            );
        }
    }

    let ctx = contexto_do_envelope(&env);
    match store
        .criar_departamento(&ctx, nome.to_string(), descricao.map(str::to_string))
        .await
    {
        Ok(departamento) => ok_reply(&env, "CreateDepartamentoReply", departamento),
        // Nome repetido é erro de quem digitou, não falha de infraestrutura. A
        // conversão padrão manda `DbError` para `AppError::Database`, e a borda
        // (com razão) não vaza detalhe de banco para o cliente — o resultado na
        // tela era "erro ao acessar o banco de dados" para quem só repetiu um
        // nome, sem pista do que corrigir. Aqui a causa ainda é conhecida, então
        // é aqui que ela vira uma frase acionável.
        Err(infrastructure_postgres::DbError::UniqueViolation(_)) => erro(
            error_core::AppError::Validation(format!(
                "Já existe um departamento chamado \"{nome}\". Escolha outro nome."
            )),
            &env,
        ),
        Err(err) => erro(err.into(), &env),
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
    let max_fluxos = payload_json
        .get("max_fluxos")
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
        .criar_plano(
            name,
            description,
            price_dec,
            max_instances,
            max_departments,
            max_fluxos,
        )
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
    let max_fluxos = payload_json
        .get("max_fluxos")
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
            max_fluxos,
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

/// Suspende assinaturas ACTIVE cujo período venceu. Chamado pelo scheduler do
/// worker, cross-tenant.
///
/// A v1 tinha `check_subscription_expirations` no Celery; a v2 não tinha
/// equivalente, e uma assinatura vencida deixava o tenant operando
/// indefinidamente. É o espelho do beco sem saída que este plano corrige: lá
/// alguém pagou e não conseguia entrar, aqui alguém não pagou e nunca saía.
///
/// Audita **uma linha por assinatura**, não uma pelo lote: quando o cliente
/// perguntar por que o sistema parou, a resposta precisa ter o tenant e a data
/// de vencimento que motivou.
async fn handler_suspender_assinaturas_vencidas(
    store: &dyn ports::PlansStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let limite = payload
        .get("limite")
        .and_then(|v| v.as_i64())
        .filter(|n| *n > 0)
        .unwrap_or(100);

    match store.suspender_assinaturas_vencidas(limite).await {
        Ok(suspensas) => {
            for (tenant_id, period_end) in &suspensas {
                audit
                    .publish(
                        &env,
                        "assinatura.suspensa_por_vencimento",
                        "Assinatura suspensa: periodo vencido".to_string(),
                        serde_json::json!({
                            "tenant_id": tenant_id.to_string(),
                            "period_end": period_end.to_rfc3339(),
                        }),
                    )
                    .await;
            }
            ok_reply(
                &env,
                "SuspenderAssinaturasVencidasReply",
                serde_json::json!({ "suspensas": suspensas.len() }),
            )
        }
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

async fn handler_query_audit_log(
    store: &dyn ports::OperacionalStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
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
        Ok((list, total_count)) => {
            // Ler o log de auditoria é, em qualquer modelo de auditoria, evento
            // auditável de primeira ordem: é o que denuncia alguém vasculhando
            // dados de tenant. Era a lacuna mais séria da cobertura — o registro
            // de acesso não registrava o próprio acesso.
            //
            // Cuidado deliberado com recursão: este evento nasce de uma LEITURA,
            // então não realimenta consultas; a escrita gera uma linha só.
            audit
                .publish(
                    &env,
                    "audit_log_consultado",
                    "Log de auditoria consultado".to_string(),
                    serde_json::json!({
                        "tenant_filtrado": tenant_id.map(|t| t.to_string()),
                        "evento_filtrado": event_type_para_log(&payload),
                        "limit": limit,
                        "offset": offset,
                        "retornadas": list.len(),
                    }),
                )
                .await;
            ok_reply(
                &env,
                "QueryAuditLogReply",
                serde_json::json!({
                    "entries": list,
                    "total_count": total_count as i32
                }),
            )
        }
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// Filtro de tipo de evento usado na consulta, para o registro do acesso.
/// Relido do payload porque o valor original é movido para o store.
fn event_type_para_log(payload: &serde_json::Value) -> Option<String> {
    payload
        .get("event_type")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
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

/// P7 — a lista de números ignorados, inclusive os desligados.
///
/// A regra da "whitelist" (que ignora, não libera — ver o contrato) já valia na
/// ingestão desde o começo. O que não existia era meio de ver ou mexer nela sem
/// abrir o banco.
async fn handler_listar_numeros_ignorados(
    store: &dyn ports::WhatsappStore,
    env: Envelope,
) -> Envelope {
    let ctx = contexto_do_envelope(&env);
    match store.listar_numeros_ignorados(&ctx).await {
        Ok(itens) => ok_reply(
            &env,
            "ListNumerosIgnoradosReply",
            serde_json::json!({ "itens": itens }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// P7 — acrescenta um número à lista.
///
/// Auditado: ignorar um número faz o sistema parar de atender alguém, e a
/// pergunta "por que este cliente nunca é respondido?" precisa ter resposta.
async fn handler_criar_numero_ignorado(
    store: &dyn ports::WhatsappStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let nome = payload
        .get("nome")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .trim()
        .to_string();
    let telefone = payload
        .get("telefone")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .trim()
        .to_string();
    if telefone.is_empty() {
        return erro(
            error_core::AppError::Validation("telefone ausente".into()),
            &env,
        );
    }

    let ctx = contexto_do_envelope(&env);
    match store.criar_numero_ignorado(&ctx, &nome, &telefone).await {
        Ok(item) => {
            audit
                .publish(
                    &env,
                    "whatsapp.numero_ignorado.criado",
                    format!("número '{}' passou a ser ignorado", item.phone_number),
                    serde_json::json!({ "id": item.id, "nome": item.name }),
                )
                .await;
            ok_reply(
                &env,
                "CriarNumeroIgnoradoReply",
                serde_json::json!({ "item": item }),
            )
        }
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// P7 — corrige o cadastro ou liga/desliga a regra.
async fn handler_atualizar_numero_ignorado(
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
    let nome = payload
        .get("nome")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .trim()
        .to_string();
    let telefone = payload
        .get("telefone")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .trim()
        .to_string();
    if telefone.is_empty() {
        return erro(
            error_core::AppError::Validation("telefone ausente".into()),
            &env,
        );
    }
    // Sem default: "não mandou" é erro de contrato, não "desligue a regra".
    let ativo = match payload.get("ativo").and_then(|v| v.as_bool()) {
        Some(v) => v,
        None => {
            return erro(
                error_core::AppError::Validation("ativo ausente".into()),
                &env,
            )
        }
    };

    let ctx = contexto_do_envelope(&env);
    match store
        .atualizar_numero_ignorado(&ctx, id, &nome, &telefone, ativo)
        .await
    {
        Ok(Some(item)) => {
            audit
                .publish(
                    &env,
                    "whatsapp.numero_ignorado.alterado",
                    format!(
                        "número '{}' {}",
                        item.phone_number,
                        if item.active {
                            "voltou a ser ignorado"
                        } else {
                            "voltou a ser atendido"
                        }
                    ),
                    serde_json::json!({ "id": item.id, "ativo": item.active }),
                )
                .await;
            ok_reply(
                &env,
                "AtualizarNumeroIgnoradoReply",
                serde_json::json!({ "sucesso": true, "item": item }),
            )
        }
        // Inexistente ou de outro tenant: a RLS já o escondeu, e responder
        // "sucesso" faria a tela sumir com uma linha que continua lá.
        Ok(None) => erro(
            error_core::AppError::Database("número ignorado não encontrado".into()),
            &env,
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// P7 — apaga a entrada de vez.
async fn handler_remover_numero_ignorado(
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
    match store.remover_numero_ignorado(&ctx, id).await {
        Ok(true) => {
            audit
                .publish(
                    &env,
                    "whatsapp.numero_ignorado.removido",
                    format!("entrada {id} removida da lista de números ignorados"),
                    serde_json::json!({ "id": id }),
                )
                .await;
            ok_reply(
                &env,
                "RemoverNumeroIgnoradoReply",
                serde_json::json!({ "sucesso": true }),
            )
        }
        Ok(false) => erro(
            error_core::AppError::Database("número ignorado não encontrado".into()),
            &env,
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// P7 — liga a conexão a um departamento; `departamento_id = 0` desfaz.
async fn handler_definir_departamento_conexao(
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
    // 0 é "sem departamento", não "departamento zero": é assim que a tela
    // desfaz o vínculo sem precisar de um campo a mais.
    let departamento_id = payload
        .get("departamento_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;
    let departamento_id = (departamento_id > 0).then_some(departamento_id);

    let ctx = contexto_do_envelope(&env);
    match store
        .definir_departamento_da_conexao(&ctx, id, departamento_id)
        .await
    {
        Ok(true) => {
            audit
                .publish(
                    &env,
                    "whatsapp_instance.departamento_definido",
                    match departamento_id {
                        Some(d) => format!("conexão {id} passou a rotear para o departamento {d}"),
                        None => format!("conexão {id} deixou de rotear por departamento"),
                    },
                    serde_json::json!({ "instance_id": id, "departamento_id": departamento_id }),
                )
                .await;
            ok_reply(
                &env,
                "DefinirDepartamentoDaConexaoReply",
                serde_json::json!({ "sucesso": true }),
            )
        }
        Ok(false) => erro(
            error_core::AppError::Database("conexão não encontrada".into()),
            &env,
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// P7 — o departamento de cada conexão do tenant.
///
/// Rota separada da listagem porque `ListWhatsappInstances` usa `query_as!`
/// (macro), cujo cache `.sqlx` não conhece a coluna nova. Juntar as duas
/// exigiria regravar o cache contra um banco vivo, e o build offline da CI
/// quebraria antes de qualquer teste rodar.
async fn handler_departamentos_das_conexoes(
    store: &dyn ports::WhatsappStore,
    env: Envelope,
) -> Envelope {
    let ctx = contexto_do_envelope(&env);
    match store.departamentos_das_conexoes(&ctx).await {
        Ok(linhas) => {
            let itens: Vec<serde_json::Value> = linhas
                .into_iter()
                .map(|(id, dep, nome)| {
                    serde_json::json!({
                        "id": id,
                        "departamento_id": dep.unwrap_or(0),
                        "departamento_nome": nome,
                    })
                })
                .collect();
            ok_reply(
                &env,
                "ListDepartamentosDasConexoesReply",
                serde_json::json!({ "itens": itens }),
            )
        }
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// P7 — o detalhe da conexão.
async fn handler_detalhe_da_conexao(store: &dyn ports::WhatsappStore, env: Envelope) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };
    let id = match payload.get("id").and_then(|v| v.as_i64()) {
        Some(i) => i as i32,
        None => return erro(error_core::AppError::Validation("id ausente".into()), &env),
    };

    let ctx = contexto_do_envelope(&env);
    match store.detalhe_da_conexao(&ctx, id).await {
        Ok(Some(d)) => ok_reply(&env, "DetalheDaConexaoReply", serde_json::json!(d)),
        Ok(None) => erro(
            error_core::AppError::Database("conexão não encontrada".into()),
            &env,
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

    // N8.5/E5: quem provocou a mudança. `consulta` = alguém abriu a tela e o
    // status foi lido do provedor; `webhook` = o provedor avisou sozinho. Sem esta
    // distinção, a trilha não responde se a queda foi detectada na hora ou horas
    // depois, quando um humano finalmente olhou.
    let origem = payload
        .get("origem")
        .and_then(|v| v.as_str())
        .unwrap_or("consulta");

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
                    serde_json::json!({
                        "instance_id": id,
                        "connection_state": connection_state,
                        "origem": origem,
                    }),
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
mod tests_contatos_unit {
    use super::*;

    /// O formato tem de ser o mesmo que a ingestão grava, senão o contato
    /// cadastrado à mão e o que escreve pelo WhatsApp viram duas pessoas.
    #[test]
    fn telefone_nacional_ganha_o_ddi() {
        assert_eq!(
            normalizar_telefone("(11) 99999-8888").as_deref(),
            Some("5511999998888")
        );
        // Fixo, 8 dígitos.
        assert_eq!(
            normalizar_telefone("11 3333-4444").as_deref(),
            Some("551133334444")
        );
    }

    #[test]
    fn telefone_com_ddi_nao_ganha_outro() {
        assert_eq!(
            normalizar_telefone("+55 11 99999-8888").as_deref(),
            Some("5511999998888")
        );
        assert_eq!(
            normalizar_telefone("5511999998888").as_deref(),
            Some("5511999998888")
        );
    }

    #[test]
    fn o_que_nao_pode_ser_telefone_e_recusado() {
        assert_eq!(normalizar_telefone(""), None);
        assert_eq!(normalizar_telefone("99999"), None);
        assert_eq!(normalizar_telefone("Maria"), None);
        // Longo demais para E.164.
        assert_eq!(normalizar_telefone("1234567890123456"), None);
    }

    #[test]
    fn email_vazio_e_ausencia_e_nao_erro() {
        assert_eq!(conferir_email("   "), Ok(None));
    }

    #[test]
    fn email_sem_arroba_e_engano_de_digitacao() {
        assert!(conferir_email("Maria Silva").is_err());
        assert!(conferir_email("@dominio.com").is_err());
        assert_eq!(
            conferir_email(" maria@exemplo.com "),
            Ok(Some("maria@exemplo.com".to_string()))
        );
    }
}

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
            resposta_bot: true,
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
mod tests_redefinicao_unit {
    use super::*;
    use crate::ports::{MockAuditPort, MockAuthStore, MockTenantStore};
    use contracts::{Envelope, MessageKind};
    use infrastructure_postgres::auth::users::AuthUser;
    use infrastructure_postgres::tenants::tenants::TenantInvite;

    const HASH: &str = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

    fn envelope_com_payload(method: &str, payload: serde_json::Value) -> Envelope {
        Envelope {
            kind: MessageKind::Request as i32,
            method: method.to_string(),
            tenant_id: uuid::Uuid::nil().to_string(),
            traceparent: "00-trace-span-01".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_scopes: vec!["tenant:admin".to_string()],
            ..Default::default()
        }
    }

    fn usuario(ativo: bool) -> AuthUser {
        AuthUser {
            id: 7,
            username: "maria".to_string(),
            email: "maria@exemplo.com".to_string(),
            password_hash: String::new(),
            first_name: "Maria".to_string(),
            last_name: String::new(),
            is_active: ativo,
            is_staff: false,
            is_superuser: false,
            last_login: None,
            date_joined: chrono::Utc::now(),
        }
    }

    fn corpo(resp: &Envelope) -> serde_json::Value {
        serde_json::from_slice(&resp.payload).unwrap()
    }

    // -- solicitar ------------------------------------------------------------

    #[tokio::test]
    async fn conta_inexistente_nao_registra_nem_audita() {
        let mut store = MockAuthStore::new();
        store.expect_buscar_por_login().returning(|_| Ok(None));
        store.expect_registrar_redefinicao_senha().never();
        let mut audit = MockAuditPort::new();
        audit.expect_publish_security().never();
        let env = envelope_com_payload(
            "SolicitarRedefinicaoSenha",
            serde_json::json!({ "login": "ninguem@x.com", "token_hash": HASH }),
        );

        let resp = handler_solicitar_redefinicao_senha(&store, &audit, env).await;

        // Resposta de sucesso: quem decide o que o cliente vê é a borda, e ela
        // responde "aceito" nos dois casos.
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        assert_eq!(corpo(&resp)["enviar"], false);
    }

    #[tokio::test]
    async fn conta_desativada_nao_recebe_link() {
        let mut store = MockAuthStore::new();
        store
            .expect_buscar_por_login()
            .returning(|_| Ok(Some(usuario(false))));
        store.expect_registrar_redefinicao_senha().never();
        let audit = MockAuditPort::new();
        let env = envelope_com_payload(
            "SolicitarRedefinicaoSenha",
            serde_json::json!({ "login": "maria", "token_hash": HASH }),
        );

        let resp = handler_solicitar_redefinicao_senha(&store, &audit, env).await;

        assert_eq!(corpo(&resp)["enviar"], false);
    }

    #[tokio::test]
    async fn conta_ativa_registra_o_hash_e_pede_o_envio() {
        let mut store = MockAuthStore::new();
        store
            .expect_buscar_por_login()
            .returning(|_| Ok(Some(usuario(true))));
        store
            .expect_registrar_redefinicao_senha()
            .withf(|uid, hash, _| *uid == 7 && hash == HASH)
            .times(1)
            .returning(|_, _, _| Ok(()));
        let mut audit = MockAuditPort::new();
        audit
            .expect_publish_security()
            .times(1)
            .returning(|_, _, _, _, _, _, _| ());
        let env = envelope_com_payload(
            "SolicitarRedefinicaoSenha",
            serde_json::json!({ "login": "maria", "token_hash": HASH }),
        );

        let resp = handler_solicitar_redefinicao_senha(&store, &audit, env).await;

        let c = corpo(&resp);
        assert_eq!(c["enviar"], true);
        assert_eq!(c["email"], "maria@exemplo.com");
        assert_eq!(c["nome"], "Maria");
    }

    #[tokio::test]
    async fn hash_malformado_nem_consulta_a_conta() {
        let mut store = MockAuthStore::new();
        store.expect_buscar_por_login().never();
        let audit = MockAuditPort::new();
        let env = envelope_com_payload(
            "SolicitarRedefinicaoSenha",
            serde_json::json!({ "login": "maria", "token_hash": "token-em-claro" }),
        );

        let resp = handler_solicitar_redefinicao_senha(&store, &audit, env).await;

        assert_eq!(resp.kind, MessageKind::Error as i32);
    }

    // -- redefinir ------------------------------------------------------------

    #[tokio::test]
    async fn senha_curta_e_recusada_sem_gastar_o_link() {
        let mut store = MockAuthStore::new();
        store.expect_redefinir_senha().never();
        let audit = MockAuditPort::new();
        let env = envelope_com_payload(
            "RedefinirSenha",
            serde_json::json!({ "token_hash": HASH, "password": "123" }),
        );

        let resp = handler_redefinir_senha(&store, &audit, env).await;

        assert_eq!(resp.error.unwrap().code, "VALIDATION_FAILED");
    }

    #[tokio::test]
    async fn link_que_nao_vale_e_conflito_nao_validacao() {
        // A tela diz "peça um link novo" para este e "escolha outra senha"
        // para a senha fraca: os códigos precisam ser diferentes.
        let mut store = MockAuthStore::new();
        store.expect_redefinir_senha().returning(|_, _| Ok(None));
        let mut audit = MockAuditPort::new();
        audit.expect_publish_security().never();
        let env = envelope_com_payload(
            "RedefinirSenha",
            serde_json::json!({ "token_hash": HASH, "password": "senha-nova-boa" }),
        );

        let resp = handler_redefinir_senha(&store, &audit, env).await;

        assert_eq!(resp.error.unwrap().code, "CONFLICT");
    }

    #[tokio::test]
    async fn senha_trocada_devolve_o_usuario_e_audita() {
        let mut store = MockAuthStore::new();
        store
            .expect_redefinir_senha()
            .withf(|hash, senha_hash| hash == HASH && senha_hash.starts_with("$argon2"))
            .times(1)
            .returning(|_, _| Ok(Some(7)));
        let mut audit = MockAuditPort::new();
        audit
            .expect_publish_security()
            .times(1)
            .returning(|_, _, _, _, _, _, _| ());
        let env = envelope_com_payload(
            "RedefinirSenha",
            serde_json::json!({ "token_hash": HASH, "password": "senha-nova-boa" }),
        );

        let resp = handler_redefinir_senha(&store, &audit, env).await;

        assert_eq!(corpo(&resp)["user_id"], 7);
    }

    // -- reenviar convite -----------------------------------------------------

    #[tokio::test]
    async fn convite_aceito_ou_revogado_nao_volta() {
        let mut store = MockTenantStore::new();
        store.expect_renovar_convite().returning(|_, _, _| Ok(None));
        let mut audit = MockAuditPort::new();
        audit.expect_publish().never();
        let env = envelope_com_payload(
            "ReenviarConvite",
            serde_json::json!({ "invite_id": uuid::Uuid::now_v7().to_string() }),
        );

        let resp = handler_reenviar_convite(&store, &audit, env).await;

        assert_eq!(resp.error.unwrap().code, "CONFLICT");
    }

    #[tokio::test]
    async fn convite_renovado_volta_com_o_token_para_o_email() {
        let mut store = MockTenantStore::new();
        store.expect_renovar_convite().returning(|_, id, expira| {
            Ok(Some(TenantInvite {
                id,
                tenant_id: uuid::Uuid::nil(),
                email: "convidado@x.com".to_string(),
                name: "Convidado".to_string(),
                role: "staff".to_string(),
                module_permissions: serde_json::json!([]),
                flow_permissions: serde_json::json!([]),
                token: "tok".to_string(),
                expires_at: expira,
                used: false,
                created_at: chrono::Utc::now(),
                created_by_id: None,
            }))
        });
        store.expect_buscar_por_id().returning(|_| Ok(None));
        let mut audit = MockAuditPort::new();
        audit.expect_publish().times(1).returning(|_, _, _, _| ());
        let env = envelope_com_payload(
            "ReenviarConvite",
            serde_json::json!({ "invite_id": uuid::Uuid::now_v7().to_string() }),
        );

        let resp = handler_reenviar_convite(&store, &audit, env).await;

        let c = corpo(&resp);
        assert_eq!(c["invite"]["token"], "tok");
        assert_eq!(c["invite"]["email"], "convidado@x.com");
    }
}

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
            mimetype_midia: None,
            nome_arquivo_midia: None,
            tamanho_midia: None,
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
    /// P2: rolar para cima pede o que veio ANTES da bolha mais antiga da tela.
    #[tokio::test]
    async fn get_thread_repassa_o_cursor_da_rolagem() {
        let mut store = MockAtendimentoStore::new();
        store
            .expect_listar_mensagens()
            .times(1)
            .returning(|_, _, _, _, before_id| {
                assert_eq!(before_id, Some(42));
                Ok(vec![])
            });
        let env = envelope_com_payload(
            "GetThread",
            serde_json::json!({ "atendimento_id": 1, "before_id": 42 }),
        );

        let resp = handler_get_thread(&store, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
    }

    #[tokio::test]
    async fn get_thread_returns_messages() {
        // Arrange
        let mut store = MockAtendimentoStore::new();
        store
            .expect_listar_mensagens()
            .times(1)
            .returning(|_, _, _, _, _| Ok(vec![mensagem_fake(1)]));
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
            .returning(|_, _, _, _, _, _, _, _| Ok(mensagem_fake(7)));
        let env = envelope_com_payload(
            "PersistMessage",
            serde_json::json!({ "atendimento_id": 1, "content": "oi", "sender_id": "5511999998888" }),
        );

        // Act
        let resp = handler_persist_message(&store, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(body["message_id"].as_i64().unwrap(), 7);
    }

    /// FAIL-CLOSED: sem `atendimento_id` o handler rejeita, em vez de gravar a
    /// mensagem no atendimento de id 1 do tenant (default silencioso removido).
    #[tokio::test]
    async fn persist_message_sem_atendimento_id_e_rejeitado() {
        // Arrange: o store não pode nem ser chamado.
        let mut store = MockAtendimentoStore::new();
        store.expect_persistir_mensagem().never();
        let env = envelope_com_payload(
            "PersistMessage",
            serde_json::json!({ "content": "oi", "sender_id": "5511999998888" }),
        );

        // Act
        let resp = handler_persist_message(&store, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Error as i32);
    }

    /// FAIL-CLOSED: sem `sender_id` o handler rejeita — o remetente decide a
    /// autoria da mensagem no chat e `gerado_por_ia`; não pode ter default.
    #[tokio::test]
    async fn persist_message_sem_sender_id_e_rejeitado() {
        // Arrange
        let mut store = MockAtendimentoStore::new();
        store.expect_persistir_mensagem().never();
        let env = envelope_com_payload(
            "PersistMessage",
            serde_json::json!({ "atendimento_id": 1, "content": "oi" }),
        );

        // Act
        let resp = handler_persist_message(&store, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Error as i32);
    }

    /// O stanzaId e a citação do webhook chegam ao store em `OrigemMensagem` —
    /// é o que sustenta a idempotência da reentrega e o "responder a" no chat.
    #[tokio::test]
    async fn persist_message_repassa_origem_do_provedor() {
        // Arrange
        let mut store = MockAtendimentoStore::new();
        store
            .expect_persistir_mensagem()
            .withf(|_, _, _, _, _, _, _, origem| {
                origem.message_id_whatsapp.as_deref() == Some("3EB0ABC")
                    && origem.citando_message_id_whatsapp.as_deref() == Some("3EB0PAI")
                    && origem.ja_entregue
            })
            .times(1)
            .returning(|_, _, _, _, _, _, _, _| Ok(mensagem_fake(11)));
        let env = envelope_com_payload(
            "PersistMessage",
            serde_json::json!({
                "atendimento_id": 1,
                "content": "oi",
                "sender_id": "atendente",
                "message_id_whatsapp": "3EB0ABC",
                "citando_message_id_whatsapp": "3EB0PAI",
                "ja_entregue": true,
            }),
        );

        // Act
        let resp = handler_persist_message(&store, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Reply as i32);
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
                    atendente_id: Some(3),
                    atendente_nome: Some("Ana".to_string()),
                    atendente_usuario_id: None,
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

    /// HAPPY PATH: atualizar_sentimento repassa nota/label ao store.
    #[tokio::test]
    async fn atualizar_sentimento_repassa_ao_store() {
        let mut store = MockAtendimentoStore::new();
        store
            .expect_atualizar_sentimento()
            .times(1)
            .withf(|_, atendimento_id, nota, label| {
                *atendimento_id == 42 && *nota == 7 && label == "positivo"
            })
            .returning(|_, _, _, _| Ok(()));
        let env = envelope_com_payload(
            "AtualizarSentimentoAtendimento",
            serde_json::json!({ "atendimento_id": 42, "nota": 7, "label": "positivo" }),
        );

        let resp = handler_atualizar_sentimento(&store, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
    }

    /// FAIL-CLOSED: atualizar_sentimento sem atendimento_id vira erro de validação.
    #[tokio::test]
    async fn atualizar_sentimento_sem_atendimento_id_valida() {
        let store = MockAtendimentoStore::new();
        let env = envelope_com_payload(
            "AtualizarSentimentoAtendimento",
            serde_json::json!({ "nota": 7, "label": "positivo" }),
        );
        let resp = handler_atualizar_sentimento(&store, env).await;
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
            .returning(|_, _, _, _, _, _, _, _| {
                Err(infrastructure_postgres::DbError::ConfigError(
                    "falha simulada".to_string(),
                ))
            });
        let env = envelope_com_payload(
            "PersistMessage",
            serde_json::json!({ "atendimento_id": 1, "content": "x", "sender_id": "contato" }),
        );

        // Act
        let resp = handler_persist_message(&store, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Error as i32);
        let err = resp.error.expect("deveria ter envelope de erro");
        assert_eq!(err.category, contracts::ErrorCategory::Internal as i32);
    }

    /// P1: o recorte pedido pelo app (busca, "minhas", não lidas) chega inteiro
    /// ao repositório — filtrar no cliente esconderia a conversa não baixada.
    #[tokio::test]
    async fn list_atendimentos_repassa_o_recorte_da_busca() {
        let mut store = MockAtendimentoStore::new();
        store
            .expect_listar_atendimentos()
            .times(1)
            .returning(|_, _, _, filtro, _| {
                assert_eq!(filtro.busca, "5531");
                assert!(filtro.somente_meus);
                assert!(filtro.somente_nao_lidos);
                assert_eq!(filtro.prioridade, "alta");
                assert_eq!(filtro.etiqueta_id, Some(9));
                assert_eq!(filtro.atendente_id, Some(-1));
                Ok(vec![])
            });
        let env = envelope_com_payload(
            "ListAtendimentos",
            serde_json::json!({
                "busca": "  5531  ",
                "somente_meus": true,
                "somente_nao_lidos": true,
                "prioridade": "alta",
                "etiqueta_id": 9,
                "atendente_id": -1,
            }),
        );

        let resp = handler_list_atendimentos(&store, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
    }

    /// HAPPY PATH: list_atendimentos devolve Reply com o array de atendimentos.
    #[tokio::test]
    async fn list_atendimentos_returns_reply() {
        // Arrange
        let mut store = MockAtendimentoStore::new();
        store
            .expect_listar_atendimentos()
            .times(1)
            .returning(|_, _, _, _, _| Ok(vec![]));
        let env = envelope_com_payload("ListAtendimentos", serde_json::json!({}));

        // Act
        let resp = handler_list_atendimentos(&store, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert!(body["atendimentos"].is_array());
    }

    /// B6: a listagem leva as não lidas de cada conversa.
    #[tokio::test]
    async fn list_atendimentos_leva_as_nao_lidas() {
        let mut store = MockAtendimentoStore::new();
        store
            .expect_listar_atendimentos()
            .times(1)
            .returning(|_, _, _, _, _| {
                let a: infrastructure_postgres::atendimentos::atendimentos::Atendimento =
                    serde_json::from_value(serde_json::json!({
                        "id": 7, "tenant_id": uuid::Uuid::nil(), "contato_id": 1,
                        "departamento_id": null, "fluxo_atendimento_id": null,
                        "status": "fila", "etapa_atual_id": null,
                        "data_inicio": "2026-09-13T10:00:00Z", "data_fim": null,
                        "data_ultima_mensagem": null, "assunto": null, "prioridade": "normal",
                        "atendente_humano_id": null, "contexto_conversa": {},
                        "historico_status": [], "tags": [], "avaliacao": null, "feedback": null,
                        "data_primeira_resposta": null, "bot_pode_atender": true,
                        "sentimento_nota": null, "sentimento_label": null
                    }))
                    .expect("atendimento de teste");
                Ok(vec![a])
            });
        store
            .expect_contar_nao_lidas()
            .times(1)
            .withf(|_, ids| ids == &vec![7])
            .returning(|_, _| Ok(std::collections::HashMap::from([(7, 3)])));
        store
            .expect_contatos_do_quadro()
            .times(1)
            .returning(|_, _| {
                Ok(std::collections::HashMap::from([(
                    7,
                    infrastructure_postgres::atendimentos::atendimentos::ContatoDoQuadro {
                        atendimento_id: 7,
                        nome: "Maria".into(),
                        telefone: "5511999998888".into(),
                        foto_url: String::new(),
                        revisao_pendente: false,
                    },
                )]))
            });
        let env = envelope_com_payload("ListAtendimentos", serde_json::json!({}));

        let resp = handler_list_atendimentos(&store, env).await;

        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(body["atendimentos"][0]["nao_lidas"], 3);
        // P13 — o cartão deixa de ser `Contato #id`.
        assert_eq!(body["atendimentos"][0]["contato_nome"], "Maria");
    }

    /// B6: marcar como lida devolve o espelho para o WhatsApp só quando há o
    /// que espelhar.
    #[tokio::test]
    async fn marcar_lido_devolve_o_espelho_do_whatsapp() {
        use infrastructure_postgres::atendimentos::mensagens::LeituraMarcada;
        let mut store = MockAtendimentoStore::new();
        store
            .expect_marcar_atendimento_lido()
            .times(1)
            .withf(|_, id| *id == 9)
            .returning(|_, _| {
                Ok(LeituraMarcada {
                    marcadas: 2,
                    message_ids_whatsapp: vec!["ABC".into(), "DEF".into()],
                    instance_id: Some(4),
                    telefone: Some("5511999990000".into()),
                })
            });
        let env = envelope_com_payload(
            "MarcarAtendimentoLido",
            serde_json::json!({ "atendimento_id": 9 }),
        );

        let resp = handler_marcar_atendimento_lido(&store, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(body["marcadas"], 2);
        assert_eq!(body["whatsapp"]["id"], 4);
        assert_eq!(body["whatsapp"]["message_ids"][1], "DEF");

        let sem_whatsapp = LeituraMarcada {
            marcadas: 1,
            message_ids_whatsapp: vec!["ABC".into()],
            ..Default::default()
        };
        assert!(espelho_da_leitura(&sem_whatsapp).is_null());
        assert!(espelho_da_leitura(&LeituraMarcada::default()).is_null());
    }

    #[tokio::test]
    async fn marcar_lido_sem_atendimento_e_validacao() {
        let store = MockAtendimentoStore::new();
        let env = envelope_com_payload("MarcarAtendimentoLido", serde_json::json!({}));

        let resp = handler_marcar_atendimento_lido(&store, env).await;

        assert_eq!(resp.kind, MessageKind::Error as i32);
    }

    /// B9 (N10 E6): a correção vai para o banco; a auditoria só sabe que houve.
    #[tokio::test]
    async fn feedback_de_teste_grava_a_correcao_e_audita_sem_o_texto() {
        let mut store = crate::ports::MockTreinamentoStore::new();
        store
            .expect_registrar_feedback_teste()
            .times(1)
            .withf(|_, novo| {
                novo.avaliacao == "ruim"
                    && novo.resposta_corrigida.as_deref() == Some("Não entregamos aos domingos.")
            })
            .returning(|_, _| Ok(11));
        let mut audit = crate::ports::MockAuditPort::new();
        audit
            .expect_publish()
            .times(1)
            .withf(|_, _, _, contexto| {
                contexto["houve_correcao"] == true
                    && contexto.get("resposta_correta").is_none()
                    && contexto.get("pergunta").is_none()
            })
            .returning(|_, _, _, _| ());
        let env = envelope_com_payload(
            "RegistrarFeedbackTeste",
            serde_json::json!({
                "pergunta": "entregam domingo?",
                "resposta_obtida": "Sim, todos os dias.",
                "resposta_correta": "Não entregamos aos domingos.",
                "avaliacao": "ruim",
            }),
        );

        let resp = handler_registrar_feedback_teste(&store, &audit, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(body["id"], 11);
    }

    #[tokio::test]
    async fn feedback_de_teste_recusa_avaliacao_desconhecida() {
        let store = crate::ports::MockTreinamentoStore::new();
        let audit = crate::ports::MockAuditPort::new();
        let env = envelope_com_payload(
            "RegistrarFeedbackTeste",
            serde_json::json!({
                "pergunta": "p",
                "resposta_obtida": "r",
                "avaliacao": "mais_ou_menos",
            }),
        );

        let resp = handler_registrar_feedback_teste(&store, &audit, env).await;

        assert_eq!(resp.kind, MessageKind::Error as i32);
    }

    /// B9 (N10 E2): o assunto é a intenção mais confiante, nunca vazio nem longo.
    #[test]
    fn assunto_da_analise_usa_a_intencao_mais_confiante() {
        let intents = serde_json::json!([
            { "tipo": "duvida_entrega", "confianca": 0.4 },
            { "tipo": "segunda_via_boleto", "confianca": 0.9 },
            { "tipo": "   ", "confianca": 1.0 },
        ]);
        assert_eq!(
            assunto_da_analise(&intents).as_deref(),
            Some("segunda_via_boleto")
        );
        assert_eq!(assunto_da_analise(&serde_json::json!([])), None);
        let longo = "x".repeat(250);
        assert_eq!(
            assunto_da_analise(&serde_json::json!([{ "tipo": longo, "confianca": 1 }]))
                .map(|a| a.chars().count()),
            Some(200)
        );
    }

    #[tokio::test]
    async fn anexar_analise_mensagem_repassa_o_assunto_sugerido() {
        let mut store = MockAtendimentoStore::new();
        store
            .expect_anexar_analise_mensagem()
            .times(1)
            .withf(
                |_, mensagem_id, atendimento_id, intents, entidades, assunto| {
                    *mensagem_id == 5
                        && *atendimento_id == 9
                        && intents.as_array().map(|a| a.len()) == Some(1)
                        && entidades.as_array().map(|a| a.len()) == Some(1)
                        && assunto.as_deref() == Some("segunda_via_boleto")
                },
            )
            .returning(|_, _, _, _, _, _| Ok(true));
        // P14 — a intenção confiante vira etiqueta, auditada.
        store
            .expect_aplicar_etiquetas_da_analise()
            .times(1)
            .withf(|_, atendimento_id, intencoes, piso| {
                *atendimento_id == 9 && intencoes.len() == 1 && (*piso - 0.8).abs() < 1e-9
            })
            .returning(|_, _, _, _| {
                Ok(vec![
                    infrastructure_postgres::atendimentos::etiquetas::EtiquetaAplicadaPelaIa {
                        id: 4,
                        nome: "Segunda via".into(),
                        confianca: 0.9,
                    },
                ])
            });
        // P15 — a "cidade" (0,8 = piso) entra nos extras do contato.
        store
            .expect_enriquecer_contato()
            .times(1)
            .withf(|_, atendimento_id, valores| {
                *atendimento_id == 9 && valores.extras.contains_key("cidade")
            })
            .returning(|_, _, _| Ok((3, vec!["metadados.entidades".to_string()])));
        let mut audit = crate::ports::MockAuditPort::new();
        audit
            .expect_publish()
            .times(1)
            .withf(|_, evento, _, _| evento == "etiqueta.aplicada_por_ia")
            .returning(|_, _, _, _| ());
        audit
            .expect_publish()
            .times(1)
            .withf(|_, evento, _, ctx| {
                // Os NOMES dos campos, nunca os valores.
                evento == "contato.enriquecido_por_ia" && !ctx.to_string().contains("Recife")
            })
            .returning(|_, _, _, _| ());
        let env = envelope_com_payload(
            "AnexarAnaliseMensagem",
            serde_json::json!({
                "mensagem_id": 5,
                "atendimento_id": 9,
                "intents": [{ "tipo": "segunda_via_boleto", "confianca": 0.9 }],
                "entidades": [{ "tipo": "cidade", "valor": "Recife", "confianca": 0.8 }],
            }),
        );

        let resp = handler_anexar_analise_mensagem(&store, &audit, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(body["assunto_definido"], true);
        assert_eq!(body["etiquetas_aplicadas"], 1);
    }

    /// B9 (N10 E5): a chave tem de ser das que o servidor gera.
    #[tokio::test]
    async fn criar_treinamento_com_arquivo_recusa_chave_de_fora() {
        let store = crate::ports::MockTreinamentoStore::new();
        let audit = crate::ports::MockAuditPort::new();
        let env = envelope_com_payload(
            "CriarTreinamentoComArquivo",
            serde_json::json!({
                "tag": "horarios",
                "grupo": "atendimento",
                "chave": "outbound/12/abc",
                "nome_arquivo": "horarios.pdf",
                "mimetype": "application/pdf",
                "bytes": 2048,
            }),
        );

        let resp = handler_criar_treinamento_com_arquivo(&store, &audit, env).await;

        assert_eq!(resp.kind, MessageKind::Error as i32);
    }

    #[tokio::test]
    async fn criar_treinamento_com_arquivo_audita_o_envio() {
        let mut store = crate::ports::MockTreinamentoStore::new();
        store
            .expect_criar_treinamento_com_arquivo()
            .times(1)
            .withf(|_, novo| novo.chave == "treinamento/xyz" && novo.bytes == 2048)
            .returning(|_, novo| {
                Ok(crate::ports::TreinamentoResumo {
                    id: 3,
                    tag: novo.tag,
                    grupo: novo.grupo,
                    arquivo_nome: novo.nome_arquivo,
                    extracao_status: "pendente".to_string(),
                    ..Default::default()
                })
            });
        let mut audit = crate::ports::MockAuditPort::new();
        audit
            .expect_publish()
            .times(1)
            .withf(|_, _, _, contexto| {
                contexto["nome_arquivo"] == "horarios.pdf" && contexto["bytes"] == 2048
            })
            .returning(|_, _, _, _| ());
        let env = envelope_com_payload(
            "CriarTreinamentoComArquivo",
            serde_json::json!({
                "tag": "horarios",
                "grupo": "atendimento",
                "chave": "treinamento/xyz",
                "nome_arquivo": "horarios.pdf",
                "mimetype": "application/pdf",
                "bytes": 2048,
            }),
        );

        let resp = handler_criar_treinamento_com_arquivo(&store, &audit, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(body["extracao_status"], "pendente");
    }

    /// B9 (N10 E5): falha de extração vai para a trilha com o motivo; sucesso não.
    #[tokio::test]
    async fn registrar_extracao_audita_so_a_falha() {
        use infrastructure_postgres::treinamento::treinamentos::ResultadoExtracao;
        let mut store = crate::ports::MockTreinamentoStore::new();
        store
            .expect_registrar_extracao_treinamento()
            .times(2)
            .returning(|_, _, _| Ok(true));
        let mut audit = crate::ports::MockAuditPort::new();
        audit
            .expect_publish()
            .times(1)
            .withf(|_, _, _, contexto| contexto["motivo"] == "o PDF está protegido por senha")
            .returning(|_, _, _, _| ());

        let falha = envelope_com_payload(
            "RegistrarExtracaoTreinamento",
            serde_json::json!({ "treinamento_id": 3, "erro": "o PDF está protegido por senha" }),
        );
        let resp = handler_registrar_extracao_treinamento(&store, &audit, falha).await;
        assert_eq!(resp.kind, MessageKind::Reply as i32);

        let sucesso = envelope_com_payload(
            "RegistrarExtracaoTreinamento",
            serde_json::json!({ "treinamento_id": 3, "texto": "Abrimos às 8h." }),
        );
        let resp = handler_registrar_extracao_treinamento(&store, &audit, sucesso).await;
        assert_eq!(resp.kind, MessageKind::Reply as i32);

        let vazio = envelope_com_payload(
            "RegistrarExtracaoTreinamento",
            serde_json::json!({ "treinamento_id": 3 }),
        );
        let resp = handler_registrar_extracao_treinamento(&store, &audit, vazio).await;
        assert_eq!(resp.kind, MessageKind::Error as i32);
        let _ = ResultadoExtracao::Texto(String::new());
    }

    /// B10 (N11 E5): documento vira dígitos com tamanho certo; UF, duas letras.
    #[test]
    fn dados_do_cliente_normaliza_e_recusa() {
        let ok = dados_do_cliente(&serde_json::json!({
            "nome_fantasia": " Padaria Sol ",
            "tipo": "PJ",
            "cnpj": "12.345.678/0001-90",
            "uf": "pe",
            "cep": "50000-000",
            "site": "",
        }))
        .expect("cliente válido");
        assert_eq!(ok.nome_fantasia, "Padaria Sol");
        assert_eq!(ok.tipo.as_deref(), Some("pj"));
        assert_eq!(ok.cnpj.as_deref(), Some("12345678000190"));
        assert_eq!(ok.uf.as_deref(), Some("PE"));
        assert_eq!(ok.cep.as_deref(), Some("50000000"));
        assert_eq!(ok.site, None);

        assert!(dados_do_cliente(&serde_json::json!({ "nome_fantasia": "" })).is_err());
        assert!(
            dados_do_cliente(&serde_json::json!({ "nome_fantasia": "x", "cnpj": "123" })).is_err()
        );
        assert!(
            dados_do_cliente(&serde_json::json!({ "nome_fantasia": "x", "uf": "Pernambuco" }))
                .is_err()
        );
        assert!(
            dados_do_cliente(&serde_json::json!({ "nome_fantasia": "x", "tipo": "ong" })).is_err()
        );
    }

    /// B10: a trilha do cadastro não leva documento nem nome.
    #[tokio::test]
    async fn create_cliente_audita_sem_dado_protegido() {
        let mut store = MockClienteStore::new();
        store.expect_criar_cliente().times(1).returning(|_, dados| {
            Ok(infrastructure_postgres::clientes::clientes::ClienteResumo {
                id: 8,
                nome_fantasia: dados.nome_fantasia,
                tipo: dados.tipo.unwrap_or_default(),
                cnpj: dados.cnpj.unwrap_or_default(),
                ativo: true,
                ..Default::default()
            })
        });
        let mut audit = crate::ports::MockAuditPort::new();
        audit
            .expect_publish()
            .times(1)
            .withf(|_, _, _, contexto| {
                contexto["id"] == 8
                    && contexto.get("cnpj").is_none()
                    && contexto.get("nome").is_none()
            })
            .returning(|_, _, _, _| ());
        let env = envelope_com_payload(
            "CreateCliente",
            serde_json::json!({ "nome_fantasia": "Padaria Sol", "tipo": "pj", "cnpj": "12345678000190" }),
        );

        let resp = handler_create_cliente(&store, &audit, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(body["cnpj"], "12345678000190");
    }

    /// B10: vínculo com contato de outro tenant é "não encontrado" e não audita.
    #[tokio::test]
    async fn vincular_contato_de_fora_nao_audita() {
        let mut store = MockClienteStore::new();
        store
            .expect_vincular_contato_cliente()
            .times(1)
            .returning(|_, _, _, _| Ok(false));
        let audit = crate::ports::MockAuditPort::new();
        let env = envelope_com_payload(
            "VincularContatoCliente",
            serde_json::json!({ "cliente_id": 1, "contato_id": 999, "vincular": true }),
        );

        let resp = handler_vincular_contato_cliente(&store, &audit, env).await;

        assert_eq!(resp.kind, MessageKind::Error as i32);
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

        // Gravação de dado pessoal de terceiro tem de deixar rastro — e o rastro
        // não pode reproduzir o telefone, que é justamente o dado protegido.
        let mut audit = crate::ports::MockAuditPort::new();
        audit
            .expect_publish()
            .withf(|_, event, _, contexto| {
                event == "contato_gravado" && contexto.get("telefone").is_none()
            })
            .times(1)
            .returning(|_, _, _, _| ());

        // Act
        let resp = handler_upsert_contact(&store, &audit, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(body["id"].as_i64().unwrap(), 3);
    }

    // --- N7.2: extrair_action_id_opcional + repasse ao store ---

    #[test]
    fn extrair_action_id_opcional_ausente_e_none() {
        assert!(extrair_action_id_opcional(&serde_json::json!({})).is_none());
    }

    #[test]
    fn extrair_action_id_opcional_vazio_e_none() {
        assert!(extrair_action_id_opcional(&serde_json::json!({ "action_id": "" })).is_none());
    }

    #[test]
    fn extrair_action_id_opcional_malformado_e_none_sem_falhar() {
        assert!(
            extrair_action_id_opcional(&serde_json::json!({ "action_id": "nao-e-um-uuid" }))
                .is_none()
        );
    }

    #[test]
    fn extrair_action_id_opcional_valido_e_some() {
        let id = uuid::Uuid::now_v7();
        let extraido =
            extrair_action_id_opcional(&serde_json::json!({ "action_id": id.to_string() }));
        assert_eq!(extraido, Some(id));
    }

    /// `SendOutboundMessage` repassa o `action_id` do payload ao store, para o
    /// dedupe atômico do adapter (N7.2).
    #[tokio::test]
    async fn send_outbound_message_repassa_action_id_ao_store() {
        let id = uuid::Uuid::now_v7();
        let mut store = MockAtendimentoStore::new();
        store
            .expect_persistir_mensagem()
            .withf(move |_, _, _, _, remetente, _, action_id, _| {
                *remetente == *"atendente" && *action_id == Some(id)
            })
            .times(1)
            .returning(|_, _, _, _, _, _, _, _| Ok(mensagem_fake(9)));
        let env = envelope_com_payload(
            "SendOutboundMessage",
            serde_json::json!({ "atendimento_id": 1, "conteudo": "oi", "action_id": id.to_string() }),
        );

        let resp = handler_send_outbound_message(&store, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
    }

    /// `SendOutboundMessage` sem `action_id` (cliente antigo) segue repassando
    /// `None` ao store — comportamento pré-N7.2 preservado.
    #[tokio::test]
    async fn send_outbound_message_sem_action_id_repassa_none() {
        let mut store = MockAtendimentoStore::new();
        store
            .expect_persistir_mensagem()
            .withf(|_, _, _, _, _, _, action_id, _| action_id.is_none())
            .times(1)
            .returning(|_, _, _, _, _, _, _, _| Ok(mensagem_fake(10)));
        let env = envelope_com_payload(
            "SendOutboundMessage",
            serde_json::json!({ "atendimento_id": 1, "conteudo": "oi" }),
        );

        let resp = handler_send_outbound_message(&store, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
    }

    /// `MoveAtendimentoEtapa` repassa o `action_id` do payload ao store.
    #[tokio::test]
    async fn move_atendimento_etapa_repassa_action_id_ao_store() {
        let id = uuid::Uuid::now_v7();
        let mut store = MockAtendimentoStore::new();
        store
            .expect_mover_etapa_atendimento()
            .withf(move |_, _, _, _, action_id| *action_id == Some(id))
            .times(1)
            .returning(|_, _, _, _, _| Ok(()));
        let env = envelope_com_payload(
            "MoveAtendimentoEtapa",
            serde_json::json!({ "atendimento_id": 1, "etapa_destino_id": 2, "action_id": id.to_string() }),
        );

        let resp = handler_move_atendimento_etapa(&store, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
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
            .returning(|_, _, _, _, _, _, _, _| Ok(false));
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
    use crate::ports::{MockAuditPort, MockOperacionalStore, MockQuotaStore};
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

    /// `delta` projeta o custo da operação em curso: quem está DENTRO do limite mas
    /// o estouraria com este arquivo é barrado (e auditado) igual a quem já estourou.
    /// Sem isso um único upload grande passa livre, porque `verificar_quota` só olha
    /// o uso já acumulado.
    #[tokio::test]
    async fn check_quota_com_delta_barra_quem_estouraria_o_limite() {
        let mut store = MockQuotaStore::new();
        store.expect_verificar_quota().times(1).returning(|_, _| {
            Ok(serde_json::json!({
                "recurso": "storage",
                "uso_atual": 900,
                "limite": 1_000,
                "excedido": false,
                "inadimplente": false,
            }))
        });
        let mut audit = MockAuditPort::new();
        audit
            .expect_publish()
            .withf(|_, event, _, _| event == "quota.excedida")
            .times(1)
            .returning(|_, _, _, _| ());
        let env = envelope_com_payload(
            "CheckQuota",
            // 900 + 200 = 1100 > 1000
            serde_json::json!({ "recurso": "storage", "auditar": true, "delta": 200 }),
        );

        let resp = handler_check_quota(&store, &audit, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let payload: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(payload["excedido"], true);
        assert_eq!(payload["excedido_projetado"], true);
        assert_eq!(payload["delta_avaliado"], 200);
    }

    /// Delta que ainda cabe no limite não bloqueia nem audita.
    #[tokio::test]
    async fn check_quota_com_delta_que_cabe_no_limite_nao_bloqueia() {
        let mut store = MockQuotaStore::new();
        store.expect_verificar_quota().times(1).returning(|_, _| {
            Ok(serde_json::json!({
                "recurso": "storage",
                "uso_atual": 900,
                "limite": 1_000,
                "excedido": false,
                "inadimplente": false,
            }))
        });
        let mut audit = MockAuditPort::new();
        audit.expect_publish().never();
        let env = envelope_com_payload(
            "CheckQuota",
            serde_json::json!({ "recurso": "storage", "auditar": true, "delta": 50 }),
        );

        let resp = handler_check_quota(&store, &audit, env).await;

        let payload: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(payload["excedido"], false);
        assert_eq!(payload["excedido_projetado"], false);
    }

    /// Plano sem limite configurado (`limite: null`) nunca bloqueia, mesmo com delta
    /// grande — mesma postura conservadora de `verificar_quota`.
    #[tokio::test]
    async fn check_quota_com_delta_e_limite_nulo_nao_bloqueia() {
        let mut store = MockQuotaStore::new();
        store.expect_verificar_quota().times(1).returning(|_, _| {
            Ok(serde_json::json!({
                "recurso": "storage",
                "uso_atual": 5_000,
                "limite": serde_json::Value::Null,
                "excedido": false,
                "inadimplente": false,
            }))
        });
        let mut audit = MockAuditPort::new();
        audit.expect_publish().never();
        let env = envelope_com_payload(
            "CheckQuota",
            serde_json::json!({ "recurso": "storage", "auditar": true, "delta": 10_000_000 }),
        );

        let resp = handler_check_quota(&store, &audit, env).await;

        let payload: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(payload["excedido_projetado"], false);
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

    // --- N7.1: RegisterStorageUsage ---

    #[tokio::test]
    async fn register_storage_usage_rejects_tenant_id_invalido_sem_tocar_a_store() {
        let mut store = MockQuotaStore::new();
        store.expect_registrar_uso_storage().never();
        let env = Envelope {
            tenant_id: "nao-e-um-uuid".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({ "delta_bytes": 100 })).unwrap(),
            ..Default::default()
        };

        let resp = handler_register_storage_usage(&store, env).await;

        assert_eq!(resp.kind, MessageKind::Error as i32);
        assert_eq!(resp.error.unwrap().code, "VALIDATION_FAILED");
    }

    #[tokio::test]
    async fn register_storage_usage_rejects_delta_ausente_ou_zero() {
        let mut store = MockQuotaStore::new();
        store.expect_registrar_uso_storage().never();

        for payload in [
            serde_json::json!({}),
            serde_json::json!({ "delta_bytes": 0 }),
        ] {
            let env = envelope_com_payload("RegisterStorageUsage", payload);
            let resp = handler_register_storage_usage(&store, env).await;
            assert_eq!(resp.kind, MessageKind::Error as i32);
        }
    }

    /// `total_bytes` é um medidor de uso CORRENTE, não um acumulado: a purga de
    /// mídia (retenção) devolve espaço ao tenant com delta negativo. Sem isto o
    /// enforce de quota bloquearia uploads legítimos de um bucket já esvaziado.
    #[tokio::test]
    async fn register_storage_usage_aceita_delta_negativo_da_purga() {
        let mut store = MockQuotaStore::new();
        store
            .expect_registrar_uso_storage()
            .times(1)
            .returning(|_, delta| Ok((1_000 + delta).max(0)));
        let env = envelope_com_payload(
            "RegisterStorageUsage",
            serde_json::json!({ "delta_bytes": -400 }),
        );

        let resp = handler_register_storage_usage(&store, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let payload: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(payload["total_bytes"], 600);
    }

    #[tokio::test]
    async fn register_storage_usage_sucesso_retorna_total_bytes() {
        let mut store = MockQuotaStore::new();
        store
            .expect_registrar_uso_storage()
            .times(1)
            .returning(|_, delta| Ok(1_000 + delta));
        let env = envelope_com_payload(
            "RegisterStorageUsage",
            serde_json::json!({ "delta_bytes": 500 }),
        );

        let resp = handler_register_storage_usage(&store, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let payload: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(payload["total_bytes"], 1_500);
    }

    #[tokio::test]
    async fn register_storage_usage_erro_da_store_retorna_database_error() {
        let mut store = MockQuotaStore::new();
        store
            .expect_registrar_uso_storage()
            .times(1)
            .returning(|_, _| Err(infrastructure_postgres::DbError::NotFound));
        let env = envelope_com_payload(
            "RegisterStorageUsage",
            serde_json::json!({ "delta_bytes": 10 }),
        );

        let resp = handler_register_storage_usage(&store, env).await;

        assert_eq!(resp.kind, MessageKind::Error as i32);
    }

    // --- N7.1: CreateDepartamento (caller de quota antes do INSERT) ---

    #[tokio::test]
    async fn create_departamento_rejects_nome_vazio_sem_tocar_quota_ou_store() {
        let mut quota = MockQuotaStore::new();
        quota.expect_verificar_quota().never();
        let mut operacional = MockOperacionalStore::new();
        operacional.expect_criar_departamento().never();
        let audit = MockAuditPort::new();
        let env = envelope_com_payload("CreateDepartamento", serde_json::json!({ "nome": "   " }));

        let resp = handler_create_departamento(&quota, &operacional, &audit, env).await;

        assert_eq!(resp.kind, MessageKind::Error as i32);
    }

    #[tokio::test]
    async fn create_departamento_dentro_do_limite_cria_sem_auditar() {
        let mut quota = MockQuotaStore::new();
        quota
            .expect_verificar_quota()
            .times(1)
            .returning(|_, _| Ok(serde_json::json!({ "excedido": false })));
        let mut operacional = MockOperacionalStore::new();
        operacional
            .expect_criar_departamento()
            .times(1)
            .returning(|_, nome, _| Ok(serde_json::json!({ "nome": nome })));
        let mut audit = MockAuditPort::new();
        audit.expect_publish().never();
        let env = envelope_com_payload(
            "CreateDepartamento",
            serde_json::json!({ "nome": "Financeiro" }),
        );

        let resp = handler_create_departamento(&quota, &operacional, &audit, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
    }

    /// Quota excedida em modo log-only (padrão, sem `SMARTCORE_QUOTA_ENFORCE=true`
    /// no ambiente de teste): cria mesmo assim, sem auditar — mesma postura do
    /// `CheckQuota` para o caminho de leitura (doc 08 §4.2).
    #[tokio::test]
    async fn create_departamento_excedido_log_only_cria_sem_auditar() {
        std::env::remove_var("SMARTCORE_QUOTA_ENFORCE");
        let mut quota = MockQuotaStore::new();
        quota
            .expect_verificar_quota()
            .times(1)
            .returning(|_, _| Ok(serde_json::json!({ "excedido": true })));
        let mut operacional = MockOperacionalStore::new();
        operacional
            .expect_criar_departamento()
            .times(1)
            .returning(|_, nome, _| Ok(serde_json::json!({ "nome": nome })));
        let mut audit = MockAuditPort::new();
        audit.expect_publish().never();
        let env = envelope_com_payload(
            "CreateDepartamento",
            serde_json::json!({ "nome": "Comercial" }),
        );

        let resp = handler_create_departamento(&quota, &operacional, &audit, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
    }

    /// Falha na própria checagem de quota é fail-open: segue para o INSERT.
    #[tokio::test]
    async fn create_departamento_falha_na_checagem_de_quota_e_fail_open() {
        let mut quota = MockQuotaStore::new();
        quota
            .expect_verificar_quota()
            .times(1)
            .returning(|_, _| Err(infrastructure_postgres::DbError::NotFound));
        let mut operacional = MockOperacionalStore::new();
        operacional
            .expect_criar_departamento()
            .times(1)
            .returning(|_, nome, _| Ok(serde_json::json!({ "nome": nome })));
        let audit = MockAuditPort::new();
        let env = envelope_com_payload("CreateDepartamento", serde_json::json!({ "nome": "TI" }));

        let resp = handler_create_departamento(&quota, &operacional, &audit, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
    }

    #[tokio::test]
    async fn create_departamento_erro_da_store_retorna_erro() {
        let mut quota = MockQuotaStore::new();
        quota
            .expect_verificar_quota()
            .times(1)
            .returning(|_, _| Ok(serde_json::json!({ "excedido": false })));
        let mut operacional = MockOperacionalStore::new();
        operacional
            .expect_criar_departamento()
            .times(1)
            .returning(|_, _, _| Err(infrastructure_postgres::DbError::PermissionDenied));
        let audit = MockAuditPort::new();
        let env = envelope_com_payload("CreateDepartamento", serde_json::json!({ "nome": "RH" }));

        let resp = handler_create_departamento(&quota, &operacional, &audit, env).await;

        assert_eq!(resp.kind, MessageKind::Error as i32);
    }
}
