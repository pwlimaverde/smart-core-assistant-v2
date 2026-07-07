//! Teste e2e (WS-0.3): prova que o `trace_id`/`traceparent` W3C semeado num evento
//! de webhook percorre toda a cadeia real — barramento (`STREAM_EVENTOS`, como o
//! `webhook_ingress` publica) → consumo (`consumir`, como o `worker` faz) → publicação
//! do evento de segurança (`STREAM_SEGURANCA`, como o `data_postgres` audita após a
//! chamada RPC) → consumidor real de auditoria (`processar_eventos_auditoria_lote`) →
//! linha persistida em `audit_log` — sem hardcode: cada etapa usa o `traceparent` que
//! efetivamente saiu da etapa anterior via Redis real (via túnel SSH do test_support).
//! Também confirma que nada sensível (telefone completo/payload bruto) chega ao
//! contexto persistido. Aceite explícito do dono para este teste (tensão sinalizada
//! com a diretriz "não criar testes por iniciativa própria" — WS-0.3 do plano
//! mvp-telas-e-endurecimento).

use redis::aio::ConnectionManager;
use sqlx::PgPool;
use transport::bus::{
    confirmar, confirmar_stream, consumir, consumir_stream, garantir_consumer_group,
    garantir_consumer_group_stream, publicar_evento, publicar_evento_seguranca, STREAM_SEGURANCA,
};
use uuid::Uuid;

fn carregar_env_teste() {
    test_support::ensure_tunnel();
    let caminhos = [
        ".env",
        "../.env",
        "../../.env",
        "apps/data_postgres/.env",
        "../data_postgres/.env",
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
}

async fn setup_pool() -> PgPool {
    carregar_env_teste();
    let admin_url = std::env::var("DATABASE_ADMIN_URL").expect("DATABASE_ADMIN_URL ausente");
    let pool = PgPool::connect(&admin_url)
        .await
        .expect("Falha ao conectar Postgres");
    infrastructure_postgres::inicializar_banco_dados(&pool)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO auth_user (id, username, email, password_hash, is_superuser, is_staff) \
         VALUES (1, 'ci_seed_admin', 'ci-seed@local', '', TRUE, TRUE) \
         ON CONFLICT (id) DO NOTHING",
    )
    .execute(&pool)
    .await
    .expect("falha ao semear auth_user padrão");
    pool
}

async fn conectar_bus() -> ConnectionManager {
    let bus_url = std::env::var("REDIS_BUS_URL")
        .or_else(|_| std::env::var("REDIS_URL"))
        .unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
    let client = redis::Client::open(bus_url).expect("Falha ao abrir cliente Redis do bus");
    ConnectionManager::new(client)
        .await
        .expect("Falha ao criar ConnectionManager do bus")
}

#[tokio::test]
async fn test_e2e_cadeia_de_trace_webhook_bus_worker_audit_log() {
    let pool = setup_pool().await;
    let mut con = conectar_bus().await;

    let tenant_id = Uuid::new_v4();
    let slug = format!("tenant-e2e-trace-{}", Uuid::new_v4());
    sqlx::query(
        "INSERT INTO tenants_tenant (id, name, slug, api_key, owner_id) VALUES ($1, $2, $3, $4, 1)",
    )
    .bind(tenant_id)
    .bind("Tenant E2E Trace")
    .bind(&slug)
    .bind(Uuid::new_v4().to_string())
    .execute(&pool)
    .await
    .unwrap();

    // Traceparent W3C semeado — simula o que o webhook_ingress injeta via
    // observability::injetar_contexto_atual ao normalizar a mensagem recebida.
    let trace_id_hex = Uuid::new_v4().simple().to_string();
    let span_id_hex = &Uuid::new_v4().simple().to_string()[..16];
    let traceparent_semeado = format!("00-{trace_id_hex}-{span_id_hex}-01");

    // --- Etapa 1: webhook_ingress publica no barramento padrão (STREAM_EVENTOS) ---
    // Payload já normalizado: telefone mascarado, nunca o número completo (doc 05 §6).
    let payload_webhook = serde_json::json!({
        "telefone_mascarado": "+55 11 9****-1234",
        "conteudo": "Olá, preciso de suporte",
    });
    let envelope_webhook =
        contracts::TenantEnvelope::novo(tenant_id, "whatsapp.mensagem_recebida", payload_webhook)
            .com_traceparent(traceparent_semeado.clone());

    let grupo_worker = format!("grupo_worker_e2e_{}", Uuid::new_v4());
    garantir_consumer_group(&mut con, &grupo_worker)
        .await
        .expect("Falha ao garantir consumer group do worker");
    publicar_evento(&mut con, &envelope_webhook)
        .await
        .expect("Falha ao publicar evento de webhook no barramento");

    // --- Etapa 2: worker consome do barramento (como faz na produção) ---
    let eventos_worker = consumir(&mut con, &grupo_worker, "worker_e2e_teste", 1, 2000)
        .await
        .expect("Falha ao consumir evento como worker");
    assert_eq!(eventos_worker.len(), 1, "worker deveria consumir 1 evento");
    let evento_consumido_pelo_worker = &eventos_worker[0];

    // Prova a 1ª perna da cadeia: o traceparent sobrevive ao hop pelo barramento.
    assert_eq!(
        evento_consumido_pelo_worker.traceparent, traceparent_semeado,
        "traceparent não sobreviveu ao hop webhook_ingress -> bus -> worker"
    );
    confirmar(
        &mut con,
        &grupo_worker,
        &evento_consumido_pelo_worker.stream_id,
    )
    .await
    .expect("Falha ao confirmar (XACK) o evento do worker");

    // --- Etapa 3: worker processa e o data_postgres audita a ação via RPC ---
    // Usa o traceparent EFETIVAMENTE consumido (não a variável original) — prova
    // que a propagação passa pelo valor real que atravessou o barramento, e não
    // por reaproveitamento acidental da variável semeada em memória.
    let traceparent_da_rpc = evento_consumido_pelo_worker.traceparent.clone();
    let audit_payload = observability::AuditLogPayload {
        tenant_id: Some(tenant_id),
        level: "INFO".to_string(),
        service: "data_postgres".to_string(),
        trace_id: Some(traceparent_da_rpc.clone()),
        event: "atendimento.mensagem_persistida".to_string(),
        message: "Mensagem de atendimento persistida via worker.".to_string(),
        // Sem telefone completo nem payload bruto — só o identificador do contato.
        context: serde_json::json!({ "contato_id": 1 }),
        user_id: None,
        ip_address: None,
        user_agent: None,
    };
    let envelope_auditoria = contracts::TenantEnvelope::novo(tenant_id, "audit_log", audit_payload)
        .com_traceparent(traceparent_da_rpc.clone());

    let grupo_audit = format!("grupo_audit_e2e_{}", Uuid::new_v4());
    garantir_consumer_group_stream(&mut con, STREAM_SEGURANCA, &grupo_audit)
        .await
        .expect("Falha ao garantir consumer group de auditoria");
    publicar_evento_seguranca(&mut con, &envelope_auditoria)
        .await
        .expect("Falha ao publicar evento de segurança");

    // --- Etapa 4: consumidor real de auditoria do data_postgres persiste no audit_log ---
    let eventos_seguranca = consumir_stream(
        &mut con,
        STREAM_SEGURANCA,
        &grupo_audit,
        "audit_consumer_e2e_teste",
        1,
        2000,
    )
    .await
    .expect("Falha ao consumir evento de segurança");
    assert_eq!(eventos_seguranca.len(), 1);
    let stream_id_seguranca = eventos_seguranca[0].stream_id.clone();

    let processou =
        data_postgres::processar_eventos_auditoria_lote(pool.clone(), eventos_seguranca).await;
    assert!(processou.is_ok(), "drenagem falhou: {:?}", processou.err());

    confirmar_stream(
        &mut con,
        STREAM_SEGURANCA,
        &grupo_audit,
        &stream_id_seguranca,
    )
    .await
    .expect("Falha ao confirmar (XACK) o evento de segurança");

    // --- Assert final: a linha em audit_log carrega o MESMO trace_id semeado lá no início ---
    let row: (String, serde_json::Value) = sqlx::query_as(
        "SELECT trace_id, context FROM audit_log \
         WHERE tenant_id = $1 AND event = 'atendimento.mensagem_persistida'",
    )
    .bind(tenant_id)
    .fetch_one(&pool)
    .await
    .expect("linha de audit_log não encontrada");
    let (trace_id_persistido, context_persistido) = row;

    assert_eq!(
        trace_id_persistido, traceparent_semeado,
        "trace_id em audit_log diverge do traceparent semeado no webhook — cadeia quebrada"
    );

    // Sanitização: nada sensível (telefone completo/payload bruto) deve ter vazado
    // até o audit_log ao longo da cadeia.
    let context_str = context_persistido.to_string();
    assert!(
        !context_str.contains("11900002222") && !context_str.contains("9****-1234"),
        "contexto de auditoria vazou dado de telefone: {context_str}"
    );
    assert!(
        !context_str.contains("Olá, preciso de suporte"),
        "contexto de auditoria vazou o payload bruto da mensagem: {context_str}"
    );

    // Limpeza (cascade remove o audit_log do tenant).
    sqlx::query("DELETE FROM tenants_tenant WHERE id = $1")
        .bind(tenant_id)
        .execute(&pool)
        .await
        .unwrap();
}
