use crate::common::{
    configurar_tenant_transacao, criar_contexto_teste, criar_tenant_para_teste, obter_pool_teste,
};
use infrastructure_postgres::{
    atendimentos::{
        atendimentos::{AtendimentoRepository, PostgresAtendimentoRepository},
        campos::{
            CampoPersonalizadoRepository, PostgresCampoPersonalizadoRepository,
            PostgresValorCampoRepository, ValorCampoRepository,
        },
        etiquetas::{
            EtiquetaRepository, NotaRepository, PostgresEtiquetaRepository, PostgresNotaRepository,
        },
        mensagens::{MensagemRepository, NovaMensagem, PostgresMensagemRepository},
        movimentos::{MovimentoFluxoRepository, PostgresMovimentoFluxoRepository},
    },
    clientes::contatos::{ContatoRepository, PostgresContatoRepository},
    operacional::{
        departamentos::{DepartamentoRepository, PostgresDepartamentoRepository},
        fluxos::{
            EtapaFluxoRepository, FluxoAtendimentoRepository, PostgresEtapaFluxoRepository,
            PostgresFluxoAtendimentoRepository,
        },
    },
    RequestContext,
};

#[tokio::test]
async fn test_atendimento_workflow_and_messages() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let depto_repo = PostgresDepartamentoRepository;
    let fluxo_repo = PostgresFluxoAtendimentoRepository;
    let etapa_repo = PostgresEtapaFluxoRepository;
    let contato_repo = PostgresContatoRepository;
    let atendimento_repo = PostgresAtendimentoRepository;
    let mensagem_repo = PostgresMensagemRepository;
    let movimento_repo = PostgresMovimentoFluxoRepository;

    // 1. Setup Tenant e Cadastros Iniciais
    let tenant = criar_tenant_para_teste(&mut tx, "Tenant Atendimentos").await;

    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    let depto = depto_repo
        .criar(&mut tx, &ctx, "Suporte", None)
        .await
        .unwrap();
    let fluxo = fluxo_repo
        .criar(&mut tx, &ctx, depto.id, "Fluxo A", None)
        .await
        .unwrap();
    let etapa_fila = etapa_repo
        .criar(&mut tx, &ctx, fluxo.id, "Fila", 1, "fila", None)
        .await
        .unwrap();
    let etapa_trab = etapa_repo
        .criar(&mut tx, &ctx, fluxo.id, "Trab", 2, "trabalho", None)
        .await
        .unwrap();
    let contato = contato_repo
        .salvar(&mut tx, &ctx, "5511999992222", Some("Cliente Fila"))
        .await
        .unwrap();

    // 2. Criar Atendimento
    let atendimento = atendimento_repo
        .criar(
            &mut tx,
            &ctx,
            contato.id,
            Some(depto.id),
            Some(fluxo.id),
            Some(etapa_fila.id),
        )
        .await
        .expect("Falha ao criar atendimento");

    assert_eq!(atendimento.contato_id, contato.id);
    assert_eq!(atendimento.status, "fila");
    assert_eq!(atendimento.etapa_atual_id, Some(etapa_fila.id));

    // 3. Criar Mensagens e Citadas
    let msg1 = mensagem_repo
        .criar(
            &mut tx,
            &ctx,
            NovaMensagem {
                message_id_whatsapp: Some("msg-id-1"),
                ..NovaMensagem::nova(atendimento.id, "chat", "Olá, preciso de suporte", "contato")
            },
        )
        .await
        .expect("Falha ao criar mensagem 1");
    assert_eq!(msg1.conteudo, "Olá, preciso de suporte");
    // Sem `ja_entregue`, a mensagem nasce pendente (default do schema).
    assert_eq!(msg1.status_envio, "pending");

    // O stanzaId é a chave de idempotência da ingestão: a busca por ele tem de
    // devolver exatamente a mensagem gravada.
    let achada = mensagem_repo
        .buscar_por_whatsapp_id(&mut tx, &ctx, "msg-id-1")
        .await
        .unwrap()
        .expect("deveria achar a mensagem pelo stanzaId");
    assert_eq!(achada.id, msg1.id);
    assert!(mensagem_repo
        .buscar_por_whatsapp_id(&mut tx, &ctx, "stanza-que-nao-existe")
        .await
        .unwrap()
        .is_none());

    // Resposta citando a primeira mensagem
    let msg2 = mensagem_repo
        .criar(
            &mut tx,
            &ctx,
            NovaMensagem {
                message_id_whatsapp: Some("msg-id-2"),
                mensagem_citada_id: Some(msg1.id),
                // Mensagem que o atendente digitou no celular (fromMe): já saiu
                // pelo WhatsApp, então NÃO pode nascer pendente de envio.
                ja_entregue: true,
                ..NovaMensagem::nova(
                    atendimento.id,
                    "chat",
                    "Pois não, em que posso ajudar?",
                    "atendente",
                )
            },
        )
        .await
        .unwrap();
    assert_eq!(msg2.mensagem_citada_id, Some(msg1.id));
    // Mensagem de humano NAO e marcada como gerada por IA.
    assert!(!msg2.gerado_por_ia);
    assert_eq!(msg2.status_envio, "sent");

    // N6.2: mensagem do assistente virtual e persistida no thread (para o atendente
    // ver o que o bot respondeu e para o proprio bot ter memoria das suas falas) e
    // o remetente "bot" deriva `gerado_por_ia = true` no INSERT.
    let msg_bot = mensagem_repo
        .criar(
            &mut tx,
            &ctx,
            NovaMensagem::nova(
                atendimento.id,
                "texto",
                "Ola! Sou o assistente virtual.",
                infrastructure_postgres::atendimentos::mensagens::REMETENTE_BOT,
            ),
        )
        .await
        .unwrap();
    assert!(msg_bot.gerado_por_ia);

    // Registrar resposta de bot
    mensagem_repo
        .registrar_resposta_bot(&mut tx, &ctx, msg1.id, "Resposta IA automática", Some(0.95))
        .await
        .unwrap();

    // Marcar como lidas
    mensagem_repo
        .marcar_como_lida(&mut tx, &ctx, atendimento.id)
        .await
        .unwrap();

    // Listar mensagens
    let msgs = mensagem_repo
        .listar_por_atendimento(&mut tx, &ctx, atendimento.id, 10, 0)
        .await
        .unwrap();
    assert_eq!(msgs.len(), 3); // contato + atendente + bot
    assert_eq!(msgs[0].id, msg1.id);
    assert!(msgs[0].respondida);
    assert_eq!(
        msgs[0].resposta_bot.as_deref(),
        Some("Resposta IA automática")
    );

    // 4. Testar Movimentação de Etapa
    let mov1 = movimento_repo
        .criar(
            &mut tx,
            &ctx,
            atendimento.id,
            Some(etapa_fila.id),
            etapa_trab.id,
            None,
            Some("Atendimento assumido pelo atendente"),
            false,
        )
        .await
        .expect("Falha ao criar movimento");

    assert_eq!(mov1.etapa_origem_id, Some(etapa_fila.id));
    assert_eq!(mov1.etapa_destino_id, etapa_trab.id);

    // Listar movimentos
    let movimentos = movimento_repo
        .listar_por_atendimento(&mut tx, &ctx, atendimento.id)
        .await
        .unwrap();
    assert_eq!(movimentos.len(), 1);
    assert_eq!(movimentos[0].id, mov1.id);

    // Atualizar status e etapa
    atendimento_repo
        .atualizar_etapa(&mut tx, &ctx, atendimento.id, etapa_trab.id, None)
        .await
        .unwrap();
    atendimento_repo
        .atualizar_status(&mut tx, &ctx, atendimento.id, "em_atendimento")
        .await
        .unwrap();

    let atendimento_pos = atendimento_repo
        .buscar_por_id(&mut tx, &ctx, atendimento.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(atendimento_pos.status, "em_atendimento");
    assert_eq!(atendimento_pos.etapa_atual_id, Some(etapa_trab.id));
    assert!(atendimento_pos.atendente_humano_id.is_none());

    tx.rollback().await.unwrap();
}

#[tokio::test]
async fn test_campos_personalizados_etiquetas_e_notas() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let depto_repo = PostgresDepartamentoRepository;
    let contato_repo = PostgresContatoRepository;
    let atendimento_repo = PostgresAtendimentoRepository;
    let campo_repo = PostgresCampoPersonalizadoRepository;
    let valor_repo = PostgresValorCampoRepository;
    let etiqueta_repo = PostgresEtiquetaRepository;
    let nota_repo = PostgresNotaRepository;

    // Setup Tenant, Contato e Atendimento
    let tenant = criar_tenant_para_teste(&mut tx, "Tenant Campos Etiquetas").await;

    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    let depto = depto_repo
        .criar(&mut tx, &ctx, "Suporte", None)
        .await
        .unwrap();
    let contato = contato_repo
        .salvar(&mut tx, &ctx, "5511999993333", Some("Cliente Campos"))
        .await
        .unwrap();
    let atendimento = atendimento_repo
        .criar(&mut tx, &ctx, contato.id, Some(depto.id), None, None)
        .await
        .unwrap();

    // 1. Criar Campo Personalizado
    let campo = campo_repo
        .criar(
            &mut tx,
            &ctx,
            "cpf_cliente",
            "CPF do Cliente",
            "GLOBAL",
            "texto",
            None,
        )
        .await
        .expect("Falha ao criar campo personalizado");
    assert_eq!(campo.slug, "cpf_cliente");

    let campos = campo_repo
        .listar_por_escopo(&mut tx, &ctx, "GLOBAL", None)
        .await
        .unwrap();
    assert!(!campos.is_empty());
    assert_eq!(campos[0].id, campo.id);

    // 2. Upsert Valor de Campo
    let valor_json = serde_json::json!("123.456.789-00");
    let valor = valor_repo
        .upsert(
            &mut tx,
            &ctx,
            atendimento.id,
            campo.id,
            valor_json.clone(),
            "bot",
            Some(0.99),
        )
        .await
        .expect("Falha ao salvar valor do campo");

    assert_eq!(valor.valor, valor_json);
    assert_eq!(valor.origem, "bot");

    // Listar valores por atendimento
    let valores = valor_repo
        .listar_por_atendimento(&mut tx, &ctx, atendimento.id)
        .await
        .unwrap();
    assert_eq!(valores.len(), 1);
    assert_eq!(valores[0].campo_id, campo.id);
    assert_eq!(valores[0].valor, valor_json);

    // 3. Criar e Aplicar Etiquetas
    let etiqueta = etiqueta_repo
        .criar(&mut tx, &ctx, "Urgente", Some("#FF0000"))
        .await
        .expect("Falha ao criar etiqueta");
    assert_eq!(etiqueta.nome, "Urgente");

    etiqueta_repo
        .aplicar(&mut tx, &ctx, atendimento.id, etiqueta.id)
        .await
        .expect("Falha ao aplicar etiqueta");

    let etiquetas_ativas = etiqueta_repo.listar_ativas(&mut tx, &ctx).await.unwrap();
    assert_eq!(etiquetas_ativas.len(), 1);
    assert_eq!(etiquetas_ativas[0].id, etiqueta.id);

    etiqueta_repo
        .remover(&mut tx, &ctx, atendimento.id, etiqueta.id)
        .await
        .expect("Falha ao remover etiqueta");

    // 4. Criar e Listar Notas
    let nota = nota_repo
        .criar(
            &mut tx,
            &ctx,
            atendimento.id,
            "Nota interna sobre o caso",
            None,
        )
        .await
        .expect("Falha ao criar nota");
    assert_eq!(nota.texto, "Nota interna sobre o caso");

    let notas = nota_repo
        .listar_por_atendimento(&mut tx, &ctx, atendimento.id)
        .await
        .unwrap();
    assert_eq!(notas.len(), 1);
    assert_eq!(notas[0].id, nota.id);

    tx.rollback().await.unwrap();
}

/// Prova o isolamento RLS do domínio de atendimentos: um atendimento criado no
/// Tenant A não pode ser lido (por id) nem listado (por status) sob o Tenant B.
/// Executa com a role de runtime (NOBYPASSRLS), então a policy fail-closed é exercida
/// de verdade — sem o filtro `tenant_id` explícito + RLS, Tenant B veria os dados.
#[tokio::test]
async fn test_atendimentos_rls_isolation() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let contato_repo = PostgresContatoRepository;
    let atendimento_repo = PostgresAtendimentoRepository;

    // 1. Tenant A cria contato + atendimento
    let tenant_a = criar_tenant_para_teste(&mut tx, "Tenant A Atend").await;
    configurar_tenant_transacao(&mut tx, tenant_a.id).await;
    let ctx_a = criar_contexto_teste(tenant_a.id);

    let contato_a = contato_repo
        .salvar(&mut tx, &ctx_a, "5511900001111", Some("Contato A"))
        .await
        .unwrap();
    let atendimento_a = atendimento_repo
        .criar(&mut tx, &ctx_a, contato_a.id, None, None, None)
        .await
        .unwrap();

    // 2. Tenant B tenta acessar o atendimento do Tenant A
    let tenant_b = criar_tenant_para_teste(&mut tx, "Tenant B Atend").await;
    configurar_tenant_transacao(&mut tx, tenant_b.id).await;
    let ctx_b = criar_contexto_teste(tenant_b.id);

    let busca_b = atendimento_repo
        .buscar_por_id(&mut tx, &ctx_b, atendimento_a.id)
        .await
        .unwrap();
    assert!(
        busca_b.is_none(),
        "Tenant B acessou atendimento do Tenant A por id!"
    );

    let lista_b = atendimento_repo
        .listar_por_status(&mut tx, &ctx_b, "fila", None, 100)
        .await
        .unwrap();
    assert!(
        lista_b.iter().all(|a| a.id != atendimento_a.id),
        "Tenant B listou atendimento do Tenant A por status!"
    );

    tx.rollback().await.unwrap();
}

/// RBAC fino por fluxo (WS-5a): `listar_por_status` só devolve atendimentos já
/// roteados a um fluxo Kanban quando o `RequestContext` tem `flow_permission` para
/// aquele fluxo; atendimentos sem fluxo atribuído (pré-roteamento) continuam visíveis.
#[tokio::test]
async fn test_listar_por_status_filtra_por_flow_permission() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let depto_repo = PostgresDepartamentoRepository;
    let fluxo_repo = PostgresFluxoAtendimentoRepository;
    let contato_repo = PostgresContatoRepository;
    let atendimento_repo = PostgresAtendimentoRepository;

    let tenant = criar_tenant_para_teste(&mut tx, "Tenant Flow Permission").await;
    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx_admin = criar_contexto_teste(tenant.id);

    let depto = depto_repo
        .criar(&mut tx, &ctx_admin, "Suporte Fluxo", None)
        .await
        .unwrap();
    let fluxo_permitido = fluxo_repo
        .criar(&mut tx, &ctx_admin, depto.id, "Fluxo Permitido", None)
        .await
        .unwrap();
    let fluxo_barrado = fluxo_repo
        .criar(&mut tx, &ctx_admin, depto.id, "Fluxo Barrado", None)
        .await
        .unwrap();

    let contato = contato_repo
        .salvar(&mut tx, &ctx_admin, "5511900002222", Some("Contato Fluxo"))
        .await
        .unwrap();

    let atendimento_fluxo_1 = atendimento_repo
        .criar(
            &mut tx,
            &ctx_admin,
            contato.id,
            None,
            Some(fluxo_permitido.id),
            None,
        )
        .await
        .unwrap();
    let atendimento_fluxo_99 = atendimento_repo
        .criar(
            &mut tx,
            &ctx_admin,
            contato.id,
            None,
            Some(fluxo_barrado.id),
            None,
        )
        .await
        .unwrap();
    let atendimento_sem_fluxo = atendimento_repo
        .criar(&mut tx, &ctx_admin, contato.id, None, None, None)
        .await
        .unwrap();

    // Atendente com flow_permission só para o fluxo permitido (sem bypass de admin).
    let ctx_atendente = RequestContext {
        tenant_id: tenant.id,
        user_id: 2,
        user_scopes: vec!["atendimentos:read".into()],
        flow_permissions: vec![fluxo_permitido.id],
    };

    let lista = atendimento_repo
        .listar_por_status(&mut tx, &ctx_atendente, "fila", None, 100)
        .await
        .unwrap();
    let ids: Vec<i32> = lista.iter().map(|a| a.id).collect();

    assert!(
        ids.contains(&atendimento_fluxo_1.id),
        "fluxo permitido deveria aparecer"
    );
    assert!(
        !ids.contains(&atendimento_fluxo_99.id),
        "fluxo sem permissão não deveria aparecer"
    );
    assert!(
        ids.contains(&atendimento_sem_fluxo.id),
        "atendimento sem fluxo atribuído deveria continuar visível"
    );

    tx.rollback().await.unwrap();
}
