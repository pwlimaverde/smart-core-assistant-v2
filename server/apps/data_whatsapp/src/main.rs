use contracts::{Envelope, MessageKind, TenantEnvelope};
use infrastructure_evolution::EvolutionProvider;
use infrastructure_messaging::{MediaType, MessagingProvider};
use secrecy::SecretString;
use std::env;
use std::time::Duration;
use transport::Server;
use uuid::Uuid;

#[derive(Clone)]
struct AppState {
    provider: EvolutionProvider,
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

    let redis_url =
        env::var("SMARTCORE_REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());

    let redis_client = redis::Client::open(redis_url)?;
    let redis_conn = redis::aio::ConnectionManager::new(redis_client.clone()).await?;

    let state = AppState {
        provider,
        redis_conn,
    };

    let s_create = state.clone();
    let s_delete = state.clone();
    let s_reconnect = state.clone();
    let s_status = state.clone();
    let s_send_text = state.clone();
    let s_send_media = state.clone();
    let s_bulk_disconnect = state;

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

    // 1. Cria a instância no provedor
    let result = match state.provider.create_instance(instance_name, None).await {
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
            let _ = state.provider.delete_instance(instance_name).await;
            return erro(e, &env);
        }
    };

    let db_id = match db_record.get("id").and_then(|v| v.as_i64()) {
        Some(id) => id,
        None => {
            let _ = state.provider.delete_instance(instance_name).await;
            return erro(
                error_core::AppError::Internal(
                    "ID de banco não retornado pelo data_postgres".into(),
                ),
                &env,
            );
        }
    };

    // 3. Configura o webhook apontando para o webhook_ingress
    let webhook_url = format!(
        "http://webhook_ingress:9200/webhook/{}/{}/{}",
        provider_name, env.tenant_id, db_id
    );

    if let Err(e) = state
        .provider
        .configure_webhook(
            instance_name,
            &instance_token,
            &webhook_url,
            &["MESSAGES_UPSERT".into(), "CONNECTION_UPDATE".into()],
        )
        .await
    {
        let _ = state.provider.delete_instance(instance_name).await;
        // Tenta remover o registro do banco
        let _ = chamar_data_postgres(
            "AdminDeletarInstancia",
            &env.tenant_id,
            serde_json::json!({ "id": db_id }),
            &env,
        )
        .await;
        return erro(
            error_core::AppError::Internal(format!(
                "Falha ao configurar webhook da instância: {e}"
            )),
            &env,
        );
    }

    // 4. Salva o provider_instance_id e tenta obter informações adicionais (como phone_number se conectado)
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

    // 5. Publica evento de auditoria no security:stream
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

    // 2. Remove do provedor
    if let Err(e) = state.provider.delete_instance(name).await {
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

    if let Err(e) = state
        .provider
        .connect_instance(name, &SecretString::from(api_key.to_string()))
        .await
    {
        return erro(
            error_core::AppError::Internal(format!("Falha ao conectar instância no provedor: {e}")),
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

    let api_key_sec = SecretString::from(api_key.to_string());

    // 1. Obtém o estado atual no provedor
    let prov_state = match state.provider.get_connection_state(name).await {
        Ok(s) => s,
        Err(e) => {
            tracing::warn!("Erro ao consultar estado da instância no provedor: {:?}", e);
            infrastructure_messaging::ConnectionState::Unknown
        }
    };

    let state_str = match prov_state {
        infrastructure_messaging::ConnectionState::Connected => "connected",
        infrastructure_messaging::ConnectionState::Disconnected => "disconnected",
        infrastructure_messaging::ConnectionState::Connecting => "connecting",
        infrastructure_messaging::ConnectionState::Unknown => "unknown",
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
    if prov_state == infrastructure_messaging::ConnectionState::Disconnected
        || prov_state == infrastructure_messaging::ConnectionState::Unknown
    {
        if let Ok(qr) = state.provider.get_qr_code(name, &api_key_sec).await {
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

    let api_key_sec = SecretString::from(api_key.to_string());

    match state
        .provider
        .send_text(name, &api_key_sec, to_number, text)
        .await
    {
        Ok(res) => ok_reply(
            &env,
            "SendWhatsappMessageReply",
            serde_json::json!({
                "status": "success",
                "message_id": res.message_id
            }),
        ),
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

    let api_key_sec = SecretString::from(api_key.to_string());

    match state
        .provider
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
async fn handler_admin_bulk_disconnect(state: AppState, env: Envelope) -> Envelope {
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

    // 1. Lista as instâncias ativas cross-tenant ou filtradas por tenant
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

        let api_key_sec = SecretString::from(api_key.to_string());
        // Tenta desconectar no provedor
        if let Err(e) = state.provider.disconnect_instance(name, &api_key_sec).await {
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

    ok_reply(
        &env,
        "AdminBulkDisconnectInstancesReply",
        serde_json::json!({
            "count": count,
            "scope": tenant_id_opt.map(|t| t.to_string()).unwrap_or_else(|| "global".to_string())
        }),
    )
}
