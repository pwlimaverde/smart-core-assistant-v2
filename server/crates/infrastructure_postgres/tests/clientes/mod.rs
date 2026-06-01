use uuid::Uuid;
use sqlx::Transaction;
use infrastructure_postgres::{
    clientes::{
        contatos::{ContatoRepository, PostgresContatoRepository, Contato},
        clientes::{ClienteRepository, PostgresClienteRepository, Cliente},
    },
    tenants::tenants::{TenantRepository, PostgresTenantRepository},
};
use crate::common::{obter_pool_teste, criar_contexto_teste, configurar_tenant_transacao};

#[tokio::test]
async fn test_contato_crud_and_idempotence() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let tenant_repo = PostgresTenantRepository;
    let contato_repo = PostgresContatoRepository;

    // 1. Setup Tenant
    let slug = format!("tenant-{}", Uuid::new_v4());
    let tenant = tenant_repo.criar(&mut tx, "Tenant Contatos", &slug, None, None, None).await.unwrap();

    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    // 2. Criar Contato
    let telefone = "5511999998888";
    let contato = contato_repo.salvar(
        &mut tx,
        &ctx,
        telefone,
        Some("João Silva"),
        Some("joao@silva.com"),
        None,
        None,
    ).await.expect("Falha ao salvar contato");

    assert_eq!(contato.telefone, telefone);
    assert_eq!(contato.nome_contato.as_deref(), Some("João Silva"));
    assert_eq!(contato.email.as_deref(), Some("joao@silva.com"));
    assert!(contato.ativo);

    // 3. Buscar por ID e Telefone
    let contato_por_id = contato_repo.buscar_por_id(&mut tx, &ctx, contato.id).await.unwrap().unwrap();
    assert_eq!(contato_por_id.id, contato.id);

    let contato_por_tel = contato_repo.buscar_por_telefone(&mut tx, &ctx, telefone).await.unwrap().unwrap();
    assert_eq!(contato_por_tel.id, contato.id);

    // 4. Testar Idempotência (ON CONFLICT DO UPDATE)
    let contato_atualizado = contato_repo.salvar(
        &mut tx,
        &ctx,
        telefone,
        Some("João S. Silva"),
        Some("joao.novo@silva.com"),
        None,
        None,
    ).await.expect("Falha ao re-salvar contato");

    assert_eq!(contato_atualizado.id, contato.id); // Mesmo ID
    assert_eq!(contato_atualizado.nome_contato.as_deref(), Some("João S. Silva")); // Nome atualizado
    assert_eq!(contato_atualizado.email.as_deref(), Some("joao.novo@silva.com")); // Email atualizado

    tx.rollback().await.unwrap();
}

#[tokio::test]
async fn test_cliente_crud_and_m2m() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let tenant_repo = PostgresTenantRepository;
    let cliente_repo = PostgresClienteRepository;
    let contato_repo = PostgresContatoRepository;

    // Setup Tenant
    let slug = format!("tenant-{}", Uuid::new_v4());
    let tenant = tenant_repo.criar(&mut tx, "Tenant Clientes", &slug, None, None, None).await.unwrap();

    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    // 1. Criar Cliente
    let cliente = cliente_repo.criar(
        &mut tx,
        &ctx,
        "Empresa Teste SA",
        "empresa-teste-sa",
        Some("Empresa Teste Limitada"),
        "JURIDICA",
        Some("12.345.678/0001-99"),
        None,
        None,
    ).await.expect("Falha ao criar cliente");

    assert_eq!(cliente.nome_fantasia, "Empresa Teste SA");
    assert_eq!(cliente.cnpj.as_deref(), Some("12.345.678/0001-99"));

    // 2. Buscar por ID e listar ativos
    let cliente_busca = cliente_repo.buscar_por_id(&mut tx, &ctx, cliente.id).await.unwrap().unwrap();
    assert_eq!(cliente_busca.id, cliente.id);

    let lista = cliente_repo.listar_ativos(&mut tx, &ctx, 10).await.unwrap();
    assert!(!lista.is_empty());
    assert_eq!(lista[0].id, cliente.id);

    // 3. Criar Contato para associar
    let contato = contato_repo.salvar(
        &mut tx,
        &ctx,
        "5511977776666",
        Some("Maria Souza"),
        None,
        None,
        None,
    ).await.unwrap();

    // 4. M2M Associação
    cliente_repo.adicionar_contato(&mut tx, &ctx, cliente.id, contato.id).await.expect("Falha ao associar contato ao cliente");

    // Listar contatos associados
    let contatos_associados = cliente_repo.listar_contatos(&mut tx, &ctx, cliente.id).await.unwrap();
    assert_eq!(contatos_associados.len(), 1);
    assert_eq!(contatos_associados[0].id, contato.id);

    // 5. M2M Remoção
    cliente_repo.remover_contato(&mut tx, &ctx, cliente.id, contato.id).await.expect("Falha ao remover associação de contato");
    let contatos_associados_pos = cliente_repo.listar_contatos(&mut tx, &ctx, cliente.id).await.unwrap();
    assert!(contatos_associados_pos.is_empty());

    tx.rollback().await.unwrap();
}

#[tokio::test]
async fn test_clientes_rls_isolation() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let tenant_repo = PostgresTenantRepository;
    let cliente_repo = PostgresClienteRepository;
    let contato_repo = PostgresContatoRepository;

    // Criar Tenant A e Tenant B
    let slug_a = format!("tenant-{}", Uuid::new_v4());
    let tenant_a = tenant_repo.criar(&mut tx, "Tenant A", &slug_a, None, None, None).await.unwrap();
    
    let slug_b = format!("tenant-{}", Uuid::new_v4());
    let tenant_b = tenant_repo.criar(&mut tx, "Tenant B", &slug_b, None, None, None).await.unwrap();

    // 1. Criar cliente no Tenant A
    configurar_tenant_transacao(&mut tx, tenant_a.id).await;
    let ctx_a = criar_contexto_teste(tenant_a.id);
    let cliente_a = cliente_repo.criar(
        &mut tx,
        &ctx_a,
        "Cliente do Tenant A",
        "cliente-a",
        None,
        "FISICA",
        None,
        None,
        None,
    ).await.unwrap();

    // Criar contato no Tenant A
    let contato_a = contato_repo.salvar(
        &mut tx,
        &ctx_a,
        "5511966665555",
        Some("Contato A"),
        None,
        None,
        None,
    ).await.unwrap();

    // 2. Alternar contexto para Tenant B e tentar acessar registros do Tenant A
    configurar_tenant_transacao(&mut tx, tenant_b.id).await;
    let ctx_b = criar_contexto_teste(tenant_b.id);

    // Tentar buscar cliente do Tenant A -> deve retornar None
    let busca_cliente = cliente_repo.buscar_por_id(&mut tx, &ctx_b, cliente_a.id).await.unwrap();
    assert!(busca_cliente.is_none(), "Tenant B acessou cliente do Tenant A!");

    // Tentar buscar contato do Tenant A -> deve retornar None
    let busca_contato = contato_repo.buscar_por_id(&mut tx, &ctx_b, contato_a.id).await.unwrap();
    assert!(busca_contato.is_none(), "Tenant B acessou contato do Tenant A!");

    // Tentar listar contatos ativos no Tenant B -> não deve trazer o contato do Tenant A
    let lista_contatos_b = contato_repo.buscar_por_telefone(&mut tx, &ctx_b, "5511966665555").await.unwrap();
    assert!(lista_contatos_b.is_none(), "Tenant B enxergou contato do Tenant A por telefone!");

    tx.rollback().await.unwrap();
}
