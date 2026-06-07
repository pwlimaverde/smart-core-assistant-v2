//! Subcomando administrativo `create-superuser` do `control_plane`.
//!
//! Cliente **fino**: lê os dados (flags ou env), monta o Envelope e envia via
//! `transport` para o serviço `data_postgres` (RPC `CreateSuperuser`). Não conecta
//! no banco nem abre túnel — a infra do Postgres é a única porta de acesso ao banco
//! e é quem trata (hash), grava e dispara a auditoria. O CLI apenas executa e
//! imprime a confirmação devolvida.

use anyhow::{bail, Context};
use contracts::{Envelope, MessageKind};
use std::time::Duration;
use uuid::Uuid;

/// Executa o cadastro do superusuário via RPC e imprime a confirmação.
///
/// Lê `username`/`email`/`password` das flags `--username/--email/--password` ou,
/// na ausência delas, das variáveis `SUPERUSER_USERNAME/SUPERUSER_EMAIL/SUPERUSER_PASSWORD`.
pub async fn create_superuser(args: &[String]) -> anyhow::Result<()> {
    let username = resolver("--username", "SUPERUSER_USERNAME", args)
        .context("informe o usuário via --username ou SUPERUSER_USERNAME")?;
    let email = resolver("--email", "SUPERUSER_EMAIL", args).unwrap_or_default();
    let password = resolver("--password", "SUPERUSER_PASSWORD", args)
        .context("informe a senha via --password ou SUPERUSER_PASSWORD")?;

    if username.trim().is_empty() {
        bail!("o username não pode ser vazio");
    }
    if password.is_empty() {
        bail!("a senha não pode ser vazia");
    }

    // `password` segue em claro apenas pelo transporte local (UDS) até a infra,
    // que faz o hash. Nunca é logada.
    let payload = serde_json::json!({
        "username": username,
        "email": email,
        "password": password,
    });

    let req = Envelope {
        tenant_id: Uuid::nil().to_string(),
        schema_version: 1,
        message_id: Uuid::now_v7().to_string(),
        causation_id: String::new(),
        traceparent: String::new(),
        occurred_at: chrono::Utc::now().timestamp_millis(),
        kind: MessageKind::Request as i32,
        method: "CreateSuperuser".to_string(),
        payload: serde_json::to_vec(&payload).context("falha ao serializar o payload")?,
        error: None,
    };

    println!("Enviando cadastro do superusuário ao data_postgres...");
    let client = transport::conectar_cliente("data_postgres")
        .await
        .context("falha ao conectar no data_postgres (o serviço está no ar?)")?;
    let resp = client
        .call(req, Duration::from_secs(15))
        .await
        .context("falha na chamada RPC CreateSuperuser")?;

    if resp.kind == MessageKind::Error as i32 {
        // Ferramenta administrativa local: mostra a mensagem detalhada (campo `message`),
        // que já vem sem segredos (ex.: "Conflito de estado: já existe um usuário ...").
        let msg = resp
            .error
            .map(|e| {
                if !e.message.is_empty() {
                    e.message
                } else {
                    e.user_message_fallback
                }
            })
            .unwrap_or_else(|| "erro desconhecido".to_string());
        bail!("falha ao criar superusuário: {msg}");
    }

    let reply: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap_or_default();
    match reply.get("status").and_then(|v| v.as_str()).unwrap_or("") {
        "created" => {
            let id = reply.get("id").and_then(|v| v.as_i64()).unwrap_or_default();
            println!("Superusuário '{username}' criado com sucesso (id={id}).");
        }
        _ => {
            println!("Resposta do data_postgres: {reply}");
        }
    }
    Ok(())
}

/// Lê o valor de uma flag `--nome valor` dos argumentos; se ausente, cai na env var.
fn resolver(flag: &str, env_var: &str, args: &[String]) -> Option<String> {
    if let Some(pos) = args.iter().position(|a| a == flag) {
        if let Some(valor) = args.get(pos + 1) {
            return Some(valor.clone());
        }
    }
    std::env::var(env_var).ok().filter(|v| !v.is_empty())
}
