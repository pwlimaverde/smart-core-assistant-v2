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
    server.run().await?;
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

    // 6. Publica evento de auditoria no security:stream
    let tenant_uuid = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());
    let auth_user_id = env.auth_user_id;
    let audit_event = TenantEnvelope::novo(
        tenant_uuid,
        "whatsapp.instance.create",
        serde_json::json!({
            "user_id": auth_user_id,
            "instance_name": instance_name,
            "provider": provider_name,
        }),
    );

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

    // 4. Publica auditoria
    let tenant_uuid = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());
    let auth_user_id = env.auth_user_id;
    let audit_event = TenantEnvelope::novo(
        tenant_uuid,
        "whatsapp.instance.delete",
        serde_json::json!({
            "user_id": auth_user_id,
            "instance_name": name,
        }),
    );
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

    // 2. Se desconectado ou unknown, tenta obter o QR code
    let mut qr_code = None;
    if prov_state == ConnectionState::Disconnected || prov_state == ConnectionState::Unknown {
        if let Ok(qr) = p.get_qr_code(name, &api_key_sec).await {
            qr_code = Some(qr);
        }
    }

    ok_reply(
        &env,
        "GetWhatsappInstanceStatusReply",
        serde_json::json!({
            "status": state_str,
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
        .and_then(|s| Uuid::parse_str(s).ok());

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

    // Publica auditoria admin global se necessário
    let tenant_uuid = tenant_id_opt.unwrap_or_else(Uuid::nil);
    let auth_user_id = env.auth_user_id;
    let audit_event = TenantEnvelope::novo(
        tenant_uuid,
        "whatsapp.admin.bulk_disconnect",
        serde_json::json!({
            "user_id": auth_user_id,
            "count": count,
            "scope": if tenant_id_opt.is_some() { "tenant" } else { "global" }
        }),
    );
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
        Ok(res) => ok_reply(
            &env,
            "DownloadWhatsappMediaReply",
            serde_json::json!({
                "base64": res.base64,
                "mime_type": res.mime_type
            }),
        ),
        Err(e) => erro(
            error_core::AppError::Internal(format!("Falha ao baixar mídia no provedor: {e}")),
            &env,
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
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
}
