//! Serviço runtime_api: Borda de API cliente servindo FlatBuffers e fallback gRPC.
//! 
//! Expõe rotas RPC de autenticação (Login) e streaming conceitual de realtime (StreamAtendimentos).

use uuid::Uuid;
use contracts::{Envelope, MessageKind};
use transport::Server;

#[derive(Clone)]
struct AppState {}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // 1. Inicializa observabilidade
    observability::init_telemetry("runtime_api", "production")
        .map_err(|e| anyhow::anyhow!(e.to_string()))?;
    tracing::info!("Iniciando serviço runtime_api...");

    let _state = AppState {};

    // 2. Inicia o Servidor RPC síncrono nos 3 protocolos
    let server = Server::from_env("RUNTIME_API")
        .route("Login", move |env| {
            Box::pin(async move { handler_login(env).await })
        })
        .route("StreamAtendimentos", move |env| {
            Box::pin(async move { handler_stream_atendimentos(env).await })
        });

    tracing::info!("Servidor RPC da runtime_api configurado e pronto.");
    
    if let Err(e) = server.run().await {
        tracing::error!("Servidor RPC da runtime_api parou com erro crítico: {:?}", e);
    }

    Ok(())
}

/// Handler de Login: extrai as credenciais e chama a lógica de negócio na crate application
async fn handler_login(env: Envelope) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(_) => serde_json::json!({}),
    };
    
    let email = payload_json.get("email").and_then(|v| v.as_str()).unwrap_or("");
    let password = payload_json.get("password").and_then(|v| v.as_str()).unwrap_or("");

    let tenant_id = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());
    let ctx = application::RequestContext {
        tenant_id,
        user_id: 0, // Identificador de usuário não autenticado na entrada de login
        user_scopes: vec![],
        traceparent: env.traceparent.clone(),
    };

    match application::auth::login::login(&ctx, email, password).await {
        Ok(tokens) => {
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "LoginReply".to_string(),
                payload: serde_json::to_vec(&tokens).unwrap_or_default(),
                error: None,
                ..env
            }
        }
        Err(err) => {
            let err_env = err.to_error_envelope(&env.traceparent, "runtime_api");
            Envelope {
                kind: MessageKind::Error as i32,
                method: "LoginReply".to_string(),
                error: Some(err_env),
                ..env
            }
        }
    }
}

/// Handler de StreamAtendimentos: retorna um snapshot de atendimentos mockados de realtime
async fn handler_stream_atendimentos(env: Envelope) -> Envelope {
    // Simula atendimentos retornados via FlatBuffers/gRPC payload
    let atendimentos = serde_json::json!({
        "atendimentos": [
            {
                "id": 1,
                "cliente": "João Silva",
                "status": "em_atendimento",
                "ultima_mensagem": "Olá, preciso de suporte."
            },
            {
                "id": 2,
                "cliente": "Maria Souza",
                "status": "aguardando",
                "ultima_mensagem": "Aguardando resposta."
            }
        ]
    });

    Envelope {
        kind: MessageKind::Reply as i32,
        method: "StreamAtendimentosReply".to_string(),
        payload: serde_json::to_vec(&atendimentos).unwrap_or_default(),
        error: None,
        ..env
    }
}
