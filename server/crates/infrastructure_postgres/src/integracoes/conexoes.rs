//! P7 — o que a conexão de WhatsApp precisa saber além de existir.
//!
//! Mora fora de `whatsapp.rs` porque aquele arquivo usa `query_as!` (macro), e
//! macro exige o cache `.sqlx` casado com o banco. A coluna `departamento_id` é
//! nova: incluí-la lá invalidaria o cache e quebraria o build offline da CI.
//! Aqui as consultas são em runtime, e o cache não tem opinião sobre elas.

use sqlx::{Postgres, Transaction};

use crate::{errors::DbError, security::RequestContext};

/// Detalhe de uma conexão — o que a lista não mostra e quem investiga precisa.
#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct DetalheDaConexao {
    pub id: i32,
    pub name: String,
    pub instance_id: Option<String>,
    pub phone_number: Option<String>,
    pub connection_state: String,
    pub active: bool,
    pub provider: String,
    pub resposta_bot: bool,
    pub departamento_id: Option<i32>,
    pub departamento_nome: Option<String>,
    pub last_state_check: Option<chrono::DateTime<chrono::Utc>>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    /// Conversas ainda abertas do tenant — o número que diz se desconectar
    /// deixa gente no meio do caminho.
    pub atendimentos_abertos: i64,
    pub mensagens_24h: i64,
}

/// Uma linha da lista com o departamento resolvido.
#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct ConexaoComDepartamento {
    pub id: i32,
    pub departamento_id: Option<i32>,
    pub departamento_nome: Option<String>,
}

/// P7 — liga a conexão a um departamento. `None` desfaz o vínculo.
///
/// `false` no retorno = conexão inexistente ou de outro tenant.
#[tracing::instrument(skip_all, fields(id = id))]
pub async fn definir_departamento(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    id: i32,
    departamento_id: Option<i32>,
) -> Result<bool, DbError> {
    ctx.exigir_qualquer(&["operacional:admin", "tenant:admin"])?;
    // O departamento é conferido pelo mesmo tenant na subconsulta, e não numa
    // leitura à parte: sem isso, mandar o id de um departamento de outro tenant
    // gravaria o vínculo e só estouraria na FK — ou nem isso, se o id existir
    // nos dois.
    let r = sqlx::query(
        r#"UPDATE whatsapp_instance
              SET departamento_id = (
                    SELECT d.id FROM oraculo_departamento d
                     WHERE d.tenant_id = $1 AND d.id = $3
                  )
            WHERE tenant_id = $1 AND id = $2"#,
    )
    .bind(ctx.tenant_id)
    .bind(id)
    .bind(departamento_id)
    .execute(&mut **tx)
    .await?;
    Ok(r.rows_affected() > 0)
}

/// P7 — o departamento para onde esta conexão roteia. `None` = nenhum.
///
/// É a consulta da INGESTÃO, e por isso não exige escopo: quem chama é o
/// worker, com o contexto de sistema.
#[tracing::instrument(skip_all, fields(instance_id = instance_id))]
pub async fn departamento_da_conexao(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    instance_id: i32,
) -> Result<Option<i32>, DbError> {
    let row = sqlx::query_as::<_, (Option<i32>,)>(
        r#"SELECT departamento_id FROM whatsapp_instance
            WHERE tenant_id = $1 AND id = $2"#,
    )
    .bind(ctx.tenant_id)
    .bind(instance_id)
    .fetch_optional(&mut **tx)
    .await?;
    Ok(row.and_then(|(d,)| d))
}

/// P7 — o departamento de cada conexão do tenant, para a lista.
#[tracing::instrument(skip_all)]
pub async fn departamentos_das_conexoes(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
) -> Result<Vec<ConexaoComDepartamento>, DbError> {
    let rows = sqlx::query_as::<_, ConexaoComDepartamento>(
        r#"SELECT i.id, i.departamento_id, d.nome AS departamento_nome
             FROM whatsapp_instance i
             LEFT JOIN oraculo_departamento d
                    ON d.id = i.departamento_id AND d.tenant_id = i.tenant_id
            WHERE i.tenant_id = $1"#,
    )
    .bind(ctx.tenant_id)
    .fetch_all(&mut **tx)
    .await?;
    Ok(rows)
}

/// P7 — o detalhe da conexão.
///
/// Os dois contadores vêm na mesma consulta porque a tela mostra os três juntos
/// e três idas ao banco para desenhar um cartão é desperdício.
#[tracing::instrument(skip_all, fields(id = id))]
pub async fn detalhe(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    id: i32,
) -> Result<Option<DetalheDaConexao>, DbError> {
    ctx.exigir_qualquer(&["operacional:read", "operacional:admin", "tenant:admin"])?;
    let row = sqlx::query_as::<_, DetalheDaConexao>(
        r#"SELECT i.id, i.name, i.instance_id, i.phone_number, i.connection_state,
                  i.active, i.provider, i.resposta_bot, i.departamento_id,
                  d.nome AS departamento_nome, i.last_state_check, i.created_at,
                  (SELECT COUNT(*) FROM oraculo_atendimento a
                    WHERE a.tenant_id = i.tenant_id AND a.data_fim IS NULL)
                      AS atendimentos_abertos,
                  (SELECT COUNT(*) FROM oraculo_mensagem m
                    WHERE m.tenant_id = i.tenant_id
                      AND m.data_envio > NOW() - INTERVAL '24 hours')
                      AS mensagens_24h
             FROM whatsapp_instance i
             LEFT JOIN oraculo_departamento d
                    ON d.id = i.departamento_id AND d.tenant_id = i.tenant_id
            WHERE i.tenant_id = $1 AND i.id = $2"#,
    )
    .bind(ctx.tenant_id)
    .bind(id)
    .fetch_optional(&mut **tx)
    .await?;
    Ok(row)
}
