use crate::common::{
    configurar_tenant_transacao, criar_contexto_teste, criar_tenant_para_teste, obter_pool_teste,
};
use infrastructure_postgres::operacional::{
    app_instances::{AppInstanceRepository, PostgresAppInstanceRepository},
    atendentes::{AtendenteRepository, PostgresAtendenteRepository},
    departamentos::{DepartamentoRepository, PostgresDepartamentoRepository},
    fluxos::{
        EtapaFluxoRepository, FluxoAtendimentoRepository, PostgresEtapaFluxoRepository,
        PostgresFluxoAtendimentoRepository,
    },
};
use uuid::Uuid;

#[tokio::test]
async fn test_departamento_and_fluxo_crud() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let depto_repo = PostgresDepartamentoRepository;
    let fluxo_repo = PostgresFluxoAtendimentoRepository;
    let etapa_repo = PostgresEtapaFluxoRepository;

    // 1. Setup Tenant
    let tenant = criar_tenant_para_teste(&mut tx, "Tenant Operacional").await;

    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    // 2. Criar Departamento
    let depto = depto_repo
        .criar(
            &mut tx,
            &ctx,
            "Suporte Técnico",
            Some("Departamento de Suporte"),
        )
        .await
        .expect("Falha ao criar departamento");
    assert_eq!(depto.nome, "Suporte Técnico");

    let depto_busca = depto_repo
        .buscar_por_id(&mut tx, &ctx, depto.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(depto_busca.nome, "Suporte Técnico");

    // 3. Criar Fluxo de Atendimento
    let fluxo = fluxo_repo
        .criar(&mut tx, &ctx, depto.id, "Fluxo Nivel 1")
        .await
        .expect("Falha ao criar fluxo");
    assert_eq!(fluxo.nome, "Fluxo Nivel 1");

    let fluxos_busca = fluxo_repo
        .buscar_por_departamento(&mut tx, &ctx, depto.id)
        .await
        .unwrap();
    assert_eq!(fluxos_busca.len(), 1);
    assert_eq!(fluxos_busca[0].id, fluxo.id);

    // 4. Criar Etapas do Fluxo
    let etapa_fila = etapa_repo
        .criar(
            &mut tx,
            &ctx,
            fluxo.id,
            "Fila de Espera",
            1,
            "fila",
            Some("#FFA500"),
        )
        .await
        .expect("Falha ao criar etapa fila");
    assert_eq!(etapa_fila.nome, "Fila de Espera");
    assert_eq!(etapa_fila.tipo_etapa, "fila");

    let _etapa_trab = etapa_repo
        .criar(&mut tx, &ctx, fluxo.id, "Em Andamento", 2, "trabalho", None)
        .await
        .unwrap();

    // 5. Testar get_etapa_inicial
    let etapa_inicial = etapa_repo
        .get_etapa_inicial(&mut tx, &ctx, fluxo.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(etapa_inicial.id, etapa_fila.id);

    // Listar por fluxo
    let etapas = etapa_repo
        .listar_por_fluxo(&mut tx, &ctx, fluxo.id)
        .await
        .unwrap();
    assert_eq!(etapas.len(), 2);
    assert_eq!(etapas[0].ordem, 1);
    assert_eq!(etapas[1].ordem, 2);

    tx.rollback().await.unwrap();
}

#[tokio::test]
async fn test_atendente_and_round_robin() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let depto_repo = PostgresDepartamentoRepository;
    let fluxo_repo = PostgresFluxoAtendimentoRepository;
    let atendente_repo = PostgresAtendenteRepository;

    // Setup Tenant, Depto e Fluxo
    let tenant = criar_tenant_para_teste(&mut tx, "Tenant Agents").await;

    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    let depto = depto_repo
        .criar(&mut tx, &ctx, "Dept 1", None)
        .await
        .unwrap();
    let fluxo = fluxo_repo
        .criar(&mut tx, &ctx, depto.id, "Fluxo 1")
        .await
        .unwrap();

    // 1. Criar Atendentes
    let atendente_a = atendente_repo
        .criar(
            &mut tx,
            &ctx,
            "Agente A",
            "agente.a@teste.com",
            "Suporte",
            fluxo.id,
            Some(depto.id),
        )
        .await
        .expect("Falha ao criar atendente A");

    let atendente_b = atendente_repo
        .criar(
            &mut tx,
            &ctx,
            "Agente B",
            "agente.b@teste.com",
            "Suporte",
            fluxo.id,
            Some(depto.id),
        )
        .await
        .expect("Falha ao criar atendente B");

    atendente_repo
        .atualizar_disponibilidade(&mut tx, &ctx, atendente_a.id, true)
        .await
        .unwrap();
    atendente_repo
        .atualizar_disponibilidade(&mut tx, &ctx, atendente_b.id, true)
        .await
        .unwrap();

    // 2. Testar buscar_disponivel_round_robin
    let disp_1 = atendente_repo
        .buscar_disponivel_round_robin(&mut tx, &ctx, Some(depto.id))
        .await
        .unwrap()
        .unwrap();

    atendente_repo
        .atualizar_ultima_atribuicao(&mut tx, &ctx, disp_1.id)
        .await
        .unwrap();

    let disp_2 = atendente_repo
        .buscar_disponivel_round_robin(&mut tx, &ctx, Some(depto.id))
        .await
        .unwrap()
        .unwrap();
    assert_ne!(
        disp_1.id, disp_2.id,
        "O algoritmo Round-Robin deve rotacionar os atendentes!"
    );

    atendente_repo
        .atualizar_ultima_atribuicao(&mut tx, &ctx, disp_2.id)
        .await
        .unwrap();

    atendente_repo
        .atualizar_disponibilidade(&mut tx, &ctx, disp_1.id, false)
        .await
        .unwrap();
    let disp_3 = atendente_repo
        .buscar_disponivel_round_robin(&mut tx, &ctx, Some(depto.id))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        disp_3.id, disp_2.id,
        "Atendente indisponível não deve ser selecionado"
    );

    tx.rollback().await.unwrap();
}

#[tokio::test]
async fn test_app_instance_crud() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let depto_repo = PostgresDepartamentoRepository;
    let app_repo = PostgresAppInstanceRepository;

    // Setup Tenant
    let tenant = criar_tenant_para_teste(&mut tx, "Tenant Instances").await;

    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    let depto = depto_repo
        .criar(&mut tx, &ctx, "Dept 2", None)
        .await
        .unwrap();

    // 1. Criar AppInstance
    let key = format!("api-key-{}", Uuid::new_v4());
    let inst = app_repo
        .criar(
            &mut tx,
            &ctx,
            &key,
            "whatsapp",
            Some("Instância WhatsApp Principal"),
            Some(depto.id),
        )
        .await
        .expect("Falha ao criar AppInstance");

    assert_eq!(inst.api_key, key);
    assert_eq!(inst.channel, "whatsapp");
    assert!(inst.active);

    // 2. Buscar por API Key
    let inst_busca = app_repo
        .buscar_por_api_key(&mut tx, &ctx, &key)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(inst_busca.id, inst.id);

    // 3. Listar ativas
    let lista = app_repo.listar_ativas(&mut tx, &ctx).await.unwrap();
    assert_eq!(lista.len(), 1);
    assert_eq!(lista[0].id, inst.id);

    tx.rollback().await.unwrap();
}

#[tokio::test]
async fn test_operacional_rls_isolation() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let depto_repo = PostgresDepartamentoRepository;
    let app_repo = PostgresAppInstanceRepository;

    // Setup Tenant A
    let tenant_a = criar_tenant_para_teste(&mut tx, "Tenant A Op").await;

    configurar_tenant_transacao(&mut tx, tenant_a.id).await;
    let ctx_a = criar_contexto_teste(tenant_a.id);
    let depto_a = depto_repo
        .criar(&mut tx, &ctx_a, "Acesso Restrito", None)
        .await
        .unwrap();

    let key = "chave-privada-tenant-a-op";
    let _inst_a = app_repo
        .criar(&mut tx, &ctx_a, key, "whatsapp", None, Some(depto_a.id))
        .await
        .unwrap();

    // Criar Tenant B e tentar acessar registros
    let tenant_b = criar_tenant_para_teste(&mut tx, "Tenant B Op").await;

    configurar_tenant_transacao(&mut tx, tenant_b.id).await;
    let ctx_b = criar_contexto_teste(tenant_b.id);

    let busca_depto = depto_repo
        .buscar_por_id(&mut tx, &ctx_b, depto_a.id)
        .await
        .unwrap();
    assert!(
        busca_depto.is_none(),
        "Tenant B acessou departamento do Tenant A!"
    );

    let busca_inst = app_repo
        .buscar_por_api_key(&mut tx, &ctx_b, key)
        .await
        .unwrap();
    assert!(
        busca_inst.is_none(),
        "Tenant B acessou AppInstance do Tenant A por API key!"
    );

    tx.rollback().await.unwrap();
}
