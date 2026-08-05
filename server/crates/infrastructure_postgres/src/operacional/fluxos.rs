use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct FluxoAtendimento {
    pub id: i32,
    pub tenant_id: Uuid,
    pub departamento_id: i32,
    pub nome: String,
    pub descricao: Option<String>,
    pub ativo: bool,
    pub data_criacao: DateTime<Utc>,
    pub data_atualizacao: DateTime<Utc>,
}

/// Projeção leve de um fluxo ativo do tenant para o Responder (N6.3): inclui o nome
/// do setor (departamento) para compor a chave "Setor - descrição" esperada pelo
/// ia_engine.
#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct FluxoDisponivel {
    pub id: i32,
    pub setor: String,
    pub nome: String,
    pub descricao: Option<String>,
}

/// Fluxo com o que a tela de gestão precisa mostrar.
///
/// O nome do departamento e as contagens vêm no mesmo SELECT: uma consulta por
/// linha para descobrir "de quem é este fluxo" e "quantas etapas tem" seria N+1
/// numa lista que o tenant abre o tempo todo.
#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct FluxoResumo {
    pub id: i32,
    pub departamento_id: i32,
    pub departamento_nome: String,
    pub nome: String,
    pub descricao: Option<String>,
    pub ativo: bool,
    pub etapas: i64,
    /// Atendimentos que ainda não terminaram neste fluxo. É o número que diz se
    /// desativar o fluxo vai deixar gente no meio do caminho.
    pub atendimentos_abertos: i64,
    pub data_criacao: DateTime<Utc>,
}

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct EtapaFluxo {
    pub id: i32,
    pub tenant_id: Uuid,
    pub fluxo_id: i32,
    pub nome: String,
    pub descricao: Option<String>,
    pub ordem: i32,
    pub cor: String,
    pub tipo_etapa: String,
    pub permite_atribuicao: bool,
    pub automatico: bool,
    pub regras_transicao: serde_json::Value,
    pub campos_obrigatorios: serde_json::Value,
    pub ativo: bool,
    pub data_criacao: DateTime<Utc>,
}

#[async_trait]
pub trait FluxoAtendimentoRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        departamento_id: i32,
        nome: &str,
        descricao: Option<&str>,
    ) -> Result<FluxoAtendimento, DbError>;

    /// Todos os fluxos do tenant, ativos e inativos, com departamento e
    /// contagens. Inativos aparecem porque some-los da tela deixaria o tenant
    /// sem como reativar o que desativou por engano.
    async fn listar_por_tenant(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<FluxoResumo>, DbError>;

    async fn atualizar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
        nome: &str,
        descricao: Option<&str>,
        ativo: bool,
    ) -> Result<bool, DbError>;

    /// Desativa — não apaga. Atendimentos apontam para o fluxo e para as etapas
    /// dele; apagar a linha levaria o histórico junto.
    async fn desativar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<bool, DbError>;

    /// Atendimentos ainda abertos no fluxo. Desativar por baixo deles deixaria
    /// conversas num quadro que ninguém mais abre.
    async fn contar_atendimentos_abertos(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<i64, DbError>;

    async fn buscar_por_departamento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        departamento_id: i32,
    ) -> Result<Vec<FluxoAtendimento>, DbError>;

    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<FluxoAtendimento>, DbError>;

    /// Retorna o primeiro fluxo ativo do tenant (menor id), usado como fluxo padrão
    /// quando o atendimento ainda não tem fluxo atribuído (política de ticket/Kanban).
    async fn buscar_primeiro_ativo(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Option<FluxoAtendimento>, DbError>;

    /// Lista todos os fluxos ativos do tenant (com o nome do setor/departamento),
    /// para o worker montar `fluxos_disponiveis` do Responder (N6.3).
    async fn listar_ativos_do_tenant(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<FluxoDisponivel>, DbError>;
}

#[async_trait]
pub trait EtapaFluxoRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        fluxo_id: i32,
        nome: &str,
        ordem: i32,
        tipo_etapa: &str,
        cor: Option<&str>,
    ) -> Result<EtapaFluxo, DbError>;

    async fn listar_por_fluxo(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        fluxo_id: i32,
    ) -> Result<Vec<EtapaFluxo>, DbError>;

    /// Retorna a primeira etapa do tipo 'fila' do fluxo (etapa de entrada).
    async fn get_etapa_inicial(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        fluxo_id: i32,
    ) -> Result<Option<EtapaFluxo>, DbError>;

    /// Primeira etapa ativa de um tipo no fluxo, na ordem do quadro.
    ///
    /// É por aqui que uma mudança de status encontra a coluna correspondente.
    /// "Primeira" e não "a" porque nada impede o tenant de ter duas colunas de
    /// espera — a da esquerda é a que recebe.
    async fn buscar_por_tipo(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        fluxo_id: i32,
        tipo_etapa: &str,
    ) -> Result<Option<EtapaFluxo>, DbError>;

    /// Próxima posição livre no fim do fluxo.
    ///
    /// Conta pelo `MAX(ordem)`, não pelo número de etapas ativas: a `UNIQUE
    /// (fluxo_id, ordem)` também vale para as desativadas, e reaproveitar a
    /// posição de uma etapa desativada estouraria a restrição.
    async fn proxima_ordem(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        fluxo_id: i32,
    ) -> Result<i32, DbError>;

    async fn atualizar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
        nome: &str,
        descricao: Option<&str>,
        cor: &str,
        tipo_etapa: &str,
    ) -> Result<bool, DbError>;

    async fn desativar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<bool, DbError>;

    /// Troca a etapa de lugar com a vizinha na direção pedida.
    ///
    /// Em três passos, não em dois: a `UNIQUE (fluxo_id, ordem)` recusa o
    /// instante em que as duas ocupariam a mesma posição, então uma delas passa
    /// por um valor negativo temporário. Tudo na mesma transação.
    ///
    /// Retorna `false` quando não há vizinha — a etapa já está na ponta.
    async fn trocar_ordem(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
        para_cima: bool,
    ) -> Result<bool, DbError>;

    /// Atendimentos parados nesta etapa agora.
    async fn contar_atendimentos(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<i64, DbError>;

    /// Quantas etapas ativas de um tipo o fluxo tem. Usado para não deixar o
    /// fluxo sem porta de entrada.
    async fn contar_ativas_do_tipo(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        fluxo_id: i32,
        tipo_etapa: &str,
    ) -> Result<i64, DbError>;

    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<EtapaFluxo>, DbError>;
}

pub struct PostgresFluxoAtendimentoRepository;
pub struct PostgresEtapaFluxoRepository;

#[async_trait]
impl FluxoAtendimentoRepository for PostgresFluxoAtendimentoRepository {
    #[tracing::instrument(skip_all, fields(departamento_id = departamento_id, nome = %nome))]
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        departamento_id: i32,
        nome: &str,
        descricao: Option<&str>,
    ) -> Result<FluxoAtendimento, DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin"])?;
        let row = sqlx::query_as!(
            FluxoAtendimento,
            r#"INSERT INTO oraculo_fluxo_atendimento (tenant_id, departamento_id, nome, descricao)
               VALUES ($1, $2, $3, $4)
               RETURNING id, tenant_id, departamento_id, nome, descricao, ativo,
                         data_criacao, data_atualizacao"#,
            ctx.tenant_id,
            departamento_id,
            nome,
            descricao
        )
        .fetch_one(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn listar_por_tenant(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<FluxoResumo>, DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin", "atendimentos:read"])?;
        let rows = sqlx::query_as!(
            FluxoResumo,
            r#"SELECT f.id, f.departamento_id, d.nome AS "departamento_nome!",
                      f.nome, f.descricao, f.ativo, f.data_criacao,
                      (SELECT COUNT(*) FROM oraculo_etapa_fluxo e
                        WHERE e.fluxo_id = f.id AND e.ativo = true) AS "etapas!",
                      -- Vocabulário de status da v1: resolvido/cancelado/arquivado
                      -- são os fins de linha; o resto ainda está vivo.
                      (SELECT COUNT(*) FROM oraculo_atendimento a
                        WHERE a.fluxo_atendimento_id = f.id
                          AND a.status NOT IN ('resolvido', 'cancelado', 'arquivado'))
                        AS "atendimentos_abertos!"
               FROM oraculo_fluxo_atendimento f
               JOIN oraculo_departamento d
                 ON d.id = f.departamento_id AND d.tenant_id = f.tenant_id
               WHERE f.tenant_id = $1
               ORDER BY d.nome, f.nome"#,
            ctx.tenant_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

    #[tracing::instrument(skip_all, fields(id = id))]
    async fn atualizar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
        nome: &str,
        descricao: Option<&str>,
        ativo: bool,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin"])?;
        let res = sqlx::query!(
            r#"UPDATE oraculo_fluxo_atendimento
                  SET nome = $3, descricao = $4, ativo = $5, data_atualizacao = NOW()
                WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            id,
            nome,
            descricao,
            ativo
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
        id: i32,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin"])?;
        let res = sqlx::query!(
            r#"UPDATE oraculo_fluxo_atendimento
                  SET ativo = false, data_atualizacao = NOW()
                WHERE tenant_id = $1 AND id = $2 AND ativo = true"#,
            ctx.tenant_id,
            id
        )
        .execute(&mut **tx)
        .await?;
        Ok(res.rows_affected() > 0)
    }

    #[tracing::instrument(skip_all, fields(id = id))]
    async fn contar_atendimentos_abertos(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<i64, DbError> {
        let total = sqlx::query_scalar!(
            r#"SELECT COUNT(*) AS "total!"
                 FROM oraculo_atendimento
                WHERE tenant_id = $1 AND fluxo_atendimento_id = $2
                  AND status NOT IN ('resolvido', 'cancelado', 'arquivado')"#,
            ctx.tenant_id,
            id
        )
        .fetch_one(&mut **tx)
        .await?;
        Ok(total)
    }

    #[tracing::instrument(skip_all, fields(departamento_id = departamento_id))]
    async fn buscar_por_departamento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        departamento_id: i32,
    ) -> Result<Vec<FluxoAtendimento>, DbError> {
        let rows = sqlx::query_as!(
            FluxoAtendimento,
            r#"SELECT id, tenant_id, departamento_id, nome, descricao, ativo,
                      data_criacao, data_atualizacao
               FROM oraculo_fluxo_atendimento
               WHERE tenant_id = $1 AND departamento_id = $2 AND ativo = true
               ORDER BY nome"#,
            ctx.tenant_id,
            departamento_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

    #[tracing::instrument(skip_all, fields(id = id))]
    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<FluxoAtendimento>, DbError> {
        let row = sqlx::query_as!(
            FluxoAtendimento,
            r#"SELECT id, tenant_id, departamento_id, nome, descricao, ativo,
                      data_criacao, data_atualizacao
               FROM oraculo_fluxo_atendimento
               WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            id
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all)]
    async fn buscar_primeiro_ativo(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Option<FluxoAtendimento>, DbError> {
        // Query em runtime (sem macro) para não exigir cache .sqlx no build offline.
        let row = sqlx::query_as::<_, FluxoAtendimento>(
            r#"SELECT id, tenant_id, departamento_id, nome, descricao, ativo,
                      data_criacao, data_atualizacao
               FROM oraculo_fluxo_atendimento
               WHERE tenant_id = $1 AND ativo = true
               ORDER BY id ASC
               LIMIT 1"#,
        )
        .bind(ctx.tenant_id)
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn listar_ativos_do_tenant(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<FluxoDisponivel>, DbError> {
        // Query em runtime (sem macro) para não exigir cache .sqlx no build offline.
        let rows = sqlx::query_as::<_, FluxoDisponivel>(
            r#"SELECT f.id, d.nome AS setor, f.nome, f.descricao
               FROM oraculo_fluxo_atendimento f
               JOIN oraculo_departamento d
                 ON d.id = f.departamento_id AND d.tenant_id = f.tenant_id
               WHERE f.tenant_id = $1 AND f.ativo = true AND d.ativo = true
               ORDER BY d.nome, f.nome"#,
        )
        .bind(ctx.tenant_id)
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }
}

#[async_trait]
impl EtapaFluxoRepository for PostgresEtapaFluxoRepository {
    #[tracing::instrument(skip_all, fields(fluxo_id = fluxo_id, ordem = ordem))]
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        fluxo_id: i32,
        nome: &str,
        ordem: i32,
        tipo_etapa: &str,
        cor: Option<&str>,
    ) -> Result<EtapaFluxo, DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin"])?;
        let cor_val = cor.unwrap_or("#6B7280");
        let row = sqlx::query_as!(
            EtapaFluxo,
            r#"INSERT INTO oraculo_etapa_fluxo (tenant_id, fluxo_id, nome, ordem, tipo_etapa, cor)
               VALUES ($1, $2, $3, $4, $5, $6)
               RETURNING id, tenant_id, fluxo_id, nome, descricao, ordem, cor, tipo_etapa,
                         permite_atribuicao, automatico, regras_transicao, campos_obrigatorios,
                         ativo, data_criacao"#,
            ctx.tenant_id,
            fluxo_id,
            nome,
            ordem,
            tipo_etapa,
            cor_val
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(fluxo_id = fluxo_id))]
    async fn listar_por_fluxo(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        fluxo_id: i32,
    ) -> Result<Vec<EtapaFluxo>, DbError> {
        let rows = sqlx::query_as!(
            EtapaFluxo,
            r#"SELECT id, tenant_id, fluxo_id, nome, descricao, ordem, cor, tipo_etapa,
                      permite_atribuicao, automatico, regras_transicao, campos_obrigatorios,
                      ativo, data_criacao
               FROM oraculo_etapa_fluxo
               WHERE tenant_id = $1 AND fluxo_id = $2 AND ativo = true
               ORDER BY ordem"#,
            ctx.tenant_id,
            fluxo_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

    #[tracing::instrument(skip_all, fields(fluxo_id = fluxo_id))]
    async fn get_etapa_inicial(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        fluxo_id: i32,
    ) -> Result<Option<EtapaFluxo>, DbError> {
        let row = sqlx::query_as!(
            EtapaFluxo,
            r#"SELECT id, tenant_id, fluxo_id, nome, descricao, ordem, cor, tipo_etapa,
                      permite_atribuicao, automatico, regras_transicao, campos_obrigatorios,
                      ativo, data_criacao
               FROM oraculo_etapa_fluxo
               WHERE tenant_id = $1 AND fluxo_id = $2
                 AND tipo_etapa = 'fila' AND ativo = true
               ORDER BY ordem ASC
               LIMIT 1"#,
            ctx.tenant_id,
            fluxo_id
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(fluxo_id = fluxo_id, tipo_etapa = %tipo_etapa))]
    async fn buscar_por_tipo(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        fluxo_id: i32,
        tipo_etapa: &str,
    ) -> Result<Option<EtapaFluxo>, DbError> {
        let row = sqlx::query_as!(
            EtapaFluxo,
            r#"SELECT id, tenant_id, fluxo_id, nome, descricao, ordem, cor, tipo_etapa,
                      permite_atribuicao, automatico, regras_transicao, campos_obrigatorios,
                      ativo, data_criacao
               FROM oraculo_etapa_fluxo
               WHERE tenant_id = $1 AND fluxo_id = $2
                 AND tipo_etapa = $3 AND ativo = true
               ORDER BY ordem ASC
               LIMIT 1"#,
            ctx.tenant_id,
            fluxo_id,
            tipo_etapa
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(fluxo_id = fluxo_id))]
    async fn proxima_ordem(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        fluxo_id: i32,
    ) -> Result<i32, DbError> {
        let ordem = sqlx::query_scalar!(
            r#"SELECT COALESCE(MAX(ordem), 0) + 1 AS "proxima!"
                 FROM oraculo_etapa_fluxo
                WHERE tenant_id = $1 AND fluxo_id = $2"#,
            ctx.tenant_id,
            fluxo_id
        )
        .fetch_one(&mut **tx)
        .await?;
        Ok(ordem)
    }

    #[tracing::instrument(skip_all, fields(id = id))]
    async fn atualizar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
        nome: &str,
        descricao: Option<&str>,
        cor: &str,
        tipo_etapa: &str,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin"])?;
        let res = sqlx::query!(
            r#"UPDATE oraculo_etapa_fluxo
                  SET nome = $3, descricao = $4, cor = $5, tipo_etapa = $6
                WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            id,
            nome,
            descricao,
            cor,
            tipo_etapa
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
        id: i32,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin"])?;
        let res = sqlx::query!(
            r#"UPDATE oraculo_etapa_fluxo
                  SET ativo = false
                WHERE tenant_id = $1 AND id = $2 AND ativo = true"#,
            ctx.tenant_id,
            id
        )
        .execute(&mut **tx)
        .await?;
        Ok(res.rows_affected() > 0)
    }

    #[tracing::instrument(skip_all, fields(id = id, para_cima = para_cima))]
    async fn trocar_ordem(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
        para_cima: bool,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin"])?;

        let atual = sqlx::query!(
            r#"SELECT fluxo_id, ordem FROM oraculo_etapa_fluxo
                WHERE tenant_id = $1 AND id = $2 AND ativo = true"#,
            ctx.tenant_id,
            id
        )
        .fetch_optional(&mut **tx)
        .await?;
        let Some(atual) = atual else {
            return Err(DbError::NotFound);
        };

        // A vizinha é a etapa ATIVA mais próxima na direção pedida, não
        // `ordem ± 1`: desativar uma etapa deixa buracos na numeração, e mover
        // para um buraco não moveria nada aos olhos de quem vê a tela.
        let vizinha = if para_cima {
            sqlx::query!(
                r#"SELECT id, ordem FROM oraculo_etapa_fluxo
                    WHERE tenant_id = $1 AND fluxo_id = $2 AND ativo = true
                      AND ordem < $3
                    ORDER BY ordem DESC LIMIT 1"#,
                ctx.tenant_id,
                atual.fluxo_id,
                atual.ordem
            )
            .fetch_optional(&mut **tx)
            .await?
            .map(|r| (r.id, r.ordem))
        } else {
            sqlx::query!(
                r#"SELECT id, ordem FROM oraculo_etapa_fluxo
                    WHERE tenant_id = $1 AND fluxo_id = $2 AND ativo = true
                      AND ordem > $3
                    ORDER BY ordem ASC LIMIT 1"#,
                ctx.tenant_id,
                atual.fluxo_id,
                atual.ordem
            )
            .fetch_optional(&mut **tx)
            .await?
            .map(|r| (r.id, r.ordem))
        };

        let Some((vizinha_id, vizinha_ordem)) = vizinha else {
            return Ok(false);
        };

        // Escada por um valor negativo: `UNIQUE (fluxo_id, ordem)` recusa o
        // instante em que as duas ocupariam a mesma posição.
        let temporaria = -atual.ordem - 1;
        for (alvo, nova) in [
            (id, temporaria),
            (vizinha_id, atual.ordem),
            (id, vizinha_ordem),
        ] {
            sqlx::query!(
                r#"UPDATE oraculo_etapa_fluxo SET ordem = $3
                    WHERE tenant_id = $1 AND id = $2"#,
                ctx.tenant_id,
                alvo,
                nova
            )
            .execute(&mut **tx)
            .await?;
        }
        Ok(true)
    }

    #[tracing::instrument(skip_all, fields(id = id))]
    async fn contar_atendimentos(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<i64, DbError> {
        let total = sqlx::query_scalar!(
            r#"SELECT COUNT(*) AS "total!"
                 FROM oraculo_atendimento
                WHERE tenant_id = $1 AND etapa_atual_id = $2"#,
            ctx.tenant_id,
            id
        )
        .fetch_one(&mut **tx)
        .await?;
        Ok(total)
    }

    #[tracing::instrument(skip_all, fields(fluxo_id = fluxo_id, tipo_etapa = %tipo_etapa))]
    async fn contar_ativas_do_tipo(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        fluxo_id: i32,
        tipo_etapa: &str,
    ) -> Result<i64, DbError> {
        let total = sqlx::query_scalar!(
            r#"SELECT COUNT(*) AS "total!"
                 FROM oraculo_etapa_fluxo
                WHERE tenant_id = $1 AND fluxo_id = $2
                  AND tipo_etapa = $3 AND ativo = true"#,
            ctx.tenant_id,
            fluxo_id,
            tipo_etapa
        )
        .fetch_one(&mut **tx)
        .await?;
        Ok(total)
    }

    #[tracing::instrument(skip_all, fields(id = id))]
    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<EtapaFluxo>, DbError> {
        let row = sqlx::query_as!(
            EtapaFluxo,
            r#"SELECT id, tenant_id, fluxo_id, nome, descricao, ordem, cor, tipo_etapa,
                      permite_atribuicao, automatico, regras_transicao, campos_obrigatorios,
                      ativo, data_criacao
               FROM oraculo_etapa_fluxo
               WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            id
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }
}
