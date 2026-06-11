use redis::aio::ConnectionManager;
use redis::Client;
use std::time::Duration;

use crate::errors::RedisError;

/// Cria um `ConnectionManager` (multiplexado, `Clone`, com reconexão automática) a partir
/// da `REDIS_URL` de ambiente. Use-o para comandos (publish, cache, tokens).
///
/// Para loops de consumo bloqueante (`XREADGROUP` com BLOCK) ou pub/sub, prefira uma
/// conexão dedicada criada a partir de [`criar_cliente`], pois comandos bloqueantes em
/// uma conexão multiplexada travam os demais usuários.
#[tracing::instrument(err)]
pub async fn criar_conexao_redis() -> Result<ConnectionManager, RedisError> {
    let url = std::env::var("REDIS_URL")
        .map_err(|_| RedisError::ConfigError("REDIS_URL não configurada".into()))?;
    criar_conexao_com_url(&url).await
}

/// Cria um `ConnectionManager` a partir de uma URL explícita (útil para testes que apontam
/// para um banco lógico dedicado).
// `url` é omitido do span: pode conter credenciais embutidas (`redis://user:pass@host`).
#[tracing::instrument(skip(url), err)]
pub async fn criar_conexao_com_url(url: &str) -> Result<ConnectionManager, RedisError> {
    let client = Client::open(url.to_string())?;
    let manager = ConnectionManager::new(client).await?;
    tracing::info!("conexão multiplexada com o Redis estabelecida");
    Ok(manager)
}

/// Cria um `Client` Redis a partir de uma URL. A partir dele obtêm-se conexões dedicadas
/// (`get_async_connection`/`get_async_pubsub`) para consumidores e assinantes.
#[tracing::instrument(skip(url), err)]
pub fn criar_cliente(url: &str) -> Result<Client, RedisError> {
    Ok(Client::open(url.to_string())?)
}

/// Verifica a conectividade com o Redis (`PING`).
#[tracing::instrument(level = "debug", skip(con), err)]
pub async fn ping(con: &mut ConnectionManager) -> Result<(), RedisError> {
    let resposta: String = redis::cmd("PING").query_async(con).await?;
    if resposta == "PONG" {
        Ok(())
    } else {
        Err(RedisError::ConfigError(format!(
            "resposta inesperada do PING: {resposta}"
        )))
    }
}

/// Cria um `ConnectionManager` com timeouts de resposta e conexão (P4).
/// Em redis 0.25.5 a configuração de timeout é feita por este construtor — NÃO existe
/// `ConnectionManagerConfig` (isso só aparece em redis ≥1.0, fora da versão fixada).
#[tracing::instrument(skip(url), err)]
pub async fn criar_conexao_com_timeouts(url: &str) -> Result<ConnectionManager, RedisError> {
    let response_ms = std::env::var("SMARTCORE_REDIS_RESPONSE_TIMEOUT_MS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(2000u64);
    let client = Client::open(url.to_string())?;
    let manager = ConnectionManager::new_with_backoff_and_timeouts(
        client,
        2,                                  // exponent_base (ms) — backoff exponencial
        100,                                // factor
        6,                                  // number_of_retries
        Duration::from_millis(response_ms), // response_timeout
        Duration::from_millis(response_ms), // connection_timeout
    )
    .await?;
    tracing::info!(response_ms, "ConnectionManager Redis criado com timeouts");
    Ok(manager)
}
