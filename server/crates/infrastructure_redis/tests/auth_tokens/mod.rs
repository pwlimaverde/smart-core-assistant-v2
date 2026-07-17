use infrastructure_redis::{RedisError, RefreshTokenStore, TokenBlocklist};
use uuid::Uuid;

use crate::common::conexao_limpa;

/// N4.4 — teste de rajada do rate limiter genérico: simula N tentativas rápidas
/// (mesma janela) do mesmo recurso/id e valida que o contador cresce
/// monotonicamente e sem perda (INCR é atômico no Redis — não deve haver
/// condição de corrida mesmo disparando concorrentemente).
#[tokio::test]
async fn test_registrar_tentativa_recurso_rajada_conta_sem_perda() {
    let con = conexao_limpa().await;
    let rajada = 50u64;

    let mut handles = Vec::with_capacity(rajada as usize);
    for _ in 0..rajada {
        let mut con = con.clone();
        handles.push(tokio::spawn(async move {
            infrastructure_redis::registrar_tentativa_recurso(&mut con, "webhook", "tenant-x:1", 60)
                .await
        }));
    }

    let mut totais = Vec::with_capacity(rajada as usize);
    for h in handles {
        totais.push(
            h.await
                .unwrap()
                .expect("registrar_tentativa_recurso falhou na rajada"),
        );
    }

    // Todas as RAJADA chamadas concorrentes devem ter incrementado o MESMO
    // contador (INCR atômico) — o maior total observado deve ser exatamente RAJADA.
    assert_eq!(
        *totais.iter().max().unwrap(),
        rajada,
        "contador final deve refletir todas as tentativas da rajada, sem perda"
    );
    // Nenhum total pode exceder a rajada (não pode haver dupla-contagem).
    assert!(totais.iter().all(|&t| t <= rajada));
}

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
