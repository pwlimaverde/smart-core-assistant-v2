use redis::aio::ConnectionManager;
use redis::AsyncCommands;
use uuid::Uuid;

use crate::errors::RedisError;
use crate::keys;

/// TTL padrão do cache de `flow_permissions`. Curto de propósito: permite que revogações de
/// acesso reflitam sem esperar a expiração do JWT.
pub const TTL_FLOW_PERMISSIONS_SEGUNDOS: u64 = 60;

/// Cache das permissões de fluxo (`flow_permissions`) por usuário/tenant.
pub struct CachePermissoes {
    con: ConnectionManager,
}

impl CachePermissoes {
    pub fn new(con: ConnectionManager) -> Self {
        Self { con }
    }

    /// Grava as `flow_permissions` do usuário com TTL (segundos).
    #[tracing::instrument(
        skip(self, flows),
        fields(tenant_id = %tenant_id, user_id, ttl_segundos),
        err
    )]
    pub async fn definir_flow_permissions(
        &mut self,
        tenant_id: Uuid,
        user_id: i32,
        flows: &[i32],
        ttl_segundos: u64,
    ) -> Result<(), RedisError> {
        let chave = keys::chave_flow_permissions(tenant_id, user_id);
        let valor = serde_json::to_string(flows)?;
        let _: () = redis::cmd("SET")
            .arg(&chave)
            .arg(valor)
            .arg("EX")
            .arg(ttl_segundos)
            .query_async(&mut self.con)
            .await?;
        Ok(())
    }

    /// Lê as `flow_permissions` em cache. `Ok(None)` quando não há entrada (cache miss).
    #[tracing::instrument(
        level = "debug",
        skip(self),
        fields(tenant_id = %tenant_id, user_id),
        err
    )]
    pub async fn obter_flow_permissions(
        &mut self,
        tenant_id: Uuid,
        user_id: i32,
    ) -> Result<Option<Vec<i32>>, RedisError> {
        let chave = keys::chave_flow_permissions(tenant_id, user_id);
        let valor: Option<String> = self.con.get(&chave).await?;
        match valor {
            Some(s) => {
                tracing::debug!("cache hit de flow_permissions");
                Ok(Some(serde_json::from_str(&s)?))
            }
            None => {
                tracing::debug!("cache miss de flow_permissions");
                Ok(None)
            }
        }
    }

    /// Invalida o cache de `flow_permissions` do usuário (ex.: após mudança de permissões).
    #[tracing::instrument(skip(self), fields(tenant_id = %tenant_id, user_id), err)]
    pub async fn invalidar(&mut self, tenant_id: Uuid, user_id: i32) -> Result<(), RedisError> {
        let chave = keys::chave_flow_permissions(tenant_id, user_id);
        let _: i64 = self.con.del(&chave).await?;
        Ok(())
    }
}
