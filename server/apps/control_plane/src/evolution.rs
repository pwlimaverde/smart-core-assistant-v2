use secrecy::{ExposeSecret, SecretString};
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct ConnectionStateResponse {
    instance: InstanceInfo,
}

#[derive(Debug, Deserialize)]
struct InstanceInfo {
    state: String, // "open", "connecting", "close"
}

/// Testa a conexão de uma instância na Evolution API.
///
/// Faz uma chamada `GET /instance/connectionState/{instance_name}`
/// e retorna o estado ("open", "connecting", "close", "error").
pub async fn test_evolution_connection(
    api_url: &str,
    global_token: Option<&SecretString>,
    instance_name: &str,
    instance_key: Option<&SecretString>,
) -> anyhow::Result<String> {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(5))
        .build()?;

    // O token global da Evolution tem prioridade para a chamada administrativa
    let api_key = match global_token {
        Some(token) if !token.expose_secret().is_empty() => token.expose_secret(),
        _ => match instance_key {
            Some(key) if !key.expose_secret().is_empty() => key.expose_secret(),
            _ => {
                return Err(anyhow::anyhow!(
                    "Nenhuma chave de API configurada para a Evolution API."
                ))
            }
        },
    };

    let url = format!(
        "{}/instance/connectionState/{}",
        api_url.trim_end_matches('/'),
        instance_name
    );

    let resp = client.get(&url).header("apikey", api_key).send().await?;

    if !resp.status().is_success() {
        let status = resp.status();
        let body = resp.text().await.unwrap_or_default();
        return Err(anyhow::anyhow!(
            "Erro da API Evolution (Status: {}): {}",
            status,
            body
        ));
    }

    let parsed: ConnectionStateResponse = resp.json().await?;
    Ok(parsed.instance.state)
}
