//! Testes de integração do `StorageClient` contra o Cloudflare R2 (S3-compatible).
//!
//! Exercitam o fluxo real put → get → presign → delete. Cada teste usa um
//! `tenant_id` único e remove os objetos ao final para não acumular lixo no bucket.
//! São pulados quando as variáveis `S3_*` não estão configuradas (ver `common`).

use crate::common::cliente_teste;
use infrastructure_storage::StorageError;
use uuid::Uuid;

#[tokio::test]
async fn put_get_delete_fluxo_real() {
    let Some(client) = cliente_teste().await else {
        return;
    };
    let tenant = Uuid::new_v4();
    let file = "arquivo_integracao.txt";
    let conteudo = b"conteudo de integracao do storage R2";

    // put
    let uri = client
        .put(tenant, file, conteudo)
        .await
        .expect("put deve enviar o objeto");
    assert!(uri.contains(file), "URI deve conter o nome do arquivo");

    // get
    let baixado = client.get(tenant, file).await.expect("get deve recuperar");
    assert_eq!(baixado, conteudo.to_vec(), "bytes devem coincidir");

    // delete
    client
        .delete(tenant, file)
        .await
        .expect("delete deve remover");

    // get após delete → NotFound
    let pos_delete = client.get(tenant, file).await;
    assert!(
        matches!(pos_delete, Err(StorageError::NotFound)),
        "get após delete deve ser NotFound, foi {pos_delete:?}"
    );
}

#[tokio::test]
async fn presign_gera_url_baixavel() {
    let Some(client) = cliente_teste().await else {
        return;
    };
    let tenant = Uuid::new_v4();
    let file = "presign_integracao.bin";
    let conteudo = b"bytes para presign";

    client
        .put(tenant, file, conteudo)
        .await
        .expect("put deve enviar o objeto");

    // presign → URL assinada
    let url = client
        .presign(tenant, file, 60)
        .await
        .expect("presign deve gerar URL");
    assert!(url.starts_with("http"), "URL deve ser http(s): {url}");
    assert!(
        url.contains("X-Amz-Signature") || url.contains("x-amz-signature"),
        "URL deve conter assinatura SigV4: {url}"
    );

    // limpeza
    client
        .delete(tenant, file)
        .await
        .expect("delete de limpeza");
}

#[tokio::test]
async fn get_de_objeto_inexistente_e_not_found() {
    let Some(client) = cliente_teste().await else {
        return;
    };
    let tenant = Uuid::new_v4();
    let resultado = client.get(tenant, "nao_existe.dat").await;
    assert!(
        matches!(resultado, Err(StorageError::NotFound)),
        "objeto inexistente deve retornar NotFound, foi {resultado:?}"
    );
}
