//! Serviço data_storage: provê RPC síncrono para upload, download e assinatura de URLs de mídia.
//! Também consome eventos de purga assíncrona de arquivos do barramento.

use contracts::{Envelope, MessageKind};
use infrastructure_storage::StorageClient;
use std::time::Duration;
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
    // Só o `Client` é necessário: o consumidor de purga abre a própria conexão
    // dedicada (o `Consumer` recebe o Client). Antes abria-se também um
    // `ConnectionManager` que ninguém usava, mantendo uma conexão ociosa por réplica.
    let redis_client = redis::Client::open(redis_url)?;
    tracing::info!("Cliente Redis do barramento pronto.");

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
    let consumidor_purga = transport::bus::nome_consumidor("data_storage_purge_consumer");
    let purge_consumer = transport::bus::Consumer::new(
        transport::bus::STREAM_EVENTOS,
        "data_storage_purge_group",
        consumidor_purga.clone(),
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

    // 4b. Reprocessamento periódico da PEL + varredura de DLQ do grupo de purga.
    //
    // `Consumer::run` relê a PEL só no boot. Uma deleção que falhe (R2 fora do ar,
    // credencial expirada) ficava pendente para sempre: o scheduler já marcou
    // `midia_purgada_em` e não republica, então o objeto permaneceria no bucket até
    // o lifecycle de 90 dias — dado do cliente retido além da política de retenção.
    //
    // Só toca em eventos parados há mais de `MIN_IDLE_REPROCESSAMENTO_MS`: o tick
    // roda em paralelo ao loop de consumo, e sem esse piso reprocessaria a purga que
    // o loop está executando neste instante (deleção duplicada no bucket).
    {
        let state_retry = state.clone();
        let bus_client_retry = redis_client.clone();
        let consumidor_retry = consumidor_purga.clone();
        let intervalo = std::env::var("SMARTCORE_PURGE_PEL_RETRY_SECS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(300u64);
        tokio::spawn(async move {
            let mut tick = tokio::time::interval(Duration::from_secs(intervalo));
            loop {
                tick.tick().await;
                let state_tick = state_retry.clone();
                let handler = move |evt: transport::bus::EventoBruto| {
                    let state = state_tick.clone();
                    async move {
                        if evt.event_type == "media.purge" {
                            processar_purga_midia(state, evt).await?;
                        }
                        Ok(())
                    }
                };
                if let Err(e) = transport::bus::reprocessar_pendentes_uma_vez(
                    &bus_client_retry,
                    transport::bus::STREAM_EVENTOS,
                    "data_storage_purge_group",
                    &consumidor_retry,
                    transport::bus::MIN_IDLE_REPROCESSAMENTO_MS,
                    handler,
                )
                .await
                {
                    tracing::warn!(
                        "Falha no reprocessamento periódico da PEL de purga: {:?}",
                        e
                    );
                }
            }
        });
    }

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

        // Tamanho ANTES de deletar: `tenants_storage_usage.total_bytes` é um
        // medidor de uso corrente, não um acumulado — a retenção precisa devolver
        // o espaço ao tenant, senão o enforce de quota (N8.3) bloquearia uploads
        // legítimos de um bucket já esvaziado. Best-effort: falha no HEAD só
        // significa "não soube quanto devolver", nunca aborta a purga.
        let bytes_liberados = state
            .client
            .tamanho(tenant_id, file_name)
            .await
            .unwrap_or_else(|e| {
                tracing::warn!(erro = %e, "falha ao consultar tamanho do objeto a purgar; uso de storage não será ajustado");
                None
            })
            .unwrap_or(0);

        state.client.delete(tenant_id, file_name).await?;

        if bytes_liberados > 0 {
            let env_ajuste = Envelope {
                tenant_id: tenant_id.to_string(),
                traceparent: envelope.traceparent.clone(),
                ..Default::default()
            };
            registrar_uso_storage(&env_ajuste, -bytes_liberados).await;
        }
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

/// N7.1 — QuotaGuard do recurso `"storage"` (mesmo padrão N4.2 do `data_whatsapp`):
/// consulta `CheckQuota` no data_postgres ANTES do upload ao R2. Modo log-only por
/// padrão (`SMARTCORE_QUOTA_ENFORCE=false`) — só loga e segue; vira bloqueio real
/// quando a flag é `true`. Falha na própria checagem é fail-open: não derruba o
/// upload por causa do guard.
///
/// `delta_bytes` é o quanto ESTE upload vai somar ao uso (já descontado o que a
/// chave ocupava, ver `handler_put_file`). O guard barra tanto quem já estourou o
/// limite quanto quem estouraria com este arquivo — sem isso, um único upload
/// grande passa livre porque a checagem olhava apenas o uso já acumulado.
async fn aplicar_quota_guard_storage(
    env: &Envelope,
    delta_bytes: i64,
) -> Result<(), error_core::AppError> {
    // Auditoria só no ponto de enforce real (invariante N4/N7): em log-only puro
    // (enforce=false) a quota excedida é apenas medição, não deve gerar evento de
    // auditoria. Por isso `auditar` acompanha a flag — o CheckQuota só publica
    // `quota.excedida` quando o guard de fato vai bloquear o upload.
    let enforce = std::env::var("SMARTCORE_QUOTA_ENFORCE")
        .map(|v| v.eq_ignore_ascii_case("true"))
        .unwrap_or(false);

    let status = match chamar_data_postgres(
        "CheckQuota",
        &env.tenant_id,
        serde_json::json!({ "recurso": "storage", "auditar": enforce, "delta": delta_bytes }),
        env,
    )
    .await
    {
        Ok(v) => v,
        Err(e) => {
            tracing::warn!(erro = %e, "falha ao verificar quota de storage; prosseguindo (fail-open)");
            return Ok(());
        }
    };

    // `excedido` já cobre os dois casos (uso acumulado e projeção com `delta`);
    // `excedido_projetado` só distingue qual deles disparou, para o log.
    let excedido = status
        .get("excedido")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    if !excedido {
        return Ok(());
    }

    if !enforce {
        tracing::warn!(
            projetado = status
                .get("excedido_projetado")
                .and_then(|v| v.as_bool())
                .unwrap_or(false),
            "quota de storage excedida (log-only; SMARTCORE_QUOTA_ENFORCE=false)"
        );
        return Ok(());
    }

    Err(error_core::AppError::RateLimit(
        "quota de armazenamento excedida".to_string(),
    ))
}

/// N7.1 — ajusta o uso de armazenamento do tenant. Best-effort (nunca falha a
/// operação já concluída por causa disso): erro só gera WARN. `delta_bytes`
/// negativo devolve espaço (purga de mídia).
async fn registrar_uso_storage(env: &Envelope, delta_bytes: i64) {
    if delta_bytes == 0 {
        return;
    }
    if let Err(e) = chamar_data_postgres(
        "RegisterStorageUsage",
        &env.tenant_id,
        serde_json::json!({ "delta_bytes": delta_bytes }),
        env,
    )
    .await
    {
        tracing::warn!(erro = %e, "falha ao registrar uso de storage (best-effort)");
    }
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

    // Tamanho já ocupado por esta chave (a mídia é content-addressable: o mesmo
    // áudio reenviado sobrescreve a MESMA chave e não consome espaço novo).
    // Só a diferença entra na contabilidade de quota — sem isto, cada reenvio
    // inflaria `tenants_storage_usage` sem ocupar um byte a mais no R2. Vem ANTES
    // do guard porque é a diferença (não o tamanho bruto) que o guard projeta.
    // Fail-open: se o HEAD falhar, assume chave nova (contabiliza tudo).
    let bytes_anteriores = client
        .tamanho(tenant_id, &file_name)
        .await
        .unwrap_or_else(|e| {
            tracing::warn!(erro = %e, "falha ao consultar tamanho anterior do objeto; contabilizando como chave nova");
            None
        })
        .unwrap_or(0);
    let delta_bytes = conteudo.len() as i64 - bytes_anteriores;

    // N7.1: guard de quota de storage ANTES do upload (log-only por padrão),
    // já considerando o custo deste arquivo.
    if let Err(e) = aplicar_quota_guard_storage(&env, delta_bytes).await {
        return responder_erro(e, env, "PutFileReply");
    }

    match client.put(tenant_id, &file_name, &conteudo).await {
        Ok(uri) => {
            // N4.2: contador agregado de arquivos (sem PII/nome de arquivo).
            observability::usage_metrics::registrar_midia_armazenada(&env.tenant_id);
            // N7.1: uso em bytes persistido no data_postgres, para a próxima checagem
            // de quota de storage (best-effort — não falha o upload já concluído).
            registrar_uso_storage(&env, delta_bytes).await;
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

    // ------------------------------------------------------------------
    // Ramos de validação dos handlers RPC. Todos retornam ANTES de tocar o
    // R2 (rede), então exercitam a lógica de validação sem I/O externo. O
    // `StorageClient` é montado por `from_env` (só constrói o cliente S3; não
    // conecta) com credenciais fictícias — o caminho de sucesso (put/get/presign
    // reais) é integração opt-in, fora do escopo unitário.
    // ------------------------------------------------------------------

    /// Monta um `StorageClient` fictício sem conectar (from_env só constrói).
    fn dummy_storage_client() -> StorageClient {
        std::env::set_var("S3_ENDPOINT", "http://127.0.0.1:9000");
        std::env::set_var("S3_ACCESS_KEY_ID", "test-key");
        std::env::set_var("S3_SECRET_ACCESS_KEY", "test-secret");
        std::env::set_var("S3_BUCKET", "test-bucket");
        StorageClient::from_env().expect("from_env deveria montar o cliente sem conectar")
    }

    /// Monta um Envelope de requisição com payload JSON serializado.
    fn env_com_payload(payload: serde_json::Value) -> Envelope {
        Envelope {
            tenant_id: "550e8400-e29b-41d4-a716-446655440000".to_string(),
            traceparent: "00-trace-span-01".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            ..Default::default()
        }
    }

    #[tokio::test]
    async fn handler_put_file_sem_file_name_responde_validation() {
        let client = dummy_storage_client();
        let env = env_com_payload(serde_json::json!({ "content_base64": "AAAA" }));
        let resp = handler_put_file(client, env).await;
        assert_eq!(resp.kind, MessageKind::Error as i32);
        assert_eq!(resp.method, "PutFileReply");
        assert!(resp.error.is_some());
    }

    #[tokio::test]
    async fn handler_put_file_sem_content_base64_responde_validation() {
        let client = dummy_storage_client();
        let env = env_com_payload(serde_json::json!({ "file_name": "a.pdf" }));
        let resp = handler_put_file(client, env).await;
        assert_eq!(resp.kind, MessageKind::Error as i32);
        assert_eq!(resp.method, "PutFileReply");
    }

    #[tokio::test]
    async fn handler_put_file_content_base64_invalido_responde_validation() {
        let client = dummy_storage_client();
        let env = env_com_payload(serde_json::json!({
            "file_name": "a.pdf",
            "content_base64": "!!! não é base64 !!!"
        }));
        let resp = handler_put_file(client, env).await;
        assert_eq!(resp.kind, MessageKind::Error as i32);
        assert_eq!(resp.method, "PutFileReply");
    }

    #[tokio::test]
    async fn handler_get_file_sem_file_name_responde_validation() {
        let client = dummy_storage_client();
        let env = env_com_payload(serde_json::json!({}));
        let resp = handler_get_file(client, env).await;
        assert_eq!(resp.kind, MessageKind::Error as i32);
        assert_eq!(resp.method, "GetFileReply");
    }

    #[tokio::test]
    async fn handler_presign_file_sem_file_name_responde_validation() {
        let client = dummy_storage_client();
        let env = env_com_payload(serde_json::json!({ "expires_in": 120 }));
        let resp = handler_presign_file(client, env).await;
        assert_eq!(resp.kind, MessageKind::Error as i32);
        assert_eq!(resp.method, "PresignFileReply");
    }

    #[tokio::test]
    async fn handler_put_file_tenant_invalido_ainda_valida_payload() {
        // tenant_id inválido cai em Uuid::nil() (não é erro); a validação de payload
        // segue normalmente — aqui falta content_base64 → Validation.
        let client = dummy_storage_client();
        let env = Envelope {
            tenant_id: "não-é-uuid".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({ "file_name": "x.bin" })).unwrap(),
            ..Default::default()
        };
        let resp = handler_put_file(client, env).await;
        assert_eq!(resp.kind, MessageKind::Error as i32);
        assert_eq!(resp.method, "PutFileReply");
    }
}
