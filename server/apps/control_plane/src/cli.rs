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
        auth_user_id: 0,
        auth_scopes: vec![],
        auth_is_superuser: false,
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

/// Exclui um superusuário de forma **interativa**: lista os superusuários, pede a
/// seleção por número e uma confirmação forte (digitar o username). Cliente fino:
/// a listagem e a exclusão são feitas pelo `data_postgres` via RPC.
pub async fn delete_superuser(_args: &[String]) -> anyhow::Result<()> {
    let client = transport::conectar_cliente("data_postgres")
        .await
        .context("falha ao conectar no data_postgres (o serviço está no ar?)")?;

    // 1. Lista os superusuários.
    let lista_resp = client
        .call(
            montar_envelope("ListSuperusers", serde_json::json!({}))?,
            Duration::from_secs(15),
        )
        .await
        .context("falha na chamada RPC ListSuperusers")?;
    if lista_resp.kind == MessageKind::Error as i32 {
        bail!(
            "falha ao listar superusuários: {}",
            msg_erro(lista_resp.error)
        );
    }
    let lista_json: serde_json::Value =
        serde_json::from_slice(&lista_resp.payload).unwrap_or_default();
    let superusers = lista_json
        .get("superusers")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();

    if superusers.is_empty() {
        println!("Nenhum superusuário cadastrado.");
        return Ok(());
    }

    println!("Superusuários cadastrados:");
    for (i, u) in superusers.iter().enumerate() {
        let id = u.get("id").and_then(|v| v.as_i64()).unwrap_or_default();
        let username = u.get("username").and_then(|v| v.as_str()).unwrap_or("");
        let email = u.get("email").and_then(|v| v.as_str()).unwrap_or("");
        let ativo = u
            .get("is_active")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let estado = if ativo { "ativo" } else { "inativo" };
        println!("  [{}] id={id} · {username} · {email} · {estado}", i + 1);
    }

    // 2. Seleção por número.
    let escolha = ler_linha("\nNúmero para EXCLUIR (Enter para cancelar): ")?;
    let escolha = escolha.trim();
    if escolha.is_empty() {
        println!("Cancelado.");
        return Ok(());
    }
    let idx = match escolha.parse::<usize>() {
        Ok(n) if n >= 1 && n <= superusers.len() => n - 1,
        _ => {
            println!("Seleção inválida. Cancelado.");
            return Ok(());
        }
    };
    let alvo = &superusers[idx];
    let alvo_id = alvo.get("id").and_then(|v| v.as_i64()).unwrap_or_default();
    let alvo_username = alvo
        .get("username")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    // 3. Confirmação forte: digitar o username.
    let confirm = ler_linha(&format!(
        "Para confirmar a EXCLUSÃO definitiva, digite o username '{alvo_username}': "
    ))?;
    if confirm.trim() != alvo_username {
        println!("Confirmação não confere. Cancelado.");
        return Ok(());
    }

    // 4. Exclui via RPC.
    let del_resp = client
        .call(
            montar_envelope("DeleteSuperuser", serde_json::json!({ "id": alvo_id }))?,
            Duration::from_secs(15),
        )
        .await
        .context("falha na chamada RPC DeleteSuperuser")?;
    if del_resp.kind == MessageKind::Error as i32 {
        bail!(
            "falha ao excluir superusuário: {}",
            msg_erro(del_resp.error)
        );
    }
    println!("Superusuário '{alvo_username}' (id={alvo_id}) excluído com sucesso.");
    Ok(())
}

/// Monta um Envelope de requisição RPC com contexto global (superuser não tem tenant).
fn montar_envelope(method: &str, payload: serde_json::Value) -> anyhow::Result<Envelope> {
    Ok(Envelope {
        tenant_id: Uuid::nil().to_string(),
        schema_version: 1,
        message_id: Uuid::now_v7().to_string(),
        causation_id: String::new(),
        traceparent: String::new(),
        occurred_at: chrono::Utc::now().timestamp_millis(),
        kind: MessageKind::Request as i32,
        method: method.to_string(),
        payload: serde_json::to_vec(&payload).context("falha ao serializar o payload")?,
        error: None,
        auth_user_id: 0,
        auth_scopes: vec![],
        auth_is_superuser: false,
    })
}

/// Extrai a mensagem detalhada de um ErrorEnvelope (ferramenta admin local).
fn msg_erro(err: Option<contracts::ErrorEnvelope>) -> String {
    err.map(|e| {
        if !e.message.is_empty() {
            e.message
        } else {
            e.user_message_fallback
        }
    })
    .unwrap_or_else(|| "erro desconhecido".to_string())
}

/// Lê uma linha do stdin exibindo um prompt (modo interativo).
fn ler_linha(prompt: &str) -> anyhow::Result<String> {
    use std::io::Write;
    print!("{prompt}");
    std::io::stdout().flush().ok();
    let mut linha = String::new();
    std::io::stdin().read_line(&mut linha)?;
    Ok(linha)
}

#[cfg(test)]
mod tests {
    use super::*;
    use contracts::{ErrorEnvelope, MessageKind};

    #[test]
    fn test_resolver_prioriza_flag_sobre_env() {
        let args = vec![
            "programa".to_string(),
            "--username".to_string(),
            "usuario_via_flag".to_string(),
        ];
        std::env::set_var("_TEST_SUPERUSER_USERNAME", "usuario_via_env");
        let resultado = resolver("--username", "_TEST_SUPERUSER_USERNAME", &args);
        assert_eq!(resultado, Some("usuario_via_flag".to_string()));
        std::env::remove_var("_TEST_SUPERUSER_USERNAME");
    }

    #[test]
    fn test_resolver_usa_env_quando_flag_ausente() {
        let args = vec!["programa".to_string()];
        std::env::set_var("_TEST_SUPERUSER_EMAIL", "admin@teste.com");
        let resultado = resolver("--email", "_TEST_SUPERUSER_EMAIL", &args);
        assert_eq!(resultado, Some("admin@teste.com".to_string()));
        std::env::remove_var("_TEST_SUPERUSER_EMAIL");
    }

    #[test]
    fn test_resolver_retorna_none_sem_flag_e_sem_env() {
        let args = vec!["programa".to_string()];
        std::env::remove_var("_TEST_SUPERUSER_PASSWORD");
        let resultado = resolver("--password", "_TEST_SUPERUSER_PASSWORD", &args);
        assert!(resultado.is_none());
    }

    #[test]
    fn test_resolver_env_vazia_retorna_none() {
        let args = vec!["programa".to_string()];
        std::env::set_var("_TEST_SUPERUSER_USERNAME2", "");
        let resultado = resolver("--username", "_TEST_SUPERUSER_USERNAME2", &args);
        assert!(resultado.is_none());
        std::env::remove_var("_TEST_SUPERUSER_USERNAME2");
    }

    #[test]
    fn test_montar_envelope_campos_corretos() {
        let payload = serde_json::json!({ "nome": "Teste", "email": "a@b.com" });
        let env = montar_envelope("CreateSuperuser", payload.clone()).unwrap();

        assert_eq!(env.kind, MessageKind::Request as i32);
        assert_eq!(env.method, "CreateSuperuser");
        assert_eq!(env.schema_version, 1);
        assert_eq!(env.auth_user_id, 0);
        assert!(!env.auth_is_superuser);
        assert!(env.error.is_none());

        let payload_de_volta: serde_json::Value = serde_json::from_slice(&env.payload).unwrap();
        assert_eq!(payload_de_volta, payload);
    }

    #[test]
    fn test_msg_erro_usa_message_quando_preenchido() {
        let err = ErrorEnvelope {
            code: "ERRO".to_string(),
            message: "mensagem detalhada do admin".to_string(),
            user_message_fallback: "fallback".to_string(),
            ..Default::default()
        };
        assert_eq!(msg_erro(Some(err)), "mensagem detalhada do admin");
    }

    #[test]
    fn test_msg_erro_usa_fallback_quando_message_vazio() {
        let err = ErrorEnvelope {
            code: "ERRO".to_string(),
            message: "".to_string(),
            user_message_fallback: "mensagem ao usuário".to_string(),
            ..Default::default()
        };
        assert_eq!(msg_erro(Some(err)), "mensagem ao usuário");
    }

    #[test]
    fn test_msg_erro_retorna_padrao_quando_none() {
        assert_eq!(msg_erro(None), "erro desconhecido");
    }
}
