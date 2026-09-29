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

/// Intenção do catálogo como o motor Jev a recebe (plano ia-engine-jev).
#[derive(Debug, Clone, Default)]
pub struct IntentDefInput {
    pub tag: String,
    pub grupo: String,
    pub descricao: String,
    pub exemplo: String,
    pub comportamento: String,
    /// Coleta estruturada: dados essenciais (tipo de entidade ou slug de
    /// campo), quantos por mensagem e o que fazer depois da rodada
    /// (`transferir` | `continuar`).
    pub campos_coleta: Vec<String>,
    pub max_perguntas: i32,
    pub apos_coleta: String,
}

/// Tipo de entidade com a estratégia de busca de valor.
#[derive(Debug, Clone, Default)]
pub struct EntidadeDefInput {
    pub tipo: String,
    pub descricao: String,
    pub estrategia: String,
    pub opcoes: Vec<String>,
}

/// Trecho da base de conhecimento, um por documento.
#[derive(Debug, Clone, Default)]
pub struct TrechoInput {
    pub id: String,
    pub conteudo: String,
    pub distancia: f64,
}

/// Um sinal que pesou na decisão do motor Jev.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct SinalOutput {
    pub nome: String,
    pub valor: f64,
    pub limiar: f64,
}

/// Julgamento de um trecho: evidência, conflito ou descartado.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct TrechoAvaliadoOutput {
    pub id: String,
    pub aprovado: bool,
    pub conflito: bool,
}

/// Custo e duração de uma decisão do motor.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct UsoOutput {
    pub tokens_entrada: i64,
    pub requisicoes: i32,
    pub duracao_ms: i64,
}

#[derive(Debug, Clone, Default)]
pub struct AnalyseInput {
    pub tenant_id: String,
    pub mensagem: String,
    pub historico: Vec<ChatTurnInput>,
    pub valid_intent_types: String,
    pub valid_entity_types: Vec<String>,
    /// Motor Jev — o atual ignora.
    pub intents: Vec<IntentDefInput>,
    pub entidades: Vec<EntidadeDefInput>,
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
    /// Motor Jev; vazios no motor atual.
    pub intent_principal: String,
    pub confianca_principal: f64,
    pub intents_a_revisar: Vec<String>,
    pub motor: String,
    pub modelo: String,
    pub uso: UsoOutput,
    /// Motor Jev: o tom da mensagem, medido na mesma leitura (1..5 e
    /// negativo | neutro | positivo). 0/vazio quando não medido.
    pub sentimento_nota: i32,
    pub sentimento_label: String,
}

/// Duração de uma etapa do motor Jev (leitura, trechos, redacao, ...).
#[derive(Debug, Clone, Default, PartialEq)]
pub struct EtapaOutput {
    pub etapa: String,
    pub ms: i64,
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
    /// Motor Jev — o atual ignora e segue com `dados_treinamento`.
    pub intents: Vec<IntentDefInput>,
    pub trechos: Vec<TrechoInput>,
    pub comportamento: String,
    /// Sombra: só a decisão, sem LLM.
    pub somente_decisao: bool,
    /// Rodadas de coleta já feitas no atendimento.
    pub rodadas_coleta: i32,
}
#[derive(Debug, Clone, Default)]
pub struct ResponderOutput {
    pub resposta_texto: String,
    pub transferir_atendimento: bool,
    pub fluxo_transferencia: String,
    pub confiabilidade: f64,
    /// C1 — campos do cartão que o cliente informou nesta mensagem.
    ///
    /// Vazio na maioria das respostas, e vazio também quando o `ia_engine` é
    /// anterior ao C1: o campo é aditivo no proto, e um servidor antigo
    /// simplesmente não o envia.
    pub campos_extraidos: Vec<CampoExtraidoOutput>,
    /// Motor Jev; vazios no motor atual (que não sabe dizer por que transferiu).
    pub motivo_transferencia: String,
    pub sinais: Vec<SinalOutput>,
    pub motor: String,
    pub modelo: String,
    pub uso: UsoOutput,
    pub trechos: Vec<TrechoAvaliadoOutput>,
    pub intencao_principal: String,
    pub confianca_intencao: f64,
    /// automatica | transferida | sem_info | a_revisar | barrada | reserva;
    /// vazio no motor atual.
    pub decisao: String,
    pub regra_id: i64,
    /// Motor Jev: o ato decidido (transferir | responder | coletar | social |
    /// sem_info | barrada), os campos pedidos ao cliente (uma rodada de
    /// coleta), a cascata e onde o tempo foi.
    pub ato: String,
    pub campos_perguntados: Vec<String>,
    pub escalada: bool,
    pub problemas: Vec<String>,
    pub modelo_llm: String,
    pub etapas: Vec<EtapaOutput>,
    /// A análise da mesma leitura: o worker grava sem chamar o `Analyse`.
    pub analise: Option<AnalyseOutput>,
}

/// Um campo extraído, como o modelo devolveu — sem validação.
///
/// `valor_json` é texto de propósito: o tipo real (número, data, lista) mora
/// no catálogo do tenant, que esta crate não conhece. Quem converte e recusa
/// é o `data_postgres`.
#[derive(Debug, Clone, Default)]
pub struct CampoExtraidoOutput {
    pub slug: String,
    pub valor_json: String,
    pub confianca: f64,
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

/// B9 (N10 E5) — documento de treinamento a ler, por URL pré-assinada.
#[derive(Debug, Clone)]
pub struct ExtrairTextoInput {
    pub tenant_id: String,
    pub media: MediaRefInput,
}
#[derive(Debug, Clone, Default)]
pub struct ExtrairTextoOutput {
    pub texto: String,
    pub formato: String,
    pub caracteres: i32,
}

/// Uma frase contra uma regra de transferência (só o motor Jev).
#[derive(Debug, Clone, Default)]
pub struct TestarRegraInput {
    pub tenant_id: String,
    pub frase: String,
    pub condicao: String,
    pub exemplos_sim: Vec<String>,
    pub exemplos_nao: Vec<String>,
    pub sensibilidade: String,
}
#[derive(Debug, Clone, Default)]
pub struct TestarRegraOutput {
    pub probabilidade: f64,
    pub limiar: f64,
    pub dispararia: bool,
    pub modelo: String,
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
// A feature `mock` expõe o dublê a quem depende da crate. Sem ela, cada
// consumidor escreveria o seu — seis métodos repetidos, que envelhecem em
// silêncio quando a trait muda.
#[cfg_attr(any(test, feature = "mock"), mockall::automock)]
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

    /// B9 (N10 E5) — texto de um documento de treinamento. Sem LLM.
    async fn extrair_texto_documento(
        &self,
        req: ExtrairTextoInput,
        traceparent: &str,
    ) -> Result<ExtrairTextoOutput, IaEngineError>;

    /// Plano ia-engine-jev — testa uma regra de transferência contra uma
    /// frase. Só o motor Jev implementa; o atual devolve `Invalid`.
    async fn testar_regra_transferencia(
        &self,
        req: TestarRegraInput,
        traceparent: &str,
    ) -> Result<TestarRegraOutput, IaEngineError>;
}
