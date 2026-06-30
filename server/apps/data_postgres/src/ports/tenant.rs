//! Port (abstração) do domínio Tenant do data_postgres.
//! O handler depende SOMENTE desta trait; a transação/SQL vive no adapter (DIP).

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use infrastructure_postgres::security::RequestContext;
use infrastructure_postgres::tenants::tenants::{Tenant, TenantInvite, TenantUser};
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

    /// Cria um convite para o tenant.
    async fn criar_convite(
        &self,
        ctx: &RequestContext,
        email: &str,
        name: &str,
        role: &str,
        token: &str,
        expires_at: DateTime<Utc>,
    ) -> Result<TenantInvite, DbError>;

    /// Busca um convite pelo token (bypass RLS).
    async fn buscar_convite_por_token(&self, token: &str) -> Result<Option<TenantInvite>, DbError>;

    /// Aceita um convite de forma transacional, criando usuário, TenantUser e marcando o convite como usado.
    async fn aceitar_convite(
        &self,
        invite_id: Uuid,
        username: &str,
        email: &str,
        password_hash: &str,
        tenant_id: Uuid,
        role: &str,
    ) -> Result<TenantUser, DbError>;
}
