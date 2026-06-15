//! Fachada gRPC-Web da `runtime_api`: traduz chamadas do browser (Flutter Web/WASM)
//! para a lógica de negócio já existente em `application::auth::*`. NÃO reimplementa
//! regra de negócio — apenas converte o transporte (metadata gRPC-Web ↔ argumentos das
//! funções de aplicação) e reaproveita a auditoria de segurança da borda (`crate::audit`).
//!
//! Roda numa `tokio::task` paralela ao `transport::Server`, numa porta HTTP própria
//! (`RUNTIME_API_GRPC_WEB_ADDR`), pois o browser fala HTTP/1.1 + gRPC-Web.

use std::sync::Arc;

use application::auth::login::AuthDeps;
use contracts::grpc::queries::auth_service_server::{AuthService, AuthServiceServer};
use contracts::grpc::queries::{
    AuthResponse, LoginRequest, LogoutRequest, LogoutResponse, RefreshRequest,
};
use tonic::{Request, Response, Status};
use uuid::Uuid;

use crate::audit::{publicar_auditoria_borda, publicar_reuso_detectado};

/// Estado compartilhado da fachada: dependências de auth e a conexão de barramento
/// usada para publicar eventos de auditoria de segurança.
pub struct AuthFacade {
    deps: Arc<AuthDeps>,
    bus: redis::aio::ConnectionManager,
}

impl AuthFacade {
    pub fn new(deps: Arc<AuthDeps>, bus: redis::aio::ConnectionManager) -> Self {
        Self { deps, bus }
    }
}

/// Converte o `AppError` interno num `tonic::Status` sem vazar detalhe sensível.
/// As mensagens são chaves de i18n estáveis resolvidas no cliente (`ErrorMessageMapper`).
fn app_err_para_status(err: &error_core::AppError) -> Status {
    use error_core::AppError::*;
    match err {
        Auth(_) => Status::unauthenticated("errors.auth"),
        RateLimit(_) => Status::resource_exhausted("errors.auth.rate_limited"),
        Validation(_) => Status::invalid_argument("errors.validation"),
        Database(m) | Cache(m) | Storage(m) if m.contains("não encontrado") => {
            Status::not_found("errors.not_found")
        }
        _ => Status::internal("errors.internal"),
    }
}

/// Extrai o access token do metadata `authorization` (com ou sem prefixo `Bearer `).
fn bearer_do_metadata<T>(req: &Request<T>) -> String {
    req.metadata()
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.trim().to_string())
        .unwrap_or_default()
}

/// Extrai o `traceparent` (W3C TraceContext) do metadata; gera um novo se ausente,
/// para que a borda gRPC-Web sempre correlacione com os spans internos.
fn traceparent_do_metadata<T>(req: &Request<T>) -> String {
    req.metadata()
        .get("traceparent")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string())
        .unwrap_or_else(novo_traceparent)
}

/// Extrai o IP do cliente repassado pelo proxy (`x-forwarded-for`, primeiro valor).
/// Agora que existe uma borda HTTP de fato, podemos registrar o IP na auditoria
/// (item pendente do doc 09 §6.4).
fn ip_do_metadata<T>(req: &Request<T>) -> Option<String> {
    req.metadata()
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.split(',').next())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

/// Gera um `traceparent` W3C novo (`00-<trace32>-<span16>-01`) a partir de UUIDs.
fn novo_traceparent() -> String {
    let trace = Uuid::now_v7().simple().to_string(); // 32 hex
    let span = &Uuid::now_v7().simple().to_string()[..16]; // 16 hex
    format!("00-{trace}-{span}-01")
}

/// Decodifica o JSON `{access_token, refresh_token, ...}` retornado por `application::auth`.
fn extrair_tokens(tokens: &serde_json::Value) -> AuthResponse {
    AuthResponse {
        access_token: tokens
            .get("access_token")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string(),
        refresh_token: tokens
            .get("refresh_token")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string(),
    }
}

#[tonic::async_trait]
impl AuthService for AuthFacade {
    /// Login: delega para `application::auth::login::login`. Sem token no metadata.
    /// Audita `login_success`/`login_rate_limited` igual ao handler do `transport::Server`.
    #[tracing::instrument(skip_all, fields(service = "runtime_api", rpc = "Login", traceparent))]
    async fn login(&self, req: Request<LoginRequest>) -> Result<Response<AuthResponse>, Status> {
        let traceparent = traceparent_do_metadata(&req);
        let ip = ip_do_metadata(&req);
        tracing::Span::current().record("traceparent", tracing::field::display(&traceparent));

        let LoginRequest { email, password } = req.into_inner();
        // NUNCA logar email/password.
        let mut bus = self.bus.clone();
        match application::auth::login::login(&self.deps, &traceparent, &email, &password).await {
            Ok(tokens) => {
                let user_id = tokens
                    .get("user_id")
                    .and_then(|v| v.as_i64())
                    .map(|v| v as i32);
                let tenant_id = tokens
                    .get("tenant_id")
                    .and_then(|v| v.as_str())
                    .and_then(|s| Uuid::parse_str(s).ok())
                    .filter(|u| !u.is_nil());
                publicar_auditoria_borda(
                    &mut bus,
                    tenant_id,
                    "INFO",
                    "login_success",
                    "Login bem-sucedido (borda gRPC-Web).".to_string(),
                    serde_json::json!({}),
                    user_id,
                    &traceparent,
                    ip,
                )
                .await;
                Ok(Response::new(extrair_tokens(&tokens)))
            }
            Err(err) => {
                if matches!(&err, error_core::AppError::RateLimit(_)) {
                    publicar_auditoria_borda(
                        &mut bus,
                        None,
                        "WARN",
                        "login_rate_limited",
                        "Tentativas de login acima do limite na janela.".to_string(),
                        serde_json::json!({}),
                        None,
                        &traceparent,
                        ip,
                    )
                    .await;
                }
                error_core::registrar(
                    &err,
                    &error_core::ErrorContext {
                        trace_id: traceparent.clone(),
                        tenant_id: String::new(),
                    },
                );
                Err(app_err_para_status(&err))
            }
        }
    }

    /// Refresh: delega para `application::auth::refresh::refresh` (rotação + detecção de reuso).
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "Refresh", traceparent)
    )]
    async fn refresh(
        &self,
        req: Request<RefreshRequest>,
    ) -> Result<Response<AuthResponse>, Status> {
        let traceparent = traceparent_do_metadata(&req);
        let ip = ip_do_metadata(&req);
        tracing::Span::current().record("traceparent", tracing::field::display(&traceparent));

        let refresh_token = req.into_inner().refresh_token;
        let mut bus = self.bus.clone();
        match application::auth::refresh::refresh(&self.deps, &traceparent, &refresh_token).await {
            Ok(tokens) => Ok(Response::new(extrair_tokens(&tokens))),
            Err(err) => {
                // Reuso de refresh rotacionado: publica `token_reuse_detected` igual ao handler.
                if matches!(&err, error_core::AppError::Auth(m) if m == application::auth::refresh::REUSE_MARKER)
                {
                    publicar_reuso_detectado(&mut bus, &traceparent, ip).await;
                }
                error_core::registrar(
                    &err,
                    &error_core::ErrorContext {
                        trace_id: traceparent.clone(),
                        tenant_id: String::new(),
                    },
                );
                Err(app_err_para_status(&err))
            }
        }
    }

    /// Logout: exige access token no metadata; delega para `application::auth::logout::logout`.
    #[tracing::instrument(skip_all, fields(service = "runtime_api", rpc = "Logout", traceparent))]
    async fn logout(
        &self,
        req: Request<LogoutRequest>,
    ) -> Result<Response<LogoutResponse>, Status> {
        let traceparent = traceparent_do_metadata(&req);
        let ip = ip_do_metadata(&req);
        tracing::Span::current().record("traceparent", tracing::field::display(&traceparent));

        let bearer = bearer_do_metadata(&req);
        let token = bearer.strip_prefix("Bearer ").unwrap_or(&bearer).trim();
        let claims = application::jwt::validar_access_token(token)
            .map_err(|_| Status::unauthenticated("errors.auth"))?;

        let refresh = req.into_inner().refresh_token;
        let refresh_opt = (!refresh.is_empty()).then_some(refresh.as_str());

        let mut bus = self.bus.clone();
        match application::auth::logout::logout(&self.deps, &traceparent, &claims, refresh_opt)
            .await
        {
            Ok(_) => {
                let tenant_id = Uuid::parse_str(&claims.tenant_id)
                    .ok()
                    .filter(|u| !u.is_nil());
                publicar_auditoria_borda(
                    &mut bus,
                    tenant_id,
                    "INFO",
                    "logout",
                    "Sessão encerrada pelo usuário (borda gRPC-Web).".to_string(),
                    serde_json::json!({ "jti": claims.jti }),
                    claims.sub.parse::<i32>().ok(),
                    &traceparent,
                    ip,
                )
                .await;
                Ok(Response::new(LogoutResponse { revoked: true }))
            }
            Err(err) => {
                error_core::registrar(
                    &err,
                    &error_core::ErrorContext {
                        trace_id: traceparent.clone(),
                        tenant_id: String::new(),
                    },
                );
                Err(app_err_para_status(&err))
            }
        }
    }
}

/// Sobe a fachada gRPC-Web numa porta HTTP própria (browser usa HTTP/1.1).
/// Ordem dos layers (obrigatória): CORS **antes** de `GrpcWebLayer`.
pub async fn serve(deps: Arc<AuthDeps>, bus: redis::aio::ConnectionManager) -> anyhow::Result<()> {
    let addr = std::env::var("RUNTIME_API_GRPC_WEB_ADDR")
        .unwrap_or_else(|_| "0.0.0.0:50051".to_string())
        .parse()?;

    let facade = AuthServiceServer::new(AuthFacade::new(deps, bus));

    // CORS restritivo (defesa em profundidade mesmo servindo na mesma origem que o WASM).
    let cors = tower_http::cors::CorsLayer::new()
        .allow_origin(tower_http::cors::AllowOrigin::mirror_request())
        .allow_methods(tower_http::cors::Any)
        .allow_headers([
            http::header::CONTENT_TYPE,
            http::header::AUTHORIZATION,
            "x-grpc-web".parse().unwrap(),
            "grpc-timeout".parse().unwrap(),
            "traceparent".parse().unwrap(),
        ])
        .expose_headers([
            "grpc-status".parse().unwrap(),
            "grpc-message".parse().unwrap(),
            "grpc-status-details-bin".parse().unwrap(),
        ]);

    tracing::info!(%addr, "Subindo fachada gRPC-Web da runtime_api");
    tonic::transport::Server::builder()
        .accept_http1(true) // OBRIGATÓRIO para o browser (HTTP/1.1)
        .layer(cors) // CORS ANTES
        .layer(tonic_web::GrpcWebLayer::new()) // GrpcWebLayer DEPOIS
        .add_service(facade)
        .serve(addr)
        .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tonic::Request;

    #[test]
    fn mapeia_app_error_para_status_sem_vazar_detalhe() {
        assert_eq!(
            app_err_para_status(&error_core::AppError::Auth("segredo".into())).code(),
            tonic::Code::Unauthenticated
        );
        assert_eq!(
            app_err_para_status(&error_core::AppError::RateLimit("x".into())).code(),
            tonic::Code::ResourceExhausted
        );
        assert_eq!(
            app_err_para_status(&error_core::AppError::Validation("x".into())).code(),
            tonic::Code::InvalidArgument
        );
        assert_eq!(
            app_err_para_status(&error_core::AppError::Database("não encontrado".into())).code(),
            tonic::Code::NotFound
        );
        assert_eq!(
            app_err_para_status(&error_core::AppError::Internal("boom".into())).code(),
            tonic::Code::Internal
        );
        // A mensagem é uma chave de i18n estável — nunca o detalhe interno.
        let st = app_err_para_status(&error_core::AppError::Auth("senha do banco".into()));
        assert_eq!(st.message(), "errors.auth");
    }

    #[test]
    fn extrai_bearer_e_traceparent_do_metadata() {
        let mut req = Request::new(LoginRequest {
            email: "x".into(),
            password: "y".into(),
        });
        req.metadata_mut()
            .insert("authorization", "Bearer abc.def.ghi".parse().unwrap());
        req.metadata_mut().insert(
            "traceparent",
            "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-01"
                .parse()
                .unwrap(),
        );
        req.metadata_mut()
            .insert("x-forwarded-for", "203.0.113.7, 10.0.0.1".parse().unwrap());

        assert_eq!(bearer_do_metadata(&req), "Bearer abc.def.ghi");
        assert_eq!(
            traceparent_do_metadata(&req),
            "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-01"
        );
        assert_eq!(ip_do_metadata(&req), Some("203.0.113.7".to_string()));
    }

    #[test]
    fn gera_traceparent_no_formato_w3c_quando_ausente() {
        let req = Request::new(RefreshRequest {
            refresh_token: "x".into(),
        });
        let tp = traceparent_do_metadata(&req);
        // 00-<32 hex>-<16 hex>-01
        let partes: Vec<&str> = tp.split('-').collect();
        assert_eq!(partes.len(), 4);
        assert_eq!(partes[0], "00");
        assert_eq!(partes[1].len(), 32);
        assert_eq!(partes[2].len(), 16);
        assert_eq!(partes[3], "01");
        assert_eq!(ip_do_metadata(&req), None);
    }

    #[test]
    fn extrai_tokens_do_json_da_aplicacao() {
        let json = serde_json::json!({
            "access_token": "acc",
            "refresh_token": "ref",
            "expires_in": 900,
        });
        let resp = extrair_tokens(&json);
        assert_eq!(resp.access_token, "acc");
        assert_eq!(resp.refresh_token, "ref");
    }
}
