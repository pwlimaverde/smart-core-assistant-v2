//! Consentimentos MCP — o que a tela de "Aplicativos conectados" pode afirmar.

use crate::common::{
    configurar_tenant_transacao, criar_contexto_teste, criar_tenant_para_teste, obter_pool_teste,
};
use infrastructure_postgres::mcp::grants;

const CLIENTE: &str = "https://claude.ai/.well-known/oauth-client";

/// Autorizar não é conectar.
///
/// O consentimento grava o grant e devolve um code; quem completa a conexão é o
/// cliente, ao trocar esse code no `/oauth/token`. Entre os dois passos existe
/// uma janela em que a linha já existe e a conexão ainda não — e um cliente que
/// desista no meio (foi o caso em 12/09/2026, por divergência de `issuer`) deixa
/// a linha ali para sempre.
///
/// Listar essa linha como aplicativo conectado faz a tela afirmar algo que não
/// aconteceu, e foi o que atrasou aquele diagnóstico: o produto dizia que o
/// vínculo existia.
#[tokio::test]
async fn grant_sem_troca_de_code_nao_conta_como_aplicativo_conectado() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let tenant = criar_tenant_para_teste(&mut tx, "Tenant MCP").await;
    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    let grant = grants::registrar_consentimento(
        &mut tx,
        &ctx,
        CLIENTE,
        "Claude",
        "https://claude.ai/api/mcp/auth_callback",
        &["atendimentos:read".to_string()],
        None,
    )
    .await
    .expect("consentimento gravado");

    // Estado logo após o "Autorizar": a linha existe, o cliente ainda não voltou.
    let listados = grants::listar_do_usuario(&mut tx, &ctx).await.unwrap();
    assert!(
        listados.is_empty(),
        "grant sem refresh apareceu como conectado: {listados:?}"
    );

    // O cliente troca o code — é aqui, e só aqui, que a conexão passa a existir.
    grants::definir_refresh_hash(&mut tx, tenant.id, grant.id, "hash-de-teste")
        .await
        .expect("hash gravado");

    let listados = grants::listar_do_usuario(&mut tx, &ctx).await.unwrap();
    assert_eq!(listados.len(), 1, "grant conectado sumiu da lista");
    assert_eq!(listados[0].id, grant.id);
    assert_eq!(listados[0].client_name, "Claude");

    tx.rollback().await.unwrap();
}

/// Desconectar tira da lista mesmo tendo conectado antes.
#[tokio::test]
async fn grant_revogado_sai_da_lista() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let tenant = criar_tenant_para_teste(&mut tx, "Tenant MCP revoga").await;
    configurar_tenant_transacao(&mut tx, tenant.id).await;
    let ctx = criar_contexto_teste(tenant.id);

    let grant = grants::registrar_consentimento(
        &mut tx,
        &ctx,
        CLIENTE,
        "Claude",
        "https://claude.ai/api/mcp/auth_callback",
        &["atendimentos:read".to_string()],
        None,
    )
    .await
    .unwrap();
    grants::definir_refresh_hash(&mut tx, tenant.id, grant.id, "hash-de-teste")
        .await
        .unwrap();
    assert_eq!(
        grants::listar_do_usuario(&mut tx, &ctx)
            .await
            .unwrap()
            .len(),
        1
    );

    let revogou = grants::revogar(&mut tx, &ctx, grant.id).await.unwrap();
    assert!(revogou, "revogação deveria ter encontrado o grant");

    assert!(
        grants::listar_do_usuario(&mut tx, &ctx)
            .await
            .unwrap()
            .is_empty(),
        "grant revogado continuou na lista"
    );

    tx.rollback().await.unwrap();
}
