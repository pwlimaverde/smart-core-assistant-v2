use infrastructure_redis::connection::criar_conexao_com_url;
use redis::aio::ConnectionManager;

/// Carrega de forma resiliente as variáveis de ambiente a partir de arquivos `.env` locais
/// ou nas pastas superiores (mesmo padrão da crate `infrastructure_postgres`).
pub fn carregar_env_teste() {
    // Garante que o túnel SSH para o Docker da Hostinger esteja ativo antes de
    // qualquer conexão. Idempotente e barato quando o túnel já está de pé.
    test_support::ensure_tunnel();

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
    com_db_logico(&base, 15)
}

/// Reescreve (ou acrescenta) o índice de banco lógico da `REDIS_URL` para `db`.
/// Robusto tanto para URLs sem índice (`redis://host:6379`) quanto com índice
/// (`redis://host:6379/0`, formato canônico do `.env.example`): sem isto, o append
/// ingênuo de `/15` produziria `.../0/15` e o redis recusaria com "Invalid database number".
/// A autoridade vai até a primeira `/` após `://`; a senha em URL é percent-encoded,
/// então nunca conterá uma `/` literal que confunda a separação.
fn com_db_logico(base: &str, db: u8) -> String {
    let (esquema, resto) = base.split_once("://").unwrap_or(("redis", base));
    let autoridade = resto.split('/').next().unwrap_or(resto);
    format!("{esquema}://{autoridade}/{db}")
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
