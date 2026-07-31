//! Fachada gRPC-Web do cadastro público de tenant.
//!
//! É a **única** fachada da borda sem autenticação — o `AuthService` tem Login
//! público, mas ali as credenciais já existem; aqui não existe conta nenhuma
//! ainda. O que a protege:
//!
//!  - **rate limit por IP** em `StartSignup` e `ConfirmPayment` (as duas rotas
//!    com efeito colateral: criar registros e consumir voucher);
//!  - o **`signup_token`** devolvido pelo passo 1, exigido nos passos seguintes
//!    e validado no `data_postgres`;
//!  - o tenant nascer **inativo**: um cadastro sem pagamento confirmado não
//!    libera nada.
//!
//! O passo de pagamento não conhece gateway algum: fala com a
//! [`RegistroProvedores`] da porta de pagamento. Hoje há só o voucher.

use std::sync::Arc;
use std::time::Duration;

use application::auth::login::{montar_envelope_request, AuthDeps};
use application::pagamento::{
    DadosCobranca, IntencaoPagamento, ModoConfirmacao as ModoDominio, RegistroProvedores,
};
use contracts::grpc::queries::onboarding_service_server::OnboardingService;
use contracts::grpc::queries::{
    CheckSlugRequest, CheckSlugResponse, ConfirmPaymentRequest, ConfirmPaymentResponse,
    GetSignupStatusRequest, GetSignupStatusResponse, ListPaymentProvidersRequest,
    ListPaymentProvidersResponse, ListPublicPlansRequest, ListPublicPlansResponse, ModoConfirmacao,
    PaymentProvider, PublicPlan, SelectPlanRequest, SelectPlanResponse, StartSignupRequest,
    StartSignupResponse,
};
use contracts::{Envelope, MessageKind};
use tonic::{Request, Response, Status};
use uuid::Uuid;

use crate::grpc_web::{ip_do_metadata, traceparent_do_metadata};

/// Timeout dos RPCs internos deste fluxo. O cadastro tem uma pessoa esperando
/// na tela; nada aqui pode demorar mais que isso.
const TIMEOUT_RPC: Duration = Duration::from_secs(10);

/// Janela e teto do rate limit por IP nas rotas com efeito colateral.
const RL_JANELA_S: u64 = 300;
const RL_MAX_PADRAO: u64 = 10;

pub struct OnboardingFacade {
    deps: Arc<AuthDeps>,
    provedores: RegistroProvedores,
}

impl OnboardingFacade {
    pub fn new(deps: Arc<AuthDeps>, provedores: RegistroProvedores) -> Self {
        Self { deps, provedores }
    }

    /// Chama o `data_postgres` e devolve o corpo JSON da resposta.
    async fn chamar_pg(
        &self,
        metodo: &str,
        traceparent: &str,
        payload: serde_json::Value,
    ) -> Result<serde_json::Value, Status> {
        let req = montar_envelope_request(Uuid::nil(), traceparent, metodo, &payload);
        let resp = self
            .deps
            .pg
            .call(req, TIMEOUT_RPC)
            .await
            .map_err(|e| Status::internal(format!("falha no serviço interno: {e:?}")))?;

        if resp.kind == MessageKind::Error as i32 {
            return Err(erro_interno_para_status(resp));
        }

        serde_json::from_slice(&resp.payload)
            .map_err(|e| Status::internal(format!("resposta ilegível: {e}")))
    }

    /// Conta a tentativa deste IP e recusa quando o teto é ultrapassado.
    ///
    /// **Fail-open**, como o rate limit do resto da borda: uma indisponibilidade
    /// do Redis não pode derrubar o cadastro. O que impede abuso em massa não é
    /// só este contador — é o voucher ser necessário para ativar qualquer coisa.
    async fn limitar_por_ip<T>(&self, req: &Request<T>, recurso: &str) -> Result<(), Status> {
        let ip = ip_do_metadata(req).unwrap_or_else(|| "desconhecido".to_string());
        let max = std::env::var("SIGNUP_RATE_LIMIT_MAX")
            .ok()
            .and_then(|s| s.parse::<u64>().ok())
            .unwrap_or(RL_MAX_PADRAO);

        let payload = serde_json::json!({
            "recurso": recurso,
            "id": ip,
            "window_s": RL_JANELA_S,
        });
        let rl_req = montar_envelope_request(
            Uuid::nil(),
            &traceparent_do_metadata(req),
            "RegisterRateLimitAttempt",
            &payload,
        );

        match self.deps.redis.call(rl_req, Duration::from_secs(3)).await {
            Ok(resp) if resp.kind != MessageKind::Error as i32 => {
                let corpo: serde_json::Value =
                    serde_json::from_slice(&resp.payload).unwrap_or_default();
                let tentativas = corpo
                    .get("attempts")
                    .and_then(serde_json::Value::as_u64)
                    .unwrap_or(0);
                if tentativas > max {
                    tracing::warn!(recurso, tentativas, max, "rate limit de cadastro excedido");
                    return Err(Status::resource_exhausted(
                        "Muitas tentativas. Aguarde alguns minutos.",
                    ));
                }
                Ok(())
            }
            outro => {
                tracing::warn!(recurso, "rate limit indisponível (fail-open): {outro:?}");
                Ok(())
            }
        }
    }
}

/// Converte um Envelope de erro do serviço interno em `Status`.
///
/// Erro de validação vira `invalid_argument` e **mantém a mensagem** (é texto
/// escrito para o usuário: "este endereço já está em uso"). Qualquer outro vira
/// `internal` com mensagem genérica — detalhe de banco não atravessa a borda.
fn erro_interno_para_status(resp: Envelope) -> Status {
    let Some(err) = resp.error else {
        return Status::internal("falha no serviço interno");
    };
    match err.code.as_str() {
        "VALIDATION_FAILED" => Status::invalid_argument(err.message),
        "AUTH_INVALID_TOKEN" | "AUTH_FAILED" => Status::permission_denied(err.message),
        _ => {
            tracing::error!(codigo = %err.code, detalhe = %err.message, "erro interno no cadastro");
            Status::internal("não foi possível concluir a operação")
        }
    }
}

fn modo_para_proto(modo: ModoDominio) -> i32 {
    match modo {
        ModoDominio::Imediata => ModoConfirmacao::Imediata as i32,
        ModoDominio::Assincrona => ModoConfirmacao::Assincrona as i32,
    }
}

fn i32_de(val: &serde_json::Value, chave: &str) -> i32 {
    val.get(chave)
        .and_then(serde_json::Value::as_i64)
        .unwrap_or(0) as i32
}

fn str_de(val: &serde_json::Value, chave: &str) -> String {
    val.get(chave)
        .and_then(serde_json::Value::as_str)
        .unwrap_or_default()
        .to_string()
}

#[tonic::async_trait]
impl OnboardingService for OnboardingFacade {
    #[tracing::instrument(skip_all, fields(service = "runtime_api", rpc = "CheckSlug"))]
    async fn check_slug(
        &self,
        req: Request<CheckSlugRequest>,
    ) -> Result<Response<CheckSlugResponse>, Status> {
        let traceparent = traceparent_do_metadata(&req);
        let slug = req.into_inner().slug;

        let corpo = self
            .chamar_pg(
                "CheckTenantSlug",
                &traceparent,
                serde_json::json!({ "slug": slug }),
            )
            .await?;

        Ok(Response::new(CheckSlugResponse {
            disponivel: corpo
                .get("disponivel")
                .and_then(serde_json::Value::as_bool)
                .unwrap_or(false),
            motivo: str_de(&corpo, "motivo"),
            mensagem: str_de(&corpo, "mensagem"),
        }))
    }

    #[tracing::instrument(skip_all, fields(service = "runtime_api", rpc = "ListPublicPlans"))]
    async fn list_public_plans(
        &self,
        req: Request<ListPublicPlansRequest>,
    ) -> Result<Response<ListPublicPlansResponse>, Status> {
        let traceparent = traceparent_do_metadata(&req);
        let corpo = self
            .chamar_pg("ListPublicPlans", &traceparent, serde_json::json!({}))
            .await?;

        let planos = corpo
            .get("planos")
            .and_then(serde_json::Value::as_array)
            .map(|arr| {
                arr.iter()
                    .map(|p| PublicPlan {
                        id: i32_de(p, "id"),
                        name: str_de(p, "name"),
                        description: str_de(p, "description"),
                        price: str_de(p, "price"),
                        max_instances: i32_de(p, "max_instances"),
                        max_departments: i32_de(p, "max_departments"),
                        max_fluxos: i32_de(p, "max_fluxos"),
                    })
                    .collect()
            })
            .unwrap_or_default();

        Ok(Response::new(ListPublicPlansResponse { planos }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListPaymentProviders")
    )]
    async fn list_payment_providers(
        &self,
        _req: Request<ListPaymentProvidersRequest>,
    ) -> Result<Response<ListPaymentProvidersResponse>, Status> {
        // A lista vem do registro, não de uma constante: quando um gateway for
        // habilitado, ele aparece aqui e na tela sem mudança de código.
        let provedores = self
            .provedores
            .descrever()
            .into_iter()
            .map(|d| PaymentProvider {
                id: d.id,
                rotulo: d.rotulo,
                instrucao: d.instrucao,
                requer_credencial: d.requer_credencial,
                rotulo_credencial: d.rotulo_credencial,
                modo: modo_para_proto(d.modo),
            })
            .collect();

        Ok(Response::new(ListPaymentProvidersResponse { provedores }))
    }

    #[tracing::instrument(skip_all, fields(service = "runtime_api", rpc = "StartSignup"))]
    async fn start_signup(
        &self,
        req: Request<StartSignupRequest>,
    ) -> Result<Response<StartSignupResponse>, Status> {
        self.limitar_por_ip(&req, "signup_start").await?;
        let traceparent = traceparent_do_metadata(&req);
        let r = req.into_inner();

        // A senha atravessa o transporte interno em claro e vira hash no
        // `data_postgres`. Nunca entra em span, log ou auditoria.
        let corpo = self
            .chamar_pg(
                "StartSignup",
                &traceparent,
                serde_json::json!({
                    "name": r.name,
                    "slug": r.slug,
                    "email": r.email,
                    "username": r.username,
                    "password": r.password,
                    "phone": r.phone,
                }),
            )
            .await?;

        Ok(Response::new(StartSignupResponse {
            tenant_id: str_de(&corpo, "tenant_id"),
            signup_token: str_de(&corpo, "signup_token"),
            proximo_passo: i32_de(&corpo, "proximo_passo"),
        }))
    }

    #[tracing::instrument(skip_all, fields(service = "runtime_api", rpc = "SelectPlan"))]
    async fn select_plan(
        &self,
        req: Request<SelectPlanRequest>,
    ) -> Result<Response<SelectPlanResponse>, Status> {
        let traceparent = traceparent_do_metadata(&req);
        let r = req.into_inner();

        let corpo = self
            .chamar_pg(
                "SelectSignupPlan",
                &traceparent,
                serde_json::json!({
                    "tenant_id": r.tenant_id,
                    "signup_token": r.signup_token,
                    "plan_id": r.plan_id,
                }),
            )
            .await?;

        Ok(Response::new(SelectPlanResponse {
            proximo_passo: i32_de(&corpo, "proximo_passo"),
        }))
    }

    /// O passo de pagamento: escolhe o provedor, deixa que ele decida, e só
    /// então ativa o tenant.
    #[tracing::instrument(skip_all, fields(service = "runtime_api", rpc = "ConfirmPayment"))]
    async fn confirm_payment(
        &self,
        req: Request<ConfirmPaymentRequest>,
    ) -> Result<Response<ConfirmPaymentResponse>, Status> {
        self.limitar_por_ip(&req, "signup_pagamento").await?;
        let traceparent = traceparent_do_metadata(&req);
        let ip = ip_do_metadata(&req).unwrap_or_default();
        let r = req.into_inner();

        let tenant_id = Uuid::parse_str(&r.tenant_id)
            .map_err(|_| Status::invalid_argument("cadastro inválido"))?;

        // 1. Autorização: sem o token do passo 1, nada acontece. A checagem é
        //    feita antes de tocar em provedor — não se consome um voucher para
        //    descobrir depois que o cadastro não é de quem chamou.
        let status = self
            .chamar_pg(
                "GetSignupStatus",
                &traceparent,
                serde_json::json!({
                    "tenant_id": r.tenant_id,
                    "signup_token": r.signup_token,
                }),
            )
            .await?;

        let plan_id = i32_de(&status, "plan_id");
        if plan_id <= 0 {
            return Err(Status::failed_precondition(
                "escolha um plano antes de pagar",
            ));
        }

        // Já ativo: retentativa ou clique duplo. Responder sucesso é mais
        // correto do que recusar — o estado desejado já é o atual.
        if status
            .get("tenant_ativo")
            .and_then(serde_json::Value::as_bool)
            .unwrap_or(false)
        {
            return Ok(Response::new(ConfirmPaymentResponse {
                confirmado: true,
                url_redirecionamento: String::new(),
                motivo: String::new(),
                mensagem: String::new(),
            }));
        }

        // 2. O provedor decide.
        let provedor = self
            .provedores
            .obter(&r.provedor)
            .ok_or_else(|| Status::invalid_argument("forma de pagamento indisponível"))?;

        let dados = DadosCobranca {
            tenant_id,
            plan_id,
            email: String::new(),
            credencial: r.credencial,
            ip,
            traceparent: traceparent.clone(),
        };

        let intencao = provedor
            .iniciar(&dados)
            .await
            .map_err(|e| crate::grpc_web::app_err_para_status(&e))?;

        match intencao {
            IntencaoPagamento::Confirmada {
                plan_id,
                periodo_fim,
                referencia,
            } => {
                // 3. Pago: liga o tenant. Se esta chamada falhar, o pagamento já
                //    aconteceu — por isso `ativar` é idempotente e pode ser
                //    repetida (pelo cliente ou por um webhook posterior).
                self.chamar_pg(
                    "ActivateSignup",
                    &traceparent,
                    serde_json::json!({
                        "tenant_id": r.tenant_id,
                        "plan_id": plan_id,
                        "periodo_fim": periodo_fim.to_rfc3339(),
                        "gateway": r.provedor,
                        "referencia": referencia,
                    }),
                )
                .await?;

                Ok(Response::new(ConfirmPaymentResponse {
                    confirmado: true,
                    url_redirecionamento: String::new(),
                    motivo: String::new(),
                    mensagem: String::new(),
                }))
            }
            // O usuário precisa concluir fora do app; a ativação virá depois,
            // pelo webhook do gateway, e o cliente acompanha por GetSignupStatus.
            IntencaoPagamento::Redirect { url, .. } => Ok(Response::new(ConfirmPaymentResponse {
                confirmado: false,
                url_redirecionamento: url,
                motivo: String::new(),
                mensagem: String::new(),
            })),
            // Recusa é resposta de sucesso com `confirmado: false`: o cliente
            // precisa da mensagem para mostrar no campo, não de um erro de RPC.
            IntencaoPagamento::Recusada { motivo, mensagem } => {
                Ok(Response::new(ConfirmPaymentResponse {
                    confirmado: false,
                    url_redirecionamento: String::new(),
                    motivo,
                    mensagem,
                }))
            }
        }
    }

    #[tracing::instrument(skip_all, fields(service = "runtime_api", rpc = "GetSignupStatus"))]
    async fn get_signup_status(
        &self,
        req: Request<GetSignupStatusRequest>,
    ) -> Result<Response<GetSignupStatusResponse>, Status> {
        let traceparent = traceparent_do_metadata(&req);
        let r = req.into_inner();

        let corpo = self
            .chamar_pg(
                "GetSignupStatus",
                &traceparent,
                serde_json::json!({
                    "tenant_id": r.tenant_id,
                    "signup_token": r.signup_token,
                }),
            )
            .await?;

        Ok(Response::new(GetSignupStatusResponse {
            passo: i32_de(&corpo, "passo"),
            plan_id: i32_de(&corpo, "plan_id"),
            status_assinatura: str_de(&corpo, "status_assinatura"),
            tenant_ativo: corpo
                .get("tenant_ativo")
                .and_then(serde_json::Value::as_bool)
                .unwrap_or(false),
            periodo_fim: corpo
                .get("periodo_fim")
                .and_then(serde_json::Value::as_i64)
                .unwrap_or(0),
        }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use contracts::ErrorEnvelope;

    fn envelope_de_erro(code: &str, message: &str) -> Envelope {
        Envelope {
            kind: MessageKind::Error as i32,
            error: Some(ErrorEnvelope {
                code: code.to_string(),
                message: message.to_string(),
                ..Default::default()
            }),
            ..Default::default()
        }
    }

    #[test]
    fn erro_de_validacao_preserva_a_mensagem_ao_usuario() {
        // "Este endereço já está em uso" é texto escrito para a tela; perdê-lo
        // deixaria o campo sem explicação.
        let status = erro_interno_para_status(envelope_de_erro(
            "VALIDATION_FAILED",
            "Este endereço já está em uso.",
        ));
        assert_eq!(status.code(), tonic::Code::InvalidArgument);
        assert_eq!(status.message(), "Este endereço já está em uso.");
    }

    #[test]
    fn erro_interno_nao_vaza_detalhe_de_banco() {
        let status = erro_interno_para_status(envelope_de_erro(
            "DB_QUERY_FAILED",
            "relation \"tenants_voucher\" does not exist",
        ));
        assert_eq!(status.code(), tonic::Code::Internal);
        assert!(!status.message().contains("tenants_voucher"));
    }

    #[test]
    fn token_invalido_vira_permissao_negada() {
        let status = erro_interno_para_status(envelope_de_erro(
            "AUTH_INVALID_TOKEN",
            "cadastro não encontrado ou já concluído",
        ));
        assert_eq!(status.code(), tonic::Code::PermissionDenied);
    }

    #[test]
    fn modo_do_dominio_mapeia_para_o_enum_do_proto() {
        assert_eq!(
            modo_para_proto(ModoDominio::Imediata),
            ModoConfirmacao::Imediata as i32
        );
        assert_eq!(
            modo_para_proto(ModoDominio::Assincrona),
            ModoConfirmacao::Assincrona as i32
        );
    }
}
