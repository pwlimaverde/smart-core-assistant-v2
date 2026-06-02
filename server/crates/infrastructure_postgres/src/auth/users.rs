use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::PgPool;

use crate::errors::DbError;

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct AuthUser {
    pub id: i32,
    pub username: String,
    pub email: String,
    pub password_hash: String,
    pub first_name: String,
    pub last_name: String,
    pub is_active: bool,
    pub is_staff: bool,
    pub is_superuser: bool,
    pub last_login: Option<DateTime<Utc>>,
    pub date_joined: DateTime<Utc>,
}

#[async_trait]
pub trait AuthUserRepository: Send + Sync {
    async fn criar(
        &self,
        pool: &PgPool,
        username: &str,
        email: &str,
        password_hash: &str,
        is_superuser: bool,
    ) -> Result<AuthUser, DbError>;

    async fn buscar_por_id(&self, pool: &PgPool, id: i32) -> Result<Option<AuthUser>, DbError>;

    async fn buscar_por_username(
        &self,
        pool: &PgPool,
        username: &str,
    ) -> Result<Option<AuthUser>, DbError>;

    async fn buscar_por_email(
        &self,
        pool: &PgPool,
        email: &str,
    ) -> Result<Option<AuthUser>, DbError>;

    async fn atualizar_ultimo_login(&self, pool: &PgPool, user_id: i32) -> Result<(), DbError>;

    async fn atualizar_senha(
        &self,
        pool: &PgPool,
        user_id: i32,
        password_hash: &str,
    ) -> Result<(), DbError>;

    async fn desativar(&self, pool: &PgPool, user_id: i32) -> Result<(), DbError>;
}

pub struct PostgresAuthUserRepository;

#[async_trait]
impl AuthUserRepository for PostgresAuthUserRepository {
    async fn criar(
        &self,
        pool: &PgPool,
        username: &str,
        email: &str,
        password_hash: &str,
        is_superuser: bool,
    ) -> Result<AuthUser, DbError> {
        let row = sqlx::query_as!(
            AuthUser,
            r#"INSERT INTO auth_user (username, email, password_hash, is_superuser)
               VALUES ($1, $2, $3, $4)
               RETURNING id, username, email, password_hash, first_name, last_name,
                         is_active, is_staff, is_superuser, last_login, date_joined"#,
            username,
            email,
            password_hash,
            is_superuser
        )
        .fetch_one(pool)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }

    async fn buscar_por_id(&self, pool: &PgPool, id: i32) -> Result<Option<AuthUser>, DbError> {
        let row = sqlx::query_as!(
            AuthUser,
            r#"SELECT id, username, email, password_hash, first_name, last_name,
                      is_active, is_staff, is_superuser, last_login, date_joined
               FROM auth_user WHERE id = $1"#,
            id
        )
        .fetch_optional(pool)
        .await?;
        Ok(row)
    }

    async fn buscar_por_username(
        &self,
        pool: &PgPool,
        username: &str,
    ) -> Result<Option<AuthUser>, DbError> {
        let row = sqlx::query_as!(
            AuthUser,
            r#"SELECT id, username, email, password_hash, first_name, last_name,
                      is_active, is_staff, is_superuser, last_login, date_joined
               FROM auth_user WHERE username = $1"#,
            username
        )
        .fetch_optional(pool)
        .await?;
        Ok(row)
    }

    async fn buscar_por_email(
        &self,
        pool: &PgPool,
        email: &str,
    ) -> Result<Option<AuthUser>, DbError> {
        let row = sqlx::query_as!(
            AuthUser,
            r#"SELECT id, username, email, password_hash, first_name, last_name,
                      is_active, is_staff, is_superuser, last_login, date_joined
               FROM auth_user WHERE email = $1"#,
            email
        )
        .fetch_optional(pool)
        .await?;
        Ok(row)
    }

    async fn atualizar_ultimo_login(&self, pool: &PgPool, user_id: i32) -> Result<(), DbError> {
        sqlx::query!(
            "UPDATE auth_user SET last_login = NOW() WHERE id = $1",
            user_id
        )
        .execute(pool)
        .await?;
        Ok(())
    }

    async fn atualizar_senha(
        &self,
        pool: &PgPool,
        user_id: i32,
        password_hash: &str,
    ) -> Result<(), DbError> {
        sqlx::query!(
            "UPDATE auth_user SET password_hash = $1 WHERE id = $2",
            password_hash,
            user_id
        )
        .execute(pool)
        .await?;
        Ok(())
    }

    async fn desativar(&self, pool: &PgPool, user_id: i32) -> Result<(), DbError> {
        sqlx::query!(
            "UPDATE auth_user SET is_active = false WHERE id = $1",
            user_id
        )
        .execute(pool)
        .await?;
        Ok(())
    }
}
