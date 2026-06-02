use infrastructure_redis::connection::criar_conexao_com_url;
use redis::aio::ConnectionManager;

/// Carrega de forma resiliente as variáveis de ambiente a partir de arquivos `.env` locais
/// ou nas pastas superiores (mesmo padrão da crate `infrastructure_postgres`).
pub fn carregar_env_teste() {
    let caminhos = [
        ".env",
        "../.env",
        "../../.env",
        "../../../.env",
        "crates/infrastructure_redis/.env",
    ];
    for caminho in caminhos {
        if let Ok(conteudo) = std::fs::read_to_string(caminho) {
            for linha in conteudo.lines() {
                let linha = linha.trim();
                if linha.is_empty() || linha.starts_with('#') {
                    continue;
                }
                if let Some((chave, valor)) = linha.split_once('=') {
                    let chave = chave.trim();
                    let valor = valor.trim().trim_matches('"').trim_matches('\'');
                    if std::env::var(chave).is_err() {
                        std::env::set_var(chave, valor);
                    }
                }
            }
            break;
        }
    }
}

/// URL do Redis para testes: usa o banco lógico dedicado `15` para não colidir com dados reais.
pub fn url_redis_teste() -> String {
    carregar_env_teste();
    let base = std::env::var("REDIS_URL").expect("REDIS_URL não configurada para testes");
    format!("{}/15", base.trim_end_matches('/'))
}

/// Conexão de teste com o banco lógico limpo (`FLUSHDB`). Como `RUST_TEST_THREADS=1`, os
/// testes rodam sequencialmente e podem compartilhar o DB de teste com segurança.
pub async fn conexao_limpa() -> ConnectionManager {
    let mut con = criar_conexao_com_url(&url_redis_teste())
        .await
        .expect("falha ao conectar no Redis de teste (verifique REDIS_URL e o túnel/compose)");
    let _: () = redis::cmd("FLUSHDB")
        .query_async(&mut con)
        .await
        .expect("falha ao limpar o DB lógico de teste");
    con
}
