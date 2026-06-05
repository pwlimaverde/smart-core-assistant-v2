use infrastructure_postgres::{
    connection::{criar_pool, inicializar_banco_dados},
    security::RequestContext,
    tenants::tenants::{PostgresTenantRepository, Tenant, TenantRepository},
};
use sqlx::postgres::PgPoolOptions;
use sqlx::{PgPool, Postgres, Transaction};
use uuid::Uuid;

/// Cria um pool conectado ao `DATABASE_ADMIN_URL` (role com BYPASSRLS).
/// Necessário para os 3 lookups pré-auth que operam sem contexto de tenant.
pub async fn obter_admin_pool_teste() -> PgPool {
    carregar_env_teste();
    let url = std::env::var("DATABASE_ADMIN_URL")
        .expect("DATABASE_ADMIN_URL não configurada para testes de admin");
    PgPoolOptions::new()
        .max_connections(2)
        .connect(&url)
        .await
        .expect("Falha ao conectar com DATABASE_ADMIN_URL")
}

/// Carrega de forma resiliente as variáveis de ambiente a partir de arquivos .env locais ou na raiz.
pub fn carregar_env_teste() {
    // Garante que o túnel SSH para o Docker da Hostinger esteja ativo antes de
    // qualquer conexão. Idempotente e barato quando o túnel já está de pé.
    test_support::ensure_tunnel();

    let caminhos = vec![
        ".env",
        "../.env",
        "../../.env",
        "crates/infrastructure_postgres/.env",
    ];
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

    // Fallback: chave AES-256 de testes (base64 de "01234567890123456789012345678901")
    if std::env::var("ENCRYPTION_KEY").is_err() {
        std::env::set_var(
            "ENCRYPTION_KEY",
            "MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE=",
        );
    }
}

/// Cria o pool de conexões de teste e garante que as migrations estão aplicadas.
/// Também garante que auth_user.id=1 existe para satisfazer FKs de owner_id.
pub async fn obter_pool_teste() -> PgPool {
    carregar_env_teste();

    // As migrations e o seed de auth_user exigem DDL/privilégios que a role de runtime
    // (app_runtime, NOBYPASSRLS) não possui. Por isso preparamos o schema com a role
    // administrativa (DATABASE_ADMIN_URL); os testes em si conectam com a role restrita
    // (DATABASE_URL) para que o RLS seja efetivamente aplicado e o isolamento validado.
    if let Ok(admin_url) = std::env::var("DATABASE_ADMIN_URL") {
        let admin_pool = PgPoolOptions::new()
            .max_connections(1)
            .connect(&admin_url)
            .await
            .expect("Falha ao conectar com DATABASE_ADMIN_URL");

        inicializar_banco_dados(&admin_pool)
            .await
            .expect("Falha ao rodar migrations de teste (DATABASE_ADMIN_URL).");

        // Garante que auth_user com id=1 existe (referenciado como owner_id nos testes)
        sqlx::query(
            "INSERT INTO auth_user (id, username, email, is_active, is_staff, is_superuser)
             VALUES (1, 'test_admin', 'test@test.com', true, false, false)
             ON CONFLICT (id) DO NOTHING",
        )
        .execute(&admin_pool)
        .await
        .expect("Falha ao garantir auth_user de teste");

        // INSERT com id explícito não avança a sequência; sincroniza para evitar
        // colisão de PK quando os testes criarem novos usuários via SERIAL.
        sqlx::query(
            "SELECT setval('auth_user_id_seq', \
             COALESCE((SELECT MAX(id) FROM auth_user), 1))",
        )
        .execute(&admin_pool)
        .await
        .expect("Falha ao sincronizar auth_user_id_seq");

        admin_pool.close().await;
    }

    // Pool dos testes: role de runtime (app_runtime) — sujeita ao RLS.
    criar_pool(5)
        .await
        .expect("Falha ao criar pool de teste. Verifique DATABASE_URL e o túnel SSH.")
}

/// Cria um RequestContext padrão de testes com escopo tenant:admin.
pub fn criar_contexto_teste(tenant_id: Uuid) -> RequestContext {
    RequestContext {
        tenant_id,
        user_id: 1,
        user_scopes: vec![
            "tenant:admin".into(),
            "atendimentos:read".into(),
            "atendimentos:write".into(),
            "treinamento:read".into(),
            "treinamento:write".into(),
            "integracoes:read".into(),
            "integracoes:write".into(),
        ],
        flow_permissions: vec![1, 2, 3],
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

/// Cria um tenant de teste dentro de uma transação.
/// Configura automaticamente o RLS (app.current_tenant) para o novo tenant.
pub async fn criar_tenant_para_teste(tx: &mut Transaction<'_, Postgres>, nome: &str) -> Tenant {
    let tenant_repo = PostgresTenantRepository;
    let slug = format!("tenant-{}", Uuid::new_v4());
    tenant_repo
        .criar(tx, nome, &slug, Some(1), None, None)
        .await
        .expect("Falha ao criar tenant de teste")
}
