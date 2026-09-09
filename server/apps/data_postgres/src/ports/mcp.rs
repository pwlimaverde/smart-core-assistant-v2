//! Port dos consentimentos OAuth 2.1 dos clientes MCP (N13.2).
//!
//! Não há checagem de escopo em nenhuma destas operações, e isso é intencional:
//! um grant é **do usuário**, não do tenant. A autorização é a identidade — todas
//! as consultas filtram por `user_id` do envelope, então nem um `tenant:admin`
//! enxerga ou revoga o consentimento de outra pessoa. Exigir escopo aqui daria a
//! falsa impressão de que um escopo alto substituiria esse filtro.

use async_trait::async_trait;
use infrastructure_postgres::{DbError, McpGrant, McpGrantComSegredo, RequestContext};
use uuid::Uuid;

#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait McpGrantStore: Send + Sync {
    /// Grava o consentimento aprovado na tela do authorization server.
    /// Reconsentir com o mesmo cliente substitui o grant anterior.
    async fn registrar(
        &self,
        ctx: &RequestContext,
        client_id: &str,
        client_name: &str,
        redirect_uri: &str,
        escopos: &[String],
        created_ip: Option<String>,
    ) -> Result<McpGrant, DbError>;

    /// Consentimentos ativos do próprio usuário (tela "Aplicativos conectados").
    async fn listar(&self, ctx: &RequestContext) -> Result<Vec<McpGrant>, DbError>;

    /// `false` quando o grant não existe, é de outro usuário ou já foi revogado.
    async fn revogar(&self, ctx: &RequestContext, grant_id: Uuid) -> Result<bool, DbError>;

    /// Grava o SHA-256 do segredo do refresh corrente (emissão ou rotação).
    async fn definir_refresh_hash(
        &self,
        tenant_id: Uuid,
        grant_id: Uuid,
        hash: &str,
    ) -> Result<(), DbError>;

    /// Grant ativo com o hash do refresh, para o caminho de renovação.
    async fn buscar_com_segredo(
        &self,
        tenant_id: Uuid,
        grant_id: Uuid,
    ) -> Result<Option<McpGrantComSegredo>, DbError>;

    /// Derruba o grant por reuso de refresh já rotacionado (suspeita de roubo).
    async fn revogar_por_reuso(&self, tenant_id: Uuid, grant_id: Uuid) -> Result<(), DbError>;
}
