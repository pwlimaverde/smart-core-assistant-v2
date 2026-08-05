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
}
