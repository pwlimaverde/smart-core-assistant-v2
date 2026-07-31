//! Vouchers de ativação contra Postgres real.
//!
//! O foco aqui é o que teste unitário não alcança: a **atomicidade do resgate**.
//! A regra de negócio pura (classificação da recusa, cálculo do período) já é
//! coberta na própria `tenants::vouchers`; o que precisa de banco é provar que
//! duas transações concorrentes não conseguem consumir a mesma vaga.

use crate::common::{criar_tenant_para_teste, obter_pool_teste};
use chrono::{Duration, Utc};
use infrastructure_postgres::tenants::vouchers::{
    criar, listar, listar_resgates, registrar_resgate, resgatar, revogar, RecusaVoucher,
    ResultadoResgate,
};
use infrastructure_postgres::DbError;
use sqlx::PgPool;
use uuid::Uuid;

/// Código único por execução: a tabela é global (sem RLS) e os testes rodam
/// contra um banco compartilhado — códigos fixos colidiriam entre execuções.
fn codigo_unico(prefixo: &str) -> String {
    format!("{prefixo}-{}", Uuid::new_v4().simple())
}

/// Id do plano usado nos testes. Reaproveita o "Básico" semeado pela migration
/// 0027; se alguém o tiver renomeado, cai em qualquer plano existente.
async fn plano_de_teste(pool: &PgPool) -> i32 {
    sqlx::query_scalar::<_, i32>(
        "SELECT id FROM tenants_plan ORDER BY (name = 'Básico') DESC, id LIMIT 1",
    )
    .fetch_one(pool)
    .await
    .expect("nenhum plano disponível — a migration 0027 semeia o Básico")
}

#[tokio::test]
async fn resgate_concede_plano_e_registra_o_periodo() {
    let pool = obter_pool_teste().await;
    let plan_id = plano_de_teste(&pool).await;
    let codigo = codigo_unico("SUCESSO");

    criar(&pool, &codigo, "teste", plan_id, 180, 1, None, None)
        .await
        .expect("falha ao criar voucher");

    let mut tx = pool.begin().await.unwrap();
    let resultado = resgatar(&mut tx, &codigo).await.unwrap();

    let ResultadoResgate::Concedido(concessao) = resultado else {
        panic!("voucher válido deveria conceder, veio {resultado:?}");
    };
    assert_eq!(concessao.plan_id, plan_id);
    assert_eq!(concessao.duracao_dias, 180);

    // O período começa no resgate e dura o que o voucher concede.
    let inicio = Utc::now();
    let fim = concessao.periodo_fim(inicio);
    assert!((fim - inicio).num_days() == 180);

    let tenant = criar_tenant_para_teste(&mut tx, "Tenant do Voucher").await;
    let resgate = registrar_resgate(
        &mut tx,
        concessao.voucher_id,
        tenant.id,
        plan_id,
        inicio,
        fim,
        "203.0.113.7",
    )
    .await
    .expect("falha ao registrar resgate");

    assert_eq!(resgate.tenant_id, tenant.id);
    assert_eq!(resgate.ip, "203.0.113.7");
    tx.rollback().await.unwrap();
}

#[tokio::test]
async fn caixa_e_espacos_nao_impedem_o_resgate() {
    let pool = obter_pool_teste().await;
    let plan_id = plano_de_teste(&pool).await;
    let codigo = codigo_unico("CaseTeste");

    criar(&pool, &codigo, "", plan_id, 30, 1, None, None)
        .await
        .unwrap();

    let mut tx = pool.begin().await.unwrap();
    // Como o usuário digitaria: caixa trocada e espaço sobrando.
    let digitado = format!("  {}  ", codigo.to_lowercase());
    let resultado = resgatar(&mut tx, &digitado).await.unwrap();

    assert!(
        matches!(resultado, ResultadoResgate::Concedido(_)),
        "normalização deveria aceitar '{digitado}', veio {resultado:?}"
    );
    tx.rollback().await.unwrap();
}

#[tokio::test]
async fn duas_transacoes_concorrentes_disputam_a_ultima_vaga() {
    // O cenário clássico de exploração de cupom: dois resgates simultâneos de um
    // código de uso único. Como `check` e `update` são o mesmo statement, o
    // segundo encontra `resgates_usados` já incrementado e sai sem conceder.
    let pool = obter_pool_teste().await;
    let plan_id = plano_de_teste(&pool).await;
    let codigo = codigo_unico("CORRIDA");

    criar(&pool, &codigo, "uso único", plan_id, 90, 1, None, None)
        .await
        .unwrap();

    let (pool_a, pool_b) = (pool.clone(), pool.clone());
    let (codigo_a, codigo_b) = (codigo.clone(), codigo.clone());

    let tarefa_a = tokio::spawn(async move {
        let mut tx = pool_a.begin().await.unwrap();
        let r = resgatar(&mut tx, &codigo_a).await.unwrap();
        // Commit: quem venceu precisa persistir o incremento para o outro ver.
        tx.commit().await.unwrap();
        r
    });
    let tarefa_b = tokio::spawn(async move {
        let mut tx = pool_b.begin().await.unwrap();
        let r = resgatar(&mut tx, &codigo_b).await.unwrap();
        tx.commit().await.unwrap();
        r
    });

    let (a, b) = (tarefa_a.await.unwrap(), tarefa_b.await.unwrap());
    let concedidos = [&a, &b]
        .iter()
        .filter(|r| matches!(r, ResultadoResgate::Concedido(_)))
        .count();

    assert_eq!(
        concedidos, 1,
        "exatamente um resgate deveria vencer a corrida; veio a={a:?} b={b:?}"
    );
    assert!(
        [&a, &b]
            .iter()
            .any(|r| matches!(r, ResultadoResgate::Recusado(RecusaVoucher::Esgotado))),
        "o perdedor deveria ser recusado por esgotamento; veio a={a:?} b={b:?}"
    );
}

#[tokio::test]
async fn retentativa_do_mesmo_tenant_nao_consome_o_voucher_de_novo() {
    // O UPDATE atômico resolve concorrência entre cadastros DISTINTOS. Uma
    // retentativa de rede do MESMO cadastro é outro problema, e quem o barra é a
    // UNIQUE (voucher_id, tenant_id): o segundo INSERT falha e derruba a
    // transação, devolvendo o resgate.
    let pool = obter_pool_teste().await;
    let plan_id = plano_de_teste(&pool).await;
    let codigo = codigo_unico("RETENTATIVA");

    // max_resgates = 0 (ilimitado) para isolar a variável: se o segundo resgate
    // for barrado, foi pela unique, não por esgotamento.
    let voucher = criar(&pool, &codigo, "", plan_id, 30, 0, None, None)
        .await
        .unwrap();

    let mut tx = pool.begin().await.unwrap();
    let tenant = criar_tenant_para_teste(&mut tx, "Tenant Retentativa").await;
    let inicio = Utc::now();
    let fim = inicio + Duration::days(30);

    registrar_resgate(&mut tx, voucher.id, tenant.id, plan_id, inicio, fim, "")
        .await
        .expect("primeiro registro deveria passar");

    let repetido =
        registrar_resgate(&mut tx, voucher.id, tenant.id, plan_id, inicio, fim, "").await;

    assert!(
        matches!(repetido, Err(DbError::UniqueViolation(_))),
        "o segundo registro do mesmo par deveria violar a unique, veio {repetido:?}"
    );
    tx.rollback().await.unwrap();
}

#[tokio::test]
async fn voucher_revogado_recusa_novos_resgates() {
    let pool = obter_pool_teste().await;
    let plan_id = plano_de_teste(&pool).await;
    let codigo = codigo_unico("REVOGADO");

    let voucher = criar(&pool, &codigo, "", plan_id, 30, 0, None, None)
        .await
        .unwrap();

    assert!(
        revogar(&pool, voucher.id, Some(1), "vazou no grupo errado")
            .await
            .unwrap(),
        "a primeira revogação deveria afetar a linha"
    );
    assert!(
        !revogar(&pool, voucher.id, Some(1), "de novo")
            .await
            .unwrap(),
        "revogar duas vezes não pode sobrescrever quem revogou e quando"
    );

    let mut tx = pool.begin().await.unwrap();
    let resultado = resgatar(&mut tx, &codigo).await.unwrap();
    assert_eq!(
        resultado,
        ResultadoResgate::Recusado(RecusaVoucher::Revogado)
    );
    tx.rollback().await.unwrap();
}

#[tokio::test]
async fn voucher_expirado_e_esgotado_sao_recusados_com_motivos_distintos() {
    let pool = obter_pool_teste().await;
    let plan_id = plano_de_teste(&pool).await;

    // Expirado. Não dá para NASCER expirado: a constraint
    // `tenants_voucher_janela_coerente` exige `valido_ate > valido_de`, e
    // `valido_de` é NOW() — uma janela invertida é dado inválido, não um estado
    // de negócio. O jeito honesto de chegar em "expirado" é simular a passagem
    // do tempo, empurrando a janela inteira para trás depois de criado.
    let expirado = codigo_unico("EXPIRADO");
    criar(&pool, &expirado, "", plan_id, 30, 0, None, None)
        .await
        .unwrap();
    sqlx::query(
        "UPDATE tenants_voucher \
            SET valido_de = NOW() - INTERVAL '30 days', \
                valido_ate = NOW() - INTERVAL '1 day' \
          WHERE codigo_normalizado = $1",
    )
    .bind(expirado.to_uppercase())
    .execute(&pool)
    .await
    .expect("falha ao envelhecer o voucher");

    // Esgotado: uma vaga, já consumida.
    let esgotado = codigo_unico("ESGOTADO");
    criar(&pool, &esgotado, "", plan_id, 30, 1, None, None)
        .await
        .unwrap();
    let mut tx = pool.begin().await.unwrap();
    resgatar(&mut tx, &esgotado).await.unwrap();
    tx.commit().await.unwrap();

    let mut tx = pool.begin().await.unwrap();
    assert_eq!(
        resgatar(&mut tx, &expirado).await.unwrap(),
        ResultadoResgate::Recusado(RecusaVoucher::Expirado)
    );
    assert_eq!(
        resgatar(&mut tx, &esgotado).await.unwrap(),
        ResultadoResgate::Recusado(RecusaVoucher::Esgotado)
    );
    assert_eq!(
        resgatar(&mut tx, "NAO-EXISTE-EM-LUGAR-NENHUM")
            .await
            .unwrap(),
        ResultadoResgate::Recusado(RecusaVoucher::Inexistente)
    );
    tx.rollback().await.unwrap();
}

#[tokio::test]
async fn codigo_duplicado_e_recusado_mesmo_com_grafia_diferente() {
    let pool = obter_pool_teste().await;
    let plan_id = plano_de_teste(&pool).await;
    let codigo = codigo_unico("DUPLICADO");

    criar(&pool, &codigo, "", plan_id, 30, 1, None, None)
        .await
        .unwrap();

    let repetido = criar(
        &pool,
        &codigo.to_lowercase(),
        "",
        plan_id,
        30,
        1,
        None,
        None,
    )
    .await;
    assert!(
        matches!(repetido, Err(DbError::UniqueViolation(_))),
        "a unique é sobre o código normalizado, veio {repetido:?}"
    );
}

#[tokio::test]
async fn listagens_expoem_o_plano_e_o_historico() {
    let pool = obter_pool_teste().await;
    let plan_id = plano_de_teste(&pool).await;
    let codigo = codigo_unico("LISTAGEM");

    let voucher = criar(&pool, &codigo, "campanha", plan_id, 180, 0, None, Some(1))
        .await
        .unwrap();

    let lista = listar(&pool).await.unwrap();
    let item = lista
        .iter()
        .find(|i| i.voucher.id == voucher.id)
        .expect("o voucher recém-criado deveria aparecer na listagem");
    assert!(
        !item.plan_name.is_empty(),
        "a listagem resolve o nome do plano pelo JOIN"
    );

    // Sem resgates ainda; depois de um, o histórico o mostra.
    assert!(listar_resgates(&pool, voucher.id).await.unwrap().is_empty());

    let mut tx = pool.begin().await.unwrap();
    let tenant = criar_tenant_para_teste(&mut tx, "Tenant Histórico").await;
    let inicio = Utc::now();
    registrar_resgate(
        &mut tx,
        voucher.id,
        tenant.id,
        plan_id,
        inicio,
        inicio + Duration::days(180),
        "198.51.100.4",
    )
    .await
    .unwrap();
    tx.commit().await.unwrap();

    let historico = listar_resgates(&pool, voucher.id).await.unwrap();
    assert_eq!(historico.len(), 1);
    assert_eq!(historico[0].tenant_id, tenant.id);
}
