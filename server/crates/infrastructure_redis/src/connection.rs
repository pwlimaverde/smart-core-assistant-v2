use redis::aio::ConnectionManager;
use redis::Client;

use crate::errors::RedisError;

/// Cria um `ConnectionManager` (multiplexado, `Clone`, com reconexão automática) a partir
/// da `REDIS_URL` de ambiente. Use-o para comandos (publish, cache, tokens).
///
/// Para loops de consumo bloqueante (`XREADGROUP` com BLOCK) ou pub/sub, prefira uma
/// conexão dedicada criada a partir de [`criar_cliente`], pois comandos bloqueantes em
/// uma conexão multiplexada travam os demais usuários.
pub async fn criar_conexao_redis() -> Result<ConnectionManager, RedisError> {
    let url = std::env::var("REDIS_URL")
        .map_err(|_| RedisError::ConfigError("REDIS_URL não configurada".into()))?;
    criar_conexao_com_url(&url).await
}

/// Cria um `ConnectionManager` a partir de uma URL explícita (útil para testes que apontam
/// para um banco lógico dedicado).
pub async fn criar_conexao_com_url(url: &str) -> Result<ConnectionManager, RedisError> {
    let client = Client::open(url.to_string())?;
    let manager = ConnectionManager::new(client).await?;
    Ok(manager)
}

/// Cria um `Client` Redis a partir de uma URL. A partir dele obtêm-se conexões dedicadas
/// (`get_async_connection`/`get_async_pubsub`) para consumidores e assinantes.
pub fn criar_cliente(url: &str) -> Result<Client, RedisError> {
    Ok(Client::open(url.to_string())?)
}

/// Verifica a conectividade com o Redis (`PING`).
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
