//! Handlers dos consentimentos OAuth 2.1 dos clientes MCP (N13.2).
//!
//! Seis rotas, dois públicos distintos:
//!
//! * `ListMcpGrants` / `RevokeMcpGrant` vêm da **borda** (`runtime_api`), a
//!   pedido do usuário na tela "Aplicativos conectados";
//! * `RegisterMcpGrant`, `SetMcpGrantRefreshHash`, `GetMcpGrantComSegredo` e
//!   `RevokeMcpGrantPorReuso` vêm do **authorization server** (`control_plane`),
//!   durante o fluxo OAuth.
//!
//! Nenhum segredo entra em payload de resposta ou em auditoria: o hash do
//! refresh só sai por `GetMcpGrantComSegredo`, que é chamado exclusivamente pelo
//! `control_plane` dentro da rede `internal`, e mesmo ali sob o nome explícito de
//! "com segredo" — para que ninguém o use por engano num caminho voltado ao
//! usuário.

use contracts::Envelope;
use uuid::Uuid;

use crate::ports;
use crate::{contexto_do_envelope, erro, ok_reply};

fn payload_de(env: &Envelope) -> serde_json::Value {
    serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}))
}

fn uuid_do_payload(payload: &serde_json::Value, chave: &str) -> Option<Uuid> {
    payload
        .get(chave)
        .and_then(|v| v.as_str())
        .and_then(|s| Uuid::parse_str(s).ok())
}

fn grant_para_json(g: &infrastructure_postgres::McpGrant) -> serde_json::Value {
    serde_json::json!({
        "id": g.id.to_string(),
        "client_id": g.client_id,
        "client_name": g.client_name,
        "redirect_uri": g.redirect_uri,
        "scopes": g.scopes,
        "last_used_at": g.last_used_at.map(|d| d.timestamp_millis()).unwrap_or(0),
        "created_at": g.created_at.timestamp_millis(),
        "user_id": g.user_id,
        "tenant_id": g.tenant_id.to_string(),
    })
}

/// Grava o consentimento aprovado na tela do AS.
///
/// Auditado como evento crítico: concessão de permissão é exatamente o que 08
/// §4.2 manda registrar. O contexto leva `client_id`, `client_name` e os escopos
/// — nunca o `code`, o `code_verifier` ou qualquer token.
pub async fn handler_register_mcp_grant(
    store: &dyn ports::McpGrantStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload = payload_de(&env);
    let ctx = contexto_do_envelope(&env);

    let client_id = payload
        .get("client_id")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    let client_name = payload
        .get("client_name")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    let redirect_uri = payload
        .get("redirect_uri")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();

    if client_id.is_empty() || redirect_uri.is_empty() {
        return erro(
            error_core::AppError::Validation(
                "client_id e redirect_uri são obrigatórios".to_string(),
            ),
            &env,
        );
    }
    if ctx.user_id <= 0 {
        return erro(
            error_core::AppError::Auth("consentimento exige usuário autenticado".to_string()),
            &env,
        );
    }

    let escopos: Vec<String> = payload
        .get("scopes")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str().map(str::to_string))
                .collect()
        })
        .unwrap_or_default();

    let created_ip = payload
        .get("created_ip")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .map(str::to_string);

    match store
        .registrar(
            &ctx,
            client_id,
            client_name,
            redirect_uri,
            &escopos,
            created_ip,
        )
        .await
    {
        Ok(grant) => {
            // INFO, não WARN: conceder consentimento é ação deliberada do dono do
            // dado. O que merece WARN é o reuso de refresh, mais abaixo.
            audit
                .publish_security(
                    &env.traceparent,
                    Some(grant.tenant_id),
                    "INFO",
                    "oauth.consentimento_concedido",
                    "Consentimento OAuth concedido a cliente MCP".to_string(),
                    serde_json::json!({
                        "grant_id": grant.id.to_string(),
                        "client_id": grant.client_id,
                        "client_name": grant.client_name,
                        "scopes": grant.scopes,
                        "source": "mcp",
                    }),
                    Some(grant.user_id),
                )
                .await;
            ok_reply(
                &env,
                "RegisterMcpGrantReply",
                serde_json::json!({ "grant": grant_para_json(&grant) }),
            )
        }
        Err(err) => erro(err.into(), &env),
    }
}

/// Lista os consentimentos ativos do próprio usuário.
///
/// Sem auditoria: é leitura do próprio dado, feita toda vez que a tela abre — o
/// evento seria ruído puro na trilha. Ausência intencional, ver plano §N13.2.
pub async fn handler_list_mcp_grants(store: &dyn ports::McpGrantStore, env: Envelope) -> Envelope {
    let ctx = contexto_do_envelope(&env);
    match store.listar(&ctx).await {
        Ok(grants) => {
            let lista: Vec<serde_json::Value> = grants.iter().map(grant_para_json).collect();
            ok_reply(
                &env,
                "ListMcpGrantsReply",
                serde_json::json!({ "grants": lista }),
            )
        }
        Err(err) => erro(err.into(), &env),
    }
}

/// Revoga um consentimento do próprio usuário.
pub async fn handler_revoke_mcp_grant(
    store: &dyn ports::McpGrantStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload = payload_de(&env);
    let ctx = contexto_do_envelope(&env);

    let Some(grant_id) = uuid_do_payload(&payload, "grant_id") else {
        return erro(
            error_core::AppError::Validation("grant_id inválido ou ausente".to_string()),
            &env,
        );
    };

    match store.revogar(&ctx, grant_id).await {
        Ok(true) => {
            audit
                .publish_security(
                    &env.traceparent,
                    Some(ctx.tenant_id),
                    "INFO",
                    "oauth.grant_revogado",
                    "Consentimento OAuth revogado pelo usuário".to_string(),
                    serde_json::json!({
                        "grant_id": grant_id.to_string(),
                        "source": "mcp",
                    }),
                    Some(ctx.user_id),
                )
                .await;
            ok_reply(
                &env,
                "RevokeMcpGrantReply",
                serde_json::json!({ "status": "success" }),
            )
        }
        // Grant inexistente, de outro usuário ou já revogado devolvem a mesma
        // mensagem: distinguir confirmaria a existência de grant alheio.
        Ok(false) => erro(
            error_core::AppError::Validation(
                "consentimento inexistente ou já revogado".to_string(),
            ),
            &env,
        ),
        Err(err) => erro(err.into(), &env),
    }
}

/// Grava o hash SHA-256 do refresh token corrente (emissão ou rotação).
/// Chamado só pelo `control_plane`. Sem auditoria: rotação de refresh acontece a
/// cada renovação e o evento útil é o **reuso**, não o giro normal.
pub async fn handler_set_mcp_grant_refresh_hash(
    store: &dyn ports::McpGrantStore,
    env: Envelope,
) -> Envelope {
    let payload = payload_de(&env);
    let tenant_id = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());

    let Some(grant_id) = uuid_do_payload(&payload, "grant_id") else {
        return erro(
            error_core::AppError::Validation("grant_id inválido ou ausente".to_string()),
            &env,
        );
    };
    let hash = payload
        .get("refresh_token_hash")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    if hash.is_empty() {
        return erro(
            error_core::AppError::Validation("refresh_token_hash ausente".to_string()),
            &env,
        );
    }

    match store.definir_refresh_hash(tenant_id, grant_id, hash).await {
        Ok(()) => ok_reply(
            &env,
            "SetMcpGrantRefreshHashReply",
            serde_json::json!({ "status": "success" }),
        ),
        Err(err) => erro(err.into(), &env),
    }
}

/// Devolve o grant ativo **com** o hash do refresh, para o AS comparar na
/// renovação. Rota interna: só o `control_plane` a chama, e ela é o único lugar
/// do sistema onde o hash sai do banco.
pub async fn handler_get_mcp_grant_com_segredo(
    store: &dyn ports::McpGrantStore,
    env: Envelope,
) -> Envelope {
    let payload = payload_de(&env);
    let tenant_id = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());

    let Some(grant_id) = uuid_do_payload(&payload, "grant_id") else {
        return erro(
            error_core::AppError::Validation("grant_id inválido ou ausente".to_string()),
            &env,
        );
    };

    match store.buscar_com_segredo(tenant_id, grant_id).await {
        Ok(Some(achado)) => ok_reply(
            &env,
            "GetMcpGrantComSegredoReply",
            serde_json::json!({
                "grant": grant_para_json(&achado.grant),
                "refresh_token_hash": achado.refresh_token_hash,
            }),
        ),
        Ok(None) => erro(
            error_core::AppError::Validation("consentimento não encontrado".to_string()),
            &env,
        ),
        Err(err) => erro(err.into(), &env),
    }
}

/// Derruba o grant por reuso de refresh já rotacionado.
///
/// Auditado em **WARN**: é o sinal de que o token está em duas mãos. É o evento
/// que se quer ver num alerta, não numa consulta retrospectiva.
pub async fn handler_revoke_mcp_grant_por_reuso(
    store: &dyn ports::McpGrantStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload = payload_de(&env);
    let tenant_id = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());

    let Some(grant_id) = uuid_do_payload(&payload, "grant_id") else {
        return erro(
            error_core::AppError::Validation("grant_id inválido ou ausente".to_string()),
            &env,
        );
    };

    match store.revogar_por_reuso(tenant_id, grant_id).await {
        Ok(()) => {
            audit
                .publish(
                    &env,
                    "oauth.refresh_reutilizado",
                    "Refresh token reutilizado após rotação: consentimento revogado".to_string(),
                    serde_json::json!({
                        "grant_id": grant_id.to_string(),
                        "source": "mcp",
                        "severidade": "suspeita_de_roubo",
                    }),
                )
                .await;
            ok_reply(
                &env,
                "RevokeMcpGrantPorReusoReply",
                serde_json::json!({ "status": "success" }),
            )
        }
        Err(err) => erro(err.into(), &env),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ports::MockMcpGrantStore;
    use contracts::MessageKind;
    use infrastructure_postgres::McpGrant;

    fn envelope(metodo: &str, payload: serde_json::Value, user_id: i32) -> Envelope {
        Envelope {
            tenant_id: Uuid::now_v7().to_string(),
            method: metodo.to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id: user_id,
            traceparent: "00-trace-mcp-01-01".to_string(),
            ..Default::default()
        }
    }

    fn grant_exemplo() -> McpGrant {
        McpGrant {
            id: Uuid::now_v7(),
            tenant_id: Uuid::now_v7(),
            user_id: 7,
            client_id: "https://claude.ai/mcp-client".to_string(),
            client_name: "Claude".to_string(),
            redirect_uri: "https://claude.ai/api/mcp/auth_callback".to_string(),
            scopes: vec!["atendimentos:read".to_string()],
            last_used_at: None,
            revoked_at: None,
            created_at: chrono::Utc::now(),
        }
    }

    struct AuditNulo;

    #[async_trait::async_trait]
    impl ports::AuditPort for AuditNulo {
        async fn publish(
            &self,
            _env: &Envelope,
            _event: &str,
            _message: String,
            _context: serde_json::Value,
        ) {
        }

        async fn publish_security(
            &self,
            _traceparent: &str,
            _tenant_id: Option<Uuid>,
            _level: &str,
            _event: &str,
            _message: String,
            _context: serde_json::Value,
            _user_id: Option<i32>,
        ) {
        }
    }

    #[tokio::test]
    async fn register_mcp_grant_recusa_sem_usuario_autenticado() {
        let store = MockMcpGrantStore::new();
        let env = envelope(
            "RegisterMcpGrant",
            serde_json::json!({
                "client_id": "https://claude.ai/mcp-client",
                "redirect_uri": "https://claude.ai/cb",
            }),
            0,
        );
        let resp = handler_register_mcp_grant(&store, &AuditNulo, env).await;
        assert_eq!(resp.kind, MessageKind::Error as i32);
    }

    #[tokio::test]
    async fn register_mcp_grant_recusa_sem_client_id() {
        let store = MockMcpGrantStore::new();
        let env = envelope(
            "RegisterMcpGrant",
            serde_json::json!({ "redirect_uri": "https://claude.ai/cb" }),
            7,
        );
        let resp = handler_register_mcp_grant(&store, &AuditNulo, env).await;
        assert_eq!(resp.kind, MessageKind::Error as i32);
    }

    #[tokio::test]
    async fn list_mcp_grants_nao_devolve_hash_de_refresh() {
        let mut store = MockMcpGrantStore::new();
        store
            .expect_listar()
            .returning(|_| Ok(vec![grant_exemplo()]));

        let env = envelope("ListMcpGrants", serde_json::json!({}), 7);
        let resp = handler_list_mcp_grants(&store, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let corpo = String::from_utf8(resp.payload).unwrap();
        assert!(corpo.contains("Claude"));
        assert!(!corpo.contains("refresh"));
    }

    #[tokio::test]
    async fn revoke_mcp_grant_de_outro_usuario_devolve_erro_generico() {
        let mut store = MockMcpGrantStore::new();
        // O repositório devolve `false` para grant inexistente, de outrem ou já
        // revogado — o handler não pode distinguir os três na mensagem.
        store.expect_revogar().returning(|_, _| Ok(false));

        let env = envelope(
            "RevokeMcpGrant",
            serde_json::json!({ "grant_id": Uuid::now_v7().to_string() }),
            7,
        );
        let resp = handler_revoke_mcp_grant(&store, &AuditNulo, env).await;

        assert_eq!(resp.kind, MessageKind::Error as i32);
        let msg = resp.error.unwrap().message;
        assert!(msg.contains("inexistente ou já revogado"));
        assert!(!msg.contains("outro"));
    }

    #[tokio::test]
    async fn revoke_mcp_grant_recusa_grant_id_malformado() {
        let store = MockMcpGrantStore::new();
        let env = envelope(
            "RevokeMcpGrant",
            serde_json::json!({ "grant_id": "nao-e-uuid" }),
            7,
        );
        let resp = handler_revoke_mcp_grant(&store, &AuditNulo, env).await;
        assert_eq!(resp.kind, MessageKind::Error as i32);
    }
}
