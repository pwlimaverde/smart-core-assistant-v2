//! Fachada gRPC-Web da `runtime_api`: traduz chamadas do browser (Flutter Web/WASM)
//! para a lógica de negócio já existente em `application::auth::*`. NÃO reimplementa
//! regra de negócio — apenas converte o transporte (metadata gRPC-Web ↔ argumentos das
//! funções de aplicação) e reaproveita a auditoria de segurança da borda (`crate::audit`).
//!
//! Roda numa `tokio::task` paralela ao `transport::Server`, numa porta HTTP própria
//! (`RUNTIME_API_GRPC_WEB_ADDR`), pois o browser fala HTTP/1.1 + gRPC-Web.

use std::sync::Arc;

use application::auth::login::AuthDeps;
use contracts::grpc::queries as q;
use contracts::grpc::queries::admin_service_server::{AdminService, AdminServiceServer};
use contracts::grpc::queries::auth_service_server::{AuthService, AuthServiceServer};
use contracts::grpc::queries::{
    // Fase N3 - Painel do Tenant (convites, usuários, config tenant-scoped)
    AcceptInviteRequest,
    AcceptInviteResponse,
    AcceptedTenantUser,
    AdminListUsersRequest,
    AdminListUsersResponse,
    AdminSetUserActiveRequest,
    AdminSetUserActiveResponse,
    AdminUserItem,
    AjustarEscoposMcpGrantRequest,
    AjustarEscoposMcpGrantResponse,
    AlternarEtiquetaRequest,
    AnaliseDaConversa,
    ApiKeyEntry as ProtoApiKeyEntry,
    AtendimentoEvent,
    AtendimentoIdRequest,
    // Fase 6 - Operacional (fila/Kanban/chat)
    AtendimentoResumo as ProtoAtendimentoResumo,
    AtribuirAtendimentoRequest,
    AtribuirAtendimentoResponse,
    AtualizarNumeroIgnoradoRequest,
    AuditLogEntry as ProtoAuditLogEntry,
    AuthResponse,
    AvaliacaoDeTeste,
    ContagemDeMigracao,
    ContatoDoCliente,
    CoreSetting as ProtoCoreSetting,
    CreateEtiquetaRequest,
    CreateInviteRequest,
    CreateInviteResponse,
    CreateMyAtendenteRequest,
    CreateMyCampoRequest,
    CreateMyClienteRequest,
    CreateMyContatoRequest,
    CreateMyDepartamentoRequest,
    CreateMyDepartamentoResponse,
    CreateMyEtapaFluxoRequest,
    CreateMyFluxoRequest,
    CreateMyTreinamentoComArquivoRequest,
    CreateMyTreinamentoRequest,
    // Configuração inicial guiada (passos 5 a 8)
    CreateMyWhatsappInstanceRequest,
    CreateMyWhatsappInstanceResponse,
    CreateNotaRequest,
    CreatePlanRequest,
    CreatePlanResponse,
    CreateTenantRequest,
    CreateTenantResponse,
    // Vouchers de ativação
    CreateVoucherRequest,
    CreateVoucherResponse,
    CriarNumeroIgnoradoRequest,
    DadoDoContato,
    DadosMyCliente,
    DecisaoDaConversa,
    DefinirBotDaConversaRequest,
    DefinirBotDaConversaResponse,
    DefinirDepartamentoDaConexaoRequest,
    DefinirMyClienteAtivoRequest,
    DefinirMyContatoAtivoRequest,
    DefinirMyItemAtivoRequest,
    DefinirPrioridadeRequest,
    DefinirPrioridadeResponse,
    DefinirRespostaBotInstanciaRequest,
    DefinirRespostaBotInstanciaResponse,
    DeleteCoreSettingRequest,
    DeleteCoreSettingResponse,
    DesativarEtiquetaRequest,
    DetalheAtendimentoResponse,
    DetalheDaConexaoRequest,
    DetalheDaConexaoResponse,
    EntidadeDaConversa,
    EnviarMidiaAtendimentoRequest,
    EnviarMidiaAtendimentoResponse,
    EnviarPresencaRequest,
    EnviarPresencaResponse,
    Etiqueta as ProtoEtiqueta,
    EtiquetaResponse,
    EventoDaTimeline,
    ExcluirMyItemRequest,
    ExcluirMyItemResponse,
    ExportTenantsCsvRequest,
    ExportTenantsCsvResponse,
    ExportarQuadroRequest,
    ExportarQuadroResponse,
    FeatureFlag as ProtoFeatureFlag,
    FeatureFlagOverride as ProtoFeatureFlagOverride,
    FinalizarMyTreinamentoRequest,
    GenerateAccessCodeRequest,
    GenerateAccessCodeResponse,
    GetDashboardSummaryRequest,
    GetDashboardSummaryResponse,
    GetMyOnboardingProgressRequest,
    GetMyOnboardingProgressResponse,
    GetMyPainelRequest,
    GetMyPainelResponse,
    GetMyTenantConfigRequest,
    GetMyTreinamentoRequest,
    GetMyWhatsappInstanceStatusRequest,
    GetMyWhatsappInstanceStatusResponse,
    GetServiceHealthRequest,
    GetServiceHealthResponse,
    GetTenantConfigRequest,
    GetTenantConfigResponse,
    GetTenantRequest,
    GetTenantResponse,
    GetThreadRequest,
    GetThreadResponse,
    GetVersaoDoAppRequest,
    GetVersaoDoAppResponse,
    GetWindowsDownloadLinkRequest,
    GetWindowsDownloadLinkResponse,
    IniciarAtendimentoManualRequest,
    IniciarAtendimentoManualResponse,
    IntencaoDaConversa,
    ItemExcluido,
    ListAtendimentosRequest,
    ListAtendimentosResponse,
    ListCoreSettingsRequest,
    ListCoreSettingsResponse,
    // Fase 4 - Feature Flags
    ListFeatureFlagsRequest,
    ListFeatureFlagsResponse,
    ListInvitesRequest,
    ListInvitesResponse,
    // N13 — aplicativos de IA conectados por OAuth (servidor MCP)
    ListMcpGrantsRequest,
    ListMcpGrantsResponse,
    ListMyAtendentesRequest,
    ListMyAtendentesResponse,
    ListMyAuditLogRequest,
    ListMyAuditLogResponse,
    ListMyAvaliacoesDeTesteRequest,
    ListMyAvaliacoesDeTesteResponse,
    ListMyCamposRequest,
    ListMyCamposResponse,
    ListMyClientesRequest,
    ListMyClientesResponse,
    ListMyContatosDoClienteResponse,
    ListMyContatosRequest,
    ListMyContatosResponse,
    ListMyDepartamentosRequest,
    ListMyDepartamentosResponse,
    ListMyEtapasFluxoResponse,
    ListMyExcluidosRequest,
    ListMyExcluidosResponse,
    ListMyFluxosRequest,
    ListMyFluxosResponse,
    ListMyIntentsRequest,
    ListMyIntentsResponse,
    ListMyMensagensNaoEntreguesRequest,
    ListMyMensagensNaoEntreguesResponse,
    ListMyNumerosIgnoradosRequest,
    ListMyNumerosIgnoradosResponse,
    ListMyTreinamentosRequest,
    ListMyTreinamentosResponse,
    ListMyWhatsappInstancesRequest,
    ListMyWhatsappInstancesResponse,
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
    ListVoucherRedemptionsRequest,
    ListVoucherRedemptionsResponse,
    ListVouchersRequest,
    ListVouchersResponse,
    ListarAtendimentosDoContatoRequest,
    ListarAtendimentosDoContatoResponse,
    ListarMidiasAtendimentoRequest,
    ListarMidiasAtendimentoResponse,
    ListarTimelineRequest,
    ListarTimelineResponse,
    LoginRequest,
    LogoutRequest,
    LogoutResponse,
    MarcarAtendimentoLidoRequest,
    MarcarAtendimentoLidoResponse,
    MarcarAvaliacaoTratadaRequest,
    MarcarRevisadoRequest,
    McpGrantItem,
    MensagemNaoEntregue,
    MensagemThread as ProtoMensagemThread,
    MidiaMensagem as ProtoMidiaMensagem,
    MigrarEscoposImplicitosRequest,
    MigrarEscoposImplicitosResponse,
    MoveAtendimentoEtapaRequest,
    MoveAtendimentoEtapaResponse,
    MoverMyEtapaFluxoRequest,
    MyAtendente,
    MyAtendenteIdRequest,
    MyAtendenteResponse,
    MyAuditLogEntry,
    MyCampoIdRequest,
    MyCampoPersonalizado,
    MyCampoResponse,
    MyCliente,
    MyClienteIdRequest,
    MyClienteResponse,
    MyContato,
    MyContatoResponse,
    MyDepartamento,
    MyDepartamentoIdRequest,
    MyEtapaFluxo,
    MyEtapaFluxoIdRequest,
    MyEtapaFluxoResponse,
    MyFluxo,
    MyFluxoIdRequest,
    MyFluxoResponse,
    MyIntent,
    MyIntentDados,
    MyIntentIdRequest,
    MyIntentResponse,
    MyNumeroIgnorado,
    MyNumeroIgnoradoResponse,
    MyTreinamento,
    MyTreinamentoResponse,
    MyWhatsappInstance,
    MyWhatsappInstanceIdRequest,
    Nota as ProtoNota,
    NotaResponse,
    NumeroIgnoradoIdRequest,
    ObterContatoDoAtendimentoRequest,
    ObterContatoDoAtendimentoResponse,
    OpcaoCampo,
    PaymentRecord as ProtoPaymentRecord,
    Plan as ProtoPlan,
    PromptDoTenant,
    // Fase 5 - Auditoria & Saúde
    QueryAuditLogRequest,
    QueryAuditLogResponse,
    QuitarMinhaAssinaturaRequest,
    QuitarMinhaAssinaturaResponse,
    ReacaoDaMensagem,
    RedefinirSenhaRequest,
    RedefinirSenhaResponse,
    ReenviarConviteRequest,
    ReenviarConviteResponse,
    ReenviarMensagemNaoEntregueRequest,
    ReenviarMensagemNaoEntregueResponse,
    RefreshRequest,
    RegisterPaymentRequest,
    RegisterPaymentResponse,
    RegistrarFeedbackTesteRequest,
    RegistrarFeedbackTesteResponse,
    RemoverMyTreinamentoRequest,
    RemoverNotaRequest,
    RevokeInviteRequest,
    RevokeInviteResponse,
    RevokeMcpGrantRequest,
    RevokeMcpGrantResponse,
    RevokeVoucherRequest,
    RevokeVoucherResponse,
    SendOutboundMessageRequest,
    SendOutboundMessageResponse,
    ServiceHealth as ProtoServiceHealth,
    SetAtendimentoStatusRequest,
    SetAtendimentoStatusResponse,
    SetFeatureFlagOverrideRequest,
    SetFeatureFlagOverrideResponse,
    SetFeatureFlagRequest,
    SetFeatureFlagResponse,
    SetMyBotPersonaRequest,
    SetMyBotPersonaResponse,
    SetMyValorCampoRequest,
    SetOnboardingProgressRequest,
    SetOnboardingProgressResponse,
    SetTenantActiveRequest,
    SetTenantActiveResponse,
    SimpleOkResponse,
    SolicitarRedefinicaoSenhaRequest,
    SolicitarRedefinicaoSenhaResponse,
    SolicitarUploadMidiaRequest,
    SolicitarUploadMidiaResponse,
    SolicitarUploadTreinamentoRequest,
    SolicitarUploadTreinamentoResponse,
    StreamAtendimentosRequest,
    Subscription as ProtoSubscription,
    Tenant as ProtoTenant,
    TenantInviteCreated,
    TenantInviteItem,
    TenantUserItem,
    // Fase 3 - Evolution Connection
    TestEvolutionConnectionRequest,
    TestEvolutionConnectionResponse,
    TestarPerguntaRequest,
    TestarPerguntaResponse,
    TestarProvedorIaRequest,
    TestarProvedorIaResponse,
    TransferirParaFluxoRequest,
    TransferirParaFluxoResponse,
    TrechoUsado,
    UpdateEtiquetaRequest,
    UpdateMyAtendenteRequest,
    UpdateMyCampoRequest,
    UpdateMyClienteRequest,
    UpdateMyConfigAvancadaRequest,
    UpdateMyContatoRequest,
    UpdateMyDepartamentoRequest,
    UpdateMyEtapaFluxoRequest,
    UpdateMyFluxoRequest,
    UpdateMyIntentRequest,
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
    ValorCampoDoAtendimento,
    VincularMyContatoClienteRequest,
    Voucher as ProtoVoucher,
    VoucherRedemption as ProtoVoucherRedemption,
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
    /// E-mail da recuperação de senha (N11 E8). Ver a nota em `AdminFacade::email`.
    email: infrastructure_email::Enviador,
}

impl AuthFacade {
    pub fn new(deps: Arc<AuthDeps>, bus: redis::aio::ConnectionManager) -> Self {
        Self {
            deps,
            bus,
            email: infrastructure_email::Enviador::do_ambiente(),
        }
    }
}

/// Endereço público do app do tenant, para montar links que saem daqui.
///
/// Existe porque o servidor não tem como adivinhá-lo: dev e produção são
/// domínios diferentes, e o request que originou a ação nem sempre chega com
/// um `Host` confiável (há um proxy na frente). Configuração explícita é a
/// única resposta honesta.
///
/// **Inclui o caminho base.** O app do tenant é servido sob `/v2/tenant/`, não
/// na raiz — o domínio sozinho responde HTTP 400, que foi o que o primeiro
/// convidado recebeu por e-mail. O padrão aqui já traz o caminho, e é o de
/// produção: um convite com link errado é pior calado do que barulhento.
fn base_publica_do_app() -> String {
    std::env::var("APP_PUBLIC_URL")
        .unwrap_or_else(|_| "https://smartcoreassistant.com.br/v2/tenant".to_string())
        .trim_end_matches('/')
        .to_string()
}

/// Quantas vezes `recurso`/`id` foi usado na janela, contando esta.
///
/// `None` quando o Redis não respondeu. Quem chama decide o que fazer com isso;
/// nos usos de hoje, falha aberto — pelo mesmo motivo do teto de atendimento
/// ativo: o limite contém abuso, e não deve virar um ponto de falha a mais entre
/// o usuário e a própria conta.
async fn tentativas_na_janela(
    deps: &AuthDeps,
    traceparent: &str,
    recurso: &str,
    id: &str,
    janela_s: u64,
) -> Option<u64> {
    let req = application::auth::login::montar_envelope_request(
        Uuid::nil(),
        traceparent,
        "RegisterRateLimitAttempt",
        &serde_json::json!({ "recurso": recurso, "id": id, "window_s": janela_s }),
    );
    match deps
        .redis
        .call(req, std::time::Duration::from_secs(3))
        .await
    {
        Ok(resp) if resp.kind != MessageKind::Error as i32 => {
            serde_json::from_slice::<serde_json::Value>(&resp.payload)
                .ok()
                .and_then(|c| c.get("attempts").and_then(serde_json::Value::as_u64))
        }
        _ => None,
    }
}

/// Converte o `AppError` interno num `tonic::Status` sem vazar detalhe sensível.
/// As mensagens são chaves de i18n estáveis resolvidas no cliente (`ErrorMessageMapper`).
pub(crate) fn app_err_para_status(err: &error_core::AppError) -> Status {
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
pub(crate) fn traceparent_do_metadata<T>(req: &Request<T>) -> String {
    req.metadata()
        .get("traceparent")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string())
        .unwrap_or_else(novo_traceparent)
}

/// Extrai o IP do cliente repassado pelo proxy (`x-forwarded-for`, primeiro valor).
/// Agora que existe uma borda HTTP de fato, podemos registrar o IP na auditoria
/// (item pendente do doc 09 §6.4).
pub(crate) fn ip_do_metadata<T>(req: &Request<T>) -> Option<String> {
    req.metadata()
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.split(',').next())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

/// N9/E7 — converte um timestamp RFC3339 do `data_postgres` em millis, ou `None`
/// quando o campo está ausente/nulo (mensagem ainda não entregue ou não lida).
fn millis_do_item(item: &serde_json::Value, campo: &str) -> Option<i64> {
    item.get(campo)
        .and_then(|v| v.as_str())
        .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
        .map(|d| d.timestamp_millis())
}

/// N9/E2 — monta a mídia da mensagem quando ela existe.
///
/// O `data_postgres` devolve o bloco `midia` **sem** URL (ponteiro e metadados:
/// `chave`, `kind`, `mimetype`, `filename`, `size_bytes`, `is_ptt`); a
/// `url_assinada` é preenchida antes daqui por [`assinar_midias_da_pagina`], que
/// pede ao `data_storage` a assinatura em lote da página (P2a). **Não logar**
/// este campo em nenhum ponto — é credencial de leitura do objeto até expirar.
fn midia_do_item(item: &serde_json::Value) -> Option<ProtoMidiaMensagem> {
    let m = item.get("midia")?;
    // Sem URL não há o que o cliente possa fazer com o registro: a mídia foi
    // purgada (retenção) ou o presign falhou. Melhor não mandar o bloco do que
    // mandar um player que não toca nada.
    let url = m.get("url_assinada").and_then(|v| v.as_str())?;
    Some(ProtoMidiaMensagem {
        kind: m
            .get("kind")
            .and_then(|v| v.as_str())
            .unwrap_or("document")
            .to_string(),
        url_assinada: url.to_string(),
        mimetype: m
            .get("mimetype")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string(),
        filename: m
            .get("filename")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string(),
        size_bytes: m.get("size_bytes").and_then(|v| v.as_i64()).unwrap_or(0),
        seconds: m.get("seconds").and_then(|v| v.as_i64()).map(|v| v as i32),
        is_ptt: m.get("is_ptt").and_then(|v| v.as_bool()),
    })
}

/// P2a — validade (s) da URL de leitura das mídias da thread e da galeria. O
/// cliente reaproveita a URL enquanto ela tem menos de 80% desse tempo e pede
/// recarga quando ela vence.
const TTL_URL_MIDIA_S: u64 = 900;

/// P2a — teto de itens por chamada `PresignFiles` (o mesmo do `data_storage`).
const TETO_PRESIGN_LOTE: usize = 100;

/// P2a — preenche `url_assinada` nos blocos `midia` de uma página (thread ou
/// galeria) com uma chamada `PresignFiles` ao `data_storage` por lote de até
/// [`TETO_PRESIGN_LOTE`] chaves — na prática, uma por página.
///
/// O `runtime_api` não fala S3: a assinatura é do `data_storage`, via RPC.
/// O `mimetype` vai como `content_type` para o R2 responder com o
/// `Content-Type` certo (a chave da mídia recebida não tem extensão).
///
/// Devolve `false` quando não conseguiu assinar (storage fora do ar ou não
/// configurado). Os blocos ficam sem URL e [`midia_do_item`] os descarta: a
/// mensagem sai só com o texto e a leitura não falha por causa da mídia.
///
/// `skip_all`: chaves, nomes e URLs nunca entram no span — só a quantidade.
#[tracing::instrument(
    skip_all,
    name = "runtime.presign_midias",
    fields(tenant_id = %tenant_uuid, qtd = blocos.len(), ttl = TTL_URL_MIDIA_S)
)]
async fn assinar_midias_da_pagina(
    storage: Option<&transport::MuxClient>,
    tenant_uuid: Uuid,
    traceparent: &str,
    mut blocos: Vec<&mut serde_json::Value>,
) -> bool {
    // Chaves únicas, na ordem em que aparecem (a mesma mídia reenviada é a mesma
    // chave content-addressable: assina uma vez só).
    let mut vistas = std::collections::HashSet::new();
    let itens: Vec<serde_json::Value> = blocos
        .iter()
        .filter_map(|b| {
            let chave = b.get("chave").and_then(|v| v.as_str())?.trim();
            if chave.is_empty() || !vistas.insert(chave.to_string()) {
                return None;
            }
            let content_type = b
                .get("mimetype")
                .and_then(|v| v.as_str())
                .filter(|m| !m.trim().is_empty());
            Some(serde_json::json!({ "file_name": chave, "content_type": content_type }))
        })
        .collect();
    if itens.is_empty() {
        return true;
    }
    let Some(storage) = storage else {
        tracing::warn!("storage não configurado; mídias da página saem sem URL");
        return false;
    };

    let Some(urls) =
        presign_em_lote(storage, tenant_uuid, traceparent, &itens, TTL_URL_MIDIA_S).await
    else {
        tracing::warn!("falha ao assinar as mídias da página");
        return false;
    };

    for bloco in blocos.iter_mut() {
        let url = bloco
            .get("chave")
            .and_then(|v| v.as_str())
            .map(str::trim)
            .and_then(|c| urls.get(c))
            .cloned();
        if let (Some(url), Some(obj)) = (url, bloco.as_object_mut()) {
            obj.insert("url_assinada".to_string(), serde_json::Value::String(url));
        }
    }
    true
}

/// P2a/P6 — `PresignFiles` em lotes de até [`TETO_PRESIGN_LOTE`] itens
/// (`{ file_name, content_type? }`). Devolve `chave → URL`, ou `None` se algum
/// lote falhou (sem detalhe do erro: a mensagem do storage pode carregar a
/// chave). Nenhuma chave nem URL vai para log.
async fn presign_em_lote(
    storage: &transport::MuxClient,
    tenant_uuid: Uuid,
    traceparent: &str,
    itens: &[serde_json::Value],
    ttl_s: u64,
) -> Option<std::collections::HashMap<String, String>> {
    let mut urls: std::collections::HashMap<String, String> = std::collections::HashMap::new();
    for lote in itens.chunks(TETO_PRESIGN_LOTE) {
        let env_presign = Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.to_string(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "PresignFiles".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({
                "itens": lote,
                "expires_in": ttl_s,
            }))
            .unwrap_or_default(),
            ..Default::default()
        };
        let resp = match storage
            .call(env_presign, std::time::Duration::from_secs(5))
            .await
        {
            Ok(r) if r.kind != MessageKind::Error as i32 => r,
            _ => return None,
        };
        let corpo: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap_or_default();
        for u in corpo
            .get("urls")
            .and_then(|v| v.as_array())
            .into_iter()
            .flatten()
        {
            if let (Some(chave), Some(url)) = (
                u.get("file_name").and_then(|v| v.as_str()),
                u.get("url").and_then(|v| v.as_str()),
            ) {
                urls.insert(chave.to_string(), url.to_string());
            }
        }
    }
    Some(urls)
}

/// P6 — validade (s) da URL assinada do avatar do contato. O cliente
/// reaproveita a URL do mesmo objeto enquanto fresca (regra do C17).
const TTL_URL_FOTO_S: u64 = 3600;

/// P6 — sem nova sincronização da foto antes disto (a não ser com `forcar`).
const PRAZO_FOTO_DIAS: i64 = 7;

/// P6 — piso do `forcar`: uma tela em laço não pede sincronização a cada quadro.
const PISO_FOTO_FORCADA_MIN: i64 = 10;

/// P6 — no máximo tantos pedidos de sincronização por listagem do quadro: o
/// quadro recarrega a cada evento, e o worker já trava por contato.
const TETO_SYNC_FOTO_POR_LISTAGEM: usize = 20;

/// P6 — chave do avatar no R2, ou `None` para o que não é uma (vazio ou
/// legado anterior ao P6 — nunca uma URL).
fn chave_de_foto(valor: &str) -> Option<&str> {
    let v = valor.trim();
    (v.starts_with("contatos/") && !v.contains("://")).then_some(v)
}

/// P6 — a foto do contato precisa ser sincronizada de novo? Nunca verificada,
/// mais de 7 dias, ou `forcar` com mais de 10 minutos da última verificação.
///
/// É uma decisão pura: quem sincroniza é o worker, pelo barramento — o
/// `runtime_api` nunca chama o provedor no caminho da requisição.
fn precisa_sincronizar_foto(verificada_ha: Option<chrono::Duration>, forcar: bool) -> bool {
    let prazo = if forcar {
        chrono::Duration::minutes(PISO_FOTO_FORCADA_MIN)
    } else {
        chrono::Duration::days(PRAZO_FOTO_DIAS)
    };
    verificada_ha.is_none_or(|idade| idade > prazo)
}

/// P6 — idade da última verificação da foto (`foto_verificada_em` RFC3339).
fn idade_da_verificacao(v: &serde_json::Value, campo: &str) -> Option<chrono::Duration> {
    v.get(campo)
        .and_then(|x| x.as_str())
        .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
        .map(|d| chrono::Utc::now().signed_duration_since(d))
}

/// P6 — o `origem` do span de `ObterContatoDoAtendimento`: `agendada` quando
/// pediu sincronização, `r2` quando devolve a foto guardada, `cache` quando
/// não há foto e a verificação está em dia.
fn origem_da_foto(agendada: bool, tem_chave: bool) -> &'static str {
    match (agendada, tem_chave) {
        (true, _) => "agendada",
        (false, true) => "r2",
        (false, false) => "cache",
    }
}

/// P6 — publica `contato.foto.sincronizar` no barramento; o worker baixa a
/// foto e grava no R2. Best-effort: falhar aqui só adia a foto.
async fn pedir_sincronizacao_da_foto(
    bus: &redis::aio::ConnectionManager,
    tenant_uuid: Uuid,
    contato_id: i32,
    traceparent: &str,
) {
    let evento = contracts::TenantEnvelope::novo(
        tenant_uuid,
        "contato.foto.sincronizar",
        serde_json::json!({ "contato_id": contato_id, "instance_id": null }),
    )
    .com_traceparent(traceparent);
    let mut conn = bus.clone();
    if let Err(e) = transport::bus::publicar_evento(&mut conn, &evento).await {
        tracing::warn!(erro = %e, "falha ao pedir a sincronização da foto do contato");
    }
}

/// P6 — o tenant do access token já validado pela chamada anterior (só decodifica:
/// a blocklist foi conferida por quem autenticou).
fn tenant_do_token<T>(req: &Request<T>) -> Option<Uuid> {
    let bearer = bearer_do_metadata(req);
    let token = bearer.strip_prefix("Bearer ").unwrap_or(&bearer).trim();
    application::jwt::validar_access_token(token)
        .ok()
        .and_then(|c| Uuid::parse_str(&c.tenant_id).ok())
}

/// Header com que o `mcp_server` declara a tool e o consentimento de cada chamada.
///
/// Existe porque o gRPC não deixa o cliente mandar o próprio `user-agent` por
/// chamada: o core do gRPC (Python e C) sobrescreve o valor com
/// `grpc-python-asyncio/...`, e toda ação de agente chegava ao `audit_log`
/// indistinguível — a tela "o que o agente fez" nunca achava nada.
const HEADER_ORIGEM_AGENTE: &str = "x-smartcore-agente";

/// Prefixo que a trilha reconhece como agente (o mesmo de
/// `infrastructure_postgres::auditoria::audit_log::PREFIXO_USER_AGENT_MCP`).
const PREFIXO_ORIGEM_AGENTE: &str = "SmartCoreAssistant-MCP/";

/// Extrai a origem da requisição para a auditoria (WS-5b). Metadado de
/// auditoria, não segredo; truncado defensivamente para evitar payload abusivo
/// no audit_log.
///
/// A origem declarada pelo agente MCP vence o `user-agent` do transporte, mas só
/// quando segue o formato `SmartCoreAssistant-MCP/<tool>`: é autodeclarada, como
/// o próprio `user-agent`, e só serve para rotular a ação de quem já se
/// autenticou — não concede nada.
fn user_agent_do_metadata<T>(req: &Request<T>) -> String {
    let texto = |chave: &str| {
        req.metadata()
            .get(chave)
            .and_then(|v| v.to_str().ok())
            .map(|s| s.chars().take(512).collect::<String>())
    };
    texto(HEADER_ORIGEM_AGENTE)
        .filter(|s| s.starts_with(PREFIXO_ORIGEM_AGENTE))
        .or_else(|| texto("user-agent"))
        .unwrap_or_default()
}

/// A mesma escolha de [`user_agent_do_metadata`], a partir dos headers HTTP.
fn origem_dos_headers(headers: &http::HeaderMap) -> String {
    let texto = |chave: &str| {
        headers
            .get(chave)
            .and_then(|v| v.to_str().ok())
            .map(|s| s.chars().take(512).collect::<String>())
    };
    texto(HEADER_ORIGEM_AGENTE)
        .filter(|s| s.starts_with(PREFIXO_ORIGEM_AGENTE))
        .or_else(|| texto("user-agent"))
        .unwrap_or_default()
}

/// Camada que registra a origem de cada requisição para o `transport`.
///
/// Dezenas de handlers montam o envelope para os serviços de dados sem copiar
/// o `user_agent`; com a origem guardada aqui, o `MuxClient` completa todos eles
/// (ver `transport::origem`). Sem isto, arquivar um atendimento ou mudar a
/// configuração avançada pelo agente MCP chegava à trilha sem origem.
#[derive(Clone, Copy, Default)]
pub(crate) struct CamadaOrigem;

impl<S> tower::Layer<S> for CamadaOrigem {
    type Service = ServicoComOrigem<S>;

    fn layer(&self, inner: S) -> Self::Service {
        ServicoComOrigem { inner }
    }
}

#[derive(Clone)]
pub(crate) struct ServicoComOrigem<S> {
    inner: S,
}

impl<S, B> tower::Service<http::Request<B>> for ServicoComOrigem<S>
where
    S: tower::Service<http::Request<B>>,
    S::Future: Send + 'static,
    S::Response: 'static,
    S::Error: 'static,
{
    type Response = S::Response;
    type Error = S::Error;
    type Future = futures_util::future::BoxFuture<'static, Result<S::Response, S::Error>>;

    fn poll_ready(
        &mut self,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, req: http::Request<B>) -> Self::Future {
        let origem = origem_dos_headers(req.headers());
        let futuro = self.inner.call(req);
        Box::pin(transport::origem::com_origem(origem, futuro))
    }
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

/// Janela em minutos entre revogar um consentimento MCP e o acesso em curso
/// realmente cessar — o access token só morre no `exp`.
///
/// Lê a mesma variável que o authorization server (`MCP_ACCESS_TTL_S`), para que
/// a tela não prometa um número diferente do que o sistema pratica.
fn janela_revogacao_min() -> i32 {
    let ttl = std::env::var("MCP_ACCESS_TTL_S")
        .ok()
        .and_then(|v| v.parse::<i64>().ok())
        .unwrap_or(900);
    // Arredonda para cima: dizer "15 minutos" quando são 15min e 1s seria
    // prometer por baixo justo na informação que o usuário usa para decidir se
    // precisa fazer mais alguma coisa depois de desconectar.
    // `div_ceil` é estável só para inteiros sem sinal; em `i64` ainda é instável
    // (`int_roundings`, rust-lang/rust#88581).
    ((ttl + 59) / 60) as i32
}

/// Exige, para a rota informada, o escopo declarado em [`crate::rbac::MAPA`].
///
/// Fail-closed: rota não declarada é negada. É de propósito — esquecer de
/// declarar aparece no primeiro teste; esquecer de restringir não apareceria em
/// lugar nenhum até virar incidente.
fn exigir_escopo_de_rota(claims: &application::jwt::Claims, metodo: &str) -> Result<(), Status> {
    let Some(exigidos) = crate::rbac::escopos_da_rota(metodo) else {
        tracing::error!(
            rota = metodo,
            "rota sem escopo declarado em rbac::MAPA — negada por segurança"
        );
        return Err(Status::permission_denied("errors.auth.forbidden"));
    };

    if crate::rbac::autorizado(&claims.scopes, exigidos, claims.is_superuser) {
        return Ok(());
    }

    // O corpo da requisição NÃO entra no log: pode carregar conteúdo de mensagem
    // ou dado de contato. Rota e escopo faltante bastam para diagnosticar.
    tracing::warn!(
        rota = metodo,
        escopos_exigidos = ?exigidos,
        user_id = %claims.sub,
        "permissão negada: sessão sem escopo para a rota"
    );
    Err(Status::permission_denied("errors.auth.forbidden"))
}

// --- Plano ia-engine-jev: conversões JSON ⇄ proto da transferência ---

fn texto_de(v: &serde_json::Value, k: &str) -> String {
    v.get(k)
        .and_then(|x| x.as_str())
        .unwrap_or_default()
        .to_string()
}

fn lista_de(v: &serde_json::Value, k: &str) -> Vec<String> {
    v.get(k)
        .and_then(|x| x.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|s| s.as_str().map(str::to_string))
                .collect()
        })
        .unwrap_or_default()
}

fn regra_do_json(v: &serde_json::Value) -> q::RegraTransferencia {
    q::RegraTransferencia {
        id: v.get("id").and_then(|x| x.as_i64()).unwrap_or(0),
        nome: texto_de(v, "nome"),
        gatilho_tipo: texto_de(v, "gatilho_tipo"),
        condicao: texto_de(v, "condicao"),
        intencao_tag: texto_de(v, "intencao_tag"),
        exemplos_sim: lista_de(v, "exemplos_sim"),
        exemplos_nao: lista_de(v, "exemplos_nao"),
        momento: texto_de(v, "momento"),
        campos_coleta: lista_de(v, "campos_coleta"),
        destino_tipo: texto_de(v, "destino_tipo"),
        destino_fluxo_id: v
            .get("destino_fluxo_id")
            .and_then(|x| x.as_i64())
            .unwrap_or(0) as i32,
        mensagem: texto_de(v, "mensagem"),
        sensibilidade: texto_de(v, "sensibilidade"),
        ativa: v.get("ativa").and_then(|x| x.as_bool()).unwrap_or(false),
        sugestao: v.get("sugestao").and_then(|x| x.as_bool()).unwrap_or(false),
        criado_em: v.get("criado_em").and_then(|x| x.as_i64()).unwrap_or(0),
        atualizado_em: v.get("atualizado_em").and_then(|x| x.as_i64()).unwrap_or(0),
    }
}

fn regra_para_json(r: &q::RegraTransferencia) -> serde_json::Value {
    serde_json::json!({
        "id": r.id,
        "nome": r.nome,
        "gatilho_tipo": r.gatilho_tipo,
        "condicao": r.condicao,
        "intencao_tag": r.intencao_tag,
        "exemplos_sim": r.exemplos_sim,
        "exemplos_nao": r.exemplos_nao,
        "momento": r.momento,
        "campos_coleta": r.campos_coleta,
        "destino_tipo": r.destino_tipo,
        // 0 = nenhum: vai como null para o servidor limpar o destino.
        "destino_fluxo_id": (r.destino_fluxo_id > 0).then_some(r.destino_fluxo_id),
        "mensagem": r.mensagem,
        "sensibilidade": r.sensibilidade,
    })
}

fn config_transferencia_do_json(v: &serde_json::Value) -> q::ConfigTransferencia {
    q::ConfigTransferencia {
        sinais: v
            .get("sinais")
            .and_then(|x| x.as_array())
            .map(|a| {
                a.iter()
                    .map(|s| q::SinalTransferencia {
                        nome: texto_de(s, "nome"),
                        ativo: s.get("ativo").and_then(|x| x.as_bool()).unwrap_or(false),
                        sensibilidade: texto_de(s, "sensibilidade"),
                    })
                    .collect()
            })
            .unwrap_or_default(),
        fluxo_padrao_id: v
            .get("fluxo_padrao_id")
            .and_then(|x| x.as_i64())
            .unwrap_or(0) as i32,
        msg_transferencia: texto_de(v, "msg_transferencia"),
        motor_analise: texto_de(v, "motor_analise"),
    }
}

fn transferencia_do_json(v: &serde_json::Value) -> q::TransferenciaIa {
    q::TransferenciaIa {
        id: v.get("id").and_then(|x| x.as_i64()).unwrap_or(0),
        atendimento_id: v
            .get("atendimento_id")
            .and_then(|x| x.as_i64())
            .unwrap_or(0) as i32,
        motor: texto_de(v, "motor"),
        modelo: texto_de(v, "modelo"),
        motivo: texto_de(v, "motivo"),
        regra_id: v.get("regra_id").and_then(|x| x.as_i64()).unwrap_or(0),
        fluxo_id: v.get("fluxo_id").and_then(|x| x.as_i64()).unwrap_or(0) as i32,
        fluxo_nome: texto_de(v, "fluxo_nome"),
        sinais: v
            .get("sinais")
            .and_then(|x| x.as_array())
            .map(|a| {
                a.iter()
                    .map(|s| q::SinalValor {
                        nome: texto_de(s, "nome"),
                        valor: s.get("valor").and_then(|x| x.as_f64()).unwrap_or(0.0),
                        limiar: s.get("limiar").and_then(|x| x.as_f64()).unwrap_or(0.0),
                    })
                    .collect()
            })
            .unwrap_or_default(),
        criado_em: v.get("criado_em").and_then(|x| x.as_i64()).unwrap_or(0),
    }
}

/// Lista de textos de um campo JSON (itens que não são texto ficam de fora).
fn lista_de_textos(v: &serde_json::Value, chave: &str) -> Vec<String> {
    v.get(chave)
        .and_then(|x| x.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|c| c.as_str().map(str::to_string))
                .collect()
        })
        .unwrap_or_default()
}

/// O catálogo de intenções do `ListIntentsReply`, como o motor Jev o recebe.
fn intents_do_catalogo(v: &serde_json::Value) -> Vec<ia_client::client::IntentDefInput> {
    v.get("intents")
        .and_then(|x| x.as_array())
        .map(|a| {
            a.iter()
                .map(|i| ia_client::client::IntentDefInput {
                    tag: texto_de(i, "tag").trim().to_string(),
                    grupo: texto_de(i, "grupo"),
                    descricao: texto_de(i, "descricao"),
                    exemplo: texto_de(i, "exemplo"),
                    comportamento: texto_de(i, "comportamento"),
                    campos_coleta: lista_de_textos(i, "campos_coleta"),
                    max_perguntas: i.get("max_perguntas").and_then(|x| x.as_i64()).unwrap_or(0)
                        as i32,
                    apos_coleta: texto_de(i, "apos_coleta"),
                })
                .filter(|i| !i.tag.is_empty())
                .collect()
        })
        .unwrap_or_default()
}

#[cfg(test)]
mod tests_transferencia {
    use super::*;

    #[test]
    fn regra_ida_e_volta_sem_destino_vira_null() {
        let r = q::RegraTransferencia {
            id: 4,
            nome: "Fechar".into(),
            condicao: "o cliente quer fechar".into(),
            exemplos_sim: vec!["pode fechar".into()],
            destino_fluxo_id: 0,
            ..Default::default()
        };
        let j = regra_para_json(&r);
        assert!(j["destino_fluxo_id"].is_null());
        let volta = regra_do_json(&j);
        assert_eq!(volta.nome, "Fechar");
        assert_eq!(volta.exemplos_sim, vec!["pode fechar"]);
    }

    #[test]
    fn config_e_transferencias_do_json() {
        let c = config_transferencia_do_json(&serde_json::json!({
            "sinais": [{ "nome": "pede_humano", "ativo": true, "sensibilidade": "alta" }],
            "fluxo_padrao_id": null,
            "motor_analise": "sombra",
        }));
        assert_eq!(c.sinais[0].sensibilidade, "alta");
        assert_eq!(c.fluxo_padrao_id, 0);
        assert_eq!(c.motor_analise, "sombra");
        let t = transferencia_do_json(&serde_json::json!({
            "id": 1, "motivo": "regra:Fechar", "sinais": [{ "nome": "pede_humano", "valor": 0.9, "limiar": 0.8 }],
        }));
        assert_eq!(t.motivo, "regra:Fechar");
        assert_eq!(t.sinais[0].valor, 0.9);
        let intents = intents_do_catalogo(
            &serde_json::json!({ "intents": [{ "tag": " a " }, { "tag": "" }] }),
        );
        assert_eq!(intents.len(), 1);
        assert_eq!(intents[0].tag, "a");
    }
}

/// Os fluxos do tenant no formato que o `Responder` espera: chave
/// "Setor - descrição" (na falta da descrição, o nome do fluxo) e o id como
/// valor — a mesma convenção do worker, para o ensaio e a conversa real
/// oferecerem à IA o mesmo catálogo.
fn fluxos_para_o_responder(resp: &serde_json::Value) -> Vec<(String, String)> {
    resp.get("fluxos")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|f| {
                    let id = f.get("id").and_then(|v| v.as_i64())?;
                    let setor = f.get("setor").and_then(|v| v.as_str()).unwrap_or_default();
                    let descricao = f
                        .get("descricao")
                        .and_then(|v| v.as_str())
                        .filter(|s| !s.is_empty())
                        .or_else(|| f.get("nome").and_then(|v| v.as_str()))
                        .unwrap_or_default();
                    Some((format!("{setor} - {descricao}"), id.to_string()))
                })
                .collect()
        })
        .unwrap_or_default()
}

/// Exige que a sessão (já autenticada) tenha **um** dos escopos informados.
///
/// Usada pelos handlers operacionais escritos à mão, que até N13.3 exigiam
/// apenas sessão válida — e por isso deixavam um `viewer` enviar mensagem a
/// cliente final.
fn exigir_escopo(
    claims: &application::jwt::Claims,
    exigidos: &[&str],
    rota: &str,
) -> Result<(), Status> {
    if crate::rbac::autorizado(&claims.scopes, exigidos, claims.is_superuser) {
        return Ok(());
    }
    tracing::warn!(
        rota,
        escopos_exigidos = ?exigidos,
        user_id = %claims.sub,
        "permissão negada: sessão sem escopo para a operação"
    );
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

/// Erros do `IssueReleaseDownloadTicket` → `Status` que a tela do instalador
/// distingue: canal inválido, downloads não configurados e release inexistente.
fn status_do_erro_de_release(err: Option<contracts::ErrorEnvelope>) -> Status {
    let Some(err) = err else {
        return Status::internal("Erro no control_plane");
    };
    match err.code.as_str() {
        "VALIDATION_FAILED" => Status::invalid_argument(err.message),
        "CONFLICT" => Status::failed_precondition(err.message),
        "STORAGE_NOT_FOUND" => Status::not_found(err.message),
        c if c.starts_with("AUTH_") => Status::permission_denied("errors.auth.forbidden"),
        _ => Status::internal(format!("Erro no control_plane: {}", err.message)),
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
        confianca_minima_transferencia: campo_str("confianca_minima_transferencia"),
        confianca_minima_automatica: campo_str("confianca_minima_automatica"),
        api_keys: api_keys_proto,
        // Configuração avançada (paridade MCP).
        entity_types_json: val
            .get("entity_types")
            .filter(|v| !v.is_null())
            .map(|v| v.to_string())
            .unwrap_or_default(),
        prompts: val
            .get("prompts")
            .and_then(|v| v.as_object())
            .map(|o| {
                let mut itens: Vec<PromptDoTenant> = o
                    .iter()
                    .filter_map(|(k, v)| {
                        Some(PromptDoTenant {
                            chave: k.clone(),
                            texto: v.as_str()?.to_string(),
                        })
                    })
                    .collect();
                itens.sort_by(|a, b| a.chave.cmp(&b.chave));
                itens
            })
            .unwrap_or_default(),
        brand_name: texto_do(val, "brand_name"),
        primary_color: texto_do(val, "primary_color"),
        secondary_color: texto_do(val, "secondary_color"),
        timezone: texto_do(val, "timezone"),
        language_code: texto_do(val, "language_code"),
        analise_previa_habilitada: val
            .get("analise_previa_habilitada")
            .and_then(|v| v.as_bool()),
        pesquisa_satisfacao_ativa: val
            .get("pesquisa_satisfacao_ativa")
            .and_then(|v| v.as_bool()),
        msg_pesquisa_satisfacao: texto_do(val, "msg_pesquisa_satisfacao"),
        minutos_inatividade_encerra: val
            .get("minutos_inatividade_encerra")
            .and_then(|v| v.as_i64())
            .map(|v| v as i32),
        transcription_enabled: val.get("transcription_enabled").and_then(|v| v.as_bool()),
        // Preenchido pelo handler (vem do cache de config, não deste JSON).
        motor_analise: String::new(),
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

    /// N11 E8 — pedido de redefinição de senha. Pública.
    ///
    /// Responde `aceito` para qualquer login bem formado, exista a conta ou
    /// não: responder diferente seria um oráculo de "quais e-mails têm conta
    /// aqui". Pelo mesmo motivo o e-mail sai em segundo plano — esperar o SMTP
    /// só quando a conta existe faria o tempo de resposta contar o segredo.
    #[tracing::instrument(
        skip_all,
        fields(
            service = "runtime_api",
            rpc = "SolicitarRedefinicaoSenha",
            traceparent
        )
    )]
    async fn solicitar_redefinicao_senha(
        &self,
        req: Request<SolicitarRedefinicaoSenhaRequest>,
    ) -> Result<Response<SolicitarRedefinicaoSenhaResponse>, Status> {
        let traceparent = traceparent_do_metadata(&req);
        let ip = ip_do_metadata(&req);
        // NUNCA logar o login: é o e-mail de alguém.
        let login = req.into_inner().login.trim().to_string();
        if login.is_empty() {
            return Err(Status::invalid_argument("errors.validation"));
        }

        // Por IP, e dito ao cliente: varrer endereços a partir de uma máquina é
        // o abuso, e recusar não revela nada sobre conta nenhuma.
        if let Some(ip) = ip.as_deref() {
            if tentativas_na_janela(
                &self.deps,
                &traceparent,
                "redefinicao_senha_ip",
                ip,
                15 * 60,
            )
            .await
            .is_some_and(|n| n > 10)
            {
                return Err(Status::resource_exhausted("errors.auth.rate_limited"));
            }
        }

        let aceito = || Response::new(SolicitarRedefinicaoSenhaResponse { aceito: true });

        // Por conta, em silêncio: avisar "muitos pedidos para esta conta"
        // confirmaria que ela existe. O limite só impede de encher a caixa de
        // entrada de alguém com links.
        let id_conta = application::tokens::hash_sha256_hex(&login.to_lowercase());
        if tentativas_na_janela(
            &self.deps,
            &traceparent,
            "redefinicao_senha_conta",
            &id_conta,
            60 * 60,
        )
        .await
        .is_some_and(|n| n > 3)
        {
            tracing::warn!("pedidos de redefinição acima do limite para uma conta; ignorado");
            return Ok(aceito());
        }

        // O token nasce aqui e só o hash desce: o banco nunca vê o token.
        let token = application::tokens::gerar_refresh_token();
        let env_req = application::auth::login::montar_envelope_request(
            Uuid::nil(),
            &traceparent,
            "SolicitarRedefinicaoSenha",
            &serde_json::json!({
                "login": login,
                "token_hash": application::tokens::hash_sha256_hex(&token),
            }),
        );
        let resp = self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
            .map_err(|e| Status::unavailable(format!("Falha no serviço interno: {e}")))?;
        if resp.kind == MessageKind::Error as i32 {
            return Err(status_do_erro_interno(resp.error));
        }

        let corpo: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap_or_default();
        if corpo.get("enviar").and_then(serde_json::Value::as_bool) == Some(true) {
            let texto = |k: &str| {
                corpo
                    .get(k)
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string()
            };
            let (para, nome) = (texto("email"), texto("nome"));
            let validade_min = corpo
                .get("validade_min")
                .and_then(serde_json::Value::as_i64)
                .unwrap_or(60);
            let link = format!("{}/redefinir-senha?token={}", base_publica_do_app(), token);
            let email = self.email.clone();
            tokio::spawn(async move {
                let envio = infrastructure_email::redefinicao_senha::enviar(
                    &email,
                    infrastructure_email::redefinicao_senha::DadosDaRedefinicao {
                        para: &para,
                        nome: &nome,
                        link: &link,
                        validade_min,
                    },
                )
                .await;
                if let Err(erro) = envio {
                    tracing::error!(%erro, "pedido de redefinição registrado, mas o e-mail não saiu");
                }
            });
        }

        Ok(aceito())
    }

    /// N11 E8 — troca a senha com o token do e-mail. Pública.
    ///
    /// Depois de trocar, derruba as sessões abertas: quem redefine por suspeita
    /// quer justamente tirar o acesso de quem tinha a senha antiga, e ele não
    /// pode continuar logado com o refresh que já tem. O access token em mãos
    /// segue válido até expirar (minutos); o refresh, não.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "RedefinirSenha", traceparent)
    )]
    async fn redefinir_senha(
        &self,
        req: Request<RedefinirSenhaRequest>,
    ) -> Result<Response<RedefinirSenhaResponse>, Status> {
        let traceparent = traceparent_do_metadata(&req);
        let ip = ip_do_metadata(&req);
        // Nem o token nem a senha entram em log.
        let RedefinirSenhaRequest { token, nova_senha } = req.into_inner();

        if let Some(ip) = ip.as_deref() {
            if tentativas_na_janela(&self.deps, &traceparent, "redefinir_senha_ip", ip, 15 * 60)
                .await
                .is_some_and(|n| n > 20)
            {
                return Err(Status::resource_exhausted("errors.auth.rate_limited"));
            }
        }
        if token.trim().is_empty() {
            return Err(Status::failed_precondition("link de redefinição inválido"));
        }

        let env_req = application::auth::login::montar_envelope_request(
            Uuid::nil(),
            &traceparent,
            "RedefinirSenha",
            &serde_json::json!({
                "token_hash": application::tokens::hash_sha256_hex(token.trim()),
                "password": nova_senha,
            }),
        );
        let resp = self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(10))
            .await
            .map_err(|e| Status::unavailable(format!("Falha no serviço interno: {e}")))?;
        if resp.kind == MessageKind::Error as i32 {
            return Err(status_do_erro_interno(resp.error));
        }

        let corpo: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap_or_default();
        if let Some(user_id) = corpo
            .get("user_id")
            .and_then(serde_json::Value::as_i64)
            .map(|v| v as i32)
        {
            let revogar = application::auth::login::montar_envelope_request(
                Uuid::nil(),
                &traceparent,
                "RevokeUserSessions",
                &serde_json::json!({ "user_id": user_id }),
            );
            // A senha já foi trocada: não desfazê-la por causa do Redis. O
            // aviso fica no log, e os refresh antigos expiram no próprio TTL.
            match self
                .deps
                .redis
                .call(revogar, std::time::Duration::from_secs(3))
                .await
            {
                Ok(r) if r.kind != MessageKind::Error as i32 => {}
                outro => tracing::warn!(
                    user_id,
                    "senha trocada, mas as sessões antigas não foram encerradas: {outro:?}"
                ),
            }
        }

        Ok(Response::new(RedefinirSenhaResponse { sucesso: true }))
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
    /// Cliente do `data_whatsapp`, para a configuração guiada do tenant
    /// (criar instância e acompanhar o pareamento). O `AuthDeps` só carrega
    /// `pg` e `redis`.
    whatsapp: transport::MuxClient,
    /// Cliente do `ia_engine`, só para o ensaio de pergunta.
    ///
    /// O worker continua sendo quem responde de verdade; aqui a chamada é
    /// síncrona e a pedido de uma pessoa que está olhando a tela — passá-la
    /// pelo barramento assíncrono seria usar a ferramenta errada. Os dois usam
    /// a mesma crate, então timeout, retry e degradação são configurados num
    /// lugar só.
    ia: Arc<dyn ia_client::IaEngineClient>,
    /// Plano ia-engine-jev — o motor Jev (`SMARTCORE_IA_ENGINE_JEV_ENDPOINT`),
    /// para o teste de regra e para o ensaio de pergunta de quem já está no
    /// motor Jev ou na sombra. `None` = não configurado.
    ia_jev: Option<Arc<dyn ia_client::IaEngineClient>>,
    /// Os mesmos provedores de pagamento do wizard público.
    ///
    /// Compartilhar o registro é o ponto: quitar depois do login e pagar durante
    /// o cadastro passam pelo mesmo provedor, com as mesmas regras de resgate. A
    /// única diferença é de onde vem a identidade — claims aqui, `signup_token`
    /// lá. Duplicar a lógica faria as duas divergirem na primeira mudança.
    provedores: application::pagamento::RegistroProvedores,
    /// Envio de e-mail transacional — hoje, só o convite de equipe.
    ///
    /// Fica aqui e não no `AuthDeps` porque o `control_plane` compartilha
    /// aquela struct e não manda e-mail nenhum. Quando não há SMTP no
    /// ambiente, o enviador entra no modo desligado e registra em log em vez
    /// de falhar — ver a nota do crate.
    email: infrastructure_email::Enviador,
}

impl AdminFacade {
    /// P18 — chamada ao `data_postgres` em nome do superusuário.
    async fn chamar_pg_como_superusuario(
        &self,
        claims: &application::jwt::Claims,
        traceparent: String,
        metodo: &str,
        payload: serde_json::Value,
    ) -> Result<serde_json::Value, Status> {
        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent,
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: metodo.to_string(),
            payload: serde_json::to_vec(&payload).unwrap_or_default(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };
        let resp = self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(30))
            .await
            .map_err(|e| Status::internal(e.to_string()))?;
        if resp.kind == MessageKind::Error as i32 {
            let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
            return Err(Status::failed_precondition(err_msg));
        }
        serde_json::from_slice(&resp.payload).map_err(|e| Status::internal(e.to_string()))
    }

    pub fn new(
        deps: Arc<AuthDeps>,
        bus: redis::aio::ConnectionManager,
        control: transport::MuxClient,
        realtime: crate::realtime::RealtimeManager,
        whatsapp: transport::MuxClient,
        ia: Arc<dyn ia_client::IaEngineClient>,
        provedores: application::pagamento::RegistroProvedores,
    ) -> Self {
        Self {
            deps,
            bus,
            control,
            realtime,
            whatsapp,
            ia,
            ia_jev: None,
            provedores,
            email: infrastructure_email::Enviador::do_ambiente(),
        }
    }

    /// Liga o motor Jev ao facade (opcional, lido do ambiente no boot).
    pub fn com_ia_jev(mut self, ia_jev: Option<Arc<dyn ia_client::IaEngineClient>>) -> Self {
        self.ia_jev = ia_jev;
        self
    }

    /// P6 — fotos dos cartões do quadro.
    ///
    /// Assina as chaves do R2 (`contato_foto_chave`) numa chamada
    /// `PresignFiles` (TTL de 3600 s) e grava `contato_foto_url` em cada item.
    /// Para os contatos com a verificação vencida (ou nunca feita), pede ao
    /// worker a sincronização — no máximo [`TETO_SYNC_FOTO_POR_LISTAGEM`] por
    /// chamada; o provedor nunca é chamado aqui.
    #[tracing::instrument(
        skip_all,
        name = "runtime.fotos_do_quadro",
        fields(tenant_id = %tenant_uuid, qtd = itens.len(), agendadas = tracing::field::Empty)
    )]
    async fn preparar_fotos_do_quadro(
        &self,
        tenant_uuid: Uuid,
        traceparent: &str,
        itens: &mut [serde_json::Value],
    ) {
        let mut agendar: Vec<i32> = Vec::new();
        let mut vistas = std::collections::HashSet::new();
        let mut pedidos: Vec<serde_json::Value> = Vec::new();
        for item in itens.iter() {
            if let Some(chave) = chave_de_foto(&texto_do(item, "contato_foto_chave")) {
                if vistas.insert(chave.to_string()) {
                    pedidos.push(serde_json::json!({ "file_name": chave }));
                }
            }
            let contato_id = item.get("contato_id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
            if contato_id > 0
                && agendar.len() < TETO_SYNC_FOTO_POR_LISTAGEM
                && !agendar.contains(&contato_id)
                && item.get("contato_foto_chave").is_some()
                && precisa_sincronizar_foto(
                    idade_da_verificacao(item, "contato_foto_verificada_em"),
                    false,
                )
            {
                agendar.push(contato_id);
            }
        }
        tracing::Span::current().record("agendadas", agendar.len());
        for contato_id in agendar {
            pedir_sincronizacao_da_foto(&self.bus, tenant_uuid, contato_id, traceparent).await;
        }

        if pedidos.is_empty() {
            return;
        }
        let Some(storage) = self.deps.storage.as_ref() else {
            return;
        };
        let Some(urls) =
            presign_em_lote(storage, tenant_uuid, traceparent, &pedidos, TTL_URL_FOTO_S).await
        else {
            tracing::warn!("falha ao assinar as fotos do quadro");
            return;
        };
        for item in itens.iter_mut() {
            let url = chave_de_foto(&texto_do(item, "contato_foto_chave"))
                .and_then(|c| urls.get(c))
                .cloned();
            if let (Some(url), Some(obj)) = (url, item.as_object_mut()) {
                obj.insert("contato_foto_url".into(), serde_json::Value::String(url));
            }
        }
    }

    /// O motor efetivo do tenant (`llm` | `sombra` | `jev`). Leitura interna,
    /// sem o RBAC da rota: quem testa a pergunta tem `treinamento:read`, e o
    /// motor não é segredo. Falha = `llm`.
    async fn motor_do_tenant(&self, tenant_id: &str, traceparent: &str) -> String {
        let env_req = Envelope {
            tenant_id: tenant_id.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            traceparent: traceparent.to_string(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "GetConfigTransferencia".to_string(),
            payload: b"{}".to_vec(),
            ..Default::default()
        };
        match self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
        {
            Ok(resp) if resp.kind != MessageKind::Error as i32 => {
                serde_json::from_slice::<serde_json::Value>(&resp.payload)
                    .ok()
                    .and_then(|v| {
                        v.get("motor_analise")
                            .and_then(|m| m.as_str())
                            .map(str::to_string)
                    })
                    .unwrap_or_else(|| "llm".into())
            }
            _ => "llm".into(),
        }
    }

    /// O cliente que responde pelo motor do tenant. Na sombra, o ensaio mostra
    /// o que o Jev faria — é para isso que a sombra existe.
    fn ia_do_motor(&self, motor: &str) -> Arc<dyn ia_client::IaEngineClient> {
        match (motor, self.ia_jev.as_ref()) {
            ("jev" | "sombra", Some(jev)) => jev.clone(),
            _ => self.ia.clone(),
        }
    }

    /// Quantas conversas o tenant ainda pode abrir hoje.
    ///
    /// **Fail-open**: Redis fora do ar não impede de atender. O limite existe
    /// para conter disparo em massa, não para ser mais um ponto de falha entre
    /// o operador e o cliente — e um tenant que não consegue abrir conversa
    /// nenhuma porque o cache caiu é um problema maior do que o que se está
    /// prevenindo.
    async fn conferir_teto_de_atendimento_ativo(
        &self,
        tenant_id: &Uuid,
        traceparent: &str,
    ) -> Result<(), Status> {
        const JANELA_S: u64 = 24 * 60 * 60;
        let teto = std::env::var("ATENDIMENTO_ATIVO_MAX_DIA")
            .ok()
            .and_then(|v| v.parse::<u64>().ok())
            .unwrap_or(50);

        let req = application::auth::login::montar_envelope_request(
            Uuid::nil(),
            traceparent,
            "RegisterRateLimitAttempt",
            &serde_json::json!({
                // O id é o tenant, não o usuário: o número de WhatsApp é do
                // tenant, e é ele que leva a denúncia. Cinco atendentes
                // disparando vinte cada dá cem, e o limite por pessoa não veria
                // nada de errado.
                "recurso": "atendimento_ativo",
                "id": tenant_id.to_string(),
                "window_s": JANELA_S,
            }),
        );

        match self
            .deps
            .redis
            .call(req, std::time::Duration::from_secs(3))
            .await
        {
            Ok(resp) if resp.kind != MessageKind::Error as i32 => {
                let corpo: serde_json::Value =
                    serde_json::from_slice(&resp.payload).unwrap_or_default();
                let tentativas = corpo
                    .get("attempts")
                    .and_then(serde_json::Value::as_u64)
                    .unwrap_or(0);
                if tentativas > teto {
                    tracing::warn!(
                        %tenant_id,
                        tentativas,
                        teto,
                        "teto diário de atendimentos ativos excedido"
                    );
                    return Err(Status::resource_exhausted(
                        "Limite diário de conversas iniciadas atingido. \
                         Iniciar muitas conversas em pouco tempo faz o WhatsApp \
                         bloquear o número.",
                    ));
                }
                Ok(())
            }
            outro => {
                tracing::warn!(%tenant_id, "teto indisponível (fail-open): {outro:?}");
                Ok(())
            }
        }
    }

    /// Manda o e-mail do convite. **Nunca falha para o chamador.**
    ///
    /// O convite já está gravado quando isto roda: o link é válido e está na
    /// tela de quem convidou. Um SMTP fora do ar é um aborrecimento — avisa-se
    /// por outro caminho —, enquanto recusar a criação por causa dele seria
    /// impedir de convidar qualquer pessoa. Por isso todo erro aqui vira log.
    async fn enviar_convite_por_email(&self, invite: &serde_json::Value, tenant_id: &str) {
        let campo = |k: &str| {
            invite
                .get(k)
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string()
        };
        let (para, nome, token, empresa) = (
            campo("email"),
            campo("name"),
            campo("token"),
            campo("tenant_name"),
        );
        if para.is_empty() || token.is_empty() {
            tracing::warn!(tenant_id, "convite sem e-mail ou token; nada a enviar");
            return;
        }

        let link = format!("{}/aceitar-convite?token={}", base_publica_do_app(), token);
        let empresa = if empresa.is_empty() {
            "Sua equipe".to_string()
        } else {
            empresa
        };

        let envio = infrastructure_email::convite::enviar(
            &self.email,
            infrastructure_email::convite::DadosDoConvite {
                para: &para,
                nome: &nome,
                empresa: &empresa,
                link: &link,
                // Espelha o `chrono::Duration::days(7)` do `data_postgres`.
                // Dito no e-mail porque um link sem prazo é um link que fica
                // para depois — e depois ele não funciona mais.
                validade_dias: 7,
            },
        )
        .await;

        match envio {
            Ok(()) if self.email.ativo() => {
                tracing::info!(tenant_id, "convite enviado por e-mail")
            }
            Ok(()) => {}
            Err(erro) => tracing::error!(
                %erro,
                tenant_id,
                "convite criado, mas o e-mail não saiu; o link continua válido"
            ),
        }
    }

    /// Encaminha um RPC com escopo de **tenant**: exige sessão autenticada com o
    /// escopo declarado para a rota e injeta o `tenant_id` das claims no envelope.
    ///
    /// A diferença para [`Self::encaminhar_admin`] é onde o tenant vem: aqui das
    /// claims, nunca do request. Um tenant não alcança o de outro nem mandando o
    /// id na mensagem.
    ///
    /// **N13.3:** o escopo exigido deixou de ser `tenant:admin` fixo e passou a
    /// vir de [`crate::rbac::MAPA`], por rota. O gate anterior barrava
    /// `manager`, `staff` e `viewer` em *todas* as 40 rotas — o catálogo de
    /// escopos do doc 09 §3 existia no papel e não no comportamento.
    async fn encaminhar_tenant<T>(
        &self,
        req: &Request<T>,
        destino: &transport::MuxClient,
        metodo: &str,
        mut payload: serde_json::Value,
    ) -> Result<serde_json::Value, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, req).await?;
        exigir_escopo_de_rota(&claims, metodo)?;
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("sessão sem tenant válido"))?;

        // O `tenant_id` também entra no corpo: alguns handlers o leem de lá.
        if let Some(obj) = payload.as_object_mut() {
            obj.insert(
                "tenant_id".to_string(),
                serde_json::Value::String(tenant_uuid.to_string()),
            );
        }

        let env_req = Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent_do_metadata(req),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: metodo.to_string(),
            payload: serde_json::to_vec(&payload).unwrap_or_default(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: claims.is_superuser,
            // N13.7: o `user_agent` viaja até o `audit_log`, e é ele que
            // distingue ação de agente de IA (`SmartCoreAssistant-MCP/<tool>`)
            // de ação humana no painel. Antes saía vazio nestas 41 rotas, e a
            // trilha não tinha como dizer de onde a mudança veio.
            user_agent: user_agent_do_metadata(req),
            ..Default::default()
        };

        // Criar instância fala com o provedor externo (Evolution) antes de
        // responder; 5s não bastam.
        let resp = destino
            .call(env_req, std::time::Duration::from_secs(30))
            .await
            .map_err(|e| Status::internal(format!("Falha no serviço interno: {e}")))?;

        if resp.kind == MessageKind::Error as i32 {
            return Err(status_do_erro_interno(resp.error));
        }

        serde_json::from_slice(&resp.payload).map_err(|e| Status::internal(e.to_string()))
    }

    /// Exige superusuário, encaminha ao `data_postgres` e devolve o corpo JSON.
    ///
    /// Condensa o preâmbulo que os métodos admin repetem (claims, envelope,
    /// chamada, checagem de erro, parse). Vale para rotas cross-tenant simples,
    /// que não precisam de `tenant_id` no envelope nem de auditoria de borda.
    async fn encaminhar_admin<T>(
        &self,
        req: &Request<T>,
        metodo: &str,
        payload: serde_json::Value,
    ) -> Result<serde_json::Value, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, req).await?;
        let traceparent = traceparent_do_metadata(req);

        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent,
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: metodo.to_string(),
            payload: serde_json::to_vec(&payload).unwrap_or_default(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };

        let resp = self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
            .map_err(|e| Status::internal(format!("Falha no serviço interno: {e}")))?;

        if resp.kind == MessageKind::Error as i32 {
            return Err(status_do_erro_interno(resp.error));
        }

        serde_json::from_slice(&resp.payload).map_err(|e| Status::internal(e.to_string()))
    }

    /// P4 — envelope das rotas operacionais: escopo exigido na borda e
    /// `flow_permissions` resolvidas, que é o que o `data_postgres` usa para o
    /// RBAC fino por fluxo. O `encaminhar_tenant` manda a lista vazia, e com
    /// ela um atendente comum não enxergaria os próprios cartões.
    async fn encaminhar_operacional<T>(
        &self,
        req: &Request<T>,
        metodo: &str,
        escopos: &[&str],
        payload: serde_json::Value,
    ) -> Result<serde_json::Value, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, req).await?;
        exigir_escopo(&claims, escopos, metodo)?;
        let traceparent = traceparent_do_metadata(req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;
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
            traceparent,
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: metodo.to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id,
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: claims.is_superuser,
            flow_permissions,
            ..Default::default()
        };

        let resp = self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(15))
            .await
            .map_err(|e| Status::internal(format!("Falha no serviço interno: {}", e)))?;
        if resp.kind == MessageKind::Error as i32 {
            let err = resp.error.unwrap_or_default();
            // Validação do servidor vira `invalid_argument` na borda: a tela
            // precisa distinguir "você errou" de "o banco caiu".
            return Err(
                if err.category == contracts::ErrorCategory::Validation as i32 {
                    Status::invalid_argument(err.message)
                } else {
                    Status::internal(format!("Erro no banco: {}", err.message))
                },
            );
        }
        serde_json::from_slice(&resp.payload).map_err(|e| Status::internal(e.to_string()))
    }
}

/// Converte o JSON de voucher do `data_postgres` na mensagem do proto.
fn voucher_do_json(item: &serde_json::Value) -> ProtoVoucher {
    let str_de = |k: &str| {
        item.get(k)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let i64_de = |k: &str| item.get(k).and_then(|v| v.as_i64()).unwrap_or_default();

    ProtoVoucher {
        id: str_de("id"),
        codigo: str_de("codigo"),
        descricao: str_de("descricao"),
        plan_id: i64_de("plan_id") as i32,
        plan_name: str_de("plan_name"),
        duracao_dias: i64_de("duracao_dias") as i32,
        max_resgates: i64_de("max_resgates") as i32,
        resgates_usados: i64_de("resgates_usados") as i32,
        valido_de: i64_de("valido_de"),
        valido_ate: i64_de("valido_ate"),
        revogado_em: i64_de("revogado_em"),
        motivo_revogacao: str_de("motivo_revogacao"),
        created_at: i64_de("created_at"),
    }
}

/// Converte o JSON de resgate do `data_postgres` na mensagem do proto.
fn resgate_do_json(item: &serde_json::Value) -> ProtoVoucherRedemption {
    let str_de = |k: &str| {
        item.get(k)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let i64_de = |k: &str| item.get(k).and_then(|v| v.as_i64()).unwrap_or_default();

    ProtoVoucherRedemption {
        id: str_de("id"),
        voucher_id: str_de("voucher_id"),
        tenant_id: str_de("tenant_id"),
        plan_id: i64_de("plan_id") as i32,
        periodo_inicio: i64_de("periodo_inicio"),
        periodo_fim: i64_de("periodo_fim"),
        ip: str_de("ip"),
        redeemed_at: i64_de("redeemed_at"),
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
        let tenant_alvo = inner.tenant_id.clone();

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
                let mut config = mapear_tenant_config_response(&val);
                config.motor_analise = self.motor_do_tenant(&tenant_alvo, &traceparent).await;
                Ok(Response::new(config))
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
            "confianca_minima_transferencia": inner.confianca_minima_transferencia,
            "confianca_minima_automatica": inner.confianca_minima_automatica,
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
    /// D7 — usuários de todos os tenants. Só superusuário.
    ///
    /// `skip_all` e **sem a busca nos campos do span**: o termo é nome ou e-mail
    /// de gente, e um log de busca vira um log de PII.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "AdminListUsers", traceparent)
    )]
    async fn admin_list_users(
        &self,
        req: Request<AdminListUsersRequest>,
    ) -> Result<Response<AdminListUsersResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let inner = req.get_ref().clone();

        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent,
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "AdminListUsers".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({
                "busca": inner.busca,
                "limite": inner.limite,
                "offset": inner.offset,
            }))
            .unwrap_or_default(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };

        let resp = self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
            .map_err(|e| Status::internal(e.to_string()))?;
        if resp.kind == MessageKind::Error as i32 {
            let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
            return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
        }
        let val: serde_json::Value =
            serde_json::from_slice(&resp.payload).map_err(|e| Status::internal(e.to_string()))?;

        let txt = |item: &serde_json::Value, chave: &str| -> String {
            item.get(chave)
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string()
        };

        let mut usuarios = Vec::new();
        if let Some(arr) = val.get("usuarios").and_then(|v| v.as_array()) {
            for item in arr {
                usuarios.push(AdminUserItem {
                    id: item.get("id").and_then(|v| v.as_i64()).unwrap_or_default() as i32,
                    username: txt(item, "username"),
                    email: txt(item, "email"),
                    nome: txt(item, "nome"),
                    is_active: item
                        .get("is_active")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false),
                    is_superuser: item
                        .get("is_superuser")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false),
                    // 0 = nunca entrou. `proto3` não tem opcional em `int64`
                    // sem `optional`, e um zero aqui é inequívoco: ninguém
                    // logou na época do epoch.
                    last_login: item
                        .get("last_login")
                        .and_then(|v| v.as_i64())
                        .unwrap_or_default(),
                    date_joined: item
                        .get("date_joined")
                        .and_then(|v| v.as_i64())
                        .unwrap_or_default(),
                    tenant_dono: txt(item, "tenant_dono"),
                    tenant_membro: txt(item, "tenant_membro"),
                    papel: txt(item, "papel"),
                });
            }
        }

        Ok(Response::new(AdminListUsersResponse { usuarios }))
    }

    /// P18 — torna explícitos os escopos que cada vínculo tem pelo papel.
    ///
    /// A regra (quem depende do fallback e que escopos ele tem) é a do login,
    /// `application::auth::login`; o `data_postgres` só lista e grava. Assim a
    /// migração não tem como gravar um acesso diferente do que a pessoa tinha.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "MigrarEscoposImplicitos", traceparent)
    )]
    async fn migrar_escopos_implicitos(
        &self,
        req: Request<MigrarEscoposImplicitosRequest>,
    ) -> Result<Response<MigrarEscoposImplicitosResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let dry_run = req.get_ref().dry_run;

        let corpo = self
            .chamar_pg_como_superusuario(
                &claims,
                traceparent.clone(),
                "ListarVinculosParaMigracao",
                serde_json::json!({}),
            )
            .await?;
        let vinculos = corpo
            .get("vinculos")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();

        let mut itens = Vec::new();
        let mut contagens: std::collections::BTreeMap<(String, String, String), i32> =
            std::collections::BTreeMap::new();
        for v in &vinculos {
            let lidas = v
                .get("module_permissions")
                .cloned()
                .unwrap_or(serde_json::Value::Null);
            if application::auth::login::tem_permissoes_explicitas(&lidas) {
                continue;
            }
            let papel = texto_do(v, "role");
            let tenant_id = texto_do(v, "tenant_id");
            let tenant_nome = texto_do(v, "tenant_nome");
            *contagens
                .entry((tenant_id.clone(), tenant_nome, papel.clone()))
                .or_default() += 1;
            itens.push(serde_json::json!({
                "id": v.get("id"),
                "user_id": v.get("user_id"),
                "tenant_id": tenant_id,
                "papel": papel,
                "lidas": lidas,
                "escopos": application::auth::login::escopos_do_papel(&papel),
            }));
        }
        let total = itens.len() as i32;

        let (migrados, pulados) = if dry_run || itens.is_empty() {
            (0, 0)
        } else {
            let r = self
                .chamar_pg_como_superusuario(
                    &claims,
                    traceparent,
                    "GravarPermissoesExplicitas",
                    serde_json::json!({ "itens": itens }),
                )
                .await?;
            (
                r.get("migrados").and_then(|x| x.as_i64()).unwrap_or(0) as i32,
                r.get("pulados").and_then(|x| x.as_i64()).unwrap_or(0) as i32,
            )
        };
        tracing::info!(
            total,
            migrados,
            pulados,
            dry_run,
            "migração de escopos implícitos"
        );

        Ok(Response::new(MigrarEscoposImplicitosResponse {
            contagens: contagens
                .into_iter()
                .map(
                    |((tenant_id, tenant_nome, papel), quantidade)| ContagemDeMigracao {
                        tenant_id,
                        tenant_nome,
                        papel,
                        quantidade,
                    },
                )
                .collect(),
            total,
            migrados,
            pulados,
            dry_run,
        }))
    }

    /// D7 — bloqueia/desbloqueia o acesso de um usuário. Só superusuário.
    ///
    /// A recusa de bloquear a si mesmo mora no `data_postgres`, onde o autor vem
    /// do envelope: uma checagem só no cliente não seria defesa nenhuma.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "AdminSetUserActive", traceparent)
    )]
    async fn admin_set_user_active(
        &self,
        req: Request<AdminSetUserActiveRequest>,
    ) -> Result<Response<AdminSetUserActiveResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let inner = *req.get_ref();
        if inner.user_id <= 0 {
            return Err(Status::invalid_argument("usuário inválido"));
        }

        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent,
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "AdminSetUserActive".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({
                "user_id": inner.user_id,
                "ativo": inner.ativo,
            }))
            .unwrap_or_default(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };

        let resp = self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
            .map_err(|e| Status::internal(e.to_string()))?;
        if resp.kind == MessageKind::Error as i32 {
            let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
            return Err(Status::invalid_argument(err_msg));
        }
        let val: serde_json::Value =
            serde_json::from_slice(&resp.payload).map_err(|e| Status::internal(e.to_string()))?;

        Ok(Response::new(AdminSetUserActiveResponse {
            ativo: val
                .get("ativo")
                .and_then(|v| v.as_bool())
                .unwrap_or(inner.ativo),
        }))
    }

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
                            max_fluxos: item
                                .get("max_fluxos")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default() as i32,
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
            "max_departments": inner.max_departments,
            "max_fluxos": inner.max_fluxos
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
                    max_fluxos: item
                        .get("max_fluxos")
                        .and_then(|v| v.as_i64())
                        .unwrap_or_default() as i32,
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
            "max_fluxos": inner.max_fluxos,
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

    // --- Configuração inicial guiada (passos 5 a 8) ---
    //
    // Escopo de TENANT: o `tenant_id` vem das claims. São os RPCs que o app
    // instalado usa para sair da conta criada e chegar ao sistema operando.

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "CreateMyWhatsappInstance", traceparent)
    )]
    async fn create_my_whatsapp_instance(
        &self,
        req: Request<CreateMyWhatsappInstanceRequest>,
    ) -> Result<Response<CreateMyWhatsappInstanceResponse>, Status> {
        let nome = req.get_ref().instance_name.trim().to_string();
        if nome.is_empty() {
            return Err(Status::invalid_argument("informe o nome da conexão"));
        }

        // O `data_whatsapp` aplica o QuotaGuard de instâncias contra o
        // `max_instances` do plano antes de criar no provedor — estourar o
        // limite volta como RESOURCE_EXHAUSTED, e a tela mostra isso.
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.whatsapp,
                "CreateWhatsappInstance",
                serde_json::json!({ "instance_name": nome }),
            )
            .await?;

        Ok(Response::new(CreateMyWhatsappInstanceResponse {
            id: corpo.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32,
            instance_name: corpo
                .get("instance_name")
                .and_then(|v| v.as_str())
                .unwrap_or(&nome)
                .to_string(),
            provider: corpo
                .get("provider")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string(),
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(
            service = "runtime_api",
            rpc = "GetMyWhatsappInstanceStatus",
            traceparent
        )
    )]
    async fn get_my_whatsapp_instance_status(
        &self,
        req: Request<GetMyWhatsappInstanceStatusRequest>,
    ) -> Result<Response<GetMyWhatsappInstanceStatusResponse>, Status> {
        let id = req.get_ref().id;
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.whatsapp,
                "GetWhatsappInstanceStatus",
                serde_json::json!({ "id": id }),
            )
            .await?;

        Ok(Response::new(GetMyWhatsappInstanceStatusResponse {
            connection_state: corpo
                .get("connection_state")
                .and_then(|v| v.as_str())
                .unwrap_or("unknown")
                .to_string(),
            // Ausente quando já conectou (ou quando o provedor ainda não gerou).
            qr_code: corpo
                .get("qr_code")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string(),
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "CreateMyDepartamento", traceparent)
    )]
    async fn create_my_departamento(
        &self,
        req: Request<CreateMyDepartamentoRequest>,
    ) -> Result<Response<CreateMyDepartamentoResponse>, Status> {
        let inner = req.get_ref().clone();
        if inner.nome.trim().is_empty() {
            return Err(Status::invalid_argument("informe o nome do departamento"));
        }

        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "CreateDepartamento",
                serde_json::json!({
                    "nome": inner.nome.trim(),
                    "descricao": inner.descricao,
                }),
            )
            .await?;

        // O handler devolve o departamento na raiz do payload; o `get` aqui é
        // tolerância a um aninhamento futuro, não o caminho corrente.
        let dep = corpo.get("departamento").unwrap_or(&corpo);
        Ok(Response::new(CreateMyDepartamentoResponse {
            id: dep.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32,
            nome: dep
                .get("nome")
                .and_then(|v| v.as_str())
                .unwrap_or(inner.nome.trim())
                .to_string(),
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "SetMyBotPersona", traceparent)
    )]
    async fn set_my_bot_persona(
        &self,
        req: Request<SetMyBotPersonaRequest>,
    ) -> Result<Response<SetMyBotPersonaResponse>, Status> {
        let inner = req.get_ref().clone();

        // Só os dois campos entram no payload. O UPSERT do `data_postgres` faz
        // `COALESCE(EXCLUDED.campo, atual)`, e uma chave AUSENTE no JSON vira
        // NULL — que preserva o valor atual. Mandar o objeto inteiro com
        // strings vazias, ao contrário, apagaria a configuração de IA.
        let mut payload = serde_json::Map::new();
        if !inner.persona_bot.trim().is_empty() {
            payload.insert(
                "persona_bot".to_string(),
                serde_json::Value::String(inner.persona_bot.trim().to_string()),
            );
        }
        if !inner.bot_agent_name.trim().is_empty() {
            payload.insert(
                "bot_agent_name".to_string(),
                serde_json::Value::String(inner.bot_agent_name.trim().to_string()),
            );
        }
        if payload.is_empty() {
            return Err(Status::invalid_argument("informe a persona ou o nome"));
        }

        self.encaminhar_tenant(
            &req,
            &self.deps.pg,
            "UpdateTenantConfig",
            serde_json::Value::Object(payload),
        )
        .await?;

        Ok(Response::new(SetMyBotPersonaResponse { success: true }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "SetOnboardingProgress", traceparent)
    )]
    async fn set_onboarding_progress(
        &self,
        req: Request<SetOnboardingProgressRequest>,
    ) -> Result<Response<SetOnboardingProgressResponse>, Status> {
        let inner = *req.get_ref();
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "SetOnboardingProgress",
                serde_json::json!({
                    "passo": inner.passo,
                    "concluido": inner.concluido,
                }),
            )
            .await?;

        Ok(Response::new(SetOnboardingProgressResponse {
            passo: corpo.get("passo").and_then(|v| v.as_i64()).unwrap_or(0) as i32,
            concluido: corpo
                .get("concluido")
                .and_then(|v| v.as_bool())
                .unwrap_or(false),
        }))
    }

    /// Lê o progresso da configuração guiada do próprio tenant.
    ///
    /// É o que permite reabrir o app e voltar ao roteiro de onde parou.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "GetMyOnboardingProgress", traceparent)
    )]
    async fn get_my_onboarding_progress(
        &self,
        req: Request<GetMyOnboardingProgressRequest>,
    ) -> Result<Response<GetMyOnboardingProgressResponse>, Status> {
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "GetOnboardingProgress",
                serde_json::json!({}),
            )
            .await?;

        Ok(Response::new(GetMyOnboardingProgressResponse {
            passo: corpo.get("passo").and_then(|v| v.as_i64()).unwrap_or(0) as i32,
            concluido: corpo
                .get("concluido")
                .and_then(|v| v.as_bool())
                .unwrap_or(false),
            // Campo ausente resolve para "não pendente". A ausência só acontece
            // com `data_postgres` defasado, e nesse caso prender quem já pagou é
            // pior do que deixar passar quem não pagou: o `data_postgres` ainda
            // recusa as escritas do inadimplente, então o pior caso é um aviso
            // que não aparece — não um cliente trancado do lado de fora.
            pagamento_pendente: corpo
                .get("pagamento_pendente")
                .and_then(|v| v.as_bool())
                .unwrap_or(false),
            assinatura_status: corpo
                .get("assinatura_status")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string(),
            plano_nome: corpo
                .get("plano_nome")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string(),
            plano_id: corpo.get("plano_id").and_then(|v| v.as_i64()).unwrap_or(0) as i32,
        }))
    }

    /// Quita a assinatura **com sessão**, sem `signup_token`.
    ///
    /// O `ConfirmPayment` do wizard exige o token do cadastro, que morre quando a
    /// sessão expira. Quem passou por isso entrava no app e não tinha como pagar:
    /// esbarrava em "assinatura inadimplente" a cada cadastro, sem tela que
    /// resolvesse. Este é o caminho de volta.
    ///
    /// Reusa o **mesmo** registro de provedores e o mesmo resgate do wizard; a
    /// única diferença é a origem da identidade — claims, nunca o request.
    #[tracing::instrument(
        // `skip_all` obrigatório: a credencial (código do voucher) não pode
        // aparecer em span nem em log. É reutilizável enquanto tiver resgates.
        skip_all,
        fields(service = "runtime_api", rpc = "QuitarMinhaAssinatura", traceparent)
    )]
    async fn quitar_minha_assinatura(
        &self,
        req: Request<QuitarMinhaAssinaturaRequest>,
    ) -> Result<Response<QuitarMinhaAssinaturaResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        // Cobrança é assunto do dono. Um colaborador não vê nem resolve.
        //
        // Chegou da `dev` chamando `exigir_escopo_tenant_admin`, que a N13.3
        // removeu ao trocar o gate binário pelo mapa rota→escopo. O equivalente
        // exato é `SOMENTE_ADMIN`: lista vazia, satisfeita apenas por
        // `tenant:admin` ou pelo coringa do superusuário.
        exigir_escopo(&claims, crate::rbac::SOMENTE_ADMIN, "QuitarMinhaAssinatura")?;
        let traceparent = traceparent_do_metadata(&req);
        let ip = ip_do_metadata(&req);
        let user_agent = user_agent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("sessão sem tenant válido"))?;
        let r = req.into_inner();

        // Helper local: envelope de tenant já com as claims desta sessão. O
        // `encaminhar_tenant` não serve aqui porque reautentica pelo metadata do
        // request, e este método faz duas chamadas com a mesma sessão.
        let envelope_para = |metodo: &str, payload: serde_json::Value| Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: metodo.to_string(),
            payload: serde_json::to_vec(&payload).unwrap_or_default(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: claims.is_superuser,
            ..Default::default()
        };

        // 1. Estado atual. Serve para duas coisas: a guarda de idempotência e o
        //    `plan_id` que um gateway externo precisaria para cobrar.
        let resp = self
            .deps
            .pg
            .call(
                envelope_para(
                    "GetOnboardingProgress",
                    serde_json::json!({ "tenant_id": tenant_uuid.to_string() }),
                ),
                std::time::Duration::from_secs(5),
            )
            .await
            .map_err(|e| Status::internal(format!("Falha no serviço interno: {e}")))?;
        if resp.kind == MessageKind::Error as i32 {
            return Err(status_do_erro_interno(resp.error));
        }
        let progresso: serde_json::Value =
            serde_json::from_slice(&resp.payload).map_err(|e| Status::internal(e.to_string()))?;

        let status_atual = progresso
            .get("assinatura_status")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string();

        // 2. Já ativa: responde sucesso **sem tocar no provedor**. Dois cliques
        //    não podem consumir dois resgates do voucher — o `UPDATE ...
        //    RETURNING` do resgate resolve a corrida entre requisições
        //    simultâneas, mas não o caso de quem já está em dia e clica de novo.
        if status_atual == "ACTIVE" {
            return Ok(Response::new(QuitarMinhaAssinaturaResponse {
                confirmado: true,
                assinatura_status: status_atual,
                url_externa: String::new(),
                motivo: String::new(),
                erro_legivel: String::new(),
            }));
        }

        let plan_id = progresso
            .get("plano_id")
            .and_then(|v| v.as_i64())
            .unwrap_or(0) as i32;

        // 3. O provedor decide. Id desconhecido é erro de validação, nunca
        //    "escolhe qualquer um".
        let provedor = self
            .provedores
            .obter(&r.provedor)
            .ok_or_else(|| Status::invalid_argument("forma de pagamento indisponível"))?;

        let dados = application::pagamento::DadosCobranca {
            tenant_id: tenant_uuid,
            plan_id,
            email: String::new(),
            credencial: r.credencial,
            ip: ip.clone().unwrap_or_default(),
            traceparent: traceparent.clone(),
        };

        let intencao = provedor
            .iniciar(&dados)
            .await
            .map_err(|e| app_err_para_status(&e))?;

        match intencao {
            application::pagamento::IntencaoPagamento::Confirmada {
                plan_id,
                periodo_fim,
                referencia,
            } => {
                // 4. Pago: ativa. `ActivateSignup` é idempotente e não exige
                //    `signup_token` — só o `tenant_id`, que aqui vem das claims.
                let resp = self
                    .deps
                    .pg
                    .call(
                        envelope_para(
                            "ActivateSignup",
                            serde_json::json!({
                                "tenant_id": tenant_uuid.to_string(),
                                "plan_id": plan_id,
                                "periodo_fim": periodo_fim.to_rfc3339(),
                                "gateway": r.provedor,
                                "referencia": referencia,
                            }),
                        ),
                        std::time::Duration::from_secs(10),
                    )
                    .await
                    .map_err(|e| Status::internal(format!("Falha no serviço interno: {e}")))?;
                if resp.kind == MessageKind::Error as i32 {
                    return Err(status_do_erro_interno(resp.error));
                }

                // Auditoria do evento financeiro. **Sem a credencial**: o código
                // do voucher é reutilizável enquanto tiver resgates, e a trilha
                // é lida por mais gente do que o log.
                let mut bus = self.bus.clone();
                publicar_auditoria_borda(
                    &mut bus,
                    Some(tenant_uuid),
                    "INFO",
                    "assinatura.quitada",
                    "Assinatura quitada pelo dono, ja logado.".to_string(),
                    serde_json::json!({
                        "meio": r.provedor,
                        "plan_id": plan_id,
                        "periodo_fim": periodo_fim.to_rfc3339(),
                    }),
                    claims.sub.parse::<i32>().ok(),
                    &traceparent,
                    ip,
                    Some(user_agent),
                )
                .await;

                Ok(Response::new(QuitarMinhaAssinaturaResponse {
                    confirmado: true,
                    assinatura_status: "ACTIVE".to_string(),
                    url_externa: String::new(),
                    motivo: String::new(),
                    erro_legivel: String::new(),
                }))
            }
            // Gateway externo: o dono conclui fora do app e a ativação vem depois.
            application::pagamento::IntencaoPagamento::Redirect { url, .. } => {
                Ok(Response::new(QuitarMinhaAssinaturaResponse {
                    confirmado: false,
                    assinatura_status: status_atual,
                    url_externa: url,
                    motivo: String::new(),
                    erro_legivel: String::new(),
                }))
            }
            // Recusa é resposta de sucesso: a tela precisa da mensagem junto do
            // campo, não de um erro de RPC que vira snackbar e some.
            application::pagamento::IntencaoPagamento::Recusada { motivo, mensagem } => {
                Ok(Response::new(QuitarMinhaAssinaturaResponse {
                    confirmado: false,
                    assinatura_status: status_atual,
                    url_externa: String::new(),
                    motivo,
                    erro_legivel: mensagem,
                }))
            }
        }
    }

    // --- Treinamento da IA ---
    //
    // Métodos concretos, não só rotas no roteador de envelope: sem eles o
    // Flutter não alcança nada, ainda que o `data_postgres` responda.

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "CreateMyTreinamento", traceparent)
    )]
    async fn create_my_treinamento(
        &self,
        req: Request<CreateMyTreinamentoRequest>,
    ) -> Result<Response<MyTreinamentoResponse>, Status> {
        let inner = req.get_ref().clone();
        if inner.tag.trim().is_empty() || inner.grupo.trim().is_empty() {
            return Err(Status::invalid_argument("informe a tag e o grupo"));
        }
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "CreateTreinamento",
                serde_json::json!({
                    "tag": inner.tag.trim(),
                    "grupo": inner.grupo.trim(),
                    "conteudo": inner.conteudo,
                }),
            )
            .await?;

        Ok(Response::new(MyTreinamentoResponse {
            treinamento: Some(treinamento_do_json(&corpo)),
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListMyTreinamentos", traceparent)
    )]
    async fn list_my_treinamentos(
        &self,
        req: Request<ListMyTreinamentosRequest>,
    ) -> Result<Response<ListMyTreinamentosResponse>, Status> {
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "ListTreinamentos",
                serde_json::json!({}),
            )
            .await?;

        let treinamentos = corpo
            .get("treinamentos")
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter().map(treinamento_do_json).collect())
            .unwrap_or_default();

        Ok(Response::new(ListMyTreinamentosResponse { treinamentos }))
    }

    /// Ensaia uma pergunta pelo mesmo caminho de uma mensagem real.
    ///
    /// Embed → RAG (`QueryCompose`) → LLM, exatamente a sequência que o worker
    /// executa quando chega uma mensagem de WhatsApp. Reimplementar um caminho
    /// mais curto aqui faria o ensaio responder diferente do que o cliente
    /// receberia — e um ensaio que mente é pior que não ter ensaio.
    ///
    /// Nada é gravado: não há atendimento, contato nem mensagem. É por isso que
    /// `atendimento_id` vai vazio.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "TestarPergunta", traceparent)
    )]
    async fn testar_pergunta(
        &self,
        req: Request<TestarPerguntaRequest>,
    ) -> Result<Response<TestarPerguntaResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        // Testar a pergunta é exercitar a base de conhecimento; quem pode lê-la
        // pode testá-la. Antes exigia `tenant:admin`, o que deixava fora de
        // alcance justamente quem cuida do treinamento.
        exigir_escopo(&claims, &["treinamento:read"], "TestarPergunta")?;
        let traceparent = traceparent_do_metadata(&req);
        let pergunta = req.get_ref().pergunta.trim().to_string();

        if pergunta.is_empty() {
            return Err(Status::invalid_argument("escreva a pergunta a testar"));
        }

        // 1. Embedding da pergunta — sem ele não há o que comparar.
        let embed = self
            .ia
            .embed(
                ia_client::EmbedInput {
                    tenant_id: claims.tenant_id.clone(),
                    textos: vec![pergunta.clone()],
                },
                &traceparent,
            )
            .await
            .map_err(|e| Status::unavailable(format!("a IA não respondeu: {e}")))?;
        let vetor = embed.embeddings.into_iter().next().unwrap_or_default();
        if vetor.is_empty() {
            return Err(Status::unavailable(
                "a IA não gerou o vetor da pergunta; tente de novo",
            ));
        }

        // 2. RAG pelo mesmo RPC que o worker usa. Sem `distance_threshold`: o
        // data_postgres aplica o limiar efetivo do tenant, o mesmo da conversa
        // real. Um 0.3 fixo aqui fazia o ensaio não achar trecho nenhum
        // enquanto o cliente, no WhatsApp, recebia a base.
        let contexto = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "QueryCompose",
                serde_json::json!({
                    "query_embedding": vetor,
                    "chunk_top_k": 3,
                }),
            )
            .await?;

        let comportamento = contexto
            .get("comportamento")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string();
        let trechos: Vec<TrechoUsado> = contexto
            .get("documentos")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .map(|d| TrechoUsado {
                        conteudo: d
                            .get("conteudo")
                            .and_then(|c| c.as_str())
                            .unwrap_or_default()
                            .to_string(),
                        distancia: d.get("distancia").and_then(|c| c.as_f64()).unwrap_or(0.0),
                    })
                    .collect()
            })
            .unwrap_or_default();

        let mut partes: Vec<String> = Vec::new();
        if !comportamento.is_empty() {
            partes.push(comportamento.clone());
        }
        for trecho in &trechos {
            if !trecho.conteudo.is_empty() {
                partes.push(trecho.conteudo.clone());
            }
        }

        // 3. Setores de transferência, montados como o worker monta: sem eles
        // o prompt dizia "nenhum setor disponível" e o ensaio nunca mostrava
        // transferência. Best-effort, como no worker.
        let fluxos_disponiveis = match self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "ListarFluxosDoTenant",
                serde_json::json!({}),
            )
            .await
        {
            Ok(resp) => fluxos_para_o_responder(&resp),
            Err(e) => {
                tracing::warn!(erro = %e, "ListarFluxosDoTenant falhou; ensaio sem setores");
                Vec::new()
            }
        };

        // 4. Resposta. Sem histórico: o ensaio é de uma pergunta isolada, e
        // inventar uma conversa anterior mudaria o que a IA responderia.
        //
        // Plano ia-engine-jev: pelo motor do tenant, com os trechos separados
        // (o Jev julga cada um), o catálogo de intenções e o comportamento à
        // parte — do mesmo jeito que o worker manda na conversa real.
        let motor = self.motor_do_tenant(&claims.tenant_id, &traceparent).await;
        let ia = self.ia_do_motor(&motor);
        let trechos_ia: Vec<ia_client::client::TrechoInput> = contexto
            .get("documentos")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|d| {
                        Some(ia_client::client::TrechoInput {
                            id: d
                                .get("id")
                                .and_then(|v| v.as_i64())
                                .unwrap_or(0)
                                .to_string(),
                            conteudo: d.get("conteudo")?.as_str()?.to_string(),
                            distancia: d.get("distancia").and_then(|c| c.as_f64()).unwrap_or(0.0),
                        })
                    })
                    .collect()
            })
            .unwrap_or_default();
        let intents = if motor == "llm" {
            Vec::new()
        } else {
            match self
                .encaminhar_tenant(&req, &self.deps.pg, "ListIntents", serde_json::json!({}))
                .await
            {
                Ok(resp) => intents_do_catalogo(&resp),
                Err(e) => {
                    tracing::warn!(erro = %e, "ListIntents falhou; ensaio sem catálogo");
                    Vec::new()
                }
            }
        };
        let saida = ia
            .responder(
                ia_client::ResponderInput {
                    tenant_id: claims.tenant_id.clone(),
                    atendimento_id: String::new(),
                    mensagem: pergunta,
                    fluxos_disponiveis,
                    dados_treinamento: partes.join("\n\n"),
                    intents,
                    trechos: trechos_ia,
                    comportamento: comportamento.clone(),
                    ..Default::default()
                },
                &traceparent,
            )
            .await
            .map_err(|e| Status::unavailable(format!("a IA não respondeu: {e}")))?;

        Ok(Response::new(TestarPerguntaResponse {
            resposta: saida.resposta_texto,
            comportamento_aplicado: comportamento,
            trechos,
            confiabilidade: saida.confiabilidade,
            transferiria: saida.transferir_atendimento,
            fluxo_transferencia: saida.fluxo_transferencia,
            motor: if saida.motor.is_empty() {
                "llm".into()
            } else {
                saida.motor
            },
            modelo: saida.modelo,
            motivo_transferencia: saida.motivo_transferencia,
            sinais: saida
                .sinais
                .into_iter()
                .map(|s| q::SinalValor {
                    nome: s.nome,
                    valor: s.valor,
                    limiar: s.limiar,
                })
                .collect(),
            intencao_principal: saida.intencao_principal,
            confianca_intencao: saida.confianca_intencao,
            decisao: saida.decisao,
            trechos_aprovados: saida
                .trechos
                .into_iter()
                .filter(|t| t.aprovado)
                .map(|t| t.id)
                .collect(),
            ato: saida.ato,
            campos_perguntados: saida.campos_perguntados,
            escalada: saida.escalada,
            problemas: saida.problemas,
            modelo_llm: saida.modelo_llm,
            etapas: saida
                .etapas
                .into_iter()
                .map(|e| q::EtapaDoMotor {
                    etapa: e.etapa,
                    ms: e.ms,
                })
                .collect(),
        }))
    }

    // ------------------------------------------------------------------
    // Plano ia-engine-jev — transferência para atendente.
    // ------------------------------------------------------------------

    #[tracing::instrument(
        skip_all,
        fields(
            service = "runtime_api",
            rpc = "ListMyRegrasTransferencia",
            traceparent
        )
    )]
    async fn list_my_regras_transferencia(
        &self,
        req: Request<q::ListMyRegrasTransferenciaRequest>,
    ) -> Result<Response<q::ListMyRegrasTransferenciaResponse>, Status> {
        let val = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "ListRegrasTransferencia",
                serde_json::json!({}),
            )
            .await?;
        let regras = val
            .get("regras")
            .and_then(|v| v.as_array())
            .map(|a| a.iter().map(regra_do_json).collect())
            .unwrap_or_default();
        Ok(Response::new(q::ListMyRegrasTransferenciaResponse {
            regras,
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(
            service = "runtime_api",
            rpc = "SalvarMyRegraTransferencia",
            traceparent
        )
    )]
    async fn salvar_my_regra_transferencia(
        &self,
        req: Request<q::SalvarMyRegraTransferenciaRequest>,
    ) -> Result<Response<q::SalvarMyRegraTransferenciaResponse>, Status> {
        let inner = req.get_ref().clone();
        let regra = inner
            .regra
            .ok_or_else(|| Status::invalid_argument("envie a regra"))?;
        let mut payload = regra_para_json(&regra);
        if let Some(obj) = payload.as_object_mut() {
            obj.remove("id");
            if inner.id > 0 {
                obj.insert("id".into(), serde_json::json!(inner.id));
            }
            obj.insert("dry_run".into(), serde_json::json!(inner.dry_run));
        }
        let val = self
            .encaminhar_tenant(&req, &self.deps.pg, "SalvarRegraTransferencia", payload)
            .await?;
        Ok(Response::new(q::SalvarMyRegraTransferenciaResponse {
            regra: val.get("regra").map(regra_do_json),
            simulacao: val
                .get("simulacao")
                .and_then(|v| v.as_bool())
                .unwrap_or(false),
            campos_alterados: val
                .get("campos_alterados")
                .and_then(|v| v.as_array())
                .map(|a| {
                    a.iter()
                        .filter_map(|c| c.as_str().map(str::to_string))
                        .collect()
                })
                .unwrap_or_default(),
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(
            service = "runtime_api",
            rpc = "SetMyRegraTransferenciaAtiva",
            traceparent
        )
    )]
    async fn set_my_regra_transferencia_ativa(
        &self,
        req: Request<q::SetMyRegraTransferenciaAtivaRequest>,
    ) -> Result<Response<q::SetMyRegraTransferenciaAtivaResponse>, Status> {
        let inner = req.get_ref().clone();
        let val = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "SetRegraTransferenciaAtiva",
                serde_json::json!({
                    "id": inner.id,
                    "ativa": inner.ativa,
                    "confirmar": inner.confirmar,
                    "dry_run": inner.dry_run,
                }),
            )
            .await?;
        Ok(Response::new(q::SetMyRegraTransferenciaAtivaResponse {
            regra: val.get("regra").map(regra_do_json),
            simulacao: val
                .get("simulacao")
                .and_then(|v| v.as_bool())
                .unwrap_or(false),
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "GetMyConfigTransferencia", traceparent)
    )]
    async fn get_my_config_transferencia(
        &self,
        req: Request<q::GetMyConfigTransferenciaRequest>,
    ) -> Result<Response<q::ConfigTransferenciaResponse>, Status> {
        let val = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "GetConfigTransferencia",
                serde_json::json!({}),
            )
            .await?;
        Ok(Response::new(q::ConfigTransferenciaResponse {
            config: Some(config_transferencia_do_json(&val)),
            simulacao: false,
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "SetMySinaisTransferencia", traceparent)
    )]
    async fn set_my_sinais_transferencia(
        &self,
        req: Request<q::SetMySinaisTransferenciaRequest>,
    ) -> Result<Response<q::ConfigTransferenciaResponse>, Status> {
        let inner = req.get_ref().clone();
        let mut payload = serde_json::json!({ "dry_run": inner.dry_run });
        if !inner.sinais.is_empty() {
            payload["sinais"] = serde_json::Value::Array(
                inner
                    .sinais
                    .iter()
                    .map(|s| {
                        serde_json::json!({
                            "nome": s.nome,
                            "ativo": s.ativo,
                            "sensibilidade": s.sensibilidade,
                        })
                    })
                    .collect(),
            );
        }
        if inner.alterar_fluxo_padrao {
            payload["fluxo_padrao_id"] = serde_json::json!(inner.fluxo_padrao_id);
        }
        let val = self
            .encaminhar_tenant(&req, &self.deps.pg, "SetSinaisTransferencia", payload)
            .await?;
        Ok(Response::new(q::ConfigTransferenciaResponse {
            config: Some(config_transferencia_do_json(&val)),
            simulacao: val
                .get("simulacao")
                .and_then(|v| v.as_bool())
                .unwrap_or(false),
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListMyTransferencias", traceparent)
    )]
    async fn list_my_transferencias(
        &self,
        req: Request<q::ListMyTransferenciasRequest>,
    ) -> Result<Response<q::ListMyTransferenciasResponse>, Status> {
        let limite = req.get_ref().limite;
        let val = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "ListTransferencias",
                serde_json::json!({ "limite": limite }),
            )
            .await?;
        let transferencias = val
            .get("transferencias")
            .and_then(|v| v.as_array())
            .map(|a| a.iter().map(transferencia_do_json).collect())
            .unwrap_or_default();
        Ok(Response::new(q::ListMyTransferenciasResponse {
            transferencias,
        }))
    }

    /// Uma frase contra uma regra (salva ou do formulário). Pelo motor Jev,
    /// mesmo que o tenant ainda esteja no motor atual: é assim que ele testa
    /// antes de ligar. Nada é gravado — nem a frase, nem o resultado.
    #[tracing::instrument(
        skip_all,
        fields(
            service = "runtime_api",
            rpc = "TestarMyRegraTransferencia",
            traceparent
        )
    )]
    async fn testar_my_regra_transferencia(
        &self,
        req: Request<q::TestarMyRegraTransferenciaRequest>,
    ) -> Result<Response<q::TestarMyRegraTransferenciaResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        exigir_escopo(&claims, &["configuracoes:read"], "TestarRegraTransferencia")?;
        let traceparent = traceparent_do_metadata(&req);
        let inner = req.get_ref().clone();
        let frase = inner.frase.trim().to_string();
        if frase.is_empty() {
            return Err(Status::invalid_argument("escreva a frase a testar"));
        }
        let regra = if inner.regra_id > 0 {
            let val = self
                .encaminhar_tenant(
                    &req,
                    &self.deps.pg,
                    "GetRegraTransferencia",
                    serde_json::json!({ "id": inner.regra_id }),
                )
                .await?;
            val.get("regra").map(regra_do_json).unwrap_or_default()
        } else {
            inner
                .regra
                .ok_or_else(|| Status::invalid_argument("informe a regra ou o regra_id"))?
        };
        if regra.gatilho_tipo == "intencao" {
            return Err(Status::invalid_argument(
                "regra por intenção se testa no \"Testar pergunta\" do treinamento",
            ));
        }
        if regra.condicao.trim().is_empty() {
            return Err(Status::invalid_argument("a regra não tem condição"));
        }
        let Some(jev) = self.ia_jev.as_ref() else {
            return Err(Status::failed_precondition(
                "o motor Jev não está configurado neste ambiente",
            ));
        };
        let saida = jev
            .testar_regra_transferencia(
                ia_client::client::TestarRegraInput {
                    tenant_id: claims.tenant_id.clone(),
                    frase,
                    condicao: regra.condicao,
                    exemplos_sim: regra.exemplos_sim,
                    exemplos_nao: regra.exemplos_nao,
                    sensibilidade: regra.sensibilidade,
                },
                &traceparent,
            )
            .await
            .map_err(|e| Status::unavailable(format!("o Jev não respondeu: {e}")))?;
        Ok(Response::new(q::TestarMyRegraTransferenciaResponse {
            probabilidade: saida.probabilidade,
            limiar: saida.limiar,
            dispararia: saida.dispararia,
            modelo: saida.modelo,
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(
            service = "runtime_api",
            rpc = "GerarMySugestoesTransferencia",
            traceparent
        )
    )]
    async fn gerar_my_sugestoes_transferencia(
        &self,
        req: Request<q::GerarMySugestoesTransferenciaRequest>,
    ) -> Result<Response<q::GerarMySugestoesTransferenciaResponse>, Status> {
        let val = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "GerarSugestoesTransferencia",
                serde_json::json!({}),
            )
            .await?;
        Ok(Response::new(q::GerarMySugestoesTransferenciaResponse {
            criadas: val.get("criadas").and_then(|v| v.as_i64()).unwrap_or(0) as i32,
        }))
    }

    /// Superusuário: o motor das decisões da IA de um tenant.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "DefinirMotorTenant", traceparent)
    )]
    async fn definir_motor_tenant(
        &self,
        req: Request<q::DefinirMotorTenantRequest>,
    ) -> Result<Response<q::DefinirMotorTenantResponse>, Status> {
        let inner = req.get_ref().clone();
        let val = self
            .encaminhar_admin(
                &req,
                "DefinirMotorTenant",
                serde_json::json!({ "tenant_id": inner.tenant_id, "motor": inner.motor }),
            )
            .await?;
        let texto = |k: &str| {
            val.get(k)
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string()
        };
        Ok(Response::new(q::DefinirMotorTenantResponse {
            anterior: texto("anterior"),
            atual: texto("atual"),
        }))
    }

    /// B9 (N10 E6) — registra a avaliação de um ensaio, com a resposta correta.
    ///
    /// Escopo `treinamento:write` (via `encaminhar_tenant`): testar é leitura,
    /// mas avaliar alimenta a curadoria do que o bot vai dizer.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "RegistrarFeedbackTeste", traceparent)
    )]
    async fn registrar_feedback_teste(
        &self,
        req: Request<RegistrarFeedbackTesteRequest>,
    ) -> Result<Response<RegistrarFeedbackTesteResponse>, Status> {
        let inner = req.get_ref().clone();
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "RegistrarFeedbackTeste",
                serde_json::json!({
                    "pergunta": inner.pergunta,
                    "resposta_obtida": inner.resposta_obtida,
                    "resposta_correta": inner.resposta_correta,
                    "avaliacao": inner.avaliacao,
                    "comportamento_aplicado": inner.comportamento_aplicado,
                    "confiabilidade": inner.confiabilidade,
                }),
            )
            .await?;

        Ok(Response::new(RegistrarFeedbackTesteResponse {
            id: corpo.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32,
        }))
    }

    /// B9 (N10 E5) — passo 1 do treinamento por arquivo: confere formato,
    /// tamanho e quota, e devolve a URL de PUT direto no bucket.
    ///
    /// `skip_all`: o nome do arquivo pode citar cliente, e a URL é credencial.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "SolicitarUploadTreinamento", bytes = tracing::field::Empty, traceparent)
    )]
    async fn solicitar_upload_treinamento(
        &self,
        req: Request<SolicitarUploadTreinamentoRequest>,
    ) -> Result<Response<SolicitarUploadTreinamentoResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        exigir_escopo(
            &claims,
            &["treinamento:write"],
            "SolicitarUploadTreinamento",
        )?;
        let traceparent = traceparent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;
        let inner = req.into_inner();
        tracing::Span::current().record("bytes", inner.bytes);

        let Some(storage) = self.deps.storage.as_ref() else {
            return Err(Status::unavailable("errors.midia.storage_indisponivel"));
        };
        formato_de_treinamento(&inner.mimetype, &inner.nome_arquivo)
            .map_err(Status::invalid_argument)?;
        if inner.bytes <= 0 {
            return Err(Status::invalid_argument("arquivo vazio"));
        }
        let limite = infrastructure_storage::midia::CategoriaMidia::Documento.limite_bytes();
        if inner.bytes > limite {
            return Err(Status::invalid_argument(
                "arquivo acima do tamanho permitido",
            ));
        }

        let envelope = |metodo: &str, payload: serde_json::Value| Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: metodo.to_string(),
            payload: serde_json::to_vec(&payload).unwrap_or_default(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: claims.is_superuser,
            ..Default::default()
        };

        let autorizacao = self
            .deps
            .pg
            .call(
                envelope(
                    "AutorizarUploadTreinamento",
                    serde_json::json!({ "bytes": inner.bytes }),
                ),
                std::time::Duration::from_secs(5),
            )
            .await
            .map_err(|e| Status::internal(format!("Falha no serviço interno: {e}")))?;
        if autorizacao.kind == MessageKind::Error as i32 {
            let msg = autorizacao.error.map(|e| e.message).unwrap_or_default();
            return Err(Status::failed_precondition(msg));
        }
        let corpo: serde_json::Value = serde_json::from_slice(&autorizacao.payload)
            .map_err(|e| Status::internal(e.to_string()))?;
        let chave = corpo
            .get("chave")
            .and_then(|v| v.as_str())
            .ok_or_else(|| Status::internal("autorização de upload sem chave"))?
            .to_string();

        let presign = storage
            .call(
                envelope(
                    "PresignUpload",
                    serde_json::json!({ "file_name": chave, "content_type": inner.mimetype }),
                ),
                std::time::Duration::from_secs(5),
            )
            .await
            .map_err(|e| Status::internal(format!("Falha no serviço de storage: {e}")))?;
        if presign.kind == MessageKind::Error as i32 {
            tracing::warn!("falha ao assinar upload de arquivo de treinamento");
            return Err(Status::internal("errors.midia.presign_falhou"));
        }
        let corpo_presign: serde_json::Value = serde_json::from_slice(&presign.payload)
            .map_err(|e| Status::internal(e.to_string()))?;

        Ok(Response::new(SolicitarUploadTreinamentoResponse {
            url_upload: corpo_presign
                .get("url")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string(),
            chave,
            content_type: inner.mimetype,
            expira_em_segundos: corpo_presign
                .get("expires_in")
                .and_then(|v| v.as_i64())
                .unwrap_or(900),
        }))
    }

    /// B9 (N10 E5) — passo 3: o arquivo subiu. Confere o **conteúdo** no bucket
    /// (a validação que vale) e cria o treinamento com a extração pendente.
    #[tracing::instrument(
        skip_all,
        fields(
            service = "runtime_api",
            rpc = "CreateMyTreinamentoComArquivo",
            traceparent
        )
    )]
    async fn create_my_treinamento_com_arquivo(
        &self,
        req: Request<CreateMyTreinamentoComArquivoRequest>,
    ) -> Result<Response<MyTreinamentoResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        exigir_escopo(
            &claims,
            &["treinamento:write"],
            "CreateMyTreinamentoComArquivo",
        )?;
        let traceparent = traceparent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;
        let inner = req.into_inner();
        if inner.tag.trim().is_empty() || inner.grupo.trim().is_empty() {
            return Err(Status::invalid_argument("informe a tag e o grupo"));
        }
        formato_de_treinamento(&inner.mimetype, &inner.nome_arquivo)
            .map_err(Status::invalid_argument)?;
        let Some(storage) = self.deps.storage.as_ref() else {
            return Err(Status::unavailable("errors.midia.storage_indisponivel"));
        };

        let envelope = |metodo: &str, payload: serde_json::Value| Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: metodo.to_string(),
            payload: serde_json::to_vec(&payload).unwrap_or_default(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: claims.is_superuser,
            ..Default::default()
        };

        let inspecao = storage
            .call(
                envelope(
                    "InspecionarMidia",
                    serde_json::json!({ "file_name": inner.chave, "mimetype": inner.mimetype }),
                ),
                std::time::Duration::from_secs(10),
            )
            .await
            .map_err(|e| Status::internal(format!("Falha no serviço de storage: {e}")))?;
        if inspecao.kind == MessageKind::Error as i32 {
            let msg = inspecao.error.map(|e| e.message).unwrap_or_default();
            return Err(Status::failed_precondition(msg));
        }
        let veredito: serde_json::Value = serde_json::from_slice(&inspecao.payload)
            .map_err(|e| Status::internal(e.to_string()))?;
        if veredito.get("ok").and_then(|v| v.as_bool()) != Some(true) {
            let motivo = veredito
                .get("motivo")
                .and_then(|v| v.as_str())
                .unwrap_or("arquivo recusada na conferência")
                .to_string();
            return Err(Status::invalid_argument(motivo));
        }
        let bytes = veredito.get("bytes").and_then(|v| v.as_i64()).unwrap_or(0);

        let resp = self
            .deps
            .pg
            .call(
                envelope(
                    "CriarTreinamentoComArquivo",
                    serde_json::json!({
                        "tag": inner.tag.trim(),
                        "grupo": inner.grupo.trim(),
                        "chave": inner.chave,
                        "nome_arquivo": inner.nome_arquivo,
                        "mimetype": inner.mimetype,
                        "bytes": bytes,
                    }),
                ),
                std::time::Duration::from_secs(5),
            )
            .await
            .map_err(|e| Status::internal(format!("Falha no serviço interno: {e}")))?;
        if resp.kind == MessageKind::Error as i32 {
            return Err(status_do_erro_interno(resp.error));
        }
        let corpo: serde_json::Value =
            serde_json::from_slice(&resp.payload).map_err(|e| Status::internal(e.to_string()))?;

        Ok(Response::new(MyTreinamentoResponse {
            treinamento: Some(treinamento_do_json(&corpo)),
        }))
    }

    // --- B10 (N11 E5): clientes (PJ/PF) ---

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListMyClientes", traceparent)
    )]
    async fn list_my_clientes(
        &self,
        req: Request<ListMyClientesRequest>,
    ) -> Result<Response<ListMyClientesResponse>, Status> {
        let inner = req.get_ref().clone();
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "ListClientes",
                serde_json::json!({
                    "busca": inner.busca,
                    "incluir_inativos": inner.incluir_inativos,
                    "limite": if inner.limite > 0 { inner.limite } else { 50 },
                }),
            )
            .await?;
        let clientes = corpo
            .get("clientes")
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter().map(cliente_do_json).collect())
            .unwrap_or_default();
        Ok(Response::new(ListMyClientesResponse { clientes }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "CreateMyCliente", traceparent)
    )]
    async fn create_my_cliente(
        &self,
        req: Request<CreateMyClienteRequest>,
    ) -> Result<Response<MyClienteResponse>, Status> {
        let dados = req.get_ref().dados.clone().unwrap_or_default();
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "CreateCliente",
                dados_cliente_para_json(&dados),
            )
            .await?;
        Ok(Response::new(MyClienteResponse {
            cliente: Some(cliente_do_json(&corpo)),
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "UpdateMyCliente", traceparent)
    )]
    async fn update_my_cliente(
        &self,
        req: Request<UpdateMyClienteRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let inner = req.get_ref().clone();
        let mut payload = dados_cliente_para_json(&inner.dados.unwrap_or_default());
        payload["id"] = serde_json::json!(inner.id);
        self.encaminhar_tenant(&req, &self.deps.pg, "UpdateCliente", payload)
            .await?;
        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "DefinirMyClienteAtivo", traceparent)
    )]
    async fn definir_my_cliente_ativo(
        &self,
        req: Request<DefinirMyClienteAtivoRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let inner = *req.get_ref();
        self.encaminhar_tenant(
            &req,
            &self.deps.pg,
            "DefinirClienteAtivo",
            serde_json::json!({ "id": inner.id, "ativo": inner.ativo }),
        )
        .await?;
        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListMyContatosDoCliente", traceparent)
    )]
    async fn list_my_contatos_do_cliente(
        &self,
        req: Request<MyClienteIdRequest>,
    ) -> Result<Response<ListMyContatosDoClienteResponse>, Status> {
        let id = req.get_ref().id;
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "ListContatosDoCliente",
                serde_json::json!({ "id": id }),
            )
            .await?;
        let contatos = corpo
            .get("contatos")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .map(|c| ContatoDoCliente {
                        id: c.get("id").and_then(|x| x.as_i64()).unwrap_or(0) as i32,
                        nome: c
                            .get("nome")
                            .and_then(|x| x.as_str())
                            .unwrap_or_default()
                            .to_string(),
                        telefone: c
                            .get("telefone")
                            .and_then(|x| x.as_str())
                            .unwrap_or_default()
                            .to_string(),
                    })
                    .collect()
            })
            .unwrap_or_default();
        Ok(Response::new(ListMyContatosDoClienteResponse { contatos }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "VincularMyContatoCliente", traceparent)
    )]
    async fn vincular_my_contato_cliente(
        &self,
        req: Request<VincularMyContatoClienteRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let inner = *req.get_ref();
        self.encaminhar_tenant(
            &req,
            &self.deps.pg,
            "VincularContatoCliente",
            serde_json::json!({
                "cliente_id": inner.cliente_id,
                "contato_id": inner.contato_id,
                "vincular": inner.vincular,
            }),
        )
        .await?;
        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    // --- Curadoria de intenções ---

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListMyIntents", traceparent)
    )]
    async fn list_my_intents(
        &self,
        req: Request<ListMyIntentsRequest>,
    ) -> Result<Response<ListMyIntentsResponse>, Status> {
        let corpo = self
            .encaminhar_tenant(&req, &self.deps.pg, "ListIntents", serde_json::json!({}))
            .await?;

        let intents = corpo
            .get("intents")
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter().map(intent_do_json).collect())
            .unwrap_or_default();

        Ok(Response::new(ListMyIntentsResponse { intents }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "CreateMyIntent", traceparent)
    )]
    async fn create_my_intent(
        &self,
        req: Request<MyIntentDados>,
    ) -> Result<Response<MyIntentResponse>, Status> {
        let inner = req.get_ref().clone();
        validar_dados_intent(&inner)?;

        let corpo = self
            .encaminhar_tenant(&req, &self.deps.pg, "CreateIntent", payload_intent(&inner))
            .await?;

        Ok(Response::new(MyIntentResponse {
            intent: Some(intent_do_json(&corpo)),
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "UpdateMyIntent", traceparent)
    )]
    async fn update_my_intent(
        &self,
        req: Request<UpdateMyIntentRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let inner = req.get_ref().clone();
        let dados = inner
            .dados
            .clone()
            .ok_or_else(|| Status::invalid_argument("informe os dados da intenção"))?;
        validar_dados_intent(&dados)?;

        let mut payload = payload_intent(&dados);
        payload["id"] = serde_json::json!(inner.id);
        self.encaminhar_tenant(&req, &self.deps.pg, "UpdateIntent", payload)
            .await?;

        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "RemoveMyIntent", traceparent)
    )]
    async fn remove_my_intent(
        &self,
        req: Request<MyIntentIdRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let id = req.get_ref().id;
        self.encaminhar_tenant(
            &req,
            &self.deps.pg,
            "RemoveIntent",
            serde_json::json!({ "id": id }),
        )
        .await?;

        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "GetMyTreinamento", traceparent)
    )]
    async fn get_my_treinamento(
        &self,
        req: Request<GetMyTreinamentoRequest>,
    ) -> Result<Response<MyTreinamentoResponse>, Status> {
        let id = req.get_ref().id;
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "GetTreinamento",
                serde_json::json!({ "id": id }),
            )
            .await?;

        Ok(Response::new(MyTreinamentoResponse {
            treinamento: Some(treinamento_do_json(&corpo)),
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "FinalizarMyTreinamento", traceparent)
    )]
    async fn finalizar_my_treinamento(
        &self,
        req: Request<FinalizarMyTreinamentoRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let inner = req.get_ref().clone();
        if inner.conteudo.trim().is_empty() {
            return Err(Status::invalid_argument("o conteúdo revisado está vazio"));
        }
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "FinalizarTreinamento",
                serde_json::json!({ "id": inner.id, "conteudo": inner.conteudo }),
            )
            .await?;

        Ok(Response::new(SimpleOkResponse {
            sucesso: corpo
                .get("sucesso")
                .and_then(|v| v.as_bool())
                .unwrap_or(false),
        }))
    }

    // --- Departamentos e atendentes ---

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListMyDepartamentos", traceparent)
    )]
    async fn list_my_departamentos(
        &self,
        req: Request<ListMyDepartamentosRequest>,
    ) -> Result<Response<ListMyDepartamentosResponse>, Status> {
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "ListDepartamentos",
                serde_json::json!({}),
            )
            .await?;

        let departamentos = corpo
            .get("departamentos")
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter().map(departamento_do_json).collect())
            .unwrap_or_default();

        Ok(Response::new(ListMyDepartamentosResponse { departamentos }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "UpdateMyDepartamento", traceparent)
    )]
    async fn update_my_departamento(
        &self,
        req: Request<UpdateMyDepartamentoRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let inner = req.get_ref().clone();
        if inner.nome.trim().is_empty() {
            return Err(Status::invalid_argument("informe o nome do departamento"));
        }
        self.encaminhar_tenant(
            &req,
            &self.deps.pg,
            "UpdateDepartamento",
            serde_json::json!({
                "id": inner.id,
                "nome": inner.nome.trim(),
                "descricao": inner.descricao,
                "ativo": inner.ativo,
            }),
        )
        .await?;

        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "DesativarMyDepartamento", traceparent)
    )]
    async fn desativar_my_departamento(
        &self,
        req: Request<MyDepartamentoIdRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let id = req.get_ref().id;
        self.encaminhar_tenant(
            &req,
            &self.deps.pg,
            "DesativarDepartamento",
            serde_json::json!({ "id": id }),
        )
        .await?;

        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListMyAtendentes", traceparent)
    )]
    async fn list_my_atendentes(
        &self,
        req: Request<ListMyAtendentesRequest>,
    ) -> Result<Response<ListMyAtendentesResponse>, Status> {
        let corpo = self
            .encaminhar_tenant(&req, &self.deps.pg, "ListAtendentes", serde_json::json!({}))
            .await?;

        let atendentes = corpo
            .get("atendentes")
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter().map(atendente_do_json).collect())
            .unwrap_or_default();

        Ok(Response::new(ListMyAtendentesResponse { atendentes }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "GetMyPainel", traceparent)
    )]
    async fn get_my_painel(
        &self,
        req: Request<GetMyPainelRequest>,
    ) -> Result<Response<GetMyPainelResponse>, Status> {
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "GetPainelTenant",
                serde_json::json!({}),
            )
            .await?;

        let n = |chave: &str| corpo.get(chave).and_then(|v| v.as_i64()).unwrap_or(0) as i32;

        Ok(Response::new(GetMyPainelResponse {
            em_andamento: n("em_andamento"),
            aguardando: n("aguardando"),
            mensagens_24h: n("mensagens_24h"),
            conexoes_ativas: n("conexoes_ativas"),
            conexoes_total: n("conexoes_total"),
            departamentos: n("departamentos"),
            treinamentos_ativos: n("treinamentos_ativos"),
            // P6 — ausente (painel antigo) vale como "sem medida", não zero.
            primeira_resposta_mediana_s: corpo
                .get("primeira_resposta_mediana_s")
                .and_then(|v| v.as_i64())
                .unwrap_or(-1) as i32,
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListMyContatos", traceparent)
    )]
    async fn list_my_contatos(
        &self,
        req: Request<ListMyContatosRequest>,
    ) -> Result<Response<ListMyContatosResponse>, Status> {
        let inner = req.get_ref().clone();
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "ListContatos",
                serde_json::json!({
                    "busca": inner.busca,
                    // 0 no proto3 significa "não informado": o servidor decide.
                    "limite": if inner.limite > 0 { inner.limite } else { 50 },
                }),
            )
            .await?;

        let contatos = corpo
            .get("contatos")
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter().map(contato_do_json).collect())
            .unwrap_or_default();

        Ok(Response::new(ListMyContatosResponse { contatos }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "CreateMyContato", traceparent)
    )]
    async fn create_my_contato(
        &self,
        req: Request<CreateMyContatoRequest>,
    ) -> Result<Response<MyContatoResponse>, Status> {
        let inner = req.get_ref().clone();
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "CreateContato",
                serde_json::json!({
                    "telefone": inner.telefone,
                    "nome_contato": inner.nome_contato,
                    "email": inner.email,
                }),
            )
            .await?;

        // O corpo é o contato inteiro, não um campo dentro dele: a resposta
        // devolve o telefone JÁ normalizado, e é isso que a tela mostra — quem
        // digitou "(11) 9..." precisa ver em que número o cadastro ficou.
        Ok(Response::new(MyContatoResponse {
            contato: Some(contato_do_json(&corpo)),
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "UpdateMyContato", traceparent)
    )]
    async fn update_my_contato(
        &self,
        req: Request<UpdateMyContatoRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let inner = req.get_ref().clone();
        // Telefone vazio não viaja: no `data_postgres` campo ausente é "não
        // mexe", e mandar string vazia pediria para apagar o número.
        let mut payload = serde_json::json!({
            "id": inner.id,
            "nome_contato": inner.nome_contato,
            "email": inner.email,
        });
        if !inner.telefone.trim().is_empty() {
            payload["telefone"] = serde_json::Value::String(inner.telefone.clone());
        }

        self.encaminhar_tenant(&req, &self.deps.pg, "UpdateContato", payload)
            .await?;
        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "DefinirMyContatoAtivo", traceparent)
    )]
    async fn definir_my_contato_ativo(
        &self,
        req: Request<DefinirMyContatoAtivoRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let inner = *req.get_ref();
        self.encaminhar_tenant(
            &req,
            &self.deps.pg,
            "DefinirContatoAtivo",
            serde_json::json!({ "id": inner.id, "ativo": inner.ativo }),
        )
        .await?;
        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ExcluirMyItem", traceparent)
    )]
    async fn excluir_my_item(
        &self,
        req: Request<ExcluirMyItemRequest>,
    ) -> Result<Response<ExcluirMyItemResponse>, Status> {
        let inner = req.get_ref().clone();
        if inner.tipo == "conexao" {
            // A conexão é apagada no provedor antes de ser marcada: o caminho
            // é o DeleteMyWhatsappInstance, e não este.
            return Err(Status::invalid_argument(
                "conexão se exclui por DeleteMyWhatsappInstance",
            ));
        }
        let val = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "ExcluirItem",
                serde_json::json!({
                    "tipo": inner.tipo,
                    "id": inner.id,
                    "confirmar": inner.confirmar,
                    "dry_run": inner.dry_run,
                }),
            )
            .await?;
        let atendimentos_excluidos = val
            .get("atendimentos_excluidos")
            .and_then(|v| v.as_array())
            .map(|a| a.iter().filter_map(|v| v.as_i64()).collect())
            .unwrap_or_default();
        let texto = |k: &str| {
            val.get(k)
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string()
        };
        Ok(Response::new(ExcluirMyItemResponse {
            sucesso: true,
            atendimentos_excluidos,
            simulacao: val
                .get("simulacao")
                .and_then(|v| v.as_bool())
                .unwrap_or(false),
            rotulo: texto("rotulo"),
            conversas: val.get("conversas").and_then(|v| v.as_i64()).unwrap_or(0),
            em_uso: texto("em_uso"),
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "DefinirMyItemAtivo", traceparent)
    )]
    async fn definir_my_item_ativo(
        &self,
        req: Request<DefinirMyItemAtivoRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let inner = req.get_ref().clone();
        self.encaminhar_tenant(
            &req,
            &self.deps.pg,
            "DefinirItemAtivo",
            serde_json::json!({ "tipo": inner.tipo, "id": inner.id, "ativo": inner.ativo }),
        )
        .await?;
        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListMyExcluidos", traceparent)
    )]
    async fn list_my_excluidos(
        &self,
        req: Request<ListMyExcluidosRequest>,
    ) -> Result<Response<ListMyExcluidosResponse>, Status> {
        let inner = req.get_ref().clone();
        let val = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "ListarExcluidos",
                serde_json::json!({ "tipo": inner.tipo, "limite": inner.limite }),
            )
            .await?;
        let itens = val
            .get("itens")
            .and_then(|v| v.as_array())
            .map(|a| {
                a.iter()
                    .map(|i| ItemExcluido {
                        tipo: i
                            .get("tipo")
                            .and_then(|v| v.as_str())
                            .unwrap_or_default()
                            .to_string(),
                        id: i.get("id").and_then(|v| v.as_i64()).unwrap_or(0),
                        rotulo: i
                            .get("rotulo")
                            .and_then(|v| v.as_str())
                            .unwrap_or_default()
                            .to_string(),
                        excluido_em: millis_do_item(i, "excluido_em").unwrap_or(0),
                        excluido_por: i
                            .get("excluido_por")
                            .and_then(|v| v.as_str())
                            .unwrap_or_default()
                            .to_string(),
                    })
                    .collect()
            })
            .unwrap_or_default();
        Ok(Response::new(ListMyExcluidosResponse { itens }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "CreateMyAtendente", traceparent)
    )]
    async fn create_my_atendente(
        &self,
        req: Request<CreateMyAtendenteRequest>,
    ) -> Result<Response<MyAtendenteResponse>, Status> {
        let inner = req.get_ref().clone();
        if inner.nome.trim().is_empty() {
            return Err(Status::invalid_argument("informe o nome do atendente"));
        }
        if inner.email.trim().is_empty() {
            return Err(Status::invalid_argument("informe o e-mail do atendente"));
        }
        if inner.fluxo_id <= 0 {
            return Err(Status::invalid_argument(
                "escolha o fluxo em que este atendente trabalha",
            ));
        }

        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "CreateAtendente",
                serde_json::json!({
                    "nome": inner.nome.trim(),
                    "email": inner.email.trim(),
                    "cargo": inner.cargo.trim(),
                    "fluxo_id": inner.fluxo_id,
                    "departamento_id": inner.departamento_id,
                }),
            )
            .await?;

        Ok(Response::new(MyAtendenteResponse {
            atendente: Some(atendente_do_json(&corpo)),
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "UpdateMyAtendente", traceparent)
    )]
    async fn update_my_atendente(
        &self,
        req: Request<UpdateMyAtendenteRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let inner = req.get_ref().clone();
        if inner.nome.trim().is_empty() {
            return Err(Status::invalid_argument("informe o nome do atendente"));
        }
        if inner.fluxo_id <= 0 {
            return Err(Status::invalid_argument(
                "escolha o fluxo em que este atendente trabalha",
            ));
        }
        self.encaminhar_tenant(
            &req,
            &self.deps.pg,
            "UpdateAtendente",
            serde_json::json!({
                "id": inner.id,
                "nome": inner.nome.trim(),
                "cargo": inner.cargo.trim(),
                "departamento_id": inner.departamento_id,
                "fluxo_id": inner.fluxo_id,
                "ativo": inner.ativo,
                "disponivel": inner.disponivel,
                "max_atendimentos_simultaneos": inner.max_atendimentos_simultaneos,
            }),
        )
        .await?;

        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "DesativarMyAtendente", traceparent)
    )]
    async fn desativar_my_atendente(
        &self,
        req: Request<MyAtendenteIdRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let id = req.get_ref().id;
        self.encaminhar_tenant(
            &req,
            &self.deps.pg,
            "DesativarAtendente",
            serde_json::json!({ "id": id }),
        )
        .await?;

        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    // --- Fluxos de atendimento e etapas ---

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListMyFluxos", traceparent)
    )]
    /// N9 E13 — o catálogo de campos do cartão.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListMyCampos", traceparent)
    )]
    async fn list_my_campos(
        &self,
        req: Request<ListMyCamposRequest>,
    ) -> Result<Response<ListMyCamposResponse>, Status> {
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "ListCamposPersonalizados",
                serde_json::json!({}),
            )
            .await?;

        let campos = corpo
            .get("campos")
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter().map(campo_do_json).collect())
            .unwrap_or_default();

        Ok(Response::new(ListMyCamposResponse { campos }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "CreateMyCampo", traceparent)
    )]
    async fn create_my_campo(
        &self,
        req: Request<CreateMyCampoRequest>,
    ) -> Result<Response<MyCampoResponse>, Status> {
        let inner = req.get_ref().clone();
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "CreateCampoPersonalizado",
                serde_json::json!({
                    "nome": inner.nome,
                    "descricao": inner.descricao,
                    "escopo": inner.escopo,
                    "fluxo_id": inner.fluxo_id,
                    "tipo": inner.tipo,
                    "opcoes": opcoes_para_json(&inner.opcoes),
                    "obrigatorio": inner.obrigatorio,
                    "extrair_automaticamente": inner.extrair_automaticamente,
                    "extrair_hint": inner.extrair_hint,
                    "mostrar_no_card": inner.mostrar_no_card,
                    "ordem": inner.ordem,
                }),
            )
            .await?;

        Ok(Response::new(MyCampoResponse {
            campo: corpo.get("campo").map(campo_do_json),
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "UpdateMyCampo", traceparent)
    )]
    async fn update_my_campo(
        &self,
        req: Request<UpdateMyCampoRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let inner = req.get_ref().clone();
        self.encaminhar_tenant(
            &req,
            &self.deps.pg,
            "UpdateCampoPersonalizado",
            serde_json::json!({
                "id": inner.id,
                "nome": inner.nome,
                "descricao": inner.descricao,
                "tipo": inner.tipo,
                "opcoes": opcoes_para_json(&inner.opcoes),
                "obrigatorio": inner.obrigatorio,
                "extrair_automaticamente": inner.extrair_automaticamente,
                "extrair_hint": inner.extrair_hint,
                "mostrar_no_card": inner.mostrar_no_card,
                "ordem": inner.ordem,
                "ativo": inner.ativo,
            }),
        )
        .await?;
        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "DesativarMyCampo", traceparent)
    )]
    async fn desativar_my_campo(
        &self,
        req: Request<MyCampoIdRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let id = req.get_ref().id;
        self.encaminhar_tenant(
            &req,
            &self.deps.pg,
            "DesativarCampoPersonalizado",
            serde_json::json!({ "id": id }),
        )
        .await?;
        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    /// Preenchimento manual de um campo na ficha do atendimento.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "SetMyValorCampo", traceparent)
    )]
    async fn set_my_valor_campo(
        &self,
        req: Request<SetMyValorCampoRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let inner = req.get_ref().clone();
        // O valor chega como texto JSON e vai como JSON: o tipo real mora no
        // catálogo, e reinterpretar aqui criaria uma segunda opinião sobre a
        // mesma coisa. `null` é apagamento deliberado e passa intacto.
        let valor: serde_json::Value = serde_json::from_str(&inner.valor_json)
            .unwrap_or(serde_json::Value::String(inner.valor_json.clone()));

        self.encaminhar_tenant(
            &req,
            &self.deps.pg,
            "SetValorCampo",
            serde_json::json!({
                "atendimento_id": inner.atendimento_id,
                "campo_id": inner.campo_id,
                "valor": valor,
            }),
        )
        .await?;
        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    async fn list_my_fluxos(
        &self,
        req: Request<ListMyFluxosRequest>,
    ) -> Result<Response<ListMyFluxosResponse>, Status> {
        let corpo = self
            .encaminhar_tenant(&req, &self.deps.pg, "ListFluxos", serde_json::json!({}))
            .await?;

        let fluxos = corpo
            .get("fluxos")
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter().map(fluxo_do_json).collect())
            .unwrap_or_default();

        Ok(Response::new(ListMyFluxosResponse { fluxos }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "CreateMyFluxo", traceparent)
    )]
    async fn create_my_fluxo(
        &self,
        req: Request<CreateMyFluxoRequest>,
    ) -> Result<Response<MyFluxoResponse>, Status> {
        let inner = req.get_ref().clone();
        if inner.nome.trim().is_empty() {
            return Err(Status::invalid_argument("informe o nome do fluxo"));
        }
        if inner.departamento_id <= 0 {
            return Err(Status::invalid_argument("escolha o departamento do fluxo"));
        }

        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "CreateFluxo",
                serde_json::json!({
                    "departamento_id": inner.departamento_id,
                    "nome": inner.nome.trim(),
                    "descricao": inner.descricao,
                }),
            )
            .await?;

        Ok(Response::new(MyFluxoResponse {
            fluxo: Some(fluxo_do_json(&corpo)),
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "UpdateMyFluxo", traceparent)
    )]
    async fn update_my_fluxo(
        &self,
        req: Request<UpdateMyFluxoRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let inner = req.get_ref().clone();
        if inner.nome.trim().is_empty() {
            return Err(Status::invalid_argument("informe o nome do fluxo"));
        }
        self.encaminhar_tenant(
            &req,
            &self.deps.pg,
            "UpdateFluxo",
            serde_json::json!({
                "id": inner.id,
                "nome": inner.nome.trim(),
                "descricao": inner.descricao,
                "ativo": inner.ativo,
            }),
        )
        .await?;

        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "DesativarMyFluxo", traceparent)
    )]
    async fn desativar_my_fluxo(
        &self,
        req: Request<MyFluxoIdRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let id = req.get_ref().id;
        self.encaminhar_tenant(
            &req,
            &self.deps.pg,
            "DesativarFluxo",
            serde_json::json!({ "id": id }),
        )
        .await?;

        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListMyEtapasFluxo", traceparent)
    )]
    async fn list_my_etapas_fluxo(
        &self,
        req: Request<MyFluxoIdRequest>,
    ) -> Result<Response<ListMyEtapasFluxoResponse>, Status> {
        let fluxo_id = req.get_ref().id;
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "ListEtapasFluxo",
                serde_json::json!({ "fluxo_id": fluxo_id }),
            )
            .await?;

        let etapas = corpo
            .get("etapas")
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter().map(etapa_do_json).collect())
            .unwrap_or_default();

        Ok(Response::new(ListMyEtapasFluxoResponse { etapas }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "CreateMyEtapaFluxo", traceparent)
    )]
    async fn create_my_etapa_fluxo(
        &self,
        req: Request<CreateMyEtapaFluxoRequest>,
    ) -> Result<Response<MyEtapaFluxoResponse>, Status> {
        let inner = req.get_ref().clone();
        if inner.nome.trim().is_empty() {
            return Err(Status::invalid_argument("informe o nome da etapa"));
        }

        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "CreateEtapaFluxo",
                serde_json::json!({
                    "fluxo_id": inner.fluxo_id,
                    "nome": inner.nome.trim(),
                    "tipo_etapa": inner.tipo_etapa,
                    "cor": inner.cor,
                }),
            )
            .await?;

        Ok(Response::new(MyEtapaFluxoResponse {
            etapa: Some(etapa_do_json(&corpo)),
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "UpdateMyEtapaFluxo", traceparent)
    )]
    async fn update_my_etapa_fluxo(
        &self,
        req: Request<UpdateMyEtapaFluxoRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let inner = req.get_ref().clone();
        if inner.nome.trim().is_empty() {
            return Err(Status::invalid_argument("informe o nome da etapa"));
        }
        self.encaminhar_tenant(
            &req,
            &self.deps.pg,
            "UpdateEtapaFluxo",
            serde_json::json!({
                "id": inner.id,
                "nome": inner.nome.trim(),
                "descricao": inner.descricao,
                "cor": inner.cor,
                "tipo_etapa": inner.tipo_etapa,
            }),
        )
        .await?;

        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "DesativarMyEtapaFluxo", traceparent)
    )]
    async fn desativar_my_etapa_fluxo(
        &self,
        req: Request<MyEtapaFluxoIdRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let id = req.get_ref().id;
        self.encaminhar_tenant(
            &req,
            &self.deps.pg,
            "DesativarEtapaFluxo",
            serde_json::json!({ "id": id }),
        )
        .await?;

        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "MoverMyEtapaFluxo", traceparent)
    )]
    async fn mover_my_etapa_fluxo(
        &self,
        req: Request<MoverMyEtapaFluxoRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let inner = *req.get_ref();
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "MoverEtapaFluxo",
                serde_json::json!({ "id": inner.id, "para_cima": inner.para_cima }),
            )
            .await?;

        // `sucesso: false` aqui é "já está na ponta", não falha: a tela só não
        // muda, e transformar isso em erro faria a última coluna parecer quebrada.
        Ok(Response::new(SimpleOkResponse {
            sucesso: corpo
                .get("sucesso")
                .and_then(|v| v.as_bool())
                .unwrap_or(false),
        }))
    }

    // --- Conexões de WhatsApp do tenant ---
    //
    // O onboarding cria a primeira. Sem estas, uma conexão que cai deixa o
    // tenant sem saída: não há como ver o estado, reconectar nem trocar.

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListMyWhatsappInstances", traceparent)
    )]
    async fn list_my_whatsapp_instances(
        &self,
        req: Request<ListMyWhatsappInstancesRequest>,
    ) -> Result<Response<ListMyWhatsappInstancesResponse>, Status> {
        // Listar é leitura do BANCO, não do provedor: quem tem a rota
        // `ListWhatsappInstances` é o `data_postgres`. Mandar para o
        // `data_whatsapp` (que só fala com a Evolution) devolvia "método
        // desconhecido" e a tela de conexões nunca carregava.
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "ListWhatsappInstances",
                serde_json::json!({}),
            )
            .await?;

        let mut instancias: Vec<MyWhatsappInstance> = corpo
            .get("instances")
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter().map(instancia_do_json).collect())
            .unwrap_or_default();

        // P7 — o departamento de cada conexão vem numa segunda chamada porque a
        // listagem usa `query_as!` (macro, cache `.sqlx`) e a coluna é nova.
        // Best-effort: falhar aqui deixaria a tela sem a lista inteira por causa
        // de um rótulo. Sem departamento, a conexão aparece como antes.
        if let Ok(deps) = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "ListDepartamentosDasConexoes",
                serde_json::json!({}),
            )
            .await
        {
            if let Some(arr) = deps.get("itens").and_then(|v| v.as_array()) {
                for item in arr {
                    let id = item.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
                    let Some(alvo) = instancias.iter_mut().find(|i| i.id == id) else {
                        continue;
                    };
                    alvo.departamento_id = item
                        .get("departamento_id")
                        .and_then(|v| v.as_i64())
                        .unwrap_or(0) as i32;
                    alvo.departamento_nome = item
                        .get("departamento_nome")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default()
                        .to_string();
                }
            }
        }

        Ok(Response::new(ListMyWhatsappInstancesResponse {
            instancias,
        }))
    }

    /// D3 — liga/desliga a resposta automática da IA **nesta conversa**.
    ///
    /// Escopo de atendimento, não de admin: quem atende a conversa é quem sabe
    /// se ela deve voltar para o robô. O `data_postgres` revalida com
    /// `atendimentos:write` ou `tenant:admin`.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "DefinirBotDaConversa", traceparent)
    )]
    async fn definir_bot_da_conversa(
        &self,
        req: Request<DefinirBotDaConversaRequest>,
    ) -> Result<Response<DefinirBotDaConversaResponse>, Status> {
        let inner = *req.get_ref();
        if inner.atendimento_id <= 0 {
            return Err(Status::invalid_argument("atendimento inválido"));
        }
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "DefinirBotDaConversa",
                serde_json::json!({
                    "atendimento_id": inner.atendimento_id,
                    "habilitado": inner.habilitado,
                }),
            )
            .await?;

        Ok(Response::new(DefinirBotDaConversaResponse {
            habilitado: corpo
                .get("habilitado")
                .and_then(|v| v.as_bool())
                .unwrap_or(inner.habilitado),
        }))
    }

    /// B6 (N9 E4) — marca como lidas as mensagens do contato numa conversa e
    /// espelha a leitura no WhatsApp (o contato vê que foi lido).
    ///
    /// Não passa por `encaminhar_tenant`: a marcação respeita o RBAC fino por
    /// fluxo, e aquele caminho sai com `flow_permissions` vazio — o atendente
    /// legítimo seria barrado. O espelho é best-effort: provedor fora do ar não
    /// desfaz a leitura, que já está gravada. Sem auditoria, de propósito.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "MarcarAtendimentoLido", traceparent)
    )]
    async fn marcar_atendimento_lido(
        &self,
        req: Request<MarcarAtendimentoLidoRequest>,
    ) -> Result<Response<MarcarAtendimentoLidoResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        exigir_escopo(&claims, &["atendimentos:read"], "MarcarAtendimentoLido")?;
        let atendimento_id = req.get_ref().atendimento_id;
        if atendimento_id <= 0 {
            return Err(Status::invalid_argument("atendimento inválido"));
        }
        let traceparent = traceparent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;
        let auth_user_id = claims.sub.parse::<i32>().unwrap_or(0);
        let flow_permissions = if claims.is_superuser {
            Vec::new()
        } else {
            resolver_flow_permissions_web(&self.deps, &claims.tenant_id, auth_user_id, &traceparent)
                .await
        };
        let envelope = |metodo: &str, payload: &serde_json::Value, fluxos: Vec<i32>| Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: metodo.to_string(),
            payload: serde_json::to_vec(payload).unwrap_or_default(),
            auth_user_id,
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: claims.is_superuser,
            flow_permissions: fluxos,
            ..Default::default()
        };

        let resp = self
            .deps
            .pg
            .call(
                envelope(
                    "MarcarAtendimentoLido",
                    &serde_json::json!({ "atendimento_id": atendimento_id }),
                    flow_permissions,
                ),
                std::time::Duration::from_secs(5),
            )
            .await
            .map_err(|e| Status::internal(format!("Falha no serviço interno: {e}")))?;
        if resp.kind == MessageKind::Error as i32 {
            let msg = resp.error.map(|e| e.message).unwrap_or_default();
            return Err(Status::internal(format!("Erro no banco: {msg}")));
        }
        let corpo: serde_json::Value =
            serde_json::from_slice(&resp.payload).map_err(|e| Status::internal(e.to_string()))?;

        if let Some(espelho) = corpo.get("whatsapp").filter(|v| v.is_object()) {
            let pedido = envelope("MarkWhatsappMessageRead", espelho, Vec::new());
            match self
                .whatsapp
                .call(pedido, std::time::Duration::from_secs(5))
                .await
            {
                Ok(r) if r.kind != MessageKind::Error as i32 => {}
                // Só o fato: o id da conversa, nunca telefone nem ids de mensagem.
                _ => tracing::warn!(atendimento_id, "leitura não espelhada no WhatsApp"),
            }
        }

        Ok(Response::new(MarcarAtendimentoLidoResponse {
            marcadas: corpo.get("marcadas").and_then(|v| v.as_i64()).unwrap_or(0) as i32,
        }))
    }

    /// D3 — liga/desliga a resposta automática da IA para a conexão inteira.
    ///
    /// Equivale ao `instances/<pk>/toggle-bot/` da v1. `tenant_id` das claims e
    /// escopo `tenant:admin` (via `encaminhar_tenant`): calar o bot de um número
    /// muda o comportamento do produto para todos os atendentes daquele tenant,
    /// e não é decisão de quem só atende.
    #[tracing::instrument(
        skip_all,
        fields(
            service = "runtime_api",
            rpc = "DefinirRespostaBotInstancia",
            traceparent
        )
    )]
    async fn definir_resposta_bot_instancia(
        &self,
        req: Request<DefinirRespostaBotInstanciaRequest>,
    ) -> Result<Response<DefinirRespostaBotInstanciaResponse>, Status> {
        let inner = *req.get_ref();
        if inner.id <= 0 {
            return Err(Status::invalid_argument("conexão inválida"));
        }
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "DefinirRespostaBotInstancia",
                serde_json::json!({ "id": inner.id, "habilitado": inner.habilitado }),
            )
            .await?;

        Ok(Response::new(DefinirRespostaBotInstanciaResponse {
            habilitado: corpo
                .get("habilitado")
                .and_then(|v| v.as_bool())
                .unwrap_or(inner.habilitado),
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(
            service = "runtime_api",
            rpc = "ReconnectMyWhatsappInstance",
            traceparent
        )
    )]
    async fn reconnect_my_whatsapp_instance(
        &self,
        req: Request<MyWhatsappInstanceIdRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let id = req.get_ref().id;
        self.encaminhar_tenant(
            &req,
            &self.whatsapp,
            "ReconnectWhatsappInstance",
            serde_json::json!({ "id": id }),
        )
        .await?;

        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    /// P13/P6 — o contato da conversa, com a foto guardada no R2.
    ///
    /// `foto_url` é a URL assinada do avatar no R2 (TTL de 3600 s), vazia quando
    /// não há foto. A foto é sincronizada pelo worker (`contato.foto.sincronizar`):
    /// no máximo a cada 7 dias por contato, ou com `forcar` (a tela o usa quando
    /// a imagem não abre) a partir de 10 minutos da última verificação. A
    /// resposta sai com o que já está guardado — **o provedor nunca é chamado no
    /// caminho da requisição**; quando a foto nova chega, o realtime avisa com
    /// `contato.foto_atualizada { contato_id }`.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ObterContatoDoAtendimento", origem = tracing::field::Empty, traceparent)
    )]
    async fn obter_contato_do_atendimento(
        &self,
        req: Request<ObterContatoDoAtendimentoRequest>,
    ) -> Result<Response<ObterContatoDoAtendimentoResponse>, Status> {
        let inner = *req.get_ref();
        if inner.atendimento_id <= 0 {
            return Err(Status::invalid_argument("atendimento inválido"));
        }
        let contato = self
            .encaminhar_operacional(
                &req,
                "ContatoDoAtendimento",
                &["atendimentos:read"],
                serde_json::json!({ "atendimento_id": inner.atendimento_id }),
            )
            .await?;

        let contato_id = contato
            .get("contato_id")
            .and_then(|v| v.as_i64())
            .unwrap_or(0) as i32;
        let foto_chave = texto_do(&contato, "foto_chave");
        let chave = chave_de_foto(&foto_chave);
        let agendar = contato_id > 0
            && precisa_sincronizar_foto(
                idade_da_verificacao(&contato, "foto_verificada_em"),
                inner.forcar,
            );

        let traceparent = traceparent_do_metadata(&req);
        let tenant_uuid = tenant_do_token(&req);
        if let (true, Some(tenant_uuid)) = (agendar, tenant_uuid) {
            pedir_sincronizacao_da_foto(&self.bus, tenant_uuid, contato_id, &traceparent).await;
        }
        tracing::Span::current().record("origem", origem_da_foto(agendar, chave.is_some()));

        // URL assinada do avatar. Storage fora do ar = sem foto, nunca erro.
        let mut foto_url = String::new();
        if let (Some(chave), Some(storage), Some(tenant_uuid)) =
            (chave, self.deps.storage.as_ref(), tenant_uuid)
        {
            let itens = [serde_json::json!({ "file_name": chave })];
            match presign_em_lote(storage, tenant_uuid, &traceparent, &itens, TTL_URL_FOTO_S).await
            {
                Some(urls) => foto_url = urls.get(chave).cloned().unwrap_or_default(),
                None => tracing::warn!("falha ao assinar a foto do contato"),
            }
        }

        Ok(Response::new(ObterContatoDoAtendimentoResponse {
            contato_id,
            nome: texto_do(&contato, "nome"),
            telefone: texto_do(&contato, "telefone"),
            foto_url,
        }))
    }

    /// P17 — as avaliações do teste de resposta ainda não tratadas.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListMyAvaliacoesDeTeste", traceparent)
    )]
    async fn list_my_avaliacoes_de_teste(
        &self,
        req: Request<ListMyAvaliacoesDeTesteRequest>,
    ) -> Result<Response<ListMyAvaliacoesDeTesteResponse>, Status> {
        let limite = req.get_ref().limite;
        let corpo = self
            .encaminhar_operacional(
                &req,
                "ListAvaliacoesDeTeste",
                &["treinamento:read"],
                serde_json::json!({ "limite": if limite > 0 { limite } else { 50 } }),
            )
            .await?;
        let itens = corpo
            .get("itens")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .map(|v| AvaliacaoDeTeste {
                        id: v.get("id").and_then(|x| x.as_i64()).unwrap_or(0) as i32,
                        pergunta: texto_do(v, "pergunta"),
                        resposta_bot: texto_do(v, "resposta_bot"),
                        resposta_corrigida: texto_do(v, "resposta_corrigida"),
                        avaliacao: texto_do(v, "avaliacao"),
                        confiabilidade: v
                            .get("confiabilidade")
                            .and_then(|x| x.as_f64())
                            .unwrap_or(0.0),
                        criada_em: v
                            .get("created_at")
                            .and_then(|x| x.as_str())
                            .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
                            .map(|d| d.timestamp_millis())
                            .unwrap_or(0),
                    })
                    .collect()
            })
            .unwrap_or_default();
        Ok(Response::new(ListMyAvaliacoesDeTesteResponse { itens }))
    }

    /// P17 — tira a avaliação da revisão.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "MarcarAvaliacaoTratada", traceparent)
    )]
    async fn marcar_avaliacao_tratada(
        &self,
        req: Request<MarcarAvaliacaoTratadaRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let inner = *req.get_ref();
        if inner.id <= 0 {
            return Err(Status::invalid_argument("avaliação inválida"));
        }
        self.encaminhar_operacional(
            &req,
            "MarcarAvaliacaoTratada",
            &["treinamento:write"],
            serde_json::json!({ "id": inner.id, "virou_treinamento": inner.virou_treinamento }),
        )
        .await?;
        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    /// P16 — o atendente conferiu a resposta que a IA deu com pouca confiança.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "MarcarRevisado", traceparent)
    )]
    async fn marcar_revisado(
        &self,
        req: Request<MarcarRevisadoRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let id = req.get_ref().atendimento_id;
        if id <= 0 {
            return Err(Status::invalid_argument("atendimento inválido"));
        }
        self.encaminhar_operacional(
            &req,
            "DefinirRevisaoPendente",
            &["atendimentos:write"],
            serde_json::json!({ "atendimento_id": id, "pendente": false }),
        )
        .await?;
        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    /// P11 — a última versão publicada do app de uma plataforma.
    ///
    /// Vem das CoreSettings (`app.<plataforma>.build`, `.url`, `.notas`), que o
    /// superusuário atualiza ao publicar o zip. Qualquer sessão pode perguntar;
    /// por isso a resposta sai de uma lista FECHADA de três chaves, e nunca da
    /// listagem inteira — as demais configurações incluem segredos.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "GetVersaoDoApp", traceparent)
    )]
    async fn get_versao_do_app(
        &self,
        req: Request<GetVersaoDoAppRequest>,
    ) -> Result<Response<GetVersaoDoAppResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        let plataforma = req.get_ref().plataforma.trim().to_lowercase();
        // O nome vira parte da chave: só letras, para ninguém montar a chave de
        // outra configuração pelo campo.
        if plataforma.is_empty() || !plataforma.chars().all(|c| c.is_ascii_lowercase()) {
            return Err(Status::invalid_argument("plataforma inválida"));
        }

        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent_do_metadata(&req),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "ListCoreSettings".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({})).unwrap_or_default(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            // Leitura interna da borda: quem pediu não vê a lista, só as três
            // chaves filtradas abaixo.
            auth_is_superuser: true,
            ..Default::default()
        };
        let resp = self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
            .map_err(|e| Status::unavailable(format!("Falha no serviço interno: {e}")))?;
        if resp.kind == MessageKind::Error as i32 {
            return Err(status_do_erro_interno(resp.error));
        }
        let corpo: serde_json::Value =
            serde_json::from_slice(&resp.payload).map_err(|e| Status::internal(e.to_string()))?;

        let valor = |sufixo: &str| -> String {
            let chave = format!("app.{plataforma}.{sufixo}");
            corpo
                .get("settings")
                .and_then(|v| v.as_array())
                .and_then(|arr| {
                    arr.iter().find(|s| {
                        s.get("key").and_then(|k| k.as_str()) == Some(chave.as_str())
                            && !s
                                .get("encrypted")
                                .and_then(|e| e.as_bool())
                                .unwrap_or(false)
                    })
                })
                .and_then(|s| s.get("value"))
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .trim()
                .to_string()
        };

        Ok(Response::new(GetVersaoDoAppResponse {
            build_atual: valor("build").parse::<i64>().unwrap_or(0),
            url_download: valor("url"),
            notas: valor("notas"),
        }))
    }

    /// P9 — as mensagens do atendente que ficaram sem destino.
    #[tracing::instrument(
        skip_all,
        fields(
            service = "runtime_api",
            rpc = "ListMyMensagensNaoEntregues",
            traceparent
        )
    )]
    async fn list_my_mensagens_nao_entregues(
        &self,
        req: Request<ListMyMensagensNaoEntreguesRequest>,
    ) -> Result<Response<ListMyMensagensNaoEntreguesResponse>, Status> {
        let corpo = self
            .encaminhar_operacional(
                &req,
                "ListMensagensNaoEntregues",
                &["operacional:read"],
                serde_json::json!({}),
            )
            .await?;
        let itens = corpo
            .get("itens")
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter().map(nao_entregue_do_json).collect())
            .unwrap_or_default();
        Ok(Response::new(ListMyMensagensNaoEntreguesResponse { itens }))
    }

    /// P9 — devolve a mensagem ao outbox para uma nova tentativa.
    ///
    /// Reusa o `ReprocessarDeadLetter` da N7.2, que já audita quem mandou
    /// reprocessar o quê — reenviar pode gerar entrega ao cliente.
    #[tracing::instrument(
        skip_all,
        fields(
            service = "runtime_api",
            rpc = "ReenviarMensagemNaoEntregue",
            traceparent
        )
    )]
    async fn reenviar_mensagem_nao_entregue(
        &self,
        req: Request<ReenviarMensagemNaoEntregueRequest>,
    ) -> Result<Response<ReenviarMensagemNaoEntregueResponse>, Status> {
        let id = req.get_ref().id;
        if id <= 0 {
            return Err(Status::invalid_argument("registro inválido"));
        }
        let corpo = self
            .encaminhar_operacional(
                &req,
                "ReprocessarDeadLetter",
                &["operacional:admin"],
                serde_json::json!({ "dead_letter_id": id }),
            )
            .await?;
        Ok(Response::new(ReenviarMensagemNaoEntregueResponse {
            status: corpo
                .get("status")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string(),
        }))
    }

    /// P7 — encerra a sessão sem apagar a conexão.
    ///
    /// Remover era a única saída para trocar de aparelho, e ela custava o
    /// cadastro inteiro: nome da instância, vínculo de departamento, tudo. Aqui
    /// o registro fica e volta com um QR novo.
    #[tracing::instrument(
        skip_all,
        fields(
            service = "runtime_api",
            rpc = "DesconectarMyWhatsappInstance",
            traceparent
        )
    )]
    async fn desconectar_my_whatsapp_instance(
        &self,
        req: Request<MyWhatsappInstanceIdRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let id = req.get_ref().id;
        self.encaminhar_tenant(
            &req,
            &self.whatsapp,
            "DisconnectWhatsappInstance",
            serde_json::json!({ "id": id }),
        )
        .await?;

        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    /// P7 — roteamento por conexão: a conversa que chega neste número entra no
    /// fluxo do departamento dele. `departamento_id = 0` desfaz o vínculo.
    #[tracing::instrument(
        skip_all,
        fields(
            service = "runtime_api",
            rpc = "DefinirDepartamentoDaConexao",
            traceparent
        )
    )]
    async fn definir_departamento_da_conexao(
        &self,
        req: Request<DefinirDepartamentoDaConexaoRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let inner = *req.get_ref();
        if inner.id <= 0 {
            return Err(Status::invalid_argument("conexão inválida"));
        }
        self.encaminhar_operacional(
            &req,
            "DefinirDepartamentoDaConexao",
            &["operacional:admin"],
            serde_json::json!({
                "id": inner.id,
                "departamento_id": inner.departamento_id,
            }),
        )
        .await?;

        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    /// P7 — o detalhe da conexão: estado, número pareado, departamento e o que
    /// se perde ao desconectar agora.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "DetalheDaConexao", traceparent)
    )]
    async fn detalhe_da_conexao(
        &self,
        req: Request<DetalheDaConexaoRequest>,
    ) -> Result<Response<DetalheDaConexaoResponse>, Status> {
        let id = req.get_ref().id;
        if id <= 0 {
            return Err(Status::invalid_argument("conexão inválida"));
        }
        let corpo = self
            .encaminhar_operacional(
                &req,
                "DetalheDaConexao",
                &["operacional:read"],
                serde_json::json!({ "id": id }),
            )
            .await?;

        let texto = |chave: &str| {
            corpo
                .get(chave)
                .and_then(|x| x.as_str())
                .unwrap_or_default()
                .to_string()
        };
        let inteiro = |chave: &str| corpo.get(chave).and_then(|x| x.as_i64()).unwrap_or(0);

        let conexao = MyWhatsappInstance {
            id: inteiro("id") as i32,
            name: texto("name"),
            phone_number: texto("phone_number"),
            connection_state: texto("connection_state"),
            active: corpo
                .get("active")
                .and_then(|x| x.as_bool())
                .unwrap_or(false),
            provider: texto("provider"),
            created_at: corpo
                .get("created_at")
                .and_then(|x| x.as_str())
                .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
                .map(|d| d.timestamp_millis())
                .unwrap_or(0),
            resposta_bot: corpo
                .get("resposta_bot")
                .and_then(|x| x.as_bool())
                .unwrap_or(true),
            departamento_id: inteiro("departamento_id") as i32,
            departamento_nome: texto("departamento_nome"),
        };

        Ok(Response::new(DetalheDaConexaoResponse {
            conexao: Some(conexao),
            ultima_checagem: corpo
                .get("last_state_check")
                .and_then(|x| x.as_str())
                .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
                .map(|d| d.timestamp_millis())
                .unwrap_or(0),
            instancia_no_provedor: texto("instance_id"),
            atendimentos_abertos: inteiro("atendimentos_abertos") as i32,
            mensagens_24h: inteiro("mensagens_24h") as i32,
        }))
    }

    /// P7 — os números que o sistema ignora (a "whitelist" da v1).
    ///
    /// A regra já era aplicada na ingestão; o que não existia era meio de ver ou
    /// mexer na lista sem abrir o banco.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListMyNumerosIgnorados", traceparent)
    )]
    async fn list_my_numeros_ignorados(
        &self,
        req: Request<ListMyNumerosIgnoradosRequest>,
    ) -> Result<Response<ListMyNumerosIgnoradosResponse>, Status> {
        let corpo = self
            .encaminhar_operacional(
                &req,
                "ListNumerosIgnorados",
                &["operacional:read"],
                serde_json::json!({}),
            )
            .await?;

        let itens = corpo
            .get("itens")
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter().map(numero_ignorado_do_json).collect())
            .unwrap_or_default();

        Ok(Response::new(ListMyNumerosIgnoradosResponse { itens }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "CriarNumeroIgnorado", traceparent)
    )]
    async fn criar_numero_ignorado(
        &self,
        req: Request<CriarNumeroIgnoradoRequest>,
    ) -> Result<Response<MyNumeroIgnoradoResponse>, Status> {
        let inner = req.get_ref().clone();
        let telefone = inner.telefone.trim().to_string();
        if telefone.is_empty() {
            return Err(Status::invalid_argument("informe o número"));
        }
        let corpo = self
            .encaminhar_operacional(
                &req,
                "CriarNumeroIgnorado",
                &["operacional:admin"],
                serde_json::json!({
                    "nome": inner.nome.trim(),
                    "telefone": telefone,
                }),
            )
            .await?;

        Ok(Response::new(MyNumeroIgnoradoResponse {
            item: corpo.get("item").map(numero_ignorado_do_json),
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "AtualizarNumeroIgnorado", traceparent)
    )]
    async fn atualizar_numero_ignorado(
        &self,
        req: Request<AtualizarNumeroIgnoradoRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let inner = req.get_ref().clone();
        if inner.id <= 0 {
            return Err(Status::invalid_argument("registro inválido"));
        }
        let telefone = inner.telefone.trim().to_string();
        if telefone.is_empty() {
            return Err(Status::invalid_argument("informe o número"));
        }
        self.encaminhar_operacional(
            &req,
            "AtualizarNumeroIgnorado",
            &["operacional:admin"],
            serde_json::json!({
                "id": inner.id,
                "nome": inner.nome.trim(),
                "telefone": telefone,
                "ativo": inner.ativo,
            }),
        )
        .await?;

        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "RemoverNumeroIgnorado", traceparent)
    )]
    async fn remover_numero_ignorado(
        &self,
        req: Request<NumeroIgnoradoIdRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let id = req.get_ref().id;
        if id <= 0 {
            return Err(Status::invalid_argument("registro inválido"));
        }
        self.encaminhar_operacional(
            &req,
            "RemoverNumeroIgnorado",
            &["operacional:admin"],
            serde_json::json!({ "id": id }),
        )
        .await?;

        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "DeleteMyWhatsappInstance", traceparent)
    )]
    async fn delete_my_whatsapp_instance(
        &self,
        req: Request<MyWhatsappInstanceIdRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let id = req.get_ref().id;
        self.encaminhar_tenant(
            &req,
            &self.whatsapp,
            "DeleteWhatsappInstance",
            serde_json::json!({ "id": id }),
        )
        .await?;

        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "RemoverMyTreinamento", traceparent)
    )]
    async fn remover_my_treinamento(
        &self,
        req: Request<RemoverMyTreinamentoRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let id = req.get_ref().id;
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "RemoverTreinamento",
                serde_json::json!({ "id": id }),
            )
            .await?;

        Ok(Response::new(SimpleOkResponse {
            sucesso: corpo
                .get("sucesso")
                .and_then(|v| v.as_bool())
                .unwrap_or(false),
        }))
    }

    // --- Vouchers de ativação (superusuário) ---
    //
    // Métodos concretos, e não só rotas no roteador de envelope: sem a
    // implementação aqui o Flutter Web não os alcança, ainda que o
    // `data_postgres` responda.

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListVouchers", traceparent)
    )]
    async fn list_vouchers(
        &self,
        req: Request<ListVouchersRequest>,
    ) -> Result<Response<ListVouchersResponse>, Status> {
        let corpo = self
            .encaminhar_admin(&req, "ListVouchers", serde_json::json!({}))
            .await?;
        Ok(Response::new(ListVouchersResponse {
            vouchers: corpo
                .get("vouchers")
                .and_then(|v| v.as_array())
                .map(|arr| arr.iter().map(voucher_do_json).collect())
                .unwrap_or_default(),
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "CreateVoucher", traceparent)
    )]
    async fn create_voucher(
        &self,
        req: Request<CreateVoucherRequest>,
    ) -> Result<Response<CreateVoucherResponse>, Status> {
        let inner = req.get_ref().clone();
        let corpo = self
            .encaminhar_admin(
                &req,
                "CreateVoucher",
                serde_json::json!({
                    "codigo": inner.codigo,
                    "descricao": inner.descricao,
                    "plan_id": inner.plan_id,
                    "duracao_dias": inner.duracao_dias,
                    "max_resgates": inner.max_resgates,
                    "valido_ate": inner.valido_ate,
                }),
            )
            .await?;
        Ok(Response::new(CreateVoucherResponse {
            voucher: corpo.get("voucher").map(voucher_do_json),
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "RevokeVoucher", traceparent)
    )]
    async fn revoke_voucher(
        &self,
        req: Request<RevokeVoucherRequest>,
    ) -> Result<Response<RevokeVoucherResponse>, Status> {
        let inner = req.get_ref().clone();
        let corpo = self
            .encaminhar_admin(
                &req,
                "RevokeVoucher",
                serde_json::json!({
                    "voucher_id": inner.voucher_id,
                    "motivo": inner.motivo,
                }),
            )
            .await?;
        Ok(Response::new(RevokeVoucherResponse {
            revogado: corpo
                .get("revogado")
                .and_then(|v| v.as_bool())
                .unwrap_or(false),
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListVoucherRedemptions", traceparent)
    )]
    async fn list_voucher_redemptions(
        &self,
        req: Request<ListVoucherRedemptionsRequest>,
    ) -> Result<Response<ListVoucherRedemptionsResponse>, Status> {
        let inner = req.get_ref().clone();
        let corpo = self
            .encaminhar_admin(
                &req,
                "ListVoucherRedemptions",
                serde_json::json!({ "voucher_id": inner.voucher_id }),
            )
            .await?;
        Ok(Response::new(ListVoucherRedemptionsResponse {
            resgates: corpo
                .get("resgates")
                .and_then(|v| v.as_array())
                .map(|arr| arr.iter().map(resgate_do_json).collect())
                .unwrap_or_default(),
        }))
    }

    /// P9 — o `test-connection` da v1 para o provedor de IA.
    ///
    /// Um embedding de ensaio com a configuração do tenant alvo: é a chamada
    /// mais barata que passa pelo provedor inteiro (chave, cota, modelo). Antes
    /// disto, chave expirada só aparecia quando o bot parava de responder.
    ///
    /// Falha do provedor volta como `ok: false` com o motivo, e não como erro
    /// gRPC: o teste deu certo — o que ele descobriu é que o provedor não está.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "TestarProvedorIa", traceparent)
    )]
    async fn testar_provedor_ia(
        &self,
        req: Request<TestarProvedorIaRequest>,
    ) -> Result<Response<TestarProvedorIaResponse>, Status> {
        let _claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let tenant_id = req.get_ref().tenant_id.trim().to_string();
        if Uuid::parse_str(&tenant_id).is_err() {
            return Err(Status::invalid_argument("tenant inválido"));
        }

        let inicio = std::time::Instant::now();
        let resultado = self
            .ia
            .embed(
                ia_client::EmbedInput {
                    tenant_id: tenant_id.clone(),
                    // Texto fixo e sem dado de ninguém: o que se mede é o
                    // caminho até o provedor, não o conteúdo.
                    textos: vec!["teste de conexão".to_string()],
                },
                &traceparent,
            )
            .await;
        let latencia_ms = inicio.elapsed().as_millis().min(i32::MAX as u128) as i32;

        let resposta = match resultado {
            Ok(saida) => {
                let dimensoes = saida.embeddings.first().map(|v| v.len()).unwrap_or(0) as i32;
                TestarProvedorIaResponse {
                    ok: dimensoes > 0,
                    latencia_ms,
                    dimensoes,
                    erro: if dimensoes > 0 {
                        String::new()
                    } else {
                        "o provedor respondeu sem vetor".to_string()
                    },
                }
            }
            Err(e) => TestarProvedorIaResponse {
                ok: false,
                latencia_ms,
                dimensoes: 0,
                erro: e.to_string(),
            },
        };

        Ok(Response::new(resposta))
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

    // --- P11: instalador Windows ---

    /// Link de download do instalador Windows (só superusuário). O ticket HMAC é
    /// assinado no control_plane (`IssueReleaseDownloadTicket`), que também
    /// audita `release_download_link_issued`; aqui fica só a guarda de borda.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "GetWindowsDownloadLink", traceparent)
    )]
    async fn get_windows_download_link(
        &self,
        req: Request<GetWindowsDownloadLinkRequest>,
    ) -> Result<Response<GetWindowsDownloadLinkResponse>, Status> {
        let claims = exigir_superuser_do_metadata(&self.deps, &self.bus, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let inner = req.into_inner();

        let env_req = Envelope {
            tenant_id: Uuid::nil().to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent,
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "IssueReleaseDownloadTicket".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({
                "channel": inner.channel.trim(),
                "version": inner.version.trim(),
            }))
            .map_err(|e| Status::internal(e.to_string()))?,
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: true,
            ..Default::default()
        };

        let resp = self
            .control
            .call(env_req, std::time::Duration::from_secs(10))
            .await
            .map_err(|e| Status::unavailable(format!("Falha no control_plane: {e}")))?;
        if resp.kind == MessageKind::Error as i32 {
            return Err(status_do_erro_de_release(resp.error));
        }
        let val: serde_json::Value =
            serde_json::from_slice(&resp.payload).map_err(|e| Status::internal(e.to_string()))?;
        let texto = |campo: &str| {
            val.get(campo)
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string()
        };
        let inteiro = |campo: &str| val.get(campo).and_then(|v| v.as_i64()).unwrap_or(0);

        Ok(Response::new(GetWindowsDownloadLinkResponse {
            url: texto("url"),
            version: texto("version"),
            file_name: texto("file_name"),
            size_bytes: inteiro("size_bytes"),
            sha256: texto("sha256"),
            release_notes_md: texto("release_notes_md"),
            expires_at_ms: inteiro("expires_at_ms"),
        }))
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

    /// P5 — a história do atendimento numa lista só.
    #[tracing::instrument(
        skip_all,
        fields(
            service = "runtime_api",
            rpc = "ListarTimelineAtendimento",
            traceparent
        )
    )]
    async fn listar_timeline_atendimento(
        &self,
        req: Request<ListarTimelineRequest>,
    ) -> Result<Response<ListarTimelineResponse>, Status> {
        let inner_ref = *req.get_ref();
        let corpo = self
            .encaminhar_operacional(
                &req,
                "ListarTimelineAtendimento",
                &["atendimentos:read"],
                serde_json::json!({ "atendimento_id": inner_ref.atendimento_id }),
            )
            .await?;

        let eventos = corpo
            .get("eventos")
            .and_then(|v| v.as_array())
            .map(|itens| {
                itens
                    .iter()
                    .map(|e| {
                        let texto = |chave: &str| {
                            e.get(chave)
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string()
                        };
                        EventoDaTimeline {
                            tipo: texto("tipo"),
                            quando: e.get("quando").and_then(|v| v.as_i64()).unwrap_or(0),
                            descricao: texto("descricao"),
                            autor: texto("autor"),
                            automatico: e
                                .get("automatico")
                                .and_then(|v| v.as_bool())
                                .unwrap_or(false),
                        }
                    })
                    .collect()
            })
            .unwrap_or_default();

        Ok(Response::new(ListarTimelineResponse { eventos }))
    }

    /// P5 — as outras conversas do mesmo contato.
    #[tracing::instrument(
        skip_all,
        fields(
            service = "runtime_api",
            rpc = "ListarAtendimentosDoContato",
            traceparent
        )
    )]
    async fn listar_atendimentos_do_contato(
        &self,
        req: Request<ListarAtendimentosDoContatoRequest>,
    ) -> Result<Response<ListarAtendimentosDoContatoResponse>, Status> {
        let inner_ref = *req.get_ref();
        let corpo = self
            .encaminhar_operacional(
                &req,
                "ListarAtendimentosDoContato",
                &["atendimentos:read"],
                serde_json::json!({
                    "contato_id": inner_ref.contato_id,
                    "limit": if inner_ref.limit > 0 { inner_ref.limit } else { 20 },
                }),
            )
            .await?;

        let atendimentos = corpo
            .get("atendimentos")
            .and_then(|v| v.as_array())
            .map(|itens| itens.iter().map(atendimento_resumo_do_json).collect())
            .unwrap_or_default();

        Ok(Response::new(ListarAtendimentosDoContatoResponse {
            atendimentos,
        }))
    }

    /// P5 — apaga uma nota interna.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "RemoverNota", traceparent)
    )]
    async fn remover_nota(
        &self,
        req: Request<RemoverNotaRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let inner_ref = *req.get_ref();
        self.encaminhar_operacional(
            &req,
            "RemoverNota",
            &["atendimentos:write"],
            serde_json::json!({
                "nota_id": inner_ref.nota_id,
                "atendimento_id": inner_ref.atendimento_id,
            }),
        )
        .await?;

        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    /// P5 — renomeia/recolore uma etiqueta do catálogo.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "UpdateEtiqueta", traceparent)
    )]
    async fn update_etiqueta(
        &self,
        req: Request<UpdateEtiquetaRequest>,
    ) -> Result<Response<EtiquetaResponse>, Status> {
        let inner_ref = req.get_ref().clone();
        let corpo = self
            .encaminhar_operacional(
                &req,
                "UpdateEtiqueta",
                &["atendimentos:write"],
                serde_json::json!({
                    "id": inner_ref.id,
                    "nome": inner_ref.nome,
                    "cor": inner_ref.cor,
                    "descricao": inner_ref.descricao,
                }),
            )
            .await?;

        Ok(Response::new(EtiquetaResponse {
            etiqueta: Some(etiqueta_do_json(&corpo)),
        }))
    }

    /// P5 — tira a etiqueta do catálogo, sem apagá-la das conversas.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "DesativarEtiqueta", traceparent)
    )]
    async fn desativar_etiqueta(
        &self,
        req: Request<DesativarEtiquetaRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let inner_ref = *req.get_ref();
        self.encaminhar_operacional(
            &req,
            "DesativarEtiqueta",
            &["atendimentos:write"],
            serde_json::json!({ "id": inner_ref.id }),
        )
        .await?;

        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    /// P4 — quem cuida da conversa.
    ///
    /// O rodízio (B5) já fazia isso sozinho; aqui é a mão do supervisor. A
    /// regra é a mesma dos dois lados: atribuir **não** tira conversa de quem
    /// já a assumiu — devolver para a fila é uma ação explícita.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "AtribuirAtendimento", traceparent)
    )]
    async fn atribuir_atendimento(
        &self,
        req: Request<AtribuirAtendimentoRequest>,
    ) -> Result<Response<AtribuirAtendimentoResponse>, Status> {
        let inner_ref = *req.get_ref();
        let corpo = self
            .encaminhar_operacional(
                &req,
                "AtribuirAtendimento",
                &["atendimentos:write"],
                serde_json::json!({
                    "atendimento_id": inner_ref.atendimento_id,
                    "atendente_id": inner_ref.atendente_id,
                    "devolver_para_fila": inner_ref.devolver_para_fila,
                }),
            )
            .await?;

        Ok(Response::new(AtribuirAtendimentoResponse {
            atribuido: corpo
                .get("atribuido")
                .and_then(|v| v.as_bool())
                .unwrap_or(false),
            motivo: corpo
                .get("motivo")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string(),
        }))
    }

    /// P4 — urgência do cartão. A coluna existia desde a 0006 e ninguém
    /// escrevia nela.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "DefinirPrioridade", traceparent)
    )]
    async fn definir_prioridade(
        &self,
        req: Request<DefinirPrioridadeRequest>,
    ) -> Result<Response<DefinirPrioridadeResponse>, Status> {
        let inner_ref = req.get_ref().clone();
        let corpo = self
            .encaminhar_operacional(
                &req,
                "DefinirPrioridade",
                &["atendimentos:write"],
                serde_json::json!({
                    "atendimento_id": inner_ref.atendimento_id,
                    "prioridade": inner_ref.prioridade,
                }),
            )
            .await?;

        Ok(Response::new(DefinirPrioridadeResponse {
            definida: corpo
                .get("definida")
                .and_then(|v| v.as_bool())
                .unwrap_or(false),
        }))
    }

    /// P4 — transferir a conversa de fluxo pela tela.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "TransferirParaFluxo", traceparent)
    )]
    async fn transferir_para_fluxo(
        &self,
        req: Request<TransferirParaFluxoRequest>,
    ) -> Result<Response<TransferirParaFluxoResponse>, Status> {
        let inner_ref = *req.get_ref();
        let corpo = self
            .encaminhar_operacional(
                &req,
                "TransferirAtendimentoParaFluxo",
                &["atendimentos:write"],
                serde_json::json!({
                    "atendimento_id": inner_ref.atendimento_id,
                    "fluxo_id": inner_ref.fluxo_id,
                }),
            )
            .await?;

        let texto = |chave: &str| {
            corpo
                .get(chave)
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string()
        };
        Ok(Response::new(TransferirParaFluxoResponse {
            transferido: corpo
                .get("transferido")
                .and_then(|v| v.as_bool())
                .unwrap_or(false),
            fluxo_id: corpo.get("fluxo_id").and_then(|v| v.as_i64()).unwrap_or(0) as i32,
            fluxo_nome: texto("fluxo_nome"),
            etapa_id: corpo.get("etapa_id").and_then(|v| v.as_i64()).unwrap_or(0) as i32,
            etapa_nome: texto("etapa_nome"),
            motivo: texto("reason"),
        }))
    }

    /// P4 — o quadro em CSV, para quem precisa fechar o dia numa planilha.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ExportarQuadro", traceparent)
    )]
    async fn exportar_quadro(
        &self,
        req: Request<ExportarQuadroRequest>,
    ) -> Result<Response<ExportarQuadroResponse>, Status> {
        let inner_ref = req.get_ref().clone();
        let corpo = self
            .encaminhar_operacional(
                &req,
                "ExportarQuadro",
                // Exportar é leitura, mas em massa e com PII: exige o escopo de
                // administração do tenant, não o de operar a fila.
                &["tenant:admin"],
                serde_json::json!({
                    "status": inner_ref.status,
                    "departamento_id": inner_ref.departamento_id,
                    "busca": inner_ref.busca,
                    "somente_meus": inner_ref.somente_meus,
                    "somente_nao_lidos": inner_ref.somente_nao_lidos,
                }),
            )
            .await?;

        let csv = corpo
            .get("csv")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string();
        Ok(Response::new(ExportarQuadroResponse {
            linhas: corpo.get("linhas").and_then(|v| v.as_i64()).unwrap_or(0) as i32,
            csv: csv.into_bytes(),
        }))
    }

    /// P3 — "digitando..." do atendente chega ao contato.
    ///
    /// Duas pernas: o `data_postgres` diz por qual conexão e para qual número
    /// (aplicando a RLS do tenant), e o `data_whatsapp` manda. Sem conexão
    /// ativa para o contato, devolve `enviado = false` em vez de erro: presença
    /// é enfeite, e derrubar a digitação por causa dela seria desproporcional.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "EnviarPresenca", traceparent)
    )]
    async fn enviar_presenca(
        &self,
        req: Request<EnviarPresencaRequest>,
    ) -> Result<Response<EnviarPresencaResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        exigir_escopo(&claims, &["atendimentos:write"], "EnviarPresenca")?;
        let traceparent = traceparent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;
        let inner = req.into_inner();

        let situacao = match inner.situacao.trim() {
            "" => "composing".to_string(),
            outro @ ("composing" | "recording" | "paused") => outro.to_string(),
            _ => return Err(Status::invalid_argument("situação de presença inválida")),
        };

        let auth_user_id = claims.sub.parse::<i32>().unwrap_or(0);
        let flow_permissions = if claims.is_superuser {
            Vec::new()
        } else {
            resolver_flow_permissions_web(&self.deps, &claims.tenant_id, auth_user_id, &traceparent)
                .await
        };

        let env_destino = Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "ResolverDestinoDoAtendimento".to_string(),
            payload: serde_json::to_vec(
                &serde_json::json!({ "atendimento_id": inner.atendimento_id }),
            )
            .unwrap(),
            auth_user_id,
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: claims.is_superuser,
            flow_permissions,
            ..Default::default()
        };

        let resp = self
            .deps
            .pg
            .call(env_destino, std::time::Duration::from_secs(5))
            .await
            .map_err(|e| Status::internal(format!("Falha no serviço interno: {}", e)))?;
        if resp.kind == MessageKind::Error as i32 {
            let err_msg = resp.error.map(|e| e.message).unwrap_or_default();
            return Err(Status::internal(format!("Erro no banco: {}", err_msg)));
        }
        let destino: serde_json::Value =
            serde_json::from_slice(&resp.payload).map_err(|e| Status::internal(e.to_string()))?;

        let (Some(instance_id), Some(to_number)) = (
            destino.get("instance_id").and_then(|v| v.as_i64()),
            destino.get("to_number").and_then(|v| v.as_str()),
        ) else {
            return Ok(Response::new(EnviarPresencaResponse { enviado: false }));
        };

        let env_presenca = Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent,
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "SetWhatsappPresence".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({
                "id": instance_id,
                "chat": to_number,
                "state": situacao,
                "is_audio": situacao == "recording",
            }))
            .unwrap(),
            auth_user_id,
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: claims.is_superuser,
            ..Default::default()
        };

        let enviado = match self
            .whatsapp
            .call(env_presenca, std::time::Duration::from_secs(5))
            .await
        {
            Ok(r) => r.kind != MessageKind::Error as i32,
            // O provedor fora do ar não pode interromper quem está digitando.
            Err(e) => {
                tracing::debug!(erro = %e, "presença não entregue ao provedor");
                false
            }
        };

        Ok(Response::new(EnviarPresencaResponse { enviado }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListAtendimentos", traceparent)
    )]
    async fn list_atendimentos(
        &self,
        req: Request<ListAtendimentosRequest>,
    ) -> Result<Response<ListAtendimentosResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        exigir_escopo(&claims, &["atendimentos:read"], "ListAtendimentos")?;
        let traceparent = traceparent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;
        let inner = req.into_inner();

        let payload = serde_json::json!({
            // Vazio viaja como vazio: é "o quadro inteiro". Trocar por "fila"
            // aqui escondia toda conversa que já tinha andado de coluna.
            "status": inner.status,
            // P1 — o recorte da v1: busca por texto, dono, não lidas, prioridade
            // e etiqueta.
            "busca": inner.busca,
            "atendente_id": inner.atendente_id,
            "somente_nao_lidos": inner.somente_nao_lidos,
            "prioridade": inner.prioridade,
            "etiqueta_id": inner.etiqueta_id,
            "somente_meus": inner.somente_meus,
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

                let mut val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;

                // P6 — fotos dos cartões: assinadas em lote, e sincronização
                // pedida ao worker para as vencidas. Nada disso derruba o quadro.
                if let Some(arr) = val.get_mut("atendimentos").and_then(|v| v.as_array_mut()) {
                    self.preparar_fotos_do_quadro(tenant_uuid, &traceparent, arr)
                        .await;
                }

                let mut atendimentos = Vec::new();
                if let Some(arr) = val.get("atendimentos").and_then(|v| v.as_array()) {
                    for item in arr {
                        atendimentos.push(atendimento_resumo_do_json(item));
                    }
                }

                Ok(Response::new(ListAtendimentosResponse { atendimentos }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    #[tracing::instrument(
        skip_all,
        fields(
            service = "runtime_api",
            rpc = "GetThread",
            traceparent,
            error_code = tracing::field::Empty
        )
    )]
    async fn get_thread(
        &self,
        req: Request<GetThreadRequest>,
    ) -> Result<Response<GetThreadResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        exigir_escopo(&claims, &["atendimentos:read"], "GetThread")?;
        let traceparent = traceparent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;
        let inner = req.into_inner();

        let payload = serde_json::json!({
            "atendimento_id": inner.atendimento_id,
            "limit": if inner.limit > 0 { inner.limit } else { 50 },
            "offset": inner.offset,
            // P2 — cursor da rolagem para trás (ausente na primeira carga).
            "before_id": inner.before_id,
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

                let mut val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;

                // P2a: assina as mídias da página numa chamada só. Falha do
                // storage não derruba a thread: as mensagens saem sem `midia`.
                let blocos: Vec<&mut serde_json::Value> = val
                    .get_mut("mensagens")
                    .and_then(|v| v.as_array_mut())
                    .map(|arr| arr.iter_mut().filter_map(|i| i.get_mut("midia")).collect())
                    .unwrap_or_default();
                if !assinar_midias_da_pagina(
                    self.deps.storage.as_ref(),
                    tenant_uuid,
                    &traceparent,
                    blocos,
                )
                .await
                {
                    tracing::Span::current().record("error_code", "presign_falhou");
                }

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
                            // N9/E2 + P2a: ponteiro/metadados vêm do
                            // `data_postgres`; a URL foi assinada acima, em lote.
                            midia: midia_do_item(item),
                            // N9/E7: ticks. As colunas existem desde a 0006 e
                            // nunca foram expostas — sem elas a bolha não
                            // distingue "enviado" de "lido".
                            data_entregue: millis_do_item(item, "data_entregue"),
                            data_lida: millis_do_item(item, "data_lida"),
                            // N9/E6: citação.
                            mensagem_citada_id: item
                                .get("mensagem_citada_id")
                                .and_then(|v| v.as_i64())
                                .map(|v| v as i32),
                            citada_remetente: item
                                .get("citada_remetente")
                                .and_then(|v| v.as_str())
                                .map(|s| s.to_string()),
                            citada_preview: item
                                .get("citada_preview")
                                .and_then(|v| v.as_str())
                                .map(|s| s.to_string()),
                            // P8 — reações e o que não cabe em `conteudo`.
                            reacoes: reacoes_do_item(item),
                            metadados_json: metadados_do_item(item),
                        });
                    }
                }

                Ok(Response::new(GetThreadResponse { mensagens }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    /// N9/E1 — passo 1 do envio de mídia: dizer ao cliente onde subir.
    ///
    /// Compõe duas portas de dados, e é por isso que mora aqui e não numa delas:
    /// o `data_postgres` valida o atendimento, o tipo e a quota do tenant; o
    /// `data_storage` assina a URL. Nenhuma porta chama a outra.
    ///
    /// A validação de tipo/tamanho aqui é a **primeira** barreira, feita sobre o
    /// que o cliente declara. A segunda — e a que vale — é a conferência do
    /// conteúdo real no passo 3, depois que o objeto está no bucket.
    ///
    /// `skip_all`: o nome do arquivo pode conter PII (nome de cliente, número de
    /// contrato) e a URL assinada é credencial.
    #[tracing::instrument(
        skip_all,
        fields(
            service = "runtime_api",
            rpc = "SolicitarUploadMidia",
            atendimento_id = tracing::field::Empty,
            bytes = tracing::field::Empty,
            traceparent
        )
    )]
    async fn solicitar_upload_midia(
        &self,
        req: Request<SolicitarUploadMidiaRequest>,
    ) -> Result<Response<SolicitarUploadMidiaResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        exigir_escopo(&claims, &["atendimentos:write"], "SolicitarUploadMidia")?;
        let traceparent = traceparent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;
        let inner = req.into_inner();

        let span = tracing::Span::current();
        span.record("atendimento_id", inner.atendimento_id);
        span.record("bytes", inner.bytes);

        let Some(storage) = self.deps.storage.as_ref() else {
            return Err(Status::unavailable("errors.midia.storage_indisponivel"));
        };

        // Barreira declarada: tipo aceito e tamanho dentro do teto da categoria.
        // Recusar aqui poupa o upload inteiro de um arquivo que seria rejeitado
        // no passo 3 — o atendente descobre antes de esperar a barra encher.
        let categoria = infrastructure_storage::midia::categoria_de(&inner.mimetype)
            .ok_or_else(|| Status::invalid_argument("errors.midia.tipo_nao_permitido"))?;
        if inner.bytes <= 0 {
            return Err(Status::invalid_argument("errors.midia.arquivo_vazio"));
        }
        if inner.bytes > categoria.limite_bytes() {
            return Err(Status::invalid_argument("errors.midia.acima_do_limite"));
        }

        // O `data_postgres` responde se o atendimento é deste tenant, se quem
        // pede tem permissão no fluxo, e se a quota de storage comporta.
        let auth_user_id = claims.sub.parse::<i32>().unwrap_or(0);
        let flow_permissions = if claims.is_superuser {
            Vec::new()
        } else {
            resolver_flow_permissions_web(&self.deps, &claims.tenant_id, auth_user_id, &traceparent)
                .await
        };
        let env_valida = Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "AutorizarUploadMidia".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({
                "atendimento_id": inner.atendimento_id,
                "bytes": inner.bytes,
            }))
            .unwrap(),
            auth_user_id,
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: claims.is_superuser,
            flow_permissions,
            ..Default::default()
        };
        let autorizacao = self
            .deps
            .pg
            .call(env_valida, std::time::Duration::from_secs(5))
            .await
            .map_err(|e| Status::internal(format!("Falha no serviço interno: {e}")))?;
        if autorizacao.kind == MessageKind::Error as i32 {
            let msg = autorizacao.error.map(|e| e.message).unwrap_or_default();
            // Quota estourada e atendimento de outro tenant chegam por aqui; a
            // mensagem já vem pronta para o operador ler.
            return Err(Status::failed_precondition(msg));
        }
        let corpo: serde_json::Value = serde_json::from_slice(&autorizacao.payload)
            .map_err(|e| Status::internal(e.to_string()))?;
        let chave = corpo
            .get("chave")
            .and_then(|v| v.as_str())
            .ok_or_else(|| Status::internal("autorização de upload sem chave"))?
            .to_string();

        // Assinatura no data_storage. O `content_type` volta ao cliente porque o
        // PUT precisa mandar exatamente este valor — o R2 recusa divergência.
        let env_presign = Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "PresignUpload".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({
                "file_name": chave,
                "content_type": inner.mimetype,
            }))
            .unwrap(),
            ..Default::default()
        };
        let presign = storage
            .call(env_presign, std::time::Duration::from_secs(5))
            .await
            .map_err(|e| Status::internal(format!("Falha no serviço de storage: {e}")))?;
        if presign.kind == MessageKind::Error as i32 {
            // Sem detalhe do erro do storage para o cliente: a mensagem pode
            // carregar a chave do objeto.
            tracing::warn!("falha ao assinar upload de mídia");
            return Err(Status::internal("errors.midia.presign_falhou"));
        }
        let corpo_presign: serde_json::Value = serde_json::from_slice(&presign.payload)
            .map_err(|e| Status::internal(e.to_string()))?;

        tracing::info!(categoria = categoria.as_str(), "upload de mídia autorizado");

        Ok(Response::new(SolicitarUploadMidiaResponse {
            // Nunca logada: é credencial de escrita no bucket.
            url_upload: corpo_presign
                .get("url")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string(),
            chave,
            content_type: inner.mimetype,
            expira_em_segundos: corpo_presign
                .get("expires_in")
                .and_then(|v| v.as_i64())
                .unwrap_or(900),
        }))
    }

    /// N9/E1 — passo 3: o upload terminou, confira e ponha na conversa.
    ///
    /// Encaminha ao `data_postgres`, que lê o cabeçalho do objeto no bucket,
    /// confere a assinatura contra o mimetype declarado, contabiliza a quota e
    /// persiste a mensagem com o evento no outbox.
    #[tracing::instrument(
        skip_all,
        fields(
            service = "runtime_api",
            rpc = "EnviarMidiaAtendimento",
            atendimento_id = tracing::field::Empty,
            traceparent
        )
    )]
    async fn enviar_midia_atendimento(
        &self,
        req: Request<EnviarMidiaAtendimentoRequest>,
    ) -> Result<Response<EnviarMidiaAtendimentoResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        exigir_escopo(&claims, &["atendimentos:write"], "EnviarMidiaAtendimento")?;
        let traceparent = traceparent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;
        let inner = req.into_inner();
        tracing::Span::current().record("atendimento_id", inner.atendimento_id);

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
            method: "EnviarMidiaAtendimento".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({
                "atendimento_id": inner.atendimento_id,
                "chave": inner.chave,
                "mimetype": inner.mimetype,
                "nome_arquivo": inner.nome_arquivo,
                "legenda": inner.legenda,
                "is_ptt": inner.is_ptt,
                "action_id": inner.action_id,
            }))
            .unwrap(),
            auth_user_id,
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: claims.is_superuser,
            flow_permissions,
            ..Default::default()
        };

        let resp = self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(10))
            .await
            .map_err(|e| Status::internal(format!("Falha no serviço interno: {e}")))?;
        if resp.kind == MessageKind::Error as i32 {
            let msg = resp.error.map(|e| e.message).unwrap_or_default();
            // Conteúdo divergente do declarado é erro do cliente, não do
            // servidor: devolver `internal` faria a tela sugerir "tente de novo"
            // para um arquivo que nunca vai passar.
            return Err(Status::invalid_argument(msg));
        }
        let corpo: serde_json::Value =
            serde_json::from_slice(&resp.payload).map_err(|e| Status::internal(e.to_string()))?;

        Ok(Response::new(EnviarMidiaAtendimentoResponse {
            message_id: corpo
                .get("message_id")
                .and_then(|v| v.as_i64())
                .unwrap_or_default() as i32,
        }))
    }

    /// N9/E2 — galeria da ficha: as mídias do atendimento, com URL assinada.
    #[tracing::instrument(
        skip_all,
        fields(
            service = "runtime_api",
            rpc = "ListarMidiasAtendimento",
            traceparent,
            error_code = tracing::field::Empty
        )
    )]
    async fn listar_midias_atendimento(
        &self,
        req: Request<ListarMidiasAtendimentoRequest>,
    ) -> Result<Response<ListarMidiasAtendimentoResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        exigir_escopo(&claims, &["atendimentos:read"], "ListarMidiasAtendimento")?;
        let traceparent = traceparent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;
        let inner = req.into_inner();

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
            method: "ListarMidiasAtendimento".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({
                "atendimento_id": inner.atendimento_id,
                "limit": if inner.limit <= 0 { 50 } else { inner.limit },
                "offset": inner.offset.max(0),
            }))
            .unwrap(),
            auth_user_id,
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: claims.is_superuser,
            flow_permissions,
            ..Default::default()
        };

        let resp = self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(10))
            .await
            .map_err(|e| Status::internal(format!("Falha no serviço interno: {e}")))?;
        if resp.kind == MessageKind::Error as i32 {
            let msg = resp.error.map(|e| e.message).unwrap_or_default();
            return Err(Status::internal(format!("Erro no banco: {msg}")));
        }
        let mut corpo: serde_json::Value =
            serde_json::from_slice(&resp.payload).map_err(|e| Status::internal(e.to_string()))?;

        // P2a: assinatura em lote da página da galeria (o `data_postgres` já
        // filtra as purgadas). Falha do storage → galeria vazia, não erro.
        let blocos: Vec<&mut serde_json::Value> = corpo
            .get_mut("midias")
            .and_then(|v| v.as_array_mut())
            .map(|arr| arr.iter_mut().collect())
            .unwrap_or_default();
        if !assinar_midias_da_pagina(
            self.deps.storage.as_ref(),
            tenant_uuid,
            &traceparent,
            blocos,
        )
        .await
        {
            tracing::Span::current().record("error_code", "presign_falhou");
        }

        let midias = corpo
            .get("midias")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    // Reaproveita o mesmo montador da thread: a mídia sem URL
                    // (presign falhou) simplesmente não entra na galeria.
                    .filter_map(|item| midia_do_item(&serde_json::json!({ "midia": item })))
                    .collect()
            })
            .unwrap_or_default();

        Ok(Response::new(ListarMidiasAtendimentoResponse { midias }))
    }

    /// C3 — abre um atendimento a partir de um cliente já cadastrado.
    ///
    /// Um método concreto, e não só a rota no roteador de envelope: sem ele o
    /// Flutter não alcança o RPC — é o que o `AdminService` expõe por
    /// gRPC-Web que define o que o cliente pode chamar.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "IniciarAtendimentoManual", traceparent)
    )]
    async fn iniciar_atendimento_manual(
        &self,
        req: Request<IniciarAtendimentoManualRequest>,
    ) -> Result<Response<IniciarAtendimentoManualResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        exigir_escopo(&claims, &["atendimentos:write"], "IniciarAtendimentoManual")?;
        let traceparent = traceparent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;
        let inner = req.into_inner();

        // Teto diário por tenant, antes de qualquer coisa.
        //
        // A evolution-go é whatsmeow: aceita qualquer número, sem a janela de
        // 24 h da Cloud API. Abrir conversa é tecnicamente trivial — e é o
        // caminho mais curto para o número do tenant ser denunciado e
        // bloqueado pelo WhatsApp, o que derruba TODO o atendimento dele, não
        // só o disparo. O limite protege o tenant de si mesmo.
        self.conferir_teto_de_atendimento_ativo(&tenant_uuid, &traceparent)
            .await?;

        let payload = serde_json::json!({
            "contato_id": inner.contato_id,
            "fluxo_id": inner.fluxo_id,
            "etapa_inicial_id": inner.etapa_inicial_id,
            "departamento_id": inner.departamento_id,
            "assunto": inner.assunto,
        });

        let auth_user_id = claims.sub.parse::<i32>().unwrap_or(0);
        // Mesmo RBAC fino por fluxo do Kanban: quem só pode operar o fluxo A
        // não abre conversa dentro do fluxo B.
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
            method: "IniciarAtendimentoManual".to_string(),
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
                    if err.code == "AUTH_INSUFFICIENT_SCOPE" {
                        return Err(Status::permission_denied("errors.auth.forbidden"));
                    }
                    return Err(status_do_erro_interno(Some(err)));
                }
                let val: serde_json::Value = serde_json::from_slice(&resp.payload)
                    .map_err(|e| Status::internal(e.to_string()))?;
                Ok(Response::new(IniciarAtendimentoManualResponse {
                    atendimento_id: val
                        .get("atendimento_id")
                        .and_then(|v| v.as_i64())
                        .unwrap_or_default() as i32,
                    ja_existia: val
                        .get("ja_existia")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false),
                }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {e}"))),
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
        exigir_escopo(&claims, &["atendimentos:write"], "MoveAtendimentoEtapa")?;
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

    // --- Ficha do atendimento: etiquetas e notas ---

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "GetDetalheAtendimento", traceparent)
    )]
    async fn get_detalhe_atendimento(
        &self,
        req: Request<AtendimentoIdRequest>,
    ) -> Result<Response<DetalheAtendimentoResponse>, Status> {
        let id = req.get_ref().atendimento_id;
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "GetDetalheAtendimento",
                serde_json::json!({ "atendimento_id": id }),
            )
            .await?;

        let lista = |chave: &str| -> Vec<ProtoEtiqueta> {
            corpo
                .get(chave)
                .and_then(|v| v.as_array())
                .map(|arr| arr.iter().map(etiqueta_do_json).collect())
                .unwrap_or_default()
        };

        Ok(Response::new(DetalheAtendimentoResponse {
            catalogo: lista("catalogo"),
            etiquetas: lista("etiquetas"),
            notas: corpo
                .get("notas")
                .and_then(|v| v.as_array())
                .map(|arr| arr.iter().map(nota_do_json).collect())
                .unwrap_or_default(),
            // Ausente = `true`: um servidor mais antigo não manda o campo, e o
            // padrão da coluna é a IA ligada. Assumir `false` faria a tela
            // anunciar um silêncio que não existe.
            bot_pode_atender: corpo
                .get("bot_pode_atender")
                .and_then(|v| v.as_bool())
                .unwrap_or(true),
            campos: corpo
                .get("campos")
                .and_then(|v| v.as_array())
                .map(|arr| arr.iter().map(valor_campo_do_json).collect())
                .unwrap_or_default(),
            // P15 — o que a IA guardou do contato.
            dados_do_contato: corpo
                .get("dados_do_contato")
                .and_then(|v| v.as_object())
                .map(|o| {
                    o.iter()
                        .filter_map(|(k, v)| {
                            Some(DadoDoContato {
                                chave: k.clone(),
                                valor: v.as_str()?.to_string(),
                            })
                        })
                        .collect()
                })
                .unwrap_or_default(),
            analise: corpo.get("analise").map(analise_do_json),
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "CreateEtiqueta", traceparent)
    )]
    async fn create_etiqueta(
        &self,
        req: Request<CreateEtiquetaRequest>,
    ) -> Result<Response<EtiquetaResponse>, Status> {
        let inner = req.get_ref().clone();
        if inner.nome.trim().is_empty() {
            return Err(Status::invalid_argument("informe o nome da etiqueta"));
        }

        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "CreateEtiqueta",
                serde_json::json!({
                    "nome": inner.nome.trim(),
                    "cor": inner.cor,
                }),
            )
            .await?;

        Ok(Response::new(EtiquetaResponse {
            etiqueta: Some(etiqueta_do_json(&corpo)),
        }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "AlternarEtiqueta", traceparent)
    )]
    async fn alternar_etiqueta(
        &self,
        req: Request<AlternarEtiquetaRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let inner = *req.get_ref();
        self.encaminhar_tenant(
            &req,
            &self.deps.pg,
            "AlternarEtiqueta",
            serde_json::json!({
                "atendimento_id": inner.atendimento_id,
                "etiqueta_id": inner.etiqueta_id,
                "aplicar": inner.aplicar,
            }),
        )
        .await?;

        Ok(Response::new(SimpleOkResponse { sucesso: true }))
    }

    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "CreateNota", traceparent)
    )]
    async fn create_nota(
        &self,
        req: Request<CreateNotaRequest>,
    ) -> Result<Response<NotaResponse>, Status> {
        let inner = req.get_ref().clone();
        if inner.texto.trim().is_empty() {
            return Err(Status::invalid_argument("escreva a anotação"));
        }

        // O texto da nota não entra em `fields` do instrument nem em log: é
        // conteúdo livre do operador sobre um cliente.
        let corpo = self
            .encaminhar_tenant(
                &req,
                &self.deps.pg,
                "CreateNota",
                serde_json::json!({
                    "atendimento_id": inner.atendimento_id,
                    "texto": inner.texto.trim(),
                }),
            )
            .await?;

        Ok(Response::new(NotaResponse {
            nota: Some(nota_do_json(&corpo)),
        }))
    }

    /// Muda o status do atendimento; o cartão acompanha.
    ///
    /// Mesmo RBAC fino por fluxo do arrasto: quem não pode mover o cartão
    /// também não pode encerrar a conversa por outro botão. E publica
    /// `kanban.movido` no mesmo canal, para que as outras telas vejam o cartão
    /// mudar de coluna sem polling — exatamente como se alguém o tivesse
    /// arrastado.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "SetAtendimentoStatus", traceparent)
    )]
    async fn set_atendimento_status(
        &self,
        req: Request<SetAtendimentoStatusRequest>,
    ) -> Result<Response<SetAtendimentoStatusResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        exigir_escopo(&claims, &["atendimentos:write"], "SetAtendimentoStatus")?;
        let traceparent = traceparent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;
        let inner = req.into_inner();

        if inner.status.trim().is_empty() {
            return Err(Status::invalid_argument("informe o status"));
        }

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
            method: "SetAtendimentoStatus".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({
                "atendimento_id": inner.atendimento_id,
                "status": inner.status,
                "motivo": inner.motivo,
            }))
            .unwrap(),
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
                    if err.code == "AUTH_INSUFFICIENT_SCOPE" {
                        return Err(Status::permission_denied("errors.auth.forbidden"));
                    }
                    if err.code.starts_with("VALIDATION") {
                        return Err(Status::invalid_argument(err.message));
                    }
                    return Err(Status::internal(format!("Erro no banco: {}", err.message)));
                }

                let corpo: serde_json::Value =
                    serde_json::from_slice(&resp.payload).unwrap_or_default();
                let etapa_atual_id = corpo
                    .get("etapa_atual_id")
                    .and_then(|v| v.as_i64())
                    .unwrap_or(0) as i32;

                // Mesmo canal do arrasto: para quem está olhando o quadro, o
                // cartão mudou de coluna — a origem da mudança é irrelevante.
                let mut bus_evento = self.bus.clone();
                let event_payload = serde_json::json!({
                    "event_type": "kanban.movido",
                    "tenant_id": tenant_uuid.to_string(),
                    "payload": {
                        "atendimento_id": inner.atendimento_id,
                        "etapa_destino_id": etapa_atual_id,
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

                Ok(Response::new(SetAtendimentoStatusResponse {
                    success: true,
                    status: inner.status,
                    etapa_atual_id,
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
        // A rota mais sensível do serviço: daqui sai mensagem para o telefone de
        // um cliente final, e não há desfazer. Até N13.3 ela exigia apenas sessão
        // válida — um `viewer` mandava mensagem em nome do negócio.
        exigir_escopo(&claims, &["atendimentos:write"], "SendOutboundMessage")?;
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

        // RBAC fino por fluxo (WS-5a). Esta rota era a única do grupo operacional
        // que saía com `flow_permissions` vazio: o `data_postgres` recebia um
        // envelope dizendo "este usuário não tem acesso a fluxo nenhum" e, na
        // prática, ou barrava atendente legítimo ou dependia do escopo largo para
        // salvar a chamada. Agora o campo é resolvido como nas outras seis rotas.
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
            method: "SendOutboundMessage".to_string(),
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
            // P1.1-B — Tratar Lagged sem derrubar o stream: avisa o cliente para
            // recarregar uma vez em vez de encerrar a conexão.
            loop {
                match broadcast_rx.recv().await {
                    Ok(ev) => {
                        if tx.send(Ok(ev)).await.is_err() {
                            break;
                        }
                    }
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(perdidos)) => {
                        tracing::warn!(
                            tenant_id = %tenant_uuid,
                            perdidos = perdidos,
                            "stream realtime defasado"
                        );
                        let aviso = contracts::grpc::queries::AtendimentoEvent {
                            event_type: "stream.defasado".into(),
                            tenant_id: tenant_uuid.to_string(),
                            payload: serde_json::json!({ "perdidos": perdidos }).to_string(),
                        };
                        if tx.send(Ok(aviso)).await.is_err() {
                            break;
                        }
                    }
                    Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
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
        // Convidar alguém é conceder acesso ao negócio: só `tenant:admin`
        // (a lista vazia significa exatamente isso — ver `rbac::autorizado`).
        exigir_escopo(&claims, crate::rbac::SOMENTE_ADMIN, "CreateInvite")?;
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

                // O convite está gravado. Mandar o e-mail é o passo que a v1
                // fazia e a v2 nunca fez: o link ficava só na tela de quem
                // convidou, e o convidado não recebia nada.
                //
                // Depois de gravar e sem poder falhar: se o SMTP estiver fora,
                // o link continua válido e visível. Recusar a criação por
                // causa do e-mail trocaria "avisar por outro caminho" por "não
                // conseguir convidar ninguém".
                if let Some(i) = invite {
                    self.enviar_convite_por_email(i, &claims.tenant_id).await;
                }

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
        exigir_escopo(&claims, crate::rbac::SOMENTE_ADMIN, "ListInvites")?;
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
        exigir_escopo(&claims, crate::rbac::SOMENTE_ADMIN, "RevokeInvite")?;
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

    /// N11 E8 — manda de novo o e-mail de um convite que não foi aceito.
    ///
    /// Renova a validade e reaproveita o link: quem perdeu o e-mail, deixou
    /// vencer ou achou no spam tarde demais recebe um convite que funciona, sem
    /// o admin ter de revogar, criar outro e reescolher as permissões.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ReenviarConvite", traceparent)
    )]
    async fn reenviar_convite(
        &self,
        req: Request<ReenviarConviteRequest>,
    ) -> Result<Response<ReenviarConviteResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        exigir_escopo(&claims, crate::rbac::SOMENTE_ADMIN, "ReenviarConvite")?;
        let traceparent = traceparent_do_metadata(&req);
        let user_agent = user_agent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;
        let invite_id = req.into_inner().invite_id;

        // Três por hora por convite: basta para quem errou de caixa de entrada,
        // e é pouco para transformar o botão num disparador contra alguém.
        if tentativas_na_janela(
            &self.deps,
            &traceparent,
            "reenviar_convite",
            &invite_id,
            60 * 60,
        )
        .await
        .is_some_and(|n| n > 3)
        {
            return Err(Status::resource_exhausted(
                "errors.convite.reenvio_limitado",
            ));
        }

        let env_req = Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent: traceparent.clone(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "ReenviarConvite".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({ "invite_id": invite_id }))
                .unwrap_or_default(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: claims.is_superuser,
            user_agent,
            ..Default::default()
        };

        let resp = self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
            .map_err(|e| Status::internal(format!("Falha no serviço interno: {e}")))?;
        if resp.kind == MessageKind::Error as i32 {
            return Err(status_do_erro_interno(resp.error));
        }
        let val: serde_json::Value =
            serde_json::from_slice(&resp.payload).map_err(|e| Status::internal(e.to_string()))?;
        let invite = val.get("invite").cloned().unwrap_or_default();

        // Mesmo caminho do convite novo — e a mesma falha aberta: o convite já
        // foi renovado, e o link continua valendo mesmo se o SMTP engasgar.
        self.enviar_convite_por_email(&invite, &claims.tenant_id)
            .await;

        Ok(Response::new(ReenviarConviteResponse {
            expires_at: invite
                .get("expires_at")
                .and_then(serde_json::Value::as_i64)
                .unwrap_or_default(),
        }))
    }

    /// B3 — "o que o agente fez": a atividade do próprio tenant.
    ///
    /// Só sessão válida aqui, sem escopo: o recorte entre "o tenant inteiro"
    /// (`tenant:admin`) e "só os meus agentes" (qualquer outra sessão) é do
    /// `data_postgres`, que força o filtro pelo escopo do envelope. Barrar na
    /// borda deixaria um `staff` sem ver o rastro do agente que ele mesmo
    /// autorizou.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListMyAuditLog", traceparent)
    )]
    async fn list_my_audit_log(
        &self,
        req: Request<ListMyAuditLogRequest>,
    ) -> Result<Response<ListMyAuditLogResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;
        let inner = req.into_inner();

        let env_req = Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent,
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "ListMyAuditLog".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({
                "origem": inner.origem,
                "grant_id": inner.grant_id,
                "desde": inner.desde,
                "limit": inner.limit,
                "offset": inner.offset,
                "evento_prefixo": inner.evento_prefixo,
            }))
            .unwrap_or_default(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: claims.is_superuser,
            ..Default::default()
        };

        let resp = self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
            .map_err(|e| Status::internal(format!("Falha no serviço interno: {e}")))?;
        if resp.kind == MessageKind::Error as i32 {
            return Err(status_do_erro_interno(resp.error));
        }
        let val: serde_json::Value =
            serde_json::from_slice(&resp.payload).map_err(|e| Status::internal(e.to_string()))?;

        let entries = val
            .get("entries")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .map(|item| {
                        let texto = |campo: &str| {
                            item.get(campo)
                                .and_then(|v| v.as_str())
                                .unwrap_or_default()
                                .to_string()
                        };
                        MyAuditLogEntry {
                            timestamp: item
                                .get("timestamp")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default(),
                            event_type: texto("event_type"),
                            origem: texto("origem"),
                            client_name: texto("client_name"),
                            tool: texto("tool"),
                            user_id: item
                                .get("user_id")
                                .and_then(|v| v.as_i64())
                                .unwrap_or_default() as i32,
                            user_nome: texto("user_nome"),
                            grant_id: texto("grant_id"),
                        }
                    })
                    .collect()
            })
            .unwrap_or_default();

        Ok(Response::new(ListMyAuditLogResponse { entries }))
    }

    /// Lista os aplicativos de IA que **este** usuário conectou por OAuth (N13.2).
    ///
    /// Sem escopo exigido além de sessão válida, e é de propósito: o grant é do
    /// usuário, não do tenant. O filtro por `user_id` acontece no repositório —
    /// um `tenant:admin` não vê com que agente o colega conectou, e um `viewer`
    /// vê os próprios.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "ListMcpGrants", traceparent)
    )]
    async fn list_mcp_grants(
        &self,
        req: Request<ListMcpGrantsRequest>,
    ) -> Result<Response<ListMcpGrantsResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;

        let env_req = Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent,
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "ListMcpGrants".to_string(),
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
                let grants = val
                    .get("grants")
                    .and_then(|v| v.as_array())
                    .map(|arr| {
                        arr.iter()
                            .map(|item| {
                                let texto = |campo: &str| {
                                    item.get(campo)
                                        .and_then(|v| v.as_str())
                                        .unwrap_or_default()
                                        .to_string()
                                };
                                McpGrantItem {
                                    id: texto("id"),
                                    client_id: texto("client_id"),
                                    client_name: texto("client_name"),
                                    redirect_uri: texto("redirect_uri"),
                                    scopes: json_strings(item.get("scopes")),
                                    last_used_at: item
                                        .get("last_used_at")
                                        .and_then(|v| v.as_i64())
                                        .unwrap_or_default(),
                                    created_at: item
                                        .get("created_at")
                                        .and_then(|v| v.as_i64())
                                        .unwrap_or_default(),
                                }
                            })
                            .collect()
                    })
                    .unwrap_or_default();
                Ok(Response::new(ListMcpGrantsResponse { grants }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    /// Desconecta um aplicativo de IA (N13.2/N13.8).
    ///
    /// A revogação corta o refresh token na hora; o access token em curso morre
    /// no `exp`. A resposta devolve essa janela em minutos para que a tela diga
    /// ao usuário a verdade — e não um número escrito à mão no Flutter que
    /// deixaria de bater no dia em que a configuração mudasse.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "RevokeMcpGrant", traceparent)
    )]
    async fn revoke_mcp_grant(
        &self,
        req: Request<RevokeMcpGrantRequest>,
    ) -> Result<Response<RevokeMcpGrantResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;
        let inner = req.into_inner();

        let env_req = Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent,
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "RevokeMcpGrant".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({
                "grant_id": inner.grant_id,
            }))
            .unwrap(),
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
                Ok(Response::new(RevokeMcpGrantResponse {
                    success: true,
                    janela_revogacao_min: janela_revogacao_min(),
                }))
            }
            Err(e) => Err(Status::internal(format!("Falha no serviço interno: {}", e))),
        }
    }

    /// B7 (doc 35-agentes F4) — reduz as permissões de um aplicativo conectado
    /// sem desconectá-lo.
    ///
    /// Como a revogação, só pede sessão: o grant é do próprio usuário, e o
    /// `data_postgres` filtra por ele. A resposta devolve em quantos minutos o
    /// agente sente a mudança — a do access token em curso, a mesma janela da
    /// revogação.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "AjustarEscoposMcpGrant", traceparent)
    )]
    async fn ajustar_escopos_mcp_grant(
        &self,
        req: Request<AjustarEscoposMcpGrantRequest>,
    ) -> Result<Response<AjustarEscoposMcpGrantResponse>, Status> {
        let claims = exigir_autenticado_do_metadata(&self.deps, &req).await?;
        let traceparent = traceparent_do_metadata(&req);
        let tenant_uuid = Uuid::parse_str(&claims.tenant_id)
            .map_err(|_| Status::invalid_argument("Invalid tenant UUID"))?;
        let inner = req.into_inner();

        let env_req = Envelope {
            tenant_id: tenant_uuid.to_string(),
            schema_version: 1,
            message_id: Uuid::now_v7().to_string(),
            causation_id: String::new(),
            traceparent,
            occurred_at: chrono::Utc::now().timestamp_millis(),
            kind: MessageKind::Request as i32,
            method: "AjustarEscoposMcpGrant".to_string(),
            payload: serde_json::to_vec(&serde_json::json!({
                "grant_id": inner.grant_id,
                "scopes": inner.scopes,
            }))
            .unwrap_or_default(),
            auth_user_id: claims.sub.parse::<i32>().unwrap_or(0),
            auth_scopes: claims.scopes.clone(),
            auth_is_superuser: claims.is_superuser,
            ..Default::default()
        };

        let resp = self
            .deps
            .pg
            .call(env_req, std::time::Duration::from_secs(5))
            .await
            .map_err(|e| Status::internal(format!("Falha no serviço interno: {e}")))?;
        if resp.kind == MessageKind::Error as i32 {
            return Err(status_do_erro_interno(resp.error));
        }
        let corpo: serde_json::Value =
            serde_json::from_slice(&resp.payload).unwrap_or_else(|_| serde_json::json!({}));

        Ok(Response::new(AjustarEscoposMcpGrantResponse {
            scopes: json_strings(corpo.get("scopes")),
            janela_min: janela_revogacao_min(),
        }))
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
        exigir_escopo(&claims, crate::rbac::SOMENTE_ADMIN, "ListTenantUsers")?;
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
        // Mudar cargo/permissão de alguém é evento crítico (08 §4.2).
        exigir_escopo(&claims, crate::rbac::SOMENTE_ADMIN, "UpdateTenantUser")?;
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
        exigir_escopo(&claims, &["configuracoes:read"], "GetMyTenantConfig")?;
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

    /// Paridade MCP — atualização parcial da configuração avançada do tenant.
    /// Só os campos presentes seguem no payload: é o que garante que um campo
    /// ausente não seja tocado no `data_postgres`.
    #[tracing::instrument(
        skip_all,
        fields(service = "runtime_api", rpc = "UpdateMyConfigAvancada", traceparent)
    )]
    async fn update_my_config_avancada(
        &self,
        req: Request<UpdateMyConfigAvancadaRequest>,
    ) -> Result<Response<SimpleOkResponse>, Status> {
        let inner = req.get_ref().clone();
        let mut payload = serde_json::Map::new();
        let mut por = |k: &str, v: serde_json::Value| {
            payload.insert(k.to_string(), v);
        };
        if let Some(v) = inner.entity_types_json {
            por("entity_types_json", v.into());
        }
        if !inner.prompts.is_empty() {
            por(
                "prompts",
                serde_json::Value::Array(
                    inner
                        .prompts
                        .iter()
                        .map(|p| serde_json::json!({ "chave": p.chave, "texto": p.texto }))
                        .collect(),
                ),
            );
        }
        for (k, v) in [
            ("brand_name", inner.brand_name),
            ("primary_color", inner.primary_color),
            ("secondary_color", inner.secondary_color),
            ("timezone", inner.timezone),
            ("language_code", inner.language_code),
            ("msg_pesquisa_satisfacao", inner.msg_pesquisa_satisfacao),
        ] {
            if let Some(v) = v {
                por(k, v.into());
            }
        }
        for (k, v) in [
            ("analise_previa_habilitada", inner.analise_previa_habilitada),
            ("pesquisa_satisfacao_ativa", inner.pesquisa_satisfacao_ativa),
            ("transcription_enabled", inner.transcription_enabled),
        ] {
            if let Some(v) = v {
                por(k, v.into());
            }
        }
        if let Some(m) = inner.minutos_inatividade_encerra {
            por("minutos_inatividade_encerra", m.into());
        }
        self.encaminhar_operacional(
            &req,
            "UpdateConfigAvancada",
            &["configuracoes:write"],
            serde_json::Value::Object(payload),
        )
        .await?;
        Ok(Response::new(SimpleOkResponse { sucesso: true }))
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
        exigir_escopo(&claims, &["configuracoes:write"], "UpdateMyTenantConfig")?;
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
            "confianca_minima_transferencia": inner.confianca_minima_transferencia,
            "confianca_minima_automatica": inner.confianca_minima_automatica,
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

/// Converte a etiqueta do JSON interno no tipo do contrato.
/// P5 — o resumo do atendimento vindo do `data_postgres`.
///
/// Extraída do `list_atendimentos`: o histórico do contato devolve exatamente
/// a mesma forma, e duplicar a conversão deixaria as duas telas divergirem no
/// primeiro campo novo.
fn atendimento_resumo_do_json(v: &serde_json::Value) -> ProtoAtendimentoResumo {
    ProtoAtendimentoResumo {
        id: v.get("id").and_then(|v| v.as_i64()).unwrap_or_default() as i32,
        contato_id: v
            .get("contato_id")
            .and_then(|v| v.as_i64())
            .unwrap_or_default() as i32,
        status: v
            .get("status")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string(),
        departamento_id: v
            .get("departamento_id")
            .and_then(|v| v.as_i64())
            .unwrap_or_default() as i32,
        fluxo_atendimento_id: v
            .get("fluxo_atendimento_id")
            .and_then(|v| v.as_i64())
            .unwrap_or_default() as i32,
        etapa_atual_id: v
            .get("etapa_atual_id")
            .and_then(|v| v.as_i64())
            .unwrap_or_default() as i32,
        assunto: v
            .get("assunto")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string(),
        prioridade: v
            .get("prioridade")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string(),
        atendente_humano_id: v
            .get("atendente_humano_id")
            .and_then(|v| v.as_i64())
            .unwrap_or_default() as i32,
        data_inicio: v
            .get("data_inicio")
            .and_then(|v| v.as_str())
            .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
            .map(|d| d.timestamp_millis())
            .unwrap_or_default(),
        data_ultima_mensagem: v
            .get("data_ultima_mensagem")
            .and_then(|v| v.as_str())
            .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
            .map(|d| d.timestamp_millis())
            .unwrap_or_default(),
        // Passagem direta (N6.5): sentimento vem pronto do
        // data_postgres; ausência/null viram None.
        sentimento_nota: v
            .get("sentimento_nota")
            .and_then(|v| v.as_i64())
            .map(|n| n as i32),
        sentimento_label: v
            .get("sentimento_label")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string()),
        nao_lidas: v
            .get("nao_lidas")
            .and_then(|v| v.as_i64())
            .unwrap_or_default() as i32,
        // P13 — o contato do cartão.
        contato_nome: texto_do(v, "contato_nome"),
        contato_telefone: texto_do(v, "contato_telefone"),
        contato_foto_url: texto_do(v, "contato_foto_url"),
        revisao_pendente: v
            .get("revisao_pendente")
            .and_then(|x| x.as_bool())
            .unwrap_or(false),
        ultima_mensagem: texto_do(v, "ultima_mensagem"),
        ultima_mensagem_tipo: texto_do(v, "ultima_mensagem_tipo"),
        ultima_mensagem_remetente: texto_do(v, "ultima_mensagem_remetente"),
        atendente_nome: texto_do(v, "atendente_nome"),
    }
}

/// Texto de um campo do JSON do `data_postgres`; ausente ou nulo vira "".
fn texto_do(v: &serde_json::Value, chave: &str) -> String {
    v.get(chave)
        .and_then(|x| x.as_str())
        .unwrap_or_default()
        .to_string()
}

/// A análise da IA da conversa, do JSON do `data_postgres` para o proto.
fn analise_do_json(v: &serde_json::Value) -> AnaliseDaConversa {
    let texto = |o: &serde_json::Value, k: &str| {
        o.get(k)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let numero = |o: &serde_json::Value, k: &str| o.get(k).and_then(|x| x.as_f64()).unwrap_or(0.0);
    let lista = |k: &str| {
        v.get(k)
            .and_then(|x| x.as_array())
            .cloned()
            .unwrap_or_default()
    };
    AnaliseDaConversa {
        intencoes: lista("intencoes")
            .iter()
            .map(|i| IntencaoDaConversa {
                tipo: texto(i, "tipo"),
                confianca: numero(i, "confianca"),
                vezes: i.get("vezes").and_then(|x| x.as_i64()).unwrap_or(0) as i32,
            })
            .collect(),
        entidades: lista("entidades")
            .iter()
            .map(|e| EntidadeDaConversa {
                tipo: texto(e, "tipo"),
                valor: texto(e, "valor"),
                confianca: numero(e, "confianca"),
            })
            .collect(),
        sentimento_label: texto(v, "sentimento_label"),
        sentimento_nota: v
            .get("sentimento_nota")
            .and_then(|x| x.as_i64())
            .unwrap_or(0) as i32,
        ultima_decisao: v.get("ultima_decisao").filter(|d| d.is_object()).map(|d| {
            DecisaoDaConversa {
                motor: texto(d, "motor"),
                ato: texto(d, "ato"),
                decisao: texto(d, "decisao"),
                motivo: texto(d, "motivo"),
                transferiu: d
                    .get("transferiu")
                    .and_then(|x| x.as_bool())
                    .unwrap_or(false),
                intencao: texto(d, "intencao"),
                criado_em: d.get("criado_em").and_then(|x| x.as_i64()).unwrap_or(0),
            }
        }),
    }
}

fn etiqueta_do_json(v: &serde_json::Value) -> ProtoEtiqueta {
    let texto = |chave: &str| {
        v.get(chave)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    ProtoEtiqueta {
        id: v.get("id").and_then(|x| x.as_i64()).unwrap_or(0),
        nome: texto("nome"),
        cor: texto("cor"),
        descricao: texto("descricao"),
        ativo: v.get("ativo").and_then(|x| x.as_bool()).unwrap_or(true),
        aplicada_pela_ia: v
            .get("aplicada_pela_ia")
            .and_then(|x| x.as_bool())
            .unwrap_or(false),
    }
}

/// Converte a nota do JSON interno no tipo do contrato.
fn nota_do_json(v: &serde_json::Value) -> ProtoNota {
    ProtoNota {
        id: v.get("id").and_then(|x| x.as_i64()).unwrap_or(0),
        texto: v
            .get("texto")
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string(),
        criado_em: v
            .get("criado_em")
            .and_then(|x| x.as_str())
            .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
            .map(|d| d.timestamp_millis())
            .unwrap_or(0),
    }
}

/// Converte a intenção do JSON interno no tipo do contrato.
fn intent_do_json(v: &serde_json::Value) -> MyIntent {
    let texto = |chave: &str| {
        v.get(chave)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    MyIntent {
        id: v.get("id").and_then(|x| x.as_i64()).unwrap_or(0) as i32,
        tag: texto("tag"),
        grupo: texto("grupo"),
        descricao: texto("descricao"),
        exemplo: texto("exemplo"),
        comportamento: texto("comportamento"),
        vetorizada: v
            .get("vetorizada")
            .and_then(|x| x.as_bool())
            .unwrap_or(false),
        criado_em: v.get("criado_em").and_then(|x| x.as_i64()).unwrap_or(0),
        atualizado_em: v.get("atualizado_em").and_then(|x| x.as_i64()).unwrap_or(0),
        campos_coleta: lista_de_textos(v, "campos_coleta"),
        max_perguntas: v.get("max_perguntas").and_then(|x| x.as_i64()).unwrap_or(2) as i32,
        apos_coleta: Some(texto("apos_coleta"))
            .filter(|a| !a.is_empty())
            .unwrap_or_else(|| "transferir".to_string()),
    }
}

/// Os três campos sem os quais a intenção não serve para nada.
///
/// `tag` + `descricao` + `exemplo` viram o vetor; `comportamento` é o que a IA
/// passa a fazer quando ele casa. Sem comportamento, casar não muda nada; sem
/// descrição, nunca casa.
fn validar_dados_intent(dados: &MyIntentDados) -> Result<(), Status> {
    if dados.tag.trim().is_empty() {
        return Err(Status::invalid_argument("informe a tag da intenção"));
    }
    if dados.descricao.trim().is_empty() {
        return Err(Status::invalid_argument(
            "descreva quando esta intenção se aplica",
        ));
    }
    if dados.comportamento.trim().is_empty() {
        return Err(Status::invalid_argument(
            "informe o que a IA deve fazer nesta intenção",
        ));
    }
    Ok(())
}

fn payload_intent(dados: &MyIntentDados) -> serde_json::Value {
    serde_json::json!({
        "tag": dados.tag.trim(),
        "grupo": dados.grupo.trim(),
        "descricao": dados.descricao.trim(),
        "exemplo": dados.exemplo.trim(),
        "comportamento": dados.comportamento.trim(),
        // Normalizados no data_postgres (campos aparados, 1..5, transferir |
        // continuar): a regra mora num lugar só.
        "campos_coleta": dados.campos_coleta,
        "max_perguntas": dados.max_perguntas,
        "apos_coleta": dados.apos_coleta,
    })
}

/// Converte o contato do JSON interno no tipo do contrato.
/// B10 (N11 E5) — os campos de um cliente como o `data_postgres` os lê.
fn dados_cliente_para_json(d: &DadosMyCliente) -> serde_json::Value {
    serde_json::json!({
        "nome_fantasia": d.nome_fantasia,
        "razao_social": d.razao_social,
        "tipo": d.tipo,
        "cnpj": d.cnpj,
        "cpf": d.cpf,
        "telefone": d.telefone,
        "site": d.site,
        "ramo_atividade": d.ramo_atividade,
        "observacoes": d.observacoes,
        "cep": d.cep,
        "logradouro": d.logradouro,
        "numero": d.numero,
        "complemento": d.complemento,
        "bairro": d.bairro,
        "cidade": d.cidade,
        "uf": d.uf,
    })
}

fn cliente_do_json(v: &serde_json::Value) -> MyCliente {
    let texto = |chave: &str| {
        v.get(chave)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    MyCliente {
        id: v.get("id").and_then(|x| x.as_i64()).unwrap_or(0) as i32,
        dados: Some(DadosMyCliente {
            nome_fantasia: texto("nome_fantasia"),
            razao_social: texto("razao_social"),
            tipo: texto("tipo"),
            cnpj: texto("cnpj"),
            cpf: texto("cpf"),
            telefone: texto("telefone"),
            site: texto("site"),
            ramo_atividade: texto("ramo_atividade"),
            observacoes: texto("observacoes"),
            cep: texto("cep"),
            logradouro: texto("logradouro"),
            numero: texto("numero"),
            complemento: texto("complemento"),
            bairro: texto("bairro"),
            cidade: texto("cidade"),
            uf: texto("uf"),
        }),
        ativo: v.get("ativo").and_then(|x| x.as_bool()).unwrap_or(false),
        contatos: v.get("contatos").and_then(|x| x.as_i64()).unwrap_or(0) as i32,
    }
}

fn contato_do_json(v: &serde_json::Value) -> MyContato {
    let texto = |chave: &str| {
        v.get(chave)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let data = |chave: &str| {
        v.get(chave)
            .and_then(|x| x.as_str())
            .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
            .map(|d| d.timestamp_millis())
            .unwrap_or(0)
    };
    MyContato {
        id: v.get("id").and_then(|x| x.as_i64()).unwrap_or(0) as i32,
        telefone: texto("telefone"),
        nome_contato: texto("nome_contato"),
        nome_perfil_whatsapp: texto("nome_perfil_whatsapp"),
        email: texto("email"),
        ativo: v.get("ativo").and_then(|x| x.as_bool()).unwrap_or(false),
        ultima_interacao: data("ultima_interacao"),
        cadastrado_em: data("data_cadastro"),
    }
}

/// Converte o fluxo do JSON interno no tipo do contrato.
///
/// Serve tanto para a lista (que traz as contagens) quanto para o retorno da
/// criação (que não traz): os campos ausentes viram 0, e a tela recarrega a
/// lista logo em seguida de qualquer forma.
fn fluxo_do_json(v: &serde_json::Value) -> MyFluxo {
    let texto = |chave: &str| {
        v.get(chave)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let numero = |chave: &str| v.get(chave).and_then(|x| x.as_i64()).unwrap_or(0) as i32;
    MyFluxo {
        id: numero("id"),
        departamento_id: numero("departamento_id"),
        departamento_nome: texto("departamento_nome"),
        nome: texto("nome"),
        descricao: texto("descricao"),
        ativo: v.get("ativo").and_then(|x| x.as_bool()).unwrap_or(false),
        etapas: numero("etapas"),
        atendimentos_abertos: numero("atendimentos_abertos"),
        criado_em: v
            .get("data_criacao")
            .and_then(|x| x.as_str())
            .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
            .map(|d| d.timestamp_millis())
            .unwrap_or(0),
    }
}

/// Converte a etapa do JSON interno no tipo do contrato.
fn etapa_do_json(v: &serde_json::Value) -> MyEtapaFluxo {
    let texto = |chave: &str| {
        v.get(chave)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let numero = |chave: &str| v.get(chave).and_then(|x| x.as_i64()).unwrap_or(0) as i32;
    MyEtapaFluxo {
        id: numero("id"),
        fluxo_id: numero("fluxo_id"),
        nome: texto("nome"),
        descricao: texto("descricao"),
        ordem: numero("ordem"),
        cor: texto("cor"),
        tipo_etapa: texto("tipo_etapa"),
        ativo: v.get("ativo").and_then(|x| x.as_bool()).unwrap_or(false),
    }
}

/// Converte o departamento do JSON interno no tipo do contrato.
fn departamento_do_json(v: &serde_json::Value) -> MyDepartamento {
    let texto = |chave: &str| {
        v.get(chave)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    MyDepartamento {
        id: v.get("id").and_then(|x| x.as_i64()).unwrap_or(0) as i32,
        nome: texto("nome"),
        slug: texto("slug"),
        descricao: texto("descricao"),
        ativo: v.get("ativo").and_then(|x| x.as_bool()).unwrap_or(false),
        criado_em: v
            .get("data_criacao")
            .and_then(|x| x.as_str())
            .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
            .map(|d| d.timestamp_millis())
            .unwrap_or(0),
    }
}

/// Converte o atendente do JSON interno no tipo do contrato.
fn atendente_do_json(v: &serde_json::Value) -> MyAtendente {
    let texto = |chave: &str| {
        v.get(chave)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    MyAtendente {
        id: v.get("id").and_then(|x| x.as_i64()).unwrap_or(0) as i32,
        nome: texto("nome"),
        email: texto("email"),
        cargo: texto("cargo"),
        // Ausente = sem departamento; 0 é o "nenhum" do contrato.
        departamento_id: v
            .get("departamento_id")
            .and_then(|x| x.as_i64())
            .unwrap_or(0) as i32,
        ativo: v.get("ativo").and_then(|x| x.as_bool()).unwrap_or(false),
        disponivel: v
            .get("disponivel")
            .and_then(|x| x.as_bool())
            .unwrap_or(false),
        max_atendimentos_simultaneos: v
            .get("max_atendimentos_simultaneos")
            .and_then(|x| x.as_i64())
            .unwrap_or(0) as i32,
        fluxo_id: v.get("fluxo_id").and_then(|x| x.as_i64()).unwrap_or(0) as i32,
    }
}

/// Converte a instância de WhatsApp do JSON interno no tipo do contrato.
fn instancia_do_json(v: &serde_json::Value) -> MyWhatsappInstance {
    let texto = |chave: &str| {
        v.get(chave)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    MyWhatsappInstance {
        id: v.get("id").and_then(|x| x.as_i64()).unwrap_or(0) as i32,
        name: texto("name"),
        phone_number: texto("phone_number"),
        connection_state: texto("connection_state"),
        active: v.get("active").and_then(|x| x.as_bool()).unwrap_or(false),
        provider: texto("provider"),
        created_at: v
            .get("created_at")
            .and_then(|x| x.as_str())
            .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
            .map(|d| d.timestamp_millis())
            .unwrap_or(0),
        // Ausente resolve para `true`: a coluna nasce TRUE, e um
        // `data_postgres` defasado nao pode fazer a tela mostrar "bot
        // desligado" numa conexao que esta respondendo normalmente.
        resposta_bot: v
            .get("resposta_bot")
            .and_then(|x| x.as_bool())
            .unwrap_or(true),
        // P7 — preenchidos depois, pela consulta do departamento: a listagem do
        // banco não os traz. 0/"" = sem departamento, que é o padrão.
        departamento_id: v
            .get("departamento_id")
            .and_then(|x| x.as_i64())
            .unwrap_or(0) as i32,
        departamento_nome: v
            .get("departamento_nome")
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string(),
    }
}

/// P9 — a linha de dead-letter no tipo do contrato.
fn nao_entregue_do_json(v: &serde_json::Value) -> MensagemNaoEntregue {
    let texto = |chave: &str| {
        v.get(chave)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let inteiro = |chave: &str| v.get(chave).and_then(|x| x.as_i64()).unwrap_or(0) as i32;
    MensagemNaoEntregue {
        id: inteiro("id"),
        mensagem_id: inteiro("mensagem_id"),
        atendimento_id: inteiro("atendimento_id"),
        motivo: texto("motivo"),
        criado_em: v
            .get("criado_em")
            .and_then(|x| x.as_str())
            .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
            .map(|d| d.timestamp_millis())
            .unwrap_or(0),
        trecho: texto("trecho"),
        contato: texto("contato"),
    }
}

/// P8 — as reações gravadas em `metadados.reacoes`.
///
/// Silenciosamente vazio quando o formato não é o esperado: uma linha antiga com
/// `metadados` escrito por outra coisa não pode derrubar a conversa inteira.
/// Emoji vazio também sai: no provedor ele significa "desfiz a reação".
fn reacoes_do_item(item: &serde_json::Value) -> Vec<ReacaoDaMensagem> {
    item.get("metadados")
        .and_then(|m| m.get("reacoes"))
        .and_then(|r| r.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|r| {
                    let emoji = r.get("emoji").and_then(|e| e.as_str())?;
                    if emoji.is_empty() {
                        return None;
                    }
                    Some(ReacaoDaMensagem {
                        emoji: emoji.to_string(),
                        de: r
                            .get("de")
                            .and_then(|d| d.as_str())
                            .unwrap_or("contato")
                            .to_string(),
                    })
                })
                .collect()
        })
        .unwrap_or_default()
}

/// P8 — o resto de `metadados`, como JSON cru, para a tela desenhar enquete,
/// lista e botões.
///
/// `reacoes` sai daqui: já viaja em campo próprio, e mandá-lo duas vezes faria
/// a tela ter duas fontes para a mesma coisa. Objeto vazio vira `None` — não há
/// por que mandar `{}` em toda mensagem de texto da conversa.
fn metadados_do_item(item: &serde_json::Value) -> Option<String> {
    let mut obj = item.get("metadados")?.as_object()?.clone();
    obj.remove("reacoes");
    if obj.is_empty() {
        return None;
    }
    serde_json::to_string(&obj).ok()
}

/// P7 — a linha do banco (`whatsapp_whitelist`) no tipo do contrato.
///
/// Os nomes divergem de propósito: no banco a tabela ainda se chama
/// `whitelist`, herança da v1; no contrato ela é o que faz — número ignorado.
fn numero_ignorado_do_json(v: &serde_json::Value) -> MyNumeroIgnorado {
    MyNumeroIgnorado {
        id: v.get("id").and_then(|x| x.as_i64()).unwrap_or(0) as i32,
        nome: v
            .get("name")
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string(),
        telefone: v
            .get("phone_number")
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string(),
        ativo: v.get("active").and_then(|x| x.as_bool()).unwrap_or(false),
        criado_em: v
            .get("created_at")
            .and_then(|x| x.as_str())
            .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
            .map(|d| d.timestamp_millis())
            .unwrap_or(0),
    }
}

/// Converte o JSON do `data_postgres` no tipo do contrato.
///
/// Campo ausente vira o default do proto3 — o cliente não distingue "ausente"
/// de "vazio", e um opcional a mais aqui só daria trabalho a quem consome.
fn treinamento_do_json(v: &serde_json::Value) -> MyTreinamento {
    let texto = |chave: &str| {
        v.get(chave)
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    let inteiro = |chave: &str| v.get(chave).and_then(|x| x.as_i64()).unwrap_or(0);
    let logico = |chave: &str| v.get(chave).and_then(|x| x.as_bool()).unwrap_or(false);

    MyTreinamento {
        id: inteiro("id") as i32,
        tag: texto("tag"),
        grupo: texto("grupo"),
        conteudo: texto("conteudo"),
        finalizado: logico("finalizado"),
        vetorizado: logico("vetorizado"),
        criado_em: inteiro("criado_em"),
        atualizado_em: inteiro("atualizado_em"),
        arquivo_nome: texto("arquivo_nome"),
        extracao_status: texto("extracao_status"),
        extracao_erro: texto("extracao_erro"),
    }
}

/// B9 (N10 E5) — o formato do arquivo de treinamento, se é um dos que a extração
/// lê. Os binários antigos do Office ficam de fora com uma saída explícita.
fn formato_de_treinamento(mimetype: &str, nome: &str) -> Result<&'static str, &'static str> {
    let base = mimetype
        .split(';')
        .next()
        .unwrap_or_default()
        .trim()
        .to_ascii_lowercase();
    let nome = nome.to_ascii_lowercase();
    let por_mimetype = match base.as_str() {
        "application/pdf" => Some("pdf"),
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => Some("docx"),
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => Some("xlsx"),
        "text/plain" => Some("txt"),
        "text/csv" => Some("csv"),
        _ => None,
    };
    if let Some(formato) = por_mimetype {
        return Ok(formato);
    }
    if base == "application/msword"
        || base == "application/vnd.ms-excel"
        || nome.ends_with(".doc")
        || nome.ends_with(".xls")
    {
        return Err("arquivos .doc e .xls não são lidos; salve como .docx ou .xlsx");
    }
    Err("formato não suportado; envie pdf, docx, xlsx, txt ou csv")
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

    // Provedores de pagamento habilitados nesta instalação. Hoje só o voucher;
    // um gateway entra aqui e aparece sozinho na tela de pagamento do cadastro.
    // Cliente próprio para o `data_postgres` — `MuxClient` não é clonável.
    let pg_pagamento = transport::conectar_cliente("data_postgres").await?;
    let provedores = application::pagamento::RegistroProvedores::novo(vec![Arc::new(
        application::pagamento::voucher::ProvedorVoucher::novo(pg_pagamento),
    )]);
    let facade_onboarding =
        contracts::grpc::queries::onboarding_service_server::OnboardingServiceServer::new(
            crate::onboarding_web::OnboardingFacade::new(deps.clone(), provedores.clone()),
        );

    let whatsapp = transport::conectar_cliente("data_whatsapp").await?;

    // Mesmo endpoint e mesma resiliência do worker — a crate `ia_client` é
    // compartilhada. `connect_lazy` não bloqueia o boot: uma falha de
    // conectividade só aparece na primeira chamada real, e a única coisa que
    // depende disto aqui é o ensaio de pergunta.
    let ia_endpoint = std::env::var("SMARTCORE_IA_ENGINE_ENDPOINT")
        .unwrap_or_else(|_| "http://127.0.0.1:50060".to_string());
    let ia: Arc<dyn ia_client::IaEngineClient> = Arc::new(ia_client::ResilientIaEngine::new(
        ia_client::TonicIaEngineClient::connect_lazy(&ia_endpoint)?,
    ));

    // Plano ia-engine-jev — o motor Jev, opcional: teste de regra e ensaio de
    // pergunta de quem está no motor Jev ou na sombra.
    let ia_jev: Option<Arc<dyn ia_client::IaEngineClient>> =
        match std::env::var("SMARTCORE_IA_ENGINE_JEV_ENDPOINT") {
            Ok(endpoint) if !endpoint.trim().is_empty() => {
                Some(Arc::new(ia_client::ResilientIaEngine::new(
                    ia_client::TonicIaEngineClient::connect_lazy(endpoint.trim())?,
                )))
            }
            _ => None,
        };

    let facade_admin = AdminServiceServer::new(
        AdminFacade::new(
            deps,
            bus,
            control,
            realtime,
            whatsapp,
            ia,
            provedores.clone(),
        )
        .com_ia_jev(ia_jev),
    );

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
        // Origem da requisição para a trilha de auditoria (ver `CamadaOrigem`).
        .layer(CamadaOrigem)
        .add_service(facade_auth)
        .add_service(facade_onboarding)
        .add_service(facade_admin)
        .serve(addr)
        .await?;
    Ok(())
}

/// Um campo do catálogo, do JSON do `data_postgres` para o protobuf.
fn campo_do_json(v: &serde_json::Value) -> MyCampoPersonalizado {
    let texto = |k: &str| {
        v.get(k)
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default()
            .to_string()
    };
    let flag = |k: &str| {
        v.get(k)
            .and_then(serde_json::Value::as_bool)
            .unwrap_or(false)
    };

    MyCampoPersonalizado {
        id: v.get("id").and_then(serde_json::Value::as_i64).unwrap_or(0),
        slug: texto("slug"),
        nome: texto("nome"),
        descricao: texto("descricao"),
        escopo: texto("escopo"),
        fluxo_id: v
            .get("fluxo_id")
            .and_then(serde_json::Value::as_i64)
            .map(|n| n as i32),
        tipo: texto("tipo"),
        opcoes: v
            .get("opcoes")
            .and_then(serde_json::Value::as_array)
            .map(|arr| {
                arr.iter()
                    .map(|o| OpcaoCampo {
                        id: o
                            .get("id")
                            .and_then(serde_json::Value::as_str)
                            .unwrap_or_default()
                            .to_string(),
                        rotulo: o
                            .get("rotulo")
                            .and_then(serde_json::Value::as_str)
                            .unwrap_or_default()
                            .to_string(),
                    })
                    .collect()
            })
            .unwrap_or_default(),
        obrigatorio: flag("obrigatorio"),
        extrair_automaticamente: flag("extrair_automaticamente"),
        extrair_hint: texto("extrair_hint"),
        mostrar_no_card: flag("mostrar_no_card"),
        ordem: v
            .get("ordem")
            .and_then(serde_json::Value::as_i64)
            .unwrap_or(0) as i32,
        ativo: flag("ativo"),
    }
}

/// As opções de um campo de lista, do protobuf para o JSON do banco.
fn opcoes_para_json(opcoes: &[OpcaoCampo]) -> serde_json::Value {
    serde_json::Value::Array(
        opcoes
            .iter()
            .map(|o| serde_json::json!({ "id": o.id, "rotulo": o.rotulo }))
            .collect(),
    )
}

/// Um campo do cartão na ficha de um atendimento.
fn valor_campo_do_json(v: &serde_json::Value) -> ValorCampoDoAtendimento {
    let texto = |k: &str| {
        v.get(k)
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default()
            .to_string()
    };
    ValorCampoDoAtendimento {
        campo_id: v
            .get("campo_id")
            .and_then(serde_json::Value::as_i64)
            .unwrap_or(0),
        slug: texto("slug"),
        nome: texto("nome"),
        descricao: texto("descricao"),
        tipo: texto("tipo"),
        opcoes: v
            .get("opcoes")
            .and_then(serde_json::Value::as_array)
            .map(|arr| {
                arr.iter()
                    .map(|o| OpcaoCampo {
                        id: o
                            .get("id")
                            .and_then(serde_json::Value::as_str)
                            .unwrap_or_default()
                            .to_string(),
                        rotulo: o
                            .get("rotulo")
                            .and_then(serde_json::Value::as_str)
                            .unwrap_or_default()
                            .to_string(),
                    })
                    .collect()
            })
            .unwrap_or_default(),
        obrigatorio: v
            .get("obrigatorio")
            .and_then(serde_json::Value::as_bool)
            .unwrap_or(false),
        valor_json: texto("valor_json"),
        origem: texto("origem"),
        confianca: v
            .get("confianca")
            .and_then(serde_json::Value::as_f64)
            .unwrap_or(0.0),
        editado_por_humano: v
            .get("editado_por_humano")
            .and_then(serde_json::Value::as_bool)
            .unwrap_or(false),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tonic::Request;

    /// O link do convite sai daqui e vai para dentro de um e-mail: uma barra a
    /// mais ou a menos produz um endereço que não abre, e quem recebe não tem
    /// como consertar.
    ///
    /// `#[serial]` não existe aqui; as duas checagens ficam num teste só para
    /// não disputarem a variável de ambiente com outro em paralelo.
    #[test]
    fn base_publica_normaliza_a_barra_final() {
        let anterior = std::env::var("APP_PUBLIC_URL").ok();

        std::env::set_var("APP_PUBLIC_URL", "https://dev.exemplo.com.br/");
        assert_eq!(base_publica_do_app(), "https://dev.exemplo.com.br");

        std::env::set_var("APP_PUBLIC_URL", "https://dev.exemplo.com.br");
        assert_eq!(base_publica_do_app(), "https://dev.exemplo.com.br");

        std::env::remove_var("APP_PUBLIC_URL");
        assert_eq!(
            base_publica_do_app(),
            // Com o caminho base: o app não vive na raiz, e o domínio sozinho
            // devolve 400.
            "https://smartcoreassistant.com.br/v2/tenant",
            "sem configuração o padrão tem de ser produção: um convite com link \
             errado é pior calado do que barulhento"
        );

        if let Some(v) = anterior {
            std::env::set_var("APP_PUBLIC_URL", v);
        }
    }

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
    fn user_agent_do_metadata_prefere_a_origem_declarada_pelo_agente() {
        // O gRPC sobrescreve o `user-agent`; a tool vem no header próprio.
        let mut req = Request::new(LogoutRequest {
            refresh_token: String::new(),
        });
        req.metadata_mut().insert(
            "user-agent",
            "grpc-python-asyncio/1.83.1 grpc-c/56.0.0".parse().unwrap(),
        );
        req.metadata_mut().insert(
            "x-smartcore-agente",
            "SmartCoreAssistant-MCP/remover_nota (grant g-1)"
                .parse()
                .unwrap(),
        );
        assert_eq!(
            user_agent_do_metadata(&req),
            "SmartCoreAssistant-MCP/remover_nota (grant g-1)"
        );
    }

    #[test]
    fn user_agent_do_metadata_ignora_origem_fora_do_formato() {
        // Qualquer outro valor no header não substitui o user-agent real.
        let mut req = Request::new(LogoutRequest {
            refresh_token: String::new(),
        });
        req.metadata_mut()
            .insert("user-agent", "Mozilla/5.0 Flutter".parse().unwrap());
        req.metadata_mut()
            .insert("x-smartcore-agente", "qualquer-coisa".parse().unwrap());
        assert_eq!(user_agent_do_metadata(&req), "Mozilla/5.0 Flutter");
    }

    #[test]
    fn origem_dos_headers_segue_a_mesma_regra_do_metadata() {
        let mut h = http::HeaderMap::new();
        h.insert("user-agent", "grpc-python-asyncio/1.83.1".parse().unwrap());
        h.insert(
            "x-smartcore-agente",
            "SmartCoreAssistant-MCP/set_atendimento_status (grant g)"
                .parse()
                .unwrap(),
        );
        assert_eq!(
            origem_dos_headers(&h),
            "SmartCoreAssistant-MCP/set_atendimento_status (grant g)"
        );

        let mut so_navegador = http::HeaderMap::new();
        so_navegador.insert("user-agent", "Mozilla/5.0 Flutter".parse().unwrap());
        assert_eq!(origem_dos_headers(&so_navegador), "Mozilla/5.0 Flutter");
        assert_eq!(origem_dos_headers(&http::HeaderMap::new()), "");
    }

    #[tokio::test]
    async fn camada_origem_disponibiliza_a_origem_ao_handler() {
        use tower::{Layer, Service};

        let interno = tower::service_fn(|_req: http::Request<()>| async {
            Ok::<_, std::convert::Infallible>(transport::origem::origem_atual())
        });
        let mut servico = CamadaOrigem.layer(interno);
        let req = http::Request::builder()
            .header(
                "x-smartcore-agente",
                "SmartCoreAssistant-MCP/arquivar (grant g)",
            )
            .body(())
            .unwrap();

        let origem = servico.call(req).await.unwrap();

        assert_eq!(
            origem.as_deref(),
            Some("SmartCoreAssistant-MCP/arquivar (grant g)")
        );
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
    fn exigir_escopo_aceita_superuser_tenant_admin_e_coringa() {
        // Superusuário passa mesmo sem escopo explícito.
        assert!(exigir_escopo(&claims_com(&[], true), &["operacional:admin"], "R").is_ok());
        // `tenant:admin` implica qualquer escopo (doc 09 §3).
        assert!(exigir_escopo(
            &claims_com(&["tenant:admin"], false),
            &["treinamento:write"],
            "R"
        )
        .is_ok());
        // Coringa de superusuário `*` passa.
        assert!(exigir_escopo(&claims_com(&["*"], false), &["configuracoes:write"], "R").is_ok());
    }

    #[test]
    fn exigir_escopo_aceita_quem_tem_o_escopo_pedido() {
        assert!(exigir_escopo(
            &claims_com(&["treinamento:read"], false),
            &["treinamento:read"],
            "R"
        )
        .is_ok());
    }

    #[test]
    fn exigir_escopo_nega_quem_nao_tem() {
        let err = exigir_escopo(
            &claims_com(&["atendimentos:read"], false),
            &["configuracoes:write"],
            "UpdateMyTenantConfig",
        )
        .unwrap_err();
        assert_eq!(err.code(), tonic::Code::PermissionDenied);
        assert_eq!(err.message(), "errors.auth.forbidden");
    }

    #[test]
    fn fluxos_para_o_responder_segue_a_convencao_do_worker() {
        let resp = serde_json::json!({ "fluxos": [
            { "id": 301, "setor": "Comercial", "descricao": "", "nome": "Atendimento - Paulo" },
            { "id": 300, "setor": "Atendimento", "descricao": "Triagem", "nome": "Inicial" },
            { "setor": "sem id" },
        ]});
        assert_eq!(
            fluxos_para_o_responder(&resp),
            vec![
                (
                    "Comercial - Atendimento - Paulo".to_string(),
                    "301".to_string()
                ),
                ("Atendimento - Triagem".to_string(), "300".to_string()),
            ]
        );
        assert!(fluxos_para_o_responder(&serde_json::json!({})).is_empty());
    }

    #[test]
    fn exigir_escopo_de_rota_nega_rota_nao_declarada() {
        // Fail-closed: uma rota nova que ninguém declarou no mapa é negada, e
        // não liberada por omissão.
        let err = exigir_escopo_de_rota(&claims_com(&["tenant:admin"], false), "RotaInexistente")
            .unwrap_err();
        assert_eq!(err.code(), tonic::Code::PermissionDenied);
    }

    #[test]
    fn exigir_escopo_de_rota_libera_manager_em_fluxo() {
        // O caso concreto que a fase N13.3 conserta: antes, `encaminhar_tenant`
        // exigia `tenant:admin` e um manager não editava fluxo nenhum.
        assert!(
            exigir_escopo_de_rota(&claims_com(&["kanban:admin"], false), "UpdateFluxo").is_ok()
        );
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
            // Os testes desta fachada não exercitam o caminho de mídia; sem
            // storage, ele responde `unavailable` em vez de exigir o serviço.
            storage: None,
        });
        let control = stub_rpc(&format!("tcp://127.0.0.1:{}", porta_base + 2)).await;
        let whatsapp = stub_rpc(&format!("tcp://127.0.0.1:{}", porta_base + 3)).await;
        // Bus, realtime e whatsapp só são tocados DEPOIS da autenticação — nenhum
        // teste daqui chega neles. O `RealtimeManager` nem abre conexão no
        // construtor.
        AdminFacade::new(
            deps,
            bus_stub().await,
            control,
            crate::realtime::RealtimeManager::new("redis://127.0.0.1:63799").unwrap(),
            whatsapp,
            // A IA só é tocada pelo ensaio de pergunta, que nenhum teste daqui
            // exercita; o mock sem expectativa basta para construir a fachada.
            Arc::new(ia_client::MockIaEngineClient::new()),
            // Registro vazio: os testes de autorização param antes do provedor.
            // Um id desconhecido devolve o mesmo erro de validação que um
            // registro cheio devolveria para um provedor inexistente.
            application::pagamento::RegistroProvedores::default(),
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
            "GetWindowsDownloadLink" => facade.get_windows_download_link(Request::new(GetWindowsDownloadLinkRequest::default())).await,
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
            "GetMyOnboardingProgress" => facade.get_my_onboarding_progress(Request::new(GetMyOnboardingProgressRequest::default())).await,
            // Operação financeira: a barreira aqui vale mais que nas demais.
            "QuitarMinhaAssinatura" => facade.quitar_minha_assinatura(Request::new(QuitarMinhaAssinaturaRequest::default())).await,
            "DefinirRespostaBotInstancia" => facade.definir_resposta_bot_instancia(Request::new(DefinirRespostaBotInstanciaRequest { id: 1, habilitado: false })).await,
            "DefinirBotDaConversa" => facade.definir_bot_da_conversa(Request::new(DefinirBotDaConversaRequest { atendimento_id: 1, habilitado: true })).await,
            "MarcarAtendimentoLido" => facade.marcar_atendimento_lido(Request::new(MarcarAtendimentoLidoRequest { atendimento_id: 1 })).await,
            "AjustarEscoposMcpGrant" => facade.ajustar_escopos_mcp_grant(Request::new(AjustarEscoposMcpGrantRequest { grant_id: String::new(), scopes: vec![] })).await,
            "RegistrarFeedbackTeste" => facade.registrar_feedback_teste(Request::new(RegistrarFeedbackTesteRequest::default())).await,
            "SolicitarUploadTreinamento" => facade.solicitar_upload_treinamento(Request::new(SolicitarUploadTreinamentoRequest::default())).await,
            "CreateMyTreinamentoComArquivo" => facade.create_my_treinamento_com_arquivo(Request::new(CreateMyTreinamentoComArquivoRequest::default())).await,
            "ListMyClientes" => facade.list_my_clientes(Request::new(ListMyClientesRequest::default())).await,
            "CreateMyCliente" => facade.create_my_cliente(Request::new(CreateMyClienteRequest::default())).await,
            "UpdateMyCliente" => facade.update_my_cliente(Request::new(UpdateMyClienteRequest::default())).await,
            "DefinirMyClienteAtivo" => facade.definir_my_cliente_ativo(Request::new(DefinirMyClienteAtivoRequest::default())).await,
            "ListMyContatosDoCliente" => facade.list_my_contatos_do_cliente(Request::new(MyClienteIdRequest::default())).await,
            "VincularMyContatoCliente" => facade.vincular_my_contato_cliente(Request::new(VincularMyContatoClienteRequest::default())).await,
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

    // -----------------------------------------------------------------------
    // P6 — foto do contato no R2
    // -----------------------------------------------------------------------

    #[test]
    fn precisa_sincronizar_foto_respeita_prazo_e_piso_do_forcar() {
        let horas = chrono::Duration::hours;
        let minutos = chrono::Duration::minutes;
        // Nunca verificada: sempre sincroniza.
        assert!(precisa_sincronizar_foto(None, false));
        assert!(precisa_sincronizar_foto(None, true));
        // Dentro dos 7 dias: não sincroniza sem `forcar`.
        assert!(!precisa_sincronizar_foto(Some(horas(24)), false));
        assert!(precisa_sincronizar_foto(
            Some(chrono::Duration::days(8)),
            false
        ));
        // `forcar` respeita o piso de 10 minutos.
        assert!(!precisa_sincronizar_foto(Some(minutos(5)), true));
        assert!(precisa_sincronizar_foto(Some(minutos(11)), true));
    }

    #[test]
    fn chave_de_foto_aceita_so_chave_do_r2() {
        assert_eq!(
            chave_de_foto(" contatos/7/avatar-0a1b2c3d.jpg "),
            Some("contatos/7/avatar-0a1b2c3d.jpg")
        );
        assert_eq!(chave_de_foto(""), None);
        // Valor legado (URL do CDN) nunca é assinado nem devolvido.
        assert_eq!(chave_de_foto("https://pps.whatsapp.net/v/t61/x.jpg"), None);
        assert_eq!(chave_de_foto("contatos/https://evil"), None);
    }

    #[test]
    fn origem_da_foto_distingue_agendada_r2_e_cache() {
        assert_eq!(origem_da_foto(true, true), "agendada");
        assert_eq!(origem_da_foto(true, false), "agendada");
        assert_eq!(origem_da_foto(false, true), "r2");
        assert_eq!(origem_da_foto(false, false), "cache");
    }

    /// P6 — `ObterContatoDoAtendimento` responde com a foto do R2 assinada por
    /// 3600 s e, com a verificação vencida, só agenda a sincronização: o
    /// `data_whatsapp` (provedor) não recebe NENHUMA chamada no caminho da
    /// requisição.
    #[tokio::test]
    async fn obter_contato_nao_chama_o_provedor_e_assina_a_foto_do_r2() {
        use std::sync::atomic::{AtomicUsize, Ordering};
        use transport::runtime::{Endpoint, Server};

        let _ =
            application::jwt::inicializar_chaves("segredo_de_teste_de_pelo_menos_32_bytes_longo");
        let addr = |i: u16| format!("tcp://127.0.0.1:{}", 29470 + i);
        let resposta = |env: Envelope, corpo: serde_json::Value| Envelope {
            kind: MessageKind::Reply as i32,
            payload: serde_json::to_vec(&corpo).unwrap(),
            ..env
        };

        // data_postgres: o contato com a chave do R2 e a verificação nunca feita.
        let pg = Server::new(Endpoint::parse(&addr(0)).unwrap(), "flatbuffers").route(
            "ContatoDoAtendimento",
            move |env| {
                Box::pin(async move {
                    resposta(
                        env,
                        serde_json::json!({
                            "contato_id": 7,
                            "nome": "Maria",
                            "telefone": "5511999998888",
                            "foto_chave": "contatos/7/avatar-0a1b2c3d.jpg",
                            "foto_verificada_em": null,
                        }),
                    )
                })
            },
        );
        // data_redis: o token não está na blocklist.
        let rd = Server::new(Endpoint::parse(&addr(1)).unwrap(), "flatbuffers").route(
            "IsTokenBlocked",
            move |env| {
                Box::pin(async move { resposta(env, serde_json::json!({ "blocked": false })) })
            },
        );
        // data_whatsapp: qualquer chamada aqui seria o provedor no caminho da requisição.
        let chamadas_provedor = Arc::new(AtomicUsize::new(0));
        let (c1, c2) = (chamadas_provedor.clone(), chamadas_provedor.clone());
        let wa = Server::new(Endpoint::parse(&addr(2)).unwrap(), "flatbuffers")
            .route("GetWhatsappProfilePicture", move |env| {
                c1.fetch_add(1, Ordering::SeqCst);
                Box::pin(async move { resposta(env, serde_json::json!({ "url": null })) })
            })
            .route("BaixarFotoDoContato", move |env| {
                c2.fetch_add(1, Ordering::SeqCst);
                Box::pin(async move { resposta(env, serde_json::json!({ "sem_foto": true })) })
            });
        // data_storage: assina o lote; o TTL volta na URL para o teste conferir.
        let st = Server::new(Endpoint::parse(&addr(3)).unwrap(), "flatbuffers").route(
            "PresignFiles",
            move |env| {
                Box::pin(async move {
                    let p: serde_json::Value =
                        serde_json::from_slice(&env.payload).unwrap_or_default();
                    let ttl = p["expires_in"].as_u64().unwrap_or(0);
                    let urls: Vec<serde_json::Value> = p["itens"]
                        .as_array()
                        .into_iter()
                        .flatten()
                        .map(|i| {
                            serde_json::json!({
                                "file_name": i["file_name"],
                                "url": format!("https://r2.example/avatar?ttl={ttl}"),
                            })
                        })
                        .collect();
                    resposta(env, serde_json::json!({ "urls": urls }))
                })
            },
        );
        for servidor in [pg, rd, wa, st] {
            tokio::spawn(async move {
                let _ = servidor.run().await;
            });
        }
        tokio::time::sleep(std::time::Duration::from_millis(150)).await;

        let cliente = |i: u16| async move {
            transport::MuxClient::conectar(
                Endpoint::parse(&addr(i)).unwrap(),
                Box::new(transport::codec::FlatbuffersCodec),
            )
            .await
            .unwrap()
        };
        let deps = Arc::new(AuthDeps {
            pg: cliente(0).await,
            redis: cliente(1).await,
            access_ttl_s: 900,
            refresh_ttl_s: 604_800,
            login_rate_max: 5,
            login_rate_window_s: 300,
            storage: Some(cliente(3).await),
        });
        let facade = AdminFacade::new(
            deps,
            bus_stub().await,
            stub_rpc(&addr(4)).await,
            crate::realtime::RealtimeManager::new("redis://127.0.0.1:63799").unwrap(),
            cliente(2).await,
            Arc::new(ia_client::MockIaEngineClient::new()),
            application::pagamento::RegistroProvedores::default(),
        );

        let agora = chrono::Utc::now().timestamp();
        let token = application::jwt::gerar_access_token(&application::jwt::Claims {
            sub: "1".to_string(),
            tenant_id: Uuid::new_v4().to_string(),
            scopes: vec!["atendimentos:read".to_string()],
            // Superusuário só para pular a resolução de permissões por fluxo,
            // que não é o assunto deste teste.
            is_superuser: true,
            jti: "jti-p6".to_string(),
            iat: agora as usize,
            exp: (agora + 300) as usize,
        })
        .unwrap();
        let mut req = Request::new(ObterContatoDoAtendimentoRequest {
            atendimento_id: 3,
            forcar: true,
        });
        req.metadata_mut()
            .insert("authorization", format!("Bearer {token}").parse().unwrap());

        let resp = facade
            .obter_contato_do_atendimento(req)
            .await
            .expect("contato")
            .into_inner();

        assert_eq!(resp.contato_id, 7);
        assert_eq!(resp.foto_url, "https://r2.example/avatar?ttl=3600");
        assert_eq!(
            chamadas_provedor.load(Ordering::SeqCst),
            0,
            "o provedor não pode ser chamado no caminho da requisição"
        );
    }
}
