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
async fn test_audit_logger_tenant_warn_and_error_levels() {
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
         VALUES (1, 'levels_test_admin', 'levels_test@test.com', true, false, false)
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
    let logger = AuditLogger::new(tenant_pool, admin_pool.clone(), "test-levels-service");

    // Cria um tenant temporário para associar aos logs do inquilino
    let tenant_repo = PostgresTenantRepository;
    let slug = format!("levels-tenant-{}", Uuid::new_v4());
    let mut tx = admin_pool.begin().await.expect("Falha ao iniciar transação admin");
    let tenant = tenant_repo
        .criar(&mut tx, "Tenant Níveis Teste", &slug, Some(1), None, None)
        .await
        .expect("Falha ao criar tenant de testes");
    tx.commit().await.expect("Falha ao comitar tenant de testes");

    let context = serde_json::json!({"action": "warn_error_tests", "meta": {"test": true}});
    let trace_id_warn = format!("trace-warn-{}", Uuid::new_v4());
    let trace_id_error = format!("trace-err-{}", Uuid::new_v4());

    // 2. Act: Dispara os logs assíncronos de WARN e ERROR para o inquilino.
    logger.warn(
        tenant.id,
        "TEST_TENANT_WARN",
        "Mensagem de warn de inquilino",
        context.clone(),
        Some(1),
        Some("127.0.0.1".to_string()),
        Some(trace_id_warn.clone()),
    );

    logger.error(
        tenant.id,
        "TEST_TENANT_ERROR",
        "Mensagem de erro de inquilino",
        context.clone(),
        Some(1),
        Some("127.0.0.1".to_string()),
        Some(trace_id_error.clone()),
    );

    // Aguarda um curto intervalo para que as tarefas em background completem a inserção.
    tokio::time::sleep(Duration::from_millis(200)).await;

    // 3. Assert: Busca e valida a inserção no banco de dados usando o pool administrativo (bypass RLS).
    // Verifica o log de WARN
    let warn_logs = sqlx::query_as::<_, AuditLogEntry>(
        "SELECT * FROM audit_log WHERE tenant_id = $1 AND event = 'TEST_TENANT_WARN'"
    )
    .bind(tenant.id)
    .fetch_all(&admin_pool)
    .await
    .expect("Falha ao consultar logs de warn");

    assert_eq!(warn_logs.len(), 1, "Deveria ter persistido exatamente 1 log de WARN");
    assert_eq!(warn_logs[0].tenant_id, Some(tenant.id));
    assert_eq!(warn_logs[0].level, "WARN");
    assert_eq!(warn_logs[0].trace_id.as_ref(), Some(&trace_id_warn));
    assert_eq!(warn_logs[0].message, "Mensagem de warn de inquilino");
    assert_eq!(warn_logs[0].context, context);

    // Verifica o log de ERROR
    let error_logs = sqlx::query_as::<_, AuditLogEntry>(
        "SELECT * FROM audit_log WHERE tenant_id = $1 AND event = 'TEST_TENANT_ERROR'"
    )
    .bind(tenant.id)
    .fetch_all(&admin_pool)
    .await
    .expect("Falha ao consultar logs de erro");

    assert_eq!(error_logs.len(), 1, "Deveria ter persistido exatamente 1 log de ERROR");
    assert_eq!(error_logs[0].tenant_id, Some(tenant.id));
    assert_eq!(error_logs[0].level, "ERROR");
    assert_eq!(error_logs[0].trace_id.as_ref(), Some(&trace_id_error));
    assert_eq!(error_logs[0].message, "Mensagem de erro de inquilino");
    assert_eq!(error_logs[0].context, context);

    // 4. Teardown: Limpeza automática pelo ON DELETE CASCADE ao deletar o tenant.
    sqlx::query("DELETE FROM tenants_tenant WHERE id = $1")
        .bind(tenant.id)
        .execute(&admin_pool)
        .await
        .expect("Falha ao limpar tenant temporário");
}

#[tokio::test]
async fn test_audit_logger_global_warn_and_error_levels() {
    // 1. Arrange: Carrega variáveis de ambiente e configura o pool de admin.
    carregar_env_teste();

    let admin_url = std::env::var("DATABASE_ADMIN_URL")
        .expect("DATABASE_ADMIN_URL não configurada para testes do AuditLogger");
    let admin_pool = PgPool::connect(&admin_url)
        .await
        .expect("Falha ao conectar admin pool");

    let tenant_pool = infrastructure_postgres::criar_pool(2)
        .await
        .expect("Falha ao criar tenant pool");

    let logger = AuditLogger::new(tenant_pool, admin_pool.clone(), "test-levels-service");

    let context = serde_json::json!({"action": "global_warn_error_tests", "meta": {"test": true}});
    let event_warn = format!("GLOBAL_WARN_{}", Uuid::new_v4());
    let event_error = format!("GLOBAL_ERROR_{}", Uuid::new_v4());

    // 2. Act: Dispara os logs assíncronos globais de WARN e ERROR.
    logger.warn_global(
        &event_warn,
        "Mensagem global de warn",
        context.clone(),
        None,
        None,
        None,
    );

    logger.error_global(
        &event_error,
        "Mensagem global de erro",
        context.clone(),
        None,
        None,
        None,
    );

    // Aguarda gravação
    tokio::time::sleep(Duration::from_millis(200)).await;

    // 3. Assert: Valida logs globais no banco de dados.
    // Valida WARN global
    let warn_logs = sqlx::query_as::<_, AuditLogEntry>(
        "SELECT * FROM audit_log WHERE tenant_id IS NULL AND event = $1"
    )
    .bind(&event_warn)
    .fetch_all(&admin_pool)
    .await
    .expect("Falha ao consultar logs de warn globais");

    assert_eq!(warn_logs.len(), 1, "Deveria ter persistido 1 log global de WARN");
    assert_eq!(warn_logs[0].tenant_id, None);
    assert_eq!(warn_logs[0].level, "WARN");
    assert_eq!(warn_logs[0].message, "Mensagem global de warn");
    assert_eq!(warn_logs[0].context, context);

    // Valida ERROR global
    let error_logs = sqlx::query_as::<_, AuditLogEntry>(
        "SELECT * FROM audit_log WHERE tenant_id IS NULL AND event = $1"
    )
    .bind(&event_error)
    .fetch_all(&admin_pool)
    .await
    .expect("Falha ao consultar logs de erro globais");

    assert_eq!(error_logs.len(), 1, "Deveria ter persistido 1 log global de ERROR");
    assert_eq!(error_logs[0].tenant_id, None);
    assert_eq!(error_logs[0].level, "ERROR");
    assert_eq!(error_logs[0].message, "Mensagem global de erro");
    assert_eq!(error_logs[0].context, context);

    // 4. Teardown: Limpeza manual dos registros globais para manter o banco limpo.
    sqlx::query("DELETE FROM audit_log WHERE event IN ($1, $2)")
        .bind(&event_warn)
        .bind(&event_error)
        .execute(&admin_pool)
        .await
        .expect("Falha ao limpar logs globais temporários");
}
