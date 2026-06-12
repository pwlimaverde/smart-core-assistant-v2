use uuid::Uuid;

/// Monta uma chave no namespace obrigatório por tenant: `tenant:<uuid>:<recurso>:<chave>`.
pub fn chave_tenant(tenant_id: Uuid, recurso: &str, chave: &str) -> String {
    format!("tenant:{tenant_id}:{recurso}:{chave}")
}

/// Cache das `flow_permissions` (IDs de fluxos de Kanban) de um usuário em um tenant.
/// Carregado pelo middleware/interceptor a cada requisição com TTL curto.
pub fn chave_flow_permissions(tenant_id: Uuid, user_id: i32) -> String {
    format!("tenant:{tenant_id}:flow_permissions:{user_id}")
}

/// Registro de um refresh token (indexado pelo hash do token, nunca pelo token em claro).
///
/// Usa prefixo `auth:` (sem tenant no namespace) porque o refresh pode preceder a seleção
/// de tenant; o `tenant_id` é guardado dentro do próprio registro.
pub fn chave_refresh(token_hash: &str) -> String {
    format!("auth:refresh:{token_hash}")
}

/// Conjunto (Set) com os hashes de todos os refresh tokens de uma mesma família de rotação.
pub fn chave_refresh_familia(family_id: &str) -> String {
    format!("auth:refresh_family:{family_id}")
}

/// Blocklist de access tokens revogados (logout), indexada pelo `jti` do JWT.
pub fn chave_blocklist(jti: &str) -> String {
    format!("auth:blocklist:{jti}")
}

/// Contador de tentativas de login por janela (rate limiting), indexado pelo hash
/// do identificador (ex.: SHA-256 do e-mail) — nunca pelo identificador em claro.
pub fn chave_rate_limit_login(id_hash: &str) -> String {
    format!("auth:rate_limit:login:{id_hash}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formats_redis_keys_according_to_domain_namespaces_correctly() {
        // Arrange
        let t = Uuid::parse_str("f47ac10b-58cc-4372-a567-0e02b2c3d479").unwrap();

        // Act & Assert
        assert_eq!(
            chave_tenant(t, "presence", "agent_123"),
            "tenant:f47ac10b-58cc-4372-a567-0e02b2c3d479:presence:agent_123"
        );
        assert_eq!(
            chave_flow_permissions(t, 7),
            "tenant:f47ac10b-58cc-4372-a567-0e02b2c3d479:flow_permissions:7"
        );
        assert_eq!(chave_refresh("abc"), "auth:refresh:abc");
        assert_eq!(chave_refresh_familia("fam1"), "auth:refresh_family:fam1");
        assert_eq!(chave_blocklist("jti1"), "auth:blocklist:jti1");
        assert_eq!(chave_rate_limit_login("h4sh"), "auth:rate_limit:login:h4sh");
    }
}
