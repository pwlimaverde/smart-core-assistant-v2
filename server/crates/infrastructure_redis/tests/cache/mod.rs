use infrastructure_redis::{CachePermissoes, TTL_FLOW_PERMISSIONS_SEGUNDOS};
use uuid::Uuid;

use crate::common::conexao_limpa;

#[tokio::test]
async fn test_should_gravar_e_ler_flow_permissions() {
    let mut cache = CachePermissoes::new(conexao_limpa().await);
    let tenant = Uuid::new_v4();

    // Cache miss inicial.
    assert!(cache
        .obter_flow_permissions(tenant, 1)
        .await
        .unwrap()
        .is_none());

    cache
        .definir_flow_permissions(tenant, 1, &[1, 2, 3], TTL_FLOW_PERMISSIONS_SEGUNDOS)
        .await
        .unwrap();

    assert_eq!(
        cache.obter_flow_permissions(tenant, 1).await.unwrap(),
        Some(vec![1, 2, 3])
    );
}

#[tokio::test]
async fn test_should_invalidar_flow_permissions() {
    let mut cache = CachePermissoes::new(conexao_limpa().await);
    let tenant = Uuid::new_v4();

    cache
        .definir_flow_permissions(tenant, 9, &[5], 60)
        .await
        .unwrap();
    cache.invalidar(tenant, 9).await.unwrap();

    assert!(cache
        .obter_flow_permissions(tenant, 9)
        .await
        .unwrap()
        .is_none());
}
