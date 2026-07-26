use contracts::TenantEnvelope;
use redis::aio::ConnectionManager;
use transport::bus::{
    confirmar, consumir, garantir_consumer_group, publicar_evento, reclamar_pendentes_abandonados,
    reprocessar_pendentes, MIN_IDLE_REPROCESSAMENTO_MS, STREAM_EVENTOS,
};
use uuid::Uuid;

fn carregar_redis_url() -> String {
    // Garante que o túnel SSH para o Redis esteja ativo
    test_support::ensure_tunnel();

    let caminhos = vec![
        ".env",
        "../.env",
        "../../.env",
        "crates/transport/.env",
        "../transport/.env",
    ];
    for caminho in caminhos {
        if let Ok(conteudo) = std::fs::read_to_string(caminho) {
            for linha in conteudo.lines() {
                let linha_limpa = linha.trim();
                if linha_limpa.is_empty() || linha_limpa.starts_with('#') {
                    continue;
                }
                if let Some((chave, valor)) = linha_limpa.split_once('=') {
                    let chave = chave.trim();
                    let valor = valor.trim().trim_matches('"').trim_matches('\'');
                    if std::env::var(chave).is_err() {
                        std::env::set_var(chave, valor);
                    }
                }
            }
            break;
        }
    }

    std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6380".to_string())
}

#[tokio::test]
async fn test_redis_bus_publish_consume_flow() {
    let redis_url = carregar_redis_url();
    let client = redis::Client::open(redis_url).expect("Falha ao abrir cliente Redis");
    let mut con = ConnectionManager::new(client)
        .await
        .expect("Falha ao criar gerenciador de conexão Redis");

    let tenant_id = Uuid::new_v4();
    let event_type = "test.integration.event";
    let payload = serde_json::json!({
        "origem": "teste_integracao",
        "timestamp_unix": chrono::Utc::now().timestamp_millis()
    });

    let envelope = TenantEnvelope::novo(tenant_id, event_type, payload.clone())
        .com_traceparent("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01");

    let grupo = format!("grupo_teste_{}", Uuid::new_v4());
    let consumidor = "consumidor_teste_1";

    // 1. Garante que o consumer group existe
    let group_res = garantir_consumer_group(&mut con, &grupo).await;
    assert!(group_res.is_ok(), "Falha ao garantir consumer group");

    // 2. Publica o evento no stream
    let pub_id = publicar_evento(&mut con, &envelope).await;
    assert!(pub_id.is_ok(), "Falha ao publicar evento");
    let stream_id = pub_id.unwrap();

    // 3. Consome o evento
    let read_eventos = consumir(&mut con, &grupo, consumidor, 1, 1000).await;
    assert!(read_eventos.is_ok());
    let eventos = read_eventos.unwrap();
    assert_eq!(
        eventos.len(),
        1,
        "Deveria ter consumido exatamente 1 evento"
    );

    let evento_bruto = &eventos[0];
    assert_eq!(evento_bruto.stream_id, stream_id);
    assert_eq!(evento_bruto.tenant_id, tenant_id.to_string());
    assert_eq!(evento_bruto.event_type, event_type);
    assert_eq!(
        evento_bruto.traceparent,
        "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
    );

    // Desserializa o payload e valida
    let env_tipado = evento_bruto.desserializar::<serde_json::Value>().unwrap();
    assert_eq!(env_tipado.payload, payload);

    // 4. Confirma o evento (XACK)
    let ack_res = confirmar(&mut con, &grupo, &stream_id).await;
    assert!(ack_res.is_ok());

    // 5. Verifica se o PEL está limpo (reprocessamento de pendentes deve retornar zero)
    let pendentes = reprocessar_pendentes(&mut con, &grupo, consumidor, 1).await;
    assert!(pendentes.is_ok());
    assert!(
        pendentes.unwrap().is_empty(),
        "PEL deveria estar limpo após o ACK"
    );
}

#[tokio::test]
async fn test_redis_bus_pending_entries_recovery() {
    let redis_url = carregar_redis_url();
    let client = redis::Client::open(redis_url).unwrap();
    let mut con = ConnectionManager::new(client).await.unwrap();

    let tenant_id = Uuid::new_v4();
    let envelope = TenantEnvelope::novo(tenant_id, "test.pel.event", serde_json::json!({}));
    let grupo = format!("grupo_pel_{}", Uuid::new_v4());
    let consumidor = "consumidor_pel_1";

    garantir_consumer_group(&mut con, &grupo).await.unwrap();

    // Publica e consome (mas NÃO confirma)
    let stream_id = publicar_evento(&mut con, &envelope).await.unwrap();
    let eventos = consumir(&mut con, &grupo, consumidor, 1, 1000)
        .await
        .unwrap();
    assert_eq!(eventos.len(), 1);

    // Como não confirmamos, o evento deve estar pendente na PEL do consumidor.
    // Vamos reprocessar e verificar que o evento retorna.
    let pendentes = reprocessar_pendentes(&mut con, &grupo, consumidor, 1)
        .await
        .unwrap();
    assert_eq!(
        pendentes.len(),
        1,
        "Deveria ter recuperado o evento pendente"
    );
    assert_eq!(pendentes[0].stream_id, stream_id);

    // Agora confirma e garante que limpou
    confirmar(&mut con, &grupo, &stream_id).await.unwrap();
    let pendentes_pos_ack = reprocessar_pendentes(&mut con, &grupo, consumidor, 1)
        .await
        .unwrap();
    assert!(
        pendentes_pos_ack.is_empty(),
        "PEL deveria estar vazia após ACK"
    );
}

/// O reprocessador periódico da PEL roda EM PARALELO ao loop de consumo ativo, e a
/// PEL não distingue "handler morreu" de "handler está rodando agora": as duas
/// situações são só "entregue e sem XACK". Este teste fixa o piso de inatividade que
/// separa as duas — sem ele, o tick de reprocessamento pega a mensagem que o loop
/// está processando neste instante e o worker responde duas vezes ao mesmo cliente.
#[tokio::test]
async fn reclamar_pendentes_respeita_o_piso_de_inatividade() {
    let redis_url = carregar_redis_url();
    let client = redis::Client::open(redis_url).unwrap();
    let mut con = ConnectionManager::new(client).await.unwrap();

    let tenant_id = Uuid::new_v4();
    let envelope = TenantEnvelope::novo(tenant_id, "test.idle.event", serde_json::json!({}))
        .com_traceparent("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01");
    let grupo = format!("grupo_idle_{}", Uuid::new_v4());
    let consumidor_loop = "consumidor_loop";
    let consumidor_tick = "consumidor_tick";

    garantir_consumer_group(&mut con, &grupo).await.unwrap();

    // Simula o loop ativo: consome sem confirmar (handler "em voo"), idle ~0ms.
    let stream_id = publicar_evento(&mut con, &envelope).await.unwrap();
    let eventos = consumir(&mut con, &grupo, consumidor_loop, 1, 1000)
        .await
        .unwrap();
    assert_eq!(eventos.len(), 1);

    // O tick com piso alto NÃO pode encostar no evento em voo.
    let em_voo = reclamar_pendentes_abandonados(
        &mut con,
        STREAM_EVENTOS,
        &grupo,
        consumidor_tick,
        MIN_IDLE_REPROCESSAMENTO_MS,
        10,
    )
    .await
    .unwrap();
    assert!(
        em_voo.is_empty(),
        "evento em voo (idle ~0) foi reclamado indevidamente: {em_voo:?}"
    );

    // Com piso zero, o MESMO evento é reclamado — o que prova que o vazio acima veio
    // do piso, e não de o evento simplesmente não estar na PEL. É também o caminho
    // real de recuperação: um evento abandonado passa do piso e volta a ser tratado,
    // inclusive quando a PEL pertencia a OUTRO consumidor do grupo (réplica morta).
    let abandonado =
        reclamar_pendentes_abandonados(&mut con, STREAM_EVENTOS, &grupo, consumidor_tick, 0, 10)
            .await
            .unwrap();
    assert_eq!(
        abandonado.len(),
        1,
        "evento abandonado deveria ter sido reclamado"
    );
    assert_eq!(abandonado[0].stream_id, stream_id);
    // O conteúdo tem de sobreviver ao XCLAIM: o reprocessador desserializa o payload.
    assert_eq!(abandonado[0].tenant_id, tenant_id.to_string());
    assert_eq!(abandonado[0].event_type, "test.idle.event");
    assert_eq!(
        abandonado[0].traceparent,
        "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
    );

    confirmar(&mut con, &grupo, &stream_id).await.unwrap();
}
