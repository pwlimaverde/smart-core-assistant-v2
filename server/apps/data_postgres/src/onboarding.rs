//! Handlers do cadastro público de tenant e da gestão de vouchers.
//!
//! Vivem fora do `main.rs` por volume: são onze rotas novas, e o `main` já passa
//! de seis mil linhas. As regras seguem as dos handlers vizinhos — validação de
//! entrada aqui, SQL no adapter, auditoria em toda transição de estado.
//!
//! **Estas rotas são as únicas do serviço alcançáveis sem sessão.** O que as
//! protege é: rate limit por IP na borda, o `signup_token` nos passos 2 em
//! diante, e o fato de o tenant nascer inativo — um cadastro sem pagamento
//! confirmado não dá acesso a nada.

use contracts::Envelope;
use uuid::Uuid;

use crate::ports::{self, DesfechoResgate, SlugIndisponivel};
use crate::{erro, ok_reply};

// ---------------------------------------------------------------------------
// Auxiliares
// ---------------------------------------------------------------------------

fn campo_str<'a>(payload: &'a serde_json::Value, chave: &str) -> &'a str {
    payload
        .get(chave)
        .and_then(serde_json::Value::as_str)
        .unwrap_or("")
        .trim()
}

fn payload_de(env: &Envelope) -> serde_json::Value {
    serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}))
}

fn tenant_do_payload(payload: &serde_json::Value) -> Option<Uuid> {
    Uuid::parse_str(campo_str(payload, "tenant_id")).ok()
}

/// Confere o `signup_token` do passo 1 antes de qualquer efeito.
///
/// Devolve o `Envelope` de erro pronto quando a autorização falha — o chamador
/// só precisa propagar. Token inválido responde o mesmo que tenant inexistente:
/// quem não começou o cadastro não descobre se ele existe.
async fn autorizar(
    signup: &dyn ports::SignupStore,
    env: &Envelope,
    tenant_id: Uuid,
    token: &str,
) -> Option<Envelope> {
    match signup.validar_token(tenant_id, token).await {
        Ok(true) => None,
        Ok(false) => Some(erro(
            error_core::AppError::Auth("cadastro não encontrado ou já concluído".to_string()),
            env,
        )),
        Err(e) => Some(erro(error_core::AppError::Database(e.to_string()), env)),
    }
}

fn motivo_slug(motivo: SlugIndisponivel) -> (&'static str, &'static str) {
    match motivo {
        SlugIndisponivel::EmUso => ("em_uso", "Este endereço já está em uso."),
        SlugIndisponivel::Reservado => ("reservado", "Este endereço é reservado."),
        SlugIndisponivel::Invalido => (
            "invalido",
            "Use de 3 a 63 caracteres: letras minúsculas, números e hífen.",
        ),
    }
}

// ---------------------------------------------------------------------------
// Passo 0 — consultas públicas
// ---------------------------------------------------------------------------

#[tracing::instrument(skip_all, fields(rpc = "CheckTenantSlug"))]
pub async fn handler_check_slug(signup: &dyn ports::SignupStore, env: Envelope) -> Envelope {
    let payload = payload_de(&env);
    let slug = campo_str(&payload, "slug");

    match signup.verificar_slug(slug).await {
        Ok(None) => ok_reply(
            &env,
            "CheckTenantSlugReply",
            serde_json::json!({ "disponivel": true, "motivo": "", "mensagem": "" }),
        ),
        Ok(Some(motivo)) => {
            let (codigo, mensagem) = motivo_slug(motivo);
            ok_reply(
                &env,
                "CheckTenantSlugReply",
                serde_json::json!({
                    "disponivel": false,
                    "motivo": codigo,
                    "mensagem": mensagem,
                }),
            )
        }
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "ListPublicPlans"))]
pub async fn handler_list_public_plans(signup: &dyn ports::SignupStore, env: Envelope) -> Envelope {
    match signup.listar_planos_publicos().await {
        Ok(planos) => ok_reply(
            &env,
            "ListPublicPlansReply",
            serde_json::json!({ "planos": planos }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

// ---------------------------------------------------------------------------
// Passo 1 — início do cadastro
// ---------------------------------------------------------------------------

#[tracing::instrument(skip_all, fields(rpc = "StartSignup"))]
pub async fn handler_start_signup(
    signup: &dyn ports::SignupStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload = payload_de(&env);
    let name = campo_str(&payload, "name");
    let slug = campo_str(&payload, "slug").to_lowercase();
    let email = campo_str(&payload, "email");
    let username = campo_str(&payload, "username");
    let phone = campo_str(&payload, "phone");
    // A senha em claro chega pelo Envelope (transporte interno) e é tratada
    // aqui: vira hash argon2id antes de qualquer persistência, e nunca entra em
    // span nem log.
    let password = payload
        .get("password")
        .and_then(serde_json::Value::as_str)
        .unwrap_or("");

    if name.is_empty() || email.is_empty() {
        return erro(
            error_core::AppError::Validation("nome da empresa e e-mail são obrigatórios".into()),
            &env,
        );
    }
    if password.len() < 8 {
        return erro(
            error_core::AppError::Validation("a senha precisa de ao menos 8 caracteres".into()),
            &env,
        );
    }

    // Revalida o slug no servidor: a checagem da tela é conveniência, não
    // autoridade — e entre uma e outra alguém pode ter registrado o mesmo nome.
    match signup.verificar_slug(&slug).await {
        Ok(Some(motivo)) => {
            let (_, mensagem) = motivo_slug(motivo);
            return erro(error_core::AppError::Validation(mensagem.to_string()), &env);
        }
        Err(e) => return erro(error_core::AppError::Database(e.to_string()), &env),
        Ok(None) => {}
    }

    let password_hash = match infrastructure_postgres::hash_password(password) {
        Ok(h) => h,
        Err(e) => {
            return erro(
                error_core::AppError::Internal(format!("falha ao processar a senha: {e}")),
                &env,
            )
        }
    };

    // Sem username explícito, o e-mail serve: é único e o usuário o conhece.
    let username = if username.is_empty() { email } else { username };

    match signup
        .iniciar(name, &slug, email, username, &password_hash, phone)
        .await
    {
        Ok(iniciado) => {
            audit
                .publish(
                    &env,
                    "signup_started",
                    format!("Cadastro iniciado para '{name}'"),
                    serde_json::json!({
                        "tenant_id": iniciado.tenant_id.to_string(),
                        "slug": slug,
                        "user_id": iniciado.user_id,
                    }),
                )
                .await;

            ok_reply(
                &env,
                "StartSignupReply",
                serde_json::json!({
                    "tenant_id": iniciado.tenant_id.to_string(),
                    "signup_token": iniciado.signup_token,
                    "proximo_passo": 2,
                }),
            )
        }
        // O e-mail/username já existe, ou o slug foi tomado no intervalo entre a
        // checagem e o INSERT. Mensagem genérica: dizer qual campo colidiu
        // transformaria o cadastro em oráculo de e-mails cadastrados.
        Err(infrastructure_postgres::DbError::UniqueViolation(_)) => erro(
            error_core::AppError::Validation(
                "não foi possível concluir o cadastro com estes dados".into(),
            ),
            &env,
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

// ---------------------------------------------------------------------------
// Passo 2 — escolha do plano
// ---------------------------------------------------------------------------

#[tracing::instrument(skip_all, fields(rpc = "SelectSignupPlan"))]
pub async fn handler_select_signup_plan(
    signup: &dyn ports::SignupStore,
    env: Envelope,
) -> Envelope {
    let payload = payload_de(&env);
    let Some(tenant_id) = tenant_do_payload(&payload) else {
        return erro(
            error_core::AppError::Validation("tenant_id inválido".into()),
            &env,
        );
    };
    let plan_id = payload
        .get("plan_id")
        .and_then(serde_json::Value::as_i64)
        .unwrap_or(0) as i32;
    if plan_id <= 0 {
        return erro(
            error_core::AppError::Validation("plano inválido".into()),
            &env,
        );
    }

    if let Some(negado) =
        autorizar(signup, &env, tenant_id, campo_str(&payload, "signup_token")).await
    {
        return negado;
    }

    match signup.selecionar_plano(tenant_id, plan_id).await {
        Ok(()) => ok_reply(
            &env,
            "SelectSignupPlanReply",
            serde_json::json!({ "proximo_passo": 3 }),
        ),
        Err(infrastructure_postgres::DbError::NotFound) => erro(
            error_core::AppError::Validation("este cadastro não está aguardando pagamento".into()),
            &env,
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

// ---------------------------------------------------------------------------
// Passo 3 — pagamento
// ---------------------------------------------------------------------------

/// Resgata um voucher. Chamado pelo `ProvedorVoucher` da porta de pagamento —
/// não diretamente pelo cliente.
#[tracing::instrument(skip_all, fields(rpc = "RedeemVoucher"))]
pub async fn handler_redeem_voucher(
    vouchers: &dyn ports::VoucherStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload = payload_de(&env);
    // O código NUNCA entra em span, log ou auditoria: é credencial de campanha.
    let codigo = campo_str(&payload, "codigo");
    let ip = campo_str(&payload, "ip");
    let Some(tenant_id) = tenant_do_payload(&payload) else {
        return erro(
            error_core::AppError::Validation("tenant_id inválido".into()),
            &env,
        );
    };

    match vouchers.resgatar(codigo, tenant_id, ip).await {
        Ok(DesfechoResgate::Concedido {
            resgate_id,
            plan_id,
            periodo_inicio,
            periodo_fim,
        }) => {
            audit
                .publish(
                    &env,
                    "voucher_redeemed",
                    "Voucher resgatado".to_string(),
                    serde_json::json!({
                        "tenant_id": tenant_id.to_string(),
                        "resgate_id": resgate_id.to_string(),
                        "plan_id": plan_id,
                    }),
                )
                .await;

            ok_reply(
                &env,
                "RedeemVoucherReply",
                serde_json::json!({
                    "concedido": true,
                    "resgate_id": resgate_id.to_string(),
                    "plan_id": plan_id,
                    "periodo_inicio": periodo_inicio.to_rfc3339(),
                    "periodo_fim": periodo_fim.to_rfc3339(),
                }),
            )
        }
        Ok(DesfechoResgate::Recusado { motivo, mensagem }) => {
            // Auditar a recusa é o que torna visível uma varredura de códigos.
            audit
                .publish(
                    &env,
                    "voucher_redeem_denied",
                    format!("Tentativa de resgate recusada: {motivo}"),
                    serde_json::json!({
                        "tenant_id": tenant_id.to_string(),
                        "motivo": motivo,
                        "ip": ip,
                    }),
                )
                .await;

            ok_reply(
                &env,
                "RedeemVoucherReply",
                serde_json::json!({
                    "concedido": false,
                    "motivo": motivo,
                    "mensagem": mensagem,
                }),
            )
        }
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// Ativa o tenant após o pagamento confirmado (por voucher agora, por webhook de
/// gateway no futuro).
#[tracing::instrument(skip_all, fields(rpc = "ActivateSignup"))]
pub async fn handler_activate_signup(
    signup: &dyn ports::SignupStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload = payload_de(&env);
    let Some(tenant_id) = tenant_do_payload(&payload) else {
        return erro(
            error_core::AppError::Validation("tenant_id inválido".into()),
            &env,
        );
    };
    let plan_id = payload
        .get("plan_id")
        .and_then(serde_json::Value::as_i64)
        .unwrap_or(0) as i32;
    let periodo_fim = payload
        .get("periodo_fim")
        .and_then(serde_json::Value::as_str)
        .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
        .map(|d| d.with_timezone(&chrono::Utc));

    let Some(periodo_fim) = periodo_fim else {
        return erro(
            error_core::AppError::Validation("periodo_fim ausente ou inválido".into()),
            &env,
        );
    };
    if plan_id <= 0 {
        return erro(
            error_core::AppError::Validation("plano inválido".into()),
            &env,
        );
    }

    let gateway = campo_str(&payload, "gateway");
    let referencia = campo_str(&payload, "referencia");

    match signup
        .ativar(tenant_id, plan_id, periodo_fim, gateway, referencia)
        .await
    {
        Ok(()) => {
            audit
                .publish(
                    &env,
                    "subscription_activated",
                    "Assinatura ativada".to_string(),
                    serde_json::json!({
                        "tenant_id": tenant_id.to_string(),
                        "plan_id": plan_id,
                        "gateway": gateway,
                        "periodo_fim": periodo_fim.to_rfc3339(),
                    }),
                )
                .await;
            ok_reply(
                &env,
                "ActivateSignupReply",
                serde_json::json!({ "ativado": true }),
            )
        }
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

// ---------------------------------------------------------------------------
// Passo 4 — acompanhamento
// ---------------------------------------------------------------------------

#[tracing::instrument(skip_all, fields(rpc = "GetSignupStatus"))]
pub async fn handler_get_signup_status(signup: &dyn ports::SignupStore, env: Envelope) -> Envelope {
    let payload = payload_de(&env);
    let Some(tenant_id) = tenant_do_payload(&payload) else {
        return erro(
            error_core::AppError::Validation("tenant_id inválido".into()),
            &env,
        );
    };

    if let Some(negado) =
        autorizar(signup, &env, tenant_id, campo_str(&payload, "signup_token")).await
    {
        return negado;
    }

    match signup.status(tenant_id).await {
        Ok(Some(s)) => ok_reply(
            &env,
            "GetSignupStatusReply",
            serde_json::json!({
                "tenant_id": s.tenant_id.to_string(),
                "passo": s.passo,
                "plan_id": s.plan_id.unwrap_or(0),
                "status_assinatura": s.status_assinatura,
                "tenant_ativo": s.tenant_ativo,
                "periodo_fim": s.periodo_fim.map(|d| d.timestamp_millis()).unwrap_or(0),
            }),
        ),
        Ok(None) => erro(
            error_core::AppError::Validation("cadastro não encontrado".into()),
            &env,
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

// ---------------------------------------------------------------------------
// Passos 5 a 8 — configuração inicial guiada
// ---------------------------------------------------------------------------

/// Registra até onde o tenant chegou na configuração guiada.
///
/// Diferente dos handlers acima, este roda **com sessão**: o `tenant_id` vem do
/// envelope, que a borda preencheu a partir das claims. Não há `signup_token`
/// aqui — o cadastro já terminou.
#[tracing::instrument(skip_all, fields(rpc = "SetOnboardingProgress", tenant_id = %env.tenant_id))]
pub async fn handler_set_onboarding_progress(
    store: &dyn ports::TenantStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload = payload_de(&env);
    let Ok(tenant_id) = Uuid::parse_str(&env.tenant_id) else {
        return erro(
            error_core::AppError::Validation("tenant_id inválido".into()),
            &env,
        );
    };

    let passo = payload
        .get("passo")
        .and_then(serde_json::Value::as_i64)
        .unwrap_or(0) as i32;
    let concluido = payload
        .get("concluido")
        .and_then(serde_json::Value::as_bool)
        .unwrap_or(false);

    // O roteiro guiado vai do 5 ao 8; 1..4 é o cadastro, que já passou.
    if !(5..=8).contains(&passo) {
        return erro(
            error_core::AppError::Validation("passo fora do roteiro".into()),
            &env,
        );
    }

    match store
        .atualizar_progresso_onboarding(tenant_id, passo, concluido)
        .await
    {
        Ok(true) => {
            // Só a conclusão é auditada: o avanço de tela é ruído, mas "o tenant
            // terminou a configuração" é um marco do ciclo de vida da conta.
            if concluido {
                audit
                    .publish(
                        &env,
                        "tenant_setup_completed",
                        "Configuração inicial concluída".to_string(),
                        serde_json::json!({ "tenant_id": tenant_id.to_string() }),
                    )
                    .await;
            }
            ok_reply(
                &env,
                "SetOnboardingProgressReply",
                serde_json::json!({ "passo": passo, "concluido": concluido }),
            )
        }
        Ok(false) => erro(
            error_core::AppError::Validation("tenant não encontrado".into()),
            &env,
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

// ---------------------------------------------------------------------------
// Gestão de vouchers (superusuário)
// ---------------------------------------------------------------------------

#[tracing::instrument(skip_all, fields(rpc = "CreateVoucher"))]
pub async fn handler_create_voucher(
    vouchers: &dyn ports::VoucherStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload = payload_de(&env);
    let codigo = campo_str(&payload, "codigo");
    let descricao = campo_str(&payload, "descricao");
    let plan_id = payload
        .get("plan_id")
        .and_then(serde_json::Value::as_i64)
        .unwrap_or(0) as i32;
    let duracao_dias = payload
        .get("duracao_dias")
        .and_then(serde_json::Value::as_i64)
        .unwrap_or(0) as i32;
    // Ausente = 1 (uso único), o padrão mais conservador.
    let max_resgates = payload
        .get("max_resgates")
        .and_then(serde_json::Value::as_i64)
        .unwrap_or(1) as i32;
    let valido_ate = payload
        .get("valido_ate")
        .and_then(serde_json::Value::as_str)
        .filter(|s| !s.trim().is_empty())
        .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
        .map(|d| d.with_timezone(&chrono::Utc));

    if codigo.is_empty() {
        return erro(
            error_core::AppError::Validation("código do voucher é obrigatório".into()),
            &env,
        );
    }
    if plan_id <= 0 || duracao_dias <= 0 {
        return erro(
            error_core::AppError::Validation("plano e duração são obrigatórios".into()),
            &env,
        );
    }
    if max_resgates < 0 {
        return erro(
            error_core::AppError::Validation("número de resgates inválido".into()),
            &env,
        );
    }

    let criado_por = (env.auth_user_id > 0).then_some(env.auth_user_id);

    match vouchers
        .criar(
            codigo,
            descricao,
            plan_id,
            duracao_dias,
            max_resgates,
            valido_ate,
            criado_por,
        )
        .await
    {
        Ok(voucher) => {
            audit
                .publish(
                    &env,
                    "voucher_created",
                    format!("Voucher '{codigo}' criado"),
                    serde_json::json!({
                        "codigo": codigo,
                        "plan_id": plan_id,
                        "duracao_dias": duracao_dias,
                        "max_resgates": max_resgates,
                    }),
                )
                .await;
            ok_reply(
                &env,
                "CreateVoucherReply",
                serde_json::json!({ "voucher": voucher }),
            )
        }
        Err(infrastructure_postgres::DbError::UniqueViolation(_)) => erro(
            error_core::AppError::Validation("já existe um voucher com este código".into()),
            &env,
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "ListVouchers"))]
pub async fn handler_list_vouchers(vouchers: &dyn ports::VoucherStore, env: Envelope) -> Envelope {
    match vouchers.listar().await {
        Ok(lista) => ok_reply(
            &env,
            "ListVouchersReply",
            serde_json::json!({ "vouchers": lista }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "RevokeVoucher"))]
pub async fn handler_revoke_voucher(
    vouchers: &dyn ports::VoucherStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let payload = payload_de(&env);
    let Ok(voucher_id) = Uuid::parse_str(campo_str(&payload, "voucher_id")) else {
        return erro(
            error_core::AppError::Validation("voucher_id inválido".into()),
            &env,
        );
    };
    let motivo = campo_str(&payload, "motivo");
    let revogado_por = (env.auth_user_id > 0).then_some(env.auth_user_id);

    match vouchers.revogar(voucher_id, revogado_por, motivo).await {
        Ok(true) => {
            audit
                .publish(
                    &env,
                    "voucher_revoked",
                    format!("Voucher revogado: {motivo}"),
                    serde_json::json!({
                        "voucher_id": voucher_id.to_string(),
                        "motivo": motivo,
                    }),
                )
                .await;
            ok_reply(
                &env,
                "RevokeVoucherReply",
                serde_json::json!({ "revogado": true }),
            )
        }
        // Já revogado: não é erro, e repetir não sobrescreve quem revogou antes.
        Ok(false) => ok_reply(
            &env,
            "RevokeVoucherReply",
            serde_json::json!({ "revogado": false }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "ListVoucherRedemptions"))]
pub async fn handler_list_voucher_redemptions(
    vouchers: &dyn ports::VoucherStore,
    env: Envelope,
) -> Envelope {
    let payload = payload_de(&env);
    let Ok(voucher_id) = Uuid::parse_str(campo_str(&payload, "voucher_id")) else {
        return erro(
            error_core::AppError::Validation("voucher_id inválido".into()),
            &env,
        );
    };

    match vouchers.listar_resgates(voucher_id).await {
        Ok(lista) => ok_reply(
            &env,
            "ListVoucherRedemptionsReply",
            serde_json::json!({ "resgates": lista }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}

/// Testes dos handlers via ports (sem banco). A cobertura do SQL real vive em
/// `crates/infrastructure_postgres/tests/tenants/vouchers.rs`.
#[cfg(test)]
mod tests {
    use super::*;
    use crate::ports::{MockAuditPort, MockSignupStore, MockVoucherStore, SignupIniciado};
    use chrono::{Duration, Utc};
    use contracts::MessageKind;

    fn envelope(method: &str, payload: serde_json::Value) -> Envelope {
        Envelope {
            kind: MessageKind::Request as i32,
            method: method.to_string(),
            tenant_id: Uuid::nil().to_string(),
            traceparent: "00-trace-span-01".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            ..Default::default()
        }
    }

    fn corpo(resp: &Envelope) -> serde_json::Value {
        serde_json::from_slice(&resp.payload).unwrap()
    }

    #[tokio::test]
    async fn slug_indisponivel_responde_com_motivo_legivel() {
        let mut store = MockSignupStore::new();
        store
            .expect_verificar_slug()
            .times(1)
            .returning(|_| Ok(Some(SlugIndisponivel::Reservado)));

        let resp = handler_check_slug(
            &store,
            envelope("CheckTenantSlug", serde_json::json!({"slug": "admin"})),
        )
        .await;

        let body = corpo(&resp);
        assert_eq!(body["disponivel"], false);
        assert_eq!(body["motivo"], "reservado");
        assert!(!body["mensagem"].as_str().unwrap().is_empty());
    }

    #[tokio::test]
    async fn senha_curta_nao_chega_a_criar_nada() {
        // Fail-closed: a validação precede a port, então nem o hash é calculado.
        let mut store = MockSignupStore::new();
        store.expect_verificar_slug().never();
        store.expect_iniciar().never();
        let mut audit = MockAuditPort::new();
        audit.expect_publish().never();

        let resp = handler_start_signup(
            &store,
            &audit,
            envelope(
                "StartSignup",
                serde_json::json!({
                    "name": "Empresa", "slug": "empresa", "email": "a@b.com", "password": "1234"
                }),
            ),
        )
        .await;

        assert_eq!(resp.kind, MessageKind::Error as i32);
        assert_eq!(resp.error.unwrap().code, "VALIDATION_FAILED");
    }

    #[tokio::test]
    async fn slug_tomado_entre_a_tela_e_o_servidor_barra_o_cadastro() {
        // A checagem do cliente é conveniência; a autoridade é esta revalidação.
        let mut store = MockSignupStore::new();
        store
            .expect_verificar_slug()
            .times(1)
            .returning(|_| Ok(Some(SlugIndisponivel::EmUso)));
        store.expect_iniciar().never();
        let mut audit = MockAuditPort::new();
        audit.expect_publish().never();

        let resp = handler_start_signup(
            &store,
            &audit,
            envelope(
                "StartSignup",
                serde_json::json!({
                    "name": "Empresa", "slug": "empresa", "email": "a@b.com",
                    "password": "senhaforte8"
                }),
            ),
        )
        .await;

        assert_eq!(resp.kind, MessageKind::Error as i32);
    }

    #[tokio::test]
    async fn cadastro_iniciado_devolve_token_e_audita() {
        let tenant_id = Uuid::new_v4();
        let mut store = MockSignupStore::new();
        store
            .expect_verificar_slug()
            .times(1)
            .returning(|_| Ok(None));
        store
            .expect_iniciar()
            .times(1)
            .returning(move |_, _, _, _, hash, _| {
                // A senha nunca é persistida em claro: o que chega ao adapter é hash.
                assert!(hash.starts_with("$argon2"), "hash inesperado: {hash}");
                Ok(SignupIniciado {
                    tenant_id,
                    signup_token: "ABCDEF0123456789ABCD".to_string(),
                    user_id: 42,
                })
            });
        let mut audit = MockAuditPort::new();
        audit.expect_publish().times(1).returning(|_, _, _, _| ());

        let resp = handler_start_signup(
            &store,
            &audit,
            envelope(
                "StartSignup",
                serde_json::json!({
                    "name": "Empresa", "slug": "empresa", "email": "a@b.com",
                    "password": "senhaforte8"
                }),
            ),
        )
        .await;

        let body = corpo(&resp);
        assert_eq!(body["tenant_id"], tenant_id.to_string());
        assert_eq!(body["signup_token"], "ABCDEF0123456789ABCD");
        assert_eq!(body["proximo_passo"], 2);
    }

    #[tokio::test]
    async fn colisao_de_email_nao_revela_qual_campo_colidiu() {
        // Do contrário o cadastro viraria um oráculo de e-mails já registrados.
        let mut store = MockSignupStore::new();
        store
            .expect_verificar_slug()
            .times(1)
            .returning(|_| Ok(None));
        store
            .expect_iniciar()
            .times(1)
            .returning(|_, _, _, _, _, _| {
                Err(infrastructure_postgres::DbError::UniqueViolation(
                    "auth_user_email_key".into(),
                ))
            });
        let mut audit = MockAuditPort::new();
        audit.expect_publish().never();

        let resp = handler_start_signup(
            &store,
            &audit,
            envelope(
                "StartSignup",
                serde_json::json!({
                    "name": "Empresa", "slug": "empresa", "email": "a@b.com",
                    "password": "senhaforte8"
                }),
            ),
        )
        .await;

        let mensagem = resp.error.unwrap().message;
        assert!(!mensagem.contains("email"), "vazou o campo: {mensagem}");
        assert!(
            !mensagem.contains("auth_user"),
            "vazou a tabela: {mensagem}"
        );
    }

    #[tokio::test]
    async fn passo_seguinte_sem_token_valido_e_recusado_sem_efeito() {
        let mut store = MockSignupStore::new();
        store
            .expect_validar_token()
            .times(1)
            .returning(|_, _| Ok(false));
        store.expect_selecionar_plano().never();

        let resp = handler_select_signup_plan(
            &store,
            envelope(
                "SelectSignupPlan",
                serde_json::json!({
                    "tenant_id": Uuid::new_v4().to_string(),
                    "signup_token": "chute",
                    "plan_id": 1
                }),
            ),
        )
        .await;

        assert_eq!(resp.kind, MessageKind::Error as i32);
        assert_eq!(resp.error.unwrap().code, "AUTH_INVALID_TOKEN");
    }

    #[tokio::test]
    async fn resgate_recusado_e_resposta_de_sucesso_com_concedido_falso() {
        // Recusa é caso de negócio: o cliente precisa da mensagem, não de um
        // erro de transporte.
        let mut store = MockVoucherStore::new();
        store.expect_resgatar().times(1).returning(|_, _, _| {
            Ok(DesfechoResgate::Recusado {
                motivo: "revogado".into(),
                mensagem: "Código inválido.".into(),
            })
        });
        let mut audit = MockAuditPort::new();
        // A recusa é auditada — é assim que uma varredura de códigos aparece.
        audit.expect_publish().times(1).returning(|_, _, _, _| ());

        let resp = handler_redeem_voucher(
            &store,
            &audit,
            envelope(
                "RedeemVoucher",
                serde_json::json!({
                    "codigo": "QUALQUER",
                    "tenant_id": Uuid::new_v4().to_string(),
                    "ip": "203.0.113.9"
                }),
            ),
        )
        .await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
        let body = corpo(&resp);
        assert_eq!(body["concedido"], false);
        assert_eq!(body["mensagem"], "Código inválido.");
    }

    #[tokio::test]
    async fn resgate_concedido_devolve_plano_e_prazo_em_rfc3339() {
        let fim = Utc::now() + Duration::days(180);
        let mut store = MockVoucherStore::new();
        store.expect_resgatar().times(1).returning(move |_, _, _| {
            Ok(DesfechoResgate::Concedido {
                resgate_id: Uuid::new_v4(),
                plan_id: 7,
                periodo_inicio: Utc::now(),
                periodo_fim: fim,
            })
        });
        let mut audit = MockAuditPort::new();
        audit.expect_publish().times(1).returning(|_, _, _, _| ());

        let resp = handler_redeem_voucher(
            &store,
            &audit,
            envelope(
                "RedeemVoucher",
                serde_json::json!({
                    "codigo": "DEVTESTE", "tenant_id": Uuid::new_v4().to_string(), "ip": ""
                }),
            ),
        )
        .await;

        let body = corpo(&resp);
        assert_eq!(body["concedido"], true);
        assert_eq!(body["plan_id"], 7);
        // O provedor de pagamento faz parse de RFC 3339 — formato errado aqui
        // vira "concedeu sem periodo_fim" lá.
        assert!(
            chrono::DateTime::parse_from_rfc3339(body["periodo_fim"].as_str().unwrap()).is_ok()
        );
    }

    #[tokio::test]
    async fn voucher_sem_plano_ou_duracao_nao_e_criado() {
        let mut store = MockVoucherStore::new();
        store.expect_criar().never();
        let mut audit = MockAuditPort::new();
        audit.expect_publish().never();

        let resp = handler_create_voucher(
            &store,
            &audit,
            envelope(
                "CreateVoucher",
                serde_json::json!({ "codigo": "X", "plan_id": 0, "duracao_dias": 180 }),
            ),
        )
        .await;

        assert_eq!(resp.kind, MessageKind::Error as i32);
    }

    #[tokio::test]
    async fn revogar_duas_vezes_nao_e_erro_nem_audita_de_novo() {
        let mut store = MockVoucherStore::new();
        store
            .expect_revogar()
            .times(1)
            .returning(|_, _, _| Ok(false));
        let mut audit = MockAuditPort::new();
        audit.expect_publish().never();

        let resp = handler_revoke_voucher(
            &store,
            &audit,
            envelope(
                "RevokeVoucher",
                serde_json::json!({
                    "voucher_id": Uuid::new_v4().to_string(), "motivo": "de novo"
                }),
            ),
        )
        .await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
        assert_eq!(corpo(&resp)["revogado"], false);
    }

    #[tokio::test]
    async fn ativacao_exige_prazo_valido() {
        // Ativar sem prazo deixaria o tenant com assinatura de validade
        // indefinida — pior do que recusar.
        let mut store = MockSignupStore::new();
        store.expect_ativar().never();
        let mut audit = MockAuditPort::new();
        audit.expect_publish().never();

        let resp = handler_activate_signup(
            &store,
            &audit,
            envelope(
                "ActivateSignup",
                serde_json::json!({
                    "tenant_id": Uuid::new_v4().to_string(), "plan_id": 1
                }),
            ),
        )
        .await;

        assert_eq!(resp.kind, MessageKind::Error as i32);
    }
}
