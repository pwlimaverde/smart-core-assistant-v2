//! # local_engine
//!
//! Motor local (client-side) do app operacional do Smart Core Assistant — roda
//! **dentro do processo do app Flutter** no desktop do atendente. Provê leitura
//! rápida offline (índice SQLite), cache de mídia por hash e fila de ações
//! offline com sincronização (last-write-wins por versão).
//!
//! **Fronteira arquitetural (princípio inviolável do plano N5):** depende apenas
//! de abstrações de storage/index locais — **nada** de infra multi-tenant nem de
//! webhook. NÃO importa `infrastructure_postgres`/`infrastructure_redis`/
//! `transport` nem fala com o Postgres/Redis do servidor. A camada de erro é
//! própria ([`LocalEngineError`]), não reexpõe `error_core`.
//!
//! As funções públicas espelham as 5 operações do `AtendimentoDataSource` do
//! módulo operacional Dart. As anotações `#[frb(...)]` do `flutter_rust_bridge` e
//! o codegen entram numa tarefa de integração futura — aqui a API é Rust pura,
//! testável isoladamente.

pub mod error;
pub mod index;
pub mod media_cache;
pub mod models;
pub mod offline_queue;

use std::path::{Path, PathBuf};

use tokio::sync::broadcast;
use uuid::Uuid;

pub use error::{LocalEngineError, LocalResult};
pub use index::SqliteIndex;
pub use media_cache::MediaCache;
pub use models::{AtendimentoEvento, AtendimentoResumo, MensagemThread};
pub use offline_queue::{
    resolve_lww, OfflineAction, OfflineActionKind, OfflineQueue, SyncError, SyncTransport,
};

/// Capacidade do bus local de eventos (mutações otimistas).
const CAPACIDADE_EVENTOS: usize = 128;

/// Remetente lógico das mensagens outbound do atendente.
const REMETENTE_ATENDENTE: &str = "atendente";

/// Configuração de inicialização do motor local.
#[derive(Debug, Clone)]
pub struct LocalEngineConfig {
    /// Caminho do arquivo SQLite do índice.
    pub db_path: PathBuf,
    /// Diretório base do cache de mídia (ex.: `%APPDATA%/.../media_cache`).
    pub media_dir: PathBuf,
    /// Tenant do atendente logado (usado só para rotular eventos locais).
    pub tenant_id: String,
}

/// Resultado de uma passada de sincronização.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SyncReport {
    /// Ações aplicadas com sucesso no servidor.
    pub aplicadas: usize,
    /// Ações superadas pela resolução last-write-wins (não enviadas).
    pub descartadas_lww: usize,
    /// Ações que falharam no transporte (permanecem na fila para retry).
    pub falhas: usize,
}

/// Motor local: índice SQLite + cache de mídia + fila offline.
pub struct LocalEngine {
    index: SqliteIndex,
    queue: OfflineQueue,
    media: MediaCache,
    eventos: broadcast::Sender<AtendimentoEvento>,
    tenant_id: String,
}

impl LocalEngine {
    /// Abre o motor: cria/migra o índice e prepara a fila e o cache.
    pub async fn abrir(config: LocalEngineConfig) -> LocalResult<Self> {
        let index = SqliteIndex::open(&config.db_path).await?;
        let queue = OfflineQueue::new(index.pool().clone());
        let media = MediaCache::new(config.media_dir);
        let (eventos, _) = broadcast::channel(CAPACIDADE_EVENTOS);
        Ok(Self {
            index,
            queue,
            media,
            eventos,
            tenant_id: config.tenant_id,
        })
    }

    // -- Ingestão (preenche o índice a partir de dados vindos do servidor) -----

    /// Grava/atualiza um resumo de atendimento no índice local.
    pub async fn ingest_atendimento(&self, a: &AtendimentoResumo) -> LocalResult<()> {
        self.index.upsert_atendimento(a).await
    }

    /// Grava/atualiza uma mensagem no índice local.
    pub async fn ingest_mensagem(&self, m: &MensagemThread) -> LocalResult<()> {
        self.index.upsert_mensagem(m).await
    }

    // -- Espelho das 5 operações do AtendimentoDataSource ----------------------

    /// Lista a fila de atendimentos por status/departamento (offline, índice).
    pub async fn list_atendimentos(
        &self,
        status: &str,
        departamento_id: Option<i64>,
        limit: i64,
    ) -> LocalResult<Vec<AtendimentoResumo>> {
        self.index
            .list_atendimentos(status, departamento_id, limit)
            .await
    }

    /// Carrega o thread de um atendimento (offline, índice).
    pub async fn get_thread(
        &self,
        atendimento_id: i64,
        limit: i64,
        offset: i64,
    ) -> LocalResult<Vec<MensagemThread>> {
        self.index.get_thread(atendimento_id, limit, offset).await
    }

    /// Move o atendimento de etapa: aplica otimista no índice e **enfileira** a
    /// ação para o sync. A auditoria acontece server-side no momento do sync.
    pub async fn move_atendimento_etapa(
        &self,
        atendimento_id: i64,
        etapa_destino_id: i64,
        motivo: &str,
    ) -> LocalResult<()> {
        self.index
            .update_etapa(atendimento_id, etapa_destino_id)
            .await?;

        let id = Uuid::now_v7();
        let kind = OfflineActionKind::MoveEtapa {
            etapa_destino_id,
            motivo: motivo.to_string(),
        };
        // N7.4: versão atribuída atomicamente dentro do próprio enqueue (single
        // statement) — elimina a corrida entre `next_version` e `enqueue`.
        self.queue
            .enqueue(id, atendimento_id, &kind, agora_millis())
            .await?;

        self.emitir_evento(
            "atendimento.etapa_movida",
            serde_json::json!({
                "atendimento_id": atendimento_id,
                "etapa_destino_id": etapa_destino_id,
            }),
        );
        Ok(())
    }

    /// Envia uma mensagem outbound: grava localmente como pendente (id
    /// client-side) e enfileira para o sync. Devolve o id local atribuído — o id
    /// definitivo do servidor chega na sincronização. `conteudo` é PII (nunca
    /// logado); o evento emitido não o carrega.
    pub async fn send_outbound_message(
        &self,
        atendimento_id: i64,
        conteudo: &str,
        tipo: &str,
    ) -> LocalResult<i64> {
        let ts = agora_millis();
        let id_local = self
            .index
            .insert_pending_mensagem(atendimento_id, conteudo, tipo, REMETENTE_ATENDENTE, ts)
            .await?;

        let id = Uuid::now_v7();
        let kind = OfflineActionKind::SendOutbound {
            conteudo: conteudo.to_string(),
            tipo: tipo.to_string(),
            local_msg_id: id_local,
        };
        // N7.4: versão atribuída atomicamente dentro do próprio enqueue (single
        // statement) — elimina a corrida entre `next_version` e `enqueue`.
        self.queue.enqueue(id, atendimento_id, &kind, ts).await?;

        self.emitir_evento(
            "mensagem.enviada",
            serde_json::json!({ "atendimento_id": atendimento_id }),
        );
        Ok(id_local)
    }

    /// Assina o stream local de eventos (espelha `streamAtendimentos`). Emite as
    /// mutações otimistas locais; o merge com o stream realtime do servidor é
    /// responsabilidade da camada acima.
    pub fn stream_atendimentos(&self) -> broadcast::Receiver<AtendimentoEvento> {
        self.eventos.subscribe()
    }

    // -- Mídia e sync ----------------------------------------------------------

    /// Garante uma mídia no cache local (baixa uma vez, valida por hash).
    pub async fn ensure_media(&self, url: &str, sha256_esperado: &str) -> LocalResult<PathBuf> {
        self.media.ensure(url, sha256_esperado).await
    }

    /// Sincroniza a fila offline com o servidor via o [`SyncTransport`] injetado.
    ///
    /// Aplica last-write-wins por versão: para cada atendimento, só o `MoveEtapa`
    /// de maior versão é enviado; ao ter sucesso, as ações de move superadas do
    /// mesmo atendimento também são marcadas como sincronizadas (obsoletas).
    /// Mensagens outbound são todas enviadas (aditivas). Falhas de transporte
    /// deixam a ação na fila para nova tentativa — sem logar payload/PII.
    pub async fn sincronizar(&self, transporte: &dyn SyncTransport) -> LocalResult<SyncReport> {
        let pendentes = self.queue.pending().await?;
        let total = pendentes.len();

        // Mapa atendimento -> ids de todos os moves pendentes (para marcar as
        // superadas junto com a vencedora quando ela for aceita).
        let mut moves_por_atendimento: std::collections::HashMap<i64, Vec<Uuid>> =
            std::collections::HashMap::new();
        for a in &pendentes {
            if let OfflineActionKind::MoveEtapa { .. } = a.kind {
                moves_por_atendimento
                    .entry(a.atendimento_id)
                    .or_default()
                    .push(a.id);
            }
        }

        let resolvidas = resolve_lww(pendentes);
        let mut report = SyncReport {
            descartadas_lww: total - resolvidas.len(),
            ..Default::default()
        };

        for acao in resolvidas {
            match &acao.kind {
                OfflineActionKind::MoveEtapa {
                    etapa_destino_id,
                    motivo,
                } => {
                    match transporte
                        .move_atendimento_etapa(
                            acao.id,
                            acao.atendimento_id,
                            *etapa_destino_id,
                            motivo,
                        )
                        .await
                    {
                        Ok(()) => {
                            let ids = moves_por_atendimento
                                .remove(&acao.atendimento_id)
                                .unwrap_or_else(|| vec![acao.id]);
                            for id in ids {
                                self.queue.mark_synced(id).await?;
                            }
                            report.aplicadas += 1;
                        }
                        Err(e) => {
                            tracing::warn!(erro = %e, "falha ao sincronizar move de etapa");
                            report.falhas += 1;
                        }
                    }
                }
                OfflineActionKind::SendOutbound {
                    conteudo,
                    tipo,
                    local_msg_id,
                } => {
                    match transporte
                        .send_outbound_message(acao.id, acao.atendimento_id, conteudo, tipo)
                        .await
                    {
                        Ok(id_definitivo) => {
                            // Promove a linha pendente ao id do servidor — sem
                            // isto a mensagem ficaria "pendente" para sempre e a
                            // re-ingestão criaria uma duplicata fantasma.
                            if *local_msg_id != 0 && id_definitivo > 0 {
                                self.index
                                    .promover_mensagem_pendente(*local_msg_id, id_definitivo)
                                    .await?;
                            }
                            self.queue.mark_synced(acao.id).await?;
                            report.aplicadas += 1;
                        }
                        Err(e) => {
                            tracing::warn!(erro = %e, "falha ao sincronizar mensagem outbound");
                            report.falhas += 1;
                        }
                    }
                }
            }
        }
        Ok(report)
    }

    fn emitir_evento(&self, tipo: &str, payload: serde_json::Value) {
        // `send` só falha se não há assinantes — irrelevante aqui.
        let _ = self.eventos.send(AtendimentoEvento {
            tipo: tipo.to_string(),
            tenant_id: self.tenant_id.clone(),
            payload,
        });
    }
}

/// Timestamp atual em epoch-millis.
fn agora_millis() -> i64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// Abre o índice a partir de um caminho — atalho fino sobre [`SqliteIndex::open`].
pub async fn abrir_index(db_path: &Path) -> LocalResult<SqliteIndex> {
    SqliteIndex::open(db_path).await
}

#[cfg(test)]
mod tests {
    use super::*;

    async fn engine_em_memoria() -> LocalEngine {
        let index = SqliteIndex::open_in_memory().await.unwrap();
        let queue = OfflineQueue::new(index.pool().clone());
        let media = MediaCache::new(std::env::temp_dir().join("le_test_media"));
        let (eventos, _) = broadcast::channel(CAPACIDADE_EVENTOS);
        LocalEngine {
            index,
            queue,
            media,
            eventos,
            tenant_id: "tenant-teste".to_string(),
        }
    }

    fn resumo(id: i64, status: &str, etapa: Option<i64>) -> AtendimentoResumo {
        AtendimentoResumo {
            id,
            contato_id: 1,
            status: status.to_string(),
            departamento_id: Some(7),
            fluxo_atendimento_id: None,
            etapa_atual_id: etapa,
            assunto: "assunto".to_string(),
            prioridade: "normal".to_string(),
            atendente_humano_id: None,
            data_inicio: 1000,
            data_ultima_mensagem: None,
        }
    }

    #[tokio::test]
    async fn ingest_e_list_filtram_por_status_e_departamento() {
        let engine = engine_em_memoria().await;
        engine
            .ingest_atendimento(&resumo(1, "fila", Some(10)))
            .await
            .unwrap();
        engine
            .ingest_atendimento(&resumo(2, "fechado", Some(10)))
            .await
            .unwrap();

        let fila = engine.list_atendimentos("fila", Some(7), 50).await.unwrap();
        assert_eq!(fila.len(), 1);
        assert_eq!(fila[0].id, 1);

        let outro_depto = engine
            .list_atendimentos("fila", Some(999), 50)
            .await
            .unwrap();
        assert!(outro_depto.is_empty());
    }

    #[tokio::test]
    async fn move_aplica_otimista_e_enfileira() {
        let engine = engine_em_memoria().await;
        engine
            .ingest_atendimento(&resumo(1, "fila", Some(10)))
            .await
            .unwrap();

        engine
            .move_atendimento_etapa(1, 20, "arrastou")
            .await
            .unwrap();

        let fila = engine.list_atendimentos("fila", None, 50).await.unwrap();
        assert_eq!(fila[0].etapa_atual_id, Some(20));

        let pend = engine.queue.pending().await.unwrap();
        assert_eq!(pend.len(), 1);
    }

    #[tokio::test]
    async fn send_outbound_grava_pendente_com_id_negativo() {
        let engine = engine_em_memoria().await;
        engine
            .ingest_atendimento(&resumo(1, "fila", Some(10)))
            .await
            .unwrap();

        let id = engine
            .send_outbound_message(1, "oi", "texto")
            .await
            .unwrap();
        assert!(id < 0, "mensagem offline deve ter id client-side negativo");

        let thread = engine.get_thread(1, 50, 0).await.unwrap();
        assert_eq!(thread.len(), 1);
        assert_eq!(thread[0].status_envio, "pendente");
    }

    /// Transporte-stub de teste: aceita tudo e devolve um id fixo do "servidor".
    struct TransporteOk {
        id_definitivo: i64,
    }

    #[async_trait::async_trait]
    impl SyncTransport for TransporteOk {
        async fn move_atendimento_etapa(
            &self,
            _action_id: Uuid,
            _atendimento_id: i64,
            _etapa_destino_id: i64,
            _motivo: &str,
        ) -> Result<(), SyncError> {
            Ok(())
        }

        async fn send_outbound_message(
            &self,
            _action_id: Uuid,
            _atendimento_id: i64,
            _conteudo: &str,
            _tipo: &str,
        ) -> Result<i64, SyncError> {
            Ok(self.id_definitivo)
        }
    }

    #[tokio::test]
    async fn sincronizar_promove_mensagem_pendente_ao_id_definitivo() {
        let engine = engine_em_memoria().await;
        engine
            .ingest_atendimento(&resumo(1, "fila", Some(10)))
            .await
            .unwrap();

        let id_local = engine
            .send_outbound_message(1, "oi", "texto")
            .await
            .unwrap();
        assert!(id_local < 0);

        let report = engine
            .sincronizar(&TransporteOk { id_definitivo: 777 })
            .await
            .unwrap();
        assert_eq!(report.aplicadas, 1);
        assert_eq!(report.falhas, 0);

        // A pendente virou a mensagem definitiva: id do servidor, status enviado,
        // sem sobrar linha com id negativo.
        let thread = engine.get_thread(1, 50, 0).await.unwrap();
        assert_eq!(thread.len(), 1);
        assert_eq!(thread[0].id, 777);
        assert_eq!(thread[0].status_envio, "enviado");

        // Nada mais pendente na fila.
        assert!(engine.queue.pending().await.unwrap().is_empty());
    }

    /// Transporte-stub que rejeita tudo — simula servidor indisponível/recusando.
    struct TransporteFalha;

    #[async_trait::async_trait]
    impl SyncTransport for TransporteFalha {
        async fn move_atendimento_etapa(
            &self,
            _action_id: Uuid,
            _atendimento_id: i64,
            _etapa_destino_id: i64,
            _motivo: &str,
        ) -> Result<(), SyncError> {
            Err(SyncError::Transport("servidor indisponível".into()))
        }

        async fn send_outbound_message(
            &self,
            _action_id: Uuid,
            _atendimento_id: i64,
            _conteudo: &str,
            _tipo: &str,
        ) -> Result<i64, SyncError> {
            Err(SyncError::Rejected("payload inválido".into()))
        }
    }

    #[tokio::test]
    async fn sincronizar_com_transporte_falhando_mantem_acoes_na_fila() {
        let engine = engine_em_memoria().await;
        engine
            .ingest_atendimento(&resumo(1, "fila", Some(10)))
            .await
            .unwrap();

        engine
            .move_atendimento_etapa(1, 20, "arrastou")
            .await
            .unwrap();

        let report = engine.sincronizar(&TransporteFalha).await.unwrap();
        assert_eq!(report.aplicadas, 0);
        assert_eq!(report.falhas, 1);

        // A ação continua pendente para nova tentativa.
        assert_eq!(engine.queue.pending().await.unwrap().len(), 1);
    }

    #[tokio::test]
    async fn sincronizar_aplica_lww_e_marca_moves_superados_como_sincronizados() {
        let engine = engine_em_memoria().await;
        engine
            .ingest_atendimento(&resumo(1, "fila", Some(10)))
            .await
            .unwrap();

        // Duas movimentações do mesmo atendimento: só a de maior versão deve ser
        // enviada, mas ambas devem sair da fila de pendentes após o sync.
        engine
            .move_atendimento_etapa(1, 20, "primeira")
            .await
            .unwrap();
        engine
            .move_atendimento_etapa(1, 30, "segunda")
            .await
            .unwrap();
        assert_eq!(engine.queue.pending().await.unwrap().len(), 2);

        let report = engine
            .sincronizar(&TransporteOk { id_definitivo: 1 })
            .await
            .unwrap();

        assert_eq!(report.aplicadas, 1, "só a vencedora do LWW é aplicada");
        assert_eq!(report.descartadas_lww, 1);
        assert!(
            engine.queue.pending().await.unwrap().is_empty(),
            "a superada também deve ser marcada como sincronizada"
        );
    }

    #[tokio::test]
    async fn stream_atendimentos_recebe_evento_emitido_pelo_move_de_etapa() {
        let engine = engine_em_memoria().await;
        engine
            .ingest_atendimento(&resumo(1, "fila", Some(10)))
            .await
            .unwrap();

        let mut receiver = engine.stream_atendimentos();
        engine
            .move_atendimento_etapa(1, 20, "arrastou")
            .await
            .unwrap();

        let evento = receiver
            .try_recv()
            .expect("evento deveria ter sido emitido");
        assert_eq!(evento.tipo, "atendimento.etapa_movida");
        assert_eq!(evento.tenant_id, "tenant-teste");
    }

    #[tokio::test]
    async fn ensure_media_delega_para_o_cache_e_retorna_o_caminho() {
        let dir = std::env::temp_dir().join(format!(
            "le_engine_media_{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_nanos())
                .unwrap_or(0)
        ));
        tokio::fs::create_dir_all(&dir).await.unwrap();

        let index = SqliteIndex::open_in_memory().await.unwrap();
        let queue = OfflineQueue::new(index.pool().clone());
        let media = MediaCache::new(&dir);
        let (eventos, _) = broadcast::channel(CAPACIDADE_EVENTOS);
        let engine = LocalEngine {
            index,
            queue,
            media,
            eventos,
            tenant_id: "tenant-teste".to_string(),
        };

        let conteudo = b"midia de teste";
        let hash = MediaCache::hash_bytes(conteudo);
        tokio::fs::write(dir.join(&hash), conteudo).await.unwrap();

        let caminho = engine
            .ensure_media("http://127.0.0.1:0/nao-usado", &hash)
            .await
            .unwrap();
        assert_eq!(caminho, dir.join(&hash));

        tokio::fs::remove_dir_all(&dir).await.ok();
    }

    #[tokio::test]
    async fn abrir_index_atalho_abre_um_indice_utilizavel() {
        let sufixo = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let db_path = std::env::temp_dir().join(format!("le_abrir_index_{sufixo}.sqlite"));

        let idx = abrir_index(&db_path).await.unwrap();
        idx.upsert_atendimento(&resumo(1, "fila", None))
            .await
            .unwrap();
        let lista = idx.list_atendimentos("fila", None, 10).await.unwrap();
        assert_eq!(lista.len(), 1);

        tokio::fs::remove_file(&db_path).await.ok();
    }

    #[tokio::test]
    async fn abrir_cria_o_motor_completo_a_partir_da_configuracao() {
        let sufixo = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let base = std::env::temp_dir().join(format!("le_abrir_engine_{sufixo}"));
        // `SqliteConnectOptions::create_if_missing` cria o arquivo, mas não o
        // diretório pai — o diretório base precisa existir antes de abrir.
        tokio::fs::create_dir_all(&base).await.unwrap();
        let config = LocalEngineConfig {
            db_path: base.join("indice.sqlite"),
            media_dir: base.join("media"),
            tenant_id: "tenant-abrir".to_string(),
        };

        let engine = LocalEngine::abrir(config).await.unwrap();
        let lista = engine.list_atendimentos("fila", None, 10).await.unwrap();
        assert!(lista.is_empty());

        tokio::fs::remove_dir_all(&base).await.ok();
    }
}
