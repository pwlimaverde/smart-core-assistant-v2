use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct CampoPersonalizado {
    pub id: i64,
    pub tenant_id: Uuid,
    pub slug: String,
    pub nome: String,
    pub descricao: String,
    pub escopo: String,
    pub fluxo_id: Option<i32>,
    pub tipo: String,
    pub opcoes: serde_json::Value,
    pub obrigatorio: bool,
    pub extrair_automaticamente: bool,
    pub extrair_hint: String,
    pub mostrar_no_card: bool,
    pub ordem: i32,
    pub ativo: bool,
    pub data_criacao: DateTime<Utc>,
    pub data_atualizacao: DateTime<Utc>,
}

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct ValorCampoAtendimento {
    pub id: i64,
    pub tenant_id: Uuid,
    pub atendimento_id: i32,
    pub campo_id: i64,
    pub valor: serde_json::Value,
    pub origem: String,
    pub confianca: Option<f64>,
    pub mensagem_origem_id: Option<i32>,
    pub editado_por_id: Option<i32>,
    pub data_atualizacao: DateTime<Utc>,
}

/// O que a tela manda ao criar um campo.
///
/// Struct em vez de dez parâmetros: a ordem de `bool`s soltos é o tipo de coisa
/// que se troca sem o compilador reclamar.
#[derive(Debug, Clone)]
pub struct NovoCampoPersonalizado<'a> {
    pub slug: &'a str,
    pub nome: &'a str,
    pub descricao: &'a str,
    pub escopo: &'a str,
    pub fluxo_id: Option<i32>,
    pub tipo: &'a str,
    pub opcoes: serde_json::Value,
    pub obrigatorio: bool,
    pub extrair_automaticamente: bool,
    pub extrair_hint: &'a str,
    pub mostrar_no_card: bool,
    pub ordem: i32,
}

/// O que a tela edita. Sem `slug`, `escopo` e `fluxo_id` — ver `atualizar`.
#[derive(Debug, Clone)]
pub struct EdicaoCampoPersonalizado<'a> {
    pub nome: &'a str,
    pub descricao: &'a str,
    pub tipo: &'a str,
    pub opcoes: serde_json::Value,
    pub obrigatorio: bool,
    pub extrair_automaticamente: bool,
    pub extrair_hint: &'a str,
    pub mostrar_no_card: bool,
    pub ordem: i32,
    pub ativo: bool,
}

#[async_trait]
pub trait CampoPersonalizadoRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        slug: &str,
        nome: &str,
        escopo: &str,
        tipo: &str,
        fluxo_id: Option<i32>,
    ) -> Result<CampoPersonalizado, DbError>;

    /// Cria o campo com tudo o que o distingue.
    ///
    /// O [`CampoPersonalizadoRepository::criar`] acima nasceu para o seed e
    /// deixa de fora justamente o que a tela configura — descrição, opções,
    /// obrigatoriedade, dica de extração. Enquanto não havia caminho para
    /// criar um campo pela tela, a diferença não aparecia.
    #[allow(clippy::too_many_arguments)]
    async fn criar_completo(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        novo: NovoCampoPersonalizado<'_>,
    ) -> Result<CampoPersonalizado, DbError>;

    /// Atualiza o que a tela edita. **Não mexe em `slug`, `escopo` nem
    /// `fluxo_id`**: os três são a identidade do campo, e o slug já está
    /// gravado dentro dos valores extraídos pela IA — trocá-lo órfãaria o que
    /// foi coletado.
    #[allow(clippy::too_many_arguments)]
    async fn atualizar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i64,
        edicao: EdicaoCampoPersonalizado<'_>,
    ) -> Result<bool, DbError>;

    /// Desativa (soft): `ativo = false`.
    ///
    /// Apagar levaria junto os valores já coletados — o `ON DELETE CASCADE` de
    /// `atu_valor_campo` — e com eles o histórico das fichas. Um campo que
    /// deixou de ser usado não apaga o que ele já registrou.
    async fn desativar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i64,
    ) -> Result<bool, DbError>;

    /// Todos os campos do tenant, ativos e inativos, para a tela de
    /// configuração. As telas de atendimento usam `listar_por_escopo`.
    async fn listar_todos(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<CampoPersonalizado>, DbError>;

    async fn listar_por_escopo(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        escopo: &str,
        fluxo_id: Option<i32>,
    ) -> Result<Vec<CampoPersonalizado>, DbError>;
}

#[async_trait]
pub trait ValorCampoRepository: Send + Sync {
    async fn upsert(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        campo_id: i64,
        valor: serde_json::Value,
        origem: &str,
        confianca: Option<f64>,
    ) -> Result<ValorCampoAtendimento, DbError>;

    /// Grava um valor que a **IA** extraiu, sem passar por cima de gente.
    ///
    /// Separado do [`ValorCampoRepository::upsert`] por causa do `WHERE` no
    /// `DO UPDATE`, que é a regra inteira:
    ///
    /// - **`editado_por_id IS NULL`** — se uma pessoa escreveu ali, ela viu a
    ///   conversa e decidiu. A IA não desfaz isso.
    /// - **`valor <> 'null'`** — `null` é o valor apagado de propósito: alguém
    ///   leu o que a IA pôs e discordou. Repreencher seria insistir.
    ///
    /// Devolve `true` quando gravou. `false` significa que a linha existe e
    /// tem dono — não é erro, é a guarda funcionando, e quem chama conta isso
    /// para o log em vez de tratar como falha.
    async fn upsert_da_ia(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        campo_id: i64,
        valor: serde_json::Value,
        confianca: f64,
        mensagem_origem_id: Option<i32>,
    ) -> Result<bool, DbError>;

    async fn listar_por_atendimento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<Vec<ValorCampoAtendimento>, DbError>;
}

pub struct PostgresCampoPersonalizadoRepository;
pub struct PostgresValorCampoRepository;

#[async_trait]
impl CampoPersonalizadoRepository for PostgresCampoPersonalizadoRepository {
    #[tracing::instrument(skip_all, fields(slug = %slug, escopo = %escopo))]
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        slug: &str,
        nome: &str,
        escopo: &str,
        tipo: &str,
        fluxo_id: Option<i32>,
    ) -> Result<CampoPersonalizado, DbError> {
        ctx.exigir_qualquer(&["configuracoes:write", "tenant:admin"])?;
        let row = sqlx::query_as!(
            CampoPersonalizado,
            r#"INSERT INTO atu_campo_personalizado (tenant_id, slug, nome, escopo, tipo, fluxo_id)
               VALUES ($1, $2, $3, $4, $5, $6)
               RETURNING id, tenant_id, slug, nome, descricao, escopo, fluxo_id, tipo,
                         opcoes, obrigatorio, extrair_automaticamente, extrair_hint,
                         mostrar_no_card, ordem, ativo, data_criacao, data_atualizacao"#,
            ctx.tenant_id,
            slug,
            nome,
            escopo,
            tipo,
            fluxo_id
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(slug = %novo.slug, escopo = %novo.escopo))]
    async fn criar_completo(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        novo: NovoCampoPersonalizado<'_>,
    ) -> Result<CampoPersonalizado, DbError> {
        ctx.exigir_qualquer(&["configuracoes:write", "tenant:admin"])?;
        let row = sqlx::query_as!(
            CampoPersonalizado,
            r#"INSERT INTO atu_campo_personalizado
                   (tenant_id, slug, nome, descricao, escopo, fluxo_id, tipo,
                    opcoes, obrigatorio, extrair_automaticamente, extrair_hint,
                    mostrar_no_card, ordem)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
               RETURNING id, tenant_id, slug, nome, descricao, escopo, fluxo_id,
                         tipo, opcoes, obrigatorio, extrair_automaticamente,
                         extrair_hint, mostrar_no_card, ordem, ativo,
                         data_criacao, data_atualizacao"#,
            ctx.tenant_id,
            novo.slug,
            novo.nome,
            novo.descricao,
            novo.escopo,
            novo.fluxo_id,
            novo.tipo,
            novo.opcoes,
            novo.obrigatorio,
            novo.extrair_automaticamente,
            novo.extrair_hint,
            novo.mostrar_no_card,
            novo.ordem
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(id = id))]
    async fn atualizar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i64,
        edicao: EdicaoCampoPersonalizado<'_>,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["configuracoes:write", "tenant:admin"])?;
        let res = sqlx::query!(
            r#"UPDATE atu_campo_personalizado
                  SET nome = $1, descricao = $2, tipo = $3, opcoes = $4,
                      obrigatorio = $5, extrair_automaticamente = $6,
                      extrair_hint = $7, mostrar_no_card = $8, ordem = $9,
                      ativo = $10, data_atualizacao = NOW()
                WHERE tenant_id = $11 AND id = $12"#,
            edicao.nome,
            edicao.descricao,
            edicao.tipo,
            edicao.opcoes,
            edicao.obrigatorio,
            edicao.extrair_automaticamente,
            edicao.extrair_hint,
            edicao.mostrar_no_card,
            edicao.ordem,
            edicao.ativo,
            ctx.tenant_id,
            id
        )
        .execute(&mut **tx)
        .await?;
        Ok(res.rows_affected() > 0)
    }

    #[tracing::instrument(skip_all, fields(id = id))]
    async fn desativar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i64,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["configuracoes:write", "tenant:admin"])?;
        let res = sqlx::query!(
            r#"UPDATE atu_campo_personalizado
                  SET ativo = false, data_atualizacao = NOW()
                WHERE tenant_id = $1 AND id = $2 AND ativo = true"#,
            ctx.tenant_id,
            id
        )
        .execute(&mut **tx)
        .await?;
        Ok(res.rows_affected() > 0)
    }

    #[tracing::instrument(skip_all)]
    async fn listar_todos(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<CampoPersonalizado>, DbError> {
        ctx.exigir_qualquer(&["configuracoes:read", "tenant:admin"])?;
        let rows = sqlx::query_as!(
            CampoPersonalizado,
            r#"SELECT id, tenant_id, slug, nome, descricao, escopo, fluxo_id,
                      tipo, opcoes, obrigatorio, extrair_automaticamente,
                      extrair_hint, mostrar_no_card, ordem, ativo,
                      data_criacao, data_atualizacao
                 FROM atu_campo_personalizado
                WHERE tenant_id = $1
                ORDER BY escopo, ordem, nome"#,
            ctx.tenant_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

    #[tracing::instrument(skip_all, fields(escopo = %escopo))]
    async fn listar_por_escopo(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        escopo: &str,
        fluxo_id: Option<i32>,
    ) -> Result<Vec<CampoPersonalizado>, DbError> {
        let rows = sqlx::query_as!(
            CampoPersonalizado,
            r#"SELECT id, tenant_id, slug, nome, descricao, escopo, fluxo_id, tipo,
                      opcoes, obrigatorio, extrair_automaticamente, extrair_hint,
                      mostrar_no_card, ordem, ativo, data_criacao, data_atualizacao
               FROM atu_campo_personalizado
               WHERE tenant_id = $1 AND escopo = $2
                 AND ($3::int IS NULL OR fluxo_id = $3) AND ativo = true
               ORDER BY ordem, nome"#,
            ctx.tenant_id,
            escopo,
            fluxo_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }
}

#[async_trait]
impl ValorCampoRepository for PostgresValorCampoRepository {
    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id, campo_id = campo_id))]
    async fn upsert(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        campo_id: i64,
        valor: serde_json::Value,
        origem: &str,
        confianca: Option<f64>,
    ) -> Result<ValorCampoAtendimento, DbError> {
        let row = sqlx::query_as!(
            ValorCampoAtendimento,
            r#"INSERT INTO atu_valor_campo
                   (tenant_id, atendimento_id, campo_id, valor, origem, confianca)
               VALUES ($1, $2, $3, $4, $5, $6)
               ON CONFLICT (tenant_id, atendimento_id, campo_id) DO UPDATE
                   SET valor = EXCLUDED.valor,
                       origem = EXCLUDED.origem,
                       confianca = EXCLUDED.confianca,
                       data_atualizacao = NOW()
               RETURNING id, tenant_id, atendimento_id, campo_id, valor, origem,
                         confianca, mensagem_origem_id, editado_por_id, data_atualizacao"#,
            ctx.tenant_id,
            atendimento_id,
            campo_id,
            valor,
            origem,
            confianca
        )
        .fetch_one(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id))]
    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id, campo_id = campo_id))]
    async fn upsert_da_ia(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        campo_id: i64,
        valor: serde_json::Value,
        confianca: f64,
        mensagem_origem_id: Option<i32>,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
        // P10 — a guarda que faltava contra a v1 (`extract_custom_fields_async`):
        // a IA só troca um valor DELA por outro de confiança igual ou maior.
        // Sem isso, uma extração tardia e insegura rebaixava um valor firme —
        // o e-mail lido com 0,95 na primeira mensagem virava o palpite de 0,6
        // da décima. Igual (e não só maior, como na v1) deixa a correção mais
        // recente ganhar quando o modelo tem a mesma certeza: o cliente que
        // corrige o próprio e-mail está certo da segunda vez.
        //
        // Sem macro: o texto da consulta mudou, e o cache `.sqlx` não o conhece.
        let res = sqlx::query(
            r#"INSERT INTO atu_valor_campo
                   (tenant_id, atendimento_id, campo_id, valor, origem,
                    confianca, mensagem_origem_id)
               VALUES ($1, $2, $3, $4, 'IA', $5, $6)
               ON CONFLICT (tenant_id, atendimento_id, campo_id) DO UPDATE
                   SET valor = EXCLUDED.valor,
                       origem = 'IA',
                       confianca = EXCLUDED.confianca,
                       mensagem_origem_id = EXCLUDED.mensagem_origem_id,
                       data_atualizacao = NOW()
                 WHERE atu_valor_campo.editado_por_id IS NULL
                   AND atu_valor_campo.origem <> 'MANUAL'
                   AND atu_valor_campo.valor <> 'null'::jsonb
                   AND (atu_valor_campo.confianca IS NULL
                        OR EXCLUDED.confianca >= atu_valor_campo.confianca)"#,
        )
        .bind(ctx.tenant_id)
        .bind(atendimento_id)
        .bind(campo_id)
        .bind(valor)
        .bind(confianca)
        .bind(mensagem_origem_id)
        .execute(&mut **tx)
        .await?;
        Ok(res.rows_affected() > 0)
    }

    async fn listar_por_atendimento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<Vec<ValorCampoAtendimento>, DbError> {
        let rows = sqlx::query_as!(
            ValorCampoAtendimento,
            r#"SELECT id, tenant_id, atendimento_id, campo_id, valor, origem,
                      confianca, mensagem_origem_id, editado_por_id, data_atualizacao
               FROM atu_valor_campo
               WHERE tenant_id = $1 AND atendimento_id = $2"#,
            ctx.tenant_id,
            atendimento_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }
}
