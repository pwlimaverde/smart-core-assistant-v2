//! Port (abstração) do domínio Treinamento/RAG do data_postgres.
//! Consumido pelo RPC `QueryCompose` (fase N2 — `ia_engine`): o worker resolve o
//! embedding da mensagem via `ia_engine.Embed` e chama este port para compor o
//! contexto de RAG (comportamento mais próximo + chunks de documento) sob RLS de
//! tenant, ANTES de chamar `ia_engine.Responder`. O `data_postgres` continua sendo
//! a única porta de banco do sistema (memória `banco-unica-porta-via-infra-rpc`).

use async_trait::async_trait;
use infrastructure_postgres::{DbError, RequestContext};

/// Um chunk de documento de treinamento retornado pela busca vetorial, junto da
/// distância de cosseno (quanto menor, mais similar).
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct DocumentoTrecho {
    /// Plano ia-engine-jev: o motor Jev julga e registra cada trecho pelo id.
    #[serde(default)]
    pub id: i32,
    pub conteudo: Option<String>,
    pub distancia: f64,
}

/// Resultado composto do RAG: o comportamento (intenção) mais próximo cadastrado
/// em `treinamento_querycompose`, mais os `chunk_top_k` trechos de documento mais
/// similares em `oraculo_documento`.
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct QueryComposeResultado {
    pub comportamento: Option<String>,
    pub documentos: Vec<DocumentoTrecho>,
}

/// Um treinamento, na forma em que a tela de acompanhamento precisa dele.
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct TreinamentoResumo {
    pub id: i32,
    pub tag: String,
    pub grupo: String,
    pub conteudo: String,
    pub finalizado: bool,
    pub vetorizado: bool,
    pub criado_em: i64,
    pub atualizado_em: i64,
    /// B9 (N10 E5) — vazios quando o treinamento é de texto colado.
    #[serde(default)]
    pub arquivo_nome: String,
    /// `pendente` | `extraido` | `falhou` | vazio.
    #[serde(default)]
    pub extracao_status: String,
    #[serde(default)]
    pub extracao_erro: String,
}

/// Operações de RAG (busca vetorial pgvector) expostas ao handler RPC `QueryCompose`,
/// mais o CRUD que a tela de treinamento consome.
#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait TreinamentoStore: Send + Sync {
    /// Compõe o contexto de RAG para uma mensagem já embedada: comportamento mais
    /// próximo (se dentro do `distance_threshold`) + até `chunk_top_k` chunks de
    /// documento (mesmo threshold), ambos por distância de cosseno sob RLS de tenant.
    async fn query_compose(
        &self,
        ctx: &RequestContext,
        query_embedding: Vec<f32>,
        distance_threshold: f64,
        chunk_top_k: i64,
    ) -> Result<QueryComposeResultado, DbError>;

    /// Cria (ou reaproveita) o treinamento da dupla tag+grupo e devolve o id.
    ///
    /// Reaproveitar é intencional e vem da v1: retreinar o mesmo assunto
    /// acumula conteúdo no mesmo registro em vez de espalhar duplicatas.
    async fn criar_treinamento(
        &self,
        ctx: &RequestContext,
        tag: &str,
        grupo: &str,
        conteudo: &str,
    ) -> Result<TreinamentoResumo, DbError>;

    async fn listar_treinamentos(
        &self,
        ctx: &RequestContext,
    ) -> Result<Vec<TreinamentoResumo>, DbError>;

    async fn obter_treinamento(
        &self,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<TreinamentoResumo>, DbError>;

    /// Aceita a revisão: grava o conteúdo (possivelmente editado) e finaliza.
    ///
    /// É o passo que a v1 chamava de pré-processamento — o texto revisado é o
    /// que vai virar vetor, e finalizar é o que o coloca na fila do worker.
    async fn finalizar_treinamento(
        &self,
        ctx: &RequestContext,
        id: i32,
        conteudo: &str,
    ) -> Result<bool, DbError>;

    async fn remover_treinamento(&self, ctx: &RequestContext, id: i32) -> Result<bool, DbError>;

    // ── vetorização (scheduler do worker) ─────────────────────────────────
    //
    // Sem esta fila, o material treinado nunca vira vetor e o RAG consulta uma
    // tabela vazia: a tela de treinamento gravaria texto que a IA nunca lê.

    /// O que foi finalizado e ainda não virou vetor, de toda a base.
    /// Exige `admin_pool` (BYPASSRLS) — sem ele a RLS devolve zero em silêncio.
    async fn listar_pendentes_vetorizacao(
        &self,
        ctx: &RequestContext,
        limite: i64,
    ) -> Result<Vec<TreinamentoPendente>, DbError>;

    /// Grava os trechos já embedados e marca o treinamento como vetorizado.
    ///
    /// Os dois passos na mesma transação: marcar sem gravar perderia o material
    /// para sempre (não volta à fila), e gravar sem marcar o reprocessaria a
    /// cada tick, duplicando os trechos.
    async fn salvar_chunks_vetorizados(
        &self,
        ctx: &RequestContext,
        treinamento_id: i32,
        chunks: Vec<ChunkVetorizado>,
    ) -> Result<bool, DbError>;

    /// Intenções sem vetor, de toda a base. Uma intenção sem embedding existe
    /// no cadastro e não existe para a IA.
    async fn listar_intents_sem_embedding(
        &self,
        ctx: &RequestContext,
        limite: i64,
    ) -> Result<Vec<IntentPendente>, DbError>;

    async fn definir_embedding_intent(
        &self,
        ctx: &RequestContext,
        id: i32,
        embedding: Vec<f32>,
    ) -> Result<bool, DbError>;

    // ── curadoria de intenções (tela de treinamento) ──────────────────────

    /// P17 — as avaliações do teste ainda não tratadas.
    async fn listar_avaliacoes_pendentes(
        &self,
        ctx: &RequestContext,
        limite: i64,
    ) -> Result<Vec<infrastructure_postgres::treinamento::treinamentos::AvaliacaoDeTeste>, DbError>;

    /// P17 — tira a avaliação da lista de revisão.
    async fn marcar_avaliacao_tratada(
        &self,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<bool, DbError>;

    /// B9 (N10 E6) — grava a avaliação de um ensaio, com a correção.
    async fn registrar_feedback_teste(
        &self,
        ctx: &RequestContext,
        novo: infrastructure_postgres::treinamento::treinamentos::NovoFeedbackTeste,
    ) -> Result<i32, DbError>;

    /// B9 (N10 E5) — confere a quota e devolve a chave onde subir o arquivo.
    async fn autorizar_upload_treinamento(
        &self,
        ctx: &RequestContext,
        bytes: i64,
    ) -> Result<String, DbError>;

    /// B9 — cria o treinamento a partir do arquivo já conferido no bucket.
    async fn criar_treinamento_com_arquivo(
        &self,
        ctx: &RequestContext,
        novo: infrastructure_postgres::treinamento::treinamentos::NovoTreinamentoComArquivo,
    ) -> Result<TreinamentoResumo, DbError>;

    /// B9 — a fila da extração, de toda a base (exige `admin_pool`).
    async fn listar_extracoes_pendentes(
        &self,
        ctx: &RequestContext,
        limite: i64,
    ) -> Result<Vec<infrastructure_postgres::treinamento::treinamentos::ExtracaoPendente>, DbError>;

    /// B9 — grava o texto extraído ou o motivo da falha.
    async fn registrar_extracao_treinamento(
        &self,
        ctx: &RequestContext,
        id: i32,
        resultado: infrastructure_postgres::treinamento::treinamentos::ResultadoExtracao,
    ) -> Result<bool, DbError>;

    async fn listar_intents(&self, ctx: &RequestContext) -> Result<Vec<Intent>, DbError>;

    async fn criar_intent(
        &self,
        ctx: &RequestContext,
        dados: DadosIntent,
    ) -> Result<Intent, DbError>;

    async fn atualizar_intent(
        &self,
        ctx: &RequestContext,
        id: i32,
        dados: DadosIntent,
    ) -> Result<bool, DbError>;

    async fn remover_intent(&self, ctx: &RequestContext, id: i32) -> Result<bool, DbError>;
}

/// Um treinamento aguardando vetorização, com o tenant a que pertence — a
/// varredura é cross-tenant, e o worker precisa saber em nome de quem gravar.
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct TreinamentoPendente {
    pub id: i32,
    pub tenant_id: String,
    pub tag: String,
    pub conteudo: String,
}

/// Um trecho de conteúdo já com o vetor correspondente.
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct ChunkVetorizado {
    pub conteudo: String,
    pub embedding: Vec<f32>,
    pub ordem: i32,
}

/// Uma intenção aguardando vetor.
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct IntentPendente {
    pub id: i32,
    pub tenant_id: String,
    /// Já montado por `to_embedding_text` — o worker não deve reimplementar o
    /// formato, senão o vetor da criação e o da atualização divergiriam.
    pub texto: String,
}

/// Uma intenção, como a tela de curadoria a mostra.
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct Intent {
    pub id: i32,
    pub tag: String,
    pub grupo: String,
    pub descricao: String,
    pub exemplo: String,
    pub comportamento: String,
    /// Motor Jev — coleta estruturada: os dados essenciais que o bot pede
    /// (tipo de entidade ou slug de campo do cartão), quantos por mensagem, e
    /// o que fazer depois da rodada (`transferir` | `continuar`).
    #[serde(default)]
    pub campos_coleta: Vec<String>,
    #[serde(default)]
    pub max_perguntas: i32,
    #[serde(default)]
    pub apos_coleta: String,
    /// `false` enquanto o worker não gerou o vetor. Até lá a intenção não é
    /// encontrada pela busca semântica — e a tela precisa dizer isso.
    pub vetorizada: bool,
    pub criado_em: i64,
    pub atualizado_em: i64,
}

/// Campos de escrita de uma intenção. Agrupados num struct porque `automock`
/// não lida bem com sete parâmetros de texto, e a lista nomeada evita a troca
/// silenciosa entre `descricao` e `exemplo`.
#[derive(Debug, Clone, Default)]
pub struct DadosIntent {
    pub tag: String,
    pub grupo: String,
    pub descricao: String,
    pub exemplo: String,
    pub comportamento: String,
    pub coleta: ColetaDaIntent,
}

/// A coleta estruturada de uma intenção, já normalizada (ver
/// `ColetaDaIntent::normalizar`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ColetaDaIntent {
    pub campos: Vec<String>,
    pub max_perguntas: i32,
    pub apos: String,
}

impl Default for ColetaDaIntent {
    fn default() -> Self {
        Self {
            campos: Vec::new(),
            max_perguntas: MAX_PERGUNTAS_PADRAO,
            apos: "transferir".to_string(),
        }
    }
}

pub const MAX_PERGUNTAS_PADRAO: i32 = 2;
const MAX_CAMPOS_COLETA: usize = 10;
const MAX_TAMANHO_CAMPO: usize = 60;

impl ColetaDaIntent {
    /// Campos aparados, sem repetição, até 10 com 60 caracteres cada;
    /// perguntas entre 1 e 5 (fora disso, 2); `apos` desconhecido vira
    /// `transferir`, que é o comportamento de quem não configurou nada.
    pub fn normalizar(campos: &[String], max_perguntas: i64, apos: &str) -> Self {
        let mut vistos: Vec<String> = Vec::new();
        for c in campos {
            let c: String = c.trim().chars().take(MAX_TAMANHO_CAMPO).collect();
            if !c.is_empty() && !vistos.contains(&c) && vistos.len() < MAX_CAMPOS_COLETA {
                vistos.push(c);
            }
        }
        Self {
            campos: vistos,
            max_perguntas: if (1..=5).contains(&max_perguntas) {
                max_perguntas as i32
            } else {
                MAX_PERGUNTAS_PADRAO
            },
            apos: if apos.trim() == "continuar" {
                "continuar".to_string()
            } else {
                "transferir".to_string()
            },
        }
    }
}

#[cfg(test)]
mod tests_coleta {
    use super::*;

    #[test]
    fn coleta_normalizada() {
        let campos: Vec<String> = [" formato ", "", "formato", "arte"]
            .iter()
            .map(|s| s.to_string())
            .chain((0..20).map(|n| format!("c{n}")))
            .collect();
        let c = ColetaDaIntent::normalizar(&campos, 9, "xyz");
        assert_eq!(&c.campos[..2], &["formato".to_string(), "arte".to_string()]);
        assert_eq!(c.campos.len(), 10);
        assert_eq!(c.max_perguntas, 2);
        assert_eq!(c.apos, "transferir");
        let c2 = ColetaDaIntent::normalizar(&[], 3, "continuar");
        assert_eq!((c2.max_perguntas, c2.apos.as_str()), (3, "continuar"));
        assert_eq!(ColetaDaIntent::default().max_perguntas, 2);
    }
}
