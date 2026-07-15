use crate::common::{
    configurar_tenant_transacao, criar_contexto_teste, criar_tenant_para_teste, obter_pool_teste,
};
use infrastructure_postgres::{
    config_cache::TenantConfigCache,
    crypto::CipherManager,
    security::RequestContext,
    tenants::{
        plans::{
            PaymentRecordRepository, Plan, PostgresPaymentRecordRepository,
            PostgresSubscriptionRepository, SubscriptionRepository,
        },
        tenants::{
            PostgresTenantInviteRepository, PostgresTenantRepository, PostgresTenantUserRepository,
            TenantInviteRepository, TenantRepository, TenantUserRepository,
        },
    },
    DbError,
};
use sqlx::{Postgres, Transaction};
use std::sync::Arc;
use uuid::Uuid;

/// RequestContext de teste SEM o escopo `tenant:admin` (para checar negação de RBAC).
fn contexto_sem_admin(tenant_id: Uuid) -> RequestContext {
    RequestContext {
        tenant_id,
        user_id: 1,
        user_scopes: vec!["atendimentos:read".into()],
        flow_permissions: vec![],
    }
}

/// Cria um auth_user de teste (tabela global, sem RLS) e retorna seu id.
async fn criar_auth_user(tx: &mut Transaction<'_, Postgres>) -> i32 {
    let sufixo = Uuid::new_v4().simple().to_string();
    sqlx::query_scalar::<_, i32>(
        "INSERT INTO auth_user (username, email, is_active, is_staff, is_superuser) \
         VALUES ($1, $2, true, false, false) RETURNING id",
    )
    .bind(format!("user-{sufixo}"))
    .bind(format!("{sufixo}@teste.com"))
    .fetch_one(&mut **tx)
    .await
    .expect("Falha ao criar auth_user de teste")
}

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

#[tokio::test]
async fn test_tenant_user_listar_e_atualizar() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let user_repo = PostgresTenantUserRepository;
    let tenant = criar_tenant_para_teste(&mut tx, "Tenant Usuarios").await;
    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    // Cria dois auth_users e seus vínculos TenantUser.
    let uid_a = criar_auth_user(&mut tx).await;
    let uid_b = criar_auth_user(&mut tx).await;
    user_repo
        .criar(&mut tx, &ctx, uid_a, "staff")
        .await
        .unwrap();
    user_repo
        .criar(&mut tx, &ctx, uid_b, "staff")
        .await
        .unwrap();

    // 1. Listagem retorna os dois usuários do tenant.
    let usuarios = user_repo.listar_por_tenant(&mut tx, &ctx).await.unwrap();
    assert_eq!(usuarios.len(), 2);
    assert!(usuarios.iter().all(|u| u.tenant_id == tenant.id));

    // 2. Atualização de role + module_permissions (escopos) + flow_permissions.
    let novos_escopos = serde_json::json!(["tenant:admin", "clientes:write"]);
    let novos_fluxos = serde_json::json!([7, 8]);
    let afetou = user_repo
        .atualizar(
            &mut tx,
            &ctx,
            uid_a,
            Some("admin"),
            Some(novos_escopos.clone()),
            Some(novos_fluxos.clone()),
        )
        .await
        .unwrap();
    assert!(afetou);

    let usuarios = user_repo.listar_por_tenant(&mut tx, &ctx).await.unwrap();
    let atualizado = usuarios.iter().find(|u| u.user_id == uid_a).unwrap();
    assert_eq!(atualizado.role, "admin");
    assert_eq!(atualizado.module_permissions, novos_escopos);
    assert_eq!(atualizado.flow_permissions, novos_fluxos);

    // 3. COALESCE: campos None preservam os valores atuais (só muda a role).
    let afetou = user_repo
        .atualizar(&mut tx, &ctx, uid_a, Some("staff"), None, None)
        .await
        .unwrap();
    assert!(afetou);
    let usuarios = user_repo.listar_por_tenant(&mut tx, &ctx).await.unwrap();
    let atualizado = usuarios.iter().find(|u| u.user_id == uid_a).unwrap();
    assert_eq!(atualizado.role, "staff");
    assert_eq!(atualizado.module_permissions, novos_escopos);
    assert_eq!(atualizado.flow_permissions, novos_fluxos);

    // 4. Usuário inexistente no tenant → nenhuma linha afetada.
    let afetou = user_repo
        .atualizar(&mut tx, &ctx, 999_999, Some("admin"), None, None)
        .await
        .unwrap();
    assert!(!afetou);

    tx.rollback().await.unwrap();
}

#[tokio::test]
async fn test_tenant_user_rbac_negado_sem_admin() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let user_repo = PostgresTenantUserRepository;
    let tenant = criar_tenant_para_teste(&mut tx, "Tenant RBAC User").await;
    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx_negado = contexto_sem_admin(tenant.id);

    // Sem tenant:admin, listar e atualizar devem falhar antes de tocar o banco.
    assert!(matches!(
        user_repo.listar_por_tenant(&mut tx, &ctx_negado).await,
        Err(DbError::PermissionDenied)
    ));
    assert!(matches!(
        user_repo
            .atualizar(&mut tx, &ctx_negado, 1, Some("admin"), None, None)
            .await,
        Err(DbError::PermissionDenied)
    ));

    tx.rollback().await.unwrap();
}

#[tokio::test]
async fn test_invites_listar_e_revogar() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let invite_repo = PostgresTenantInviteRepository;
    let tenant = criar_tenant_para_teste(&mut tx, "Tenant Convites").await;
    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    let futuro = chrono::Utc::now() + chrono::Duration::days(7);

    // Convite válido (será revogado), convite usado e convite expirado.
    let valido = invite_repo
        .criar(&mut tx, &ctx, "a@teste.com", "A", "staff", &token(), futuro)
        .await
        .unwrap();
    let usado = invite_repo
        .criar(&mut tx, &ctx, "b@teste.com", "B", "staff", &token(), futuro)
        .await
        .unwrap();
    let passado = chrono::Utc::now() - chrono::Duration::days(1);
    let expirado = invite_repo
        .criar(
            &mut tx,
            &ctx,
            "c@teste.com",
            "C",
            "staff",
            &token(),
            passado,
        )
        .await
        .unwrap();
    sqlx::query("UPDATE tenants_tenantinvite SET used = true WHERE id = $1")
        .bind(usado.id)
        .execute(&mut *tx)
        .await
        .unwrap();

    // 1. Listagem traz os três convites, todos ainda não revogados.
    let convites = invite_repo.listar_por_tenant(&mut tx, &ctx).await.unwrap();
    assert_eq!(convites.len(), 3);
    assert!(convites.iter().all(|c| !c.revoked));

    // 2. Revoga o convite válido → true; revogar de novo → false (já revogado).
    assert!(invite_repo
        .marcar_revogado(&mut tx, &ctx, valido.id)
        .await
        .unwrap());
    assert!(!invite_repo
        .marcar_revogado(&mut tx, &ctx, valido.id)
        .await
        .unwrap());

    // 3. Convite usado e convite expirado não podem ser revogados.
    assert!(!invite_repo
        .marcar_revogado(&mut tx, &ctx, usado.id)
        .await
        .unwrap());
    assert!(!invite_repo
        .marcar_revogado(&mut tx, &ctx, expirado.id)
        .await
        .unwrap());

    // 4. Após revogar, a listagem reflete revoked = true no convite correto.
    let convites = invite_repo.listar_por_tenant(&mut tx, &ctx).await.unwrap();
    let item = convites.iter().find(|c| c.id == valido.id).unwrap();
    assert!(item.revoked);

    tx.rollback().await.unwrap();
}

#[tokio::test]
async fn test_invites_rbac_negado_sem_admin() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let invite_repo = PostgresTenantInviteRepository;
    let tenant = criar_tenant_para_teste(&mut tx, "Tenant RBAC Convite").await;
    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx_negado = contexto_sem_admin(tenant.id);

    assert!(matches!(
        invite_repo.listar_por_tenant(&mut tx, &ctx_negado).await,
        Err(DbError::PermissionDenied)
    ));
    assert!(matches!(
        invite_repo
            .marcar_revogado(&mut tx, &ctx_negado, Uuid::new_v4())
            .await,
        Err(DbError::PermissionDenied)
    ));

    tx.rollback().await.unwrap();
}

/// Gera um token URL-safe de 64 caracteres para os convites de teste.
fn token() -> String {
    format!("{}{}", Uuid::new_v4().simple(), Uuid::new_v4().simple())
}
