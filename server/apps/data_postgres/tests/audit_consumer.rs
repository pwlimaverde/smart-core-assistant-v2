//! Teste de INTEGRAÇÃO do consumidor de auditoria do `data_postgres`.
//!
//! Exercita `data_postgres::processar_eventos_auditoria_lote` contra um Postgres
//! real (via túnel SSH aberto automaticamente pelo `test_support`). Por ser
//! integração, vive em `tests/` e roda apenas na suíte completa (`test-local.ps1`
//! / CI), NUNCA no caminho rápido `--bins`.

use sqlx::PgPool;
use uuid::Uuid;

/// Carrega `server/.env` (idempotente) e garante o túnel SSH ativo.
fn carregar_env_teste() {
    test_support::ensure_tunnel();
    let caminhos = [
        ".env",
        "../.env",
        "../../.env",
        "apps/data_postgres/.env",
        "../data_postgres/.env",
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
}

/// Conecta no Postgres (pool admin), roda migrations e semeia o `auth_user` id=1.
async fn setup_pool() -> PgPool {
    carregar_env_teste();
    let admin_url = std::env::var("DATABASE_ADMIN_URL").expect("DATABASE_ADMIN_URL ausente");
    let pool = PgPool::connect(&admin_url)
        .await
        .expect("Falha ao conectar Postgres");

    infrastructure_postgres::inicializar_banco_dados(&pool)
        .await
        .unwrap();

    // Garante o `auth_user` id=1 — owner padrão dos fixtures de tenant. Idempotente.
    sqlx::query(
        "INSERT INTO auth_user (id, username, email, password_hash, is_superuser, is_staff) \
         VALUES (1, 'ci_seed_admin', 'ci-seed@local', '', TRUE, TRUE) \
         ON CONFLICT (id) DO NOTHING",
    )
    .execute(&pool)
    .await
    .expect("falha ao semear auth_user padrão");
    sqlx::query(
        "SELECT setval(pg_get_serial_sequence('auth_user','id'), \
         GREATEST((SELECT COALESCE(MAX(id), 1) FROM auth_user), 1))",
    )
    .execute(&pool)
    .await
    .expect("falha ao ajustar a sequence de auth_user");

    pool
}

#[tokio::test]
async fn processa_evento_de_auditoria_persiste_no_audit_log() {
    let pool = setup_pool().await;

    let tenant_id = Uuid::new_v4();
    let slug = format!("tenant-{}", Uuid::new_v4());
    sqlx::query(
        "INSERT INTO tenants_tenant (id, name, slug, api_key, owner_id) VALUES ($1, $2, $3, $4, 1)",
    )
    .bind(tenant_id)
    .bind("Tenant Audit Test")
    .bind(slug)
    .bind(Uuid::new_v4().to_string())
    .execute(&pool)
    .await
    .unwrap();

    let audit_payload = observability::AuditLogPayload {
        tenant_id: Some(tenant_id),
        level: "INFO".to_string(),
        service: "data_postgres_test".to_string(),
        trace_id: Some("00-trace5-span5-01".to_string()),
        event: "test_event".to_string(),
        message: "Evento de auditoria de teste integrado".to_string(),
        context: serde_json::json!({}),
        user_id: Some(1),
        ip_address: Some("127.0.0.1".to_string()),
        user_agent: Some("integration-test-suite/1.0".to_string()),
    };
    let payload_json_str = serde_json::to_string(&audit_payload).unwrap();

    let evt = transport::bus::EventoBruto {
        stream_id: "12345-0".to_string(),
        tenant_id: tenant_id.to_string(),
        event_id: Uuid::now_v7().to_string(),
        event_type: "security.audit".to_string(),
        timestamp: chrono::Utc::now().to_rfc3339(),
        traceparent: "00-trace5-span5-01".to_string(),
        payload: payload_json_str,
    };

    // Act: consolida o lote (1 evento tenant-scoped) no audit_log.
    let processou = data_postgres::processar_eventos_auditoria_lote(pool.clone(), vec![evt]).await;
    assert!(processou.is_ok(), "drenagem falhou: {:?}", processou.err());

    // Assert: o evento foi persistido sob o tenant correto.
    let count: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM audit_log WHERE tenant_id = $1 AND event = 'test_event'",
    )
    .bind(tenant_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(count.0, 1);

    // Limpeza
    sqlx::query("DELETE FROM tenants_tenant WHERE id = $1")
        .bind(tenant_id)
        .execute(&pool)
        .await
        .unwrap();
}
