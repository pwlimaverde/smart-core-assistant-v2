//! Serviço worker: Consumidor em background que consome do barramento e orquestra processos de domínio.

use contracts::{Envelope, MessageKind};
use redis::aio::ConnectionManager;
use std::time::Duration;
use uuid::Uuid;

use std::sync::Arc;

mod scheduler;

/// Escopos de um ator de SISTEMA (worker). O worker é um serviço interno confiável
/// que reage a eventos do barramento (não a um usuário final); as operações de
/// persistência/orquestração que ele dispara exigem escopos de escrita no
/// `data_postgres`. Usa-se o coringa `"*"` (acesso pleno intra-tenant) para não
/// acoplar o worker ao catálogo de escopos — o RLS do Postgres continua isolando
/// por `tenant_id` em todas as queries.
fn escopos_sistema() -> Vec<String> {
    vec!["*".to_string()]
}

/// Mascara um telefone para auditoria/log, preservando apenas os 4 últimos dígitos.
/// Evita expor PII completa na trilha de auditoria.
fn mascarar_telefone(phone: &str) -> String {
    let digitos: Vec<char> = phone.chars().collect();
    if digitos.len() <= 4 {
        return "*".repeat(digitos.len());
    }
    let visiveis: String = digitos[digitos.len() - 4..].iter().collect();
    format!("{}{}", "*".repeat(digitos.len() - 4), visiveis)
}

/// Chama uma RPC síncrona (`method`) em `client`, propagando `traceparent`/`causation_id`
/// e os escopos de sistema do worker. Retorna o payload desserializado da resposta ou
/// um erro (inclui o corpo de erro do serviço remoto na mensagem).
pub(crate) async fn chamar_rpc(
    client: &transport::MuxClient,
    tenant_id: &str,
    method: &str,
    payload: serde_json::Value,
    causation_id: &str,
    traceparent: &str,
) -> anyhow::Result<serde_json::Value> {
    let envelope = Envelope {
        tenant_id: tenant_id.to_string(),
        schema_version: 1,
        message_id: Uuid::now_v7().to_string(),
        causation_id: causation_id.to_string(),
        traceparent: traceparent.to_string(),
        occurred_at: chrono::Utc::now().timestamp_millis(),
        kind: MessageKind::Request as i32,
        method: method.to_string(),
        payload: serde_json::to_vec(&payload).unwrap_or_default(),
        error: None,
        auth_user_id: 0,
        auth_scopes: escopos_sistema(),
        auth_is_superuser: false,
        flow_permissions: vec![],
        user_agent: String::new(),
    };

    let resp = client.call(envelope, Duration::from_secs(5)).await?;
    if resp.kind == MessageKind::Error as i32 {
        let err_msg = resp
            .error
            .as_ref()
            .map(|e| e.message.as_str())
            .unwrap_or("Erro desconhecido");
        anyhow::bail!("RPC {} falhou: {}", method, err_msg);
    }
    Ok(serde_json::from_slice(&resp.payload)?)
}

#[derive(Clone)]
struct AppState {
    #[allow(dead_code)]
    redis_conn: Option<ConnectionManager>,
    audit_logger: observability::AuditLogger,
    pg_client: Arc<transport::MuxClient>,
    whatsapp_client: Arc<transport::MuxClient>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // 1. Inicializa observabilidade
    observability::init_telemetry("worker", "production")
        .map_err(|e| anyhow::anyhow!(e.to_string()))?;
    tracing::info!("Iniciando serviço worker...");

    // 2. Conecta ao Redis para escutar eventos
    let redis_url =
        std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
    let redis_client = redis::Client::open(redis_url)?;
    let redis_conn = ConnectionManager::new(redis_client.clone()).await?;
    tracing::info!("Conexão com Redis estabelecida.");

    // Conecta ao microserviço data_postgres (cliente gRPC persistente)
    let pg_client = Arc::new(transport::conectar_cliente("data_postgres").await?);
    tracing::info!("Cliente RPC data_postgres estabelecido.");

    // Conecta ao microserviço data_whatsapp (cliente gRPC persistente)
    let whatsapp_client = Arc::new(transport::conectar_cliente("data_whatsapp").await?);
    tracing::info!("Cliente RPC data_whatsapp estabelecido.");

    let audit_logger = observability::AuditLogger::new_with_redis(redis_conn.clone(), "worker");
    let state = AppState {
        redis_conn: Some(redis_conn),
        audit_logger,
        pg_client,
        whatsapp_client,
    };

    // 3. Inicia o consumidor do barramento (events:stream)
    let consumer = transport::bus::Consumer::new(
        transport::bus::STREAM_EVENTOS,
        "worker_group",
        "worker_consumer_1",
        redis_client.clone(),
    );

    tracing::info!("Consumidor do worker ativado e escutando eventos.");

    // 3b. Scheduler temporal (F4.3b): timeout de feedback + disparo de purga de mídia.
    // Roda em tokio::spawn paralelo ao loop de consumo do bus abaixo.
    scheduler::iniciar(state.clone());

    // Loop de consumo
    let state_clone = state.clone();
    if let Err(e) = consumer
        .run(move |evt| {
            let state = state_clone.clone();
            async move {
                if evt.event_type == "whatsapp.message.received"
                    || evt.event_type == "message.received"
                {
                    processar_mensagem_recebida(&state, evt).await?;
                } else if evt.event_type == "whatsapp.message.status" {
                    processar_status_mensagem(&state, evt).await?;
                } else if evt.event_type == "message.persisted" {
                    processar_mensagem_persistida(&state, evt).await?;
                }
                Ok(())
            }
        })
        .await
    {
        tracing::error!("Consumidor do worker parou com erro crítico: {:?}", e);
    }

    Ok(())
}

/// Consome o evento "message.received", orquestra e delega persistência ao data_postgres via RPC síncrono.
async fn processar_mensagem_recebida(
    state: &AppState,
    evt: transport::bus::EventoBruto,
) -> anyhow::Result<()> {
    let envelope = evt.desserializar::<serde_json::Value>()?;

    let raw_payload = &envelope.payload;
    let raw_event = raw_payload
        .get("raw_event")
        .ok_or_else(|| anyhow::anyhow!("raw_event ausente"))?;
    let instance_id = raw_payload
        .get("instance_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;

    // Normalização via domain_whatsapp
    let msg_normalized =
        domain_whatsapp::NormalizedMessage::parse(raw_event, envelope.tenant_id, instance_id)
            .map_err(|e| anyhow::anyhow!("Erro ao normalizar mensagem: {}", e))?;

    tracing::info!(
        event_id = %envelope.event_id,
        tenant_id = %envelope.tenant_id,
        sender = %msg_normalized.sender,
        "Worker processando evento message.received."
    );

    let pg_client = &state.pg_client;

    // 1. Resolve atendimento para contato
    let resolve_payload = serde_json::json!({
        "phone": msg_normalized.sender,
        "push_name": msg_normalized.push_name,
    });

    let resolve_envelope = Envelope {
        tenant_id: envelope.tenant_id.to_string(),
        schema_version: 1,
        message_id: Uuid::now_v7().to_string(),
        causation_id: envelope.event_id.to_string(),
        traceparent: envelope.traceparent.clone(),
        occurred_at: chrono::Utc::now().timestamp_millis(),
        kind: MessageKind::Request as i32,
        method: "ResolveAtendimentoParaContato".to_string(),
        payload: serde_json::to_vec(&resolve_payload).unwrap_or_default(),
        error: None,
        auth_user_id: 0,
        auth_scopes: escopos_sistema(),
        auth_is_superuser: false,
        flow_permissions: vec![],
        user_agent: String::new(),
    };

    let resolve_resp = pg_client
        .call(resolve_envelope, Duration::from_secs(5))
        .await?;
    if resolve_resp.kind == MessageKind::Error as i32 {
        let err_msg = resolve_resp
            .error
            .as_ref()
            .map(|e| e.message.as_str())
            .unwrap_or("Erro desconhecido");
        anyhow::bail!("Falha ao resolver atendimento: {}", err_msg);
    }

    let resolve_body: serde_json::Value = serde_json::from_slice(&resolve_resp.payload)?;
    let atendimento_id = resolve_body
        .get("atendimento_id")
        .and_then(|v| v.as_i64())
        .ok_or_else(|| anyhow::anyhow!("atendimento_id ausente na resposta"))?
        as i32;

    // 2. Persiste a mensagem no atendimento resolvido
    let persist_payload = serde_json::json!({
        "atendimento_id": atendimento_id,
        "content": msg_normalized.content,
        "tipo": match msg_normalized.media_type {
            domain_whatsapp::MediaType::Text => "texto",
            domain_whatsapp::MediaType::Image => "imagem",
            domain_whatsapp::MediaType::Audio => "audio",
            domain_whatsapp::MediaType::Video => "video",
            domain_whatsapp::MediaType::Document => "documento",
            domain_whatsapp::MediaType::Location => "localizacao",
            domain_whatsapp::MediaType::Sticker => "sticker",
            domain_whatsapp::MediaType::Contact => "contato",
            domain_whatsapp::MediaType::Other(ref o) => o,
        },
        "sender_id": msg_normalized.sender,
    });

    let persist_envelope = Envelope {
        tenant_id: envelope.tenant_id.to_string(),
        schema_version: 1,
        message_id: Uuid::now_v7().to_string(),
        causation_id: envelope.event_id.to_string(),
        traceparent: envelope.traceparent.clone(),
        occurred_at: chrono::Utc::now().timestamp_millis(),
        kind: MessageKind::Request as i32,
        method: "PersistMessage".to_string(),
        payload: serde_json::to_vec(&persist_payload).unwrap_or_default(),
        error: None,
        auth_user_id: 0,
        auth_scopes: escopos_sistema(),
        auth_is_superuser: false,
        flow_permissions: vec![],
        user_agent: String::new(),
    };

    let resp = pg_client
        .call(persist_envelope, Duration::from_secs(5))
        .await?;

    let tenant_uuid = envelope.tenant_id;

    if resp.kind == MessageKind::Error as i32 {
        let err_msg = resp
            .error
            .as_ref()
            .map(|e| e.message.as_str())
            .unwrap_or("Erro desconhecido");

        state.audit_logger.error(
            tenant_uuid,
            "mensagem.falha_persistencia",
            &format!(
                "Falha na persistência da mensagem via data_postgres RPC: {}",
                err_msg
            ),
            serde_json::json!({
                "error": err_msg,
                "sender_id": mascarar_telefone(&msg_normalized.sender),
            }),
            None,
            None,
            Some(envelope.event_id.to_string()),
        );

        anyhow::bail!(
            "Falha na persistência da mensagem via data_postgres RPC: {}",
            err_msg
        );
    }

    state.audit_logger.info(
        tenant_uuid,
        "mensagem.persistida",
        "Mensagem persistida com sucesso via worker",
        serde_json::json!({
            "atendimento_id": atendimento_id,
            "sender_id": mascarar_telefone(&msg_normalized.sender),
        }),
        None,
        None,
        Some(envelope.event_id.to_string()),
    );

    tracing::info!(
        event_id = %envelope.event_id,
        atendimento_id = atendimento_id,
        "Mensagem persistida com sucesso via RPC síncrono do data_postgres."
    );

    if let Some(ref redis_conn) = state.redis_conn {
        let channel = format!("tenant:{}:events", tenant_uuid);
        let event_payload = serde_json::json!({
            "event_type": "mensagem.recebida",
            "tenant_id": tenant_uuid.to_string(),
            "payload": {
                "atendimento_id": atendimento_id,
                "message": msg_normalized,
            }
        });

        let mut conn = redis_conn.clone();
        let payload_str = event_payload.to_string();
        let publish_res: Result<u32, _> = redis::cmd("PUBLISH")
            .arg(&channel)
            .arg(&payload_str)
            .query_async(&mut conn)
            .await;

        if let Err(e) = publish_res {
            tracing::error!("Erro ao publicar mensagem no Redis Pub/Sub: {:?}", e);
        }
    }

    // 3. Se o atendimento foi acabado de criar (is_new == true), audita a abertura
    let is_new = resolve_body
        .get("is_new")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    if is_new {
        state.audit_logger.info(
            tenant_uuid,
            "atendimento.aberto",
            "Novo atendimento aberto para o contato",
            serde_json::json!({
                "atendimento_id": atendimento_id,
                "sender_id": mascarar_telefone(&msg_normalized.sender),
            }),
            None,
            None,
            Some(envelope.event_id.to_string()),
        );

        // Política de ticket/Kanban: posiciona o atendimento recém-aberto na etapa
        // inicial do fluxo. Falha aqui não interrompe o processamento da mensagem
        // (best-effort), mas é auditada/logada.
        if let Err(e) = aplicar_politica_ticket_kanban(
            state,
            tenant_uuid,
            &envelope.event_id.to_string(),
            &envelope.traceparent,
            atendimento_id,
        )
        .await
        {
            tracing::warn!(
                atendimento_id = atendimento_id,
                "Falha ao aplicar política de ticket/Kanban: {:?}",
                e
            );
        }
    }

    // 4. Aplica o debounce de 2 segundos para regras do Bot/Kanban
    let mut is_debounce_winner = true;
    if let Some(ref redis_conn) = state.redis_conn {
        let lock_key = format!(
            "tenant:{}:lock:debounce:{}",
            tenant_uuid, msg_normalized.sender
        );
        let mut conn = redis_conn.clone();
        let set_res: Result<bool, _> = redis::cmd("SET")
            .arg(&lock_key)
            .arg("1")
            .arg("NX")
            .arg("EX")
            .arg(2) // 2 segundos
            .query_async(&mut conn)
            .await;

        match set_res {
            Ok(inserted) => {
                is_debounce_winner = inserted;
            }
            Err(e) => {
                tracing::error!("Erro no Redis ao obter lock de debounce: {:?}", e);
            }
        }
    }

    if is_debounce_winner {
        // 5. Verifica a barreira de bot
        let bot_pode_atender = resolve_body
            .get("bot_pode_atender")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let atendente_humano_id = resolve_body
            .get("atendente_humano_id")
            .and_then(|v| v.as_i64());

        if bot_pode_atender && atendente_humano_id.is_none() {
            tracing::info!(
                atendimento_id = atendimento_id,
                sender = %msg_normalized.sender,
                "Assistente virtual respondendo à mensagem..."
            );

            let bot_text = "Olá! Sou o assistente virtual. Recebi sua mensagem e ela já está na nossa fila de atendimento. Em breve um atendente falará com você.";
            // Chaves exigidas pelo handler de data_whatsapp (main.rs de data_whatsapp,
            // handler_send_whatsapp_message): "id" (db id da instância) e "to_number"
            // (telefone) — não "instance_id"/"to" (bug pré-existente corrigido na N1.3).
            let outbound_payload = serde_json::json!({
                "id": instance_id,
                "to_number": msg_normalized.sender,
                "text": bot_text,
            });

            let outbound_envelope = Envelope {
                tenant_id: envelope.tenant_id.to_string(),
                schema_version: 1,
                message_id: Uuid::now_v7().to_string(),
                causation_id: envelope.event_id.to_string(),
                traceparent: envelope.traceparent.clone(),
                occurred_at: chrono::Utc::now().timestamp_millis(),
                kind: MessageKind::Request as i32,
                method: "SendWhatsappMessage".to_string(),
                payload: serde_json::to_vec(&outbound_payload).unwrap_or_default(),
                error: None,
                auth_user_id: 0,
                auth_scopes: escopos_sistema(),
                auth_is_superuser: false,
                flow_permissions: vec![],
                user_agent: String::new(),
            };

            let out_resp = state
                .whatsapp_client
                .call(outbound_envelope, Duration::from_secs(5))
                .await?;
            if out_resp.kind == MessageKind::Error as i32 {
                let err_msg = out_resp
                    .error
                    .as_ref()
                    .map(|e| e.message.as_str())
                    .unwrap_or("Erro desconhecido");
                tracing::error!("Falha ao enviar resposta do bot: {}", err_msg);

                // Auditoria de falha de envio outbound (sem corpo da mensagem).
                state.audit_logger.warn(
                    tenant_uuid,
                    "mensagem.falha_envio",
                    "Falha ao enviar resposta automática do assistente virtual",
                    serde_json::json!({
                        "atendimento_id": atendimento_id,
                        "recipient": mascarar_telefone(&msg_normalized.sender),
                        "error": err_msg,
                    }),
                    None,
                    None,
                    Some(envelope.event_id.to_string()),
                );
            } else {
                // Auditoria de barreira de bot (respondeu) e do envio outbound.
                state.audit_logger.info(
                    tenant_uuid,
                    "bot.respondeu",
                    "Resposta automática do assistente virtual enviada com sucesso",
                    serde_json::json!({
                        "atendimento_id": atendimento_id,
                        "recipient": mascarar_telefone(&msg_normalized.sender),
                    }),
                    None,
                    None,
                    Some(envelope.event_id.to_string()),
                );
                state.audit_logger.info(
                    tenant_uuid,
                    "mensagem.enviada",
                    "Mensagem outbound enviada com sucesso via data_whatsapp",
                    serde_json::json!({
                        "atendimento_id": atendimento_id,
                        "recipient": mascarar_telefone(&msg_normalized.sender),
                    }),
                    None,
                    None,
                    Some(envelope.event_id.to_string()),
                );
            }
        } else {
            // Barreira de bot impediu a resposta automática (humano ativo ou flag desligada).
            state.audit_logger.info(
                tenant_uuid,
                "bot.silenciado",
                "Assistente virtual silenciado para o atendimento",
                serde_json::json!({
                    "atendimento_id": atendimento_id,
                    "bot_pode_atender": bot_pode_atender,
                    "humano_ativo": atendente_humano_id.is_some(),
                }),
                None,
                None,
                Some(envelope.event_id.to_string()),
            );
        }
    }

    Ok(())
}

/// Aplica a política de ticket/Kanban a um atendimento recém-aberto via RPC ao
/// `data_postgres` e, havendo movimento, audita `ticket.transicionado` + `kanban.movido`
/// e publica o evento de realtime para o tenant (WS-2.4).
async fn aplicar_politica_ticket_kanban(
    state: &AppState,
    tenant_uuid: Uuid,
    causation_id: &str,
    traceparent: &str,
    atendimento_id: i32,
) -> anyhow::Result<()> {
    let payload = serde_json::json!({ "atendimento_id": atendimento_id });

    let req_envelope = Envelope {
        tenant_id: tenant_uuid.to_string(),
        schema_version: 1,
        message_id: Uuid::now_v7().to_string(),
        causation_id: causation_id.to_string(),
        traceparent: traceparent.to_string(),
        occurred_at: chrono::Utc::now().timestamp_millis(),
        kind: MessageKind::Request as i32,
        method: "AplicarPoliticaTicketKanban".to_string(),
        payload: serde_json::to_vec(&payload).unwrap_or_default(),
        error: None,
        auth_user_id: 0,
        auth_scopes: escopos_sistema(),
        auth_is_superuser: false,
        flow_permissions: vec![],
        user_agent: String::new(),
    };

    let resp = state
        .pg_client
        .call(req_envelope, Duration::from_secs(5))
        .await?;
    if resp.kind == MessageKind::Error as i32 {
        let err_msg = resp
            .error
            .as_ref()
            .map(|e| e.message.as_str())
            .unwrap_or("Erro desconhecido");
        anyhow::bail!("Falha ao aplicar política de ticket/Kanban: {}", err_msg);
    }

    let body: serde_json::Value = serde_json::from_slice(&resp.payload)?;
    let moved = body.get("moved").and_then(|v| v.as_bool()).unwrap_or(false);
    if !moved {
        // Sem fluxo configurado / já posicionado: nada a auditar como transição.
        return Ok(());
    }

    let etapa_id = body.get("etapa_id").and_then(|v| v.as_i64());
    let etapa_nome = body
        .get("etapa_nome")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let ticket_status = body
        .get("ticket_status")
        .and_then(|v| v.as_str())
        .unwrap_or("fila")
        .to_string();

    let contexto = serde_json::json!({
        "atendimento_id": atendimento_id,
        "etapa_id": etapa_id,
        "etapa_nome": etapa_nome,
        "status": ticket_status,
    });

    state.audit_logger.info(
        tenant_uuid,
        "ticket.transicionado",
        "Ticket posicionado pela política automática de atendimento",
        contexto.clone(),
        None,
        None,
        Some(causation_id.to_string()),
    );
    state.audit_logger.info(
        tenant_uuid,
        "kanban.movido",
        "Atendimento movido para a etapa inicial do Kanban",
        contexto.clone(),
        None,
        None,
        Some(causation_id.to_string()),
    );

    // Realtime: notifica o tenant sobre a movimentação no Kanban.
    if let Some(ref redis_conn) = state.redis_conn {
        let channel = format!("tenant:{}:events", tenant_uuid);
        let event_payload = serde_json::json!({
            "event_type": "kanban.movido",
            "tenant_id": tenant_uuid.to_string(),
            "payload": contexto,
        });
        let mut conn = redis_conn.clone();
        let payload_str = event_payload.to_string();
        let publish_res: Result<u32, _> = redis::cmd("PUBLISH")
            .arg(&channel)
            .arg(&payload_str)
            .query_async(&mut conn)
            .await;
        if let Err(e) = publish_res {
            tracing::error!(
                "Erro ao publicar movimento de Kanban no Redis Pub/Sub: {:?}",
                e
            );
        }
    }

    Ok(())
}

async fn processar_status_mensagem(
    state: &AppState,
    evt: transport::bus::EventoBruto,
) -> anyhow::Result<()> {
    let envelope = evt.desserializar::<serde_json::Value>()?;
    let raw_payload = &envelope.payload;
    let raw_event = raw_payload
        .get("raw_event")
        .ok_or_else(|| anyhow::anyhow!("raw_event ausente"))?;

    let data = raw_event
        .get("data")
        .ok_or_else(|| anyhow::anyhow!("data ausente no status"))?;
    let status_str = data
        .get("status")
        .and_then(|v| v.as_str())
        .unwrap_or("sent");
    let key = data
        .get("key")
        .ok_or_else(|| anyhow::anyhow!("key ausente no status"))?;
    let msg_id = key
        .get("id")
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow::anyhow!("id da mensagem ausente"))?;

    tracing::info!(
        event_id = %envelope.event_id,
        tenant_id = %envelope.tenant_id,
        message_id = %msg_id,
        status = %status_str,
        "Worker processando evento whatsapp.message.status"
    );

    let pg_client = &state.pg_client;

    let req_payload = serde_json::json!({
        "message_id_whatsapp": msg_id,
        "status": status_str,
    });

    let req_envelope = Envelope {
        tenant_id: envelope.tenant_id.to_string(),
        schema_version: 1,
        message_id: Uuid::now_v7().to_string(),
        causation_id: envelope.event_id.to_string(),
        traceparent: envelope.traceparent.clone(),
        occurred_at: chrono::Utc::now().timestamp_millis(),
        kind: MessageKind::Request as i32,
        method: "UpdateMessageStatus".to_string(),
        payload: serde_json::to_vec(&req_payload).unwrap_or_default(),
        error: None,
        auth_user_id: 0,
        auth_scopes: escopos_sistema(),
        auth_is_superuser: false,
        flow_permissions: vec![],
        user_agent: String::new(),
    };

    let resp = pg_client.call(req_envelope, Duration::from_secs(5)).await?;

    if resp.kind == MessageKind::Error as i32 {
        let err_msg = resp
            .error
            .as_ref()
            .map(|e| e.message.as_str())
            .unwrap_or("Erro desconhecido");
        anyhow::bail!(
            "Falha ao atualizar status da mensagem no data_postgres: {}",
            err_msg
        );
    }

    // Convenção do glossário (§8): confirmação de status outbound usa `mensagem.confirmada`.
    state.audit_logger.info(
        envelope.tenant_id,
        "mensagem.confirmada",
        "Status de mensagem do WhatsApp atualizado",
        serde_json::json!({
            "message_id_whatsapp": msg_id,
            "status": status_str,
        }),
        None,
        None,
        Some(envelope.event_id.to_string()),
    );

    if let Some(ref redis_conn) = state.redis_conn {
        let channel = format!("tenant:{}:events", envelope.tenant_id);
        let event_payload = serde_json::json!({
            "event_type": "mensagem.status_atualizado",
            "tenant_id": envelope.tenant_id.to_string(),
            "payload": {
                "message_id_whatsapp": msg_id,
                "status": status_str,
            }
        });

        let mut conn = redis_conn.clone();
        let payload_str = event_payload.to_string();
        let publish_res: Result<u32, _> = redis::cmd("PUBLISH")
            .arg(&channel)
            .arg(&payload_str)
            .query_async(&mut conn)
            .await;

        if let Err(e) = publish_res {
            tracing::error!("Erro ao publicar status no Redis Pub/Sub: {:?}", e);
        }
    }

    Ok(())
}

/// Consome "message.persisted" (drenado do outbox pelo `OutboxRelay` do data_postgres)
/// e fecha o elo outbox->outbound do atendente (WS-6.3 / N1.3): quando `sender_id`
/// é "atendente", resolve instância/telefone do contato e envia via
/// `data_whatsapp::SendWhatsappMessage`, com retry/backoff e atualização de
/// `status_envio`. Mensagens do contato/bot (`sender_id` != "atendente") também
/// passam pelo outbox mas já foram entregues antes de chegar aqui — no-op.
async fn processar_mensagem_persistida(
    state: &AppState,
    evt: transport::bus::EventoBruto,
) -> anyhow::Result<()> {
    let envelope = evt.desserializar::<serde_json::Value>()?;

    let sender_id = envelope
        .payload
        .get("sender_id")
        .and_then(|v| v.as_str())
        .unwrap_or_default();
    if sender_id != "atendente" {
        return Ok(());
    }

    let mensagem_id: i32 = envelope
        .payload
        .get("message_id")
        .and_then(|v| v.as_str())
        .and_then(|s| s.parse().ok())
        .ok_or_else(|| {
            anyhow::anyhow!("message_id ausente/inválido no evento message.persisted")
        })?;

    let tenant_id = envelope.tenant_id.to_string();
    let causation_id = envelope.event_id.to_string();

    let destino = chamar_rpc(
        &state.pg_client,
        &tenant_id,
        "ResolverDestinoEnvioOutbound",
        serde_json::json!({ "mensagem_id": mensagem_id }),
        &causation_id,
        &envelope.traceparent,
    )
    .await?;

    let status_envio = destino
        .get("status_envio")
        .and_then(|v| v.as_str())
        .unwrap_or_default();
    if status_envio != "pending" {
        // Reentrega do consumer group (at-least-once) de um evento já processado
        // (sent/failed): no-op idempotente — status_envio é a fonte de verdade.
        tracing::debug!(
            mensagem_id = mensagem_id,
            status_envio = status_envio,
            "mensagem outbound já processada, ignorando reentrega"
        );
        return Ok(());
    }

    let instance_id = destino
        .get("instance_id")
        .and_then(|v| v.as_i64())
        .ok_or_else(|| anyhow::anyhow!("instance_id ausente na resolução de destino"))?;
    let to_number = destino
        .get("to_number")
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow::anyhow!("to_number ausente na resolução de destino"))?
        .to_string();
    let conteudo = destino
        .get("conteudo")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_string();

    let send_payload = serde_json::json!({
        "id": instance_id,
        "to_number": to_number,
        "text": conteudo,
    });

    // Retry com backoff (1s/2s/4s) para falhas transitórias do provedor.
    let backoffs_secs = [0u64, 1, 2, 4];
    let mut ultimo_erro: Option<anyhow::Error> = None;
    let mut stanza_id: Option<String> = None;
    for espera_secs in backoffs_secs {
        if espera_secs > 0 {
            tokio::time::sleep(Duration::from_secs(espera_secs)).await;
        }
        match chamar_rpc(
            &state.whatsapp_client,
            &tenant_id,
            "SendWhatsappMessage",
            send_payload.clone(),
            &causation_id,
            &envelope.traceparent,
        )
        .await
        {
            Ok(resp) => {
                stanza_id = resp
                    .get("message_id")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string());
                ultimo_erro = None;
                break;
            }
            Err(e) => ultimo_erro = Some(e),
        }
    }

    if let Some(stanza_id) = stanza_id {
        chamar_rpc(
            &state.pg_client,
            &tenant_id,
            "MarcarMensagemEnviada",
            serde_json::json!({ "mensagem_id": mensagem_id, "message_id_whatsapp": stanza_id }),
            &causation_id,
            &envelope.traceparent,
        )
        .await?;
        return Ok(());
    }

    // Falha definitiva após esgotar as tentativas.
    if let Err(e) = chamar_rpc(
        &state.pg_client,
        &tenant_id,
        "MarcarMensagemFalhaEnvio",
        serde_json::json!({ "mensagem_id": mensagem_id }),
        &causation_id,
        &envelope.traceparent,
    )
    .await
    {
        tracing::error!(
            mensagem_id = mensagem_id,
            "falha ao marcar status_envio='failed': {:?}",
            e
        );
    }

    state.audit_logger.warn(
        envelope.tenant_id,
        "mensagem.envio_falhou",
        "Falha definitiva ao enviar mensagem outbound do atendente ao WhatsApp",
        serde_json::json!({ "mensagem_id": mensagem_id }),
        None,
        None,
        Some(causation_id),
    );

    anyhow::bail!(
        "Falha definitiva ao enviar mensagem outbound (mensagem_id={}): {:?}",
        mensagem_id,
        ultimo_erro
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    use contracts::{Envelope, MessageKind};
    use std::time::Duration;
    use transport::bus::EventoBruto;
    use transport::runtime::{Endpoint, Server};
    use uuid::Uuid;

    static WORKER_TEST_MUTEX: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

    fn evento_message_received(tenant_id: &str) -> EventoBruto {
        let raw_event = serde_json::json!({
            "data": {
                "key": {
                    "remoteJid": "5511999998888@s.whatsapp.net",
                    "fromMe": false,
                    "id": "MSG1234"
                },
                "pushName": "João Silva",
                "messageTimestamp": chrono::Utc::now().timestamp(),
                "message": {
                    "conversation": "Preciso de ajuda"
                }
            }
        });

        let payload = serde_json::json!({
            "instance_id": 42,
            "provider": "evolution",
            "raw_event": raw_event
        });

        EventoBruto {
            stream_id: "1234567890-0".to_string(),
            tenant_id: tenant_id.to_string(),
            event_id: Uuid::now_v7().to_string(),
            event_type: "whatsapp.message.received".to_string(),
            timestamp: chrono::Utc::now().to_rfc3339(),
            traceparent: "00-trace-worker-01-01".to_string(),
            payload: serde_json::to_string(&payload).unwrap(),
        }
    }

    #[tokio::test]
    async fn test_processar_mensagem_recebida_sucesso() {
        let _guard = WORKER_TEST_MUTEX.lock().await;
        let pg_addr = "tcp://127.0.0.1:29220";
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);

        let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
        let pg_server = Server::new(pg_endpoint, "flatbuffers")
            .route("ResolveAtendimentoParaContato", |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({
                        "status": "success",
                        "contato_id": 10,
                        "atendimento_id": 42,
                    });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "ResolveAtendimentoParaContatoReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            })
            .route("PersistMessage", |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({ "status": "success", "message_id": 100 });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "PersistMessageReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            });
        let pg_handle = tokio::spawn(async move {
            pg_server.run().await.unwrap();
        });
        tokio::time::sleep(Duration::from_millis(150)).await;

        let pg_client = Arc::new(transport::conectar_cliente("data_postgres").await.unwrap());
        let state = AppState {
            redis_conn: None,
            audit_logger: observability::AuditLogger::new_dummy("worker"),
            whatsapp_client: pg_client.clone(),
            pg_client,
        };

        let evt = evento_message_received(&Uuid::new_v4().to_string());
        let resultado = processar_mensagem_recebida(&state, evt).await;
        assert!(
            resultado.is_ok(),
            "Esperava sucesso, obteve: {:?}",
            resultado
        );

        pg_handle.abort();
    }

    #[tokio::test]
    async fn test_processar_mensagem_recebida_erro_rpc() {
        let _guard = WORKER_TEST_MUTEX.lock().await;
        let pg_addr = "tcp://127.0.0.1:29221";
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);

        let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
        let pg_server =
            Server::new(pg_endpoint, "flatbuffers").route("ResolveAtendimentoParaContato", |env| {
                Box::pin(async move {
                    let error_env = contracts::ErrorEnvelope {
                        code: "DB_ERROR".to_string(),
                        message: "Falha ao resolver".to_string(),
                        ..Default::default()
                    };
                    Envelope {
                        kind: MessageKind::Error as i32,
                        method: "ResolveAtendimentoParaContatoReply".to_string(),
                        error: Some(error_env),
                        ..env
                    }
                })
            });
        let pg_handle = tokio::spawn(async move {
            pg_server.run().await.unwrap();
        });
        tokio::time::sleep(Duration::from_millis(150)).await;

        let pg_client = Arc::new(transport::conectar_cliente("data_postgres").await.unwrap());
        let state = AppState {
            redis_conn: None,
            audit_logger: observability::AuditLogger::new_dummy("worker"),
            whatsapp_client: pg_client.clone(),
            pg_client,
        };

        let evt = evento_message_received(&Uuid::new_v4().to_string());
        let resultado = processar_mensagem_recebida(&state, evt).await;
        assert!(resultado.is_err(), "Esperava erro na persistência RPC");

        pg_handle.abort();
    }

    #[tokio::test]
    async fn test_processar_mensagem_recebida_sem_data_postgres() {
        let _guard = WORKER_TEST_MUTEX.lock().await;
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", "tcp://127.0.0.1:29229");

        let pg_client_res = transport::conectar_cliente("data_postgres").await;
        if pg_client_res.is_err() {
            return;
        }

        let pg_client = Arc::new(pg_client_res.unwrap());
        let state = AppState {
            redis_conn: None,
            audit_logger: observability::AuditLogger::new_dummy("worker"),
            whatsapp_client: pg_client.clone(),
            pg_client,
        };

        let evt = evento_message_received(&Uuid::new_v4().to_string());
        let resultado = processar_mensagem_recebida(&state, evt).await;
        assert!(resultado.is_err(), "Esperava erro de conexão recusada");
    }

    #[tokio::test]
    async fn test_processar_mensagem_tenant_uuid_invalido_falha_desserializacao() {
        let _guard = WORKER_TEST_MUTEX.lock().await;
        let pg_addr = "tcp://127.0.0.1:29223";
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);

        let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
        let pg_server = Server::new(pg_endpoint, "flatbuffers")
            .route("ResolveAtendimentoParaContato", |env| {
                Box::pin(async move { env })
            });
        let pg_handle = tokio::spawn(async move {
            pg_server.run().await.unwrap();
        });
        tokio::time::sleep(Duration::from_millis(150)).await;

        let pg_client = Arc::new(transport::conectar_cliente("data_postgres").await.unwrap());
        let state = AppState {
            redis_conn: None,
            audit_logger: observability::AuditLogger::new_dummy("worker"),
            whatsapp_client: pg_client.clone(),
            pg_client,
        };

        let evt = EventoBruto {
            stream_id: "1234-0".to_string(),
            tenant_id: "nao-e-um-uuid".to_string(),
            event_id: Uuid::now_v7().to_string(),
            event_type: "message.received".to_string(),
            timestamp: chrono::Utc::now().to_rfc3339(),
            traceparent: "".to_string(),
            payload: r#"{"content":"ok","sender_id":"s"}"#.to_string(),
        };
        let resultado = processar_mensagem_recebida(&state, evt).await;
        assert!(resultado.is_err(), "Esperava erro de UUID inválido");

        pg_handle.abort();
    }

    fn evento_message_persistida(sender_id: &str, mensagem_id: i64) -> EventoBruto {
        let payload = serde_json::json!({
            "message_id": mensagem_id.to_string(),
            "sender_id": sender_id,
            "content": "mensagem de teste do atendente",
            "timestamp": chrono::Utc::now().timestamp_millis(),
        });

        EventoBruto {
            stream_id: "9999-0".to_string(),
            tenant_id: Uuid::new_v4().to_string(),
            event_id: Uuid::now_v7().to_string(),
            event_type: "message.persisted".to_string(),
            timestamp: chrono::Utc::now().to_rfc3339(),
            traceparent: "00-trace-worker-n13-01".to_string(),
            payload: serde_json::to_string(&payload).unwrap(),
        }
    }

    #[tokio::test]
    async fn test_processar_mensagem_persistida_sender_contato_noop() {
        let _guard = WORKER_TEST_MUTEX.lock().await;
        // Servidor sem nenhuma rota registrada: se o código tentasse qualquer RPC
        // aqui, receberia um erro do servidor (método desconhecido) e o teste falharia.
        let pg_addr = "tcp://127.0.0.1:29390";
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
        std::env::set_var("SMARTCORE_DATA_WHATSAPP_ENDPOINT", pg_addr);

        let pg_server = Server::new(Endpoint::parse(pg_addr).unwrap(), "flatbuffers");
        let pg_handle = tokio::spawn(async move { pg_server.run().await.unwrap() });
        tokio::time::sleep(Duration::from_millis(150)).await;

        let pg_client = Arc::new(transport::conectar_cliente("data_postgres").await.unwrap());
        let whatsapp_client = Arc::new(transport::conectar_cliente("data_whatsapp").await.unwrap());
        let state = AppState {
            redis_conn: None,
            audit_logger: observability::AuditLogger::new_dummy("worker"),
            pg_client,
            whatsapp_client,
        };

        let evt = evento_message_persistida("contato", 1);
        let resultado = processar_mensagem_persistida(&state, evt).await;
        assert!(
            resultado.is_ok(),
            "mensagem de contato/bot deve ser no-op: {:?}",
            resultado
        );

        pg_handle.abort();
    }

    #[tokio::test]
    async fn test_processar_mensagem_persistida_sucesso_envia() {
        let _guard = WORKER_TEST_MUTEX.lock().await;
        let pg_addr = "tcp://127.0.0.1:29392";
        let wa_addr = "tcp://127.0.0.1:29393";
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
        std::env::set_var("SMARTCORE_DATA_WHATSAPP_ENDPOINT", wa_addr);

        let pg_server = Server::new(Endpoint::parse(pg_addr).unwrap(), "flatbuffers")
            .route("ResolverDestinoEnvioOutbound", |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({
                        "atendimento_id": 42,
                        "instance_id": 7,
                        "to_number": "5511999998888",
                        "status_envio": "pending",
                        "conteudo": "mensagem de teste do atendente",
                    });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "ResolverDestinoEnvioOutboundReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            })
            .route("MarcarMensagemEnviada", |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({ "status": "ok" });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "MarcarMensagemEnviadaReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            });
        let wa_server = Server::new(Endpoint::parse(wa_addr).unwrap(), "flatbuffers").route(
            "SendWhatsappMessage",
            |env| {
                Box::pin(async move {
                    let reply =
                        serde_json::json!({ "status": "success", "message_id": "WA-STANZA-1" });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "SendWhatsappMessageReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            },
        );
        let pg_handle = tokio::spawn(async move { pg_server.run().await.unwrap() });
        let wa_handle = tokio::spawn(async move { wa_server.run().await.unwrap() });
        tokio::time::sleep(Duration::from_millis(150)).await;

        let pg_client = Arc::new(transport::conectar_cliente("data_postgres").await.unwrap());
        let whatsapp_client = Arc::new(transport::conectar_cliente("data_whatsapp").await.unwrap());
        let state = AppState {
            redis_conn: None,
            audit_logger: observability::AuditLogger::new_dummy("worker"),
            pg_client,
            whatsapp_client,
        };

        let evt = evento_message_persistida("atendente", 100);
        let resultado = processar_mensagem_persistida(&state, evt).await;
        assert!(
            resultado.is_ok(),
            "Esperava sucesso, obteve: {:?}",
            resultado
        );

        pg_handle.abort();
        wa_handle.abort();
    }

    #[tokio::test]
    async fn test_processar_mensagem_persistida_idempotente_ja_enviada() {
        let _guard = WORKER_TEST_MUTEX.lock().await;
        let pg_addr = "tcp://127.0.0.1:29394";
        // whatsapp aponta para o mesmo servidor mock (sem rota SendWhatsappMessage):
        // se o código tentasse enviar de novo, receberia erro de método desconhecido —
        // confirma que o caminho idempotente não chama SendWhatsappMessage.
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
        std::env::set_var("SMARTCORE_DATA_WHATSAPP_ENDPOINT", pg_addr);

        let pg_server = Server::new(Endpoint::parse(pg_addr).unwrap(), "flatbuffers").route(
            "ResolverDestinoEnvioOutbound",
            |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({
                        "atendimento_id": 42,
                        "instance_id": 7,
                        "to_number": "5511999998888",
                        "status_envio": "sent",
                        "conteudo": "já enviada antes",
                    });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "ResolverDestinoEnvioOutboundReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            },
        );
        let pg_handle = tokio::spawn(async move { pg_server.run().await.unwrap() });
        tokio::time::sleep(Duration::from_millis(150)).await;

        let pg_client = Arc::new(transport::conectar_cliente("data_postgres").await.unwrap());
        let whatsapp_client = Arc::new(transport::conectar_cliente("data_whatsapp").await.unwrap());
        let state = AppState {
            redis_conn: None,
            audit_logger: observability::AuditLogger::new_dummy("worker"),
            pg_client,
            whatsapp_client,
        };

        let evt = evento_message_persistida("atendente", 101);
        let resultado = processar_mensagem_persistida(&state, evt).await;
        assert!(
            resultado.is_ok(),
            "reentrega de mensagem já enviada deve ser idempotente (no-op): {:?}",
            resultado
        );

        pg_handle.abort();
    }
}
