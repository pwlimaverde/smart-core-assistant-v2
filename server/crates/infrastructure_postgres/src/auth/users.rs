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

/// Um usuário na visão do superusuário (D7), com o vínculo de tenant resolvido.
///
/// **Sem `password_hash`.** `AuthUser` carrega o hash porque serve ao login;
/// esta struct serve a uma listagem que trafega até o painel, e credencial não
/// atravessa fronteira que não precisa dela — nem em memória, nem em log.
#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct UsuarioGlobal {
    pub id: i32,
    pub username: String,
    pub email: String,
    pub first_name: String,
    pub last_name: String,
    pub is_active: bool,
    pub is_superuser: bool,
    pub last_login: Option<DateTime<Utc>>,
    pub date_joined: DateTime<Utc>,
    /// Tenant de que este usuário é **dono**, se for de algum.
    pub tenant_dono: Option<String>,
    /// Tenant em que este usuário é **funcionário**, se for de algum.
    pub tenant_membro: Option<String>,
    /// Papel como funcionário (`tenants_tenantuser.role`), quando houver.
    pub papel: Option<String>,
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

    /// D7 — lista usuários de TODOS os tenants, para o painel do superusuário.
    ///
    /// A v1 tinha isto no admin do Django e a v2 não tinha nada equivalente:
    /// `ListTenantUsers` resolve o tenant a partir das claims de quem chama, e
    /// portanto nunca enxerga além do próprio. Sem esta consulta, "o cliente diz
    /// que não consegue entrar" não tem por onde começar.
    ///
    /// `busca` casa em username, e-mail e nome. Vazio lista todo mundo.
    async fn listar_global(
        &self,
        pool: &PgPool,
        busca: &str,
        limite: i64,
        offset: i64,
    ) -> Result<Vec<UsuarioGlobal>, DbError>;

    /// D7 — bloqueia/desbloqueia o acesso de um usuário.
    ///
    /// Devolve `false` quando o usuário não existe. Generaliza [`Self::desativar`],
    /// que só sabia o caminho de ida — bloquear alguém sem poder desbloquear é
    /// uma porta que só fecha.
    async fn definir_ativo(
        &self,
        pool: &PgPool,
        user_id: i32,
        ativo: bool,
    ) -> Result<bool, DbError>;

    /// Lista todos os superusuários (tabela global, sem RLS), ordenados por id.
    async fn listar_superusers(&self, pool: &PgPool) -> Result<Vec<AuthUser>, DbError>;

    /// Remove fisicamente um superusuário pelo id. Só apaga se o registro for
    /// de fato superusuário (proteção contra apagar usuário comum por esta via).
    /// Retorna a quantidade de linhas afetadas (0 = não era superusuário/não existe).
    async fn deletar_superuser(&self, pool: &PgPool, user_id: i32) -> Result<u64, DbError>;
}

pub struct PostgresAuthUserRepository;

#[async_trait]
impl AuthUserRepository for PostgresAuthUserRepository {
    // `password_hash` é material de credencial: omitido do span.
    #[tracing::instrument(
        skip(self, pool, password_hash),
        fields(username = %username, email = %email, is_superuser),
        err
    )]
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

    #[tracing::instrument(level = "debug", skip(self, pool), fields(id), err)]
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

    #[tracing::instrument(level = "debug", skip(self, pool), fields(username = %username), err)]
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

    #[tracing::instrument(level = "debug", skip(self, pool), fields(email = %email), err)]
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

    #[tracing::instrument(skip(self, pool), fields(user_id), err)]
    async fn atualizar_ultimo_login(&self, pool: &PgPool, user_id: i32) -> Result<(), DbError> {
        sqlx::query!(
            "UPDATE auth_user SET last_login = NOW() WHERE id = $1",
            user_id
        )
        .execute(pool)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip(self, pool, password_hash), fields(user_id), err)]
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

    #[tracing::instrument(skip(self, pool), fields(user_id), err)]
    async fn desativar(&self, pool: &PgPool, user_id: i32) -> Result<(), DbError> {
        sqlx::query!(
            "UPDATE auth_user SET is_active = false WHERE id = $1",
            user_id
        )
        .execute(pool)
        .await?;
        Ok(())
    }

    /// `skip(self, pool)` e **sem `busca` nos campos**: o termo pesquisado é
    /// e-mail ou nome de gente, e um log de busca vira um log de PII.
    #[tracing::instrument(level = "debug", skip_all, fields(limite = limite, offset = offset), err)]
    async fn listar_global(
        &self,
        pool: &PgPool,
        busca: &str,
        limite: i64,
        offset: i64,
    ) -> Result<Vec<UsuarioGlobal>, DbError> {
        // ⚠️ **Exige pool com BYPASSRLS.** `auth_user` não tem RLS (é lida antes
        // de existir tenant na sessão), mas `tenants_tenant` e
        // `tenants_tenantuser` têm — e com FORCE. Sem `app.current_tenant`
        // definido, a política resolve para falso e os LEFT JOIN devolvem NULL
        // em TODA linha: a listagem sairia com todo mundo "sem tenant", que é
        // pior que um erro, porque parece um dado válido.
        //
        // Os dois vínculos possíveis: dono do tenant e funcionário. Um usuário
        // pode ser os dois, um, ou nenhum (superusuário do sistema).
        //
        // `ILIKE` com `%termo%` não usa índice; é aceitável porque a base de
        // usuários é pequena por natureza (uma linha por pessoa, não por
        // mensagem) e a listagem é paginada.
        let padrao = if busca.trim().is_empty() {
            "%".to_string()
        } else {
            format!("%{}%", busca.trim())
        };
        let rows = sqlx::query_as::<_, UsuarioGlobal>(
            r#"SELECT u.id, u.username, u.email, u.first_name, u.last_name,
                      u.is_active, u.is_superuser, u.last_login, u.date_joined,
                      dono.name  AS tenant_dono,
                      membro.name AS tenant_membro,
                      tu.role     AS papel
                 FROM auth_user u
                 LEFT JOIN tenants_tenant dono ON dono.owner_id = u.id
                 LEFT JOIN tenants_tenantuser tu ON tu.user_id = u.id
                 LEFT JOIN tenants_tenant membro ON membro.id = tu.tenant_id
                WHERE $1 = '%'
                   OR u.username ILIKE $1
                   OR u.email ILIKE $1
                   OR (u.first_name || ' ' || u.last_name) ILIKE $1
                ORDER BY u.date_joined DESC, u.id DESC
                LIMIT $2 OFFSET $3"#,
        )
        .bind(&padrao)
        .bind(limite)
        .bind(offset)
        .fetch_all(pool)
        .await?;
        Ok(rows)
    }

    #[tracing::instrument(skip(self, pool), fields(user_id = user_id, ativo = ativo), err)]
    async fn definir_ativo(
        &self,
        pool: &PgPool,
        user_id: i32,
        ativo: bool,
    ) -> Result<bool, DbError> {
        let res = sqlx::query("UPDATE auth_user SET is_active = $1 WHERE id = $2")
            .bind(ativo)
            .bind(user_id)
            .execute(pool)
            .await?;
        Ok(res.rows_affected() > 0)
    }

    #[tracing::instrument(level = "debug", skip(self, pool), err)]
    async fn listar_superusers(&self, pool: &PgPool) -> Result<Vec<AuthUser>, DbError> {
        // Query em runtime (sem macro): dispensa cache .sqlx; `AuthUser` deriva `FromRow`.
        let rows = sqlx::query_as::<_, AuthUser>(
            r#"SELECT id, username, email, password_hash, first_name, last_name,
                      is_active, is_staff, is_superuser, last_login, date_joined
               FROM auth_user WHERE is_superuser = TRUE ORDER BY id"#,
        )
        .fetch_all(pool)
        .await?;
        Ok(rows)
    }

    #[tracing::instrument(skip(self, pool), fields(user_id), err)]
    async fn deletar_superuser(&self, pool: &PgPool, user_id: i32) -> Result<u64, DbError> {
        let resultado = sqlx::query("DELETE FROM auth_user WHERE id = $1 AND is_superuser = TRUE")
            .bind(user_id)
            .execute(pool)
            .await?;
        Ok(resultado.rows_affected())
    }
}
