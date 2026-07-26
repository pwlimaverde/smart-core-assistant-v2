use infrastructure_evolution::EvolutionProvider;
#[allow(unused_imports)]
use infrastructure_messaging::{
    AdvancedSettings, AdvancedSettingsControl, ConnectionState, CreateInstanceResult,
    InstanceManager, MediaDownloadResult, MediaDownloader, MediaType, MessageSender,
    MessagingProvider, MessagingProviderError, PresenceControl, PresenceState, ProfileQuery,
    Reactions, ReadReceipts, SendMessageResult, WebhookConfig,
};
use secrecy::SecretString;
use wiremock::matchers::{body_json, header, method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

async fn setup() -> (MockServer, EvolutionProvider) {
    let mock_server = MockServer::start().await;
    let provider = EvolutionProvider::new(
        mock_server.uri(),
        SecretString::from("global-key".to_string()),
    );
    (mock_server, provider)
}

#[tokio::test]
async fn test_provider_name() {
    let (_, provider) = setup().await;
    assert_eq!(provider.provider_name(), "evolution");
}

#[tokio::test]
async fn test_create_instance_success() {
    let (server, provider) = setup().await;

    Mock::given(method("POST"))
        .and(path("/instance/create"))
        .and(header("apikey", "global-key"))
        .respond_with(ResponseTemplate::new(201).set_body_json(serde_json::json!({
            "instance": {
                "instanceName": "instancia-1",
                "token": "token-123"
            }
        })))
        .mount(&server)
        .await;

    let res = provider.create_instance("instancia-1", None).await.unwrap();
    assert_eq!(res.provider_instance_id, "instancia-1");
    assert_eq!(res.instance_token, "token-123");
}

#[tokio::test]
async fn test_create_instance_with_custom_token() {
    let (server, provider) = setup().await;

    Mock::given(method("POST"))
        .and(path("/instance/create"))
        .and(body_json(serde_json::json!({
            "name": "instancia-1",
            "token": "custom-token-val"
        })))
        .respond_with(ResponseTemplate::new(201).set_body_json(serde_json::json!({
            "instance": {
                "instanceName": "instancia-1",
                "token": "custom-token-val"
            }
        })))
        .mount(&server)
        .await;

    let custom_sec = SecretString::from("custom-token-val".to_string());
    let res = provider
        .create_instance("instancia-1", Some(&custom_sec))
        .await
        .unwrap();
    assert_eq!(res.provider_instance_id, "instancia-1");
    assert_eq!(res.instance_token, "custom-token-val");
}

#[tokio::test]
async fn test_delete_instance() {
    let (server, provider) = setup().await;

    Mock::given(method("DELETE"))
        .and(path("/instance/delete/instancia-1"))
        .and(header("apikey", "global-key"))
        .respond_with(ResponseTemplate::new(200))
        .mount(&server)
        .await;

    let res = provider.delete_instance("instancia-1").await;
    assert!(res.is_ok());
}

#[tokio::test]
async fn test_connect_instance() {
    let (server, provider) = setup().await;

    Mock::given(method("POST"))
        .and(path("/instance/connect"))
        .and(header("apikey", "inst-token"))
        .and(body_json(serde_json::json!({
            "instanceName": "instancia-1",
            "webhookUrl": "http://webhook.url",
            "subscribe": ["MESSAGE", "CONNECTION"],
            "immediate": true
        })))
        .respond_with(ResponseTemplate::new(200))
        .mount(&server)
        .await;

    let token = SecretString::from("inst-token".to_string());
    let webhook = WebhookConfig {
        url: "http://webhook.url".to_string(),
        subscribe: vec!["MESSAGE".to_string(), "CONNECTION".to_string()],
    };
    let res = provider
        .connect_instance("instancia-1", &token, &webhook)
        .await;
    assert!(res.is_ok());
}

#[tokio::test]
async fn test_disconnect_instance() {
    let (server, provider) = setup().await;

    Mock::given(method("DELETE"))
        .and(path("/instance/logout"))
        .and(header("apikey", "inst-token"))
        .respond_with(ResponseTemplate::new(200))
        .mount(&server)
        .await;

    let token = SecretString::from("inst-token".to_string());
    let res = provider.disconnect_instance("instancia-1", &token).await;
    assert!(res.is_ok());
}

#[tokio::test]
async fn test_reconnect_instance() {
    let (server, provider) = setup().await;

    Mock::given(method("POST"))
        .and(path("/instance/reconnect"))
        .and(header("apikey", "inst-token"))
        .respond_with(ResponseTemplate::new(200))
        .mount(&server)
        .await;

    let token = SecretString::from("inst-token".to_string());
    let res = provider.reconnect_instance("instancia-1", &token).await;
    assert!(res.is_ok());
}

#[tokio::test]
async fn test_get_qr_code() {
    let (server, provider) = setup().await;
    let token = SecretString::from("inst-token".to_string());

    // Cenário 1: QR code direto na raiz na chave "code"
    Mock::given(method("GET"))
        .and(path("/instance/qr"))
        .and(header("apikey", "inst-token"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "code": "qr-code-direct"
        })))
        .mount(&server)
        .await;

    let qr = provider.get_qr_code("instancia-1", &token).await.unwrap();
    assert_eq!(qr, "qr-code-direct");

    // Cenário 2: QR code aninhado em "qrcode.code"
    server.reset().await;
    Mock::given(method("GET"))
        .and(path("/instance/qr"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "qrcode": {
                "code": "qr-code-nested"
            }
        })))
        .mount(&server)
        .await;

    let qr = provider.get_qr_code("instancia-1", &token).await.unwrap();
    assert_eq!(qr, "qr-code-nested");
}

#[tokio::test]
async fn test_get_connection_state() {
    let (server, provider) = setup().await;
    let token = SecretString::from("inst-token".to_string());

    // Conectado ("open" -> Connected)
    Mock::given(method("GET"))
        .and(path("/instance/status"))
        .and(header("apikey", "inst-token"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "state": "open"
        })))
        .mount(&server)
        .await;

    let state = provider
        .get_connection_state("instancia-1", &token)
        .await
        .unwrap();
    assert_eq!(state, ConnectionState::Connected);

    // Desconectado ("close" -> Disconnected)
    server.reset().await;
    Mock::given(method("GET"))
        .and(path("/instance/status"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "state": "close"
        })))
        .mount(&server)
        .await;

    let state = provider
        .get_connection_state("instancia-1", &token)
        .await
        .unwrap();
    assert_eq!(state, ConnectionState::Disconnected);
}

#[tokio::test]
async fn test_list_all_instances() {
    let (server, provider) = setup().await;

    Mock::given(method("GET"))
        .and(path("/instance/all"))
        .and(header("apikey", "global-key"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "data": [
                { "instanceName": "inst-1" },
                { "name": "inst-2" }
            ]
        })))
        .mount(&server)
        .await;

    let instances = provider.list_all_instances().await.unwrap();
    assert_eq!(instances, vec!["inst-1".to_string(), "inst-2".to_string()]);
}

#[tokio::test]
async fn test_send_text() {
    let (server, provider) = setup().await;
    let token = SecretString::from("inst-token".to_string());

    Mock::given(method("POST"))
        .and(path("/send/text"))
        .and(header("apikey", "inst-token"))
        .and(body_json(serde_json::json!({
            "number": "5511999998888",
            "text": "Olá Mundo"
        })))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "key": {
                "id": "msg-id-123"
            }
        })))
        .mount(&server)
        .await;

    let res = provider
        .send_text("instancia-1", &token, "5511999998888", "Olá Mundo")
        .await
        .unwrap();
    assert_eq!(res.message_id, "msg-id-123");
}

#[tokio::test]
async fn test_send_media() {
    let (server, provider) = setup().await;
    let token = SecretString::from("inst-token".to_string());

    Mock::given(method("POST"))
        .and(path("/send/media"))
        .and(header("apikey", "inst-token"))
        .and(body_json(serde_json::json!({
            "number": "5511999998888",
            "type": "image",
            "url": "http://media.url/image.png",
            "caption": "Minha imagem"
        })))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "key": {
                "id": "media-id-123"
            }
        })))
        .mount(&server)
        .await;

    let res = provider
        .send_media(
            "instancia-1",
            &token,
            "5511999998888",
            MediaType::Image,
            "http://media.url/image.png",
            Some("Minha imagem"),
        )
        .await
        .unwrap();
    assert_eq!(res.message_id, "media-id-123");
}

#[tokio::test]
async fn test_presence_control() {
    let (server, provider) = setup().await;
    let token = SecretString::from("inst-token".to_string());

    Mock::given(method("POST"))
        .and(path("/message/presence"))
        .and(header("apikey", "inst-token"))
        .and(body_json(serde_json::json!({
            "number": "5511999998888",
            "state": "recording",
            "isAudio": true
        })))
        .respond_with(ResponseTemplate::new(200))
        .mount(&server)
        .await;

    let presence = provider.presence().unwrap();
    let res = presence
        .set_presence(
            "instancia-1",
            &token,
            "5511999998888",
            PresenceState::Recording,
            true,
        )
        .await;
    assert!(res.is_ok());
}

#[tokio::test]
async fn test_read_receipts() {
    let (server, provider) = setup().await;
    let token = SecretString::from("inst-token".to_string());

    Mock::given(method("POST"))
        .and(path("/message/markread"))
        .and(header("apikey", "inst-token"))
        .and(body_json(serde_json::json!({
            "number": "5511999998888",
            "id": ["msg-1", "msg-2"]
        })))
        .respond_with(ResponseTemplate::new(200))
        .mount(&server)
        .await;

    let receipts = provider.read_receipts().unwrap();
    let res = receipts
        .mark_read(
            "instancia-1",
            &token,
            "5511999998888",
            &["msg-1".to_string(), "msg-2".to_string()],
        )
        .await;
    assert!(res.is_ok());
}

#[tokio::test]
async fn test_reactions() {
    let (server, provider) = setup().await;
    let token = SecretString::from("inst-token".to_string());

    Mock::given(method("POST"))
        .and(path("/message/react"))
        .and(header("apikey", "inst-token"))
        .and(body_json(serde_json::json!({
            "number": "5511999998888",
            "reaction": "❤️",
            "id": "msg-123",
            "fromMe": false
        })))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "id": "msg-123"
        })))
        .mount(&server)
        .await;

    let reactions = provider.reactions().unwrap();
    let res = reactions
        .send_reaction(
            "instancia-1",
            &token,
            "5511999998888",
            "msg-123",
            "❤️",
            false,
        )
        .await
        .unwrap();
    assert_eq!(res.message_id, "msg-123");
}

#[tokio::test]
async fn test_media_downloader() {
    let (server, provider) = setup().await;
    let token = SecretString::from("inst-token".to_string());

    Mock::given(method("POST"))
        .and(path("/message/downloadmedia"))
        .and(header("apikey", "inst-token"))
        .and(body_json(serde_json::json!({
            "message": { "imageMessage": { "url": "http://media" } }
        })))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "base64": "SGVsbG8=",
            "mimetype": "image/png"
        })))
        .mount(&server)
        .await;

    let downloader = provider.media_downloader().unwrap();
    let res = downloader
        .download_media(
            "instancia-1",
            &token,
            &serde_json::json!({ "imageMessage": { "url": "http://media" } }),
        )
        .await
        .unwrap();
    assert_eq!(res.base64, "SGVsbG8=");
    assert_eq!(res.mime_type, Some("image/png".to_string()));
}

#[tokio::test]
async fn test_profile_query() {
    let (server, provider) = setup().await;
    let token = SecretString::from("inst-token".to_string());

    Mock::given(method("POST"))
        .and(path("/user/avatar"))
        .and(header("apikey", "inst-token"))
        .and(body_json(serde_json::json!({
            "number": "5511999998888",
            "preview": false
        })))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "url": "http://profile-pic"
        })))
        .mount(&server)
        .await;

    let profiles = provider.profiles().unwrap();
    let res = profiles
        .get_profile_picture("instancia-1", &token, "5511999998888")
        .await
        .unwrap();
    assert_eq!(res, Some("http://profile-pic".to_string()));
}

#[tokio::test]
async fn test_set_advanced_settings() {
    let (server, provider) = setup().await;
    let token = SecretString::from("inst-token".to_string());

    Mock::given(method("PUT"))
        .and(path("/instance/inst-uuid-1/advanced-settings"))
        .and(header("apikey", "inst-token"))
        .and(body_json(serde_json::json!({
            "alwaysOnline": true,
            "readMessages": false,
            "rejectCall": true,
            "msgRejectCall": "Desculpe, não aceito chamadas.",
            "ignoreGroups": false,
            "ignoreStatus": true
        })))
        .respond_with(ResponseTemplate::new(200))
        .mount(&server)
        .await;

    let adv = provider.advanced_settings().unwrap();
    let settings = AdvancedSettings {
        always_online: true,
        read_messages: false,
        reject_call: true,
        msg_reject_call: "Desculpe, não aceito chamadas.".to_string(),
        ignore_groups: false,
        ignore_status: true,
    };
    let res = adv
        .set_advanced_settings("inst-uuid-1", &token, settings)
        .await;
    assert!(res.is_ok());
}

// ---------------------------------------------------------------------------
// Ramos de fallback/erro/retry — cobrem os caminhos secundários do provider que
// os testes de caminho feliz acima não exercitam.
// ---------------------------------------------------------------------------

#[tokio::test]
async fn test_create_instance_token_no_campo_raiz() {
    // Sem `instance.token`; o token vem do campo `token` na raiz da resposta.
    let (server, provider) = setup().await;
    Mock::given(method("POST"))
        .and(path("/instance/create"))
        .respond_with(ResponseTemplate::new(201).set_body_json(serde_json::json!({
            "instance": { "instanceName": "inst-x" },
            "token": "token-raiz"
        })))
        .mount(&server)
        .await;

    let res = provider.create_instance("inst-x", None).await.unwrap();
    assert_eq!(res.instance_token, "token-raiz");
}

#[tokio::test]
async fn test_create_instance_token_no_hash_string() {
    // `hash` como string simples é usado quando não há `token`.
    let (server, provider) = setup().await;
    Mock::given(method("POST"))
        .and(path("/instance/create"))
        .respond_with(ResponseTemplate::new(201).set_body_json(serde_json::json!({
            "instance": { "instanceName": "inst-x" },
            "hash": "hash-como-string"
        })))
        .mount(&server)
        .await;

    let res = provider.create_instance("inst-x", None).await.unwrap();
    assert_eq!(res.instance_token, "hash-como-string");
}

#[tokio::test]
async fn test_create_instance_token_no_hash_objeto_apikey() {
    // `hash` como objeto `{ "apikey": ... }` (formato de versões novas da Evolution).
    let (server, provider) = setup().await;
    Mock::given(method("POST"))
        .and(path("/instance/create"))
        .respond_with(ResponseTemplate::new(201).set_body_json(serde_json::json!({
            "instance": { "instanceName": "inst-x" },
            "hash": { "apikey": "apikey-do-hash" }
        })))
        .mount(&server)
        .await;

    let res = provider.create_instance("inst-x", None).await.unwrap();
    assert_eq!(res.instance_token, "apikey-do-hash");
}

#[tokio::test]
async fn test_create_instance_fallback_para_token_gerado() {
    // Sem token/hash na resposta: cai no token gerado localmente (custom_token aqui).
    let (server, provider) = setup().await;
    Mock::given(method("POST"))
        .and(path("/instance/create"))
        .respond_with(ResponseTemplate::new(201).set_body_json(serde_json::json!({
            "instance": { "instanceName": "inst-x" }
        })))
        .mount(&server)
        .await;

    let custom = SecretString::from("token-local".to_string());
    let res = provider
        .create_instance("inst-x", Some(&custom))
        .await
        .unwrap();
    assert_eq!(res.instance_token, "token-local");
}

#[tokio::test]
async fn test_create_instance_erro_api() {
    // Status != 2xx → ok_or_api devolve ProviderApi.
    let (server, provider) = setup().await;
    Mock::given(method("POST"))
        .and(path("/instance/create"))
        .respond_with(ResponseTemplate::new(500).set_body_string("erro interno"))
        .mount(&server)
        .await;

    let err = provider.create_instance("inst-x", None).await.unwrap_err();
    assert!(matches!(
        err,
        MessagingProviderError::ProviderApi { status: 500, .. }
    ));
}

#[tokio::test]
async fn test_get_qr_code_base64_na_raiz() {
    let (server, provider) = setup().await;
    let token = SecretString::from("t".to_string());
    Mock::given(method("GET"))
        .and(path("/instance/qr"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "base64": "b64-raiz"
        })))
        .mount(&server)
        .await;

    let qr = provider.get_qr_code("inst", &token).await.unwrap();
    assert_eq!(qr, "b64-raiz");
}

#[tokio::test]
async fn test_get_qr_code_base64_aninhado() {
    let (server, provider) = setup().await;
    let token = SecretString::from("t".to_string());
    Mock::given(method("GET"))
        .and(path("/instance/qr"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "qrcode": { "base64": "b64-aninhado" }
        })))
        .mount(&server)
        .await;

    let qr = provider.get_qr_code("inst", &token).await.unwrap();
    assert_eq!(qr, "b64-aninhado");
}

#[tokio::test]
async fn test_get_qr_code_sem_codigo_retorna_erro() {
    let (server, provider) = setup().await;
    let token = SecretString::from("t".to_string());
    Mock::given(method("GET"))
        .and(path("/instance/qr"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({})))
        .mount(&server)
        .await;

    let err = provider.get_qr_code("inst", &token).await.unwrap_err();
    assert!(matches!(err, MessagingProviderError::Deserialization(_)));
}

#[tokio::test]
async fn test_get_connection_state_connecting_e_unknown() {
    let (server, provider) = setup().await;
    let token = SecretString::from("t".to_string());

    Mock::given(method("GET"))
        .and(path("/instance/status"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "state": "connecting"
        })))
        .mount(&server)
        .await;
    assert_eq!(
        provider.get_connection_state("i", &token).await.unwrap(),
        ConnectionState::Connecting
    );

    server.reset().await;
    Mock::given(method("GET"))
        .and(path("/instance/status"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "state": "estado-esquisito"
        })))
        .mount(&server)
        .await;
    assert_eq!(
        provider.get_connection_state("i", &token).await.unwrap(),
        ConnectionState::Unknown
    );
}

#[tokio::test]
async fn test_list_all_instances_array_na_raiz_e_vazio() {
    let (server, provider) = setup().await;

    // Array direto na raiz (sem envelope "data").
    Mock::given(method("GET"))
        .and(path("/instance/all"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!([
            { "name": "somente-name" }
        ])))
        .mount(&server)
        .await;
    let nomes = provider.list_all_instances().await.unwrap();
    assert_eq!(nomes, vec!["somente-name".to_string()]);

    // Resposta sem array → lista vazia.
    server.reset().await;
    Mock::given(method("GET"))
        .and(path("/instance/all"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({ "outro": 1 })))
        .mount(&server)
        .await;
    assert!(provider.list_all_instances().await.unwrap().is_empty());
}

#[tokio::test]
async fn test_send_text_id_na_raiz() {
    // Resposta com `id` na raiz (sem `key`).
    let (server, provider) = setup().await;
    let token = SecretString::from("t".to_string());
    Mock::given(method("POST"))
        .and(path("/send/text"))
        .respond_with(
            ResponseTemplate::new(200).set_body_json(serde_json::json!({ "id": "id-raiz" })),
        )
        .mount(&server)
        .await;

    let res = provider.send_text("i", &token, "5511", "oi").await.unwrap();
    assert_eq!(res.message_id, "id-raiz");
}

#[tokio::test]
async fn test_send_text_retry_apos_5xx_e_sucesso() {
    // Primeiro 503 (server error → retentável), depois 200 com sucesso.
    let (server, provider) = setup().await;
    let token = SecretString::from("t".to_string());
    Mock::given(method("POST"))
        .and(path("/send/text"))
        .respond_with(ResponseTemplate::new(503))
        .up_to_n_times(1)
        .mount(&server)
        .await;
    Mock::given(method("POST"))
        .and(path("/send/text"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "key": { "id": "apos-retry" }
        })))
        .mount(&server)
        .await;

    let res = provider.send_text("i", &token, "5511", "oi").await.unwrap();
    assert_eq!(res.message_id, "apos-retry");
}

#[tokio::test]
async fn test_send_text_esgota_retries_retorna_erro() {
    // Todas as tentativas retornam 503 → esgota e devolve erro de rede.
    let (server, provider) = setup().await;
    let token = SecretString::from("t".to_string());
    Mock::given(method("POST"))
        .and(path("/send/text"))
        .respond_with(ResponseTemplate::new(503))
        .mount(&server)
        .await;

    let err = provider
        .send_text("i", &token, "5511", "oi")
        .await
        .unwrap_err();
    assert!(matches!(err, MessagingProviderError::Network(_)));
}

#[tokio::test]
async fn test_send_text_erro_4xx_nao_retenta() {
    // 400 não é server_error nem 429 → vai direto ao ok_or_api → ProviderApi.
    let (server, provider) = setup().await;
    let token = SecretString::from("t".to_string());
    Mock::given(method("POST"))
        .and(path("/send/text"))
        .respond_with(ResponseTemplate::new(400).set_body_string("numero invalido"))
        .mount(&server)
        .await;

    let err = provider
        .send_text("i", &token, "5511", "oi")
        .await
        .unwrap_err();
    assert!(matches!(
        err,
        MessagingProviderError::ProviderApi { status: 400, .. }
    ));
}

#[tokio::test]
async fn test_send_media_id_na_raiz() {
    let (server, provider) = setup().await;
    let token = SecretString::from("t".to_string());
    Mock::given(method("POST"))
        .and(path("/send/media"))
        .respond_with(
            ResponseTemplate::new(200).set_body_json(serde_json::json!({ "id": "media-raiz" })),
        )
        .mount(&server)
        .await;

    let res = provider
        .send_media(
            "i",
            &token,
            "5511",
            MediaType::Document,
            "http://u/doc.pdf",
            None,
        )
        .await
        .unwrap();
    assert_eq!(res.message_id, "media-raiz");
}

#[tokio::test]
async fn test_send_media_esgota_retries_retorna_erro() {
    let (server, provider) = setup().await;
    let token = SecretString::from("t".to_string());
    Mock::given(method("POST"))
        .and(path("/send/media"))
        .respond_with(ResponseTemplate::new(500))
        .mount(&server)
        .await;

    let err = provider
        .send_media(
            "i",
            &token,
            "5511",
            MediaType::Video,
            "http://u/v.mp4",
            None,
        )
        .await
        .unwrap_err();
    assert!(matches!(err, MessagingProviderError::Network(_)));
}

#[tokio::test]
async fn test_get_profile_picture_prioriza_profile_picture_url() {
    let (server, provider) = setup().await;
    let token = SecretString::from("t".to_string());
    Mock::given(method("POST"))
        .and(path("/user/avatar"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "profilePictureUrl": "http://foto-principal",
            "url": "http://foto-alternativa"
        })))
        .mount(&server)
        .await;

    let res = provider
        .get_profile_picture("i", &token, "5511")
        .await
        .unwrap();
    assert_eq!(res, Some("http://foto-principal".to_string()));
}

#[tokio::test]
async fn test_get_profile_picture_status_nao_sucesso_retorna_none() {
    // Falha do endpoint de avatar não é erro: devolve None (sem foto).
    let (server, provider) = setup().await;
    let token = SecretString::from("t".to_string());
    Mock::given(method("POST"))
        .and(path("/user/avatar"))
        .respond_with(ResponseTemplate::new(404))
        .mount(&server)
        .await;

    let res = provider
        .get_profile_picture("i", &token, "5511")
        .await
        .unwrap();
    assert_eq!(res, None);
}

#[tokio::test]
async fn test_send_reaction_fallback_para_message_id() {
    // Resposta sem id/key → usa o próprio message_id enviado como resultado.
    let (server, provider) = setup().await;
    let token = SecretString::from("t".to_string());
    Mock::given(method("POST"))
        .and(path("/message/react"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({})))
        .mount(&server)
        .await;

    let reactions = provider.reactions().unwrap();
    let res = reactions
        .send_reaction("i", &token, "5511", "msg-original", "👍", true)
        .await
        .unwrap();
    assert_eq!(res.message_id, "msg-original");
}

/// Uma Evolution que aceita a conexão e NUNCA responde não pode pendurar o
/// chamador para sempre: sem timeout no cliente HTTP, o handler RPC do
/// `data_whatsapp` ficaria preso indefinidamente (e as tasks se acumulariam a cada
/// reenvio do worker, que desiste em 5s). O teste cobra o teto de tempo.
#[tokio::test]
async fn envio_com_provedor_pendurado_falha_por_timeout() {
    // Arrange: teto curto para o teste não esperar os 60s de produção.
    std::env::set_var("SMARTCORE_EVOLUTION_HTTP_TIMEOUT_SECS", "1");
    let server = MockServer::start().await;
    let provider =
        EvolutionProvider::new(server.uri(), SecretString::from("global-key".to_string()));
    std::env::remove_var("SMARTCORE_EVOLUTION_HTTP_TIMEOUT_SECS");

    // Provedor que demora MUITO mais que o teto configurado.
    Mock::given(method("POST"))
        .and(path("/send/text"))
        .respond_with(
            ResponseTemplate::new(200)
                .set_delay(std::time::Duration::from_secs(30))
                .set_body_json(serde_json::json!({})),
        )
        .mount(&server)
        .await;

    let token = SecretString::from("t".to_string());
    let inicio = std::time::Instant::now();

    // Act
    let err = provider
        .send_text("i", &token, "5511999998888", "oi")
        .await
        .unwrap_err();

    // Assert: erro de rede (timeout) e não espera de 30s.
    assert!(
        matches!(err, MessagingProviderError::Network(_)),
        "esperado Network(timeout), obteve: {err:?}"
    );
    assert!(
        inicio.elapsed() < std::time::Duration::from_secs(15),
        "a chamada deveria ter sido cortada pelo timeout, levou {:?}",
        inicio.elapsed()
    );
}

#[tokio::test]
async fn test_delete_instance_erro_api() {
    let (server, provider) = setup().await;
    Mock::given(method("DELETE"))
        .and(path("/instance/delete/inst"))
        .respond_with(ResponseTemplate::new(404).set_body_string("nao existe"))
        .mount(&server)
        .await;

    let err = provider.delete_instance("inst").await.unwrap_err();
    assert!(matches!(
        err,
        MessagingProviderError::ProviderApi { status: 404, .. }
    ));
}
