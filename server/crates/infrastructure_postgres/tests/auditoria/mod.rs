use crate::common::{
    configurar_tenant_transacao, criar_tenant_para_teste, obter_admin_pool_teste, obter_pool_teste,
};
use infrastructure_postgres::{
    buscar_audit_logs, buscar_audit_logs_admin, buscar_audit_logs_globais,
    buscar_audit_logs_por_evento, inserir_audit_log, inserir_audit_log_global, AuditLogEntry,
    NewAuditLogEntry,
};
use sqlx::Row;
use uuid::Uuid;

#[tokio::test]
async fn test_audit_log_tenant_insertion_and_retrieval_under_rls() {
    // 1. Arrange: Obtém pool restrito de teste e inicia transação.
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.expect("Falha ao iniciar transação");

    // Cria um inquilino temporário para o teste.
    let tenant = criar_tenant_para_teste(&mut tx, "Tenant Auditoria RLS").await;

    // Configura o tenant na transação atual do RLS.
    configurar_tenant_transacao(&mut tx, tenant.id).await;

    let trace_id = format!("trace-{}", Uuid::new_v4());
    let entry = NewAuditLogEntry {
        tenant_id: Some(tenant.id),
        level: "INFO".to_string(),
        service: "test-service-infra".to_string(),
        trace_id: Some(trace_id.clone()),
        event: "TEST_INSERT".to_string(),
        message: "Mensagem de teste de auditoria no RLS".to_string(),
        context: serde_json::json!({"test_key": "test_val"}),
        user_id: Some(1), // user_id = 1 é semeado por padrão no obter_pool_teste
        ip_address: Some("127.0.0.1".to_string()),
    };

    // 2. Act: Insere o registro de auditoria na transação do inquilino.
    let log_id = inserir_audit_log(&mut tx, &entry)
        .await
        .expect("Falha ao inserir log de auditoria");

    // 3. Assert: Busca os logs para o tenant especificado.
    let logs = buscar_audit_logs(&mut tx, tenant.id, 10, 0)
        .await
        .expect("Falha ao buscar logs de auditoria");

    assert_eq!(logs.len(), 1, "Deveria ter retornado exatamente 1 log");
    let log = &logs[0];
    assert_eq!(log.id, log_id);
    assert_eq!(log.tenant_id, Some(tenant.id));
    assert_eq!(log.level, "INFO");
    assert_eq!(log.service, "test-service-infra");
    assert_eq!(log.trace_id.as_ref(), Some(&trace_id));
    assert_eq!(log.event, "TEST_INSERT");
    assert_eq!(log.message, "Mensagem de teste de auditoria no RLS");
    assert_eq!(log.context, serde_json::json!({"test_key": "test_val"}));
    assert_eq!(log.user_id, Some(1));
    assert_eq!(log.ip_address.as_deref(), Some("127.0.0.1"));

    // Testa também a busca filtrada por evento.
    let logs_por_evento = buscar_audit_logs_por_evento(&mut tx, tenant.id, "TEST_INSERT", 10, 0)
        .await
        .expect("Falha ao buscar logs por evento");
    assert_eq!(logs_por_evento.len(), 1);
    assert_eq!(logs_por_evento[0].id, log_id);

    let logs_por_outro_evento =
        buscar_audit_logs_por_evento(&mut tx, tenant.id, "NON_EXISTENT", 10, 0)
            .await
            .expect("Falha ao buscar logs por evento inexistente");
    assert!(logs_por_outro_evento.is_empty());

    // 4. Teardown: Reverte a transação para não poluir o banco de dados.
    tx.rollback().await.expect("Falha ao reverter transação");
}

#[tokio::test]
async fn test_audit_log_rls_isolation_enforced() {
    // 1. Arrange: Obtém o pool de runtime e inicia transação.
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.expect("Falha ao iniciar transação");

    // Cria dois inquilinos distintos para validar o isolamento.
    let tenant_a = criar_tenant_para_teste(&mut tx, "Tenant Auditoria A").await;
    let tenant_b = criar_tenant_para_teste(&mut tx, "Tenant Auditoria B").await;

    // Configura o RLS para o Tenant A.
    configurar_tenant_transacao(&mut tx, tenant_a.id).await;

    let entry_a = NewAuditLogEntry {
        tenant_id: Some(tenant_a.id),
        level: "INFO".to_string(),
        service: "test-service-infra".to_string(),
        trace_id: Some("trace-a".to_string()),
        event: "EVENT_A".to_string(),
        message: "Log exclusivo do Tenant A".to_string(),
        context: serde_json::json!({}),
        user_id: Some(1),
        ip_address: None,
    };

    // Insere o log para o Tenant A.
    let log_a_id = inserir_audit_log(&mut tx, &entry_a)
        .await
        .expect("Falha ao inserir log do Tenant A");

    // Altera o contexto RLS para o Tenant B.
    configurar_tenant_transacao(&mut tx, tenant_b.id).await;

    let entry_b = NewAuditLogEntry {
        tenant_id: Some(tenant_b.id),
        level: "INFO".to_string(),
        service: "test-service-infra".to_string(),
        trace_id: Some("trace-b".to_string()),
        event: "EVENT_B".to_string(),
        message: "Log exclusivo do Tenant B".to_string(),
        context: serde_json::json!({}),
        user_id: Some(1),
        ip_address: None,
    };

    // Insere o log para o Tenant B.
    let log_b_id = inserir_audit_log(&mut tx, &entry_b)
        .await
        .expect("Falha ao inserir log do Tenant B");

    // 2. Act & Assert: Estando no contexto de Tenant B, o Tenant B não deve enxergar dados do Tenant A.
    let logs_b = buscar_audit_logs(&mut tx, tenant_b.id, 10, 0)
        .await
        .expect("Falha ao buscar logs do Tenant B");

    // Deve ver apenas o log do Tenant B.
    assert_eq!(logs_b.len(), 1);
    assert_eq!(logs_b[0].id, log_b_id);
    assert_ne!(logs_b[0].id, log_a_id);

    // Tenta explicitamente ler o log de A pela query direta na tabela usando o ID de A
    // (a policy do RLS deve impedir a leitura mesmo que tentemos burlar selecionando tenant_id de A).
    let logs_a_tentativa: Vec<AuditLogEntry> =
        sqlx::query_as::<_, AuditLogEntry>("SELECT * FROM audit_log WHERE tenant_id = $1")
            .bind(tenant_a.id)
            .fetch_all(&mut *tx)
            .await
            .expect("Falha ao tentar selecionar dados cruzados de tenant");

    assert!(
        logs_a_tentativa.is_empty(),
        "VULNERABILIDADE: Tenant B conseguiu ler logs de auditoria do Tenant A!"
    );

    // 3. Teardown
    tx.rollback().await.expect("Falha ao reverter transação");
}

#[tokio::test]
async fn test_audit_log_global_insertion_and_retrieval() {
    // 1. Arrange: Logs globais exigem o pool administrativo (DATABASE_ADMIN_URL),
    // pois a role padrão `app_runtime` não bypassa o RLS e impede leitura/escrita com tenant_id = NULL.
    let admin_pool = obter_admin_pool_teste().await;

    let unique_event = format!("GLOBAL_TEST_EVENT_{}", Uuid::new_v4());
    let entry = NewAuditLogEntry {
        tenant_id: None,
        level: "WARN".to_string(),
        service: "test-global-service".to_string(),
        trace_id: Some("global-trace-999".to_string()),
        event: unique_event.clone(),
        message: "Mensagem global de auditoria de sistema".to_string(),
        context: serde_json::json!({"admin_action": true}),
        user_id: None,
        ip_address: None,
    };

    // 2. Act: Insere no banco administrativo (dá commit implícito porque é chamado direto no pool).
    let log_id = inserir_audit_log_global(&admin_pool, &entry)
        .await
        .expect("Falha ao inserir log de auditoria global");

    // 3. Assert: Busca usando as APIs administrativas
    // Busca logs globais (onde tenant_id IS NULL)
    let logs_globais = buscar_audit_logs_globais(&admin_pool, 20, 0)
        .await
        .expect("Falha ao buscar logs globais");

    let log_encontrado = logs_globais.iter().find(|l| l.id == log_id);
    assert!(
        log_encontrado.is_some(),
        "Log global inserido não foi encontrado na busca global"
    );
    let log = log_encontrado.unwrap();
    assert_eq!(log.tenant_id, None);
    assert_eq!(log.level, "WARN");
    assert_eq!(log.service, "test-global-service");
    assert_eq!(log.event, unique_event);

    // Busca todos os logs filtrados por evento (usando a API geral de admin)
    let logs_admin_filtrado = buscar_audit_logs_admin(&admin_pool, Some(&unique_event), 10, 0)
        .await
        .expect("Falha ao buscar logs filtrados na API de admin");
    assert_eq!(logs_admin_filtrado.len(), 1);
    assert_eq!(logs_admin_filtrado[0].id, log_id);

    // 4. Teardown: Remove manualmente o log global inserido para manter o banco limpo.
    sqlx::query("DELETE FROM audit_log WHERE id = $1")
        .bind(log_id)
        .execute(&admin_pool)
        .await
        .expect("Falha ao limpar log de auditoria de teste global");
}

#[tokio::test]
async fn test_audit_log_cascading_deletion_on_tenant() {
    // 1. Arrange: Obtém pool administrativo para manipulação de tenants globais e cascade.
    let admin_pool = obter_admin_pool_teste().await;
    let mut tx = admin_pool
        .begin()
        .await
        .expect("Falha ao iniciar transação admin");

    // Cria um tenant temporário.
    let tenant = criar_tenant_para_teste(&mut tx, "Tenant Auditoria Cascade").await;

    // Insere um log de auditoria associado a esse tenant na transação admin.
    let entry = NewAuditLogEntry {
        tenant_id: Some(tenant.id),
        level: "ERROR".to_string(),
        service: "test-cascade-service".to_string(),
        trace_id: None,
        event: "CASCADE_TEST".to_string(),
        message: "Log associado a tenant para teste de exclusão em cascata".to_string(),
        context: serde_json::json!({}),
        user_id: Some(1),
        ip_address: None,
    };
    let log_id = inserir_audit_log(&mut tx, &entry)
        .await
        .expect("Falha ao inserir log de auditoria para cascade");

    // Confirma que o log foi inserido.
    let logs_antes = buscar_audit_logs(&mut tx, tenant.id, 10, 0)
        .await
        .expect("Falha ao buscar log antes da exclusão");
    assert_eq!(logs_antes.len(), 1);

    // 2. Act: Deleta o tenant de teste da tabela tenants_tenant.
    sqlx::query("DELETE FROM tenants_tenant WHERE id = $1")
        .bind(tenant.id)
        .execute(&mut *tx)
        .await
        .expect("Falha ao deletar tenant de teste");

    // 3. Assert: Verifica se o log correspondente sumiu (ON DELETE CASCADE).
    let rows: Vec<AuditLogEntry> =
        sqlx::query_as::<_, AuditLogEntry>("SELECT * FROM audit_log WHERE id = $1")
            .bind(log_id)
            .fetch_all(&mut *tx)
            .await
            .expect("Falha ao buscar log pós-deleção");

    assert!(
        rows.is_empty(),
        "ERRO: O log de auditoria não foi apagado após a exclusão do Tenant associado!"
    );

    // 4. Teardown
    tx.rollback()
        .await
        .expect("Falha ao reverter transação admin");
}

#[tokio::test]
async fn test_audit_log_user_deletion_sets_null() {
    // 1. Arrange: Obtém pool admin e inicia transação.
    let admin_pool = obter_admin_pool_teste().await;
    let mut tx = admin_pool
        .begin()
        .await
        .expect("Falha ao iniciar transação admin");

    // Cria um usuário temporário no banco para o teste.
    let user_row = sqlx::query(
        "INSERT INTO auth_user (username, email, is_active, is_staff, is_superuser)
         VALUES ('temp_audit_user', 'temp_audit@test.com', true, false, false)
         RETURNING id",
    )
    .fetch_one(&mut *tx)
    .await
    .expect("Falha ao criar usuário temporário");
    let temp_user_id: i32 = user_row.get("id");

    // Cria tenant de teste.
    let tenant = criar_tenant_para_teste(&mut tx, "Tenant User Null").await;

    // Insere o log de auditoria vinculado a esse usuário temporário.
    let entry = NewAuditLogEntry {
        tenant_id: Some(tenant.id),
        level: "INFO".to_string(),
        service: "test-user-null-service".to_string(),
        trace_id: None,
        event: "USER_NULL_TEST".to_string(),
        message: "Log associado a usuário temporário".to_string(),
        context: serde_json::json!({}),
        user_id: Some(temp_user_id),
        ip_address: None,
    };
    let log_id = inserir_audit_log(&mut tx, &entry)
        .await
        .expect("Falha ao inserir log associado a usuário");

    // 2. Act: Deleta o usuário da tabela auth_user.
    sqlx::query("DELETE FROM auth_user WHERE id = $1")
        .bind(temp_user_id)
        .execute(&mut *tx)
        .await
        .expect("Falha ao deletar usuário temporário");

    // 3. Assert: O log de auditoria deve continuar existindo, mas com o campo user_id = NULL.
    let log_pos: AuditLogEntry =
        sqlx::query_as::<_, AuditLogEntry>("SELECT * FROM audit_log WHERE id = $1")
            .bind(log_id)
            .fetch_one(&mut *tx)
            .await
            .expect("Falha ao buscar log pós-exclusão do usuário");

    assert_eq!(
        log_pos.user_id, None,
        "ERRO: O user_id deveria ter sido atualizado para NULL (ON DELETE SET NULL)"
    );

    // 4. Teardown
    tx.rollback().await.expect("Falha ao reverter transação");
}
