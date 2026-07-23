//! Fila de ações offline + resolução de conflito (last-write-wins) e o port de
//! transporte para o sync.
//!
//! **Auditoria:** o cliente NÃO emite auditoria própria dessas ações — elas são
//! auditadas **server-side no momento do sync**, com o ator real. O `id` uuid v7
//! viaja como chave de idempotência para o servidor não reprocessar duplicatas.

use std::collections::HashMap;

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use sqlx::{Row, SqlitePool};
use thiserror::Error;
use uuid::Uuid;

use crate::error::{LocalEngineError, LocalResult};

/// Falha do transporte de sync — erro do **port**, isolado do armazenamento
/// interno para que adapters (gRPC/FFI) não dependam de `LocalEngineError`.
#[derive(Debug, Error)]
pub enum SyncError {
    /// Servidor inalcançável (offline, timeout, rede).
    #[error("transporte indisponível: {0}")]
    Transport(String),

    /// Servidor recebeu mas rejeitou a ação (validação, permissão).
    #[error("rejeitado pelo servidor: {0}")]
    Rejected(String),
}

impl From<SyncError> for LocalEngineError {
    fn from(e: SyncError) -> Self {
        LocalEngineError::Sync(e.to_string())
    }
}

/// Operação específica de uma ação offline.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum OfflineActionKind {
    /// Mover atendimento de etapa (Kanban).
    MoveEtapa {
        etapa_destino_id: i64,
        motivo: String,
    },
    /// Enviar mensagem outbound. `conteudo` é PII — nunca logar.
    SendOutbound {
        conteudo: String,
        tipo: String,
        /// Id client-side (negativo) da linha pendente em `mensagens`, para o
        /// sync promovê-la ao id definitivo do servidor. `0` = desconhecido
        /// (ações antigas serializadas antes deste campo — via serde default).
        #[serde(default)]
        local_msg_id: i64,
    },
}

impl OfflineActionKind {
    fn tag(&self) -> &'static str {
        match self {
            OfflineActionKind::MoveEtapa { .. } => "move_etapa",
            OfflineActionKind::SendOutbound { .. } => "send_outbound",
        }
    }
}

/// Ação do atendente registrada localmente para sincronizar ao reconectar.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OfflineAction {
    /// uuid v7 gerado no cliente — chave de idempotência levada ao servidor.
    pub id: Uuid,
    /// Contador monotônico do cliente, base da resolução last-write-wins.
    pub version: i64,
    pub atendimento_id: i64,
    pub kind: OfflineActionKind,
    pub created_at: i64,
}

/// Port de transporte do sync. O adapter real (gRPC-Web pelo lado Dart/FFI, ou
/// um cliente gRPC-Rust futuro) é injetado depois — este crate não implementa
/// transporte nem um mock funcional de servidor.
#[async_trait]
pub trait SyncTransport: Send + Sync {
    /// Aplica no servidor a mudança de etapa. `action_id` é a chave idempotente.
    async fn move_atendimento_etapa(
        &self,
        action_id: Uuid,
        atendimento_id: i64,
        etapa_destino_id: i64,
        motivo: &str,
    ) -> Result<(), SyncError>;

    /// Persiste no servidor a mensagem outbound; devolve o id definitivo.
    async fn send_outbound_message(
        &self,
        action_id: Uuid,
        atendimento_id: i64,
        conteudo: &str,
        tipo: &str,
    ) -> Result<i64, SyncError>;
}

/// Resolve conflitos por **last-write-wins por versão**.
///
/// Mover etapa é idempotente por atendimento: apenas a ação de maior versão vale
/// (as anteriores são superadas e descartadas). Mensagens outbound são aditivas
/// — cada uma tem id idempotente próprio e nunca é colapsada.
pub fn resolve_lww(mut acoes: Vec<OfflineAction>) -> Vec<OfflineAction> {
    acoes.sort_by_key(|a| a.version);
    let mut vencedora_move: HashMap<i64, OfflineAction> = HashMap::new();
    let mut resultado: Vec<OfflineAction> = Vec::new();

    for acao in acoes {
        match acao.kind {
            OfflineActionKind::MoveEtapa { .. } => {
                vencedora_move
                    .entry(acao.atendimento_id)
                    .and_modify(|atual| {
                        if acao.version >= atual.version {
                            *atual = acao.clone();
                        }
                    })
                    .or_insert(acao);
            }
            OfflineActionKind::SendOutbound { .. } => resultado.push(acao),
        }
    }

    resultado.extend(vencedora_move.into_values());
    resultado.sort_by_key(|a| a.version);
    resultado
}

/// Fila offline respaldada pelo mesmo SQLite do índice.
#[derive(Clone)]
pub struct OfflineQueue {
    pool: SqlitePool,
}

impl OfflineQueue {
    pub(crate) fn new(pool: SqlitePool) -> Self {
        Self { pool }
    }

    /// Enfileira uma ação, atribuindo a versão monotônica ATOMICAMENTE num único
    /// statement (`INSERT ... SELECT COALESCE(MAX(version),0)+1 ...`), em vez de
    /// um `SELECT MAX` seguido de `INSERT` separados (a corrida coberta por
    /// `enqueue_concorrente_atribui_versoes_distintas`, abaixo — N7.4). O SQLite
    /// serializa escritas — um único statement elimina a janela entre duas
    /// conexões do pool lendo o mesmo `MAX` antes de qualquer uma commitar.
    /// Retorna a versão atribuída.
    pub async fn enqueue(
        &self,
        id: Uuid,
        atendimento_id: i64,
        kind: &OfflineActionKind,
        created_at: i64,
    ) -> LocalResult<i64> {
        let payload = serde_json::to_string(kind)
            .map_err(|e| LocalEngineError::Storage(format!("serialização: {e}")))?;
        let version: i64 = sqlx::query_scalar(
            "INSERT INTO offline_actions (id, version, atendimento_id, kind, payload, created_at, synced) \
             SELECT ?, COALESCE(MAX(version), 0) + 1, ?, ?, ?, ?, 0 FROM offline_actions \
             RETURNING version",
        )
        .bind(id.to_string())
        .bind(atendimento_id)
        .bind(kind.tag())
        .bind(&payload)
        .bind(created_at)
        .fetch_one(&self.pool)
        .await?;
        Ok(version)
    }

    /// Ações ainda não sincronizadas, em ordem de versão.
    pub async fn pending(&self) -> LocalResult<Vec<OfflineAction>> {
        let rows = sqlx::query(
            "SELECT id, version, atendimento_id, payload, created_at \
             FROM offline_actions WHERE synced = 0 ORDER BY version ASC",
        )
        .fetch_all(&self.pool)
        .await?;

        let mut acoes = Vec::with_capacity(rows.len());
        for row in rows {
            let id_txt: String = row.try_get("id")?;
            let id = Uuid::parse_str(&id_txt)
                .map_err(|e| LocalEngineError::Storage(format!("uuid inválido: {e}")))?;
            let payload: String = row.try_get("payload")?;
            let kind: OfflineActionKind = serde_json::from_str(&payload)
                .map_err(|e| LocalEngineError::Storage(format!("desserialização: {e}")))?;
            acoes.push(OfflineAction {
                id,
                version: row.try_get("version")?,
                atendimento_id: row.try_get("atendimento_id")?,
                kind,
                created_at: row.try_get("created_at")?,
            });
        }
        Ok(acoes)
    }

    /// Marca uma ação como sincronizada.
    pub async fn mark_synced(&self, id: Uuid) -> LocalResult<()> {
        sqlx::query("UPDATE offline_actions SET synced = 1 WHERE id = ?")
            .bind(id.to_string())
            .execute(&self.pool)
            .await?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn acao(
        id_v7: u128,
        version: i64,
        atendimento_id: i64,
        kind: OfflineActionKind,
    ) -> OfflineAction {
        OfflineAction {
            id: Uuid::from_u128(id_v7),
            version,
            atendimento_id,
            kind,
            created_at: version,
        }
    }

    #[test]
    fn lww_mantem_apenas_o_move_de_maior_versao_por_atendimento() {
        let acoes = vec![
            acao(
                1,
                1,
                100,
                OfflineActionKind::MoveEtapa {
                    etapa_destino_id: 10,
                    motivo: String::new(),
                },
            ),
            acao(
                2,
                3,
                100,
                OfflineActionKind::MoveEtapa {
                    etapa_destino_id: 30,
                    motivo: String::new(),
                },
            ),
            acao(
                3,
                2,
                100,
                OfflineActionKind::MoveEtapa {
                    etapa_destino_id: 20,
                    motivo: String::new(),
                },
            ),
        ];
        let resolvidas = resolve_lww(acoes);
        assert_eq!(resolvidas.len(), 1);
        assert_eq!(
            resolvidas[0].kind,
            OfflineActionKind::MoveEtapa {
                etapa_destino_id: 30,
                motivo: String::new()
            }
        );
    }

    #[test]
    fn lww_preserva_todas_as_mensagens_outbound() {
        let acoes = vec![
            acao(
                1,
                1,
                100,
                OfflineActionKind::SendOutbound {
                    conteudo: "a".into(),
                    tipo: "texto".into(),
                    local_msg_id: -1,
                },
            ),
            acao(
                2,
                2,
                100,
                OfflineActionKind::SendOutbound {
                    conteudo: "b".into(),
                    tipo: "texto".into(),
                    local_msg_id: -2,
                },
            ),
        ];
        let resolvidas = resolve_lww(acoes);
        assert_eq!(resolvidas.len(), 2);
    }

    #[test]
    fn lww_com_lista_vazia_nao_produz_resultado() {
        let resolvidas = resolve_lww(Vec::new());
        assert!(resolvidas.is_empty());
    }

    #[test]
    fn lww_mistura_move_e_outbound_do_mesmo_atendimento() {
        let acoes = vec![
            acao(
                1,
                1,
                100,
                OfflineActionKind::MoveEtapa {
                    etapa_destino_id: 10,
                    motivo: String::new(),
                },
            ),
            acao(
                2,
                2,
                100,
                OfflineActionKind::SendOutbound {
                    conteudo: "msg".into(),
                    tipo: "texto".into(),
                    local_msg_id: -1,
                },
            ),
        ];
        let resolvidas = resolve_lww(acoes);
        // A mensagem outbound é aditiva e o move (único) vence por ser o maior —
        // ambas sobrevivem à resolução.
        assert_eq!(resolvidas.len(), 2);
    }

    #[test]
    fn offline_action_kind_tag_identifica_a_variante() {
        let mv = OfflineActionKind::MoveEtapa {
            etapa_destino_id: 1,
            motivo: String::new(),
        };
        let out = OfflineActionKind::SendOutbound {
            conteudo: String::new(),
            tipo: String::new(),
            local_msg_id: 0,
        };
        assert_eq!(mv.tag(), "move_etapa");
        assert_eq!(out.tag(), "send_outbound");
    }

    #[test]
    fn sync_error_transport_converte_para_local_engine_error_sync() {
        let erro: LocalEngineError = SyncError::Transport("indisponível".to_string()).into();
        assert!(matches!(erro, LocalEngineError::Sync(_)));
    }

    #[test]
    fn sync_error_rejected_converte_para_local_engine_error_sync() {
        let erro: LocalEngineError = SyncError::Rejected("validação".to_string()).into();
        assert!(matches!(erro, LocalEngineError::Sync(_)));
    }

    #[tokio::test]
    async fn enqueue_pending_e_mark_synced_fluxo_completo() {
        let index = crate::index::SqliteIndex::open_in_memory().await.unwrap();
        let queue = OfflineQueue::new(index.pool().clone());

        let a1 = acao(
            1,
            1,
            100,
            OfflineActionKind::MoveEtapa {
                etapa_destino_id: 10,
                motivo: "teste".into(),
            },
        );
        queue
            .enqueue(a1.id, a1.atendimento_id, &a1.kind, a1.created_at)
            .await
            .unwrap();

        let pendentes = queue.pending().await.unwrap();
        assert_eq!(pendentes.len(), 1);
        assert_eq!(pendentes[0].id, a1.id);
        assert_eq!(pendentes[0].kind, a1.kind);

        queue.mark_synced(a1.id).await.unwrap();
        let pendentes_apos = queue.pending().await.unwrap();
        assert!(pendentes_apos.is_empty());
    }

    #[tokio::test]
    async fn enqueue_atribui_versao_comecando_em_um_e_incrementando() {
        let index = crate::index::SqliteIndex::open_in_memory().await.unwrap();
        let queue = OfflineQueue::new(index.pool().clone());

        let a1 = acao(
            1,
            0,
            100,
            OfflineActionKind::SendOutbound {
                conteudo: "a".into(),
                tipo: "texto".into(),
                local_msg_id: -1,
            },
        );
        let v1 = queue
            .enqueue(a1.id, a1.atendimento_id, &a1.kind, a1.created_at)
            .await
            .unwrap();
        assert_eq!(v1, 1);

        let a2 = acao(
            2,
            0,
            100,
            OfflineActionKind::SendOutbound {
                conteudo: "b".into(),
                tipo: "texto".into(),
                local_msg_id: -2,
            },
        );
        let v2 = queue
            .enqueue(a2.id, a2.atendimento_id, &a2.kind, a2.created_at)
            .await
            .unwrap();
        assert_eq!(v2, 2);
    }

    #[tokio::test]
    async fn pending_ignora_acoes_ja_sincronizadas() {
        let index = crate::index::SqliteIndex::open_in_memory().await.unwrap();
        let queue = OfflineQueue::new(index.pool().clone());

        let a1 = acao(
            1,
            1,
            100,
            OfflineActionKind::SendOutbound {
                conteudo: "a".into(),
                tipo: "texto".into(),
                local_msg_id: -1,
            },
        );
        let a2 = acao(
            2,
            2,
            100,
            OfflineActionKind::SendOutbound {
                conteudo: "b".into(),
                tipo: "texto".into(),
                local_msg_id: -2,
            },
        );
        queue
            .enqueue(a1.id, a1.atendimento_id, &a1.kind, a1.created_at)
            .await
            .unwrap();
        queue
            .enqueue(a2.id, a2.atendimento_id, &a2.kind, a2.created_at)
            .await
            .unwrap();
        queue.mark_synced(a1.id).await.unwrap();

        let pendentes = queue.pending().await.unwrap();
        assert_eq!(pendentes.len(), 1);
        assert_eq!(pendentes[0].id, a2.id);
    }

    /// N7.4 — regressão do achado de N7 (antes: `next_version()` lia `MAX` numa
    /// consulta separada do `INSERT`, permitindo duas ações concorrentes
    /// receberem a mesma versão). Agora `enqueue` atribui a versão num único
    /// statement; duas chamadas concorrentes devem sempre sair com versões
    /// distintas, nunca empatadas.
    #[tokio::test]
    async fn enqueue_concorrente_atribui_versoes_distintas() {
        let index = crate::index::SqliteIndex::open_in_memory().await.unwrap();
        let queue = OfflineQueue::new(index.pool().clone());

        let q1 = queue.clone();
        let q2 = queue.clone();
        let kind1 = OfflineActionKind::SendOutbound {
            conteudo: "a".into(),
            tipo: "texto".into(),
            local_msg_id: -1,
        };
        let kind2 = OfflineActionKind::SendOutbound {
            conteudo: "b".into(),
            tipo: "texto".into(),
            local_msg_id: -2,
        };
        let (v1, v2) = tokio::join!(
            q1.enqueue(Uuid::from_u128(1), 100, &kind1, 1),
            q2.enqueue(Uuid::from_u128(2), 100, &kind2, 2),
        );
        let (v1, v2) = (v1.unwrap(), v2.unwrap());
        assert_ne!(
            v1, v2,
            "duas ações concorrentes não podem receber a mesma versão"
        );
        assert_eq!(
            [v1, v2]
                .iter()
                .collect::<std::collections::HashSet<_>>()
                .len(),
            2
        );
    }

    #[test]
    fn lww_isola_moves_de_atendimentos_distintos() {
        let acoes = vec![
            acao(
                1,
                1,
                100,
                OfflineActionKind::MoveEtapa {
                    etapa_destino_id: 10,
                    motivo: String::new(),
                },
            ),
            acao(
                2,
                2,
                200,
                OfflineActionKind::MoveEtapa {
                    etapa_destino_id: 20,
                    motivo: String::new(),
                },
            ),
        ];
        let resolvidas = resolve_lww(acoes);
        assert_eq!(resolvidas.len(), 2);
    }
}
