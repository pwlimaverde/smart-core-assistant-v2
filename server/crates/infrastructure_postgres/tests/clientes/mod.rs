use crate::common::{
    configurar_tenant_transacao, criar_contexto_teste, criar_tenant_para_teste, obter_pool_teste,
};
use infrastructure_postgres::clientes::{
    clientes::{ClienteRepository, PostgresClienteRepository},
    contatos::{ContatoRepository, PostgresContatoRepository},
};

#[tokio::test]
async fn test_contato_crud_and_idempotence() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let contato_repo = PostgresContatoRepository;

    // Setup Tenant
    let tenant = criar_tenant_para_teste(&mut tx, "Tenant Contatos").await;

    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    // 1. Criar Contato
    let telefone = "5511999998888";
    let contato = contato_repo
        .salvar(&mut tx, &ctx, telefone, Some("João Silva"))
        .await
        .expect("Falha ao salvar contato");

    assert_eq!(contato.telefone.as_deref(), Some(telefone));
    assert_eq!(contato.nome_contato.as_deref(), Some("João Silva"));
    assert!(contato.ativo);

    // 2. Buscar por ID e Telefone
    let contato_por_id = contato_repo
        .buscar_por_id(&mut tx, &ctx, contato.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(contato_por_id.id, contato.id);

    let contato_por_tel = contato_repo
        .buscar_por_telefone(&mut tx, &ctx, telefone)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(contato_por_tel.id, contato.id);

    // 3. Testar Idempotência (ON CONFLICT DO UPDATE)
    let contato_atualizado = contato_repo
        .salvar(&mut tx, &ctx, telefone, Some("João S. Silva"))
        .await
        .expect("Falha ao re-salvar contato");

    assert_eq!(contato_atualizado.id, contato.id);
    assert_eq!(
        contato_atualizado.nome_contato.as_deref(),
        Some("João S. Silva")
    );

    tx.rollback().await.unwrap();
}

#[tokio::test]
async fn test_cliente_crud_and_m2m() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let cliente_repo = PostgresClienteRepository;
    let contato_repo = PostgresContatoRepository;

    // Setup Tenant
    let tenant = criar_tenant_para_teste(&mut tx, "Tenant Clientes").await;

    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    // 1. Criar Cliente
    let cliente = cliente_repo
        .criar(
            &mut tx,
            &ctx,
            "Empresa Teste SA",
            Some("JURIDICA"),
            Some("12.345.678/0001-99"),
            None,
        )
        .await
        .expect("Falha ao criar cliente");

    assert_eq!(cliente.nome_fantasia, "Empresa Teste SA");
    assert_eq!(cliente.cnpj.as_deref(), Some("12.345.678/0001-99"));

    // 2. Buscar por ID e listar ativos
    let cliente_busca = cliente_repo
        .buscar_por_id(&mut tx, &ctx, cliente.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(cliente_busca.id, cliente.id);

    let lista = cliente_repo
        .listar_ativos(&mut tx, &ctx, 10, 0)
        .await
        .unwrap();
    assert!(!lista.is_empty());
    assert_eq!(lista[0].id, cliente.id);

    // 3. Criar Contato para associar
    let contato = contato_repo
        .salvar(&mut tx, &ctx, "5511977776666", Some("Maria Souza"))
        .await
        .unwrap();

    // 4. M2M Associação
    cliente_repo
        .adicionar_contato(&mut tx, &ctx, cliente.id, contato.id)
        .await
        .expect("Falha ao associar contato ao cliente");

    // Listar contatos via query direta (sem método no trait)
    let contatos_associados: Vec<i32> = sqlx::query_scalar!(
        "SELECT contato_id FROM oraculo_cliente_contatos
         WHERE tenant_id = $1 AND cliente_id = $2",
        ctx.tenant_id,
        cliente.id
    )
    .fetch_all(&mut *tx)
    .await
    .unwrap();
    assert_eq!(contatos_associados.len(), 1);
    assert_eq!(contatos_associados[0], contato.id);

    // 5. M2M Remoção
    cliente_repo
        .remover_contato(&mut tx, &ctx, cliente.id, contato.id)
        .await
        .expect("Falha ao remover associação de contato");

    let contatos_pos: Vec<i32> = sqlx::query_scalar!(
        "SELECT contato_id FROM oraculo_cliente_contatos
         WHERE tenant_id = $1 AND cliente_id = $2",
        ctx.tenant_id,
        cliente.id
    )
    .fetch_all(&mut *tx)
    .await
    .unwrap();
    assert!(contatos_pos.is_empty());

    tx.rollback().await.unwrap();
}

#[tokio::test]
async fn test_clientes_rls_isolation() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let cliente_repo = PostgresClienteRepository;
    let contato_repo = PostgresContatoRepository;

    // Criar Tenant A
    let tenant_a = criar_tenant_para_teste(&mut tx, "Tenant A Clientes").await;

    // 1. Criar cliente no Tenant A
    configurar_tenant_transacao(&mut tx, tenant_a.id).await;
    let ctx_a = criar_contexto_teste(tenant_a.id);
    let cliente_a = cliente_repo
        .criar(
            &mut tx,
            &ctx_a,
            "Cliente do Tenant A",
            Some("FISICA"),
            None,
            None,
        )
        .await
        .unwrap();

    let contato_a = contato_repo
        .salvar(&mut tx, &ctx_a, "5511966665555", Some("Contato A"))
        .await
        .unwrap();

    // 2. Criar Tenant B e tentar acessar registros do Tenant A
    let tenant_b = criar_tenant_para_teste(&mut tx, "Tenant B Clientes").await;

    configurar_tenant_transacao(&mut tx, tenant_b.id).await;
    let ctx_b = criar_contexto_teste(tenant_b.id);

    let busca_cliente = cliente_repo
        .buscar_por_id(&mut tx, &ctx_b, cliente_a.id)
        .await
        .unwrap();
    assert!(
        busca_cliente.is_none(),
        "Tenant B acessou cliente do Tenant A!"
    );

    let busca_contato = contato_repo
        .buscar_por_id(&mut tx, &ctx_b, contato_a.id)
        .await
        .unwrap();
    assert!(
        busca_contato.is_none(),
        "Tenant B acessou contato do Tenant A!"
    );

    let lista_contatos_b = contato_repo
        .buscar_por_telefone(&mut tx, &ctx_b, "5511966665555")
        .await
        .unwrap();
    assert!(
        lista_contatos_b.is_none(),
        "Tenant B enxergou contato do Tenant A por telefone!"
    );

    tx.rollback().await.unwrap();
}

/// V1 — a busca de cliente casa o documento digitado com máscara, e o
/// documento gravado com máscara em cadastro antigo. V3 — a sugestão de
/// vínculo acha o cliente pelo documento e some quando o contato já é dele.
#[tokio::test]
async fn test_busca_por_documento_com_mascara_e_sugestao_de_vinculo() {
    use infrastructure_postgres::atendimentos::atendimentos::{
        AtendimentoRepository, PostgresAtendimentoRepository,
    };
    use infrastructure_postgres::clientes::clientes::{self as repo, DadosCliente};
    use infrastructure_postgres::operacional::departamentos::{
        DepartamentoRepository, PostgresDepartamentoRepository,
    };

    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();
    let tenant = criar_tenant_para_teste(&mut tx, "Tenant Busca Documento").await;
    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    let id_pf = repo::criar_cliente(
        &mut tx,
        &ctx,
        &DadosCliente {
            nome_fantasia: "Padaria Sol".into(),
            tipo: Some("pf".into()),
            cpf: Some("52998224725".into()),
            ..Default::default()
        },
    )
    .await
    .expect("Falha ao criar cliente PF");
    // Cadastro antigo: documento gravado com a máscara.
    let antigo = PostgresClienteRepository
        .criar(
            &mut tx,
            &ctx,
            "Empresa Antiga",
            Some("pj"),
            Some("11.222.333/0001-81"),
            None,
        )
        .await
        .expect("Falha ao criar cliente antigo");

    let ids = |lista: Vec<repo::ClienteResumo>| lista.into_iter().map(|c| c.id).collect::<Vec<_>>();
    let com_mascara = repo::listar_clientes(&mut tx, &ctx, "529.982.247-25", false, 10)
        .await
        .unwrap();
    assert_eq!(ids(com_mascara), vec![id_pf]);
    let so_digitos = repo::listar_clientes(&mut tx, &ctx, "52998224725", false, 10)
        .await
        .unwrap();
    assert_eq!(ids(so_digitos), vec![id_pf]);
    let antigo_por_digitos = repo::listar_clientes(&mut tx, &ctx, "11222333000181", false, 10)
        .await
        .unwrap();
    assert_eq!(ids(antigo_por_digitos), vec![antigo.id]);
    // Termo com letra procura nome: os dígitos dele não casam documento.
    let nome_com_numero = repo::listar_clientes(&mut tx, &ctx, "Loja 2247", false, 10)
        .await
        .unwrap();
    assert!(nome_com_numero.is_empty());

    let depto = PostgresDepartamentoRepository
        .criar(&mut tx, &ctx, "Suporte", None)
        .await
        .unwrap();
    let contato = PostgresContatoRepository
        .salvar(&mut tx, &ctx, "5511955554444", Some("Cliente Sugestão"))
        .await
        .unwrap();
    let atendimento = PostgresAtendimentoRepository
        .criar(&mut tx, &ctx, contato.id, Some(depto.id), None, None)
        .await
        .unwrap();

    let a = atendimento.id;
    assert_eq!(
        repo::cliente_do_documento_sem_vinculo(&mut tx, &ctx, a, "529.982.247-25")
            .await
            .unwrap(),
        Some(id_pf)
    );
    assert_eq!(
        repo::cliente_do_documento_sem_vinculo(&mut tx, &ctx, a, "11222333000181")
            .await
            .unwrap(),
        Some(antigo.id),
        "documento gravado com máscara tem de casar pelos dígitos"
    );
    // Documento válido que ninguém tem, e documento de tamanho errado.
    assert_eq!(
        repo::cliente_do_documento_sem_vinculo(&mut tx, &ctx, a, "11144477735")
            .await
            .unwrap(),
        None
    );
    assert_eq!(
        repo::cliente_do_documento_sem_vinculo(&mut tx, &ctx, a, "5299822472")
            .await
            .unwrap(),
        None
    );

    // Contato já ligado ao cliente: não há o que sugerir.
    assert!(
        repo::vincular_contato(&mut tx, &ctx, id_pf, contato.id, true)
            .await
            .unwrap()
    );
    assert_eq!(
        repo::cliente_do_documento_sem_vinculo(&mut tx, &ctx, a, "52998224725")
            .await
            .unwrap(),
        None
    );

    tx.rollback().await.unwrap();
}

/// V4 — CPF repetido no mesmo tenant vira `UniqueViolation`, que o
/// `data_postgres` devolve como conflito legível em vez de erro de banco.
#[tokio::test]
async fn test_documento_repetido_vira_violacao_de_unicidade() {
    use infrastructure_postgres::clientes::clientes::{self as repo, DadosCliente};
    use infrastructure_postgres::DbError;

    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();
    let tenant = criar_tenant_para_teste(&mut tx, "Tenant Documento Repetido").await;
    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    let dados = DadosCliente {
        nome_fantasia: "Primeiro".into(),
        tipo: Some("pf".into()),
        cpf: Some("52998224725".into()),
        ..Default::default()
    };
    repo::criar_cliente(&mut tx, &ctx, &dados)
        .await
        .expect("Falha ao criar o primeiro cliente");
    let repetido = repo::criar_cliente(
        &mut tx,
        &ctx,
        &DadosCliente {
            nome_fantasia: "Segundo".into(),
            ..dados.clone()
        },
    )
    .await;
    assert!(
        matches!(repetido, Err(DbError::UniqueViolation(_))),
        "esperava UniqueViolation"
    );

    // A transação ficou abortada pela violação; nada mais roda nela.
    tx.rollback().await.unwrap();
}

/// O que o teste do encadeamento colhe antes de limpar o banco.
struct ColhidoDoEncadeamento {
    cliente_id: i32,
    com_busca_falha: Result<(bool, Option<i32>), infrastructure_postgres::DbError>,
    depois_da_falha: Vec<serde_json::Value>,
    com_busca_ok: Result<(bool, Option<i32>), infrastructure_postgres::DbError>,
    depois_do_ok: Vec<serde_json::Value>,
    sem_documento: Result<(bool, Option<i32>), infrastructure_postgres::DbError>,
    marcou_manual: bool,
    com_gente_no_caminho: Result<(bool, Option<i32>), infrastructure_postgres::DbError>,
}

/// V3 — o encadeamento que o `gravar_campos_extraidos` do `data_postgres`
/// usa para o campo de CPF/CNPJ: grava o valor e procura o cliente a sugerir,
/// na mesma transação.
///
/// Diferente dos testes acima, este confirma as transações de verdade (como
/// o E2E): o que se prova é justamente o que fica no banco depois de cada
/// chamada. A falha da busca é provocada do único jeito que não exige
/// injeção de defeito: um contexto que pode gravar o valor
/// (`atendimentos:write`) e não pode ler clientes (`clientes:read`).
#[tokio::test]
async fn test_valor_da_ia_e_sugestao_de_vinculo_na_mesma_transacao() {
    use infrastructure_postgres::atendimentos::atendimentos::{
        AtendimentoRepository, PostgresAtendimentoRepository,
    };
    use infrastructure_postgres::atendimentos::campos::{
        CampoPersonalizadoRepository, PostgresCampoPersonalizadoRepository,
        PostgresValorCampoRepository, ValorCampoRepository,
    };
    use infrastructure_postgres::clientes::clientes::{
        self as repo, DadosCliente, ValorExtraidoPelaIa,
    };
    use infrastructure_postgres::connection::run_in_tenant_transaction;
    use infrastructure_postgres::{DbError, RequestContext};
    use sqlx::PgPool;

    const CPF: &str = "52998224725";

    /// Uma chamada do encadeamento na sua própria transação, confirmada só
    /// se der certo — é o que o adaptador do `data_postgres` faz.
    async fn gravar(
        pool: &PgPool,
        ctx: &RequestContext,
        extraido: ValorExtraidoPelaIa,
        documento: Option<&'static str>,
    ) -> Result<(bool, Option<i32>), DbError> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(pool, ctx.tenant_id, |mut tx| async move {
            let desfecho =
                repo::gravar_valor_da_ia_e_sugerir_vinculo(&mut tx, &ctx, extraido, documento)
                    .await?;
            Ok((desfecho, tx))
        })
        .await
    }

    /// O que está gravado no atendimento, lido em transação independente.
    async fn valores_gravados(
        pool: &PgPool,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Vec<serde_json::Value> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(pool, ctx.tenant_id, |mut tx| async move {
            let linhas = PostgresValorCampoRepository
                .listar_por_atendimento(&mut tx, &ctx, atendimento_id)
                .await?;
            let valores: Vec<serde_json::Value> = linhas.into_iter().map(|l| l.valor).collect();
            Ok((valores, tx))
        })
        .await
        .expect("Falha ao ler os valores gravados")
    }

    let pool = obter_pool_teste().await;
    let mut tx0 = pool.begin().await.unwrap();
    let tenant = criar_tenant_para_teste(&mut tx0, "Tenant Encadeamento Sugestão").await;
    tx0.commit().await.unwrap();
    let tenant_id = tenant.id;
    let ctx = criar_contexto_teste(tenant_id);
    // Grava valor de campo, mas não lê clientes: a busca da sugestão falha.
    let ctx_sem_clientes = RequestContext {
        tenant_id,
        user_id: 1,
        user_scopes: vec!["atendimentos:read".into(), "atendimentos:write".into()],
        flow_permissions: Vec::new(),
    };

    let preparo: Result<(i32, i32, i64), DbError> = {
        let ctx = ctx.clone();
        run_in_tenant_transaction(&pool, tenant_id, |mut tx| async move {
            let cliente_id = repo::criar_cliente(
                &mut tx,
                &ctx,
                &DadosCliente {
                    nome_fantasia: "Padaria Sol".into(),
                    tipo: Some("pf".into()),
                    cpf: Some(CPF.into()),
                    ..Default::default()
                },
            )
            .await?;
            let contato = PostgresContatoRepository
                .salvar(&mut tx, &ctx, "5511944443333", Some("Cliente Encadeamento"))
                .await?;
            let atendimento = PostgresAtendimentoRepository
                .criar(&mut tx, &ctx, contato.id, None, None, None)
                .await?;
            let campo = PostgresCampoPersonalizadoRepository
                .criar(
                    &mut tx,
                    &ctx,
                    "cpf_do_cliente",
                    "CPF",
                    "GLOBAL",
                    "cpf",
                    None,
                )
                .await?;
            Ok(((cliente_id, atendimento.id, campo.id), tx))
        })
        .await
    };

    // Tudo o que o teste observa é colhido antes da limpeza; as asserções
    // ficam para o fim, para o tenant não sobrar no banco quando uma falha.
    let mut colhido = None;
    if let Ok((cliente_id, atendimento_id, campo_id)) = preparo {
        let extraido = || ValorExtraidoPelaIa {
            atendimento_id,
            campo_id,
            valor: serde_json::json!(CPF),
            confianca: 0.9,
            mensagem_origem_id: None,
        };

        // 1. Busca falha: erro para quem chama, transação não confirmada.
        let com_busca_falha = gravar(&pool, &ctx_sem_clientes, extraido(), Some(CPF)).await;
        let depois_da_falha = valores_gravados(&pool, &ctx, atendimento_id).await;

        // 2. Busca ok: o valor entra e a sugestão sai.
        let com_busca_ok = gravar(&pool, &ctx, extraido(), Some(CPF)).await;
        let depois_do_ok = valores_gravados(&pool, &ctx, atendimento_id).await;

        // 3. Documento regravado igual: o chamador não manda documento, e
        //    não há busca nem sugestão repetida — com este contexto a busca
        //    daria erro, e não dá.
        let sem_documento = gravar(&pool, &ctx_sem_clientes, extraido(), None).await;

        // 4. Gente no caminho: o valor não é regravado e nem se procura
        //    cliente (de novo, a busca daria erro com este contexto).
        let marcou_manual = run_in_tenant_transaction(&pool, tenant_id, |mut tx| async move {
            sqlx::query(
                "UPDATE atu_valor_campo SET origem = 'MANUAL' \
                 WHERE tenant_id = $1 AND atendimento_id = $2",
            )
            .bind(tenant_id)
            .bind(atendimento_id)
            .execute(&mut *tx)
            .await?;
            Ok(((), tx))
        })
        .await
        .is_ok();
        let com_gente_no_caminho = gravar(&pool, &ctx_sem_clientes, extraido(), Some(CPF)).await;

        colhido = Some(ColhidoDoEncadeamento {
            cliente_id,
            com_busca_falha,
            depois_da_falha,
            com_busca_ok,
            depois_do_ok,
            sem_documento,
            marcou_manual,
            com_gente_no_caminho,
        });
    }

    // Limpeza: o tenant leva junto cliente, contato, atendimento e campo.
    let limpou = run_in_tenant_transaction(&pool, tenant_id, |mut tx| async move {
        sqlx::query("DELETE FROM tenants_tenant WHERE id = $1")
            .bind(tenant_id)
            .execute(&mut *tx)
            .await?;
        Ok(((), tx))
    })
    .await
    .is_ok();

    let c = colhido.expect("Falha ao preparar cliente, contato, atendimento e campo");
    assert!(limpou, "Falha ao apagar o tenant de teste");

    assert!(
        matches!(c.com_busca_falha, Err(DbError::PermissionDenied)),
        "a falha da busca tem de chegar a quem chama"
    );
    assert!(
        c.depois_da_falha.is_empty(),
        "com a busca falhando, o valor não pode ficar gravado"
    );

    assert!(
        matches!(c.com_busca_ok, Ok((true, Some(id))) if id == c.cliente_id),
        "com a busca funcionando, o valor entra e o cliente do documento é sugerido"
    );
    assert_eq!(c.depois_do_ok, vec![serde_json::json!(CPF)]);

    assert!(
        matches!(c.sem_documento, Ok((true, None))),
        "sem documento não há busca: grava e não sugere"
    );

    assert!(c.marcou_manual, "Falha ao marcar o valor como manual");
    assert!(
        matches!(c.com_gente_no_caminho, Ok((false, None))),
        "valor que a IA não gravou não gera busca nem sugestão"
    );
}
