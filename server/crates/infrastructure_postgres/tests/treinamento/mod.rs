use uuid::Uuid;
use sqlx::Transaction;
use infrastructure_postgres::{
    treinamento::{
        treinamentos::{TreinamentoRepository, PostgresTreinamentoRepository, Treinamento},
        documentos::{DocumentoRepository, PostgresDocumentoRepository, Documento},
        query_compose::{QueryComposeRepository, PostgresQueryComposeRepository, QueryCompose, to_embedding_text},
    },
    tenants::tenants::{TenantRepository, PostgresTenantRepository},
};
use crate::common::{obter_pool_teste, criar_contexto_teste, configurar_tenant_transacao};

/// Helper para criar um vetor de embedding normalizado de 1536 dimensões.
fn criar_vetor_teste(primeira_val: f32, segunda_val: f32) -> Vec<f32> {
    let mut vec = vec![0.0f32; 1536];
    vec[0] = primeira_val;
    vec[1] = segunda_val;
    vec
}

#[tokio::test]
async fn test_treinamento_and_document_vector_search() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let tenant_repo = PostgresTenantRepository;
    let treinamento_repo = PostgresTreinamentoRepository;
    let documento_repo = PostgresDocumentoRepository;

    // 1. Setup Tenant
    let slug = format!("tenant-{}", Uuid::new_v4());
    let tenant = tenant_repo.criar(&mut tx, "Tenant RAG", &slug, None, None, None).await.unwrap();

    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    // 2. Criar Treinamento
    let treinamento = treinamento_repo.criar(
        &mut tx,
        &ctx,
        "faq",
        "financeiro",
        Some("FAQ do setor financeiro"),
    ).await.expect("Falha ao criar treinamento");

    assert_eq!(treinamento.tag, "faq");
    assert!(!treinamento.treinamento_finalizado);

    // 3. Cadastrar Documentos com Embeddings
    let emb_a = criar_vetor_teste(1.0, 0.0);
    let doc_a = documento_repo.criar(
        &mut tx,
        &ctx,
        treinamento.id,
        Some("Como pagar minha fatura?"),
        Some(emb_a),
        1,
        serde_json::json!({}),
    ).await.expect("Falha ao criar documento A");

    let emb_b = criar_vetor_teste(0.0, 1.0);
    let doc_b = documento_repo.criar(
        &mut tx,
        &ctx,
        treinamento.id,
        Some("Horário de expediente bancário"),
        Some(emb_b),
        2,
        serde_json::json!({}),
    ).await.unwrap();

    // 4. Testar Busca Semântica antes de marcar como finalizado (não deve retornar nada)
    let query_vector = criar_vetor_teste(1.0, 0.0);
    let docs_antes = documento_repo.buscar_documentos_similares(
        &mut tx,
        tenant.id,
        query_vector.clone(),
        5,
        1.5,
    ).await.unwrap();
    assert!(docs_antes.is_empty(), "Busca retornou documentos de treinamento não finalizado!");

    // 5. Finalizar treinamento
    treinamento_repo.marcar_finalizado(&mut tx, &ctx, treinamento.id).await.unwrap();

    // Listar pendentes de vetorização
    let pendentes = treinamento_repo.listar_pendentes_vetorizacao(&mut tx, &ctx).await.unwrap();
    assert_eq!(pendentes.len(), 1);
    assert_eq!(pendentes[0].id, treinamento.id);

    // Marcar como vetorizado
    treinamento_repo.marcar_vetorizado(&mut tx, &ctx, treinamento.id).await.unwrap();

    // 6. Testar Busca Vetorial por Distância de Cosseno
    let docs_depois = documento_repo.buscar_documentos_similares(
        &mut tx,
        tenant.id,
        query_vector.clone(),
        5,
        1.5,
    ).await.unwrap();

    assert_eq!(docs_depois.len(), 2);
    assert_eq!(docs_depois[0].0.id, doc_a.id);
    assert!(docs_depois[0].1 < 0.01, "Distância do documento A deve ser próxima de 0");

    assert_eq!(docs_depois[1].0.id, doc_b.id);
    assert!((docs_depois[1].1 - 1.0).abs() < 0.01, "Distância do documento B deve ser próxima de 1");

    // 7. Filtrar por threshold de distância (excluir o Doc B que tem distância 1.0)
    let docs_filtrados = documento_repo.buscar_documentos_similares(
        &mut tx,
        tenant.id,
        query_vector.clone(),
        5,
        0.5, // threshold rígido
    ).await.unwrap();
    assert_eq!(docs_filtrados.len(), 1);
    assert_eq!(docs_filtrados[0].0.id, doc_a.id);

    tx.rollback().await.unwrap();
}

#[tokio::test]
async fn test_query_compose_vector_search() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let tenant_repo = PostgresTenantRepository;
    let query_repo = PostgresQueryComposeRepository;

    // Setup Tenant
    let slug = format!("tenant-{}", Uuid::new_v4());
    let tenant = tenant_repo.criar(&mut tx, "Tenant QueryCompose", &slug, None, None, None).await.unwrap();

    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    let text = to_embedding_text("saudacao", "Responder bom dia", "Bom dia!");
    assert!(text.contains("saudacao"));
    assert!(text.contains("Bom dia!"));

    // 1. Criar QueryCompose com embedding
    let emb_a = criar_vetor_teste(1.0, 0.0);
    let qc = query_repo.criar(
        &mut tx,
        &ctx,
        "saudacao",
        "padrao",
        "Responder bom dia",
        "Bom dia!",
        "Dizer Olá, sou o Bot",
        Some(emb_a),
    ).await.expect("Falha ao criar QueryCompose");

    assert_eq!(qc.tag, "saudacao");

    // Listar
    let lista = query_repo.listar_por_tenant(&mut tx, &ctx).await.unwrap();
    assert_eq!(lista.len(), 1);
    assert_eq!(lista[0].id, qc.id);

    // 2. Buscar comportamento similar
    let query_vector = criar_vetor_teste(1.0, 0.0);
    let comportamento = query_repo.buscar_comportamento_similar(
        &mut tx,
        tenant.id,
        query_vector,
        0.5,
    ).await.unwrap();

    assert_eq!(comportamento.as_deref(), Some("Dizer Olá, sou o Bot"));

    tx.rollback().await.unwrap();
}

#[tokio::test]
async fn test_rag_rls_isolation() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let tenant_repo = PostgresTenantRepository;
    let treinamento_repo = PostgresTreinamentoRepository;
    let documento_repo = PostgresDocumentoRepository;

    // Setup Tenants
    let slug_a = format!("tenant-{}", Uuid::new_v4());
    let tenant_a = tenant_repo.criar(&mut tx, "Tenant A", &slug_a, None, None, None).await.unwrap();
    
    let slug_b = format!("tenant-{}", Uuid::new_v4());
    let tenant_b = tenant_repo.criar(&mut tx, "Tenant B", &slug_b, None, None, None).await.unwrap();

    // 1. Cadastrar documento no Tenant A
    configurar_tenant_transacao(&mut tx, tenant_a.id).await;
    let ctx_a = criar_contexto_teste(tenant_a.id);
    let treinamento_a = treinamento_repo.criar(&mut tx, &ctx_a, "faq", "geral", None).await.unwrap();
    treinamento_repo.marcar_finalizado(&mut tx, &ctx_a, treinamento_a.id).await.unwrap();

    let emb = criar_vetor_teste(1.0, 0.0);
    let _doc_a = documento_repo.criar(
        &mut tx,
        &ctx_a,
        treinamento_a.id,
        Some("Secreto do Tenant A"),
        Some(emb),
        1,
        serde_json::json!({}),
    ).await.unwrap();

    // 2. Mudar para Tenant B e tentar buscar via vetor
    configurar_tenant_transacao(&mut tx, tenant_b.id).await;
    let query_vector = criar_vetor_teste(1.0, 0.0);

    let docs_busca = documento_repo.buscar_documentos_similares(
        &mut tx,
        tenant_b.id,
        query_vector,
        5,
        1.5,
    ).await.unwrap();

    assert!(docs_busca.is_empty(), "Tenant B acessou documento semântico do Tenant A!");

    tx.rollback().await.unwrap();
}
