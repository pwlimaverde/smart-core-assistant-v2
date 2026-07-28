//! Port do cliente gRPC do `ia_engine` (fase N2). Desacopla o domínio do worker do
//! tipo `prost` gerado — `TonicIaEngineClient` (adapter real) converte estes DTOs
//! de/para `contracts::grpc::ai::*`. Mockável via `mockall` para testar a barreira
//! de bot sem subir um servidor `tonic` real.

use async_trait::async_trait;

#[derive(Debug, Clone, Default)]
pub struct MediaRefInput {
    pub url: String,
    pub mimetype: String,
    pub file_name: String,
}

#[derive(Debug, Clone, Default)]
pub struct ChatTurnInput {
    pub role: String,
    pub conteudo: String,
}

#[derive(Debug, Clone, Default)]
pub struct TranscribeInput {
    pub tenant_id: String,
    pub media: MediaRefInput,
    pub language: String,
}
#[derive(Debug, Clone, Default)]
pub struct TranscribeOutput {
    pub transcricao: String,
    pub resumo: String,
}

#[derive(Debug, Clone, Default)]
pub struct InterpretMediaInput {
    pub tenant_id: String,
    pub media: MediaRefInput,
    pub media_type: String,
}
#[derive(Debug, Clone, Default)]
pub struct InterpretMediaOutput {
    pub analise: String,
    pub resumo: String,
}

#[derive(Debug, Clone, Default)]
pub struct AnalyseInput {
    pub tenant_id: String,
    pub mensagem: String,
    pub historico: Vec<ChatTurnInput>,
    pub valid_intent_types: String,
    pub valid_entity_types: Vec<String>,
}
#[derive(Debug, Clone, Default)]
pub struct IntentOutput {
    pub tipo: String,
    pub confianca: f64,
}
#[derive(Debug, Clone, Default)]
pub struct EntidadeOutput {
    pub tipo: String,
    pub valor: String,
    pub confianca: f64,
}
#[derive(Debug, Clone, Default)]
pub struct AnalyseOutput {
    pub intents: Vec<IntentOutput>,
    pub entidades: Vec<EntidadeOutput>,
}

#[derive(Debug, Clone, Default)]
pub struct EmbedInput {
    pub tenant_id: String,
    pub textos: Vec<String>,
}
#[derive(Debug, Clone, Default)]
pub struct EmbedOutput {
    pub embeddings: Vec<Vec<f32>>,
}

#[derive(Debug, Clone, Default)]
pub struct CampoColetadoInput {
    pub slug: String,
    pub nome: String,
    pub valor: String,
}
#[derive(Debug, Clone, Default)]
pub struct CampoPendenteInput {
    pub slug: String,
    pub nome: String,
    pub descricao: String,
    pub hint: String,
}

#[derive(Debug, Clone, Default)]
pub struct ResponderInput {
    pub tenant_id: String,
    pub atendimento_id: String,
    pub mensagem: String,
    pub historico: Vec<ChatTurnInput>,
    /// Chave = "Setor - descrição" (convenção herdada da v1).
    pub fluxos_disponiveis: Vec<(String, String)>,
    pub dados_treinamento: String,
    pub campos_coletados: Vec<CampoColetadoInput>,
    pub campos_pendentes: Vec<CampoPendenteInput>,
}
#[derive(Debug, Clone, Default)]
pub struct ResponderOutput {
    pub resposta_texto: String,
    pub transferir_atendimento: bool,
    pub fluxo_transferencia: String,
    pub confiabilidade: f64,
}

#[derive(Debug, Clone, Default)]
pub struct SentimentoInput {
    pub tenant_id: String,
    pub historico: Vec<ChatTurnInput>,
}
#[derive(Debug, Clone, Default)]
pub struct SentimentoOutput {
    pub nota: i32,
    pub sentimento: String,
    pub feedback: String,
}

/// Erro do cliente `ia_engine`, já classificado por retentabilidade (usado pelo
/// decorator `ResilientIaEngine`). `Timeout`/`Unavailable` são transitórios
/// (retry vale a pena); `Invalid`/`Internal` são definitivos.
#[derive(Debug, Clone)]
pub enum IaEngineError {
    Timeout,
    Unavailable(String),
    Invalid(String),
    Internal(String),
}

impl std::fmt::Display for IaEngineError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            IaEngineError::Timeout => write!(f, "timeout ao chamar ia_engine"),
            IaEngineError::Unavailable(m) => write!(f, "ia_engine indisponível: {m}"),
            IaEngineError::Invalid(m) => write!(f, "requisição inválida ao ia_engine: {m}"),
            IaEngineError::Internal(m) => write!(f, "erro interno do ia_engine: {m}"),
        }
    }
}

impl std::error::Error for IaEngineError {}

impl IaEngineError {
    /// `true` quando vale a pena retentar (erro transitório de rede/disponibilidade).
    pub fn retentavel(&self) -> bool {
        matches!(self, IaEngineError::Timeout | IaEngineError::Unavailable(_))
    }
}

/// Port do cliente gRPC do `ia_engine`. Cada método corresponde a um RPC de
/// `IaEngineService` (`server/crates/contracts/schemas/ai/ai_engine.proto`).
#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait IaEngineClient: Send + Sync {
    async fn transcribe(
        &self,
        req: TranscribeInput,
        traceparent: &str,
    ) -> Result<TranscribeOutput, IaEngineError>;

    async fn interpret_media(
        &self,
        req: InterpretMediaInput,
        traceparent: &str,
    ) -> Result<InterpretMediaOutput, IaEngineError>;

    async fn analyse(
        &self,
        req: AnalyseInput,
        traceparent: &str,
    ) -> Result<AnalyseOutput, IaEngineError>;

    async fn embed(&self, req: EmbedInput, traceparent: &str)
        -> Result<EmbedOutput, IaEngineError>;

    async fn responder(
        &self,
        req: ResponderInput,
        traceparent: &str,
    ) -> Result<ResponderOutput, IaEngineError>;

    async fn sentimento(
        &self,
        req: SentimentoInput,
        traceparent: &str,
    ) -> Result<SentimentoOutput, IaEngineError>;
}
