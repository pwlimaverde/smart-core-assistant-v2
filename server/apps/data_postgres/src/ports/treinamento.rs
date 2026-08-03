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
}
