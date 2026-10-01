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

/// Teto de tempo de uma chamada ao Evolution, do envio à resposta completa.
///
/// `reqwest::Client::new()` NÃO tem timeout: uma Evolution que aceita a conexão e
/// nunca responde (processo travado, container em swap, instância do WhatsApp
/// pendurada) deixaria a chamada esperando para sempre. O chamador é o
/// `data_whatsapp`, cujo handler RPC ficaria preso junto — o `worker` do outro lado
/// desiste em 5s e reenvia, mas a task travada aqui nunca é liberada, e elas se
/// acumulam a cada tentativa.
///
/// 60s é generoso de propósito: a chamada mais pesada é `download_media`, que
/// devolve o arquivo inteiro em base64 (o limite de mídia é 20 MB).
const TIMEOUT_REQUISICAO_SEGUNDOS: u64 = 60;

/// Teto só para o aperto de mão da conexão. Curto porque "não consigo abrir a
/// conexão" é diagnóstico imediato — não vale ocupar o teto da requisição inteira.
const TIMEOUT_CONEXAO_SEGUNDOS: u64 = 5;

fn segundos_do_ambiente(chave: &str, padrao: u64) -> u64 {
    std::env::var(chave)
        .ok()
        .and_then(|v| v.parse().ok())
        .filter(|v| *v > 0)
        .unwrap_or(padrao)
}

impl EvolutionProvider {
    pub fn new(base_url: impl Into<String>, global_api_key: SecretString) -> Self {
        let timeout = std::time::Duration::from_secs(segundos_do_ambiente(
            "SMARTCORE_EVOLUTION_HTTP_TIMEOUT_SECS",
            TIMEOUT_REQUISICAO_SEGUNDOS,
        ));
        let connect_timeout = std::time::Duration::from_secs(segundos_do_ambiente(
            "SMARTCORE_EVOLUTION_CONNECT_TIMEOUT_SECS",
            TIMEOUT_CONEXAO_SEGUNDOS,
        ));
        // `build()` só falha por configuração de TLS/resolver do sistema. Cair para o
        // cliente default (sem timeout) é pior que ideal, mas melhor que derrubar o
        // serviço no boot por causa disso — e o WARN denuncia a situação.
        let http = reqwest::Client::builder()
            .timeout(timeout)
            .connect_timeout(connect_timeout)
            .build()
            .unwrap_or_else(|e| {
                tracing::warn!(
                    erro = %e,
                    "falha ao construir cliente HTTP com timeout; usando o default SEM timeout"
                );
                reqwest::Client::new()
            });
        Self {
            http,
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

    /// Lê o corpo como JSON e **desembrulha o envelope do provedor**.
    ///
    /// A `evolution-go` responde `{"data": <conteúdo>, "message": "success"}` em
    /// todas as rotas; a Evolution API v2 (Node) devolve o conteúdo na raiz.
    /// Aceitar as duas formas custa uma indireção e evita o modo de falha que
    /// derrubou o onboarding: a instância era criada no provedor, a resposta não
    /// casava com a struct esperada, e o cliente recebia "erro inesperado" com
    /// uma instância órfã do outro lado.
    pub(crate) async fn json_do_provedor(
        resp: reqwest::Response,
    ) -> Result<serde_json::Value, MessagingProviderError> {
        let bruto: serde_json::Value = resp
            .json()
            .await
            .map_err(|e| MessagingProviderError::Deserialization(e.to_string()))?;
        Ok(desembrulhar(bruto))
    }

    /// O id de um envio que o provedor já aceitou (2xx). Nunca falha: corpo
    /// ilegível ou sem id viram id vazio, com aviso no log — a mensagem saiu,
    /// e tratar isso como erro provocaria o reenvio.
    pub(crate) async fn id_do_envio(resp: reqwest::Response) -> String {
        match Self::json_do_provedor(resp).await {
            Ok(v) => id_da_mensagem_enviada(&v).unwrap_or_else(|| {
                tracing::warn!("envio aceito pelo provedor sem o id da mensagem");
                String::new()
            }),
            Err(e) => {
                tracing::warn!(erro = %e, "envio aceito pelo provedor com resposta ilegível");
                String::new()
            }
        }
    }
}

/// Tira o conteúdo de dentro de `{"data": ...}` quando o envelope está presente.
///
/// Só desembrulha se `data` for objeto ou array: uma rota que devolva um campo
/// `data` escalar na raiz (string, número) é conteúdo, não envelope.
pub(crate) fn desembrulhar(v: serde_json::Value) -> serde_json::Value {
    match v.get("data") {
        Some(d) if d.is_object() || d.is_array() => d.clone(),
        _ => v,
    }
}

/// O id da mensagem que o provedor acabou de enviar, já sem o envelope.
///
/// A evolution-go devolve `{"data": {"Info": {"ID": "…"}, "Message": …}}`
/// (o `MessageInfo` do whatsmeow, sem tags json). A Evolution v2 devolvia
/// `{"key": {"id": "…"}}` ou o `id` na raiz — continuam aceitos.
pub(crate) fn id_da_mensagem_enviada(v: &serde_json::Value) -> Option<String> {
    let texto = |x: Option<&serde_json::Value>| {
        x.and_then(|x| x.as_str())
            .filter(|s| !s.is_empty())
            .map(str::to_string)
    };
    let info = v.get("Info").or_else(|| v.get("info"));
    texto(info.and_then(|i| i.get("ID").or_else(|| i.get("id"))))
        .or_else(|| texto(v.get("key").and_then(|k| k.get("id"))))
        .or_else(|| texto(v.get("id")))
        .or_else(|| texto(v.get("messageId")))
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
