#[allow(unused_imports)]
use async_trait::async_trait;
use contracts::{Envelope, MessageKind, TenantEnvelope};
use infrastructure_evolution::EvolutionProvider;
#[allow(unused_imports)]
use infrastructure_messaging::{
    AdvancedSettings, ConnectionState, CreateInstanceResult, InstanceManager, MediaType,
    MessageSender, MessagingProvider, MessagingProviderError, PresenceState, ProviderRegistry,
    SendMessageResult, WebhookConfig,
};
use secrecy::SecretString;
use std::env;
use std::time::Duration;
use transport::Server;
use uuid::Uuid;

#[derive(Clone)]
struct AppState {
    registry: ProviderRegistry,
    redis_conn: redis::aio::ConnectionManager,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    observability::init_telemetry("data_whatsapp", "production")
        .map_err(|e| anyhow::anyhow!(e.to_string()))?;
    // Panic em task de background mata so a task: o processo segue vivo e a
    // funcionalidade some sem deixar rastro. O hook garante o registro estruturado.
    observability::instalar_hook_de_panic("data_whatsapp");
    tracing::info!("Iniciando serviço data_whatsapp...");

    let api_url =
        env::var("EVOLUTION_API_URL").unwrap_or_else(|_| "http://localhost:8080".to_string());
    let api_token = env::var("EVOLUTION_GLOBAL_API_KEY")
        .or_else(|_| env::var("EVOLUTION_API_TOKEN"))
        .unwrap_or_default();

    let provider = EvolutionProvider::new(api_url, SecretString::from(api_token));
    let registry = ProviderRegistry::builder()
        .register(std::sync::Arc::new(provider))
        .build();

    let redis_url =
        env::var("REDIS_BUS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());

    let redis_client = redis::Client::open(redis_url)?;
    let redis_conn = redis::aio::ConnectionManager::new(redis_client.clone()).await?;

    let state = AppState {
        registry,
        redis_conn,
    };

    let s_create = state.clone();
    let s_delete = state.clone();
    let s_reconnect = state.clone();
    let s_status = state.clone();
    let s_send_text = state.clone();
    let s_send_media = state.clone();
    let s_bulk_disconnect = state.clone();
    let s_reconciliar = state.clone();

    // Novas rotas de capacidades opcionais
    let s_mark_read = state.clone();
    let s_react = state.clone();
    let s_presence = state.clone();
    let s_profile = state.clone();
    let s_download = state;

    let server = Server::from_env("DATA_WHATSAPP")
        .route("CreateWhatsappInstance", move |env| {
            let s = s_create.clone();
            Box::pin(async move { handler_create_whatsapp_instance(s, env).await })
        })
        .route("DeleteWhatsappInstance", move |env| {
            let s = s_delete.clone();
            Box::pin(async move { handler_delete_whatsapp_instance(s, env).await })
        })
        .route("ReconnectWhatsappInstance", move |env| {
            let s = s_reconnect.clone();
            Box::pin(async move { handler_reconnect_whatsapp_instance(s, env).await })
        })
        .route("GetWhatsappInstanceStatus", move |env| {
            let s = s_status.clone();
            Box::pin(async move { handler_get_whatsapp_instance_status(s, env).await })
        })
        .route("ReconciliarConexaoInstancia", move |env| {
            let s = s_reconciliar.clone();
            Box::pin(async move { handler_reconciliar_conexao_instancia(s, env).await })
        })
        .route("SendWhatsappMessage", move |env| {
            let s = s_send_text.clone();
            Box::pin(async move { handler_send_whatsapp_message(s, env).await })
        })
        .route("SendWhatsappMedia", move |env| {
            let s = s_send_media.clone();
            Box::pin(async move { handler_send_whatsapp_media(s, env).await })
        })
        .route("AdminBulkDisconnectInstances", move |env| {
            let s = s_bulk_disconnect.clone();
            Box::pin(async move { handler_admin_bulk_disconnect(s, env).await })
        })
        .route("MarkWhatsappMessageRead", move |env| {
            let s = s_mark_read.clone();
            Box::pin(async move { handler_mark_whatsapp_message_read(s, env).await })
        })
        .route("SendWhatsappReaction", move |env| {
            let s = s_react.clone();
            Box::pin(async move { handler_send_whatsapp_reaction(s, env).await })
        })
        .route("SetWhatsappPresence", move |env| {
            let s = s_presence.clone();
            Box::pin(async move { handler_set_whatsapp_presence(s, env).await })
        })
        .route("GetWhatsappProfilePicture", move |env| {
            let s = s_profile.clone();
            Box::pin(async move { handler_get_whatsapp_profile_picture(s, env).await })
        })
        .route("DownloadWhatsappMedia", move |env| {
            let s = s_download.clone();
            Box::pin(async move { handler_download_whatsapp_media(s, env).await })
        });

    tracing::info!("Servidor RPC do data_whatsapp configurado e pronto.");

    // Ver a nota em `data_redis`: SIGTERM precisa ser tratado, senão todo deploy
    // mata o processo no meio do que estava em voo.
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

fn erro(app_err: error_core::AppError, env: &Envelope) -> Envelope {
    let err_env = app_err.to_error_envelope(&env.traceparent, "data_whatsapp");
    Envelope {
        kind: MessageKind::Error as i32,
        error: Some(err_env),
        ..env.clone()
    }
}

fn ok_reply(env: &Envelope, method: &str, payload: serde_json::Value) -> Envelope {
    Envelope {
        kind: MessageKind::Reply as i32,
        method: method.to_string(),
        payload: serde_json::to_vec(&payload).unwrap_or_default(),
        error: None,
        ..env.clone()
    }
}

async fn chamar_data_postgres(
    method: &str,
    tenant_id: &str,
    payload: serde_json::Value,
    env: &Envelope,
) -> Result<serde_json::Value, error_core::AppError> {
    let pg_client = transport::conectar_cliente("data_postgres")
        .await
        .map_err(|e| {
            error_core::AppError::Internal(format!("Falha ao conectar no data_postgres: {e}"))
        })?;

    let req = Envelope {
        kind: MessageKind::Request as i32,
        method: method.to_string(),
        tenant_id: tenant_id.to_string(),
        payload: serde_json::to_vec(&payload).unwrap_or_default(),
        traceparent: env.traceparent.clone(),
        auth_user_id: env.auth_user_id,
        auth_scopes: env.auth_scopes.clone(),
        ..Default::default()
    };

    let resp = pg_client
        .call(req, Duration::from_secs(5))
        .await
        .map_err(|e| {
            error_core::AppError::Internal(format!("Falha ao chamar RPC {method}: {e}"))
        })?;

    if resp.kind == MessageKind::Error as i32 {
        let msg = resp
            .error
            .map(|err| err.message)
            .unwrap_or_else(|| "Erro desconhecido".to_string());
        return Err(error_core::AppError::Database(msg));
    }

    let val: serde_json::Value = serde_json::from_slice(&resp.payload).map_err(|e| {
        error_core::AppError::Validation(format!(
            "Falha ao parsear payload de resposta da RPC {method}: {e}"
        ))
    })?;

    Ok(val)
}

/// N4.2 — QuotaGuard (decorator): consulta `CheckQuota` no data_postgres antes de
/// operações sujeitas a limite de plano (hoje: provisionamento de instância).
/// Modo log-only por padrão (`SMARTCORE_QUOTA_ENFORCE=false`) — só loga e segue;
/// vira bloqueio real quando a flag é `true`. Falha na própria checagem (RPC fora
/// do ar) é fail-open: não derruba o caminho de negócio por causa do guard.
async fn aplicar_quota_guard(recurso: &str, env: &Envelope) -> Result<(), error_core::AppError> {
    // `auditar: true` — este é o ponto de enforcement (provisionamento), onde a
    // auditoria de `quota.excedida`/inadimplência é um evento pontual legítimo.
    let status = match chamar_data_postgres(
        "CheckQuota",
        &env.tenant_id,
        serde_json::json!({ "recurso": recurso, "auditar": true }),
        env,
    )
    .await
    {
        Ok(v) => v,
        Err(e) => {
            tracing::warn!(erro = %e, recurso, "falha ao verificar quota; prosseguindo (fail-open)");
            return Ok(());
        }
    };

    let excedido = status
        .get("excedido")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let inadimplente = status
        .get("inadimplente")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    if !excedido && !inadimplente {
        return Ok(());
    }

    let enforce = std::env::var("SMARTCORE_QUOTA_ENFORCE")
        .map(|v| v.eq_ignore_ascii_case("true"))
        .unwrap_or(false);

    if !enforce {
        tracing::warn!(
            recurso,
            excedido,
            inadimplente,
            "quota/inadimplência detectada (log-only; SMARTCORE_QUOTA_ENFORCE=false)"
        );
        return Ok(());
    }

    if inadimplente {
        return Err(error_core::AppError::RateLimit(
            "assinatura inadimplente; operação bloqueada".into(),
        ));
    }
    Err(error_core::AppError::RateLimit(format!(
        "quota de '{recurso}' excedida"
    )))
}

#[tracing::instrument(skip_all, fields(rpc = "CreateWhatsappInstance", tenant_id = %env.tenant_id))]
async fn handler_create_whatsapp_instance(mut state: AppState, env: Envelope) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let instance_name = match payload.get("instance_name").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("instance_name ausente".into()),
                &env,
            )
        }
    };

    let provider_name = payload
        .get("provider")
        .and_then(|v| v.as_str())
        .unwrap_or("evolution");

    // 0. QuotaGuard: quota de instâncias do plano vigente (N4.2).
    if let Err(e) = aplicar_quota_guard("instancias", &env).await {
        return erro(e, &env);
    }

    let p = match state.registry.resolve(provider_name) {
        Ok(prov) => prov,
        Err(e) => return erro(error_core::AppError::Internal(e.to_string()), &env),
    };

    // 1. Cria a instância no provedor
    let result = match p.create_instance(instance_name, None).await {
        Ok(res) => res,
        Err(e) => {
            return erro(
                error_core::AppError::Internal(format!(
                    "Falha ao criar instância no provedor: {e}"
                )),
                &env,
            )
        }
    };
    let instance_token = SecretString::from(result.instance_token.clone());

    // 2. Salva o registro no banco via data_postgres
    let db_record = match chamar_data_postgres(
        "CreateWhatsappInstanceRecord",
        &env.tenant_id,
        serde_json::json!({
            "name": instance_name,
            "api_key": result.instance_token,
            "provider": provider_name,
        }),
        &env,
    )
    .await
    {
        Ok(r) => r,
        Err(e) => {
            // Rollback no provedor para não deixar sujeira
            let _ = p.delete_instance(instance_name).await;
            return erro(e, &env);
        }
    };

    let db_id = match db_record.get("id").and_then(|v| v.as_i64()) {
        Some(id) => id,
        None => {
            let _ = p.delete_instance(instance_name).await;
            return erro(
                error_core::AppError::Internal(
                    "ID de banco não retornado pelo data_postgres".into(),
                ),
                &env,
            );
        }
    };

    // 3. Conecta a instância passando webhook Url embutido e eventos de assinatura
    let webhook_url = format!(
        "http://webhook_ingress:9200/webhook/{}/{}/{}",
        provider_name, env.tenant_id, db_id
    );
    let webhook_conf = WebhookConfig {
        url: webhook_url,
        subscribe: vec![
            "MESSAGE".to_string(),
            "CONNECTION".to_string(),
            "PRESENCE".to_string(),
            "QRCODE".to_string(),
        ],
    };

    if let Err(e) = p
        .connect_instance(instance_name, &instance_token, &webhook_conf)
        .await
    {
        let _ = p.delete_instance(instance_name).await;
        let _ = chamar_data_postgres(
            "AdminDeletarInstancia",
            &env.tenant_id,
            serde_json::json!({ "id": db_id }),
            &env,
        )
        .await;
        return erro(
            error_core::AppError::Internal(format!("Falha ao conectar instância no provedor: {e}")),
            &env,
        );
    }

    // 4. Configura advanced settings (alwaysOnline: true, readMessages: false)
    if let Some(adv) = p.advanced_settings() {
        if let Err(e) = adv
            .set_advanced_settings(
                &result.provider_instance_id,
                &instance_token,
                AdvancedSettings::default(),
            )
            .await
        {
            tracing::warn!(
                "Erro ao configurar advanced settings da instância (continuando): {:?}",
                e
            );
        }
    }

    // 5. Salva o provider_instance_id e tenta obter informações adicionais
    let provider_instance_id = result.provider_instance_id;
    let _ = chamar_data_postgres(
        "AtualizarInstanciaProviderId",
        &env.tenant_id,
        serde_json::json!({
            "id": db_id,
            "instance_id": provider_instance_id,
            "phone_number": serde_json::Value::Null,
        }),
        &env,
    )
    .await;

    // 6. Publica evento de auditoria no security:stream.
    //
    // O consumidor (data_postgres::processar_eventos_auditoria_lote) desserializa
    // TODA mensagem deste stream como observability::AuditLogPayload — publicar um
    // serde_json::json!({...}) solto (formato antigo deste arquivo) falha com
    // "missing field `level`" e o evento é descartado em silêncio, nunca gravado
    // em audit_log. Confirmado ao vivo nos logs de produção.
    let tenant_uuid = Uuid::parse_str(&env.tenant_id).ok().filter(|id| !id.is_nil());
    let audit_payload = observability::AuditLogPayload {
        tenant_id: tenant_uuid,
        level: "INFO".to_string(),
        service: "data_whatsapp".to_string(),
        trace_id: Some(env.traceparent.clone()),
        event: "whatsapp.instance.create".to_string(),
        message: format!(
            "Instância WhatsApp '{instance_name}' criada (provedor: {provider_name})"
        ),
        context: serde_json::json!({ "instance_name": instance_name, "provider": provider_name }),
        user_id: (env.auth_user_id > 0).then_some(env.auth_user_id),
        ip_address: None,
        user_agent: None,
    };
    let audit_event = TenantEnvelope::novo(
        tenant_uuid.unwrap_or_else(Uuid::nil),
        "security.audit",
        audit_payload,
    )
    .com_traceparent(env.traceparent.clone());

    let _ = transport::bus::publicar_evento_seguranca(&mut state.redis_conn, &audit_event).await;

    ok_reply(
        &env,
        "CreateWhatsappInstanceReply",
        serde_json::json!({
            "status": "success",
            "id": db_id,
            "instance_name": instance_name,
            "provider": provider_name,
        }),
    )
}

#[tracing::instrument(skip_all, fields(rpc = "DeleteWhatsappInstance", tenant_id = %env.tenant_id))]
async fn handler_delete_whatsapp_instance(mut state: AppState, env: Envelope) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let db_id = match payload.get("id").and_then(|v| v.as_i64()) {
        Some(id) => id,
        None => return erro(error_core::AppError::Validation("id ausente".into()), &env),
    };

    // 1. Busca os detalhes da instância
    let instance = match chamar_data_postgres(
        "GetWhatsappInstance",
        &env.tenant_id,
        serde_json::json!({ "id": db_id }),
        &env,
    )
    .await
    {
        Ok(inst) => inst,
        Err(e) => return erro(e, &env),
    };

    let name = match instance.get("name").and_then(|v| v.as_str()) {
        Some(s) if !s.is_empty() => s,
        _ => {
            return erro(
                error_core::AppError::Database(
                    "não encontrado: Instância não encontrada no banco".into(),
                ),
                &env,
            )
        }
    };

    let provider_name = instance
        .get("provider")
        .and_then(|v| v.as_str())
        .unwrap_or("evolution");
    let p = match state.registry.resolve(provider_name) {
        Ok(prov) => prov,
        Err(e) => return erro(error_core::AppError::Internal(e.to_string()), &env),
    };

    // 2. Remove do provedor
    if let Err(e) = p.delete_instance(name).await {
        tracing::warn!(
            "Erro ao deletar instância no provedor (continuando remoção do banco): {:?}",
            e
        );
    }

    // 3. Remove do banco
    if let Err(e) = chamar_data_postgres(
        "AdminDeletarInstancia",
        &env.tenant_id,
        serde_json::json!({ "id": db_id }),
        &env,
    )
    .await
    {
        return erro(e, &env);
    }

    // 4. Publica auditoria (ver comentário em handler_create_instance sobre o
    // formato exigido pelo consumidor — AuditLogPayload, não json!({}) solto).
    let tenant_uuid = Uuid::parse_str(&env.tenant_id).ok().filter(|id| !id.is_nil());
    let audit_payload = observability::AuditLogPayload {
        tenant_id: tenant_uuid,
        level: "INFO".to_string(),
        service: "data_whatsapp".to_string(),
        trace_id: Some(env.traceparent.clone()),
        event: "whatsapp.instance.delete".to_string(),
        message: format!("Instância WhatsApp '{name}' removida"),
        context: serde_json::json!({ "instance_name": name }),
        user_id: (env.auth_user_id > 0).then_some(env.auth_user_id),
        ip_address: None,
        user_agent: None,
    };
    let audit_event = TenantEnvelope::novo(
        tenant_uuid.unwrap_or_else(Uuid::nil),
        "security.audit",
        audit_payload,
    )
    .com_traceparent(env.traceparent.clone());
    let _ = transport::bus::publicar_evento_seguranca(&mut state.redis_conn, &audit_event).await;

    ok_reply(
        &env,
        "DeleteWhatsappInstanceReply",
        serde_json::json!({ "status": "success" }),
    )
}

#[tracing::instrument(skip_all, fields(rpc = "ReconnectWhatsappInstance", tenant_id = %env.tenant_id))]
async fn handler_reconnect_whatsapp_instance(state: AppState, env: Envelope) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let db_id = match payload.get("id").and_then(|v| v.as_i64()) {
        Some(id) => id,
        None => return erro(error_core::AppError::Validation("id ausente".into()), &env),
    };

    let instance = match chamar_data_postgres(
        "GetWhatsappInstance",
        &env.tenant_id,
        serde_json::json!({ "id": db_id }),
        &env,
    )
    .await
    {
        Ok(inst) => inst,
        Err(e) => return erro(e, &env),
    };

    let name = match instance.get("name").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Database("não encontrado: Instância não encontrada".into()),
                &env,
            )
        }
    };

    let api_key = match instance.get("api_key").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("Chave da instância ausente".into()),
                &env,
            )
        }
    };

    let provider_name = instance
        .get("provider")
        .and_then(|v| v.as_str())
        .unwrap_or("evolution");
    let p = match state.registry.resolve(provider_name) {
        Ok(prov) => prov,
        Err(e) => return erro(error_core::AppError::Internal(e.to_string()), &env),
    };

    if let Err(e) = p
        .reconnect_instance(name, &SecretString::from(api_key.to_string()))
        .await
    {
        return erro(
            error_core::AppError::Internal(format!(
                "Falha ao reconectar instância no provedor: {e}"
            )),
            &env,
        );
    }

    ok_reply(
        &env,
        "ReconnectWhatsappInstanceReply",
        serde_json::json!({ "status": "success" }),
    )
}

/// Confere uma instância com o provedor e a religa se o socket caiu.
///
/// É o que mantém o WhatsApp no ar sem ninguém olhando. O socket cai por
/// motivos banais — rede, restart do container do provedor, o próprio WhatsApp
/// derrubando — e, sem alguém para religá-lo, a instância fica fora
/// indefinidamente. Passados ~14 dias offline o WhatsApp **desvincula o
/// aparelho**, e aí não há reconexão que resolva: só um QR novo, presencial.
/// Religar cedo é o que evita esse ponto sem volta.
///
/// **Nunca pede o QR** — diferente de `GetWhatsappInstanceStatus`, que o pede
/// quando não está conectado. Pedir o QR reinicia o cliente no provedor, e ao
/// quinto código a evolution-go força logout. Num laço periódico isso derrubaria
/// justamente a sessão que viemos preservar.
///
/// Religar usa `connect`, não `reconnect`: `/instance/reconnect` responde
/// "no active session found" quando o socket já caiu — ele serve para uma sessão
/// viva, não para ressuscitar uma morta.
#[tracing::instrument(skip_all, fields(rpc = "ReconciliarConexaoInstancia", tenant_id = %env.tenant_id))]
async fn handler_reconciliar_conexao_instancia(state: AppState, env: Envelope) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let db_id = match payload.get("id").and_then(|v| v.as_i64()) {
        Some(id) => id,
        None => return erro(error_core::AppError::Validation("id ausente".into()), &env),
    };

    let instance = match chamar_data_postgres(
        "GetWhatsappInstance",
        &env.tenant_id,
        serde_json::json!({ "id": db_id }),
        &env,
    )
    .await
    {
        Ok(inst) => inst,
        Err(e) => return erro(e, &env),
    };

    let name = match instance.get("name").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Database("não encontrado: Instância não encontrada".into()),
                &env,
            )
        }
    };

    let api_key = match instance.get("api_key").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("Chave da instância ausente".into()),
                &env,
            )
        }
    };

    let provider_name = instance
        .get("provider")
        .and_then(|v| v.as_str())
        .unwrap_or("evolution");
    let p = match state.registry.resolve(provider_name) {
        Ok(prov) => prov,
        Err(e) => return erro(error_core::AppError::Internal(e.to_string()), &env),
    };

    let api_key_sec = SecretString::from(api_key.to_string());

    let estado_inicial = p
        .get_connection_state(name, &api_key_sec)
        .await
        .unwrap_or(ConnectionState::Unknown);

    // Já no ar: só carimba o estado e sai. É o caminho de todo tick normal.
    if estado_inicial == ConnectionState::Connected {
        gravar_estado(&env, db_id, "connected").await;
        return ok_reply(
            &env,
            "ReconciliarConexaoInstanciaReply",
            serde_json::json!({ "state": "connected", "religada": false, "precisa_parear": false }),
        );
    }

    // `Unknown` é "não sei", não "está fora": o provedor pode ter engasgado.
    // Religar por não saber acabaria reiniciando um cliente saudável.
    if estado_inicial == ConnectionState::Unknown {
        tracing::warn!(
            instance_id = db_id,
            "provedor não respondeu o estado; sem ação"
        );
        return ok_reply(
            &env,
            "ReconciliarConexaoInstanciaReply",
            serde_json::json!({ "state": "unknown", "religada": false, "precisa_parear": false }),
        );
    }

    let webhook_conf = WebhookConfig {
        url: format!(
            "http://webhook_ingress:9200/webhook/{}/{}/{}",
            provider_name, env.tenant_id, db_id
        ),
        subscribe: vec![
            "MESSAGE".to_string(),
            "CONNECTION".to_string(),
            "PRESENCE".to_string(),
            "QRCODE".to_string(),
        ],
    };

    if let Err(e) = p.connect_instance(name, &api_key_sec, &webhook_conf).await {
        tracing::warn!(instance_id = db_id, erro = %e, "falha ao religar instância");
        gravar_estado(&env, db_id, "disconnected").await;
        return ok_reply(
            &env,
            "ReconciliarConexaoInstanciaReply",
            serde_json::json!({ "state": "disconnected", "religada": false, "precisa_parear": false }),
        );
    }

    // O handshake não é instantâneo: o socket abre e a sessão é validada logo
    // depois. Conferir no mesmo instante devolveria `Connecting` sempre.
    tokio::time::sleep(Duration::from_secs(5)).await;

    let estado_final = p
        .get_connection_state(name, &api_key_sec)
        .await
        .unwrap_or(ConnectionState::Unknown);

    let (texto, religada, precisa_parear) = desfecho_da_religada(estado_final);

    if texto != "unknown" {
        gravar_estado(&env, db_id, texto).await;
    }

    if religada {
        tracing::info!(instance_id = db_id, "instância religada pela reconciliação");
    } else if precisa_parear {
        tracing::warn!(
            instance_id = db_id,
            estado = texto,
            "instância exige novo pareamento (QR); reconexão não resolve"
        );
    }

    ok_reply(
        &env,
        "ReconciliarConexaoInstanciaReply",
        serde_json::json!({
            "state": texto,
            "religada": religada,
            "precisa_parear": precisa_parear
        }),
    )
}

/// O que o estado, depois da tentativa de religar, significa para quem espera:
/// `(texto_do_banco, religada, precisa_parear)`.
///
/// A distinção que importa é entre "o servidor resolve" e "só o dono do celular
/// resolve" — é ela que decide se o cliente vê um aviso na tela ou se nem fica
/// sabendo que houve queda.
fn desfecho_da_religada(estado: ConnectionState) -> (&'static str, bool, bool) {
    match estado {
        ConnectionState::Connected => ("connected", true, false),
        // Socket aberto e sessão recusada: o aparelho foi desvinculado do lado
        // do WhatsApp. Nenhuma reconexão resolve — é QR na mão do usuário. Quem
        // avisa é a tela, por isso o sinalizador sobe até o cliente.
        ConnectionState::Connecting => ("connecting", false, true),
        ConnectionState::Disconnected => ("disconnected", false, true),
        // "Não sei" não vira alarme: o provedor pode ter engasgado, e mandar o
        // cliente parear um WhatsApp que talvez esteja no ar seria pior que
        // esperar o próximo ciclo.
        ConnectionState::Unknown => ("unknown", false, false),
    }
}

/// Carimba o estado no banco. Best-effort: a reconciliação não deve falhar
/// porque a escrita do estado falhou — o próximo tick tenta de novo.
async fn gravar_estado(env: &Envelope, db_id: i64, estado: &str) {
    let _ = chamar_data_postgres(
        "AtualizarEstadoInstancia",
        &env.tenant_id,
        serde_json::json!({
            "id": db_id,
            "connection_state": estado,
            "origem": "reconciliacao",
        }),
        env,
    )
    .await;
}

#[tracing::instrument(skip_all, fields(rpc = "GetWhatsappInstanceStatus", tenant_id = %env.tenant_id))]
async fn handler_get_whatsapp_instance_status(state: AppState, env: Envelope) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let db_id = match payload.get("id").and_then(|v| v.as_i64()) {
        Some(id) => id,
        None => return erro(error_core::AppError::Validation("id ausente".into()), &env),
    };

    let instance = match chamar_data_postgres(
        "GetWhatsappInstance",
        &env.tenant_id,
        serde_json::json!({ "id": db_id }),
        &env,
    )
    .await
    {
        Ok(inst) => inst,
        Err(e) => return erro(e, &env),
    };

    let name = match instance.get("name").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Database("não encontrado: Instância não encontrada".into()),
                &env,
            )
        }
    };

    let api_key = match instance.get("api_key").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("Chave da instância ausente".into()),
                &env,
            )
        }
    };

    let provider_name = instance
        .get("provider")
        .and_then(|v| v.as_str())
        .unwrap_or("evolution");
    let p = match state.registry.resolve(provider_name) {
        Ok(prov) => prov,
        Err(e) => return erro(error_core::AppError::Internal(e.to_string()), &env),
    };

    let api_key_sec = SecretString::from(api_key.to_string());

    // 1. Obtém o estado atual no provedor (agora exige token)
    let prov_state = match p.get_connection_state(name, &api_key_sec).await {
        Ok(s) => s,
        Err(e) => {
            tracing::warn!("Erro ao consultar estado da instância no provedor: {:?}", e);
            ConnectionState::Unknown
        }
    };

    let state_str = match prov_state {
        ConnectionState::Connected => "connected",
        ConnectionState::Disconnected => "disconnected",
        ConnectionState::Connecting => "connecting",
        ConnectionState::Unknown => "unknown",
    };

    // Atualiza o estado no banco
    let _ = chamar_data_postgres(
        "AtualizarEstadoInstancia",
        &env.tenant_id,
        serde_json::json!({ "id": db_id, "connection_state": state_str }),
        &env,
    )
    .await;

    // 2. Enquanto não estiver pareado, busca o QR.
    //
    // A condição era `Disconnected || Unknown`, o que deixava justamente
    // `Connecting` de fora — e `Connecting` é O estado da espera pelo
    // pareamento: socket de pé no provedor, sessão ainda não autenticada,
    // QR na tela aguardando leitura. A tela de conexão ficava girando sem
    // nunca receber o código.
    let mut qr_code = None;
    if prov_state != ConnectionState::Connected {
        if let Ok(qr) = p.get_qr_code(name, &api_key_sec).await {
            qr_code = Some(qr);
        }
    }

    ok_reply(
        &env,
        "GetWhatsappInstanceStatusReply",
        serde_json::json!({
            // Duas chaves para o mesmo valor, de propósito: o `control_plane`
            // lê `status` e a fachada gRPC-Web lê `connection_state`. Só
            // `status` existia, então a borda caía no default e o cliente
            // recebia "unknown" para sempre — a tela nunca via `connected` e
            // não avançava nem depois do pareamento.
            "status": state_str,
            "connection_state": state_str,
            "qr_code": qr_code,
        }),
    )
}

#[tracing::instrument(skip_all, fields(rpc = "SendWhatsappMessage", tenant_id = %env.tenant_id))]
async fn handler_send_whatsapp_message(state: AppState, env: Envelope) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let db_id = match payload.get("id").and_then(|v| v.as_i64()) {
        Some(id) => id,
        None => return erro(error_core::AppError::Validation("id ausente".into()), &env),
    };

    let to_number = match payload.get("to_number").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("to_number ausente".into()),
                &env,
            )
        }
    };

    let text = match payload.get("text").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("text ausente".into()),
                &env,
            )
        }
    };

    let instance = match chamar_data_postgres(
        "GetWhatsappInstance",
        &env.tenant_id,
        serde_json::json!({ "id": db_id }),
        &env,
    )
    .await
    {
        Ok(inst) => inst,
        Err(e) => return erro(e, &env),
    };

    let name = match instance.get("name").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Database("não encontrado: Instância não encontrada".into()),
                &env,
            )
        }
    };

    let api_key = match instance.get("api_key").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("Chave da instância ausente".into()),
                &env,
            )
        }
    };

    let provider_name = instance
        .get("provider")
        .and_then(|v| v.as_str())
        .unwrap_or("evolution");
    let p = match state.registry.resolve(provider_name) {
        Ok(prov) => prov,
        Err(e) => return erro(error_core::AppError::Internal(e.to_string()), &env),
    };

    let api_key_sec = SecretString::from(api_key.to_string());

    match p.send_text(name, &api_key_sec, to_number, text).await {
        Ok(res) => {
            observability::usage_metrics::registrar_mensagem(
                &env.tenant_id,
                observability::usage_metrics::DirecaoMensagem::Enviada,
            );
            ok_reply(
                &env,
                "SendWhatsappMessageReply",
                serde_json::json!({
                    "status": "success",
                    "message_id": res.message_id
                }),
            )
        }
        Err(e) => erro(
            error_core::AppError::Internal(format!("Falha ao enviar mensagem pelo provedor: {e}")),
            &env,
        ),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "SendWhatsappMedia", tenant_id = %env.tenant_id))]
async fn handler_send_whatsapp_media(state: AppState, env: Envelope) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let db_id = match payload.get("id").and_then(|v| v.as_i64()) {
        Some(id) => id,
        None => return erro(error_core::AppError::Validation("id ausente".into()), &env),
    };

    let to_number = match payload.get("to_number").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("to_number ausente".into()),
                &env,
            )
        }
    };

    let media_type_str = match payload.get("media_type").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("media_type ausente".into()),
                &env,
            )
        }
    };

    let media_url = match payload.get("media_url").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("media_url ausente".into()),
                &env,
            )
        }
    };

    let caption = payload.get("caption").and_then(|v| v.as_str());

    let media_type = match media_type_str.to_lowercase().as_str() {
        "image" => MediaType::Image,
        "video" => MediaType::Video,
        "audio" => MediaType::Audio,
        "document" => MediaType::Document,
        _ => {
            return erro(
                error_core::AppError::Validation(format!("media_type '{media_type_str}' inválido")),
                &env,
            )
        }
    };

    let instance = match chamar_data_postgres(
        "GetWhatsappInstance",
        &env.tenant_id,
        serde_json::json!({ "id": db_id }),
        &env,
    )
    .await
    {
        Ok(inst) => inst,
        Err(e) => return erro(e, &env),
    };

    let name = match instance.get("name").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Database("não encontrado: Instância não encontrada".into()),
                &env,
            )
        }
    };

    let api_key = match instance.get("api_key").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("Chave da instância ausente".into()),
                &env,
            )
        }
    };

    let provider_name = instance
        .get("provider")
        .and_then(|v| v.as_str())
        .unwrap_or("evolution");
    let p = match state.registry.resolve(provider_name) {
        Ok(prov) => prov,
        Err(e) => return erro(error_core::AppError::Internal(e.to_string()), &env),
    };

    let api_key_sec = SecretString::from(api_key.to_string());

    match p
        .send_media(
            name,
            &api_key_sec,
            to_number,
            media_type,
            media_url,
            caption,
        )
        .await
    {
        Ok(res) => ok_reply(
            &env,
            "SendWhatsappMediaReply",
            serde_json::json!({
                "status": "success",
                "message_id": res.message_id
            }),
        ),
        Err(e) => erro(
            error_core::AppError::Internal(format!("Falha ao enviar mídia pelo provedor: {e}")),
            &env,
        ),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "AdminBulkDisconnectInstances"))]
async fn handler_admin_bulk_disconnect(mut state: AppState, env: Envelope) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    // Apenas quem possui escopo "operacional:admin" pode prosseguir
    if !env.auth_scopes.contains(&"operacional:admin".to_string()) {
        return erro(
            error_core::AppError::Auth(
                "permissão insuficiente: Operação restrita a administradores operacionais".into(),
            ),
            &env,
        );
    }

    let tenant_id_opt = payload
        .get("tenant_id")
        .and_then(|v| v.as_str())
        .and_then(|s| Uuid::parse_str(s).ok())
        .filter(|id| !id.is_nil());

    let lista_res = if let Some(tenant_id) = tenant_id_opt {
        chamar_data_postgres(
            "ListWhatsappInstances",
            &tenant_id.to_string(),
            serde_json::json!({}),
            &env,
        )
        .await
    } else {
        chamar_data_postgres(
            "AdminListAllConnectedInstances",
            "00000000-0000-0000-0000-000000000000",
            serde_json::json!({}),
            &env,
        )
        .await
    };

    let insts = match lista_res {
        Ok(val) => match val
            .get("instances")
            .or_else(|| val.as_array().map(|_| &val))
        {
            Some(arr) => arr.as_array().cloned().unwrap_or_default(),
            None => Vec::new(),
        },
        Err(e) => return erro(e, &env),
    };

    let mut count = 0;
    for inst in insts {
        let name = inst.get("name").and_then(|v| v.as_str()).unwrap_or("");
        let api_key = inst.get("api_key").and_then(|v| v.as_str()).unwrap_or("");
        let id = inst.get("id").and_then(|v| v.as_i64()).unwrap_or(0);
        let inst_tenant = inst.get("tenant_id").and_then(|v| v.as_str()).unwrap_or("");

        if name.is_empty() || api_key.is_empty() || id == 0 {
            continue;
        }

        let provider_name = inst
            .get("provider")
            .and_then(|v| v.as_str())
            .unwrap_or("evolution");
        let p = match state.registry.resolve(provider_name) {
            Ok(prov) => prov,
            Err(_) => continue,
        };

        let api_key_sec = SecretString::from(api_key.to_string());
        // Tenta desconectar no provedor
        if let Err(e) = p.disconnect_instance(name, &api_key_sec).await {
            tracing::warn!("Erro ao desconectar instância {name} no provedor: {:?}", e);
        }

        // Atualiza estado no banco
        let _ = chamar_data_postgres(
            "AtualizarEstadoInstancia",
            inst_tenant,
            serde_json::json!({ "id": id, "connection_state": "disconnected" }),
            &env,
        )
        .await;

        count += 1;
    }

    // Publica auditoria admin global se necessário (ver comentário em
    // handler_create_instance sobre o formato exigido pelo consumidor).
    let escopo = if tenant_id_opt.is_some() { "tenant" } else { "global" };
    let audit_payload = observability::AuditLogPayload {
        tenant_id: tenant_id_opt,
        level: "WARN".to_string(),
        service: "data_whatsapp".to_string(),
        trace_id: Some(env.traceparent.clone()),
        event: "whatsapp.admin.bulk_disconnect".to_string(),
        message: format!("Desconexão em massa de {count} instância(s) WhatsApp ({escopo})"),
        context: serde_json::json!({ "count": count, "scope": escopo }),
        user_id: (env.auth_user_id > 0).then_some(env.auth_user_id),
        ip_address: None,
        user_agent: None,
    };
    let audit_event = TenantEnvelope::novo(
        tenant_id_opt.unwrap_or_else(Uuid::nil),
        "security.audit",
        audit_payload,
    )
    .com_traceparent(env.traceparent.clone());
    let _ = transport::bus::publicar_evento_seguranca(&mut state.redis_conn, &audit_event).await;

    ok_reply(
        &env,
        "AdminBulkDisconnectInstancesReply",
        serde_json::json!({
            "count": count,
            "scope": tenant_id_opt.map(|t| t.to_string()).unwrap_or_else(|| "global".to_string())
        }),
    )
}

#[tracing::instrument(skip_all, fields(rpc = "MarkWhatsappMessageRead", tenant_id = %env.tenant_id))]
async fn handler_mark_whatsapp_message_read(state: AppState, env: Envelope) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let db_id = match payload.get("id").and_then(|v| v.as_i64()) {
        Some(id) => id,
        None => return erro(error_core::AppError::Validation("id ausente".into()), &env),
    };

    let chat = match payload.get("chat").and_then(|v| v.as_str()) {
        Some(c) => c,
        None => {
            return erro(
                error_core::AppError::Validation("chat ausente".into()),
                &env,
            )
        }
    };

    let message_ids: Vec<String> = match payload.get("message_ids").and_then(|v| v.as_array()) {
        Some(arr) => arr
            .iter()
            .filter_map(|v| v.as_str().map(|s| s.to_string()))
            .collect(),
        None => {
            return erro(
                error_core::AppError::Validation("message_ids ausente ou inválido".into()),
                &env,
            )
        }
    };

    let instance = match chamar_data_postgres(
        "GetWhatsappInstance",
        &env.tenant_id,
        serde_json::json!({ "id": db_id }),
        &env,
    )
    .await
    {
        Ok(inst) => inst,
        Err(e) => return erro(e, &env),
    };

    let name = match instance.get("name").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Database("não encontrado: Instância não encontrada".into()),
                &env,
            )
        }
    };

    let api_key = match instance.get("api_key").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("Chave da instância ausente".into()),
                &env,
            )
        }
    };

    let provider_name = instance
        .get("provider")
        .and_then(|v| v.as_str())
        .unwrap_or("evolution");
    let p = match state.registry.resolve(provider_name) {
        Ok(prov) => prov,
        Err(e) => return erro(error_core::AppError::Internal(e.to_string()), &env),
    };

    let api_key_sec = SecretString::from(api_key.to_string());

    // LSP: capacidade ausente vira Unsupported (sem no-op/panic), mapeado para AppError.
    let receipts = match p.read_receipts() {
        Some(r) => r,
        None => {
            return erro(
                error_core::AppError::Internal(
                    MessagingProviderError::Unsupported("read_receipts").to_string(),
                ),
                &env,
            )
        }
    };

    match receipts
        .mark_read(name, &api_key_sec, chat, &message_ids)
        .await
    {
        Ok(_) => ok_reply(
            &env,
            "MarkWhatsappMessageReadReply",
            serde_json::json!({ "status": "success" }),
        ),
        Err(e) => erro(
            error_core::AppError::Internal(format!("Falha ao marcar como lido no provedor: {e}")),
            &env,
        ),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "SendWhatsappReaction", tenant_id = %env.tenant_id))]
async fn handler_send_whatsapp_reaction(state: AppState, env: Envelope) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let db_id = match payload.get("id").and_then(|v| v.as_i64()) {
        Some(id) => id,
        None => return erro(error_core::AppError::Validation("id ausente".into()), &env),
    };

    let chat = match payload.get("chat").and_then(|v| v.as_str()) {
        Some(c) => c,
        None => {
            return erro(
                error_core::AppError::Validation("chat ausente".into()),
                &env,
            )
        }
    };

    let message_id = match payload.get("message_id").and_then(|v| v.as_str()) {
        Some(m) => m,
        None => {
            return erro(
                error_core::AppError::Validation("message_id ausente".into()),
                &env,
            )
        }
    };

    let emoji = match payload.get("emoji").and_then(|v| v.as_str()) {
        Some(e) => e,
        None => {
            return erro(
                error_core::AppError::Validation("emoji ausente".into()),
                &env,
            )
        }
    };

    let from_me = payload
        .get("from_me")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    let instance = match chamar_data_postgres(
        "GetWhatsappInstance",
        &env.tenant_id,
        serde_json::json!({ "id": db_id }),
        &env,
    )
    .await
    {
        Ok(inst) => inst,
        Err(e) => return erro(e, &env),
    };

    let name = match instance.get("name").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Database("não encontrado: Instância não encontrada".into()),
                &env,
            )
        }
    };

    let api_key = match instance.get("api_key").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("Chave da instância ausente".into()),
                &env,
            )
        }
    };

    let provider_name = instance
        .get("provider")
        .and_then(|v| v.as_str())
        .unwrap_or("evolution");
    let p = match state.registry.resolve(provider_name) {
        Ok(prov) => prov,
        Err(e) => return erro(error_core::AppError::Internal(e.to_string()), &env),
    };

    let api_key_sec = SecretString::from(api_key.to_string());

    // LSP: capacidade ausente vira Unsupported (sem no-op/panic), mapeado para AppError.
    let reactions = match p.reactions() {
        Some(r) => r,
        None => {
            return erro(
                error_core::AppError::Internal(
                    MessagingProviderError::Unsupported("reactions").to_string(),
                ),
                &env,
            )
        }
    };

    match reactions
        .send_reaction(name, &api_key_sec, chat, message_id, emoji, from_me)
        .await
    {
        Ok(res) => ok_reply(
            &env,
            "SendWhatsappReactionReply",
            serde_json::json!({ "status": "success", "message_id": res.message_id }),
        ),
        Err(e) => erro(
            error_core::AppError::Internal(format!("Falha ao reagir à mensagem no provedor: {e}")),
            &env,
        ),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "SetWhatsappPresence", tenant_id = %env.tenant_id))]
async fn handler_set_whatsapp_presence(state: AppState, env: Envelope) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let db_id = match payload.get("id").and_then(|v| v.as_i64()) {
        Some(id) => id,
        None => return erro(error_core::AppError::Validation("id ausente".into()), &env),
    };

    let chat = match payload.get("chat").and_then(|v| v.as_str()) {
        Some(c) => c,
        None => {
            return erro(
                error_core::AppError::Validation("chat ausente".into()),
                &env,
            )
        }
    };

    let state_str = match payload.get("state").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("state ausente".into()),
                &env,
            )
        }
    };

    let is_audio = payload
        .get("is_audio")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    let presence_state = match state_str.to_lowercase().as_str() {
        "composing" => PresenceState::Composing,
        "recording" => PresenceState::Recording,
        "paused" => PresenceState::Paused,
        _ => {
            return erro(
                error_core::AppError::Validation(format!("state '{state_str}' inválido")),
                &env,
            )
        }
    };

    let instance = match chamar_data_postgres(
        "GetWhatsappInstance",
        &env.tenant_id,
        serde_json::json!({ "id": db_id }),
        &env,
    )
    .await
    {
        Ok(inst) => inst,
        Err(e) => return erro(e, &env),
    };

    let name = match instance.get("name").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Database("não encontrado: Instância não encontrada".into()),
                &env,
            )
        }
    };

    let api_key = match instance.get("api_key").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("Chave da instância ausente".into()),
                &env,
            )
        }
    };

    let provider_name = instance
        .get("provider")
        .and_then(|v| v.as_str())
        .unwrap_or("evolution");
    let p = match state.registry.resolve(provider_name) {
        Ok(prov) => prov,
        Err(e) => return erro(error_core::AppError::Internal(e.to_string()), &env),
    };

    let api_key_sec = SecretString::from(api_key.to_string());

    // LSP: capacidade ausente vira Unsupported (sem no-op/panic), mapeado para AppError.
    let presence = match p.presence() {
        Some(pr) => pr,
        None => {
            return erro(
                error_core::AppError::Internal(
                    MessagingProviderError::Unsupported("presence").to_string(),
                ),
                &env,
            )
        }
    };

    match presence
        .set_presence(name, &api_key_sec, chat, presence_state, is_audio)
        .await
    {
        Ok(_) => ok_reply(
            &env,
            "SetWhatsappPresenceReply",
            serde_json::json!({ "status": "success" }),
        ),
        Err(e) => erro(
            error_core::AppError::Internal(format!("Falha ao definir presença no provedor: {e}")),
            &env,
        ),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "GetWhatsappProfilePicture", tenant_id = %env.tenant_id))]
async fn handler_get_whatsapp_profile_picture(state: AppState, env: Envelope) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let db_id = match payload.get("id").and_then(|v| v.as_i64()) {
        Some(id) => id,
        None => return erro(error_core::AppError::Validation("id ausente".into()), &env),
    };

    let number = match payload.get("number").and_then(|v| v.as_str()) {
        Some(n) => n,
        None => {
            return erro(
                error_core::AppError::Validation("number ausente".into()),
                &env,
            )
        }
    };

    let instance = match chamar_data_postgres(
        "GetWhatsappInstance",
        &env.tenant_id,
        serde_json::json!({ "id": db_id }),
        &env,
    )
    .await
    {
        Ok(inst) => inst,
        Err(e) => return erro(e, &env),
    };

    let name = match instance.get("name").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Database("não encontrado: Instância não encontrada".into()),
                &env,
            )
        }
    };

    let api_key = match instance.get("api_key").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("Chave da instância ausente".into()),
                &env,
            )
        }
    };

    let provider_name = instance
        .get("provider")
        .and_then(|v| v.as_str())
        .unwrap_or("evolution");
    let p = match state.registry.resolve(provider_name) {
        Ok(prov) => prov,
        Err(e) => return erro(error_core::AppError::Internal(e.to_string()), &env),
    };

    let api_key_sec = SecretString::from(api_key.to_string());

    // LSP: capacidade ausente vira Unsupported (sem no-op/panic), mapeado para AppError.
    let profiles = match p.profiles() {
        Some(pr) => pr,
        None => {
            return erro(
                error_core::AppError::Internal(
                    MessagingProviderError::Unsupported("profile").to_string(),
                ),
                &env,
            )
        }
    };

    match profiles
        .get_profile_picture(name, &api_key_sec, number)
        .await
    {
        Ok(url) => ok_reply(
            &env,
            "GetWhatsappProfilePictureReply",
            serde_json::json!({ "url": url }),
        ),
        Err(e) => erro(
            error_core::AppError::Internal(format!(
                "Falha ao consultar foto de perfil no provedor: {e}"
            )),
            &env,
        ),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "DownloadWhatsappMedia", tenant_id = %env.tenant_id))]
async fn handler_download_whatsapp_media(state: AppState, env: Envelope) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => return erro(error_core::AppError::Validation(e.to_string()), &env),
    };

    let db_id = match payload.get("id").and_then(|v| v.as_i64()) {
        Some(id) => id,
        None => return erro(error_core::AppError::Validation("id ausente".into()), &env),
    };

    let message = match payload.get("message") {
        Some(m) if m.is_object() => m,
        _ => {
            return erro(
                error_core::AppError::Validation("message ausente ou inválido".into()),
                &env,
            )
        }
    };

    let instance = match chamar_data_postgres(
        "GetWhatsappInstance",
        &env.tenant_id,
        serde_json::json!({ "id": db_id }),
        &env,
    )
    .await
    {
        Ok(inst) => inst,
        Err(e) => return erro(e, &env),
    };

    let name = match instance.get("name").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Database("não encontrado: Instância não encontrada".into()),
                &env,
            )
        }
    };

    let api_key = match instance.get("api_key").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => {
            return erro(
                error_core::AppError::Validation("Chave da instância ausente".into()),
                &env,
            )
        }
    };

    let provider_name = instance
        .get("provider")
        .and_then(|v| v.as_str())
        .unwrap_or("evolution");
    let p = match state.registry.resolve(provider_name) {
        Ok(prov) => prov,
        Err(e) => return erro(error_core::AppError::Internal(e.to_string()), &env),
    };

    let api_key_sec = SecretString::from(api_key.to_string());

    // LSP: capacidade ausente vira Unsupported (sem no-op/panic), mapeado para AppError.
    let downloader = match p.media_downloader() {
        Some(d) => d,
        None => {
            return erro(
                error_core::AppError::Internal(
                    MessagingProviderError::Unsupported("download").to_string(),
                ),
                &env,
            )
        }
    };

    match downloader.download_media(name, &api_key_sec, message).await {
        Ok(res) => {
            // Limite de tamanho (env, default 20 MB — abaixo do teto de 25 MB das APIs
            // de transcrição). Acima do limite é erro tratável, nunca pânico.
            let max_bytes = limite_midia_bytes();
            let bytes_estimados = bytes_estimados_base64(res.base64.len());
            if bytes_estimados > max_bytes {
                return erro(
                    error_core::AppError::Validation(format!(
                        "mídia excede o limite de {max_bytes} bytes (estimado {bytes_estimados})"
                    )),
                    &env,
                );
            }
            ok_reply(
                &env,
                "DownloadWhatsappMediaReply",
                serde_json::json!({
                    "base64": res.base64,
                    "mime_type": res.mime_type
                }),
            )
        }
        Err(e) => erro(
            error_core::AppError::Internal(format!("Falha ao baixar mídia no provedor: {e}")),
            &env,
        ),
    }
}

/// Limite de tamanho de mídia baixada, em bytes. Configurável por
/// `SMARTCORE_MEDIA_MAX_BYTES`; default 20 MiB.
fn limite_midia_bytes() -> u64 {
    std::env::var("SMARTCORE_MEDIA_MAX_BYTES")
        .ok()
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(20 * 1024 * 1024)
}

/// Estima os bytes decodificados a partir do comprimento de uma string base64
/// (evita decodificar só para medir). base64 padrão: cada 4 chars ≈ 3 bytes.
fn bytes_estimados_base64(base64_len: usize) -> u64 {
    (base64_len as u64).saturating_mul(3) / 4
}

#[cfg(test)]
mod tests {
    use super::*;

    // --- O que a reconciliação conclui depois de tentar religar ---
    //
    // A regra que decide se o cliente é incomodado ou não. Errar aqui custa dos
    // dois lados: pedir QR de um WhatsApp saudável, ou ficar em silêncio
    // enquanto nenhuma mensagem entra.

    #[test]
    fn religada_com_sucesso_nao_incomoda_o_cliente() {
        let (texto, religada, parear) = desfecho_da_religada(ConnectionState::Connected);
        assert_eq!(texto, "connected");
        assert!(religada);
        assert!(!parear, "religou sozinho: o atendente nem precisa saber");
    }

    #[test]
    fn sessao_recusada_apos_religar_exige_pareamento() {
        // Socket aberto e sessão não confirmada DEPOIS de um connect é o retrato
        // do aparelho desvinculado pelo WhatsApp: reconectar de novo não muda
        // nada, só o QR resolve.
        let (texto, religada, parear) = desfecho_da_religada(ConnectionState::Connecting);
        assert_eq!(texto, "connecting");
        assert!(!religada);
        assert!(parear);
    }

    #[test]
    fn socket_que_nem_abriu_tambem_pede_pareamento() {
        let (texto, religada, parear) = desfecho_da_religada(ConnectionState::Disconnected);
        assert_eq!(texto, "disconnected");
        assert!(!religada);
        assert!(parear);
    }

    #[test]
    fn provedor_mudo_nao_vira_pedido_de_qr() {
        // "Não sei" não é "está fora". Mandar parear por causa de um provedor
        // que engasgou seria pior que esperar o próximo ciclo.
        let (texto, religada, parear) = desfecho_da_religada(ConnectionState::Unknown);
        assert_eq!(texto, "unknown");
        assert!(!religada);
        assert!(!parear);
    }
    use contracts::Envelope;
    use secrecy::SecretString;
    use transport::{Endpoint, Server};
    use wiremock::matchers::{method, path};
    use wiremock::Mock;
    use wiremock::MockServer;
    use wiremock::ResponseTemplate;

    // FakeProvider para provar o DIP e LSP nos testes
    struct FakeMessagingProvider;

    #[async_trait]
    impl InstanceManager for FakeMessagingProvider {
        fn provider_name(&self) -> &'static str {
            "fake"
        }
        async fn create_instance(
            &self,
            name: &str,
            custom_token: Option<&SecretString>,
        ) -> Result<CreateInstanceResult, MessagingProviderError> {
            let _ = (name, custom_token);
            Ok(CreateInstanceResult {
                provider_instance_id: "fake-id-123".to_string(),
                instance_token: "fake-token".to_string(),
            })
        }
        async fn delete_instance(&self, name: &str) -> Result<(), MessagingProviderError> {
            let _ = name;
            Ok(())
        }
        async fn connect_instance(
            &self,
            name: &str,
            token: &SecretString,
            webhook: &WebhookConfig,
        ) -> Result<(), MessagingProviderError> {
            let _ = (name, token, webhook);
            Ok(())
        }
        async fn disconnect_instance(
            &self,
            name: &str,
            token: &SecretString,
        ) -> Result<(), MessagingProviderError> {
            let _ = (name, token);
            Ok(())
        }
        async fn reconnect_instance(
            &self,
            name: &str,
            token: &SecretString,
        ) -> Result<(), MessagingProviderError> {
            let _ = (name, token);
            Ok(())
        }
        async fn get_qr_code(
            &self,
            name: &str,
            token: &SecretString,
        ) -> Result<String, MessagingProviderError> {
            let _ = (name, token);
            Ok("fake-qr".to_string())
        }
        async fn get_connection_state(
            &self,
            name: &str,
            token: &SecretString,
        ) -> Result<ConnectionState, MessagingProviderError> {
            let _ = (name, token);
            Ok(ConnectionState::Connected)
        }
        async fn list_all_instances(&self) -> Result<Vec<String>, MessagingProviderError> {
            Ok(vec!["fake-id-123".to_string()])
        }
    }

    #[async_trait]
    impl MessageSender for FakeMessagingProvider {
        async fn send_text(
            &self,
            name: &str,
            token: &SecretString,
            to: &str,
            text: &str,
        ) -> Result<SendMessageResult, MessagingProviderError> {
            let _ = (name, token, to, text);
            Ok(SendMessageResult {
                message_id: "fake-msg-id".to_string(),
            })
        }
        async fn send_media(
            &self,
            name: &str,
            token: &SecretString,
            to: &str,
            media: MediaType,
            url: &str,
            caption: Option<&str>,
        ) -> Result<SendMessageResult, MessagingProviderError> {
            let _ = (name, token, to, media, url, caption);
            Ok(SendMessageResult {
                message_id: "fake-media-id".to_string(),
            })
        }
    }

    impl MessagingProvider for FakeMessagingProvider {}

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

    async fn setup_test_env() -> (MockServer, AppState, tokio::task::JoinHandle<()>) {
        let wiremock_server = MockServer::start().await;

        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", "tcp://127.0.0.1:29292");
        std::env::set_var("SMARTCORE_DATA_POSTGRES_CODEC", "flatbuffers");

        let pg_server = Server::new(Endpoint::parse("tcp://127.0.0.1:29292").unwrap(), "flatbuffers")
            .route("CreateWhatsappInstanceRecord", |env| {
                Box::pin(async move {
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        payload: serde_json::to_vec(&serde_json::json!({ "id": 42 })).unwrap(),
                        ..env
                    }
                })
            })
            .route("GetWhatsappInstance", |env| {
                Box::pin(async move {
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        payload: serde_json::to_vec(&serde_json::json!({
                            "id": 42,
                            "name": "instancia-test",
                            "api_key": "inst-key-123",
                            "provider": "evolution"
                        })).unwrap(),
                        ..env
                    }
                })
            })
            .route("AdminDeletarInstancia", |env| {
                Box::pin(async move {
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        payload: serde_json::to_vec(&serde_json::json!({ "status": "success" })).unwrap(),
                        ..env
                    }
                })
            })
            .route("AtualizarInstanciaProviderId", |env| {
                Box::pin(async move {
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        payload: serde_json::to_vec(&serde_json::json!({ "status": "success" })).unwrap(),
                        ..env
                    }
                })
            })
            .route("AtualizarEstadoInstancia", |env| {
                Box::pin(async move {
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        payload: serde_json::to_vec(&serde_json::json!({ "status": "success" })).unwrap(),
                        ..env
                    }
                })
            })
            .route("ListWhatsappInstances", |env| {
                Box::pin(async move {
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        payload: serde_json::to_vec(&serde_json::json!({
                            "instances": [
                                { "id": 42, "name": "inst-1", "api_key": "key-1", "tenant_id": "00000000-0000-0000-0000-000000000001", "provider": "evolution" }
                            ]
                        })).unwrap(),
                        ..env
                    }
                })
            })
            .route("AdminListAllConnectedInstances", |env| {
                Box::pin(async move {
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        payload: serde_json::to_vec(&serde_json::json!([
                            { "id": 42, "name": "inst-1", "api_key": "key-1", "tenant_id": "00000000-0000-0000-0000-000000000001", "provider": "evolution" }
                        ])).unwrap(),
                        ..env
                    }
                })
            });

        let pg_handle = tokio::spawn(async move {
            let _ = pg_server.run().await;
        });

        tokio::time::sleep(tokio::time::Duration::from_millis(150)).await;

        let provider = EvolutionProvider::new(
            wiremock_server.uri(),
            SecretString::from("global-key".to_string()),
        );

        let registry = ProviderRegistry::builder()
            .register(std::sync::Arc::new(provider))
            .register(std::sync::Arc::new(FakeMessagingProvider))
            .build();

        let redis_conn = fake_bus(29257).await;

        let state = AppState {
            registry,
            redis_conn,
        };

        (wiremock_server, state, pg_handle)
    }

    #[tokio::test]
    async fn test_handler_create_whatsapp_instance() {
        let (server, state, pg_handle) = setup_test_env().await;

        Mock::given(method("POST"))
            .and(path("/instance/create"))
            .respond_with(ResponseTemplate::new(201).set_body_json(serde_json::json!({
                "instance": {
                    "instanceName": "instancia-test",
                    "token": "token-123"
                }
            })))
            .mount(&server)
            .await;

        Mock::given(method("POST"))
            .and(path("/instance/connect"))
            .respond_with(ResponseTemplate::new(200))
            .mount(&server)
            .await;

        Mock::given(method("PUT"))
            .and(path("/instance/instancia-test/advanced-settings"))
            .respond_with(ResponseTemplate::new(200))
            .mount(&server)
            .await;

        let payload = serde_json::json!({
            "instance_name": "instancia-test",
            "provider": "evolution"
        });

        let env = Envelope {
            kind: MessageKind::Request as i32,
            method: "CreateWhatsappInstance".to_string(),
            tenant_id: "00000000-0000-0000-0000-000000000001".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            ..Default::default()
        };

        let res = handler_create_whatsapp_instance(state, env).await;
        assert_eq!(res.kind, MessageKind::Reply as i32);
        let res_payload: serde_json::Value = serde_json::from_slice(&res.payload).unwrap();
        assert_eq!(
            res_payload.get("status").unwrap().as_str().unwrap(),
            "success"
        );
        assert_eq!(res_payload.get("id").unwrap().as_i64().unwrap(), 42);

        pg_handle.abort();
    }

    #[tokio::test]
    async fn test_handler_delete_whatsapp_instance() {
        let (server, state, pg_handle) = setup_test_env().await;

        Mock::given(method("DELETE"))
            .and(path("/instance/delete/instancia-test"))
            .respond_with(ResponseTemplate::new(200))
            .mount(&server)
            .await;

        let payload = serde_json::json!({
            "id": 42
        });

        let env = Envelope {
            kind: MessageKind::Request as i32,
            method: "DeleteWhatsappInstance".to_string(),
            tenant_id: "00000000-0000-0000-0000-000000000001".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            ..Default::default()
        };

        let res = handler_delete_whatsapp_instance(state, env).await;
        assert_eq!(res.kind, MessageKind::Reply as i32);
        let res_payload: serde_json::Value = serde_json::from_slice(&res.payload).unwrap();
        assert_eq!(
            res_payload.get("status").unwrap().as_str().unwrap(),
            "success"
        );

        pg_handle.abort();
    }

    #[tokio::test]
    async fn test_handler_reconnect_whatsapp_instance() {
        let (server, state, pg_handle) = setup_test_env().await;

        Mock::given(method("POST"))
            .and(path("/instance/reconnect"))
            .respond_with(ResponseTemplate::new(200))
            .mount(&server)
            .await;

        let payload = serde_json::json!({
            "id": 42
        });

        let env = Envelope {
            kind: MessageKind::Request as i32,
            method: "ReconnectWhatsappInstance".to_string(),
            tenant_id: "00000000-0000-0000-0000-000000000001".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            ..Default::default()
        };

        let res = handler_reconnect_whatsapp_instance(state, env).await;
        assert_eq!(res.kind, MessageKind::Reply as i32);
        let res_payload: serde_json::Value = serde_json::from_slice(&res.payload).unwrap();
        assert_eq!(
            res_payload.get("status").unwrap().as_str().unwrap(),
            "success"
        );

        pg_handle.abort();
    }

    #[tokio::test]
    async fn test_handler_get_whatsapp_instance_status() {
        let (server, state, pg_handle) = setup_test_env().await;

        Mock::given(method("GET"))
            .and(path("/instance/status"))
            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
                "state": "open"
            })))
            .mount(&server)
            .await;

        let payload = serde_json::json!({
            "id": 42
        });

        let env = Envelope {
            kind: MessageKind::Request as i32,
            method: "GetWhatsappInstanceStatus".to_string(),
            tenant_id: "00000000-0000-0000-0000-000000000001".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            ..Default::default()
        };

        let res = handler_get_whatsapp_instance_status(state, env).await;
        assert_eq!(res.kind, MessageKind::Reply as i32);
        let res_payload: serde_json::Value = serde_json::from_slice(&res.payload).unwrap();
        assert_eq!(
            res_payload.get("status").unwrap().as_str().unwrap(),
            "connected"
        );

        pg_handle.abort();
    }

    /// Regressao dupla da tela de conexao do WhatsApp.
    ///
    /// A evolution-go responde o pareamento pendente como
    /// `{"Connected": true, "LoggedIn": false}` — socket de pe, sessao ainda
    /// nao autenticada, ou seja `Connecting`. A condicao do QR era
    /// `Disconnected || Unknown` e deixava justamente esse estado de fora: a
    /// tela ficava girando sem nunca receber o codigo. E o reply so trazia
    /// `status`, enquanto a fachada gRPC-Web le `connection_state` — o cliente
    /// recebia "unknown" para sempre e nao avancava nem depois de parear.
    #[tokio::test]
    async fn test_status_pendente_devolve_qr_e_as_duas_chaves() {
        let (server, state, pg_handle) = setup_test_env().await;

        Mock::given(method("GET"))
            .and(path("/instance/status"))
            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
                "data": { "Connected": true, "LoggedIn": false, "Name": "" },
                "message": "success"
            })))
            .mount(&server)
            .await;

        Mock::given(method("GET"))
            .and(path("/instance/qr"))
            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
                "data": {
                    "qrcode": "data:image/png;base64,iVBORw0KG",
                    "code": "https://wa.me/settings/linked_devices#2@abc"
                },
                "message": "success"
            })))
            .mount(&server)
            .await;

        let env = Envelope {
            kind: MessageKind::Request as i32,
            method: "GetWhatsappInstanceStatus".to_string(),
            tenant_id: "00000000-0000-0000-0000-000000000001".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({ "id": 42 })).unwrap(),
            ..Default::default()
        };

        let res = handler_get_whatsapp_instance_status(state, env).await;
        assert_eq!(res.kind, MessageKind::Reply as i32);
        let corpo: serde_json::Value = serde_json::from_slice(&res.payload).unwrap();

        assert_eq!(corpo["status"], "connecting");
        // A fachada gRPC-Web le esta chave; sem ela o cliente via "unknown".
        assert_eq!(corpo["connection_state"], "connecting");
        // E a IMAGEM, nao o link: a tela desenha com `Image.memory`.
        assert_eq!(corpo["qr_code"], "data:image/png;base64,iVBORw0KG");

        pg_handle.abort();
    }

    #[tokio::test]
    async fn test_handler_send_whatsapp_message() {
        let (server, state, pg_handle) = setup_test_env().await;

        Mock::given(method("POST"))
            .and(path("/send/text"))
            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
                "key": {
                    "id": "msg-123"
                }
            })))
            .mount(&server)
            .await;

        let payload = serde_json::json!({
            "id": 42,
            "to_number": "5511999998888",
            "text": "Olá"
        });

        let env = Envelope {
            kind: MessageKind::Request as i32,
            method: "SendWhatsappMessage".to_string(),
            tenant_id: "00000000-0000-0000-0000-000000000001".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            ..Default::default()
        };

        let res = handler_send_whatsapp_message(state, env).await;
        assert_eq!(res.kind, MessageKind::Reply as i32);
        let res_payload: serde_json::Value = serde_json::from_slice(&res.payload).unwrap();
        assert_eq!(
            res_payload.get("status").unwrap().as_str().unwrap(),
            "success"
        );
        assert_eq!(
            res_payload.get("message_id").unwrap().as_str().unwrap(),
            "msg-123"
        );

        pg_handle.abort();
    }

    #[tokio::test]
    async fn test_handler_send_whatsapp_media() {
        let (server, state, pg_handle) = setup_test_env().await;

        Mock::given(method("POST"))
            .and(path("/send/media"))
            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
                "key": {
                    "id": "media-123"
                }
            })))
            .mount(&server)
            .await;

        let payload = serde_json::json!({
            "id": 42,
            "to_number": "5511999998888",
            "media_type": "image",
            "media_url": "http://media.url/image.png",
            "caption": "Foto"
        });

        let env = Envelope {
            kind: MessageKind::Request as i32,
            method: "SendWhatsappMedia".to_string(),
            tenant_id: "00000000-0000-0000-0000-000000000001".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            ..Default::default()
        };

        let res = handler_send_whatsapp_media(state, env).await;
        assert_eq!(res.kind, MessageKind::Reply as i32);
        let res_payload: serde_json::Value = serde_json::from_slice(&res.payload).unwrap();
        assert_eq!(
            res_payload.get("status").unwrap().as_str().unwrap(),
            "success"
        );
        assert_eq!(
            res_payload.get("message_id").unwrap().as_str().unwrap(),
            "media-123"
        );

        pg_handle.abort();
    }

    #[tokio::test]
    async fn test_handler_admin_bulk_disconnect() {
        let (server, state, pg_handle) = setup_test_env().await;

        Mock::given(method("DELETE"))
            .and(path("/instance/logout"))
            .respond_with(ResponseTemplate::new(200))
            .mount(&server)
            .await;

        let payload = serde_json::json!({
            "tenant_id": "00000000-0000-0000-0000-000000000001"
        });

        let env = Envelope {
            kind: MessageKind::Request as i32,
            method: "AdminBulkDisconnectInstances".to_string(),
            tenant_id: "00000000-0000-0000-0000-000000000001".to_string(),
            auth_scopes: vec!["operacional:admin".to_string()],
            payload: serde_json::to_vec(&payload).unwrap(),
            ..Default::default()
        };

        let res = handler_admin_bulk_disconnect(state, env).await;
        assert_eq!(res.kind, MessageKind::Reply as i32);
        let res_payload: serde_json::Value = serde_json::from_slice(&res.payload).unwrap();
        assert_eq!(res_payload.get("count").unwrap().as_i64().unwrap(), 1);

        pg_handle.abort();
    }

    #[tokio::test]
    async fn test_lsp_unsupported_error() {
        // Testa a resolução de provedor fake e retorno do erro Unsupported (LSP)
        let (_, _state, pg_handle) = setup_test_env().await;

        // O GetWhatsappInstance mockado retorna "provider": "evolution", mas se for um RPC de reações
        // que tenta usar o fake, mudamos o banco no mock do pg_server?
        // Sim, o pg_server de GetWhatsappInstance retorna "provider": "evolution".
        // Para simular o "fake", podemos fazer o gRPC de GetWhatsappInstance do flatbuffers retornar "fake".
        // No pg_server, o GetWhatsappInstance é hardcoded "evolution".
        // Mas podemos testar diretamente chamando handler_send_whatsapp_reaction em que a instância no banco está mockada.
        // Espera, para simular o GetWhatsappInstance retornando "fake", teríamos que mudar o gRPC mockado do flatbuffers.
        // Para simplificar, vamos criar outro gRPC mock para o banco? Não, não precisa de pg_server completo,
        // nos testes unitários podemos testar diretamente o comportamento de Unsupported resolvendo e chamando!
        // De qualquer forma, no data_postgres mockado que roda na 29292, podemos colocar "provider": "fake" para este teste!
        // No entanto, para não mudar o mock global pg_server, nos testes de integração podemos fazer:
        let pg_server_fake = Server::new(
            Endpoint::parse("tcp://127.0.0.1:29293").unwrap(),
            "flatbuffers",
        )
        .route("GetWhatsappInstance", |_env| {
            Box::pin(async move {
                Envelope {
                    kind: MessageKind::Reply as i32,
                    payload: serde_json::to_vec(&serde_json::json!({
                        "id": 42,
                        "name": "inst-fake",
                        "api_key": "inst-key-123",
                        "provider": "fake"
                    }))
                    .unwrap(),
                    .._env
                }
            })
        });

        let pg_handle_fake = tokio::spawn(async move {
            let _ = pg_server_fake.run().await;
        });
        tokio::time::sleep(tokio::time::Duration::from_millis(150)).await;

        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", "tcp://127.0.0.1:29293");

        let redis_conn = fake_bus(29258).await;
        let registry = ProviderRegistry::builder()
            .register(std::sync::Arc::new(FakeMessagingProvider))
            .build();

        let state_fake = AppState {
            registry,
            redis_conn,
        };

        let payload = serde_json::json!({
            "id": 42,
            "chat": "5511999998888",
            "message_id": "msg-123",
            "emoji": "❤️",
            "from_me": false
        });

        let env = Envelope {
            kind: MessageKind::Request as i32,
            method: "SendWhatsappReaction".to_string(),
            tenant_id: "00000000-0000-0000-0000-000000000001".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            ..Default::default()
        };

        let res = handler_send_whatsapp_reaction(state_fake, env).await;
        assert_eq!(res.kind, MessageKind::Error as i32);
        let err = res.error.unwrap();
        // Mensagem canônica do MessagingProviderError::Unsupported (LSP)
        assert!(
            err.message.contains("não suportada pelo provedor")
                && err.message.contains("reactions")
        );

        pg_handle_fake.abort();
        pg_handle.abort();
    }

    #[test]
    fn bytes_estimados_base64_aproxima_tres_quartos() {
        // 100 chars base64 ≈ 75 bytes decodificados.
        assert_eq!(bytes_estimados_base64(100), 75);
        assert_eq!(bytes_estimados_base64(0), 0);
        // Comprimento gigante não estoura (saturating_mul).
        assert!(bytes_estimados_base64(usize::MAX) > 0);
    }

    #[test]
    fn limite_midia_bytes_usa_default_e_override() {
        std::env::remove_var("SMARTCORE_MEDIA_MAX_BYTES");
        assert_eq!(limite_midia_bytes(), 20 * 1024 * 1024);

        std::env::set_var("SMARTCORE_MEDIA_MAX_BYTES", "1048576");
        assert_eq!(limite_midia_bytes(), 1_048_576);

        // Valor inválido cai no default.
        std::env::set_var("SMARTCORE_MEDIA_MAX_BYTES", "nao-numero");
        assert_eq!(limite_midia_bytes(), 20 * 1024 * 1024);
        std::env::remove_var("SMARTCORE_MEDIA_MAX_BYTES");
    }
}
