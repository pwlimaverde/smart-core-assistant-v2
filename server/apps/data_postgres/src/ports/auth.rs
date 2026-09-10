//! Port (abstração) do domínio Auth do data_postgres.
//! O handler depende SOMENTE desta trait; o acesso ao datastore vive no adapter (DIP).
//! A verificação de senha (argon2) é operação de CPU pura e permanece no handler.

use async_trait::async_trait;
use infrastructure_postgres::auth::users::{AuthUser, UsuarioGlobal};
use infrastructure_postgres::tenants::tenants::TenantUser;
use infrastructure_postgres::DbError;

/// Operações de persistência do domínio Auth expostas aos handlers RPC.
#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait AuthStore: Send + Sync {
    /// Busca usuário por e-mail; se não encontrar, tenta por username.
    async fn buscar_por_login(&self, login: &str) -> Result<Option<AuthUser>, DbError>;

    /// Busca usuário pelo id.
    async fn buscar_por_id(&self, id: i32) -> Result<Option<AuthUser>, DbError>;

    /// Busca usuário pelo username (checagem de duplicidade no bootstrap).
    async fn buscar_por_username(&self, username: &str) -> Result<Option<AuthUser>, DbError>;

    /// Busca usuário pelo e-mail (checagem de duplicidade no bootstrap).
    async fn buscar_por_email(&self, email: &str) -> Result<Option<AuthUser>, DbError>;

    /// Resolve o vínculo TenantUser do usuário.
    async fn buscar_tenant_user(&self, user_id: i32) -> Result<Option<TenantUser>, DbError>;

    /// Registra a data do último login (best-effort).
    async fn registrar_ultimo_login(&self, user_id: i32) -> Result<(), DbError>;

    /// Cria um superusuário (hash de senha já calculado pelo handler).
    async fn criar_superuser(
        &self,
        username: &str,
        email: &str,
        password_hash: &str,
    ) -> Result<AuthUser, DbError>;

    /// Lista todos os superusuários.
    /// D7 — lista usuários de todos os tenants (painel do superusuário).
    async fn listar_usuarios_global(
        &self,
        busca: &str,
        limite: i64,
        offset: i64,
    ) -> Result<Vec<UsuarioGlobal>, DbError>;

    /// D7 — bloqueia/desbloqueia o acesso de um usuário. `false` = não existe.
    async fn definir_usuario_ativo(&self, user_id: i32, ativo: bool) -> Result<bool, DbError>;

    async fn listar_superusers(&self) -> Result<Vec<AuthUser>, DbError>;

    /// Remove fisicamente um superusuário; retorna linhas afetadas (0 = inexistente).
    async fn deletar_superuser(&self, user_id: i32) -> Result<u64, DbError>;
}
