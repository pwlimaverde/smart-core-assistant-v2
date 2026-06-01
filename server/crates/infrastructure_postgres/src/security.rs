use uuid::Uuid;

/// Contexto de requisição com identidade do usuário e escopos de permissão.
/// Construído pelo middleware JWT (futuro runtime_api) e injetado como Extension do Axum.
#[derive(Debug, Clone)]
pub struct RequestContext {
    /// Tenant ao qual a requisição pertence (extraído das Claims do JWT, nunca do body).
    pub tenant_id: Uuid,
    /// Identificador do usuário logado (referência a auth_user).
    pub user_id: i32,
    /// Escopos concedidos ao usuário (catálogo canônico em 09_diretrizes_permissoes_acesso.md).
    pub user_scopes: Vec<String>,
    /// IDs de FluxoAtendimento que o atendente está autorizado a visualizar no Kanban.
    /// Carregado do TenantUser.flow_permissions no middleware de autenticação.
    pub flow_permissions: Vec<i32>,
}

impl RequestContext {
    /// Retorna true se o usuário possui o escopo informado.
    pub fn has_permission(&self, permission: &str) -> bool {
        self.user_scopes.iter().any(|p| p == permission)
    }

    /// Retorna true se o usuário pode acessar o fluxo Kanban informado.
    /// Administradores com escopo "kanban:admin" têm acesso irrestrito.
    pub fn has_flow_permission(&self, flow_id: i32) -> bool {
        if self.has_permission("kanban:admin") || self.has_permission("tenant:admin") {
            return true;
        }
        self.flow_permissions.contains(&flow_id)
    }
}
