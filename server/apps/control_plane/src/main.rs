//! Serviço control_plane: Painel administrativo e tarefas de back office.

mod cli;

use contracts::{Envelope, MessageKind};
use std::time::Duration;
use transport::Server;

#[derive(Clone)]
struct AppState {}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // 1. Inicializa observabilidade
    observability::init_telemetry("control_plane", "production")
        .map_err(|e| anyhow::anyhow!(e.to_string()))?;

    // Subcomando administrativo de bootstrap: `control_plane create-superuser ...`.
    // Cliente fino que fala com o data_postgres via RPC; executa e encerra.
    let args: Vec<String> = std::env::args().collect();
    if args.get(1).map(String::as_str) == Some("create-superuser") {
        return cli::create_superuser(&args).await;
    }

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

/// Handler administrativo: encaminha o cadastro do tenant ao `data_postgres` por contrato
/// (RPC `CreateTenant`). O control_plane não acessa o banco diretamente.
async fn handler_register_tenant(env: Envelope) -> Envelope {
    let pg_client = match transport::conectar_cliente("data_postgres").await {
        Ok(c) => c,
        Err(e) => {
            let app_err =
                error_core::AppError::Internal(format!("falha ao conectar ao data_postgres: {e}"));
            let err_env = app_err.to_error_envelope(&env.traceparent, "control_plane");
            return Envelope {
                kind: MessageKind::Error as i32,
                method: "RegisterTenantReply".to_string(),
                error: Some(err_env),
                ..env
            };
        }
    };

    // Repassa o payload do cliente reescrevendo apenas o método para o contrato do data_postgres.
    let req = Envelope {
        kind: MessageKind::Request as i32,
        method: "CreateTenant".to_string(),
        ..env.clone()
    };

    match pg_client.call(req, Duration::from_secs(5)).await {
        Ok(resp) => Envelope {
            method: "RegisterTenantReply".to_string(),
            ..resp
        },
        Err(e) => {
            let app_err = error_core::AppError::Internal(format!("RPC CreateTenant falhou: {e}"));
            let err_env = app_err.to_error_envelope(&env.traceparent, "control_plane");
            Envelope {
                kind: MessageKind::Error as i32,
                method: "RegisterTenantReply".to_string(),
                error: Some(err_env),
                ..env
            }
        }
    }
}
