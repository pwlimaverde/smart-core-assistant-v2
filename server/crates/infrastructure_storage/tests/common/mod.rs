//! Apoio aos testes de integração de storage contra o Cloudflare R2.
//!
//! O R2 é acessado diretamente via HTTPS (não há túnel SSH). As variáveis `S3_*`
//! são lidas de um `.env` local. Os testes são **opt-in**: se `S3_ENDPOINT` não
//! estiver configurado, são pulados — evita escrever no bucket real em execuções
//! rotineiras de `cargo test`. Para rodá-los, preencha as `S3_*` (R2) no `.env`.

use infrastructure_storage::StorageClient;

/// Carrega as variáveis `S3_*` de um `.env` local (e pastas superiores) para o
/// ambiente do processo de teste.
fn carregar_env_teste() {
    let caminhos = [
        ".env",
        "../.env",
        "../../.env",
        "../../../.env",
        "crates/infrastructure_storage/.env",
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

/// Cria um `StorageClient` de teste apontando para o R2 e confirma o acesso ao bucket.
///
/// Retorna `None` (teste pulado) quando `S3_ENDPOINT` não está configurado — assim
/// `cargo test` não toca o bucket real sem configuração explícita.
pub async fn cliente_teste() -> Option<StorageClient> {
    carregar_env_teste();
    if std::env::var("S3_ENDPOINT").is_err() {
        eprintln!(
            "[storage IT] pulado: configure as variáveis S3_* (R2) em um .env para rodar os testes"
        );
        return None;
    }
    let client = StorageClient::from_env()
        .expect("falha ao criar StorageClient (verifique as variáveis S3_* do R2)");
    client
        .garantir_bucket()
        .await
        .expect("bucket do R2 inacessível (verifique credenciais e S3_BUCKET)");
    Some(client)
}
