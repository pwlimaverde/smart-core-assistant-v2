use infrastructure_messaging::MessagingProviderError;
use secrecy::SecretString;
use serde::Deserialize;

/// Cliente REST do Evolution API. `reqwest::Client` mantém pool interno e é barato de clonar.
#[derive(Clone)]
pub struct EvolutionProvider {
    pub(crate) http: reqwest::Client,
    pub(crate) base_url: String,
    pub(crate) global_api_key: SecretString, // gerencia instâncias; NUNCA logar
}

impl EvolutionProvider {
    pub fn new(base_url: impl Into<String>, global_api_key: SecretString) -> Self {
        Self {
            http: reqwest::Client::new(),
            base_url: base_url.into(),
            global_api_key,
        }
    }

    /// Trata a resposta HTTP: erro de rede vira Network, status != 2xx vira ProviderApi
    /// com o body truncado a 200 chars (evita vazar PII/segredo em logs).
    pub(crate) async fn ok_or_api(
        resp: reqwest::Response,
    ) -> Result<reqwest::Response, MessagingProviderError> {
        if resp.status().is_success() {
            Ok(resp)
        } else {
            let status = resp.status().as_u16();
            let body = resp.text().await.unwrap_or_default();
            let body = body.chars().take(200).collect::<String>();
            Err(MessagingProviderError::ProviderApi { status, body })
        }
    }
}

#[derive(Deserialize, Debug)]
#[allow(dead_code)]
pub(crate) struct CreateInstanceInner {
    #[serde(rename = "instanceName")]
    pub(crate) instance_name: String,
    #[serde(rename = "instanceId")]
    pub(crate) instance_id: Option<String>,
    pub(crate) id: Option<String>,
    pub(crate) token: Option<String>,
}

#[derive(Deserialize, Debug)]
pub(crate) struct CreateInstanceResp {
    pub(crate) instance: CreateInstanceInner,
    pub(crate) token: Option<String>,
    pub(crate) hash: Option<serde_json::Value>, // pode ser string ou objeto {"apikey": "..."}
}

#[derive(Deserialize, Debug)]
pub(crate) struct ConnStateResp {
    pub(crate) state: String,
}

#[derive(Deserialize, Debug)]
pub(crate) struct QrCodeInner {
    pub(crate) code: Option<String>,
    pub(crate) base64: Option<String>,
}

#[derive(Deserialize, Debug)]
pub(crate) struct QrCodeResp {
    pub(crate) code: Option<String>,
    pub(crate) base64: Option<String>,
    pub(crate) qrcode: Option<QrCodeInner>,
}

#[derive(Deserialize, Debug)]
pub(crate) struct MessageKey {
    pub(crate) id: String,
}

#[derive(Deserialize, Debug)]
pub(crate) struct SendMessageResp {
    pub(crate) key: Option<MessageKey>,
    pub(crate) id: Option<String>,
}

#[derive(Deserialize, Debug)]
pub(crate) struct DownloadMediaResp {
    pub(crate) base64: String,
    pub(crate) mimetype: Option<String>,
}

#[derive(Deserialize, Debug)]
pub(crate) struct AvatarResp {
    #[serde(rename = "profilePictureUrl")]
    pub(crate) profile_picture_url: Option<String>,
    pub(crate) url: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_ok_or_api_success() {
        let resp = reqwest::Response::from(
            http::Response::builder()
                .status(200)
                .body("sucesso")
                .unwrap(),
        );
        let res = EvolutionProvider::ok_or_api(resp).await;
        assert!(res.is_ok());
    }

    #[tokio::test]
    async fn test_ok_or_api_error_truncation() {
        let long_body = "a".repeat(300);
        let resp = reqwest::Response::from(
            http::Response::builder()
                .status(400)
                .body(long_body)
                .unwrap(),
        );
        let res = EvolutionProvider::ok_or_api(resp).await;
        assert!(res.is_err());
        if let Err(infrastructure_messaging::MessagingProviderError::ProviderApi { status, body }) =
            res
        {
            assert_eq!(status, 400);
            assert_eq!(body.len(), 200);
            assert_eq!(body, "a".repeat(200));
        } else {
            panic!("Esperava ProviderApi erro");
        }
    }
}
