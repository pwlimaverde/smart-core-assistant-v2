//! A análise da IA de um atendimento, para a ficha.
//!
//! No painel antigo ela ia na descrição do cartão do Trello ("🤖 Análise de
//! IA": intenções e entidades das mensagens). Aqui sai do que o worker já
//! grava em cada mensagem, do sentimento do atendimento e da última decisão do
//! motor — nada é calculado de novo ao abrir a ficha.

use serde::Serialize;
use sqlx::{Postgres, Transaction};

use crate::{errors::DbError, security::RequestContext};

/// Quantas intenções a ficha mostra; o resto é ruído de conversa longa.
const MAX_INTENCOES: i64 = 8;
/// Quantas entidades a ficha mostra.
const MAX_ENTIDADES: i64 = 15;

#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct IntencaoDaConversa {
    pub tipo: String,
    /// A maior confiança com que a intenção apareceu.
    pub confianca: f64,
    /// Em quantas mensagens ela apareceu.
    pub vezes: i32,
}

#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct EntidadeDaConversa {
    pub tipo: String,
    /// O valor mais recente: o cliente que corrige a quantidade vale o novo.
    pub valor: String,
    pub confianca: f64,
}

#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct UltimaDecisao {
    pub motor: String,
    pub ato: String,
    pub decisao: String,
    pub motivo: String,
    pub transferiu: bool,
    pub intencao: String,
    pub criado_em: i64,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct AnaliseDoAtendimento {
    pub intencoes: Vec<IntencaoDaConversa>,
    pub entidades: Vec<EntidadeDaConversa>,
    pub sentimento_label: String,
    /// 0 = sem nota.
    pub sentimento_nota: i32,
    pub ultima_decisao: Option<UltimaDecisao>,
}

/// Junta a análise do atendimento. Lista vazia é o normal de conversa nova.
#[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id))]
pub async fn analise_do_atendimento(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    atendimento_id: i32,
) -> Result<AnaliseDoAtendimento, DbError> {
    let intencoes = sqlx::query_as::<_, IntencaoDaConversa>(
        r#"SELECT i->>'tipo' AS tipo,
                  COALESCE(MAX((i->>'confianca')::float8), 0) AS confianca,
                  COUNT(*)::int AS vezes
             FROM oraculo_mensagem m
             CROSS JOIN LATERAL jsonb_array_elements(
                 CASE WHEN jsonb_typeof(m.intent_detectado) = 'array'
                      THEN m.intent_detectado ELSE '[]'::jsonb END
             ) i
            WHERE m.tenant_id = $1 AND m.atendimento_id = $2
              AND COALESCE(i->>'tipo', '') <> ''
            GROUP BY i->>'tipo'
            ORDER BY MAX(m.id) DESC
            LIMIT $3"#,
    )
    .bind(ctx.tenant_id)
    .bind(atendimento_id)
    .bind(MAX_INTENCOES)
    .fetch_all(&mut **tx)
    .await?;

    let entidades = sqlx::query_as::<_, EntidadeDaConversa>(
        r#"SELECT tipo, valor, confianca
             FROM (
                SELECT DISTINCT ON (e->>'tipo')
                       e->>'tipo' AS tipo,
                       e->>'valor' AS valor,
                       COALESCE((e->>'confianca')::float8, 0) AS confianca,
                       m.id AS mensagem_id
                  FROM oraculo_mensagem m
                  CROSS JOIN LATERAL jsonb_array_elements(
                      CASE WHEN jsonb_typeof(m.entidades_extraidas) = 'array'
                           THEN m.entidades_extraidas ELSE '[]'::jsonb END
                  ) e
                 WHERE m.tenant_id = $1 AND m.atendimento_id = $2
                   AND COALESCE(e->>'tipo', '') <> ''
                   AND COALESCE(e->>'valor', '') <> ''
                 ORDER BY e->>'tipo', m.id DESC
             ) ultimas
            ORDER BY mensagem_id DESC
            LIMIT $3"#,
    )
    .bind(ctx.tenant_id)
    .bind(atendimento_id)
    .bind(MAX_ENTIDADES)
    .fetch_all(&mut **tx)
    .await?;

    let sentimento = sqlx::query_as::<_, (Option<String>, Option<i32>)>(
        "SELECT sentimento_label, sentimento_nota FROM oraculo_atendimento \
          WHERE tenant_id = $1 AND id = $2",
    )
    .bind(ctx.tenant_id)
    .bind(atendimento_id)
    .fetch_optional(&mut **tx)
    .await?;

    // Só a decisão que valeu: a da sombra não aconteceu para o cliente.
    let ultima_decisao = sqlx::query_as::<_, UltimaDecisao>(
        r#"SELECT motor, ato, decisao, motivo, transferiu, intencao,
                  (EXTRACT(EPOCH FROM criado_em) * 1000)::bigint AS criado_em
             FROM oraculo_decisao_ia
            WHERE tenant_id = $1 AND atendimento_id = $2 AND vale
            ORDER BY criado_em DESC, id DESC
            LIMIT 1"#,
    )
    .bind(ctx.tenant_id)
    .bind(atendimento_id)
    .fetch_optional(&mut **tx)
    .await?;

    let (sentimento_label, sentimento_nota) = sentimento.unwrap_or((None, None));
    Ok(AnaliseDoAtendimento {
        intencoes,
        entidades,
        sentimento_label: sentimento_label.unwrap_or_default(),
        sentimento_nota: sentimento_nota.unwrap_or(0),
        ultima_decisao,
    })
}
