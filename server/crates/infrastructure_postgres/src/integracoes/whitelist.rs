use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct WhiteList {
    pub id: i32,
    pub tenant_id: Uuid,
    pub contact_id: Option<i32>,
    pub name: String,
    pub phone_number: String,
    pub active: bool,
    pub created_at: DateTime<Utc>,
}

#[async_trait]
pub trait WhiteListRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        name: &str,
        phone_number: &str,
        contact_id: Option<i32>,
    ) -> Result<WhiteList, DbError>;

    /// Verifica se um número está na whitelist do tenant.
    async fn esta_na_lista(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        phone_number: &str,
    ) -> Result<bool, DbError>;

    async fn listar_ativas(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<WhiteList>, DbError>;

    /// P7 — a lista INTEIRA, inclusive os desligados.
    ///
    /// A tela precisa dos inativos: desligar é como se volta a atender alguém
    /// sem perder o registro de que ele já esteve fora. `listar_ativas` é da
    /// ingestão, que só se importa com quem está valendo agora.
    async fn listar_todas(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<WhiteList>, DbError>;

    /// P7 — renomeia, corrige o número ou liga/desliga a regra.
    ///
    /// `None` no retorno = id inexistente ou de outro tenant; quem chama
    /// precisa saber para não auditar uma alteração que não houve.
    async fn atualizar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
        name: &str,
        phone_number: &str,
        active: bool,
    ) -> Result<Option<WhiteList>, DbError>;

    /// P7 — apaga a entrada de vez.
    ///
    /// Existe junto do desligar porque são coisas diferentes: desligar mantém a
    /// memória de que aquele número já foi ignorado; apagar é para o que entrou
    /// errado e não deveria constar.
    async fn remover(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<bool, DbError>;
}

pub struct PostgresWhiteListRepository;

#[async_trait]
impl WhiteListRepository for PostgresWhiteListRepository {
    #[tracing::instrument(skip_all)]
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        name: &str,
        phone_number: &str,
        contact_id: Option<i32>,
    ) -> Result<WhiteList, DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin"])?;
        let row = sqlx::query_as!(
            WhiteList,
            r#"INSERT INTO whatsapp_whitelist (tenant_id, name, phone_number, contact_id)
               VALUES ($1, $2, $3, $4)
               RETURNING id, tenant_id, contact_id, name, phone_number, active, created_at"#,
            ctx.tenant_id,
            name,
            phone_number,
            contact_id
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }

    #[tracing::instrument(skip_all)]
    async fn esta_na_lista(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        phone_number: &str,
    ) -> Result<bool, DbError> {
        let count = sqlx::query_scalar!(
            r#"SELECT COUNT(*) FROM whatsapp_whitelist
               WHERE tenant_id = $1 AND phone_number = $2 AND active = true"#,
            ctx.tenant_id,
            phone_number
        )
        .fetch_one(&mut **tx)
        .await?;
        Ok(count.unwrap_or(0) > 0)
    }

    #[tracing::instrument(skip_all)]
    async fn listar_ativas(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<WhiteList>, DbError> {
        let rows = sqlx::query_as!(
            WhiteList,
            r#"SELECT id, tenant_id, contact_id, name, phone_number, active, created_at
               FROM whatsapp_whitelist
               WHERE tenant_id = $1 AND active = true
               ORDER BY name"#,
            ctx.tenant_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

    // As três consultas abaixo são sem macro (`query_as::<_, T>`) de propósito:
    // consulta nova não está no cache `.sqlx`, e o build offline da CI quebra no
    // `cargo check` antes de qualquer teste rodar.

    #[tracing::instrument(skip_all)]
    async fn listar_todas(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<WhiteList>, DbError> {
        ctx.exigir_qualquer(&["operacional:read", "operacional:admin", "tenant:admin"])?;
        let rows = sqlx::query_as::<_, WhiteList>(
            r#"SELECT id, tenant_id, contact_id, name, phone_number, active, created_at
               FROM whatsapp_whitelist
               WHERE tenant_id = $1
               ORDER BY active DESC, name"#,
        )
        .bind(ctx.tenant_id)
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
        name: &str,
        phone_number: &str,
        active: bool,
    ) -> Result<Option<WhiteList>, DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin"])?;
        let row = sqlx::query_as::<_, WhiteList>(
            r#"UPDATE whatsapp_whitelist
                  SET name = $3, phone_number = $4, active = $5
                WHERE tenant_id = $1 AND id = $2
            RETURNING id, tenant_id, contact_id, name, phone_number, active, created_at"#,
        )
        .bind(ctx.tenant_id)
        .bind(id)
        .bind(name)
        .bind(phone_number)
        .bind(active)
        .fetch_optional(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(id = id))]
    async fn remover(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin"])?;
        let r = sqlx::query(r#"DELETE FROM whatsapp_whitelist WHERE tenant_id = $1 AND id = $2"#)
            .bind(ctx.tenant_id)
            .bind(id)
            .execute(&mut **tx)
            .await?;
        Ok(r.rows_affected() > 0)
    }
}
