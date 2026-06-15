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
    if args.get(1).map(String::as_str) == Some("delete-superuser") {
        return cli::delete_superuser(&args).await;
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

#[cfg(test)]
mod tests {
    use super::*;
    use contracts::{Envelope, MessageKind};
    use std::time::Duration;
    use transport::runtime::{Endpoint, Server};
    use uuid::Uuid;

    static CONTROL_PLANE_MUTEX: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

    #[tokio::test]
    async fn test_handler_register_tenant_sucesso() {
        let _guard = CONTROL_PLANE_MUTEX.lock().await;
        let pg_addr = "tcp://127.0.0.1:29210";
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);

        let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
        let pg_server = Server::new(pg_endpoint, "flatbuffers").route("CreateTenant", |env| {
            Box::pin(async move {
                let reply = serde_json::json!({
                    "status": "success",
                    "tenant": { "id": Uuid::new_v4().to_string() }
                });
                Envelope {
                    kind: MessageKind::Reply as i32,
                    method: "CreateTenantReply".to_string(),
                    payload: serde_json::to_vec(&reply).unwrap(),
                    ..env
                }
            })
        });
        let pg_handle = tokio::spawn(async move {
            pg_server.run().await.unwrap();
        });
        tokio::time::sleep(Duration::from_millis(150)).await;

        let env = Envelope {
            tenant_id: Uuid::nil().to_string(),
            method: "RegisterTenant".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({ "name": "Tenant Teste" })).unwrap(),
            traceparent: "00-trace-cp-01-01".to_string(),
            ..Default::default()
        };

        let resp = handler_register_tenant(env).await;
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        assert_eq!(resp.method, "RegisterTenantReply");
        let resp_payload: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(
            resp_payload.get("status").and_then(|v| v.as_str()),
            Some("success")
        );

        pg_handle.abort();
    }

    #[tokio::test]
    async fn test_handler_register_tenant_erro_rpc_data_postgres() {
        let _guard = CONTROL_PLANE_MUTEX.lock().await;
        let pg_addr = "tcp://127.0.0.1:29211";
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);

        let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
        let pg_server = Server::new(pg_endpoint, "flatbuffers").route("CreateTenant", |env| {
            Box::pin(async move {
                let error_env = contracts::ErrorEnvelope {
                    code: "CONFLICT".to_string(),
                    message: "Tenant já existe".to_string(),
                    ..Default::default()
                };
                Envelope {
                    kind: MessageKind::Error as i32,
                    method: "CreateTenantReply".to_string(),
                    error: Some(error_env),
                    ..env
                }
            })
        });
        let pg_handle = tokio::spawn(async move {
            pg_server.run().await.unwrap();
        });
        tokio::time::sleep(Duration::from_millis(150)).await;

        let env = Envelope {
            tenant_id: Uuid::nil().to_string(),
            method: "RegisterTenant".to_string(),
            payload: b"{}".to_vec(),
            traceparent: "00-trace-cp-02-01".to_string(),
            ..Default::default()
        };

        let resp = handler_register_tenant(env).await;
        // data_postgres retorna erro → control_plane repassa o envelope de erro
        assert_eq!(resp.kind, MessageKind::Error as i32);
        assert_eq!(resp.method, "RegisterTenantReply");

        pg_handle.abort();
    }

    #[tokio::test]
    async fn test_handler_register_tenant_sem_conexao_data_postgres() {
        let _guard = CONTROL_PLANE_MUTEX.lock().await;
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", "tcp://127.0.0.1:29219");

        let env = Envelope {
            tenant_id: Uuid::nil().to_string(),
            method: "RegisterTenant".to_string(),
            payload: b"{}".to_vec(),
            traceparent: "00-trace-cp-03-01".to_string(),
            ..Default::default()
        };

        let resp = handler_register_tenant(env).await;
        assert_eq!(resp.kind, MessageKind::Error as i32);
        assert_eq!(resp.method, "RegisterTenantReply");
        let err = resp.error.unwrap();
        assert!(err.message.contains("falha ao conectar ao data_postgres"));
    }
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
