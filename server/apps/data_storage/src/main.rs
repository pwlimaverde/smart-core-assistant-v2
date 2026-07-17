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

    // N4.3: lifecycle do bucket como defesa em profundidade (best-effort — não
    // impede o boot). Margem conservadora sobre a retenção por plano (default 30d
    // da purga aplicativa): default 90d aqui, configurável por ambiente.
    let lifecycle_days: i32 = std::env::var("S3_LIFECYCLE_EXPIRATION_DAYS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(90);
    client.garantir_lifecycle(lifecycle_days).await;

    // N5.3: CORS do bucket para paridade Web. A mídia é entregue ao Flutter Web por
    // presign (origem cross-site), e o browser aplica CORS mesmo com URL assinada.
    // Origens permitidas vêm de S3_CORS_ALLOWED_ORIGINS (comma-separated); a origem
    // da verdade versionada é infra/r2-cors.json. Best-effort — não trava o boot.
    let cors_origins: Vec<String> = std::env::var("S3_CORS_ALLOWED_ORIGINS")
        .unwrap_or_default()
        .split(',')
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();
    client.garantir_cors(&cors_origins).await;

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
            // N4.2: medição de uso de armazenamento de mídia por tenant (contador
            // agregado — sem PII/nome de arquivo). Storage ainda não tem campo de
            // limite no plano (`tenants_plan`); por ora é medição, não bloqueio.
            observability::usage_metrics::registrar_midia_armazenada(&env.tenant_id);
            let res = serde_json::json!({ "uri": uri });
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "PutFileReply".to_string(),
                payload: serde_json::to_vec(&res).unwrap_or_default(),
                error: None,
                ..env
            }
        }
        Err(e) => responder_erro(
            error_core::AppError::Storage(e.to_string()),
            env,
            "PutFileReply",
        ),
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
        Err(e) => responder_erro(
            error_core::AppError::Storage(e.to_string()),
            env,
            "GetFileReply",
        ),
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

#[cfg(test)]
mod tests {
    use super::*;
    use contracts::{Envelope, MessageKind};

    #[test]
    fn test_extrair_file_name_ausente() {
        assert!(extrair_file_name(&serde_json::json!({})).is_none());
    }

    #[test]
    fn test_extrair_file_name_vazio() {
        assert!(extrair_file_name(&serde_json::json!({ "file_name": "" })).is_none());
    }

    #[test]
    fn test_extrair_file_name_apenas_espacos() {
        assert!(extrair_file_name(&serde_json::json!({ "file_name": "   " })).is_none());
    }

    #[test]
    fn test_extrair_file_name_presente_sem_espacos() {
        assert_eq!(
            extrair_file_name(&serde_json::json!({ "file_name": "documento.pdf" })),
            Some("documento.pdf".to_string())
        );
    }

    #[test]
    fn test_extrair_file_name_trim_de_espacos() {
        assert_eq!(
            extrair_file_name(&serde_json::json!({ "file_name": "  foto.jpg  " })),
            Some("foto.jpg".to_string())
        );
    }

    #[test]
    fn test_responder_erro_preenche_kind_e_method() {
        let env = Envelope {
            tenant_id: "550e8400-e29b-41d4-a716-446655440000".to_string(),
            traceparent: "00-trace123-span456-01".to_string(),
            message_id: "abc".to_string(),
            ..Default::default()
        };
        let app_err = error_core::AppError::Validation("campo obrigatório".to_string());
        let resp = responder_erro(app_err, env.clone(), "PutFileReply");

        assert_eq!(resp.kind, MessageKind::Error as i32);
        assert_eq!(resp.method, "PutFileReply");
        assert!(resp.error.is_some());
        assert_eq!(resp.tenant_id, env.tenant_id);
        assert_eq!(resp.traceparent, env.traceparent);
    }

    #[test]
    fn test_responder_erro_storage_preserva_contexto() {
        let env = Envelope {
            tenant_id: "550e8400-e29b-41d4-a716-446655440000".to_string(),
            traceparent: "00-trace999-span999-01".to_string(),
            ..Default::default()
        };
        let resp = responder_erro(
            error_core::AppError::Storage("S3 off".to_string()),
            env,
            "GetFileReply",
        );

        assert_eq!(resp.kind, MessageKind::Error as i32);
        assert_eq!(resp.method, "GetFileReply");
        assert!(resp.error.is_some());
    }

    #[test]
    fn test_responder_erro_method_presign() {
        let env = Envelope::default();
        let resp = responder_erro(
            error_core::AppError::Validation("file_name obrigatório".to_string()),
            env,
            "PresignFileReply",
        );
        assert_eq!(resp.method, "PresignFileReply");
        assert_eq!(resp.kind, MessageKind::Error as i32);
    }
}
