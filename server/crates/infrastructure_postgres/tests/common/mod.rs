use std::sync::Arc;
use sqlx::{PgPool, Postgres, Transaction};
use uuid::Uuid;
use infrastructure_postgres::{
    connection::{criar_pool, inicializar_banco_dados},
    security::RequestContext,
    crypto::CipherManager,
};

/// Carrega de forma resiliente as variáveis de ambiente a partir de arquivos .env locais ou na raiz.
pub fn carregar_env_teste() {
    // Tenta carregar do diretório atual (crate) ou do pai (workspace)
    let caminhos = vec![".env", "../.env", "../../.env", "crates/infrastructure_postgres/.env"];
    for caminho in caminhos {
        if let Ok(conteudo) = std::fs::read_to_string(caminho) {
            for linha in conteudo.lines() {
                let linha_limpa = linha.trim();
                if linha_limpa.is_empty() || linha_limpa.starts_with('#') {
                    continue;
                }
                if let Some((chave, valor)) = linha_limpa.split_once('=') {
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
    
    // Fallback de chaves para evitar pânicos lógicos se não fornecidas
    if std::env::var("ENCRYPTION_KEY").is_err() {
        // Chave padrão base64 de 32 bytes: "A7f3J9xZ2kQ5wL8vN1yP4tM0rS3bG6dH" (32 caracteres -> convertidos para 32 bytes base64)
        // Vamos usar uma chave base64 válida de 32 bytes: "MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE=" (base64 de "01234567890123456789012345678901")
        std::env::set_var("ENCRYPTION_KEY", "MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE=");
    }
}

/// Cria o pool de conexões de teste e garante que as migrations estão aplicadas.
pub async fn obter_pool_teste() -> PgPool {
    carregar_env_teste();
    let pool = criar_pool(5)
        .await
        .expect("Falha ao criar pool de conexões de teste. Certifique-se de que o túnel do banco de dados está ativo e a DATABASE_URL está configurada.");
    
    inicializar_banco_dados(&pool)
        .await
        .expect("Falha ao rodar migrations de teste.");
        
    pool
}

/// Cria um RequestContext padrão de testes.
pub fn criar_contexto_teste(tenant_id: Uuid) -> RequestContext {
    RequestContext {
        tenant_id,
        user_id: 1, // ID padrão de teste para auth_user
        user_scopes: vec![
            "tenant:admin".into(),
            "atendimentos:read".into(),
            "atendimentos:write".into(),
            "treinamento:read".into(),
            "treinamento:write".into(),
            "integracoes:read".into(),
            "integracoes:write".into(),
        ],
        flow_permissions: vec![1, 2, 3], // IDs de fluxos autorizados para teste
    }
}

/// Configura a variável RLS para o tenant especificado dentro da transação atual.
pub async fn configurar_tenant_transacao(tx: &mut Transaction<'_, Postgres>, tenant_id: Uuid) {
    sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
        .bind(tenant_id.to_string())
        .execute(&mut **tx)
        .await
        .expect("Falha ao definir o tenant para isolamento RLS");
}
