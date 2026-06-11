//! Serviço data_storage: provê RPC síncrono para upload, download e assinatura de URLs de mídia.
//! Também consome eventos de purga assíncrona de arquivos do barramento.

use contracts::{Envelope, MessageKind};
use infrastructure_storage::StorageClient;
use transport::Server;
use uuid::Uuid;

#[derive(Clone)]
struct AppState {
    client: StorageClient,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // 1. Inicializa observabilidade
    observability::init_telemetry("data_storage", "production")
        .map_err(|e| anyhow::anyhow!(e.to_string()))?;
    tracing::info!("Iniciando serviço data_storage...");

    // 2. Conecta ao Redis para o barramento de purga
    let redis_url =
        std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
    let redis_client = redis::Client::open(redis_url)?;
    let _redis_conn = redis::aio::ConnectionManager::new(redis_client.clone()).await?;
    tracing::info!("Conexão com Redis estabelecida.");

    // 3. Inicializa o cliente de storage S3-compatible (MinIO em dev / R2 em prod)
    //    a partir das variáveis S3_* e garante a existência do bucket.
    let client = StorageClient::from_env()?;
    client.garantir_bucket().await?;
    tracing::info!(bucket = %client.bucket(), "cliente de storage S3 pronto.");

    let state = AppState { client };

    // 4. Inicia o Consumidor de Purga de Mídia em background
    let state_clone = state.clone();
    let purge_consumer = transport::bus::Consumer::new(
        transport::bus::STREAM_EVENTOS,
        "data_storage_purge_group",
        "data_storage_purge_consumer",
        redis_client.clone(),
    );
    let purge_handle = tokio::spawn(async move {
        if let Err(e) = purge_consumer
            .run(move |evt| {
                let state = state_clone.clone();
                async move {
                    if evt.event_type == "media.purge" {
                        processar_purga_midia(state, evt).await?;
                    }
                    Ok(())
                }
            })
            .await
        {
            tracing::error!("Consumidor de purga parou com erro crítico: {:?}", e);
        }
    });

    // 5. Inicia o Servidor RPC síncrono nos 3 protocolos
    let state_clone2 = state.clone();
    let state_for_put = state_clone2.clone();
    let state_for_get = state_clone2.clone();
    let state_for_presign = state_clone2;

    let server = Server::from_env("DATA_STORAGE")
        .route("PutFile", move |env| {
            let state = state_for_put.clone();
            Box::pin(async move { handler_put_file(state.client, env).await })
        })
        .route("GetFile", move |env| {
            let state = state_for_get.clone();
            Box::pin(async move { handler_get_file(state.client, env).await })
        })
        .route("PresignFile", move |env| {
            let state = state_for_presign.clone();
            Box::pin(async move { handler_presign_file(state.client, env).await })
        });

    tracing::info!("Servidor RPC do data_storage configurado e pronto.");

    tokio::select! {
        res = server.run() => {
            if let Err(e) = res {
                tracing::error!("Servidor RPC parou com erro crítico: {:?}", e);
            }
        }
        _ = purge_handle => {}
    }

    Ok(())
}

async fn processar_purga_midia(
    state: AppState,
    evt: transport::bus::EventoBruto,
) -> anyhow::Result<()> {
    let envelope = evt.desserializar::<serde_json::Value>()?;
    let file_name = envelope
        .payload
        .get("file_name")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let tenant_id = envelope.tenant_id;

    if !file_name.is_empty() {
        tracing::info!(
            file_name = %file_name,
            tenant_id = %tenant_id,
            "Purga assíncrona: iniciando deleção física do arquivo de mídia."
        );
        state.client.delete(tenant_id, file_name).await?;
    }

    Ok(())
}

/// Extrai e valida o `file_name` do payload JSON da requisição.
/// Devolve `None` quando ausente/vazio — o caller responde erro de validação.
fn extrair_file_name(payload_json: &serde_json::Value) -> Option<String> {
    payload_json
        .get("file_name")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(String::from)
}

/// Resposta de erro padronizada dos handlers de storage.
fn responder_erro(app_err: error_core::AppError, env: Envelope, method: &str) -> Envelope {
    let err_env = app_err.to_error_envelope(&env.traceparent, "data_storage");
    Envelope {
        kind: MessageKind::Error as i32,
        method: method.to_string(),
        error: Some(err_env),
        ..env
    }
}

async fn handler_put_file(client: StorageClient, env: Envelope) -> Envelope {
    let tenant_id = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());

    // O payload carrega o nome e o conteúdo (base64), já que o `method` do Envelope
    // é o nome da rota RPC e não pode transportar o nome do arquivo.
    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let Some(file_name) = extrair_file_name(&payload_json) else {
        return responder_erro(
            error_core::AppError::Validation("file_name obrigatório no payload".to_string()),
            env,
            "PutFileReply",
        );
    };
    let conteudo = match payload_json
        .get("content_base64")
        .and_then(|v| v.as_str())
        .map(|s| base64::Engine::decode(&base64::engine::general_purpose::STANDARD, s))
    {
        Some(Ok(bytes)) => bytes,
        Some(Err(e)) => {
            return responder_erro(
                error_core::AppError::Validation(format!("content_base64 inválido: {e}")),
                env,
                "PutFileReply",
            );
        }
        None => {
            return responder_erro(
                error_core::AppError::Validation(
                    "content_base64 obrigatório no payload".to_string(),
                ),
                env,
                "PutFileReply",
            );
        }
    };

    match client.put(tenant_id, &file_name, &conteudo).await {
        Ok(uri) => {
            let res = serde_json::json!({ "uri": uri });
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "PutFileReply".to_string(),
                payload: serde_json::to_vec(&res).unwrap_or_default(),
                error: None,
                ..env
            }
        }
        Err(e) => responder_erro(error_core::AppError::Storage(e.to_string()), env, "PutFileReply"),
    }
}

async fn handler_get_file(client: StorageClient, env: Envelope) -> Envelope {
    let tenant_id = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());

    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let Some(file_name) = extrair_file_name(&payload_json) else {
        return responder_erro(
            error_core::AppError::Validation("file_name obrigatório no payload".to_string()),
            env,
            "GetFileReply",
        );
    };

    match client.get(tenant_id, &file_name).await {
        Ok(data) => Envelope {
            kind: MessageKind::Reply as i32,
            method: "GetFileReply".to_string(),
            payload: data,
            error: None,
            ..env
        },
        Err(e) => responder_erro(error_core::AppError::Storage(e.to_string()), env, "GetFileReply"),
    }
}

async fn handler_presign_file(client: StorageClient, env: Envelope) -> Envelope {
    let tenant_id = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());

    let payload_json: serde_json::Value =
        serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}));
    let Some(file_name) = extrair_file_name(&payload_json) else {
        return responder_erro(
            error_core::AppError::Validation("file_name obrigatório no payload".to_string()),
            env,
            "PresignFileReply",
        );
    };
    // Janela de validade da URL pré-assinada (segundos); default 1 hora.
    let expires_in = payload_json
        .get("expires_in")
        .and_then(|v| v.as_u64())
        .unwrap_or(3600);

    match client.presign(tenant_id, &file_name, expires_in).await {
        Ok(url) => {
            let res = serde_json::json!({ "url": url });
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "PresignFileReply".to_string(),
                payload: serde_json::to_vec(&res).unwrap_or_default(),
                error: None,
                ..env
            }
        }
        Err(e) => responder_erro(
            error_core::AppError::Storage(e.to_string()),
            env,
            "PresignFileReply",
        ),
    }
}
