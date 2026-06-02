use crate::common::{criar_contexto_teste, criar_tenant_para_teste, obter_pool_teste};
use infrastructure_postgres::{
    atendimentos::{
        atendimentos::{AtendimentoRepository, PostgresAtendimentoRepository},
        mensagens::{MensagemRepository, PostgresMensagemRepository},
    },
    clientes::contatos::{ContatoRepository, PostgresContatoRepository},
    connection::run_in_tenant_transaction,
};

/// Teste end-to-end de CRUD com PERSISTÊNCIA REAL no banco.
///
/// Diferente dos demais testes (que usam transação + rollback para não poluir),
/// este faz `commit` de verdade e relê os dados em transações independentes, provando
/// que a gravação chegou ao PostgreSQL. Ao final, exerce o DELETE em cascata do tenant
/// e confirma que todos os dados dependentes foram removidos — servindo de smoke test
/// da comunicação real crate ↔ banco (incluindo RLS via role NOBYPASSRLS).
///
/// Observação: os repositórios são structs sem estado (ZST), então são instanciados
/// dentro de cada closure de transação (custo zero) para evitar capturá-los por move.
#[tokio::test]
async fn test_crud_completo_persistente_e2e() {
    let pool = obter_pool_teste().await;

    // --- CREATE (commit real) -------------------------------------------------
    // Cria tenant numa transação dedicada e a persiste.
    let mut tx0 = pool.begin().await.unwrap();
    let tenant = criar_tenant_para_teste(&mut tx0, "E2E Persistente").await;
    tx0.commit().await.unwrap();
    let tenant_id = tenant.id;
    let ctx = criar_contexto_teste(tenant_id);

    // Cria contato + atendimento + mensagem usando o helper de transação RLS (commit).
    let (contato_id, atendimento_id) = run_in_tenant_transaction(&pool, tenant_id, |mut tx| {
        let ctx = ctx.clone();
        async move {
            let contato_repo = PostgresContatoRepository;
            let atendimento_repo = PostgresAtendimentoRepository;
            let mensagem_repo = PostgresMensagemRepository;

            let contato = contato_repo
                .salvar(&mut tx, &ctx, "5511900000000", Some("Cliente E2E"))
                .await?;
            let atendimento = atendimento_repo
                .criar(&mut tx, &ctx, contato.id, None, None, None)
                .await?;
            mensagem_repo
                .criar(
                    &mut tx,
                    &ctx,
                    atendimento.id,
                    "extendedTextMessage",
                    "Olá, preciso de ajuda",
                    "contato",
                    None,
                    None,
                )
                .await?;
            Ok(((contato.id, atendimento.id), tx))
        }
    })
    .await
    .expect("Falha ao persistir cadastro E2E");

    // --- READ (transação independente — prova a persistência) -----------------
    let (contato_lido, mensagens) = run_in_tenant_transaction(&pool, tenant_id, |mut tx| {
        let ctx = ctx.clone();
        async move {
            let contato_repo = PostgresContatoRepository;
            let mensagem_repo = PostgresMensagemRepository;

            let c = contato_repo
                .buscar_por_id(&mut tx, &ctx, contato_id)
                .await?;
            let msgs = mensagem_repo
                .listar_por_atendimento(&mut tx, &ctx, atendimento_id, 10, 0)
                .await?;
            Ok(((c, msgs), tx))
        }
    })
    .await
    .unwrap();
    assert!(
        contato_lido.is_some(),
        "Contato deveria ter sido persistido no banco!"
    );
    assert_eq!(
        contato_lido.unwrap().nome_contato.as_deref(),
        Some("Cliente E2E")
    );
    assert_eq!(mensagens.len(), 1, "A mensagem deveria estar persistida!");
    assert_eq!(mensagens[0].conteudo, "Olá, preciso de ajuda");

    // --- UPDATE (commit real) -------------------------------------------------
    run_in_tenant_transaction(&pool, tenant_id, |mut tx| {
        let ctx = ctx.clone();
        async move {
            let atendimento_repo = PostgresAtendimentoRepository;
            atendimento_repo
                .atualizar_status(&mut tx, &ctx, atendimento_id, "resolvido")
                .await?;
            Ok(((), tx))
        }
    })
    .await
    .unwrap();

    // Confirma a atualização numa nova transação.
    let status_persistido = run_in_tenant_transaction(&pool, tenant_id, |mut tx| {
        let ctx = ctx.clone();
        async move {
            let atendimento_repo = PostgresAtendimentoRepository;
            let a = atendimento_repo
                .buscar_por_id(&mut tx, &ctx, atendimento_id)
                .await?
                .expect("atendimento deveria existir");
            Ok((a.status, tx))
        }
    })
    .await
    .unwrap();
    assert_eq!(
        status_persistido, "resolvido",
        "O UPDATE de status não persistiu!"
    );

    // --- DELETE em cascata (commit real) --------------------------------------
    // Remover o tenant deve apagar contato, atendimento e mensagem via ON DELETE CASCADE.
    run_in_tenant_transaction(&pool, tenant_id, |mut tx| async move {
        sqlx::query!("DELETE FROM tenants_tenant WHERE id = $1", tenant_id)
            .execute(&mut *tx)
            .await
            .map_err(infrastructure_postgres::errors::DbError::SqlxError)?;
        Ok(((), tx))
    })
    .await
    .unwrap();

    // Verifica (com a role admin, sem RLS) que nada sobrou — prova o cascade.
    let admin_url = std::env::var("DATABASE_ADMIN_URL")
        .expect("DATABASE_ADMIN_URL necessária para a verificação final do cascade");
    let admin_pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(1)
        .connect(&admin_url)
        .await
        .unwrap();

    let contatos_restantes: i64 = sqlx::query_scalar!(
        "SELECT COUNT(*) FROM oraculo_contato WHERE tenant_id = $1",
        tenant_id
    )
    .fetch_one(&admin_pool)
    .await
    .unwrap()
    .unwrap_or(0);
    let mensagens_restantes: i64 = sqlx::query_scalar!(
        "SELECT COUNT(*) FROM oraculo_mensagem WHERE tenant_id = $1",
        tenant_id
    )
    .fetch_one(&admin_pool)
    .await
    .unwrap()
    .unwrap_or(0);

    assert_eq!(contatos_restantes, 0, "Cascade não removeu os contatos!");
    assert_eq!(mensagens_restantes, 0, "Cascade não removeu as mensagens!");

    admin_pool.close().await;
}
