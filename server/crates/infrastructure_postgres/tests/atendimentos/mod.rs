use uuid::Uuid;
use sqlx::Transaction;
use infrastructure_postgres::{
    atendimentos::{
        atendimentos::{AtendimentoRepository, PostgresAtendimentoRepository, Atendimento},
        mensagens::{MensagemRepository, PostgresMensagemRepository, BoxMensagem = Mensagem}, // reexportando ou usando o nome original
        movimentos::{MovimentoFluxoRepository, PostgresMovimentoFluxoRepository, MovimentoFluxo},
        campos::{CampoPersonalizadoRepository, PostgresCampoPersonalizadoRepository, ValorCampoRepository, PostgresValorCampoRepository, CampoPersonalizado, ValorCampoAtendimento},
        etiquetas::{EtiquetaRepository, PostgresEtiquetaRepository, NotaRepository, PostgresNotaRepository, Etiqueta, Nota},
    },
    clientes::contatos::{ContatoRepository, PostgresContatoRepository},
    operacional::{
        departamentos::{DepartamentoRepository, PostgresDepartamentoRepository},
        fluxos::{FluxoAtendimentoRepository, PostgresFluxoAtendimentoRepository, EtapaFluxoRepository, PostgresEtapaFluxoRepository},
    },
    tenants::tenants::{TenantRepository, PostgresTenantRepository},
};
use crate::common::{obter_pool_teste, criar_contexto_teste, configurar_tenant_transacao};

// Alias manual para evitar colisão caso o compilador precise de clareza
type Msg = infrastructure_postgres::atendimentos::mensagens::Mensagem;

#[tokio::test]
async fn test_atendimento_workflow_and_messages() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let tenant_repo = PostgresTenantRepository;
    let depto_repo = PostgresDepartamentoRepository;
    let fluxo_repo = PostgresFluxoAtendimentoRepository;
    let etapa_repo = PostgresEtapaFluxoRepository;
    let contato_repo = PostgresContatoRepository;
    
    let atendimento_repo = PostgresAtendimentoRepository;
    let mensagem_repo = PostgresMensagemRepository;
    let movimento_repo = PostgresMovimentoFluxoRepository;

    // 1. Setup Tenant e Cadastros Iniciais
    let slug = format!("tenant-{}", Uuid::new_v4());
    let tenant = tenant_repo.criar(&mut tx, "Tenant Atendimentos", &slug, None, None, None).await.unwrap();

    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    let depto = depto_repo.criar(&mut tx, &ctx, "Suporte", "suporte", None).await.unwrap();
    let fluxo = fluxo_repo.criar(&mut tx, &ctx, depto.id, "Fluxo A").await.unwrap();
    let etapa_fila = etapa_repo.criar(&mut tx, &ctx, fluxo.id, "Fila", 1, "fila", None).await.unwrap();
    let etapa_trab = etapa_repo.criar(&mut tx, &ctx, fluxo.id, "Trab", 2, "trabalho", None).await.unwrap();
    let contato = contato_repo.salvar(&mut tx, &ctx, "5511999992222", Some("Cliente Fila"), None, None, None).await.unwrap();

    // 2. Criar Atendimento
    let atendimento = atendimento_repo.criar(
        &mut tx,
        &ctx,
        contato.id,
        Some(depto.id),
        Some(fluxo.id),
        Some(etapa_fila.id),
    ).await.expect("Falha ao criar atendimento");

    assert_eq!(atendimento.contato_id, contato.id);
    assert_eq!(atendimento.status, "fila");
    assert_eq!(atendimento.etapa_atual_id, Some(etapa_fila.id));

    // 3. Criar Mensagens e Citadas
    let msg1 = mensagem_repo.criar(
        &mut tx,
        &ctx,
        atendimento.id,
        "chat",
        "Olá, preciso de suporte",
        "contato",
        Some("msg-id-1"),
        None,
    ).await.expect("Falha ao criar mensagem 1");
    assert_eq!(msg1.conteudo, "Olá, preciso de suporte");

    // Resposta citando a primeira mensagem
    let msg2 = mensagem_repo.criar(
        &mut tx,
        &ctx,
        atendimento.id,
        "chat",
        "Pois não, em que posso ajudar?",
        "atendente",
        Some("msg-id-2"),
        Some(msg1.id),
    ).await.unwrap();
    assert_eq!(msg2.mensagem_citada_id, Some(msg1.id));

    // Registrar resposta de bot
    mensagem_repo.registrar_resposta_bot(&mut tx, &ctx, msg1.id, "Resposta IA automática", Some(0.95)).await.unwrap();
    
    // Marcar como lidas
    mensagem_repo.marcar_como_lida(&mut tx, &ctx, atendimento.id).await.unwrap();

    // Listar mensagens
    let msgs = mensagem_repo.listar_por_atendimento(&mut tx, &ctx, atendimento.id, 10, 0).await.unwrap();
    assert_eq!(msgs.len(), 2);
    assert_eq!(msgs[0].id, msg1.id);
    assert!(msgs[0].respondida);
    assert_eq!(msgs[0].resposta_bot.as_deref(), Some("Resposta IA automática"));

    // 4. Testar Movimentação de Etapa (MovimentoFluxo)
    let mov1 = movimento_repo.criar(
        &mut tx,
        &ctx,
        atendimento.id,
        Some(etapa_fila.id),
        etapa_trab.id,
        None,
        Some("Atendimento assumido pelo atendente"),
        false,
    ).await.expect("Falha ao criar movimento");

    assert_eq!(mov1.etapa_origem_id, Some(etapa_fila.id));
    assert_eq!(mov1.etapa_destino_id, etapa_trab.id);

    // Listar movimentos
    let movimentos = movimento_repo.listar_por_atendimento(&mut tx, &ctx, atendimento.id).await.unwrap();
    assert_eq!(movimentos.len(), 1);
    assert_eq!(movimentos[0].id, mov1.id);

    // Atualizar status e etapa no atendimento
    atendimento_repo.atualizar_etapa(&mut tx, &ctx, atendimento.id, etapa_trab.id, Some(10)).await.unwrap();
    atendimento_repo.atualizar_status(&mut tx, &ctx, atendimento.id, "em_atendimento").await.unwrap();

    let atendimento_pos = atendimento_repo.buscar_por_id(&mut tx, &ctx, atendimento.id).await.unwrap().unwrap();
    assert_eq!(atendimento_pos.status, "em_atendimento");
    assert_eq!(atendimento_pos.etapa_atual_id, Some(etapa_trab.id));
    assert_eq!(atendimento_pos.atendente_humano_id, Some(10));

    tx.rollback().await.unwrap();
}

#[tokio::test]
async fn test_campos_personalizados_etiquetas_e_notas() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let tenant_repo = PostgresTenantRepository;
    let depto_repo = PostgresDepartamentoRepository;
    let contato_repo = PostgresContatoRepository;
    let atendimento_repo = PostgresAtendimentoRepository;

    let campo_repo = PostgresCampoPersonalizadoRepository;
    let valor_repo = PostgresValorCampoRepository;
    let etiqueta_repo = PostgresEtiquetaRepository;
    let nota_repo = PostgresNotaRepository;

    // Setup Tenant, Contato e Atendimento
    let slug = format!("tenant-{}", Uuid::new_v4());
    let tenant = tenant_repo.criar(&mut tx, "Tenant Campos Etiquetas", &slug, None, None, None).await.unwrap();

    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    let depto = depto_repo.criar(&mut tx, &ctx, "Suporte", "suporte", None).await.unwrap();
    let contato = contato_repo.salvar(&mut tx, &ctx, "5511999993333", Some("Cliente Campos"), None, None, None).await.unwrap();
    let atendimento = atendimento_repo.criar(&mut tx, &ctx, contato.id, Some(depto.id), None, None).await.unwrap();

    // 1. Criar Campo Personalizado
    let campo = campo_repo.criar(
        &mut tx,
        &ctx,
        "cpf_cliente",
        "CPF do Cliente",
        "GLOBAL",
        "texto",
        None,
    ).await.expect("Falha ao criar campo personalizado");
    assert_eq!(campo.slug, "cpf_cliente");

    let campos = campo_repo.listar_por_escopo(&mut tx, &ctx, "GLOBAL", None).await.unwrap();
    assert!(!campos.is_empty());
    assert_eq!(campos[0].id, campo.id);

    // 2. Upsert Valor de Campo
    let valor_json = serde_json::json!("123.456.789-00");
    let valor = valor_repo.upsert(
        &mut tx,
        &ctx,
        atendimento.id,
        campo.id,
        valor_json.clone(),
        "bot",
        Some(0.99),
    ).await.expect("Falha ao salvar valor do campo");

    assert_eq!(valor.valor, valor_json);
    assert_eq!(valor.origem, "bot");

    // Listar valores por atendimento
    let valores = valor_repo.listar_por_atendimento(&mut tx, &ctx, atendimento.id).await.unwrap();
    assert_eq!(valores.len(), 1);
    assert_eq!(valores[0].campo_id, campo.id);
    assert_eq!(valores[0].valor, valor_json);

    // 3. Criar e Aplicar Etiquetas
    let etiqueta = etiqueta_repo.criar(&mut tx, &ctx, "Urgente", Some("#FF0000")).await.expect("Falha ao criar etiqueta");
    assert_eq!(etiqueta.nome, "Urgente");

    // Aplicar etiqueta
    etiqueta_repo.aplicar(&mut tx, &ctx, atendimento.id, etiqueta.id).await.expect("Falha ao aplicar etiqueta");

    let etiquetas_ativas = etiqueta_repo.listar_ativas(&mut tx, &ctx).await.unwrap();
    assert_eq!(etiquetas_ativas.len(), 1);
    assert_eq!(etiquetas_ativas[0].id, etiqueta.id);

    // Remover etiqueta
    etiqueta_repo.remover(&mut tx, &ctx, atendimento.id, etiqueta.id).await.expect("Falha ao remover etiqueta");

    // 4. Criar e Listar Notas
    let nota = nota_repo.criar(
        &mut tx,
        &ctx,
        atendimento.id,
        "Nota interna sobre o caso",
        Some(10),
    ).await.expect("Falha ao criar nota");
    assert_eq!(nota.texto, "Nota interna sobre o caso");

    let notas = nota_repo.listar_por_atendimento(&mut tx, &ctx, atendimento.id).await.unwrap();
    assert_eq!(notas.len(), 1);
    assert_eq!(notas[0].id, nota.id);

    tx.rollback().await.unwrap();
}
