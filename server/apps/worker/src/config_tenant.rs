//! N8.5/E4 — leitura, pelo worker, da config resolvida do tenant.
//!
//! O `data_postgres` já resolve a cascata `TenantConfig > CoreSettings` e publica
//! o resultado em `tenant:config:<uuid>` no Redis de **cache**, avisando por
//! `tenant:config:invalidate` (ver `data_postgres/src/config_publisher.rs`). O
//! `ia_engine` lê de lá desde a N6; o worker não lia, e por isso `msg_fallback` —
//! configurável no painel, persistida, publicada — nunca chegava ao contato: o
//! texto de degradação era uma constante no código.
//!
//! **Por que ler o Redis e não chamar `ResolverConfigIa`:** o RPC existe só por
//! causa do kill-switch de transcrição, e a direção do projeto (28/07) foi tirar
//! config do caminho quente. Ler a chave que já está publicada custa um GET, não
//! um round-trip de RPC com o banco atrás.
//!
//! **Segurança:** a chave carrega as API keys decifradas do tenant. Este módulo
//! expõe **apenas campos de texto de negócio** (`msg_*`) por nome explícito, e o
//! JSON inteiro nunca é logado nem devolvido ao chamador.

use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use redis::aio::ConnectionManager;
use uuid::Uuid;

/// TTL da cópia em RAM. É rede de segurança, não o mecanismo de atualização: a
/// invalidação real chega pelo canal Pub/Sub (`iniciar_escuta_invalidacao`). O TTL
/// cobre a janela em que o listener esteja caído ou a notificação se perca.
const TTL_PADRAO_SEGUNDOS: u64 = 60;

type Entrada = (Instant, Arc<serde_json::Value>);

/// Cache do processo, compartilhado por todas as tasks do worker.
///
/// `std::sync::Mutex` (não o do tokio) de propósito: o guard nunca atravessa um
/// `await` — as duas funções abaixo soltam o lock antes de qualquer I/O.
fn cache() -> &'static Mutex<HashMap<Uuid, Entrada>> {
    static C: OnceLock<Mutex<HashMap<Uuid, Entrada>>> = OnceLock::new();
    C.get_or_init(|| Mutex::new(HashMap::new()))
}

fn ttl() -> Duration {
    Duration::from_secs(
        std::env::var("SMARTCORE_CONFIG_CACHE_TTL_SEGUNDOS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(TTL_PADRAO_SEGUNDOS),
    )
}

/// Descarta a cópia em RAM do tenant. Chamado pelo listener de invalidação.
pub(crate) fn invalidar(tenant: &Uuid) {
    if let Ok(mut guard) = cache().lock() {
        guard.remove(tenant);
    }
}

/// Lê a config do tenant (cache em RAM → Redis). `None` quando não há Redis
/// configurado, a chave não existe ou o JSON não parseia.
///
/// Best-effort por natureza: quem chama precisa ter um default próprio. Uma falha
/// aqui nunca pode interromper o atendimento — no máximo significa "use o texto
/// versionado no código".
async fn obter(conn: Option<&ConnectionManager>, tenant: Uuid) -> Option<Arc<serde_json::Value>> {
    if let Ok(guard) = cache().lock() {
        if let Some((gravado_em, valor)) = guard.get(&tenant) {
            if gravado_em.elapsed() < ttl() {
                return Some(valor.clone());
            }
        }
    }

    let mut conn = conn?.clone();
    let chave = infrastructure_redis::chave_config_tenant(tenant);
    let bruto: Option<String> = match redis::AsyncCommands::get(&mut conn, &chave).await {
        Ok(v) => v,
        Err(e) => {
            // Sem o valor no log: a chave carrega segredo.
            tracing::warn!(tenant_id = %tenant, "falha ao ler config do tenant no Redis: {e}");
            return None;
        }
    };

    let valor: serde_json::Value = serde_json::from_str(&bruto?).ok()?;
    let valor = Arc::new(valor);
    if let Ok(mut guard) = cache().lock() {
        guard.insert(tenant, (Instant::now(), valor.clone()));
    }
    Some(valor)
}

/// Devolve um campo de **texto de negócio** da config do tenant, ou `None` quando
/// ausente/vazio.
///
/// Vazio conta como ausente de propósito: a cascata do `data_postgres` já preenche
/// o campo com o default global quando o tenant não configurou nada, e string
/// vazia significaria enviar uma mensagem em branco ao contato.
///
/// `chave` precisa ser um dos campos `msg_*`; **não** use esta função para ler
/// chaves de API — elas moram no mesmo JSON e devem continuar só no `ia_engine`.
pub(crate) async fn texto(
    conn: Option<&ConnectionManager>,
    tenant: Uuid,
    chave: &str,
) -> Option<String> {
    debug_assert!(
        chave.starts_with("msg_"),
        "config_tenant::texto só serve campos de mensagem (msg_*); \
         ler segredo por aqui vazaria a chave do tenant para o worker"
    );
    let cfg = obter(conn, tenant).await?;
    cfg.get(chave)
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

/// Assina `tenant:config:invalidate` e descarta a cópia em RAM do tenant avisado.
///
/// Roda em background e se reconecta sozinho: se a assinatura cair e ninguém
/// reabrir, o worker passaria a servir config velha até o TTL — silenciosamente,
/// que é exatamente a classe de bug que a N8.5 está consertando.
pub(crate) fn iniciar_escuta_invalidacao(client: redis::Client) {
    tokio::spawn(async move {
        loop {
            match escutar(&client).await {
                Ok(()) => tracing::warn!("assinatura de invalidação de config encerrou; reabrindo"),
                Err(e) => tracing::warn!("assinatura de invalidação de config falhou: {e}"),
            }
            tokio::time::sleep(Duration::from_secs(5)).await;
        }
    });
}

// `get_async_connection` está deprecada em favor da conexão multiplexada, mas
// Pub/Sub exige conexão DEDICADA (o multiplex não entrega mensagens de canal).
// Mesmo tratamento já dado ao subscriber do runtime_api (`realtime.rs`).
#[allow(deprecated)]
async fn escutar(client: &redis::Client) -> anyhow::Result<()> {
    use futures_util::StreamExt;

    let conn = client.get_async_connection().await?;
    let mut pubsub = conn.into_pubsub();
    pubsub
        .subscribe(infrastructure_redis::CANAL_CONFIG_INVALIDATE)
        .await?;
    tracing::info!("worker assinou o canal de invalidação de config do tenant");

    let mut stream = pubsub.on_message();
    while let Some(msg) = stream.next().await {
        let payload: String = match msg.get_payload() {
            Ok(p) => p,
            Err(e) => {
                tracing::warn!("payload inválido na invalidação de config: {e}");
                continue;
            }
        };
        match Uuid::parse_str(payload.trim()) {
            Ok(tenant) => {
                invalidar(&tenant);
                tracing::debug!(tenant_id = %tenant, "config do tenant invalidada no worker");
            }
            Err(_) => tracing::warn!("invalidação de config com tenant_id inválido"),
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Sem Redis (ambiente de teste, ou Redis fora do ar) a leitura devolve `None`
    /// em vez de explodir — é o que garante que o chamador caia no default do
    /// código em vez de deixar o contato sem resposta.
    #[tokio::test]
    async fn texto_sem_redis_devolve_none() {
        let tenant = Uuid::new_v4();
        assert_eq!(texto(None, tenant, "msg_fallback").await, None);
    }

    /// Campo em branco tem de contar como "não configurado": a alternativa seria
    /// mandar uma mensagem vazia ao contato.
    #[tokio::test]
    async fn campo_em_branco_conta_como_ausente() {
        let tenant = Uuid::new_v4();
        cache().lock().unwrap().insert(
            tenant,
            (
                Instant::now(),
                Arc::new(serde_json::json!({
                    "msg_fallback": "   ",
                    "msg_sem_info": "Não encontrei essa informação.",
                })),
            ),
        );

        assert_eq!(texto(None, tenant, "msg_fallback").await, None);
        assert_eq!(
            texto(None, tenant, "msg_sem_info").await.as_deref(),
            Some("Não encontrei essa informação.")
        );
        invalidar(&tenant);
    }

    #[tokio::test]
    async fn invalidar_descarta_a_copia_em_ram() {
        let tenant = Uuid::new_v4();
        cache().lock().unwrap().insert(
            tenant,
            (
                Instant::now(),
                Arc::new(serde_json::json!({ "msg_fallback": "texto do tenant" })),
            ),
        );
        assert_eq!(
            texto(None, tenant, "msg_fallback").await.as_deref(),
            Some("texto do tenant")
        );

        invalidar(&tenant);
        // Sem Redis para recarregar, a leitura seguinte não acha mais nada.
        assert_eq!(texto(None, tenant, "msg_fallback").await, None);
    }
}
