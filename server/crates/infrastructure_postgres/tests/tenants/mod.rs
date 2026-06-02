use crate::common::{
    configurar_tenant_transacao, criar_contexto_teste, criar_tenant_para_teste, obter_pool_teste,
};
use infrastructure_postgres::{
    config_cache::TenantConfigCache,
    crypto::CipherManager,
    tenants::{
        plans::{
            PaymentRecordRepository, Plan, PostgresPaymentRecordRepository,
            PostgresSubscriptionRepository, SubscriptionRepository,
        },
        tenants::{PostgresTenantRepository, TenantRepository},
    },
};
use std::sync::Arc;
use uuid::Uuid;

#[tokio::test]
async fn test_tenant_crud_and_rls() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let tenant_repo = PostgresTenantRepository;

    // 1. Criar novo Tenant (gera UUID + api_key internamente; configura RLS antes do INSERT)
    let slug = format!("tenant-{}", Uuid::new_v4());
    let tenant = tenant_repo
        .criar(
            &mut tx,
            "Tenant Teste CRUD",
            &slug,
            Some(1),
            Some("teste@tenant.com"),
            None,
        )
        .await
        .expect("Falha ao criar tenant");

    assert_eq!(tenant.name, "Tenant Teste CRUD");
    assert_eq!(tenant.slug, slug);
    assert!(tenant.active);

    // Configura RLS para o tenant criado
    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    // 2. Buscar por ID e por Slug
    let tenant_por_id = tenant_repo
        .buscar_por_id(&mut tx, &ctx, tenant.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(tenant_por_id.id, tenant.id);

    let tenant_por_slug = tenant_repo
        .buscar_por_slug(&mut tx, &ctx, &slug)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(tenant_por_slug.id, tenant.id);

    // 3. Atualizar Status (desativar)
    tenant_repo
        .atualizar_status(&mut tx, &ctx, tenant.id, false)
        .await
        .unwrap();
    let tenant_inativo = tenant_repo
        .buscar_por_id(&mut tx, &ctx, tenant.id)
        .await
        .unwrap()
        .unwrap();
    assert!(!tenant_inativo.active);

    // 4. Verificar busca do próprio tenant pelo slug (confirmação de leitura consistente)
    // Nota: tenants_tenant é a tabela raiz; o isolamento de dados de tenant
    // (clientes, atendimentos, etc.) é testado nos testes específicos de RLS de cada domínio.
    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let tenant_reconfirmado = tenant_repo
        .buscar_por_slug(&mut tx, &ctx, &slug)
        .await
        .unwrap();
    assert!(
        tenant_reconfirmado.is_some(),
        "Tenant deve enxergar o próprio slug!"
    );

    tx.rollback().await.unwrap();
}

#[tokio::test]
async fn test_plans_and_subscriptions() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let sub_repo = PostgresSubscriptionRepository;
    let pgto_repo = PostgresPaymentRecordRepository;

    // 1. Criar um plano global (sem RLS nesta tabela)
    let plano_nome = format!("Plano {}", Uuid::new_v4());
    let plano = sqlx::query_as!(
        Plan,
        r#"INSERT INTO tenants_plan (name, description, price, max_instances, max_departments, active)
           VALUES ($1, 'Plano de testes', 99.90, 5, 3, true)
           RETURNING id, name, description, price, max_instances, max_departments, active, created_at"#,
        plano_nome
    )
    .fetch_one(&mut *tx)
    .await
    .unwrap();

    // 2. Criar Tenant
    let tenant = criar_tenant_para_teste(&mut tx, "Tenant Sub").await;

    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    // 3. Criar Assinatura via SQL direto (não há método criar no trait)
    sqlx::query!(
        r#"INSERT INTO tenants_subscription
               (tenant_id, plan_id, status, payment_gateway, external_customer_id, external_subscription_id)
           VALUES ($1, $2, 'ACTIVE', 'manual', '', '')"#,
        tenant.id, plano.id
    )
    .execute(&mut *tx)
    .await
    .unwrap();

    // 4. Buscar Assinatura por Tenant
    let sub_busca = sub_repo
        .buscar_por_tenant(&mut tx, &ctx)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(sub_busca.tenant_id, tenant.id);
    assert_eq!(sub_busca.plan_id, Some(plano.id));
    assert_eq!(sub_busca.status, "ACTIVE");

    // 5. Atualizar Status da Assinatura
    sub_repo
        .atualizar_status(&mut tx, &ctx, "CANCELED")
        .await
        .unwrap();
    let sub_cancelada = sub_repo
        .buscar_por_tenant(&mut tx, &ctx)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(sub_cancelada.status, "CANCELED");

    // 6. Criar Registro de Pagamento
    let hoje = chrono::Utc::now().date_naive();
    let pgto = pgto_repo
        .registrar(
            &mut tx,
            &ctx,
            rust_decimal::Decimal::new(9990, 2),
            "credit_card",
            hoje,
            hoje,
            hoje,
            "Pagamento de teste",
        )
        .await
        .unwrap();
    assert_eq!(pgto.tenant_id, tenant.id);
    assert_eq!(pgto.amount, rust_decimal::Decimal::new(9990, 2));

    tx.rollback().await.unwrap();
}

#[tokio::test]
async fn test_core_settings_and_config_cache() {
    let pool = obter_pool_teste().await;

    // Configura chave de criptografia de testes
    let key_str = "MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE=";
    std::env::set_var("ENCRYPTION_KEY", key_str);
    let cipher = Arc::new(CipherManager::new_from_env().unwrap());

    // Usar defaults da migration como globals (LLM_CLASS="ChatOpenAI", CHUNK_OVERLAP=200, etc.)
    // Inserir tenant config com overrides locais
    let mut tx = pool.begin().await.unwrap();
    let tenant = criar_tenant_para_teste(&mut tx, "Tenant Config").await;

    // Chave de API local encriptada no formato JSONB
    let (ct_local, nonce_local, tag_local) = cipher.encrypt(b"local-key-999").unwrap();
    let api_keys_json = serde_json::json!({
        "openai_api_key": {
            "ciphertext": ct_local,
            "nonce": nonce_local,
            "tag": tag_local
        }
    });

    sqlx::query!(
        r#"INSERT INTO tenants_tenantconfig
           (tenant_id, model, chunk_size, api_keys)
           VALUES ($1, $2, $3, $4)"#,
        tenant.id,
        Some("gpt-4-turbo"),
        Some(500_i32),
        api_keys_json
    )
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    // TenantConfigCache resolve Tenant > CoreSettings (defaults da migration)
    let cache = TenantConfigCache::new(pool.clone(), cipher.clone());
    let config = cache.get_config(tenant.id).await.unwrap();

    assert_eq!(config.tenant_id, tenant.id);
    // Valores sobrescritos pelo tenant
    assert_eq!(config.model, "gpt-4-turbo");
    assert_eq!(config.chunk_size, 500);
    // Valores herdados dos defaults da migration (0009_settings_manager.sql)
    assert_eq!(config.chunk_overlap, 200);
    assert_eq!(config.llm_class, "ChatOpenAI");
    assert!((config.llm_temperature - 0.7).abs() < 0.001);
    // Chave local sobrescreve o global vazio
    use secrecy::ExposeSecret;
    assert_eq!(config.openai_api_key.expose_secret(), "local-key-999");

    // Limpeza manual com RLS configurado
    let mut clean_tx = pool.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
        .bind(tenant.id.to_string())
        .execute(&mut *clean_tx)
        .await
        .unwrap();
    sqlx::query!(
        "DELETE FROM tenants_tenantconfig WHERE tenant_id = $1",
        tenant.id
    )
    .execute(&mut *clean_tx)
    .await
    .unwrap();
    sqlx::query!("DELETE FROM tenants_tenant WHERE id = $1", tenant.id)
        .execute(&mut *clean_tx)
        .await
        .unwrap();
    clean_tx.commit().await.unwrap();
}
