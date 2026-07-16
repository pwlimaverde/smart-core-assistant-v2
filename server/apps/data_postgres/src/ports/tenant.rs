//! Port (abstração) do domínio Tenant do data_postgres.
//! O handler depende SOMENTE desta trait; a transação/SQL vive no adapter (DIP).

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use infrastructure_postgres::security::RequestContext;
use infrastructure_postgres::tenants::tenants::{
    Tenant, TenantInvite, TenantInviteListItem, TenantUser,
};
use infrastructure_postgres::DbError;
use uuid::Uuid;

/// Operações de persistência do domínio Tenant expostas aos handlers RPC.
/// Operações administrativas (cross-tenant) do control_plane; cada método
/// encapsula a abertura/commit da transação (ou o SQL direto) no adapter concreto.
#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait TenantStore: Send + Sync {
    /// Cria um novo tenant (gera UUID/api_key internamente; owner padrão = 1).
    /// `email`/`phone` são owned para satisfazer o `automock` (lifetime aninhado).
    async fn criar(
        &self,
        name: &str,
        slug: &str,
        email: Option<String>,
        phone: Option<String>,
    ) -> Result<Tenant, DbError>;

    /// Lista todos os tenants (operação administrativa, ordenada por nome).
    async fn listar_todos(&self) -> Result<Vec<Tenant>, DbError>;

    /// Busca um tenant pelo id (operação administrativa).
    async fn buscar_por_id(&self, id: Uuid) -> Result<Option<Tenant>, DbError>;

    /// Atualiza o cadastro do tenant; retorna `true` se algum registro foi afetado.
    async fn atualizar_cadastro(
        &self,
        id: Uuid,
        name: &str,
        slug: &str,
        owner_id: i32,
        email: &str,
        phone: Option<String>,
    ) -> Result<bool, DbError>;

    /// Ativa/desativa o tenant; retorna `true` se algum registro foi afetado.
    async fn definir_ativo(&self, id: Uuid, active: bool) -> Result<bool, DbError>;

    /// Persiste um novo código de acesso; retorna `true` se algum registro foi afetado.
    async fn gerar_access_code(&self, id: Uuid, code: &str) -> Result<bool, DbError>;

    /// Cria um convite para o tenant, já com as permissões (`module_permissions` =
    /// escopos; `flow_permissions` = ids de fluxo) que o convidado receberá no aceite.
    #[allow(clippy::too_many_arguments)]
    async fn criar_convite(
        &self,
        ctx: &RequestContext,
        email: &str,
        name: &str,
        role: &str,
        module_permissions: serde_json::Value,
        flow_permissions: serde_json::Value,
        token: &str,
        expires_at: DateTime<Utc>,
    ) -> Result<TenantInvite, DbError>;

    /// Busca um convite pelo token (bypass RLS).
    async fn buscar_convite_por_token(&self, token: &str) -> Result<Option<TenantInvite>, DbError>;

    /// Aceita um convite de forma transacional, criando usuário e TenantUser (com as
    /// permissões definidas no convite) e marcando o convite como usado.
    #[allow(clippy::too_many_arguments)]
    async fn aceitar_convite(
        &self,
        invite_id: Uuid,
        username: &str,
        email: &str,
        password_hash: &str,
        tenant_id: Uuid,
        role: &str,
        module_permissions: serde_json::Value,
        flow_permissions: serde_json::Value,
    ) -> Result<TenantUser, DbError>;

    /// Lista os TenantUser do tenant do `ctx` (RBAC `tenant:admin` no repositório).
    async fn listar_usuarios(&self, ctx: &RequestContext) -> Result<Vec<TenantUser>, DbError>;

    /// Atualiza role/permissões de um TenantUser do tenant do `ctx`; retorna `true`
    /// se afetou alguma linha.
    async fn atualizar_usuario(
        &self,
        ctx: &RequestContext,
        user_id: i32,
        role: Option<String>,
        module_permissions: Option<serde_json::Value>,
        flow_permissions: Option<serde_json::Value>,
    ) -> Result<bool, DbError>;

    /// Lista os convites do tenant do `ctx` (sem `token`; RBAC `tenant:admin`).
    async fn listar_convites(
        &self,
        ctx: &RequestContext,
    ) -> Result<Vec<TenantInviteListItem>, DbError>;

    /// Revoga um convite do tenant do `ctx`; retorna `true` se o convite era válido.
    async fn revogar_convite(&self, ctx: &RequestContext, invite_id: Uuid)
        -> Result<bool, DbError>;

    /// Cria o primeiro TenantUser admin de um tenant recém-criado (bootstrap do
    /// CreateTenant). `module_permissions` são os escopos iniciais do admin.
    async fn criar_primeiro_admin(
        &self,
        tenant_id: Uuid,
        owner_id: i32,
        module_permissions: serde_json::Value,
    ) -> Result<TenantUser, DbError>;
}
