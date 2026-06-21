//! Adapter de auditoria: publica no bus de segurança via ConnectionManager.

use async_trait::async_trait;
use contracts::Envelope;
use redis::aio::ConnectionManager;

use crate::ports::AuditPort;

/// Publica eventos de auditoria no bus de segurança (REDIS_BUS_URL).
#[derive(Clone)]
pub struct RedisAuditPort {
    conn: ConnectionManager,
}

impl RedisAuditPort {
    pub fn new(conn: ConnectionManager) -> Self {
        Self { conn }
    }
}

#[async_trait]
impl AuditPort for RedisAuditPort {
    #[tracing::instrument(skip_all, fields(event = event))]
    async fn publish(
        &self,
        env: &Envelope,
        event: &str,
        message: String,
        context: serde_json::Value,
    ) {
        // ConnectionManager é clonável (compartilha a conexão multiplexada subjacente).
        let mut conn = self.conn.clone();
        // Reusa a função existente: NÃO há auditoria própria aqui (evita recursão);
        // a falha de publicação é registrada como ERROR dentro de publicar_auditoria.
        crate::publicar_auditoria(&mut conn, env, event, message, context).await;
    }
}
