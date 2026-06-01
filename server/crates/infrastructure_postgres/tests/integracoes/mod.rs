use uuid::Uuid;
use sqlx::Transaction;
use infrastructure_postgres::{
    integracoes::{
        evolution::{EvolutionInstanceRepository, PostgresEvolutionInstanceRepository, EvolutionContactRepository, PostgresEvolutionContactRepository, EvolutionInstance, EvolutionContact},
        whitelist::{WhiteListRepository, PostgresWhiteListRepository, WhiteList},
    },
    tenants::tenants::{TenantRepository, PostgresTenantRepository},
};
use crate::common::{obter_pool_teste, criar_contexto_teste, configurar_tenant_transacao};

#[tokio::test]
async fn test_evolution_sync_crud() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let tenant_repo = PostgresTenantRepository;
    let instance_repo = PostgresEvolutionInstanceRepository;
    let contact_repo = PostgresEvolutionContactRepository;

    // 1. Setup Tenant
    let slug = format!("tenant-{}", Uuid::new_v4());
    let tenant = tenant_repo.criar(&mut tx, "Tenant Evolution", &slug, None, None, None).await.unwrap();

    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    // 2. Criar EvolutionInstance
    let inst_name = "whatsapp-evolution-1";
    let inst = instance_repo.criar(&mut tx, &ctx, inst_name, "api-key-test").await.expect("Falha ao criar instância Evolution");
    assert_eq!(inst.name, inst_name);
    assert_eq!(inst.connection_state, "unknown");

    // Buscar por Name
    let inst_busca = instance_repo.buscar_por_name(&mut tx, &ctx, inst_name).await.unwrap().unwrap();
    assert_eq!(inst_busca.id, inst.id);

    // 3. Atualizar Estado
    sqlx::query!(
        "UPDATE evolution_sync_instance SET instance_id = 'inst-uuid-123' WHERE id = $1",
        inst.id
    ).execute(&mut *tx).await.unwrap();

    instance_repo.atualizar_estado(&mut tx, &ctx, "inst-uuid-123", "connected").await.expect("Falha ao atualizar estado");
    
    let inst_atualizada = instance_repo.buscar_por_name(&mut tx, &ctx, inst_name).await.unwrap().unwrap();
    assert_eq!(inst_atualizada.connection_state, "connected");

    // Listar Ativas
    let lista = instance_repo.listar_ativas(&mut tx, &ctx).await.unwrap();
    assert_eq!(lista.len(), 1);
    assert_eq!(lista[0].id, inst.id);

    // 4. Criar ou Atualizar EvolutionContact
    let jid = "5511999998888@s.whatsapp.net";
    let contact = contact_repo.criar_ou_atualizar(&mut tx, &ctx, inst.id, jid, Some(42)).await.expect("Falha ao criar contato evolution");
    assert_eq!(contact.jid.as_deref(), Some(jid));
    assert_eq!(contact.contact_id, Some(42));

    // Buscar por JID
    let contact_busca = contact_repo.buscar_por_jid(&mut tx, &ctx, jid).await.unwrap().unwrap();
    assert_eq!(contact_busca.id, contact.id);

    // Upsert (atualizar contact_id)
    let contact_up = contact_repo.criar_ou_atualizar(&mut tx, &ctx, inst.id, jid, Some(43)).await.unwrap();
    assert_eq!(contact_up.id, contact.id); // Mesmo ID
    assert_eq!(contact_up.contact_id, Some(43)); // Novo ID do contato

    tx.rollback().await.unwrap();
}

#[tokio::test]
async fn test_whitelist_crud() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let tenant_repo = PostgresTenantRepository;
    let whitelist_repo = PostgresWhiteListRepository;

    // Setup Tenant
    let slug = format!("tenant-{}", Uuid::new_v4());
    let tenant = tenant_repo.criar(&mut tx, "Tenant Whitelist", &slug, None, None, None).await.unwrap();

    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    // 1. Criar Whitelist
    let phone = "5511912345678";
    let wl = whitelist_repo.criar(&mut tx, &ctx, "Cliente Whitelisted", phone, None).await.expect("Falha ao criar whitelist");
    assert_eq!(wl.phone_number, phone);
    assert!(wl.active);

    // 2. Verificar se está na lista
    let na_lista = whitelist_repo.esta_na_lista(&mut tx, &ctx, phone).await.unwrap();
    assert!(na_lista, "Telefone deveria estar na whitelist!");

    let nao_na_lista = whitelist_repo.esta_na_lista(&mut tx, &ctx, "5511988887777").await.unwrap();
    assert!(!nao_na_lista, "Telefone não deveria estar na whitelist!");

    // 3. Listar ativas
    let lista = whitelist_repo.listar_ativas(&mut tx, &ctx).await.unwrap();
    assert_eq!(lista.len(), 1);
    assert_eq!(lista[0].id, wl.id);

    tx.rollback().await.unwrap();
}

#[tokio::test]
async fn test_integracoes_rls_isolation() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let tenant_repo = PostgresTenantRepository;
    let instance_repo = PostgresEvolutionInstanceRepository;
    let whitelist_repo = PostgresWhiteListRepository;

    // Setup Tenants
    let slug_a = format!("tenant-{}", Uuid::new_v4());
    let tenant_a = tenant_repo.criar(&mut tx, "Tenant A", &slug_a, None, None, None).await.unwrap();
    
    let slug_b = format!("tenant-{}", Uuid::new_v4());
    let tenant_b = tenant_repo.criar(&mut tx, "Tenant B", &slug_b, None, None, None).await.unwrap();

    // 1. Criar registros no Tenant A
    configurar_tenant_transacao(&mut tx, tenant_a.id).await;
    let ctx_a = criar_contexto_teste(tenant_a.id);
    
    let _inst_a = instance_repo.criar(&mut tx, &ctx_a, "instancia-a", "key-a").await.unwrap();
    
    let phone_a = "5511999991111";
    whitelist_repo.criar(&mut tx, &ctx_a, "WL A", phone_a, None).await.unwrap();

    // 2. Mudar para Tenant B e tentar acessar
    configurar_tenant_transacao(&mut tx, tenant_b.id).await;
    let ctx_b = criar_contexto_teste(tenant_b.id);

    let busca_inst = instance_repo.buscar_por_name(&mut tx, &ctx_b, "instancia-a").await.unwrap();
    assert!(busca_inst.is_none(), "Tenant B acessou instância do Tenant A!");

    let esta_na_lista_b = whitelist_repo.esta_na_lista(&mut tx, &ctx_b, phone_a).await.unwrap();
    assert!(!esta_na_lista_b, "Tenant B enxergou número da whitelist do Tenant A!");

    tx.rollback().await.unwrap();
}
