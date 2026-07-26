//! Fachada gRPC-Web da `runtime_api`: traduz chamadas do browser (Flutter Web/WASM)
//! para a lógica de negócio já existente em `application::auth::*`. NÃO reimplementa
//! regra de negócio — apenas converte o transporte (metadata gRPC-Web ↔ argumentos das
//! funções de aplicação) e reaproveita a auditoria de segurança da borda (`crate::audit`).
//!
//! Roda numa `tokio::task` paralela ao `transport::Server`, numa porta HTTP própria
//! (`RUNTIME_API_GRPC_WEB_ADDR`), pois o browser fala HTTP/1.1 + gRPC-Web.

use std::sync::Arc;

use application::auth::login::AuthDeps;
use contracts::grpc::queries::admin_service_server::{AdminService, AdminServiceServer};
use contracts::grpc::queries::auth_service_server::{AuthService, AuthServiceServer};
use contracts::grpc::queries::{
    // Fase N3 - Painel do Tenant (convites, usuários, config tenant-scoped)
    AcceptInviteRequest,
    AcceptInviteResponse,
    AcceptedTenantUser,
    ApiKeyEntry as ProtoApiKeyEntry,
    AtendimentoEvent,
    // Fase 6 - Operacional (fila/Kanban/chat)
    AtendimentoResumo as ProtoAtendimentoResumo,
    AuditLogEntry as ProtoAuditLogEntry,
    AuthResponse,
    CoreSetting as ProtoCoreSetting,
    CreateInviteRequest,
    CreateInviteResponse,
    CreatePlanRequest,
    CreatePlanResponse,
    CreateTenantRequest,
    CreateTenantResponse,
    DeleteCoreSettingRequest,
    DeleteCoreSettingResponse,
    ExportTenantsCsvRequest,
    ExportTenantsCsvResponse,
    FeatureFlag as ProtoFeatureFlag,
    FeatureFlagOverride as ProtoFeatureFlagOverride,
    GenerateAccessCodeRequest,
    GenerateAccessCodeResponse,
    GetDashboardSummaryRequest,
    GetDashboardSummaryResponse,
    GetMyTenantConfigRequest,
    GetServiceHealthRequest,
    GetServiceHealthResponse,
    GetTenantConfigRequest,
    GetTenantConfigResponse,
    GetTenantRequest,
    GetTenantResponse,
    GetThreadRequest,
    GetThreadResponse,
    ListAtendimentosRequest,
    ListAtendimentosResponse,
    ListCoreSettingsRequest,
    ListCoreSettingsResponse,
    // Fase 4 - Feature Flags
    ListFeatureFlagsRequest,
    ListFeatureFlagsResponse,
    ListInvitesRequest,
    ListInvitesResponse,
    ListPaymentsRequest,
    ListPaymentsResponse,
    // Fase 2 - Billing
    ListPlansRequest,
    ListPlansResponse,
    ListSubscriptionsRequest,
    ListSubscriptionsResponse,
    ListTenantUsersRequest,
    ListTenantUsersResponse,
    // Fase 2 - Tenants
    ListTenantsRequest,
    ListTenantsResponse,
    LoginRequest,
    LogoutRequest,
    LogoutResponse,
    MensagemThread as ProtoMensagemThread,
    MoveAtendimentoEtapaRequest,
    MoveAtendimentoEtapaResponse,
    PaymentRecord as ProtoPaymentRecord,
    Plan as ProtoPlan,
    // Fase 5 - Auditoria & Saúde
    QueryAuditLogRequest,
    QueryAuditLogResponse,
    RefreshRequest,
    RegisterPaymentRequest,
    RegisterPaymentResponse,
    RevokeInviteRequest,
    RevokeInviteResponse,
    SendOutboundMessageRequest,
    SendOutboundMessageResponse,
    ServiceHealth as ProtoServiceHealth,
    SetFeatureFlagOverrideRequest,
    SetFeatureFlagOverrideResponse,
    SetFeatureFlagRequest,
    SetFeatureFlagResponse,
    SetTenantActiveRequest,
    SetTenantActiveResponse,
    StreamAtendimentosRequest,
    Subscription as ProtoSubscription,
    Tenant as ProtoTenant,
    TenantInviteCreated,
    TenantInviteItem,
    TenantUserItem,
    // Fase 3 - Evolution Connection
    TestEvolutionConnectionRequest,
    TestEvolutionConnectionResponse,
    UpdateMyTenantConfigRequest,
    UpdatePlanRequest,
    UpdatePlanResponse,
    UpdateTenantConfigRequest,
    UpdateTenantConfigResponse,
    UpdateTenantRequest,
    UpdateTenantResponse,
    UpdateTenantUserRequest,
    UpdateTenantUserResponse,
    UpsertCoreSettingRequest,
    UpsertCoreSettingResponse,
};
use contracts::{Envelope, MessageKind};
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

/// Extrai o `User-Agent` da requisição gRPC-Web (WS-5b). Metadado de auditoria,
/// não segredo; truncado defensivamente para evitar payload abusivo no audit_log.
fn user_agent_do_metadata<T>(req: &Request<T>) -> String {
    req.metadata()
        .get("user-agent")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.chars().take(512).collect::<String>())
        .unwrap_or_default()
}

/// Guarda de borda gRPC-Web: valida JWT + blocklist Redis + privilégio de superusuário.
async fn exigir_superuser_do_metadata<T>(
    deps: &AuthDeps,
    bus: &redis::aio::ConnectionManager,
    req: &Request<T>,
) -> Result<application::jwt::Claims, Status> {
    let claims = exigir_autenticado_do_metadata(deps, req).await?;

    // Exigir privilégios de superusuário (rotas administrativas).
    if !claims.is_superuser {
        let traceparent = traceparent_do_metadata(req);
        let ip = ip_do_metadata(req);
        let mut bus_clone = bus.clone();
        publicar_auditoria_borda(
            &mut bus_clone,
            None,
            "WARN",
            "auth_access_denied",
            "Acesso admin via gRPC-Web negado (sem is_superuser).".to_string(),
            serde_json::json!({}),
            claims.sub.parse::<i32>().ok(),
            &traceparent,
            ip,
            Some(user_agent_do_metadata(req)),
        )
        .await;
        return Err(Status::permission_denied("errors.auth.forbidden"));
    }

    Ok(claims)
}

/// Guarda de borda gRPC-Web para rotas operacionais (WS-6): exige apenas JWT válido
/// (não blocklistado), sem exigir superusuário. O RBAC fino por fluxo (`flow_permissions`,
/// WS-5a) é aplicado adiante, no `data_postgres`, sobre cada atendimento/fluxo.
async fn exigir_autenticado_do_metadata<T>(
    deps: &AuthDeps,
    req: &Request<T>,
) -> Result<application::jwt::Claims, Status> {
    let traceparent = traceparent_do_metadata(req);

    // 1. Extrair access token do metadata authorization
    let bearer = bearer_do_metadata(req);
    let token = bearer.strip_prefix("Bearer ").unwrap_or(&bearer).trim();
    if token.is_empty() {
        return Err(Status::unauthenticated("errors.auth"));
    }

    // 2. Validar assinatura e expiração via application::jwt
    let claims = application::jwt::validar_access_token(token)
        .map_err(|_| Status::unauthenticated("errors.auth"))?;

    // 3. Verificar blocklist no Redis via RPC IsTokenBlocked
    let blocked_payload = serde_json::json!({ "jti": claims.jti });
    let block_req = application::auth::login::montar_envelope_request(
        Uuid::nil(),
        &traceparent,
        "IsTokenBlocked",
        &blocked_payload,
    );

    match deps
        .redis
        .call(block_req, std::time::Duration::from_secs(3))
        .await
    {
        Ok(resp) => {
            let v: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap_or_default();
            if v.get("blocked").and_then(|b| b.as_bool()).unwrap_or(false) {
                return Err(Status::unauthenticated("errors.auth"));
            }
        }
        Err(_) => return Err(Status::internal("errors.internal")),
    }

    Ok(claims)
}

/// Exige que a sessão (já autenticada) tenha o escopo `tenant:admin` (ou o coringa
/// `*` de superusuário) — usado pelos RPCs tenant-scoped de config (N3.3), que expõem
/// dado sensível (api keys, prompts) e não devem ficar abertos a qualquer `TenantUser`.
fn exigir_escopo_tenant_admin(claims: &application::jwt::Claims) -> Result<(), Status> {
    if claims.is_superuser
        || claims
            .scopes
            .iter()
            .any(|s| s == "tenant:admin" || s == "*")
    {
        return Ok(());
    }
    Err(Status::permission_denied("errors.auth.forbidden"))
}

/// Resolve os `flow_permissions` (RBAC fino por fluxo — WS-5a) do usuário autenticado
/// na borda gRPC-Web, espelhando a estratégia RPC+cache curto do `transport::Server`
/// (ver `main::resolver_flow_permissions`). Sem isso, o `data_postgres` receberia o
/// envelope com `flow_permissions` vazio e barraria todo atendente não-admin (a fila
/// não mostraria cards com fluxo e mover etapa seria sempre negado).
///
/// Superusuário não tem `TenantUser`; o bypass de fluxo já ocorre via escopo
/// (`kanban:admin`/`tenant:admin`) em `RequestContext::has_flow_permission`, então o
/// chamador só invoca esta função para não-superusuários.
async fn resolver_flow_permissions_web(
    deps: &AuthDeps,
    tenant_id: &str,
    user_id: i32,
    traceparent: &str,
) -> Vec<i32> {
    let tenant_uuid = Uuid::parse_str(tenant_id).unwrap_or_else(|_| Uuid::nil());
    let lookup_payload = serde_json::json!({ "user_id": user_id });

    // Cache-aside: tenta o cache curto no data_redis antes da fonte de verdade.
    let cache_req = application::auth::login::montar_envelope_request(
        tenant_uuid,
        traceparent,
        "GetCache",
        &lookup_payload,
    );
    if let Ok(resp) = deps
        .redis
        .call(cache_req, std::time::Duration::from_secs(2))
        .await
    {
        if resp.kind != MessageKind::Error as i32 {
            if let Some(perms) = extrair_permissoes_web(&resp.payload) {
                return perms;
            }
        }
    }

    // Cache miss: consulta a fonte de verdade (data_postgres).
    let db_req = application::auth::login::montar_envelope_request(
        tenant_uuid,
        traceparent,
        "GetUserFlowPermissions",
        &lookup_payload,
    );
    let permissions = match deps
        .pg
        .call(db_req, std::time::Duration::from_secs(3))
        .await
    {
        Ok(resp) if resp.kind != MessageKind::Error as i32 => {
            extrair_permissoes_web(&resp.payload).unwrap_or_default()
        }
        _ => Vec::new(),
    };

    // Repovoa o cache (best-effort, TTL curto — não atrasa a resposta em caso de falha).
    let set_payload = serde_json::json!({
        "user_id": user_id,
        "permissions": permissions,
        "ttl": 30,
    });
    let set_req = application::auth::login::montar_envelope_request(
        tenant_uuid,
        traceparent,
        "SetCache",
        &set_payload,
    );
    let _ = deps
        .redis
        .call(set_req, std::time::Duration::from_secs(2))
        .await;

    permissions
}

fn extrair_permissoes_web(payload: &[u8]) -> Option<Vec<i32>> {
    let json: serde_json::Value = serde_json::from_slice(payload).ok()?;
    let arr = json.get("permissions")?.as_array()?;
    Some(
        arr.iter()
            .filter_map(|v| v.as_i64())
            .map(|v| v as i32)
            .collect(),
    )
}

/// Converte o `ErrorEnvelope` devolvido pelo serviço interno num `Status` gRPC
/// coerente para o cliente (N3): permissão insuficiente vira PERMISSION_DENIED
/// (antes tudo achatava em `internal`, e uma negação de RBAC parecia erro 500).
fn status_do_erro_interno(err: Option<contracts::ErrorEnvelope>) -> Status {
    let Some(err) = err else {
        return Status::internal("Erro no serviço interno");
    };
    match err.code.as_str() {
        "AUTH_INSUFFICIENT_SCOPE" => Status::permission_denied("errors.auth.forbidden"),
        "DB_RECORD_NOT_FOUND" => Status::not_found(err.message),
        "VALIDATION_FAILED" => Status::invalid_argument(err.message),
        "CONFLICT" | "DB_CONSTRAINT_VIOLATION" => Status::failed_precondition(err.message),
        _ => Status::internal(format!("Erro no banco: {}", err.message)),
    }
}

/// Extrai um array de strings de um campo JSON opcional (N3: `module_permissions`).
fn json_strings(val: Option<&serde_json::Value>) -> Vec<String> {
    val.and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str().map(|s| s.to_string()))
                .collect()
        })
        .unwrap_or_default()
}

/// Extrai um array de inteiros de um campo JSON opcional (N3: `flow_permissions`).
fn json_i32s(val: Option<&serde_json::Value>) -> Vec<i32> {
    val.and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_i64())
                .map(|v| v as i32)
                .collect()
        })
        .unwrap_or_default()
}

/// Gera um `traceparent` W3C novo (`00-<trace32>-<span16>-01`) a partir de UUIDs.
fn novo_traceparent() -> String {
    let trace = Uuid::now_v7().simple().to_string(); // 32 hex
    let span = &Uuid::now_v7().simple().to_string()[..16]; // 16 hex
    format!("00-{trace}-{span}-01")
}

/// Mapeia o payload JSON de `GetTenantConfig`/`GetMyTenantConfig` (fonte de verdade no
/// `data_postgres`) para a mensagem proto de resposta. Compartilhado entre o caminho de
/// superusuário e o caminho tenant-scoped (N3.3) — mesma forma de resposta em ambos.
fn mapear_tenant_config_response(val: &serde_json::Value) -> GetTenantConfigResponse {
    let mut api_keys = std::collections::HashMap::new();
    if let Some(keys_obj) = val.get("api_keys").and_then(|v| v.as_object()) {
        for (k, v) in keys_obj {
            if let Some(v_str) = v.as_str() {
                api_keys.insert(k.clone(), v_str.to_string());
            }
        }
    }
    let api_keys_proto = api_keys
        .into_iter()
        .map(|(key, value)| ProtoApiKeyEntry { key, value })
        .collect();

    let campo_str = |chave: &str| {
        val.get(chave)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string()
    };

    GetTenantConfigResponse {
        dados_empresa: campo_str("dados_empresa"),
        persona_bot: campo_str("persona_bot"),
        bot_agent_name: campo_str("bot_agent_name"),
        msg_fallback: campo_str("msg_fallback"),
        msg_sem_info: campo_str("msg_sem_info"),
        msg_transferencia: campo_str("msg_transferencia"),
        llm_class: campo_str("llm_class"),
        model: campo_str("model"),
        llm_temperature: campo_str("llm_temperature"),
        transcription_provider: campo_str("transcription_provider"),
        transcription_model: campo_str("transcription_model"),
        vision_provider: campo_str("vision_provider"),
        vision_model: campo_str("vision_model"),
        embeddings_class: campo_str("embeddings_class"),
        embeddings_model: campo_str("embeddings_model"),
        chunk_size: val
            .get("chunk_size")
            .and_then(|v| v.as_i64())
            .unwrap_or_default() as i32,
        chunk_overlap: val
            .get("chunk_overlap")
            .and_then(|v| v.as_i64())
            .unwrap_or_default() as i32,
        similarity_threshold: campo_str("similarity_threshold"),
        vector_distance_threshold: campo_str("vector_distance_threshold"),
        api_keys: api_keys_proto,
    }
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
        let user_agent = user_agent_do_metadata(&req);
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
                    Some(user_agent.clone()),
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
                        Some(user_agent.clone()),
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
        let user_agent = user_agent_do_metadata(&req);
        tracing::Span::current().record("traceparent", tracing::field::display(&traceparent));

        let refresh_token = req.into_inner().refresh_token;
        let mut bus = self.bus.clone();
        match application::auth::refresh::refresh(&self.deps, &traceparent, &refresh_token).await {
            Ok(tokens) => Ok(Response::new(extrair_tokens(&tokens))),
            Err(err) => {
                // Reuso de refresh rotacionado: publica `token_reuse_detected` igual ao handler.
                if matches!(&err, error_core::AppError::Auth(m) if m == application::auth::refresh::REUSE_MARKER)
                {
                    publicar_reuso_detectado(&mut bus, &traceparent, ip, Some(user_agent)).await;
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
        let user_agent = user_agent_do_metadata(&req);
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
                    Some(user_agent),
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

/// Estado compartilhado para a fachada do AdminService.
pub struct AdminFacade {
    deps: Arc<AuthDeps>,
    bus: redis::aio::ConnectionManager,
    control: transport::MuxClient,
    realtime: crate::realtime::RealtimeManager,
}

impl AdminFacade {
    pub fn new(
        deps: Arc<AuthDeps>,
        bus: redis::aio::ConnectionManager,
        control: transport::MuxClient,
        realtime: crate::realtime::RealtimeManager,
    ) -> Self {
        Self {
            deps,
            bus,
            control,
            realtime,
        }
    }
}

#[tonic::async_trait]
impl AdminService for AdminFacade {
    /// ListCoreSettings: delega para o data_postgres. Exige superuser.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListCoreSettings", traceparent)
    )]
    async fn list_core_settings(
        &self,
        req: Request<ListCoreSettingsRequest>,
    ) -> Result<Response<ListCoreSettingsResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);

        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "ListCoreSettings".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({})).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };

        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }

                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;

                let settings_val = val.get("settings").and_then(|v| v.as_array());
                let mut settings = Vec::new();
                if let Some(arr) = settings_val {
                    for item in arr {
                        settings.push(ProtoCoreSetting {
                            key: item
                                .get("key")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            value: item
                                .get("value")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            encrypted: item
                                .get("encrypted")
                                .and_then(|v| v.as_bool())
                                .unwrap_or_default(),
                            description: item
                                .get("description")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                        });
                    }
                }

                Ok(Response::new(ListCoreSettingsResponse { settings }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    /// UpsertCoreSetting: delega para o data_postgres. Exige superuser.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "UpsertCoreSetting", traceparent)
    )]
    async fn upsert_core_setting(
        &self,
        req: Request<UpsertCoreSettingRequest>,
    ) -> Result<Response<UpsertCoreSettingResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let inner = req.into_inner();

        let payload = serde_json::json!({
            "key": inner.key,
            "value": inner.value,
            "encrypted": inner.encrypted,
            "description": inner.description,
        });

        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "UpsertCoreSetting".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };

        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }
                Ok(Response::new(UpsertCoreSettingResponse { success: true }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    /// DeleteCoreSetting: delega para o data_postgres. Exige superuser.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "DeleteCoreSetting", traceparent)
    )]
    async fn delete_core_setting(
        &self,
        req: Request<DeleteCoreSettingRequest>,
    ) -> Result<Response<DeleteCoreSettingResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let inner = req.into_inner();

        let payload = serde_json::json!({
            "key": inner.key,
        });

        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "DeleteCoreSetting".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };

        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }
                Ok(Response::new(DeleteCoreSettingResponse { success: true }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    /// GetTenantConfig: delega para o data_postgres. Exige superuser.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "GetTenantConfig", traceparent)
    )]
    async fn get_tenant_config(
        &self,
        req: Request<GetTenantConfigRequest>,
    ) -> Result<Response<GetTenantConfigResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let inner = req.into_inner();

        let payload = serde_json::json!({
            "tenant_id": inner.tenant_id,
        });

        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "GetTenantConfig".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };

        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }

                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;
                Ok(Response::new(mapear_tenant_config_response(&val)))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    /// UpdateTenantConfig: delega para o data_postgres. Exige superuser.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "UpdateTenantConfig", traceparent)
    )]
    async fn update_tenant_config(
        &self,
        req: Request<UpdateTenantConfigRequest>,
    ) -> Result<Response<UpdateTenantConfigResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let inner = req.into_inner();

        let mut api_keys_map = serde_json::Map::new();
        for entry in inner.api_keys {
            api_keys_map.insert(entry.key, serde_json::Value::String(entry.value));
        }

        let payload = serde_json::json!({
            "tenant_id": inner.tenant_id,
            "dados_empresa": inner.dados_empresa,
            "persona_bot": inner.persona_bot,
            "bot_agent_name": inner.bot_agent_name,
            "msg_fallback": inner.msg_fallback,
            "msg_sem_info": inner.msg_sem_info,
            "msg_transferencia": inner.msg_transferencia,
            "llm_class": inner.llm_class,
            "model": inner.model,
            "llm_temperature": inner.llm_temperature,
            "transcription_provider": inner.transcription_provider,
            "transcription_model": inner.transcription_model,
            "vision_provider": inner.vision_provider,
            "vision_model": inner.vision_model,
            "embeddings_class": inner.embeddings_class,
            "embeddings_model": inner.embeddings_model,
            "chunk_size": inner.chunk_size,
            "chunk_overlap": inner.chunk_overlap,
            "similarity_threshold": inner.similarity_threshold,
            "vector_distance_threshold": inner.vector_distance_threshold,
            "api_keys": serde_json::Value::Object(api_keys_map),
        });

        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "UpdateTenantConfig".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };

        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }
                Ok(Response::new(UpdateTenantConfigResponse { success: true }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    // --- Fase 2: Tenants ---

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListTenants", traceparent)
    )]
    async fn list_tenants(
        &self,
        req: Request<ListTenantsRequest>,
    ) -> Result<Response<ListTenantsResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "ListTenants".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({})).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };
        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }
                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;
                let list_val = val.get("tenants").and_then(|v| v.as_array());
                let mut tenants = Vec::new();
                if let Some(arr) = list_val {
                    for item in arr {
                        tenants.push(ProtoTenant {
                            id: item
                                .get("id")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            name: item
                                .get("name")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            slug: item
                                .get("slug")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            api_key: item
                                .get("api_key")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            owner_id: item
                                .get("owner_id")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default() as i32,
                            email: item
                                .get("email")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            phone: item
                                .get("phone")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            active: item
                                .get("active")
                                .and_then(|v| v.as_bool())
                                .unwrap_or_default(),
                            setup_completed: item
                                .get("setup_completed")
                                .and_then(|v| v.as_bool())
                                .unwrap_or_default(),
                            onboarding_step: item
                                .get("onboarding_step")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default()
                                as i32,
                            access_code: item
                                .get("access_code")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            created_at: item
                                .get("created_at")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default(),
                            updated_at: item
                                .get("updated_at")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default(),
                        });
                    }
                }
                Ok(Response::new(ListTenantsResponse { tenants }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "GetTenant", traceparent)
    )]
    async fn get_tenant(
        &self,
        req: Request<GetTenantRequest>,
    ) -> Result<Response<GetTenantResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let inner = req.into_inner();
        let payload = serde_json::json!({ "id": inner.id });
        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "GetTenant".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };
        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }
                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;
                let t_val = val.get("tenant");
                let proto_tenant = t_val.map(|item| ProtoTenant {
                    id: item
                        .get("id")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                    name: item
                        .get("name")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                    slug: item
                        .get("slug")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                    api_key: item
                        .get("api_key")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                    owner_id: item
                        .get("owner_id")
                        .and_then(|v| v.as_i64())
                        .unwrap_or_default() as i32,
                    email: item
                        .get("email")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                    phone: item
                        .get("phone")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                    active: item
                        .get("active")
                        .and_then(|v| v.as_bool())
                        .unwrap_or_default(),
                    setup_completed: item
                        .get("setup_completed")
                        .and_then(|v| v.as_bool())
                        .unwrap_or_default(),
                    onboarding_step: item
                        .get("onboarding_step")
                        .and_then(|v| v.as_i64())
                        .unwrap_or_default() as i32,
                    access_code: item
                        .get("access_code")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                    created_at: item
                        .get("created_at")
                        .and_then(|v| v.as_i64())
                        .unwrap_or_default(),
                    updated_at: item
                        .get("updated_at")
                        .and_then(|v| v.as_i64())
                        .unwrap_or_default(),
                });
                Ok(Response::new(GetTenantResponse {
                    tenant: proto_tenant,
                }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "CreateTenant", traceparent)
    )]
    async fn create_tenant(
        &self,
        req: Request<CreateTenantRequest>,
    ) -> Result<Response<CreateTenantResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let inner = req.into_inner();
        let payload = serde_json::json!({
            "name": inner.name,
            "slug": inner.slug,
            "owner_id": if inner.owner_id > 0 { Some(inner.owner_id) } else { None },
            "email": if !inner.email.is_empty() { Some(inner.email) } else { None },
            "phone": if !inner.phone.is_empty() { Some(inner.phone) } else { None }
        });
        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "CreateTenant".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };
        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }
                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;
                let t_val = val.get("tenant");
                let proto_tenant = t_val.map(|item| ProtoTenant {
                    id: item
                        .get("id")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                    name: item
                        .get("name")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                    slug: item
                        .get("slug")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                    api_key: item
                        .get("api_key")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                    owner_id: item
                        .get("owner_id")
                        .and_then(|v| v.as_i64())
                        .unwrap_or_default() as i32,
                    email: item
                        .get("email")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                    phone: item
                        .get("phone")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                    active: item
                        .get("active")
                        .and_then(|v| v.as_bool())
                        .unwrap_or_default(),
                    setup_completed: item
                        .get("setup_completed")
                        .and_then(|v| v.as_bool())
                        .unwrap_or_default(),
                    onboarding_step: item
                        .get("onboarding_step")
                        .and_then(|v| v.as_i64())
                        .unwrap_or_default() as i32,
                    access_code: item
                        .get("access_code")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                    created_at: item
                        .get("created_at")
                        .and_then(|v| v.as_i64())
                        .unwrap_or_default(),
                    updated_at: item
                        .get("updated_at")
                        .and_then(|v| v.as_i64())
                        .unwrap_or_default(),
                });
                Ok(Response::new(CreateTenantResponse {
                    tenant: proto_tenant,
                }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "UpdateTenant", traceparent)
    )]
    async fn update_tenant(
        &self,
        req: Request<UpdateTenantRequest>,
    ) -> Result<Response<UpdateTenantResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let inner = req.into_inner();
        let payload = serde_json::json!({
            "id": inner.id,
            "name": inner.name,
            "slug": inner.slug,
            "owner_id": inner.owner_id,
            "email": inner.email,
            "phone": if !inner.phone.is_empty() { Some(inner.phone) } else { None }
        });
        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "UpdateTenant".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };
        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }
                Ok(Response::new(UpdateTenantResponse { success: true }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "SetTenantActive", traceparent)
    )]
    async fn set_tenant_active(
        &self,
        req: Request<SetTenantActiveRequest>,
    ) -> Result<Response<SetTenantActiveResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let inner = req.into_inner();
        let payload = serde_json::json!({
            "id": inner.id,
            "active": inner.active
        });
        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "SetTenantActive".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };
        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }
                Ok(Response::new(SetTenantActiveResponse { success: true }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "GenerateAccessCode", traceparent)
    )]
    async fn generate_access_code(
        &self,
        req: Request<GenerateAccessCodeRequest>,
    ) -> Result<Response<GenerateAccessCodeResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let inner = req.into_inner();
        let payload = serde_json::json!({ "id": inner.id });
        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "GenerateAccessCode".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };
        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }
                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;
                let access_code = val
                    .get("access_code")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string();
                Ok(Response::new(GenerateAccessCodeResponse { access_code }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    // --- Fase 2: Billing ---

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListPlans", traceparent)
    )]
    async fn list_plans(
        &self,
        req: Request<ListPlansRequest>,
    ) -> Result<Response<ListPlansResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "ListPlans".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({})).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };
        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }
                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;
                let list_val = val.get("plans").and_then(|v| v.as_array());
                let mut plans = Vec::new();
                if let Some(arr) = list_val {
                    for item in arr {
                        plans.push(ProtoPlan {
                            id: item.get("id").and_then(|v| v.as_i64()).unwrap_or_default() as i32,
                            name: item
                                .get("name")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            description: item
                                .get("description")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            price: item
                                .get("price")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            max_instances: item
                                .get("max_instances")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default()
                                as i32,
                            max_departments: item
                                .get("max_departments")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default()
                                as i32,
                            active: item
                                .get("active")
                                .and_then(|v| v.as_bool())
                                .unwrap_or_default(),
                            created_at: item
                                .get("created_at")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default(),
                        });
                    }
                }
                Ok(Response::new(ListPlansResponse { plans }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "CreatePlan", traceparent)
    )]
    async fn create_plan(
        &self,
        req: Request<CreatePlanRequest>,
    ) -> Result<Response<CreatePlanResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let inner = req.into_inner();
        let payload = serde_json::json!({
            "name": inner.name,
            "description": inner.description,
            "price": inner.price,
            "max_instances": inner.max_instances,
            "max_departments": inner.max_departments
        });
        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "CreatePlan".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };
        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }
                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;
                let p_val = val.get("plan");
                let proto_plan = p_val.map(|item| ProtoPlan {
                    id: item.get("id").and_then(|v| v.as_i64()).unwrap_or_default() as i32,
                    name: item
                        .get("name")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                    description: item
                        .get("description")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                    price: item
                        .get("price")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                    max_instances: item
                        .get("max_instances")
                        .and_then(|v| v.as_i64())
                        .unwrap_or_default() as i32,
                    max_departments: item
                        .get("max_departments")
                        .and_then(|v| v.as_i64())
                        .unwrap_or_default() as i32,
                    active: item
                        .get("active")
                        .and_then(|v| v.as_bool())
                        .unwrap_or_default(),
                    created_at: item
                        .get("created_at")
                        .and_then(|v| v.as_i64())
                        .unwrap_or_default(),
                });
                Ok(Response::new(CreatePlanResponse { plan: proto_plan }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "UpdatePlan", traceparent)
    )]
    async fn update_plan(
        &self,
        req: Request<UpdatePlanRequest>,
    ) -> Result<Response<UpdatePlanResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let inner = req.into_inner();
        let payload = serde_json::json!({
            "id": inner.id,
            "name": inner.name,
            "description": inner.description,
            "price": inner.price,
            "max_instances": inner.max_instances,
            "max_departments": inner.max_departments,
            "active": inner.active
        });
        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "UpdatePlan".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };
        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }
                Ok(Response::new(UpdatePlanResponse { success: true }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListSubscriptions", traceparent)
    )]
    async fn list_subscriptions(
        &self,
        req: Request<ListSubscriptionsRequest>,
    ) -> Result<Response<ListSubscriptionsResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "ListSubscriptions".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({})).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };
        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }
                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;
                let list_val = val.get("subscriptions").and_then(|v| v.as_array());
                let mut subscriptions = Vec::new();
                if let Some(arr) = list_val {
                    for item in arr {
                        subscriptions.push(ProtoSubscription {
                            id: item.get("id").and_then(|v| v.as_i64()).unwrap_or_default() as i32,
                            tenant_id: item
                                .get("tenant_id")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            plan_id: item
                                .get("plan_id")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default() as i32,
                            status: item
                                .get("status")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            current_period_start: item
                                .get("current_period_start")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default(),
                            current_period_end: item
                                .get("current_period_end")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default(),
                            payment_gateway: item
                                .get("payment_gateway")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            external_customer_id: item
                                .get("external_customer_id")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            external_subscription_id: item
                                .get("external_subscription_id")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            updated_at: item
                                .get("updated_at")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default(),
                        });
                    }
                }
                Ok(Response::new(ListSubscriptionsResponse { subscriptions }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "RegisterPayment", traceparent)
    )]
    async fn register_payment(
        &self,
        req: Request<RegisterPaymentRequest>,
    ) -> Result<Response<RegisterPaymentResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let inner = req.into_inner();
        let payload = serde_json::json!({
            "tenant_id": inner.tenant_id,
            "amount": inner.amount,
            "payment_method": inner.payment_method,
            "payment_date": inner.payment_date,
            "period_start": inner.period_start,
            "period_end": inner.period_end,
            "notes": inner.notes
        });
        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "RegisterPayment".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };
        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }
                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;
                let p_val = val.get("payment");
                let proto_payment = p_val.map(|item| ProtoPaymentRecord {
                    id: item.get("id").and_then(|v| v.as_i64()).unwrap_or_default() as i32,
                    tenant_id: item
                        .get("tenant_id")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                    amount: item
                        .get("amount")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                    payment_date: item
                        .get("payment_date")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                    payment_method: item
                        .get("payment_method")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                    period_start: item
                        .get("period_start")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                    period_end: item
                        .get("period_end")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                    notes: item
                        .get("notes")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                    recorded_by_id: item
                        .get("recorded_by_id")
                        .and_then(|v| v.as_i64())
                        .unwrap_or_default() as i32,
                    created_at: item
                        .get("created_at")
                        .and_then(|v| v.as_i64())
                        .unwrap_or_default(),
                });
                Ok(Response::new(RegisterPaymentResponse {
                    payment: proto_payment,
                }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListPayments", traceparent)
    )]
    async fn list_payments(
        &self,
        req: Request<ListPaymentsRequest>,
    ) -> Result<Response<ListPaymentsResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let inner = req.into_inner();
        let payload = serde_json::json!({
            "tenant_id": if !inner.tenant_id.is_empty() { Some(inner.tenant_id) } else { None }
        });
        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "ListPayments".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };
        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }
                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;
                let list_val = val.get("payments").and_then(|v| v.as_array());
                let mut payments = Vec::new();
                if let Some(arr) = list_val {
                    for item in arr {
                        payments.push(ProtoPaymentRecord {
                            id: item.get("id").and_then(|v| v.as_i64()).unwrap_or_default() as i32,
                            tenant_id: item
                                .get("tenant_id")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            amount: item
                                .get("amount")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            payment_date: item
                                .get("payment_date")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            payment_method: item
                                .get("payment_method")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            period_start: item
                                .get("period_start")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            period_end: item
                                .get("period_end")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            notes: item
                                .get("notes")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            recorded_by_id: item
                                .get("recorded_by_id")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default()
                                as i32,
                            created_at: item
                                .get("created_at")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default(),
                        });
                    }
                }
                Ok(Response::new(ListPaymentsResponse { payments }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    // --- Fase 3: Evolution Connection ---

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "TestEvolutionConnection", traceparent)
    )]
    async fn test_evolution_connection(
        &self,
        req: Request<TestEvolutionConnectionRequest>,
    ) -> Result<Response<TestEvolutionConnectionResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let ip = ip_do_metadata(&req);
        let user_agent = user_agent_do_metadata(&req);
        let inner = req.into_inner();

        let payload = serde_json::json!({
            "tenant_id": inner.tenant_id,
        });

        let env_req = Envelope {
            tenant_id: inner.tenant_id.clone(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "TestEvolutionConnection".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };

        match self
            .control
            .call(env_req, std::time::Duration::from_secs(10))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!(
                        "Erro no control_plane: {}",
                        err_msg
                    )));
                }

                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;

                let state = val
                    .get("status")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string();

                // Auditoria obrigatória do teste de conexão (catálogo §12). O `context`
                // registra apenas o tenant alvo e o estado retornado — nunca a api_key.
                let tenant_alvo = Uuid::parse_str(&inner.tenant_id)
                    .ok()
                    .filter(|u| !u.is_nil());
                let mut bus = self.bus.clone();
                publicar_auditoria_borda(
                    &mut bus,
                    tenant_alvo,
                    "INFO",
                    "connection_tested",
                    "Teste de conexão Evolution executado (borda gRPC-Web).".to_string(),
                    serde_json::json!({ "tenant_id": inner.tenant_id, "state": state }),
                    claims.sub.parse::<i32>().ok(),
                    &traceparent,
                    ip,
                    Some(user_agent),
                )
                .await;

                Ok(Response::new(TestEvolutionConnectionResponse {
                    status: state,
                    error_message: val
                        .get("error_message")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string(),
                }))
            }
            Err(e) => Err(Status::internal(format!("Falha no control_plane: {}", e))),
        }
    }

    // --- Fase 4: Feature Flags ---

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListFeatureFlags", traceparent)
    )]
    async fn list_feature_flags(
        &self,
        req: Request<ListFeatureFlagsRequest>,
    ) -> Result<Response<ListFeatureFlagsResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);

        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "ListFeatureFlags".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({})).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };

        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }

                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;

                let flags_val = val.get("flags").and_then(|v| v.as_array());
                let mut flags = Vec::new();
                if let Some(arr) = flags_val {
                    for item in arr {
                        let mut overrides = Vec::new();
                        if let Some(ovs_arr) = item.get("overrides").and_then(|v| v.as_array()) {
                            for ov in ovs_arr {
                                overrides.push(ProtoFeatureFlagOverride {
                                    tenant_id: ov
                                        .get("tenant_id")
                                        .and_then(|v| v.as_str())
                                        .unwrap_or_default()
                                        .to_string(),
                                    enabled: ov
                                        .get("enabled")
                                        .and_then(|v| v.as_bool())
                                        .unwrap_or_default(),
                                });
                            }
                        }
                        flags.push(ProtoFeatureFlag {
                            key: item
                                .get("key")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            description: item
                                .get("description")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            enabled_globally: item
                                .get("enabled_globally")
                                .and_then(|v| v.as_bool())
                                .unwrap_or_default(),
                            overrides,
                        });
                    }
                }

                Ok(Response::new(ListFeatureFlagsResponse { flags }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "SetFeatureFlag", traceparent)
    )]
    async fn set_feature_flag(
        &self,
        req: Request<SetFeatureFlagRequest>,
    ) -> Result<Response<SetFeatureFlagResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let inner = req.into_inner();

        let payload = serde_json::json!({
            "key": inner.key,
            "enabled_globally": inner.enabled_globally,
        });

        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "SetFeatureFlag".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };

        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }
                Ok(Response::new(SetFeatureFlagResponse { success: true }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "SetFeatureFlagOverride", traceparent)
    )]
    async fn set_feature_flag_override(
        &self,
        req: Request<SetFeatureFlagOverrideRequest>,
    ) -> Result<Response<SetFeatureFlagOverrideResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let inner = req.into_inner();

        let payload = serde_json::json!({
            "key": inner.key,
            "tenant_id": inner.tenant_id,
            "enabled": inner.enabled,
            "remove_override": inner.remove_override,
        });

        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "SetFeatureFlagOverride".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };

        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }
                Ok(Response::new(SetFeatureFlagOverrideResponse {
                    success: true,
                }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    // --- Fase 5: Auditoria & Saúde ---

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "QueryAuditLog", traceparent)
    )]
    async fn query_audit_log(
        &self,
        req: Request<QueryAuditLogRequest>,
    ) -> Result<Response<QueryAuditLogResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let inner = req.into_inner();

        let payload = serde_json::json!({
            "tenant_id": inner.tenant_id,
            "event_type": inner.event_type,
            "limit": inner.limit,
            "offset": inner.offset,
        });

        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "QueryAuditLog".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };

        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }

                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;

                let entries_val = val.get("entries").and_then(|v| v.as_array());
                let mut entries = Vec::new();
                if let Some(arr) = entries_val {
                    for (idx, item) in arr.iter().enumerate() {
                        entries.push(ProtoAuditLogEntry {
                            id: (idx + 1) as i32,
                            event_type: item
                                .get("event_type")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            actor: item
                                .get("user_id")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default()
                                .to_string(),
                            tenant_id: item
                                .get("tenant_id")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            description: item
                                .get("description")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            ip_address: item
                                .get("ip_address")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            user_agent: String::new(),
                            created_at: item
                                .get("created_at")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default(),
                        });
                    }
                }

                let total_count = val
                    .get("total_count")
                    .and_then(|v| v.as_i64())
                    .unwrap_or_default() as i32;

                Ok(Response::new(QueryAuditLogResponse {
                    entries,
                    total_count,
                }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "GetServiceHealth", traceparent)
    )]
    async fn get_service_health(
        &self,
        req: Request<GetServiceHealthRequest>,
    ) -> Result<Response<GetServiceHealthResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);

        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "GetServiceHealth".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({})).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };

        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }

                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;

                let services_val = val.get("services").and_then(|v| v.as_array());
                let mut services = Vec::new();
                if let Some(arr) = services_val {
                    for item in arr {
                        services.push(ProtoServiceHealth {
                            service_name: item
                                .get("service_name")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            status: item
                                .get("status")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            message: item
                                .get("message")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            response_time_ms: item
                                .get("response_time_ms")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default(),
                        });
                    }
                }

                Ok(Response::new(GetServiceHealthResponse { services }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "GetDashboardSummary", traceparent)
    )]
    async fn get_dashboard_summary(
        &self,
        req: Request<GetDashboardSummaryRequest>,
    ) -> Result<Response<GetDashboardSummaryResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);

        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "GetDashboardSummary".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({})).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };

        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }

                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;

                let total_tenants = val
                    .get("total_tenants")
                    .and_then(|v| v.as_i64())
                    .unwrap_or_default() as i32;
                let active_tenants = val
                    .get("active_tenants")
                    .and_then(|v| v.as_i64())
                    .unwrap_or_default() as i32;
                let total_subscriptions = val
                    .get("total_subscriptions")
                    .and_then(|v| v.as_i64())
                    .unwrap_or_default() as i32;
                let monthly_recurring_revenue = val
                    .get("monthly_recurring_revenue")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string();

                let health_val = val.get("health").and_then(|v| v.as_array());
                let mut health = Vec::new();
                if let Some(arr) = health_val {
                    for item in arr {
                        health.push(ProtoServiceHealth {
                            service_name: item
                                .get("service_name")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            status: item
                                .get("status")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            message: item
                                .get("message")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            response_time_ms: item
                                .get("response_time_ms")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default(),
                        });
                    }
                }

                Ok(Response::new(GetDashboardSummaryResponse {
                    total_tenants,
                    active_tenants,
                    total_subscriptions,
                    monthly_recurring_revenue,
                    health,
                }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    // --- Fase 6: Operacional (fila/Kanban/chat — WS-6). Exige só autenticação (não
    // superuser); o RBAC fino por fluxo (flow_permissions, WS-5a) é aplicado no
    // data_postgres sobre cada atendimento/fluxo. ---

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListAtendimentos", traceparent)
    )]
    async fn list_atendimentos(
        &self,
        req: Request<ListAtendimentosRequest>,
    ) -> Result<Response<ListAtendimentosResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;
        let inner = req.into_inner();

        let payload = serde_json::json!({
            "status": if inner.status.is_empty() { "fila" } else { &inner.status },
            "departamento_id": if inner.departamento_id > 0 { Some(inner.departamento_id) } else { None },
            "limit": if inner.limit > 0 { inner.limit } else { 50 },
        });

        // RBAC fino por fluxo (WS-5a): popula flow_permissions para que o filtro do
        // data_postgres (listar_por_status) mostre ao atendente só os fluxos permitidos.
        let auth_user_id = claims.sub.parse::<i32>().unwrap_or(0);
        let flow_permissions = if claims.is_superuser {
            Vec::new()
        } else {
            resolver_flow_permissions_web(&self.deps, &claims.tenant_id, auth_user_id, &traceparent)
                .await
        };

        let env_req = Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "ListAtendimentos".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id,
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: claims.is_superuser,
            flow_permissions,
            ..Default::default()
        };

        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }

                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;

                let mut atendimentos = Vec::new();
                if let Some(arr) = val.get("atendimentos").and_then(|v| v.as_array()) {
                    for item in arr {
                        atendimentos.push(ProtoAtendimentoResumo {
                            id: item.get("id").and_then(|v| v.as_i64()).unwrap_or_default() as i32,
                            contato_id: item
                                .get("contato_id")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default() as i32,
                            status: item
                                .get("status")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            departamento_id: item
                                .get("departamento_id")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default()
                                as i32,
                            fluxo_atendimento_id: item
                                .get("fluxo_atendimento_id")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default()
                                as i32,
                            etapa_atual_id: item
                                .get("etapa_atual_id")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default()
                                as i32,
                            assunto: item
                                .get("assunto")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            prioridade: item
                                .get("prioridade")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            atendente_humano_id: item
                                .get("atendente_humano_id")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default()
                                as i32,
                            data_inicio: item
                                .get("data_inicio")
                                .and_then(|v| v.as_str())
                                .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
                                .map(|d| d.timestamp_millis())
                                .unwrap_or_default(),
                            data_ultima_mensagem: item
                                .get("data_ultima_mensagem")
                                .and_then(|v| v.as_str())
                                .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
                                .map(|d| d.timestamp_millis())
                                .unwrap_or_default(),
                            // Passagem direta (N6.5): sentimento vem pronto do
                            // data_postgres; ausência/null viram None.
                            sentimento_nota: item
                                .get("sentimento_nota")
                                .and_then(|v| v.as_i64())
                                .map(|n| n as i32),
                            sentimento_label: item
                                .get("sentimento_label")
                                .and_then(|v| v.as_str())
                                .map(|s| s.to_string()),
                        });
                    }
                }

                Ok(Response::new(ListAtendimentosResponse { atendimentos }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "GetThread", traceparent)
    )]
    async fn get_thread(
        &self,
        req: Request<GetThreadRequest>,
    ) -> Result<Response<GetThreadResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;
        let inner = req.into_inner();

        let payload = serde_json::json!({
            "atendimento_id": inner.atendimento_id,
            "limit": if inner.limit > 0 { inner.limit } else { 50 },
            "offset": inner.offset,
        });

        let env_req = Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "GetThread".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: claims.is_superuser,
            ..Default::default()
        };

        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }

                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;

                let mut mensagens = Vec::new();
                if let Some(arr) = val.get("mensagens").and_then(|v| v.as_array()) {
                    for item in arr {
                        mensagens.push(ProtoMensagemThread {
                            id: item.get("id").and_then(|v| v.as_i64()).unwrap_or_default() as i32,
                            atendimento_id: item
                                .get("atendimento_id")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default()
                                as i32,
                            tipo: item
                                .get("tipo")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            conteudo: item
                                .get("conteudo")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            remetente: item
                                .get("remetente")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            timestamp: item
                                .get("timestamp")
                                .and_then(|v| v.as_str())
                                .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
                                .map(|d| d.timestamp_millis())
                                .unwrap_or_default(),
                            status_envio: item
                                .get("status_envio")
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string(),
                            // Passagem direta (N6.2): campos de IA vêm prontos do
                            // data_postgres; ausência/null viram default (false/None).
                            gerado_por_ia: item
                                .get("gerado_por_ia")
                                .and_then(|v| v.as_bool())
                                .unwrap_or(false),
                            resumo_midia: item
                                .get("resumo_midia")
                                .and_then(|v| v.as_str())
                                .map(|s| s.to_string()),
                        });
                    }
                }

                Ok(Response::new(GetThreadResponse { mensagens }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "MoveAtendimentoEtapa", traceparent)
    )]
    async fn move_atendimento_etapa(
        &self,
        req: Request<MoveAtendimentoEtapaRequest>,
    ) -> Result<Response<MoveAtendimentoEtapaResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let ip = ip_do_metadata(&req);
        let user_agent = user_agent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;
        let inner = req.into_inner();

        let payload = serde_json::json!({
            "atendimento_id": inner.atendimento_id,
            "etapa_destino_id": inner.etapa_destino_id,
            "motivo": if inner.motivo.is_empty() { None } else { Some(inner.motivo.clone()) },
            // N7.2: aditivo/opcional — clientes antigos (sem action_id) seguem sem dedupe.
            "action_id": inner.action_id.clone(),
        });

        // RBAC fino por fluxo (WS-5a): popula flow_permissions para que o exigir_fluxo
        // do data_postgres autorize o atendente a mover cards do fluxo permitido.
        let auth_user_id = claims.sub.parse::<i32>().unwrap_or(0);
        let flow_permissions = if claims.is_superuser {
            Vec::new()
        } else {
            resolver_flow_permissions_web(&self.deps, &claims.tenant_id, auth_user_id, &traceparent)
                .await
        };

        let env_req = Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "MoveAtendimentoEtapa".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id,
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: claims.is_superuser,
            flow_permissions,
            ..Default::default()
        };

        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err = resp.error.unwrap_or_default();
                    // `AUTH_INSUFFICIENT_SCOPE` é o código estável de PermissionDenied
                    // (RBAC fino por fluxo, WS-5a) — ver error_core::envelope_bridge.
                    if err.code == "AUTH_INSUFFICIENT_SCOPE" {
                        let mut bus = self.bus.clone();
                        publicar_auditoria_borda(
                            &mut bus,
                            Some(tenant_uuid),
                            "WARN",
                            "autorizacao.negada",
                            "Movimentação de Kanban barrada por RBAC fino de fluxo.".to_string(),
                            serde_json::json!({ "atendimento_id": inner.atendimento_id }),
                            claims.sub.parse::<i32>().ok(),
                            &traceparent,
                            ip,
                            Some(user_agent),
                        )
                        .await;
                        return Err(Status::permission_denied("errors.auth.forbidden"));
                    }
                    return Err(Status::internal(format!("Erro no banco: {}", err.message)));
                }

                let mut bus = self.bus.clone();
                publicar_auditoria_borda(
                    &mut bus,
                    Some(tenant_uuid),
                    "INFO",
                    "kanban.movido",
                    "Atendimento movido de etapa no Kanban.".to_string(),
                    serde_json::json!({
                        "atendimento_id": inner.atendimento_id,
                        "etapa_destino_id": inner.etapa_destino_id,
                    }),
                    claims.sub.parse::<i32>().ok(),
                    &traceparent,
                    ip,
                    Some(user_agent),
                )
                .await;

                // Realtime: publica no mesmo canal Pub/Sub que o RealtimeManager já consome,
                // para que outras telas conectadas reflitam o movimento sem polling.
                let mut bus_evento = self.bus.clone();
                let event_payload = serde_json::json!({
                    "event_type": "kanban.movido",
                    "tenant_id": tenant_uuid.to_string(),
                    "payload": {
                        "atendimento_id": inner.atendimento_id,
                        "etapa_destino_id": inner.etapa_destino_id,
                    }
                });
                let channel = format!("tenant:{}:events", tenant_uuid);
                let publish_res: Result<u32, _> = redis::cmd("PUBLISH")
                    .arg(&channel)
                    .arg(event_payload.to_string())
                    .query_async(&mut bus_evento)
                    .await;
                if let Err(e) = publish_res {
                    tracing::error!("Erro ao publicar kanban.movido no Redis Pub/Sub: {:?}", e);
                }

                Ok(Response::new(MoveAtendimentoEtapaResponse {
                    success: true,
                }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "SendOutboundMessage", traceparent)
    )]
    async fn send_outbound_message(
        &self,
        req: Request<SendOutboundMessageRequest>,
    ) -> Result<Response<SendOutboundMessageResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let ip = ip_do_metadata(&req);
        let user_agent = user_agent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;
        let inner = req.into_inner();

        if inner.conteudo.trim().is_empty() {
            return Err(Status::invalid_argument("errors.validation"));
        }

        let payload = serde_json::json!({
            "atendimento_id": inner.atendimento_id,
            // NUNCA logar `conteudo` fora do payload RPC (é PII/mensagem do usuário).
            "conteudo": inner.conteudo,
            "tipo": if inner.tipo.is_empty() { "texto" } else { &inner.tipo },
            // N7.2: aditivo/opcional — clientes antigos (sem action_id) seguem sem dedupe.
            "action_id": inner.action_id.clone(),
        });

        let env_req = Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "SendOutboundMessage".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: claims.is_superuser,
            ..Default::default()
        };

        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }

                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;
                let message_id = val
                    .get("message_id")
                    .and_then(|v| v.as_i64())
                    .unwrap_or_default() as i32;

                // Auditoria SEM o conteúdo da mensagem (é PII) — só metadados.
                let mut bus = self.bus.clone();
                publicar_auditoria_borda(
                    &mut bus,
                    Some(tenant_uuid),
                    "INFO",
                    "mensagem.enviada",
                    "Mensagem outbound enviada pelo atendente.".to_string(),
                    serde_json::json!({
                        "atendimento_id": inner.atendimento_id,
                        "message_id": message_id,
                    }),
                    claims.sub.parse::<i32>().ok(),
                    &traceparent,
                    ip,
                    Some(user_agent),
                )
                .await;

                // Realtime: publica no mesmo canal Pub/Sub que o worker usa para
                // `mensagem.recebida`, mantendo o chat lateral em tempo real também para
                // mensagens outbound (sem incluir o conteúdo — a UI recarrega o thread).
                let mut bus_evento = self.bus.clone();
                let event_payload = serde_json::json!({
                    "event_type": "mensagem.enviada",
                    "tenant_id": tenant_uuid.to_string(),
                    "payload": {
                        "atendimento_id": inner.atendimento_id,
                        "message_id": message_id,
                    }
                });
                let channel = format!("tenant:{}:events", tenant_uuid);
                let publish_res: Result<u32, _> = redis::cmd("PUBLISH")
                    .arg(&channel)
                    .arg(event_payload.to_string())
                    .query_async(&mut bus_evento)
                    .await;
                if let Err(e) = publish_res {
                    tracing::error!(
                        "Erro ao publicar mensagem.enviada no Redis Pub/Sub: {:?}",
                        e
                    );
                }

                Ok(Response::new(SendOutboundMessageResponse { message_id }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    type StreamAtendimentosStream =
        tokio_stream::wrappers::ReceiverStream<Result<AtendimentoEvent, Status>>;

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "StreamAtendimentos", traceparent)
    )]
    async fn stream_atendimentos(
        &self,
        req: Request<StreamAtendimentosRequest>,
    ) -> Result<Response<Self::StreamAtendimentosStream>, Status> {
        let traceparent = traceparent_do_metadata(&req);
        let ip = ip_do_metadata(&req);
        let user_agent = user_agent_do_metadata(&req);

        let token = bearer_do_metadata(&req);
        let token = token.strip_prefix("Bearer ").unwrap_or(&token).trim();
        let claims = match application::jwt::validar_access_token(token) {
            Ok(c) => c,
            Err(_) => {
                // Auditoria de tentativa de abertura de stream sem autorização (sem tenant conhecido).
                let mut bus = self.bus.clone();
                publicar_auditoria_borda(
                    &mut bus,
                    None,
                    "WARN",
                    "stream.nao_autorizado",
                    "Tentativa de abrir stream de atendimentos com token inválido.".to_string(),
                    serde_json::json!({ "reason": "invalid_token" }),
                    None,
                    &traceparent,
                    ip.clone(),
                    Some(user_agent.clone()),
                )
                .await;
                return Err(Status::unauthenticated("errors.auth"));
            }
        };

        let tenant_uuid = match Uuid::parse_str(&claims.tenant_id) {
            Ok(u) => u,
            Err(_) => {
                let mut bus = self.bus.clone();
                publicar_auditoria_borda(
                    &mut bus,
                    None,
                    "WARN",
                    "stream.nao_autorizado",
                    "Tentativa de abrir stream com tenant_id inválido no token.".to_string(),
                    serde_json::json!({ "user_id": claims.sub, "reason": "invalid_tenant" }),
                    claims.sub.parse::<i32>().ok(),
                    &traceparent,
                    ip.clone(),
                    Some(user_agent.clone()),
                )
                .await;
                return Err(Status::invalid_argument("Invalid tenant UUID"));
            }
        };

        tracing::info!(tenant_id = %tenant_uuid, user_id = %claims.sub, "Conexão de streaming de atendimentos aberta");

        let mut bus = self.bus.clone();
        publicar_auditoria_borda(
            &mut bus,
            Some(tenant_uuid),
            "INFO",
            "stream.aberto",
            "Stream realtime de atendimentos aberto pelo usuário.".to_string(),
            serde_json::json!({ "user_id": claims.sub }),
            claims.sub.parse::<i32>().ok(),
            &traceparent,
            ip.clone(),
            Some(user_agent.clone()),
        )
        .await;

        let mut broadcast_rx = self.realtime.obter_stream(tenant_uuid).await?;

        let (tx, rx) = tokio::sync::mpsc::channel(100);

        let mut bus_clone = self.bus.clone();
        let traceparent_clone = traceparent.clone();
        let ip_clone = ip;
        let user_agent_clone = user_agent;
        let sub_clone = claims.sub.clone();
        tokio::spawn(async move {
            while let Ok(event) = broadcast_rx.recv().await {
                if tx.send(Ok(event)).await.is_err() {
                    break;
                }
            }

            publicar_auditoria_borda(
                &mut bus_clone,
                Some(tenant_uuid),
                "INFO",
                "stream.fechado",
                "Stream realtime de atendimentos encerrado.".to_string(),
                serde_json::json!({ "user_id": sub_clone }),
                sub_clone.parse::<i32>().ok(),
                &traceparent_clone,
                ip_clone,
                Some(user_agent_clone),
            )
            .await;
        });

        Ok(Response::new(tokio_stream::wrappers::ReceiverStream::new(
            rx,
        )))
    }

    type ExportTenantsCsvStream = std::pin::Pin<
        Box<
            dyn futures_util::Stream<Item = Result<ExportTenantsCsvResponse, Status>>
                + Send
                + 'static,
        >,
    >;

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ExportTenantsCsv", traceparent)
    )]
    async fn export_tenants_csv(
        &self,
        req: Request<ExportTenantsCsvRequest>,
    ) -> Result<Response<Self::ExportTenantsCsvStream>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);

        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "ExportTenantsCsv".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({})).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };

        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(10))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
                    return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
                }

                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;

                let csv_data_str = val
                    .get("csv_data")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default();
                let csv_bytes = csv_data_str.as_bytes().to_vec();

                let chunk_size = 64 * 1024;
                let chunks: Vec<Result<ExportTenantsCsvResponse, Status>> = csv_bytes
                    .chunks(chunk_size)
                    .map(|chunk| {
                        Ok(ExportTenantsCsvResponse {
                            chunk: chunk.to_vec(),
                        })
                    })
                    .collect();

                let stream = futures_util::stream::iter(chunks);
                Ok(Response::new(
                    Box::pin(stream) as Self::ExportTenantsCsvStream
                ))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    // --- Fase N3: Painel do Tenant (convites, usuários, config tenant-scoped) ---
    // Guard `exigir_autenticado_do_metadata` (não superuser): o RBAC fino `tenant:admin`
    // é aplicado dentro do data_postgres. `tenant_id` sempre vem de `claims.tenant_id`,
    // nunca do request (um tenant não pode agir sobre outro). Segue fielmente o padrão
    // de passthrough já usado por `create_tenant`/`update_tenant` (sem auditoria própria
    // na borda — a auditoria de negócio já acontece no `data_postgres`).

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "CreateInvite", traceparent)
    )]
    async fn create_invite(
        &self,
        req: Request<CreateInviteRequest>,
    ) -> Result<Response<CreateInviteResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;
        let inner = req.into_inner();

        let payload = serde_json::json!({
            "email": inner.email,
            "name": inner.name,
            "role": if inner.role.is_empty() { "staff" } else { &inner.role },
            "module_permissions": inner.module_permissions,
            "flow_permissions": inner.flow_permissions,
        });

        let env_req = Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "CreateInvite".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: claims.is_superuser,
            ..Default::default()
        };

        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    return Err(status_do_erro_interno(resp.error));
                }
                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;
                let invite = val.get("invite");

                Ok(Response::new(CreateInviteResponse {
                    invite: invite.map(|i| TenantInviteCreated {
                        id: i
                            .get("id")
                            .and_then(|v| v.as_str())
                            .unwrap_or_default()
                            .to_string(),
                        tenant_id: i
                            .get("tenant_id")
                            .and_then(|v| v.as_str())
                            .unwrap_or_default()
                            .to_string(),
                        email: i
                            .get("email")
                            .and_then(|v| v.as_str())
                            .unwrap_or_default()
                            .to_string(),
                        name: i
                            .get("name")
                            .and_then(|v| v.as_str())
                            .unwrap_or_default()
                            .to_string(),
                        role: i
                            .get("role")
                            .and_then(|v| v.as_str())
                            .unwrap_or_default()
                            .to_string(),
                        token: i
                            .get("token")
                            .and_then(|v| v.as_str())
                            .unwrap_or_default()
                            .to_string(),
                        expires_at: i
                            .get("expires_at")
                            .and_then(|v| v.as_i64())
                            .unwrap_or_default(),
                        used: i.get("used").and_then(|v| v.as_bool()).unwrap_or_default(),
                        created_at: i
                            .get("created_at")
                            .and_then(|v| v.as_i64())
                            .unwrap_or_default(),
                    }),
                }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    /// AcceptInvite: rota PÚBLICA (sem sessão) — o convidado ainda não tem conta;
    /// o tenant é resolvido pelo token do convite dentro do data_postgres.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "AcceptInvite", traceparent)
    )]
    async fn accept_invite(
        &self,
        req: Request<AcceptInviteRequest>,
    ) -> Result<Response<AcceptInviteResponse>, Status> {
        let traceparent = traceparent_do_metadata(&req);
        let inner = req.into_inner();

        let payload = serde_json::json!({
            "token": inner.token,
            "username": inner.username,
            "email": inner.email,
            "password": inner.password,
        });

        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "AcceptInvite".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            ..Default::default()
        };

        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    return Err(status_do_erro_interno(resp.error));
                }
                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;
                let tu = val.get("tenant_user");

                Ok(Response::new(AcceptInviteResponse {
                    tenant_user: tu.map(|u| AcceptedTenantUser {
                        id: u.get("id").and_then(|v| v.as_i64()).unwrap_or_default() as i32,
                        user_id: u
                            .get("user_id")
                            .and_then(|v| v.as_i64())
                            .unwrap_or_default() as i32,
                        tenant_id: u
                            .get("tenant_id")
                            .and_then(|v| v.as_str())
                            .unwrap_or_default()
                            .to_string(),
                        role: u
                            .get("role")
                            .and_then(|v| v.as_str())
                            .unwrap_or_default()
                            .to_string(),
                        module_permissions: json_strings(u.get("module_permissions")),
                        flow_permissions: json_i32s(u.get("flow_permissions")),
                        is_active: u
                            .get("is_active")
                            .and_then(|v| v.as_bool())
                            .unwrap_or_default(),
                    }),
                }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListInvites", traceparent)
    )]
    async fn list_invites(
        &self,
        req: Request<ListInvitesRequest>,
    ) -> Result<Response<ListInvitesResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;

        let env_req = Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "ListInvites".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({})).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: claims.is_superuser,
            ..Default::default()
        };

        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    return Err(status_do_erro_interno(resp.error));
                }
                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;
                let invites = val
                    .get("invites")
                    .and_then(|v| v.as_array())
                    .map(|arr| {
                        arr.iter()
                            .map(|item| TenantInviteItem {
                                id: item
                                    .get("id")
                                    .and_then(|v| v.as_str())
                                    .unwrap_or_default()
                                    .to_string(),
                                email: item
                                    .get("email")
                                    .and_then(|v| v.as_str())
                                    .unwrap_or_default()
                                    .to_string(),
                                name: item
                                    .get("name")
                                    .and_then(|v| v.as_str())
                                    .unwrap_or_default()
                                    .to_string(),
                                role: item
                                    .get("role")
                                    .and_then(|v| v.as_str())
                                    .unwrap_or_default()
                                    .to_string(),
                                module_permissions: json_strings(item.get("module_permissions")),
                                flow_permissions: json_i32s(item.get("flow_permissions")),
                                expires_at: item
                                    .get("expires_at")
                                    .and_then(|v| v.as_i64())
                                    .unwrap_or_default(),
                                used: item
                                    .get("used")
                                    .and_then(|v| v.as_bool())
                                    .unwrap_or_default(),
                                revoked: item
                                    .get("revoked")
                                    .and_then(|v| v.as_bool())
                                    .unwrap_or_default(),
                                created_at: item
                                    .get("created_at")
                                    .and_then(|v| v.as_i64())
                                    .unwrap_or_default(),
                            })
                            .collect()
                    })
                    .unwrap_or_default();
                Ok(Response::new(ListInvitesResponse { invites }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "RevokeInvite", traceparent)
    )]
    async fn revoke_invite(
        &self,
        req: Request<RevokeInviteRequest>,
    ) -> Result<Response<RevokeInviteResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;
        let inner = req.into_inner();

        let payload = serde_json::json!({ "invite_id": inner.invite_id });

        let env_req = Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "RevokeInvite".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: claims.is_superuser,
            ..Default::default()
        };

        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    return Err(status_do_erro_interno(resp.error));
                }
                Ok(Response::new(RevokeInviteResponse { success: true }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListTenantUsers", traceparent)
    )]
    async fn list_tenant_users(
        &self,
        req: Request<ListTenantUsersRequest>,
    ) -> Result<Response<ListTenantUsersResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;

        let env_req = Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "ListTenantUsers".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({})).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: claims.is_superuser,
            ..Default::default()
        };

        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    return Err(status_do_erro_interno(resp.error));
                }
                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;
                let users = val
                    .get("users")
                    .and_then(|v| v.as_array())
                    .map(|arr| {
                        arr.iter()
                            .map(|item| TenantUserItem {
                                id: item.get("id").and_then(|v| v.as_i64()).unwrap_or_default()
                                    as i32,
                                user_id: item
                                    .get("user_id")
                                    .and_then(|v| v.as_i64())
                                    .unwrap_or_default()
                                    as i32,
                                role: item
                                    .get("role")
                                    .and_then(|v| v.as_str())
                                    .unwrap_or_default()
                                    .to_string(),
                                module_permissions: json_strings(item.get("module_permissions")),
                                flow_permissions: json_i32s(item.get("flow_permissions")),
                                is_active: item
                                    .get("is_active")
                                    .and_then(|v| v.as_bool())
                                    .unwrap_or_default(),
                                created_at: item
                                    .get("created_at")
                                    .and_then(|v| v.as_i64())
                                    .unwrap_or_default(),
                            })
                            .collect()
                    })
                    .unwrap_or_default();
                Ok(Response::new(ListTenantUsersResponse { users }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "UpdateTenantUser", traceparent)
    )]
    async fn update_tenant_user(
        &self,
        req: Request<UpdateTenantUserRequest>,
    ) -> Result<Response<UpdateTenantUserResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;
        let inner = req.into_inner();

        let mut payload = serde_json::Map::new();
        payload.insert("user_id".to_string(), serde_json::json!(inner.user_id));
        if inner.set_role {
            payload.insert("role".to_string(), serde_json::json!(inner.role));
        }
        if inner.set_module_permissions {
            payload.insert(
                "module_permissions".to_string(),
                serde_json::json!(inner.module_permissions),
            );
        }
        if inner.set_flow_permissions {
            payload.insert(
                "flow_permissions".to_string(),
                serde_json::json!(inner.flow_permissions),
            );
        }

        let env_req = Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "UpdateTenantUser".to_string(),
            payload: serde_json::to_vec(&serde_json::Value::Object(payload)).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: claims.is_superuser,
            ..Default::default()
        };

        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    return Err(status_do_erro_interno(resp.error));
                }
                Ok(Response::new(UpdateTenantUserResponse { success: true }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    /// GetMyTenantConfig: variante tenant-scoped de `get_tenant_config` — `tenant_id`
    /// vem de `claims.tenant_id` (nunca do request); exige escopo `tenant:admin`
    /// (ou `*`) além de sessão autenticada, já que config do tenant é dado sensível.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "GetMyTenantConfig", traceparent)
    )]
    async fn get_my_tenant_config(
        &self,
        req: Request<GetMyTenantConfigRequest>,
    ) -> Result<Response<GetTenantConfigResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        exigir_escopo_tenant_admin(&claims)?;
        let traceparent = traceparent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;

        let payload = serde_json::json!({ "tenant_id": tenant_uuid.to_string() });

        let env_req = Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "GetTenantConfig".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: claims.is_superuser,
            ..Default::default()
        };

        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    return Err(status_do_erro_interno(resp.error));
                }
                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;
                Ok(Response::new(mapear_tenant_config_response(&val)))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    /// UpdateMyTenantConfig: variante tenant-scoped de `update_tenant_config` —
    /// `tenant_id` vem de `claims.tenant_id`; exige escopo `tenant:admin`.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "UpdateMyTenantConfig", traceparent)
    )]
    async fn update_my_tenant_config(
        &self,
        req: Request<UpdateMyTenantConfigRequest>,
    ) -> Result<Response<UpdateTenantConfigResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        exigir_escopo_tenant_admin(&claims)?;
        let traceparent = traceparent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;
        let inner = req.into_inner();

        let mut api_keys_map = serde_json::Map::new();
        for entry in inner.api_keys {
            api_keys_map.insert(entry.key, serde_json::Value::String(entry.value));
        }

        let payload = serde_json::json!({
            "tenant_id": tenant_uuid.to_string(),
            "dados_empresa": inner.dados_empresa,
            "persona_bot": inner.persona_bot,
            "bot_agent_name": inner.bot_agent_name,
            "msg_fallback": inner.msg_fallback,
            "msg_sem_info": inner.msg_sem_info,
            "msg_transferencia": inner.msg_transferencia,
            "llm_class": inner.llm_class,
            "model": inner.model,
            "llm_temperature": inner.llm_temperature,
            "transcription_provider": inner.transcription_provider,
            "transcription_model": inner.transcription_model,
            "vision_provider": inner.vision_provider,
            "vision_model": inner.vision_model,
            "embeddings_class": inner.embeddings_class,
            "embeddings_model": inner.embeddings_model,
            "chunk_size": inner.chunk_size,
            "chunk_overlap": inner.chunk_overlap,
            "similarity_threshold": inner.similarity_threshold,
            "vector_distance_threshold": inner.vector_distance_threshold,
            "api_keys": serde_json::Value::Object(api_keys_map),
        });

        let env_req = Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "UpdateTenantConfig".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: claims.is_superuser,
            ..Default::default()
        };

        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) => {
                if resp.kind == MessageKind::Error as i32 {
                    return Err(status_do_erro_interno(resp.error));
                }
                Ok(Response::new(UpdateTenantConfigResponse { success: true }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }
}

/// Sobe a fachada gRPC-Web numa porta HTTP própria (browser usa HTTP/1.1).
/// Ordem dos layers (obrigatória): CORS **antes** de `GrpcWebLayer`.
pub async fn serve(deps: Arc<AuthDeps>, bus: redis::aio::ConnectionManager) -> anyhow::Result<()> {
    let addr = std::env::var("RUNTIME_API_GRPC_WEB_ADDR")
        .unwrap_or_else(|_| "0.0.0.0:50051".to_string())
        .parse()?;

    let bus_url = std::env::var("REDIS_BUS_URL")
        .or_else(|_| std::env::var("REDIS_URL"))
        .unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
    let realtime = crate::realtime::RealtimeManager::new(&bus_url)?;

    let facade_auth = AuthServiceServer::new(AuthFacade::new(deps.clone(), bus.clone()));
    let control = transport::conectar_cliente("control_plane").await?;
    let facade_admin = AdminServiceServer::new(AdminFacade::new(deps, bus, control, realtime));

    // CORS restritivo (defesa em profundidade mesmo servindo na mesma origem que o WASM).
    let cors = tower_http::cors::CorsLayer::new()
        .allow_origin(tower_http::cors::AllowOrigin::mirror_request())
        .allow_methods(tower_http::cors::Any)
        .allow_headers([
            http::header::CONTENT_TYPE,
            http::header::AUTHORIZATION,
            "x-grpc-web".parse().unwrap(),
            "grpc-timeout".parse().unwrap(),
            "x-user-agent".parse().unwrap(),
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
        .add_service(facade_auth)
        .add_service(facade_admin)
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

    #[test]
    fn extrai_tokens_ausentes_vira_string_vazia() {
        // JSON sem os campos esperados não deve entrar em pânico — vira default vazio.
        let resp = extrair_tokens(&serde_json::json!({}));
        assert_eq!(resp.access_token, "");
        assert_eq!(resp.refresh_token, "");
    }

    #[test]
    fn mapeia_database_nao_encontrado_para_not_found_mas_outro_erro_para_internal() {
        // O guard só vira NotFound quando a mensagem carrega "não encontrado".
        assert_eq!(
            app_err_para_status(&error_core::AppError::Cache(
                "registro não encontrado".into()
            ))
            .code(),
            tonic::Code::NotFound
        );
        assert_eq!(
            app_err_para_status(&error_core::AppError::Storage("não encontrado".into())).code(),
            tonic::Code::NotFound
        );
        // Database sem a substring cai no ramo genérico (Internal).
        assert_eq!(
            app_err_para_status(&error_core::AppError::Database("conexão caiu".into())).code(),
            tonic::Code::Internal
        );
    }

    #[test]
    fn user_agent_do_metadata_extrai_e_trunca() {
        // Presente: é lido tal qual (dentro do limite).
        let mut req = Request::new(LogoutRequest {
            refresh_token: String::new(),
        });
        req.metadata_mut()
            .insert("user-agent", "Mozilla/5.0 Flutter".parse().unwrap());
        assert_eq!(user_agent_do_metadata(&req), "Mozilla/5.0 Flutter");

        // Ausente: string vazia (não pânico).
        let req_vazio = Request::new(LogoutRequest {
            refresh_token: String::new(),
        });
        assert_eq!(user_agent_do_metadata(&req_vazio), "");
    }

    #[test]
    fn user_agent_do_metadata_trunca_em_512_chars() {
        // Payload abusivo é truncado defensivamente em 512 caracteres.
        let ua = "a".repeat(1000);
        let mut req = Request::new(LogoutRequest {
            refresh_token: String::new(),
        });
        req.metadata_mut().insert("user-agent", ua.parse().unwrap());
        assert_eq!(user_agent_do_metadata(&req).len(), 512);
    }

    /// Constrói `Claims` mínimos para testar as guardas de escopo (sem tocar em JWT real).
    fn claims_com(scopes: &[&str], is_superuser: bool) -> application::jwt::Claims {
        application::jwt::Claims {
            sub: "1".into(),
            tenant_id: "t".into(),
            scopes: scopes.iter().map(|s| s.to_string()).collect(),
            is_superuser,
            jti: "j".into(),
            iat: 0,
            exp: 0,
        }
    }

    #[test]
    fn exigir_escopo_tenant_admin_aceita_superuser_e_escopos_validos() {
        // Superusuário passa mesmo sem escopo explícito.
        assert!(exigir_escopo_tenant_admin(&claims_com(&[], true)).is_ok());
        // Escopo tenant:admin passa.
        assert!(exigir_escopo_tenant_admin(&claims_com(&["tenant:admin"], false)).is_ok());
        // Coringa de superusuário `*` passa.
        assert!(exigir_escopo_tenant_admin(&claims_com(&["*"], false)).is_ok());
    }

    #[test]
    fn exigir_escopo_tenant_admin_nega_sem_escopo() {
        // Usuário comum sem os escopos exigidos recebe PERMISSION_DENIED.
        let err = exigir_escopo_tenant_admin(&claims_com(&["kanban:read"], false)).unwrap_err();
        assert_eq!(err.code(), tonic::Code::PermissionDenied);
        assert_eq!(err.message(), "errors.auth.forbidden");
    }

    #[test]
    fn extrair_permissoes_web_le_array_de_inteiros() {
        let payload = serde_json::json!({ "permissions": [1, 2, 3] }).to_string();
        assert_eq!(
            extrair_permissoes_web(payload.as_bytes()),
            Some(vec![1, 2, 3])
        );
    }

    #[test]
    fn extrair_permissoes_web_retorna_none_para_payload_invalido() {
        // JSON inválido → None.
        assert_eq!(extrair_permissoes_web(b"not json"), None);
        // Sem o campo permissions → None.
        assert_eq!(
            extrair_permissoes_web(serde_json::json!({}).to_string().as_bytes()),
            None
        );
        // permissions não é array → None.
        assert_eq!(
            extrair_permissoes_web(
                serde_json::json!({ "permissions": 5 })
                    .to_string()
                    .as_bytes()
            ),
            None
        );
    }

    #[test]
    fn status_do_erro_interno_mapeia_cada_codigo() {
        let mk = |code: &str| {
            status_do_erro_interno(Some(contracts::ErrorEnvelope {
                code: code.into(),
                message: "detalhe".into(),
                ..Default::default()
            }))
            .code()
        };
        assert_eq!(mk("AUTH_INSUFFICIENT_SCOPE"), tonic::Code::PermissionDenied);
        assert_eq!(mk("DB_RECORD_NOT_FOUND"), tonic::Code::NotFound);
        assert_eq!(mk("VALIDATION_FAILED"), tonic::Code::InvalidArgument);
        assert_eq!(mk("CONFLICT"), tonic::Code::FailedPrecondition);
        assert_eq!(
            mk("DB_CONSTRAINT_VIOLATION"),
            tonic::Code::FailedPrecondition
        );
        assert_eq!(mk("QUALQUER_OUTRO"), tonic::Code::Internal);
    }

    #[test]
    fn status_do_erro_interno_sem_envelope_vira_internal() {
        assert_eq!(status_do_erro_interno(None).code(), tonic::Code::Internal);
    }

    #[test]
    fn json_strings_extrai_array_ou_vazio() {
        let val = serde_json::json!(["kanban", "billing", 42, "audit"]);
        // Ignora o não-string (42) e mantém a ordem.
        assert_eq!(json_strings(Some(&val)), vec!["kanban", "billing", "audit"]);
        // None → vetor vazio.
        assert!(json_strings(None).is_empty());
        // Valor que não é array → vetor vazio.
        assert!(json_strings(Some(&serde_json::json!("x"))).is_empty());
    }

    #[test]
    fn json_i32s_extrai_array_ou_vazio() {
        let val = serde_json::json!([10, 20, "nao_int", 30]);
        assert_eq!(json_i32s(Some(&val)), vec![10, 20, 30]);
        assert!(json_i32s(None).is_empty());
        assert!(json_i32s(Some(&serde_json::json!(7))).is_empty());
    }

    #[test]
    fn novo_traceparent_segue_formato_w3c() {
        let tp = novo_traceparent();
        let partes: Vec<&str> = tp.split('-').collect();
        assert_eq!(partes.len(), 4);
        assert_eq!(partes[0], "00");
        assert_eq!(partes[1].len(), 32);
        assert_eq!(partes[2].len(), 16);
        assert_eq!(partes[3], "01");
        // Dois traceparents consecutivos não colidem no trace-id.
        assert_ne!(novo_traceparent(), novo_traceparent());
    }

    #[test]
    fn mapear_tenant_config_response_mapeia_todos_os_campos() {
        let val = serde_json::json!({
            "dados_empresa": "Acme",
            "persona_bot": "cordial",
            "bot_agent_name": "Ana",
            "msg_fallback": "fb",
            "msg_sem_info": "si",
            "msg_transferencia": "tr",
            "llm_class": "openai",
            "model": "gpt",
            "llm_temperature": "0.7",
            "transcription_provider": "whisper",
            "transcription_model": "large",
            "vision_provider": "vp",
            "vision_model": "vm",
            "embeddings_class": "emb",
            "embeddings_model": "text-emb",
            "chunk_size": 512,
            "chunk_overlap": 64,
            "similarity_threshold": "0.8",
            "vector_distance_threshold": "0.5",
            "api_keys": { "openai": "sk-abc" },
        });

        let resp = mapear_tenant_config_response(&val);

        assert_eq!(resp.dados_empresa, "Acme");
        assert_eq!(resp.bot_agent_name, "Ana");
        assert_eq!(resp.chunk_size, 512);
        assert_eq!(resp.chunk_overlap, 64);
        assert_eq!(resp.similarity_threshold, "0.8");
        assert_eq!(resp.api_keys.len(), 1);
        assert_eq!(resp.api_keys[0].key, "openai");
        assert_eq!(resp.api_keys[0].value, "sk-abc");
    }

    #[test]
    fn mapear_tenant_config_response_usa_defaults_para_json_vazio() {
        // JSON sem campos → strings vazias, inteiros zero, sem api keys (não pânico).
        let resp = mapear_tenant_config_response(&serde_json::json!({}));
        assert_eq!(resp.dados_empresa, "");
        assert_eq!(resp.model, "");
        assert_eq!(resp.chunk_size, 0);
        assert_eq!(resp.chunk_overlap, 0);
        assert!(resp.api_keys.is_empty());
    }

    // -----------------------------------------------------------------------
    // Barreira de autenticação da fachada gRPC-Web
    //
    // Esta é a ÚNICA porta pela qual o browser (Flutter Web/WASM) entra no
    // sistema, e ela é publicada na internet pelo Caddy. Cada método aqui repete
    // à mão a primeira linha de autenticação (`exigir_*_do_metadata`); nada no
    // compilador obriga um método NOVO a fazer isso, e o esquecimento não quebra
    // nenhum teste — só abre leitura/escrita dos dados de tenant a quem não
    // apresentou credencial. O teste abaixo cobra a barreira método a método.
    //
    // Nenhuma RPC de backend é envolvida: sem token a fachada devolve
    // `Unauthenticated` ANTES de chamar o data_postgres/data_redis. Os endpoints
    // dos stubs existem só porque `AuthDeps` guarda clientes já conectados.
    // -----------------------------------------------------------------------

    /// Sobe um stub RPC que não responde nada (nenhum teste daqui chega a chamá-lo)
    /// e devolve um cliente conectado a ele.
    async fn stub_rpc(addr: &str) -> transport::MuxClient {
        use transport::runtime::{Endpoint, Server};
        let servidor = Server::new(Endpoint::parse(addr).unwrap(), "flatbuffers");
        tokio::spawn(async move {
            let _ = servidor.run().await;
        });
        tokio::time::sleep(std::time::Duration::from_millis(150)).await;
        transport::MuxClient::conectar(
            Endpoint::parse(addr).unwrap(),
            Box::new(transport::codec::FlatbuffersCodec),
        )
        .await
        .unwrap()
    }

    /// `AdminFacade` pronta para exercitar apenas o caminho de rejeição por
    /// credencial ausente.
    async fn facade_para_teste_de_auth(porta_base: u16) -> AdminFacade {
        let deps = Arc::new(AuthDeps {
            pg: stub_rpc(&format!("tcp://127.0.0.1:{}", porta_base)).await,
            redis: stub_rpc(&format!("tcp://127.0.0.1:{}", porta_base + 1)).await,
            access_ttl_s: 900,
            refresh_ttl_s: 604_800,
            login_rate_max: 5,
            login_rate_window_s: 300,
        });
        let control = stub_rpc(&format!("tcp://127.0.0.1:{}", porta_base + 2)).await;
        // Bus e realtime só são tocados DEPOIS da autenticação — nenhum teste daqui
        // chega neles. O `RealtimeManager` nem abre conexão no construtor.
        AdminFacade::new(
            deps,
            bus_stub().await,
            control,
            crate::realtime::RealtimeManager::new("redis://127.0.0.1:63799").unwrap(),
        )
    }

    /// `ConnectionManager` é exigido pela assinatura da fachada mesmo sem Redis: sem
    /// ele não há como construir o `AdminFacade`. Este stub RESP mínimo
    /// (só `+PONG`/`+OK`) satisfaz o handshake do cliente.
    async fn bus_stub() -> redis::aio::ConnectionManager {
        let listener = tokio::net::TcpListener::bind(("127.0.0.1", 0))
            .await
            .unwrap();
        let porta = listener.local_addr().unwrap().port();
        tokio::spawn(async move {
            while let Ok((mut socket, _)) = listener.accept().await {
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

    /// Nenhum método administrativo pode responder a uma chamada SEM credencial.
    /// Um `Unauthenticated` por método é o contrato; qualquer outro código significa
    /// que a requisição passou da barreira (no melhor caso vira erro interno adiante,
    /// no pior devolve dado de tenant a um anônimo).
    #[tokio::test]
    async fn todo_metodo_admin_rejeita_chamada_sem_credencial() {
        let _ =
            application::jwt::inicializar_chaves("segredo_de_teste_de_pelo_menos_32_bytes_longo");
        let facade = facade_para_teste_de_auth(29301).await;

        // Cada entrada exercita um método real da fachada. `accept_invite` fica de
        // fora de propósito: o convite é aceito por quem AINDA não tem conta, e a
        // credencial dele é o próprio token do convite (ver `create_invite`, que sim
        // exige autenticação). `login`/`refresh` são públicos pela mesma natureza.
        macro_rules! exigir_unauthenticated {
            ($($rotulo:literal => $chamada:expr),+ $(,)?) => {
                $(
                    let resultado = $chamada;
                    match resultado {
                        Ok(_) => panic!(
                            "{} respondeu SEM credencial: a barreira de autenticação está ausente",
                            $rotulo
                        ),
                        Err(status) => assert_eq!(
                            status.code(),
                            tonic::Code::Unauthenticated,
                            "{} rejeitou com {:?} (esperado Unauthenticated): a chamada passou da barreira de auth",
                            $rotulo,
                            status.code()
                        ),
                    }
                )+
            };
        }

        exigir_unauthenticated! {
            "ListCoreSettings" => facade.list_core_settings(Request::new(ListCoreSettingsRequest::default())).await,
            "UpsertCoreSetting" => facade.upsert_core_setting(Request::new(UpsertCoreSettingRequest::default())).await,
            "DeleteCoreSetting" => facade.delete_core_setting(Request::new(DeleteCoreSettingRequest::default())).await,
            "GetTenantConfig" => facade.get_tenant_config(Request::new(GetTenantConfigRequest::default())).await,
            "UpdateTenantConfig" => facade.update_tenant_config(Request::new(UpdateTenantConfigRequest::default())).await,
            "ListTenants" => facade.list_tenants(Request::new(ListTenantsRequest::default())).await,
            "GetTenant" => facade.get_tenant(Request::new(GetTenantRequest::default())).await,
            "CreateTenant" => facade.create_tenant(Request::new(CreateTenantRequest::default())).await,
            "UpdateTenant" => facade.update_tenant(Request::new(UpdateTenantRequest::default())).await,
            "SetTenantActive" => facade.set_tenant_active(Request::new(SetTenantActiveRequest::default())).await,
            "GenerateAccessCode" => facade.generate_access_code(Request::new(GenerateAccessCodeRequest::default())).await,
            "ListPlans" => facade.list_plans(Request::new(ListPlansRequest::default())).await,
            "CreatePlan" => facade.create_plan(Request::new(CreatePlanRequest::default())).await,
            "UpdatePlan" => facade.update_plan(Request::new(UpdatePlanRequest::default())).await,
            "ListSubscriptions" => facade.list_subscriptions(Request::new(ListSubscriptionsRequest::default())).await,
            "RegisterPayment" => facade.register_payment(Request::new(RegisterPaymentRequest::default())).await,
            "ListPayments" => facade.list_payments(Request::new(ListPaymentsRequest::default())).await,
            "TestEvolutionConnection" => facade.test_evolution_connection(Request::new(TestEvolutionConnectionRequest::default())).await,
            "ListFeatureFlags" => facade.list_feature_flags(Request::new(ListFeatureFlagsRequest::default())).await,
            "SetFeatureFlag" => facade.set_feature_flag(Request::new(SetFeatureFlagRequest::default())).await,
            "SetFeatureFlagOverride" => facade.set_feature_flag_override(Request::new(SetFeatureFlagOverrideRequest::default())).await,
            "QueryAuditLog" => facade.query_audit_log(Request::new(QueryAuditLogRequest::default())).await,
            "GetServiceHealth" => facade.get_service_health(Request::new(GetServiceHealthRequest::default())).await,
            "GetDashboardSummary" => facade.get_dashboard_summary(Request::new(GetDashboardSummaryRequest::default())).await,
            "ExportTenantsCsv" => facade.export_tenants_csv(Request::new(ExportTenantsCsvRequest::default())).await,
            "ListAtendimentos" => facade.list_atendimentos(Request::new(ListAtendimentosRequest::default())).await,
            "GetThread" => facade.get_thread(Request::new(GetThreadRequest::default())).await,
            "MoveAtendimentoEtapa" => facade.move_atendimento_etapa(Request::new(MoveAtendimentoEtapaRequest::default())).await,
            "SendOutboundMessage" => facade.send_outbound_message(Request::new(SendOutboundMessageRequest::default())).await,
            "StreamAtendimentos" => facade.stream_atendimentos(Request::new(StreamAtendimentosRequest::default())).await.map(|_| ()),
            "CreateInvite" => facade.create_invite(Request::new(CreateInviteRequest::default())).await,
            "ListInvites" => facade.list_invites(Request::new(ListInvitesRequest::default())).await,
            "RevokeInvite" => facade.revoke_invite(Request::new(RevokeInviteRequest::default())).await,
            "ListTenantUsers" => facade.list_tenant_users(Request::new(ListTenantUsersRequest::default())).await,
            "UpdateTenantUser" => facade.update_tenant_user(Request::new(UpdateTenantUserRequest::default())).await,
            "GetMyTenantConfig" => facade.get_my_tenant_config(Request::new(GetMyTenantConfigRequest::default())).await,
            "UpdateMyTenantConfig" => facade.update_my_tenant_config(Request::new(UpdateMyTenantConfigRequest::default())).await,
        }
    }

    /// Token sintaticamente presente mas com assinatura inválida também não passa:
    /// a barreira valida a assinatura, não só a presença do cabeçalho.
    #[tokio::test]
    async fn metodo_admin_rejeita_token_com_assinatura_invalida() {
        let _ =
            application::jwt::inicializar_chaves("segredo_de_teste_de_pelo_menos_32_bytes_longo");
        let facade = facade_para_teste_de_auth(29311).await;

        let mut req = Request::new(ListTenantsRequest::default());
        req.metadata_mut()
            .insert("authorization", "Bearer aaaa.bbbb.cccc".parse().unwrap());

        let status = facade.list_tenants(req).await.unwrap_err();
        assert_eq!(status.code(), tonic::Code::Unauthenticated);
    }
}
