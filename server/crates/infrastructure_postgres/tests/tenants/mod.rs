use std::sync::Arc;
use uuid::Uuid;
use sqlx::PgPool;
use infrastructure_postgres::{
    tenants::{
        tenants::{TenantRepository, PostgresTenantRepository, Tenant, TenantUser, TenantInvite},
        plans::{PlanRepository, PostgresPlanRepository, Plan, Subscription, PaymentRecord},
        settings::{CoreSettingsRepository, PostgresCoreSettingsRepository, CoreSettings},
        config::resolve_runtime_config,
    },
    config_cache::TenantConfigCache,
    crypto::CipherManager,
};
use crate::common::{obter_pool_teste, criar_contexto_teste, configurar_tenant_transacao};

#[tokio::test]
async fn test_tenant_crud_and_rls() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let tenant_repo = PostgresTenantRepository;
    
    // 1. Criar novo Tenant
    let slug = format!("tenant-{}", Uuid::new_v4());
    let tenant = tenant_repo.criar(
        &mut tx,
        "Tenant Teste CRUD",
        &slug,
        None, // sem owner id por enquanto
        Some("teste@tenant.com"),
        None,
    ).await.expect("Falha ao criar tenant");

    assert_eq!(tenant.name, "Tenant Teste CRUD");
    assert_eq!(tenant.slug, slug);
    assert!(tenant.active);

    // Configurar o RLS para o ID do tenant criado
    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    // 2. Buscar por ID e por Slug
    let tenant_por_id = tenant_repo.buscar_por_id(&mut tx, &ctx, tenant.id).await.unwrap().unwrap();
    assert_eq!(tenant_por_id.id, tenant.id);

    let tenant_por_slug = tenant_repo.buscar_por_slug(&mut tx, &ctx, &slug).await.unwrap().unwrap();
    assert_eq!(tenant_por_slug.id, tenant.id);

    // 3. Atualizar Status
    tenant_repo.atualizar_status(&mut tx, &ctx, tenant.id, false).await.unwrap();
    let tenant_inativo = tenant_repo.buscar_por_id(&mut tx, &ctx, tenant.id).await.unwrap().unwrap();
    assert!(!tenant_inativo.active);

    // 4. Testar Isolamento RLS com outro Tenant
    let outro_tenant_id = Uuid::new_v4();
    configurar_tenant_transacao(&mut tx, outro_tenant_id).await;
    let outro_ctx = criar_contexto_teste(outro_tenant_id);

    // A busca por ID do tenant original pelo contexto do outro tenant deve retornar NotFound ou None (se filtrado pela policy)
    let busca_cross = tenant_repo.buscar_por_id(&mut tx, &outro_ctx, tenant.id).await.unwrap();
    assert!(busca_cross.is_none(), "Isolamento RLS falhou para tenants_tenant!");

    tx.rollback().await.unwrap();
}

#[tokio::test]
async fn test_plans_and_subscriptions() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let plan_repo = PostgresPlanRepository;
    let tenant_repo = PostgresTenantRepository;

    // 1. Criar um plano global
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
    let slug = format!("tenant-{}", Uuid::new_v4());
    let tenant = tenant_repo.criar(&mut tx, "Tenant Sub", &slug, None, None, None).await.unwrap();

    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    // 3. Criar Assinatura
    let sub = plan_repo.criar_assinatura(&mut tx, &ctx, tenant.id, plano.id).await.unwrap();
    assert_eq!(sub.tenant_id, tenant.id);
    assert_eq!(sub.plan_id, plano.id);
    assert_eq!(sub.status, "ACTIVE");

    // 4. Buscar Assinatura por Tenant
    let sub_busca = plan_repo.buscar_por_tenant(&mut tx, &ctx, tenant.id).await.unwrap().unwrap();
    assert_eq!(sub_busca.id, sub.id);

    // 5. Atualizar Status da Assinatura
    plan_repo.atualizar_status(&mut tx, &ctx, sub.id, "CANCELED").await.unwrap();
    let sub_cancelada = plan_repo.buscar_por_tenant(&mut tx, &ctx, tenant.id).await.unwrap().unwrap();
    assert_eq!(sub_cancelada.status, "CANCELED");

    // 6. Criar Registro de Pagamento
    let pgto = plan_repo.registrar_pagamento(
        &mut tx,
        &ctx,
        tenant.id,
        rust_decimal::Decimal::new(9990, 2),
        chrono::Utc::now().naive_utc().into(),
        "credit_card",
        None,
    ).await.unwrap();
    assert_eq!(pgto.tenant_id, tenant.id);
    assert_eq!(pgto.amount, rust_decimal::Decimal::new(9990, 2));

    tx.rollback().await.unwrap();
}

#[tokio::test]
async fn test_core_settings_and_config_cache() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let settings_repo = PostgresCoreSettingsRepository;
    let tenant_repo = PostgresTenantRepository;
    
    // Injetar chave de criptografia de teste
    let key_str = "MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE="; // base64 de 32 bytes
    std::env::set_var("ENCRYPTION_KEY", key_str);
    let cipher = Arc::new(CipherManager::new_from_env().unwrap());

    // 1. Criar configurações globais de fallback (CoreSettings)
    sqlx::query("DELETE FROM settings_manager_coresettings").execute(&mut *tx).await.unwrap();
    
    settings_repo.salvar(&mut tx, "LLM_CLASS", "openai", false, Some("LLM provider")).await.unwrap();
    settings_repo.salvar(&mut tx, "MODEL", "gpt-4o", false, None).await.unwrap();
    settings_repo.salvar(&mut tx, "LLM_TEMPERATURE", "0.7", false, None).await.unwrap();
    settings_repo.salvar(&mut tx, "CHUNK_SIZE", "1000", false, None).await.unwrap();
    settings_repo.salvar(&mut tx, "CHUNK_OVERLAP", "200", false, None).await.unwrap();
    settings_repo.salvar(&mut tx, "SIMILARITY_THRESHOLD", "0.6", false, None).await.unwrap();
    settings_repo.salvar(&mut tx, "VECTOR_DISTANCE_THRESHOLD", "0.4", false, None).await.unwrap();

    // Chave de API global encriptada
    let (ct, nonce, tag) = cipher.encrypt(b"global-key-123").unwrap();
    sqlx::query!(
        r#"INSERT INTO settings_manager_coresettings (key, value, encrypted)
           VALUES ('OPENAI_API_KEY', $1, true)"#,
        format!("{{\"ciphertext\":\"{}\",\"nonce\":\"{}\",\"tag\":\"{}\"}}", ct, nonce, tag)
    ).execute(&mut *tx).await.unwrap();

    // 2. Criar Tenant e sua configuração local
    let slug = format!("tenant-{}", Uuid::new_v4());
    let tenant = tenant_repo.criar(&mut tx, "Tenant Config", &slug, None, None, None).await.unwrap();

    // Inserir configuração local do tenant na tabela tenants_tenantconfig
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
        Some(500),
        api_keys_json
    ).execute(&mut *tx).await.unwrap();

    tx.commit().await.unwrap();

    // Executa fora da transação
    let cache = TenantConfigCache::new(pool.clone(), cipher.clone());
    let config = cache.get_config(tenant.id).await.unwrap();

    // Assert: Fallbacks aplicados corretamente
    assert_eq!(config.tenant_id, tenant.id);
    assert_eq!(config.model, "gpt-4-turbo"); // Sobrescrito localmente
    assert_eq!(config.chunk_size, 500);       // Sobrescrito localmente
    assert_eq!(config.chunk_overlap, 200);    // Herdado do global
    assert_eq!(config.llm_class, "openai");   // Herdado do global
    assert_eq!(config.llm_temperature, 0.7);  // Herdado do global
    
    use secrecy::ExposeSecret;
    assert_eq!(config.openai_api_key.expose_secret(), "local-key-999"); // Sobrescrito localmente

    // Limpeza manual pós-commit
    let mut clean_tx = pool.begin().await.unwrap();
    sqlx::query!("DELETE FROM tenants_tenantconfig WHERE tenant_id = $1", tenant.id).execute(&mut *clean_tx).await.unwrap();
    sqlx::query!("DELETE FROM tenants_tenant WHERE id = $1", tenant.id).execute(&mut *clean_tx).await.unwrap();
    sqlx::query!("DELETE FROM settings_manager_coresettings").execute(&mut *clean_tx).await.unwrap();
    clean_tx.commit().await.unwrap();
}
