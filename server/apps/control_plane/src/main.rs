//! Serviço control_plane: Painel administrativo e tarefas de back office.

use contracts::{Envelope, MessageKind};
use transport::Server;
use uuid::Uuid;

#[derive(Clone)]
struct AppState {}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // 1. Inicializa observabilidade
    observability::init_telemetry("control_plane", "production")
        .map_err(|e| anyhow::anyhow!(e.to_string()))?;
    tracing::info!("Iniciando serviço control_plane...");

    let _state = AppState {};

    // 2. Inicia o Servidor RPC síncrono nos 3 de protocolos
    let server = Server::from_env("CONTROL_PLANE").route("RegisterTenant", move |env| {
        Box::pin(async move { handler_register_tenant(env).await })
    });

    tracing::info!("Servidor RPC do control_plane configurado e pronto.");

    if let Err(e) = server.run().await {
        tracing::error!(
            "Servidor RPC do control_plane parou com erro crítico: {:?}",
            e
        );
    }

    Ok(())
}

/// Handler administrativo que simula o cadastro de um novo Tenant
async fn handler_register_tenant(env: Envelope) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(_) => serde_json::json!({}),
    };

    let tenant_name = payload_json
        .get("name")
        .and_then(|v| v.as_str())
        .unwrap_or("Novo Tenant");
    let tenant_id = Uuid::new_v4();

    tracing::info!(
        tenant_id = %tenant_id,
        tenant_name = %tenant_name,
        "Painel Administrativo: registrando novo inquilino global."
    );

    let res = serde_json::json!({
        "status": "success",
        "tenant_id": tenant_id.to_string(),
        "name": tenant_name,
    });

    Envelope {
        kind: MessageKind::Reply as i32,
        method: "RegisterTenantReply".to_string(),
        payload: serde_json::to_vec(&res).unwrap_or_default(),
        error: None,
        ..env
    }
}
