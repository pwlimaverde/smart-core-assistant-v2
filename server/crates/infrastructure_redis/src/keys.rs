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

/// Contador de tentativas por janela para um recurso genérico (N4.4 — rate
/// limiting amplo: webhook por instância/tenant, rotas quentes do `runtime_api`).
/// `id` deve ser um identificador opaco — nunca PII em claro.
pub fn chave_rate_limit(recurso: &str, id: &str) -> String {
    format!("rate_limit:{recurso}:{id}")
}

/// `RuntimeConfig` consolidado do tenant (cascata `TenantConfig > CoreSettings`
/// já resolvida), publicado pelo Rust e lido pelo `ia_engine`.
///
/// NÃO usa `chave_tenant` de propósito: o formato `tenant:config:<uuid>` é
/// **contrato com o cliente Python** (ver
/// `doc_dev/modelagem_dados/gerenciamento_configuracoes_ia.md`, seção 3.1), não
/// uma convenção interna do Rust. Mudar aqui quebra o `ia_engine` em silêncio.
pub fn chave_config_tenant(tenant_id: Uuid) -> String {
    format!("tenant:config:{tenant_id}")
}

/// Canal Pub/Sub que avisa o `ia_engine` para descartar a cópia em RAM da
/// config de um tenant. Payload: o `tenant_id` em texto puro (não JSON) —
/// é o que o listener Python espera.
///
/// Distinto de `core:settings:invalidate`, que serve ao cache interno do Rust
/// e carrega JSON. São dois consumidores com contratos diferentes; unificá-los
/// acoplaria o Python ao formato interno do Rust.
pub const CANAL_CONFIG_INVALIDATE: &str = "tenant:config:invalidate";

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

    #[test]
    fn formats_tenant_config_key_as_the_python_client_expects() {
        // O formato e' contrato com o `ia_engine` (Python), nao convencao
        // interna: `tenant:config:<uuid>`, sem o segmento de recurso que
        // `chave_tenant` insere.
        let t = Uuid::parse_str("f47ac10b-58cc-4372-a567-0e02b2c3d479").unwrap();

        assert_eq!(
            chave_config_tenant(t),
            "tenant:config:f47ac10b-58cc-4372-a567-0e02b2c3d479"
        );
        assert_eq!(CANAL_CONFIG_INVALIDATE, "tenant:config:invalidate");
    }
}
