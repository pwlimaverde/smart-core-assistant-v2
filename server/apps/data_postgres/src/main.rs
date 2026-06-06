//! Serviço data_postgres: provê RPC síncrono e pub/sub assíncrono sujeito a políticas RLS.
//! Contém o Relay de Outbox e o Consumidor de Auditoria integrados.

use contracts::{Envelope, MessageKind};
use infrastructure_postgres::{
    inserir_audit_log, inserir_audit_log_global, NewAuditLogEntry, RequestContext,
};
use redis::aio::ConnectionManager;
use sqlx::PgPool;
use transport::Server;
use uuid::Uuid;

mod outbox_relay;
use outbox_relay::OutboxRelay;

#[derive(Clone)]
struct AppState {
    pool: PgPool,
    redis_conn: ConnectionManager,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // 1. Inicializa observabilidade
    observability::init_telemetry("data_postgres", "production")
        .map_err(|e| anyhow::anyhow!(e.to_string()))?;
    tracing::info!("Iniciando serviço data_postgres...");

    // 2. Conecta ao banco de dados e roda migrations
    let pool = infrastructure_postgres::criar_pool(5).await?;
    infrastructure_postgres::inicializar_banco_dados(&pool).await?;
    tracing::info!("Banco de dados PostgreSQL conectado e migrations executadas.");

    // 3. Conecta ao Redis
    let redis_url =
        std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
    let redis_client = redis::Client::open(redis_url)?;
    let redis_conn = ConnectionManager::new(redis_client).await?;
    tracing::info!("Conexão com Redis estabelecida.");

    let state = AppState {
        pool: pool.clone(),
        redis_conn: redis_conn.clone(),
    };

    // 4. Inicia o Relay de Outbox em background
    let relay = OutboxRelay::new(pool.clone(), redis_conn.clone());
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
        redis_conn.clone(),
    );
    let audit_handle = tokio::spawn(async move {
        if let Err(e) = audit_consumer
            .run(move |evt| {
                let pool = pool_clone.clone();
                async move {
                    if let Err(err) = processar_evento_auditoria(pool, evt).await {
                        tracing::error!("Erro consolidação auditoria: {:?}", err);
                    }
                }
            })
            .await
        {
            tracing::error!("Consumidor de auditoria parou com erro crítico: {:?}", e);
        }
    });

    // 6. Inicia o Servidor RPC síncrono nos 3 protocolos
    let state_clone = state.clone();
    let state_for_get_thread = state_clone.clone();
    let state_for_persist = state_clone.clone();
    let state_for_verify = state_clone.clone();
    let state_for_upsert = state_clone.clone();
    let state_for_list = state_clone.clone();
    let state_for_create_tenant = state_clone;

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
            Box::pin(async move { handler_create_tenant(state.pool, env).await })
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

/// Consolida um evento de auditoria vindo do barramento de segurança no banco de dados.
async fn processar_evento_auditoria(
    pool: PgPool,
    evt: transport::bus::EventoBruto,
) -> anyhow::Result<()> {
    let envelope = evt.desserializar::<observability::AuditLogPayload>()?;

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
        // Ação de Tenant: sujeita a isolamento RLS
        let result = infrastructure_postgres::run_in_tenant_transaction(
            &pool,
            tenant_id,
            |mut tx| async move {
                let id = inserir_audit_log(&mut tx, &entry).await?;
                Ok((id, tx))
            },
        )
        .await;
        if let Err(e) = result {
            tracing::error!(
                "Falha ao consolidar log de auditoria do tenant no Postgres: {:?}",
                e
            );
        }
    } else {
        // Ação Global: bypass RLS
        if let Err(e) = inserir_audit_log_global(&pool, &entry).await {
            tracing::error!(
                "Falha ao consolidar log de auditoria global no Postgres: {:?}",
                e
            );
        }
    }

    Ok(())
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

    let ctx = RequestContext {
        tenant_id,
        user_id: 1,
        user_scopes: vec!["atendimentos:read".to_string()],
        flow_permissions: vec![],
    };
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

    let ctx = RequestContext {
        tenant_id,
        user_id: 1,
        user_scopes: vec!["atendimentos:read".to_string()],
        flow_permissions: vec![],
    };
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
async fn handler_create_tenant(pool: PgPool, env: Envelope) -> Envelope {
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
    let ctx = RequestContext {
        tenant_id,
        user_id: 1,
        user_scopes: vec!["atendimentos:write".to_string()],
        flow_permissions: vec![],
    };

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
    let ctx = RequestContext {
        tenant_id,
        user_id: 1,
        user_scopes: vec!["clientes:write".to_string()],
        flow_permissions: vec![],
    };

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

    // Busca o usuário por e-mail no banco
    let user_opt = match repo.buscar_por_email(&pool, email).await {
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

    let login_sucesso = if let Some(user) = &user_opt {
        infrastructure_postgres::verify_password(password, &user.password_hash)
    } else {
        false
    };

    if login_sucesso {
        let user = user_opt.unwrap();
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

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;
    use contracts::{Envelope, MessageKind};
    use sqlx::PgPool;
    use redis::aio::ConnectionManager;

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
        let pool = PgPool::connect(&admin_url).await.expect("Falha ao conectar Postgres");
        
        infrastructure_postgres::inicializar_banco_dados(&pool).await.unwrap();

        let redis_url = std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6380".to_string());
        let redis_client = redis::Client::open(redis_url).unwrap();
        let redis_conn = ConnectionManager::new(redis_client).await.unwrap();

        (pool, redis_conn)
    }

    #[tokio::test]
    async fn test_handler_create_tenant() {
        let (pool, _) = setup_teste().await;
        
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
        };

        let resp = handler_create_tenant(pool.clone(), req).await;
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        assert_eq!(resp.method, "CreateTenantReply");

        let resp_payload: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(resp_payload.get("status").unwrap().as_str().unwrap(), "success");
        
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
        
        let user = auth_repo.criar(&pool, &test_username, &test_email, &hash, false)
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
        };

        let resp_valido = handler_verify_credentials(pool.clone(), redis_conn.clone(), req_valido).await;
        assert_eq!(resp_valido.kind, MessageKind::Reply as i32);
        let resp_valido_payload: serde_json::Value = serde_json::from_slice(&resp_valido.payload).unwrap();
        assert_eq!(resp_valido_payload.get("id").unwrap().as_i64().unwrap(), user.id as i64);

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
        };

        let resp_invalido = handler_verify_credentials(pool.clone(), redis_conn.clone(), req_invalido).await;
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
        };

        let resp_msg = handler_persist_message(pool.clone(), req_msg).await;
        assert_eq!(resp_msg.kind, MessageKind::Reply as i32);
        
        let resp_msg_payload: serde_json::Value = serde_json::from_slice(&resp_msg.payload).unwrap();
        assert_eq!(resp_msg_payload.get("status").unwrap().as_str().unwrap(), "success");
        let msg_id = resp_msg_payload.get("message_id").unwrap().as_i64().unwrap() as i32;

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
        };

        let resp_thread = handler_get_thread(pool.clone(), req_thread).await;
        assert_eq!(resp_thread.kind, MessageKind::Reply as i32);

        let resp_thread_payload: serde_json::Value = serde_json::from_slice(&resp_thread.payload).unwrap();
        let mensagens_arr = resp_thread_payload.get("mensagens").unwrap().as_array().unwrap();
        assert!(!mensagens_arr.is_empty());
        
        let encontrada = mensagens_arr.iter().any(|m| m.get("id").unwrap().as_i64().unwrap() == msg_id as i64);
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
        };

        let resp_contato = handler_upsert_contact(pool.clone(), req_contato).await;
        assert_eq!(resp_contato.kind, MessageKind::Reply as i32);

        let resp_contato_payload: serde_json::Value = serde_json::from_slice(&resp_contato.payload).unwrap();
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
        };

        let resp_list = handler_list_atendimentos(pool.clone(), req_list).await;
        assert_eq!(resp_list.kind, MessageKind::Reply as i32);

        let resp_list_payload: serde_json::Value = serde_json::from_slice(&resp_list.payload).unwrap();
        let atendimentos_arr = resp_list_payload.get("atendimentos").unwrap().as_array().unwrap();
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

        let count: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM audit_log WHERE tenant_id = $1 AND event = 'test_event'")
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
}
