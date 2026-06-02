use infrastructure_redis::{RedisError, RefreshTokenStore, TokenBlocklist};
use uuid::Uuid;

use crate::common::conexao_limpa;

#[tokio::test]
async fn test_should_rotacionar_refresh_quando_token_valido() {
    let mut store = RefreshTokenStore::new(conexao_limpa().await);
    let tenant = Some(Uuid::new_v4());

    store
        .armazenar("hash-a", 1, tenant, "fam-1", 3600)
        .await
        .unwrap();

    let registro = store.validar_e_rotacionar("hash-a").await.unwrap();
    assert_eq!(registro.user_id, 1);
    assert_eq!(registro.tenant_id, tenant);
    assert!(!registro.rotacionado);

    // Novo token na mesma família continua válido.
    store
        .armazenar("hash-b", 1, tenant, "fam-1", 3600)
        .await
        .unwrap();
    let registro2 = store.validar_e_rotacionar("hash-b").await.unwrap();
    assert_eq!(registro2.family_id, "fam-1");
}

#[tokio::test]
async fn test_should_revogar_familia_quando_reuso_detectado() {
    let mut store = RefreshTokenStore::new(conexao_limpa().await);

    store
        .armazenar("hash-x", 7, None, "fam-2", 3600)
        .await
        .unwrap();
    store
        .armazenar("hash-y", 7, None, "fam-2", 3600)
        .await
        .unwrap();

    // Primeiro uso de hash-x: rotaciona normalmente.
    store.validar_e_rotacionar("hash-x").await.unwrap();

    // Reuso de hash-x: detecta e revoga a família inteira.
    let err = store.validar_e_rotacionar("hash-x").await.unwrap_err();
    assert!(matches!(err, RedisError::TokenReuse));

    // hash-y, da mesma família, também foi revogado.
    let err2 = store.validar_e_rotacionar("hash-y").await.unwrap_err();
    assert!(matches!(err2, RedisError::NotFound));
}

#[tokio::test]
async fn test_should_retornar_not_found_quando_token_inexistente() {
    let mut store = RefreshTokenStore::new(conexao_limpa().await);
    let err = store.validar_e_rotacionar("inexistente").await.unwrap_err();
    assert!(matches!(err, RedisError::NotFound));
}

#[tokio::test]
async fn test_should_bloquear_jti_na_blocklist() {
    let mut blocklist = TokenBlocklist::new(conexao_limpa().await);

    assert!(!blocklist.esta_bloqueado("jti-1").await.unwrap());
    blocklist.bloquear("jti-1", 60).await.unwrap();
    assert!(blocklist.esta_bloqueado("jti-1").await.unwrap());
}
