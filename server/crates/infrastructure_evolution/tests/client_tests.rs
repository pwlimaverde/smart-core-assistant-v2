use infrastructure_evolution::EvolutionProvider;
use infrastructure_messaging::{ConnectionState, MediaType, MessagingProvider};
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
        .and(body_json(serde_json::json!({
            "instanceName": "instancia-1",
            "qrcode": true,
            "integration": "WHATSAPP-BAILEYS"
        })))
        .respond_with(ResponseTemplate::new(201).set_body_json(serde_json::json!({
            "instance": {
                "instanceName": "instancia-1",
                "hash": "token-123"
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
            "instanceName": "instancia-1",
            "qrcode": true,
            "integration": "WHATSAPP-BAILEYS",
            "token": "custom-token-val"
        })))
        .respond_with(ResponseTemplate::new(201).set_body_json(serde_json::json!({
            "instance": {
                "instanceName": "instancia-1"
            },
            "hash": "custom-token-val"
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

    Mock::given(method("GET"))
        .and(path("/instance/connect/instancia-1"))
        .and(header("apikey", "inst-token"))
        .respond_with(ResponseTemplate::new(200))
        .mount(&server)
        .await;

    let token = SecretString::from("inst-token".to_string());
    let res = provider.connect_instance("instancia-1", &token).await;
    assert!(res.is_ok());
}

#[tokio::test]
async fn test_disconnect_instance() {
    let (server, provider) = setup().await;

    Mock::given(method("POST"))
        .and(path("/instance/logout/instancia-1"))
        .and(header("apikey", "inst-token"))
        .respond_with(ResponseTemplate::new(200))
        .mount(&server)
        .await;

    let token = SecretString::from("inst-token".to_string());
    let res = provider.disconnect_instance("instancia-1", &token).await;
    assert!(res.is_ok());
}

#[tokio::test]
async fn test_get_qr_code() {
    let (server, provider) = setup().await;
    let token = SecretString::from("inst-token".to_string());

    // Cenário 1: QR code direto na chave "code"
    Mock::given(method("GET"))
        .and(path("/instance/connect/instancia-1"))
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
        .and(path("/instance/connect/instancia-1"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "qrcode": {
                "code": "qr-code-nested"
            }
        })))
        .mount(&server)
        .await;

    let qr = provider.get_qr_code("instancia-1", &token).await.unwrap();
    assert_eq!(qr, "qr-code-nested");

    // Cenário 3: QR code em "qrcode.base64"
    server.reset().await;
    Mock::given(method("GET"))
        .and(path("/instance/connect/instancia-1"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "qrcode": {
                "base64": "qr-code-base64-nested"
            }
        })))
        .mount(&server)
        .await;

    let qr = provider.get_qr_code("instancia-1", &token).await.unwrap();
    assert_eq!(qr, "qr-code-base64-nested");

    // Cenário 4: QR code em "base64" na raiz
    server.reset().await;
    Mock::given(method("GET"))
        .and(path("/instance/connect/instancia-1"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "base64": "qr-code-base64-root"
        })))
        .mount(&server)
        .await;

    let qr = provider.get_qr_code("instancia-1", &token).await.unwrap();
    assert_eq!(qr, "qr-code-base64-root");
}

#[tokio::test]
async fn test_pair_by_phone() {
    let (server, provider) = setup().await;
    let token = SecretString::from("inst-token".to_string());

    Mock::given(method("POST"))
        .and(path("/instance/pairingCode/instancia-1"))
        .and(header("apikey", "inst-token"))
        .and(body_json(serde_json::json!({ "number": "5511999998888" })))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "code": "XYZ-ABC"
        })))
        .mount(&server)
        .await;

    let code = provider
        .pair_by_phone("instancia-1", &token, "5511999998888")
        .await
        .unwrap();
    assert_eq!(code, "XYZ-ABC");
}

#[tokio::test]
async fn test_configure_webhook() {
    let (server, provider) = setup().await;
    let token = SecretString::from("inst-token".to_string());

    Mock::given(method("PUT"))
        .and(path("/webhook/set/instancia-1"))
        .and(header("apikey", "inst-token"))
        .and(body_json(serde_json::json!({
            "enabled": true,
            "url": "http://webhook.url",
            "webhookByEvents": false,
            "events": ["E1", "E2"]
        })))
        .respond_with(ResponseTemplate::new(200))
        .mount(&server)
        .await;

    let res = provider
        .configure_webhook(
            "instancia-1",
            &token,
            "http://webhook.url",
            &["E1".to_string(), "E2".to_string()],
        )
        .await;
    assert!(res.is_ok());
}

#[tokio::test]
async fn test_get_connection_state() {
    let (server, provider) = setup().await;

    // Conectado ("open" -> Connected)
    Mock::given(method("GET"))
        .and(path("/instance/connectionState/instancia-1"))
        .and(header("apikey", "global-key"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "instance": {
                "state": "open"
            }
        })))
        .mount(&server)
        .await;

    let state = provider.get_connection_state("instancia-1").await.unwrap();
    assert_eq!(state, ConnectionState::Connected);

    // Desconectado ("close" -> Disdisconnected)
    server.reset().await;
    Mock::given(method("GET"))
        .and(path("/instance/connectionState/instancia-1"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "instance": {
                "state": "close"
            }
        })))
        .mount(&server)
        .await;

    let state = provider.get_connection_state("instancia-1").await.unwrap();
    assert_eq!(state, ConnectionState::Disconnected);

    // Conectando ("connecting" -> Connecting)
    server.reset().await;
    Mock::given(method("GET"))
        .and(path("/instance/connectionState/instancia-1"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "instance": {
                "state": "connecting"
            }
        })))
        .mount(&server)
        .await;

    let state = provider.get_connection_state("instancia-1").await.unwrap();
    assert_eq!(state, ConnectionState::Connecting);

    // Desconhecido ("outro" -> Unknown)
    server.reset().await;
    Mock::given(method("GET"))
        .and(path("/instance/connectionState/instancia-1"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "instance": {
                "state": "qualquer"
            }
        })))
        .mount(&server)
        .await;

    let state = provider.get_connection_state("instancia-1").await.unwrap();
    assert_eq!(state, ConnectionState::Unknown);
}

#[tokio::test]
async fn test_send_text() {
    let (server, provider) = setup().await;
    let token = SecretString::from("inst-token".to_string());

    Mock::given(method("POST"))
        .and(path("/message/sendText/instancia-1"))
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

    // Teste de Imagem com Legenda
    Mock::given(method("POST"))
        .and(path("/message/sendMedia/instancia-1"))
        .and(header("apikey", "inst-token"))
        .and(body_json(serde_json::json!({
            "number": "5511999998888",
            "media": "http://media.url/image.png",
            "mediatype": "image",
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
async fn test_list_all_instances() {
    let (server, provider) = setup().await;

    Mock::given(method("GET"))
        .and(path("/instance/fetchInstances"))
        .and(header("apikey", "global-key"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!([
            { "instanceName": "inst-1" },
            { "name": "inst-2" }
        ])))
        .mount(&server)
        .await;

    let instances = provider.list_all_instances().await.unwrap();
    assert_eq!(instances, vec!["inst-1".to_string(), "inst-2".to_string()]);
}
