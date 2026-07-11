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

/// Operações de RAG (busca vetorial pgvector) expostas ao handler RPC `QueryCompose`.
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
}
