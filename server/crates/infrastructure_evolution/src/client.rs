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

#[derive(Deserialize)]
pub(crate) struct CreateInstanceResp {
    pub(crate) instance: CreateInstanceInner,
    pub(crate) hash: Option<String>,
}

#[derive(Deserialize)]
pub(crate) struct CreateInstanceInner {
    #[serde(rename = "instanceName")]
    pub(crate) instance_name: String,
    pub(crate) hash: Option<String>,
}

#[derive(Deserialize)]
pub(crate) struct ConnStateResp {
    pub(crate) instance: ConnStateInner,
}

#[derive(Deserialize)]
pub(crate) struct ConnStateInner {
    pub(crate) state: String,
}
