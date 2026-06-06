use infrastructure_postgres::{
    tenants::tenants::{PostgresTenantRepository, TenantRepository},
    AuditLogEntry,
};
use observability::AuditLogger;
use sqlx::PgPool;
use std::time::Duration;
use uuid::Uuid;

/// Carrega de forma resiliente as variáveis de ambiente a partir de arquivos .env locais ou na raiz do projeto.
fn carregar_env_teste() {
    // Garante que o túnel SSH para o Docker da Hostinger esteja ativo antes de
    // qualquer conexão. Idempotente e barato quando o túnel já está de pé.
    test_support::ensure_tunnel();

    let caminhos = vec![
        ".env",
        "../.env",
        "../../.env",
        "crates/infrastructure_postgres/.env",
        "../infrastructure_postgres/.env",
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

    // Configura chave AES-256 padrão para testes caso não exista
    if std::env::var("ENCRYPTION_KEY").is_err() {
        std::env::set_var(
            "ENCRYPTION_KEY",
            "MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE=",
        );
    }
}

#[tokio::test]
async fn test_audit_logger_async_fire_and_forget() {
    // 1. Arrange: Carrega variáveis de ambiente e configura os pools necessários.
    carregar_env_teste();

    let admin_url = std::env::var("DATABASE_ADMIN_URL")
        .expect("DATABASE_ADMIN_URL não configurada para testes do AuditLogger");
    let admin_pool = PgPool::connect(&admin_url)
        .await
        .expect("Falha ao conectar admin pool");

    // Inicializa banco de dados (roda as migrations se necessário)
    infrastructure_postgres::inicializar_banco_dados(&admin_pool)
        .await
        .expect("Falha ao inicializar o banco de dados/migrations");

    // Garante que o usuário administrativo de ID 1 existe (necessário para FK de user_id)
    sqlx::query(
        "INSERT INTO auth_user (id, username, email, is_active, is_staff, is_superuser)
         VALUES (1, 'obs_test_admin', 'obs_test@test.com', true, false, false)
         ON CONFLICT (id) DO NOTHING",
    )
    .execute(&admin_pool)
    .await
    .expect("Falha ao semear usuário de testes");

    // Cria o pool com a role de runtime sujeita ao RLS
    let tenant_pool = infrastructure_postgres::criar_pool(2)
        .await
        .expect("Falha ao criar tenant pool");

    // Cria o AuditLogger de testes
    let logger = AuditLogger::new(
        tenant_pool,
        admin_pool.clone(),
        "test-observability-service",
    );

    // Cria um tenant temporário para associar ao log do inquilino
    let tenant_repo = PostgresTenantRepository;
    let slug = format!("obs-tenant-{}", Uuid::new_v4());
    let mut tx = admin_pool
        .begin()
        .await
        .expect("Falha ao iniciar transação admin");
    let tenant = tenant_repo
        .criar(
            &mut tx,
            "Tenant Observabilidade Teste",
            &slug,
            Some(1),
            None,
            None,
        )
        .await
        .expect("Falha ao criar tenant de testes");
    tx.commit()
        .await
        .expect("Falha ao comitar tenant de testes");

    let context = serde_json::json!({"action": "integration_test", "meta": {"ok": true}});
    let trace_id = format!("trace-{}", Uuid::new_v4());
    let unique_global_event = format!("TEST_GLOBAL_{}", Uuid::new_v4());

    // 2. Act: Dispara os logs assíncronos (fire-and-forget, usam tokio::spawn internamente).
    logger.info(
        tenant.id,
        "TEST_TENANT_EVENT",
        "Mensagem de teste assíncrono de tenant",
        context.clone(),
        Some(1),
        Some("127.0.0.1".to_string()),
        Some(trace_id.clone()),
    );

    logger.info_global(
        &unique_global_event,
        "Mensagem de teste assíncrono global",
        context.clone(),
        None,
        None,
        None,
    );

    // 3 + 4. Assert: as inserções são fire-and-forget (tokio::spawn). Contra o banco remoto
    // (via túnel SSH) a latência pode exceder qualquer sleep fixo, então aguardamos a row
    // aparecer com polling e timeout (~5s) em vez de assumir um tempo fixo. Consulta via
    // pool administrativo (bypass RLS).
    let mut tenant_logs = Vec::new();
    for _ in 0..50 {
        tenant_logs = sqlx::query_as::<_, AuditLogEntry>(
            "SELECT * FROM audit_log WHERE tenant_id = $1 AND event = 'TEST_TENANT_EVENT'",
        )
        .bind(tenant.id)
        .fetch_all(&admin_pool)
        .await
        .expect("Falha ao consultar logs do tenant");
        if tenant_logs.len() == 1 {
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }

    assert_eq!(
        tenant_logs.len(),
        1,
        "Deveria ter persistido exatamente 1 log para o tenant"
    );
    assert_eq!(tenant_logs[0].tenant_id, Some(tenant.id));
    assert_eq!(tenant_logs[0].level, "INFO");
    assert_eq!(tenant_logs[0].service, "test-observability-service");
    assert_eq!(tenant_logs[0].trace_id.as_ref(), Some(&trace_id));
    assert_eq!(
        tenant_logs[0].message,
        "Mensagem de teste assíncrono de tenant"
    );
    assert_eq!(tenant_logs[0].context, context);

    // Verifica o log de auditoria Global (mesmo polling tolerante a latência).
    let mut global_logs = Vec::new();
    for _ in 0..50 {
        global_logs = sqlx::query_as::<_, AuditLogEntry>(
            "SELECT * FROM audit_log WHERE tenant_id IS NULL AND event = $1",
        )
        .bind(&unique_global_event)
        .fetch_all(&admin_pool)
        .await
        .expect("Falha ao consultar logs globais");
        if global_logs.len() == 1 {
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }

    assert_eq!(
        global_logs.len(),
        1,
        "Deveria ter persistido exatamente 1 log global"
    );
    assert_eq!(global_logs[0].tenant_id, None);
    assert_eq!(global_logs[0].level, "INFO");
    assert_eq!(global_logs[0].service, "test-observability-service");
    assert_eq!(
        global_logs[0].message,
        "Mensagem de teste assíncrono global"
    );
    assert_eq!(global_logs[0].context, context);

    // 5. Teardown: Limpeza manual dos registros para não poluir o banco de dados.
    // O log do tenant será removido automaticamente pelo ON DELETE CASCADE quando deletarmos o tenant.
    sqlx::query("DELETE FROM tenants_tenant WHERE id = $1")
        .bind(tenant.id)
        .execute(&admin_pool)
        .await
        .expect("Falha ao limpar tenant temporário");

    // O log global precisa ser apagado explicitamente pelo seu evento único.
    sqlx::query("DELETE FROM audit_log WHERE event = $1")
        .bind(&unique_global_event)
        .execute(&admin_pool)
        .await
        .expect("Falha ao limpar log global temporário");
}
