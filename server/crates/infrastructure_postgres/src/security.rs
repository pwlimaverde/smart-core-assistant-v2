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

#[cfg(test)]
mod tests {
    use super::*;

    fn get_test_context(scopes: Vec<&str>, flows: Vec<i32>) -> RequestContext {
        RequestContext {
            tenant_id: Uuid::new_v4(),
            user_id: 42,
            user_scopes: scopes.into_iter().map(String::from).collect(),
            flow_permissions: flows,
        }
    }

    #[test]
    fn test_request_context_has_permission() {
        let ctx = get_test_context(vec!["atendimentos:read", "atendimentos:write"], vec![]);

        assert!(ctx.has_permission("atendimentos:read"));
        assert!(ctx.has_permission("atendimentos:write"));
        assert!(!ctx.has_permission("tenant:admin"));
    }

    #[test]
    fn test_request_context_has_flow_permission() {
        // 1. Permissão de fluxo normal
        let ctx = get_test_context(vec!["atendimentos:read"], vec![1, 2]);
        assert!(ctx.has_flow_permission(1));
        assert!(ctx.has_flow_permission(2));
        assert!(!ctx.has_flow_permission(3));

        // 2. Acesso irrestrito via kanban:admin
        let ctx_kanban_admin = get_test_context(vec!["kanban:admin"], vec![1]);
        assert!(ctx_kanban_admin.has_flow_permission(1));
        assert!(ctx_kanban_admin.has_flow_permission(99));

        // 3. Acesso irrestrito via tenant:admin
        let ctx_tenant_admin = get_test_context(vec!["tenant:admin"], vec![1]);
        assert!(ctx_tenant_admin.has_flow_permission(1));
        assert!(ctx_tenant_admin.has_flow_permission(99));
    }
}
