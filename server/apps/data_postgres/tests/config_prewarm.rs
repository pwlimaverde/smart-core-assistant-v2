//! Teste de INTEGRAÇÃO do pre-warm de config (`config_publisher`).
//!
//! Existe por causa de um bug que não dava erro: listar todos os tenants é uma
//! consulta **cross-tenant**, e `tenants_tenant` tem RLS com `FORCE`. No pool de
//! runtime (`NOBYPASSRLS`, sem `app.current_tenant`), a política fail-closed
//! devolve ZERO linhas — sem erro, sem log. O pre-warm reportava "0 tenants
//! publicados" e parecia estar funcionando; em produção a config nunca chegaria
//! ao `ia_engine` até alguém salvar algo no painel.
//!
//! Por ser integração, vive em `tests/` e roda apenas na suíte completa.

use sqlx::PgPool;
use uuid::Uuid;

/// Carrega `server/.env` (idempotente) e garante o túnel SSH ativo.
fn carregar_env_teste() {
    test_support::ensure_tunnel();
    let caminhos = [".env", "../.env", "../../.env"];
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
}

/// Cria um tenant ativo e devolve `(admin_pool, runtime_pool, tenant_id)`.
async fn setup() -> (PgPool, PgPool, Uuid) {
    carregar_env_teste();
    let admin_url = std::env::var("DATABASE_ADMIN_URL").expect("DATABASE_ADMIN_URL ausente");
    let runtime_url = std::env::var("DATABASE_URL").expect("DATABASE_URL ausente");

    let admin_pool = PgPool::connect(&admin_url).await.expect("conectar admin");
    let runtime_pool = PgPool::connect(&runtime_url)
        .await
        .expect("conectar runtime");

    infrastructure_postgres::inicializar_banco_dados(&admin_pool)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO auth_user (id, username, email, password_hash, is_superuser, is_staff) \
         VALUES (1, 'ci_seed_admin', 'ci-seed@local', '', TRUE, TRUE) \
         ON CONFLICT (id) DO NOTHING",
    )
    .execute(&admin_pool)
    .await
    .expect("semear auth_user");

    let tenant_id = Uuid::new_v4();
    let sufixo = &tenant_id.to_string()[..8];
    sqlx::query(
        "INSERT INTO tenants_tenant (id, name, slug, api_key, owner_id, active) \
         VALUES ($1, $2, $3, $4, 1, TRUE)",
    )
    .bind(tenant_id)
    .bind(format!("Tenant prewarm {sufixo}"))
    .bind(format!("prewarm-{sufixo}"))
    .bind(format!("key-prewarm-{sufixo}"))
    .execute(&admin_pool)
    .await
    .expect("criar tenant de teste");

    (admin_pool, runtime_pool, tenant_id)
}

async fn limpar(admin_pool: &PgPool, tenant_id: Uuid) {
    let _ = sqlx::query("DELETE FROM tenants_tenant WHERE id = $1")
        .bind(tenant_id)
        .execute(admin_pool)
        .await;
}

/// O pool de runtime NÃO enxerga a lista de tenants — e é justamente por não
/// dar erro que o bug passou despercebido.
#[tokio::test]
async fn runtime_pool_nao_lista_tenants_por_causa_do_rls() {
    let (admin_pool, runtime_pool, tenant_id) = setup().await;

    let via_admin: Vec<Uuid> =
        sqlx::query_scalar("SELECT id FROM tenants_tenant WHERE active = TRUE")
            .fetch_all(&admin_pool)
            .await
            .expect("consulta via admin");

    let via_runtime: Vec<Uuid> =
        sqlx::query_scalar("SELECT id FROM tenants_tenant WHERE active = TRUE")
            .fetch_all(&runtime_pool)
            .await
            .expect("consulta via runtime não deve ERRAR — ela devolve vazio");

    limpar(&admin_pool, tenant_id).await;

    assert!(
        via_admin.contains(&tenant_id),
        "o admin_pool (BYPASSRLS) precisa enxergar o tenant recém-criado"
    );
    assert!(
        !via_runtime.contains(&tenant_id),
        "o pool de runtime NÃO deveria enxergar tenants sem app.current_tenant; \
         se este assert falhar, o RLS de tenants_tenant afrouxou"
    );
}

/// Com o `admin_pool`, o pre-warm encontra o tenant e publica a config.
#[tokio::test]
async fn prewarm_publica_config_do_tenant_ativo() {
    let (admin_pool, _runtime_pool, tenant_id) = setup().await;

    let redis_url = std::env::var("REDIS_URL").expect("REDIS_URL ausente");
    let cliente = infrastructure_redis::criar_cliente(&redis_url).expect("cliente redis");
    let conn = redis::aio::ConnectionManager::new(cliente)
        .await
        .expect("ConnectionManager");

    let cipher = std::sync::Arc::new(
        infrastructure_postgres::crypto::CipherManager::new_from_env().unwrap(),
    );
    let cache = infrastructure_postgres::TenantConfigCache::new(admin_pool.clone(), cipher);

    let publicados =
        data_postgres::config_publisher::prewarm_configs(Some(&admin_pool), &cache, &conn)
            .await
            .expect("prewarm não deve falhar");

    // A chave precisa existir no Redis, no formato que o ia_engine lê.
    let chave = infrastructure_redis::chave_config_tenant(tenant_id);
    let bruto: Option<String> = redis::AsyncCommands::get(&mut conn.clone(), &chave)
        .await
        .expect("GET da config");

    let _: Result<(), redis::RedisError> =
        redis::AsyncCommands::del(&mut conn.clone(), &chave).await;
    limpar(&admin_pool, tenant_id).await;

    assert!(
        publicados >= 1,
        "esperado ao menos o tenant de teste publicado"
    );
    let json = bruto.expect("config do tenant precisa estar no Redis após o pre-warm");
    let valor: serde_json::Value = serde_json::from_str(&json).expect("config precisa ser JSON");
    assert_eq!(
        valor.get("tenant_id").and_then(|v| v.as_str()),
        Some(tenant_id.to_string().as_str())
    );
    // Campos que o ia_engine consome — se algum sumir do DTO, o Python quebra
    // só em runtime, na desserialização.
    for campo in [
        "persona_bot",
        "bot_agent_name",
        "msg_transferencia",
        "llm_class",
        "model",
        "openai_api_key",
        "prompts",
    ] {
        assert!(
            valor.get(campo).is_some(),
            "campo `{campo}` ausente no DTO publicado"
        );
    }
}

/// Sem `admin_pool` o pre-warm avisa e devolve 0, em vez de fingir sucesso.
#[tokio::test]
async fn prewarm_sem_admin_pool_nao_finge_sucesso() {
    carregar_env_teste();
    let redis_url = std::env::var("REDIS_URL").expect("REDIS_URL ausente");
    let cliente = infrastructure_redis::criar_cliente(&redis_url).expect("cliente redis");
    let conn = redis::aio::ConnectionManager::new(cliente)
        .await
        .expect("ConnectionManager");

    let admin_url = std::env::var("DATABASE_ADMIN_URL").expect("DATABASE_ADMIN_URL ausente");
    let pool = PgPool::connect(&admin_url).await.expect("conectar");
    let cipher = std::sync::Arc::new(
        infrastructure_postgres::crypto::CipherManager::new_from_env().unwrap(),
    );
    let cache = infrastructure_postgres::TenantConfigCache::new(pool, cipher);

    let publicados = data_postgres::config_publisher::prewarm_configs(None, &cache, &conn)
        .await
        .expect("sem admin_pool não é erro fatal, só não publica");

    assert_eq!(publicados, 0);
}
