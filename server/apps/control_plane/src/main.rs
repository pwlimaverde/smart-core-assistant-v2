//! Serviço control_plane: Painel administrativo e tarefas de back office.

mod cli;

use contracts::{Envelope, MessageKind, TenantEnvelope};
use std::time::Duration;
use transport::Server;
use uuid::Uuid;

#[derive(Clone)]
struct AppState {
    redis_conn: redis::aio::ConnectionManager,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // 1. Inicializa observabilidade
    observability::init_telemetry("control_plane", "production")
        .map_err(|e| anyhow::anyhow!(e.to_string()))?;
    // Panic em task de background mata so a task: o processo segue vivo e a
    // funcionalidade some sem deixar rastro. O hook garante o registro estruturado.
    observability::instalar_hook_de_panic("control_plane");

    // Subcomando administrativo de bootstrap: `control_plane create-superuser ...`.
    let args: Vec<String> = std::env::args().collect();
    if args.get(1).map(String::as_str) == Some("create-superuser") {
        return cli::create_superuser(&args).await;
    }
    if args.get(1).map(String::as_str) == Some("delete-superuser") {
        return cli::delete_superuser(&args).await;
    }

    tracing::info!("Iniciando serviço control_plane...");

    // Inicializa Redis para publicar auditoria no security:stream
    let redis_url = std::env::var("REDIS_BUS_URL")
        .or_else(|_| std::env::var("REDIS_URL"))
        .unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
    let client = redis::Client::open(redis_url)?;
    let redis_conn = redis::aio::ConnectionManager::new(client).await?;

    let s_disconnect = AppState { redis_conn };

    // 2. Inicia o Servidor RPC síncrono nos 3 de protocolos
    let server = Server::from_env("CONTROL_PLANE")
        .route("RegisterTenant", move |env| {
            Box::pin(async move { handler_register_tenant(env).await })
        })
        .route("TestEvolutionConnection", move |env| {
            Box::pin(async move { handler_test_evolution_connection(env).await })
        })
        .route("AdminBulkDisconnect", move |env| {
            let s = s_disconnect.clone();
            Box::pin(async move { handler_admin_bulk_disconnect(s, env).await })
        });

    tracing::info!("Servidor RPC do control_plane configurado e pronto.");

    // Ver a nota em `data_redis`: SIGTERM precisa ser tratado, senão todo deploy
    // mata o processo no meio do que estava em voo.
    tokio::select! {
        res = server.run() => {
            if let Err(e) = res {
                tracing::error!(
                    "Servidor RPC do control_plane parou com erro crítico: {:?}",
                    e
                );
            }
        }
        _ = observability::aguardar_sinal_de_parada() => {}
    }

    observability::shutdown_telemetry();
    Ok(())
}

fn ok_reply(env: &Envelope, method: &str, payload: serde_json::Value) -> Envelope {
    Envelope {
        kind: MessageKind::Reply as i32,
        method: method.to_string(),
        payload: serde_json::to_vec(&payload).unwrap_or_default(),
        error: None,
        ..env.clone()
    }
}

/// Handler administrativo: encaminha o cadastro do tenant ao `data_postgres` por contrato
/// (RPC `CreateTenant`). O control_plane não acessa o banco diretamente.
#[tracing::instrument(
    skip_all,
    fields(service = "control_plane", rpc = "RegisterTenant", traceparent = %env.traceparent)
)]
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

/// Testa a conexão Evolution de um tenant. Agora direciona para o DATA_WHATSAPP.
#[tracing::instrument(
    skip_all,
    fields(service = "control_plane", rpc = "TestEvolutionConnection", traceparent = %env.traceparent)
)]
async fn handler_test_evolution_connection(env: Envelope) -> Envelope {
    let pg_client = match transport::conectar_cliente("data_postgres").await {
        Ok(c) => c,
        Err(e) => {
            let app_err =
                error_core::AppError::Internal(format!("falha ao conectar ao data_postgres: {e}"));
            let err_env = app_err.to_error_envelope(&env.traceparent, "control_plane");
            return Envelope {
                kind: MessageKind::Error as i32,
                method: "TestEvolutionConnectionReply".to_string(),
                error: Some(err_env),
                ..env
            };
        }
    };

    // 1. Obtém as instâncias do WhatsApp para este tenant
    let req_inst = Envelope {
        kind: MessageKind::Request as i32,
        method: "ListWhatsappInstances".to_string(),
        ..env.clone()
    };

    let list_val = match pg_client.call(req_inst, Duration::from_secs(5)).await {
        Ok(resp) if resp.kind != MessageKind::Error as i32 => {
            serde_json::from_slice::<serde_json::Value>(&resp.payload).unwrap_or_default()
        }
        _ => serde_json::json!({}),
    };

    let first_inst_id = list_val
        .get("instances")
        .and_then(|v| v.as_array())
        .and_then(|arr| arr.first())
        .and_then(|inst| inst.get("id").and_then(|i| i.as_i64()));

    let inst_id = match first_inst_id {
        Some(id) => id,
        None => {
            let app_err = error_core::AppError::Validation(
                "Nenhuma instância ativa do WhatsApp configurada para este tenant.".to_string(),
            );
            let err_env = app_err.to_error_envelope(&env.traceparent, "control_plane");
            return Envelope {
                kind: MessageKind::Error as i32,
                method: "TestEvolutionConnectionReply".to_string(),
                error: Some(err_env),
                ..env
            };
        }
    };

    // 2. Conecta ao DATA_WHATSAPP para verificar o status da instância
    let wa_client = match transport::conectar_cliente("data_whatsapp").await {
        Ok(c) => c,
        Err(e) => {
            let app_err =
                error_core::AppError::Internal(format!("falha ao conectar ao data_whatsapp: {e}"));
            let err_env = app_err.to_error_envelope(&env.traceparent, "control_plane");
            return Envelope {
                kind: MessageKind::Error as i32,
                method: "TestEvolutionConnectionReply".to_string(),
                error: Some(err_env),
                ..env
            };
        }
    };

    let req_status = Envelope {
        kind: MessageKind::Request as i32,
        method: "GetWhatsappInstanceStatus".to_string(),
        payload: serde_json::to_vec(&serde_json::json!({ "id": inst_id })).unwrap(),
        ..env.clone()
    };

    match wa_client.call(req_status, Duration::from_secs(10)).await {
        Ok(resp) if resp.kind != MessageKind::Error as i32 => {
            let val: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap_or_default();
            let status = val
                .get("status")
                .and_then(|v| v.as_str())
                .unwrap_or("unknown");

            // Map para o formato de retorno esperado pelo grpc_web
            let state_str = match status {
                "connected" => "open",
                "disconnected" => "close",
                "connecting" => "connecting",
                _ => "error",
            };

            let reply = serde_json::json!({
                "status": state_str,
                "error_message": ""
            });

            Envelope {
                kind: MessageKind::Reply as i32,
                method: "TestEvolutionConnectionReply".to_string(),
                payload: serde_json::to_vec(&reply).unwrap(),
                ..env
            }
        }
        _ => {
            let reply = serde_json::json!({
                "status": "error",
                "error_message": "Falha ao obter status da instância"
            });
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "TestEvolutionConnectionReply".to_string(),
                payload: serde_json::to_vec(&reply).unwrap(),
                ..env
            }
        }
    }
}

/// Admin Bulk Disconnect Handler
#[tracing::instrument(
    skip_all,
    fields(service = "control_plane", rpc = "AdminBulkDisconnect", traceparent = %env.traceparent)
)]
async fn handler_admin_bulk_disconnect(mut state: AppState, env: Envelope) -> Envelope {
    let payload: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(e) => {
            let app_err = error_core::AppError::Validation(e.to_string());
            let err_env = app_err.to_error_envelope(&env.traceparent, "control_plane");
            return Envelope {
                kind: MessageKind::Error as i32,
                method: "AdminBulkDisconnectReply".to_string(),
                error: Some(err_env),
                ..env
            };
        }
    };

    let target_tenant = payload
        .get("tenant_id")
        .and_then(|v| v.as_str())
        .and_then(|s| Uuid::parse_str(s).ok())
        .filter(|id| !id.is_nil());

    let wa_client = match transport::conectar_cliente("data_whatsapp").await {
        Ok(c) => c,
        Err(e) => {
            let app_err =
                error_core::AppError::Internal(format!("falha ao conectar ao data_whatsapp: {e}"));
            let err_env = app_err.to_error_envelope(&env.traceparent, "control_plane");
            return Envelope {
                kind: MessageKind::Error as i32,
                method: "AdminBulkDisconnectReply".to_string(),
                error: Some(err_env),
                ..env
            };
        }
    };

    let req = Envelope {
        kind: MessageKind::Request as i32,
        method: "AdminBulkDisconnectInstances".to_string(),
        payload: serde_json::to_vec(&serde_json::json!({
            "tenant_id": target_tenant.map(|t| t.to_string())
        }))
        .unwrap(),
        ..env.clone()
    };

    match wa_client.call(req, Duration::from_secs(15)).await {
        Ok(resp) => {
            if resp.kind == MessageKind::Error as i32 {
                return Envelope {
                    method: "AdminBulkDisconnectReply".to_string(),
                    ..resp
                };
            }

            let val: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap_or_default();
            let count = val.get("count").and_then(|v| v.as_i64()).unwrap_or(0);
            let scope = val
                .get("scope")
                .and_then(|v| v.as_str())
                .unwrap_or("global")
                .to_string();

            // Auditoria do admin disconnect. O consumidor (data_postgres) desserializa
            // toda mensagem deste stream como observability::AuditLogPayload — um
            // json!({}) solto (formato antigo aqui) falha com "missing field `level`"
            // e o evento é descartado em silêncio, nunca gravado em audit_log.
            let audit_payload = observability::AuditLogPayload {
                tenant_id: target_tenant,
                level: "WARN".to_string(),
                service: "control_plane".to_string(),
                trace_id: Some(env.traceparent.clone()),
                event: "whatsapp.admin.bulk_disconnect".to_string(),
                message: format!("Desconexão em massa de {count} instância(s) WhatsApp ({scope})"),
                context: serde_json::json!({ "scope": scope, "count": count }),
                user_id: (env.auth_user_id > 0).then_some(env.auth_user_id),
                ip_address: None,
                user_agent: None,
            };
            let audit_event = TenantEnvelope::novo(
                target_tenant.unwrap_or_else(Uuid::nil),
                "security.audit",
                audit_payload,
            )
            .com_traceparent(env.traceparent.clone());

            let _ = transport::bus::publicar_evento_seguranca(&mut state.redis_conn, &audit_event)
                .await;

            ok_reply(
                &env,
                "AdminBulkDisconnectReply",
                serde_json::json!({
                    "count": count,
                    "scope": scope
                }),
            )
        }
        Err(e) => {
            let app_err = error_core::AppError::Internal(format!(
                "RPC AdminBulkDisconnectInstances falhou: {e}"
            ));
            let err_env = app_err.to_error_envelope(&env.traceparent, "control_plane");
            Envelope {
                kind: MessageKind::Error as i32,
                method: "AdminBulkDisconnectReply".to_string(),
                error: Some(err_env),
                ..env
            }
        }
    }
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

    async fn fake_bus(porta: u16) -> redis::aio::ConnectionManager {
        let listener = tokio::net::TcpListener::bind(("127.0.0.1", porta))
            .await
            .unwrap();
        tokio::spawn(async move {
            loop {
                let Ok((mut socket, _)) = listener.accept().await else {
                    break;
                };
                tokio::spawn(async move {
                    use tokio::io::{AsyncReadExt, AsyncWriteExt};
                    let mut buf = [0u8; 4096];
                    while let Ok(n) = socket.read(&mut buf).await {
                        if n == 0 {
                            break;
                        }
                        let req = String::from_utf8_lossy(&buf[..n]);
                        for parte in req.split('*') {
                            if parte.is_empty() {
                                continue;
                            }
                            if parte.to_uppercase().contains("PING") {
                                let _ = socket.write_all(b"+PONG\r\n").await;
                            } else {
                                let _ = socket.write_all(b"+OK\r\n").await;
                            }
                        }
                    }
                });
            }
        });
        let client = redis::Client::open(format!("redis://127.0.0.1:{porta}")).unwrap();
        redis::aio::ConnectionManager::new(client).await.unwrap()
    }

    #[tokio::test]
    async fn test_handler_test_evolution_connection_sucesso() {
        let _guard = CONTROL_PLANE_MUTEX.lock().await;
        let pg_addr = "tcp://127.0.0.1:29222";
        let wa_addr = "tcp://127.0.0.1:29220";
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
        std::env::set_var("SMARTCORE_DATA_WHATSAPP_ENDPOINT", wa_addr);

        let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
        let pg_server =
            Server::new(pg_endpoint, "flatbuffers").route("ListWhatsappInstances", |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({
                        "instances": [
                            { "id": 42 }
                        ]
                    });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "ListWhatsappInstancesReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            });
        let pg_handle = tokio::spawn(async move {
            pg_server.run().await.unwrap();
        });

        let wa_endpoint = Endpoint::parse(wa_addr).unwrap();
        let wa_server =
            Server::new(wa_endpoint, "flatbuffers").route("GetWhatsappInstanceStatus", |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({
                        "status": "connected"
                    });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "GetWhatsappInstanceStatusReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            });
        let wa_handle = tokio::spawn(async move {
            wa_server.run().await.unwrap();
        });
        tokio::time::sleep(Duration::from_millis(150)).await;

        let env = Envelope {
            tenant_id: Uuid::nil().to_string(),
            method: "TestEvolutionConnection".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({ "id": 42 })).unwrap(),
            traceparent: "00-trace-cp-wa-01".to_string(),
            ..Default::default()
        };

        let resp = handler_test_evolution_connection(env).await;
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        assert_eq!(resp.method, "TestEvolutionConnectionReply");
        let resp_payload: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(
            resp_payload.get("status").and_then(|v| v.as_str()),
            Some("open")
        );

        wa_handle.abort();
        pg_handle.abort();
    }

    #[tokio::test]
    async fn test_handler_admin_bulk_disconnect_sucesso() {
        let _guard = CONTROL_PLANE_MUTEX.lock().await;
        let wa_addr = "tcp://127.0.0.1:29221";
        std::env::set_var("SMARTCORE_DATA_WHATSAPP_ENDPOINT", wa_addr);

        let wa_endpoint = Endpoint::parse(wa_addr).unwrap();
        let wa_server =
            Server::new(wa_endpoint, "flatbuffers").route("AdminBulkDisconnectInstances", |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({
                        "count": 5,
                        "scope": "global"
                    });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "AdminBulkDisconnectInstancesReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            });
        let wa_handle = tokio::spawn(async move {
            wa_server.run().await.unwrap();
        });

        let redis_conn = fake_bus(29255).await;
        let state = AppState { redis_conn };

        let env = Envelope {
            tenant_id: Uuid::nil().to_string(),
            method: "AdminBulkDisconnect".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({ "tenant_id": null })).unwrap(),
            traceparent: "00-trace-cp-wa-02".to_string(),
            ..Default::default()
        };

        tokio::time::sleep(Duration::from_millis(150)).await;

        let resp = handler_admin_bulk_disconnect(state, env).await;
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let resp_payload: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(resp_payload.get("count").and_then(|v| v.as_i64()), Some(5));

        wa_handle.abort();
    }
}
