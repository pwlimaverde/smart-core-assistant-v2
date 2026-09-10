use crate::common::{
    configurar_tenant_transacao, criar_contexto_teste, criar_tenant_para_teste, obter_pool_teste,
};
use infrastructure_postgres::atendimentos::atendimentos::{
    AtendimentoRepository, PostgresAtendimentoRepository,
};
use infrastructure_postgres::clientes::contatos::{ContatoRepository, PostgresContatoRepository};
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
        .criar(&mut tx, &ctx, depto.id, "Fluxo Nivel 1", None)
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
        .criar(&mut tx, &ctx, depto.id, "Fluxo 1", None)
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
        .buscar_disponivel_round_robin(&mut tx, &ctx, Some(depto.id), None)
        .await
        .unwrap()
        .unwrap();

    atendente_repo
        .atualizar_ultima_atribuicao(&mut tx, &ctx, disp_1.id)
        .await
        .unwrap();

    let disp_2 = atendente_repo
        .buscar_disponivel_round_robin(&mut tx, &ctx, Some(depto.id), None)
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
        .buscar_disponivel_round_robin(&mut tx, &ctx, Some(depto.id), None)
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

/// D2 — o rodízio filtra por FLUXO, não só por departamento.
///
/// O atendente tem `fluxo_id` obrigatório e `departamento_id` opcional. A
/// transferência sabe para qual fluxo vai; escolher pelo departamento entregaria
/// a conversa a quem não trabalha naquele fluxo.
#[tokio::test]
async fn rodizio_respeita_o_fluxo_do_atendente() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let depto_repo = PostgresDepartamentoRepository;
    let fluxo_repo = PostgresFluxoAtendimentoRepository;
    let atendente_repo = PostgresAtendenteRepository;

    let tenant = criar_tenant_para_teste(&mut tx, "Tenant Rodizio Fluxo").await;
    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    let depto = depto_repo.criar(&mut tx, &ctx, "Dept", None).await.unwrap();
    let fluxo_vendas = fluxo_repo
        .criar(&mut tx, &ctx, depto.id, "Vendas", None)
        .await
        .unwrap();
    let fluxo_suporte = fluxo_repo
        .criar(&mut tx, &ctx, depto.id, "Suporte", None)
        .await
        .unwrap();

    // Os dois no MESMO departamento — só o fluxo os separa.
    let de_vendas = atendente_repo
        .criar(
            &mut tx,
            &ctx,
            "Vendedora",
            "vendas@teste.com",
            "Vendas",
            fluxo_vendas.id,
            Some(depto.id),
        )
        .await
        .unwrap();
    atendente_repo
        .criar(
            &mut tx,
            &ctx,
            "Suporte",
            "suporte@teste.com",
            "Suporte",
            fluxo_suporte.id,
            Some(depto.id),
        )
        .await
        .unwrap();

    let escolhido = atendente_repo
        .buscar_disponivel_round_robin(&mut tx, &ctx, None, Some(fluxo_vendas.id))
        .await
        .unwrap()
        .expect("havia alguém no fluxo de vendas");

    assert_eq!(
        escolhido.id, de_vendas.id,
        "o rodízio entregou a conversa a quem não trabalha neste fluxo"
    );

    tx.rollback().await.unwrap();
}

/// D2 — quem já está no teto não recebe mais.
///
/// `max_atendimentos_simultaneos` existe desde a migração 0005 e nunca foi
/// consultado por nada em produção.
#[tokio::test]
async fn rodizio_respeita_o_teto_de_atendimentos_simultaneos() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let depto_repo = PostgresDepartamentoRepository;
    let fluxo_repo = PostgresFluxoAtendimentoRepository;
    let atendente_repo = PostgresAtendenteRepository;
    let contato_repo = PostgresContatoRepository;
    let atendimento_repo = PostgresAtendimentoRepository;

    let tenant = criar_tenant_para_teste(&mut tx, "Tenant Rodizio Teto").await;
    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    let depto = depto_repo.criar(&mut tx, &ctx, "Dept", None).await.unwrap();
    let fluxo = fluxo_repo
        .criar(&mut tx, &ctx, depto.id, "Fluxo", None)
        .await
        .unwrap();

    let unico = atendente_repo
        .criar(
            &mut tx,
            &ctx,
            "Único",
            "unico@teste.com",
            "Suporte",
            fluxo.id,
            Some(depto.id),
        )
        .await
        .unwrap();

    // Teto 1, e uma conversa aberta já na conta.
    atendente_repo
        .atualizar(
            &mut tx,
            &ctx,
            unico.id,
            "Único",
            "Suporte",
            Some(depto.id),
            fluxo.id,
            true,
            true,
            1,
        )
        .await
        .unwrap();

    let contato = contato_repo
        .salvar(&mut tx, &ctx, "5511900000001", Some("Cliente"))
        .await
        .unwrap();
    let ocupando = atendimento_repo
        .criar(
            &mut tx,
            &ctx,
            contato.id,
            Some(depto.id),
            Some(fluxo.id),
            None,
        )
        .await
        .unwrap();
    assert!(
        atendimento_repo
            .atribuir_se_livre(&mut tx, &ctx, ocupando.id, unico.id)
            .await
            .unwrap(),
        "a conversa estava livre e deveria ter sido atribuída"
    );

    let escolhido = atendente_repo
        .buscar_disponivel_round_robin(&mut tx, &ctx, None, Some(fluxo.id))
        .await
        .unwrap();

    assert!(
        escolhido.is_none(),
        "atendente no teto foi escolhido de novo; o limite não vale nada"
    );

    tx.rollback().await.unwrap();
}

/// D2 — o rodízio nunca tira uma conversa de quem já a pegou.
#[tokio::test]
async fn atribuir_se_livre_nao_rouba_conversa_com_dono() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let depto_repo = PostgresDepartamentoRepository;
    let fluxo_repo = PostgresFluxoAtendimentoRepository;
    let atendente_repo = PostgresAtendenteRepository;
    let contato_repo = PostgresContatoRepository;
    let atendimento_repo = PostgresAtendimentoRepository;

    let tenant = criar_tenant_para_teste(&mut tx, "Tenant Nao Rouba").await;
    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    let depto = depto_repo.criar(&mut tx, &ctx, "Dept", None).await.unwrap();
    let fluxo = fluxo_repo
        .criar(&mut tx, &ctx, depto.id, "Fluxo", None)
        .await
        .unwrap();

    let primeiro = atendente_repo
        .criar(
            &mut tx,
            &ctx,
            "Primeiro",
            "primeiro@teste.com",
            "Suporte",
            fluxo.id,
            Some(depto.id),
        )
        .await
        .unwrap();
    let segundo = atendente_repo
        .criar(
            &mut tx,
            &ctx,
            "Segundo",
            "segundo@teste.com",
            "Suporte",
            fluxo.id,
            Some(depto.id),
        )
        .await
        .unwrap();

    let contato = contato_repo
        .salvar(&mut tx, &ctx, "5511900000002", Some("Cliente"))
        .await
        .unwrap();
    let atendimento = atendimento_repo
        .criar(
            &mut tx,
            &ctx,
            contato.id,
            Some(depto.id),
            Some(fluxo.id),
            None,
        )
        .await
        .unwrap();

    assert!(atendimento_repo
        .atribuir_se_livre(&mut tx, &ctx, atendimento.id, primeiro.id)
        .await
        .unwrap());

    assert!(
        !atendimento_repo
            .atribuir_se_livre(&mut tx, &ctx, atendimento.id, segundo.id)
            .await
            .unwrap(),
        "a segunda atribuição passou: alguém perderia a conversa que já estava atendendo"
    );

    let depois = atendimento_repo
        .buscar_por_id(&mut tx, &ctx, atendimento.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(depois.atendente_humano_id, Some(primeiro.id));

    tx.rollback().await.unwrap();
}
