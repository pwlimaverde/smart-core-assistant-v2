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
    let state_for_upsert = state_clone;

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

async fn handler_get_thread(_pool: PgPool, env: Envelope) -> Envelope {
    // Stub de consulta de thread/atendimento
    Envelope {
        kind: MessageKind::Reply as i32,
        method: "GetThreadReply".to_string(),
        payload: vec![],
        ..env
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

            sqlx::query("INSERT INTO outbox (tenant_id, event_type, payload) VALUES ($1, $2, $3)")
                .bind(tenant_id)
                .bind("message.persisted")
                .bind(event_payload_bytes)
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
