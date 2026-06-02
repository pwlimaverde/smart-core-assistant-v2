use infrastructure_redis::{
    confirmar, consumir, garantir_consumer_group, publicar_evento, reprocessar_pendentes,
    TenantEnvelope,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::common::conexao_limpa;

#[derive(Debug, Serialize, Deserialize, PartialEq)]
struct MensagemRecebida {
    texto: String,
}

#[tokio::test]
async fn test_should_publicar_consumir_e_confirmar() {
    let mut con = conexao_limpa().await;
    let grupo = "grp-basico";
    garantir_consumer_group(&mut con, grupo).await.unwrap();

    let tenant = Uuid::new_v4();
    let envelope = TenantEnvelope::novo(
        tenant,
        "message.received",
        MensagemRecebida { texto: "oi".into() },
    );
    publicar_evento(&mut con, &envelope).await.unwrap();

    let recebidos = consumir(&mut con, grupo, "c1", 10, 0).await.unwrap();
    assert_eq!(recebidos.len(), 1);

    let bruto = &recebidos[0];
    assert_eq!(bruto.event_type, "message.received");

    let tipado: TenantEnvelope<MensagemRecebida> = bruto.desserializar().unwrap();
    assert_eq!(tipado.tenant_id, tenant);
    assert_eq!(tipado.event_id, envelope.event_id);
    assert_eq!(tipado.payload, MensagemRecebida { texto: "oi".into() });

    // Confirma e garante que não restam pendentes.
    confirmar(&mut con, grupo, &bruto.stream_id).await.unwrap();
    let pendentes = reprocessar_pendentes(&mut con, grupo, "c1", 10)
        .await
        .unwrap();
    assert!(pendentes.is_empty());
}

#[tokio::test]
async fn test_should_reprocessar_pendentes_quando_sem_ack() {
    let mut con = conexao_limpa().await;
    let grupo = "grp-replay";
    garantir_consumer_group(&mut con, grupo).await.unwrap();

    let envelope = TenantEnvelope::novo(
        Uuid::new_v4(),
        "ticket.opened",
        MensagemRecebida { texto: "x".into() },
    );
    publicar_evento(&mut con, &envelope).await.unwrap();

    // Consome sem confirmar (simula falha de processamento).
    let recebidos = consumir(&mut con, grupo, "c1", 10, 0).await.unwrap();
    assert_eq!(recebidos.len(), 1);

    // Replay: relê os pendentes do mesmo consumidor.
    let pendentes = reprocessar_pendentes(&mut con, grupo, "c1", 10)
        .await
        .unwrap();
    assert_eq!(pendentes.len(), 1);
    assert_eq!(pendentes[0].stream_id, recebidos[0].stream_id);

    // Após confirmar, não há mais pendentes.
    confirmar(&mut con, grupo, &pendentes[0].stream_id)
        .await
        .unwrap();
    let pendentes2 = reprocessar_pendentes(&mut con, grupo, "c1", 10)
        .await
        .unwrap();
    assert!(pendentes2.is_empty());
}
