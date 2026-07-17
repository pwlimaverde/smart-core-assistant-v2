//! Casca FFI fina sobre o crate `local_engine` (Rust puro).
//!
//! Espelha as cinco operações do `AtendimentoDataSource` do módulo operacional
//! Dart, além do cache de mídia e do stream local. A lógica não é reimplementada:
//! cada método delega ao [`local_engine::LocalEngine`]. As structs-espelho (com
//! sufixo `Ffi`) existem só para a fronteira do `flutter_rust_bridge` — datas em
//! epoch-millis `i64` e `payload` como JSON serializado, já que o
//! `serde_json::Value` não cruza o FFI.
//!
//! Runtime: um `tokio::runtime::Runtime` multi-thread vive dentro do handle
//! [`LocalEngineApi`] porque o `local_engine` é async (sqlx/reqwest). As chamadas
//! assíncronas do FRB despacham nesse runtime via `spawn`, mantendo o contexto
//! tokio necessário para o sqlx sem depender do executor do FRB.

use std::path::PathBuf;
use std::sync::Arc;

use async_trait::async_trait;
use flutter_rust_bridge::{frb, DartFnFuture};
use tokio::runtime::Runtime;
use uuid::Uuid;

use crate::frb_generated::StreamSink;

use local_engine::{
    AtendimentoEvento, AtendimentoResumo, LocalEngine, LocalEngineConfig, MensagemThread,
    SyncError, SyncReport, SyncTransport,
};

/// Resumo de atendimento na fronteira FFI (datas em epoch-millis).
pub struct AtendimentoResumoFfi {
    pub id: i64,
    pub contato_id: i64,
    pub status: String,
    pub departamento_id: Option<i64>,
    pub fluxo_atendimento_id: Option<i64>,
    pub etapa_atual_id: Option<i64>,
    pub assunto: String,
    pub prioridade: String,
    pub atendente_humano_id: Option<i64>,
    pub data_inicio: i64,
    pub data_ultima_mensagem: Option<i64>,
}

impl From<AtendimentoResumo> for AtendimentoResumoFfi {
    fn from(a: AtendimentoResumo) -> Self {
        Self {
            id: a.id,
            contato_id: a.contato_id,
            status: a.status,
            departamento_id: a.departamento_id,
            fluxo_atendimento_id: a.fluxo_atendimento_id,
            etapa_atual_id: a.etapa_atual_id,
            assunto: a.assunto,
            prioridade: a.prioridade,
            atendente_humano_id: a.atendente_humano_id,
            data_inicio: a.data_inicio,
            data_ultima_mensagem: a.data_ultima_mensagem,
        }
    }
}

/// Mensagem de thread na fronteira FFI. `conteudo` é PII — nunca logar.
pub struct MensagemThreadFfi {
    pub id: i64,
    pub atendimento_id: i64,
    pub tipo: String,
    pub conteudo: String,
    pub remetente: String,
    pub timestamp: i64,
    pub status_envio: String,
    pub gerado_por_ia: bool,
    pub resumo_midia: Option<String>,
}

impl From<MensagemThread> for MensagemThreadFfi {
    fn from(m: MensagemThread) -> Self {
        Self {
            id: m.id,
            atendimento_id: m.atendimento_id,
            tipo: m.tipo,
            conteudo: m.conteudo,
            remetente: m.remetente,
            timestamp: m.timestamp,
            status_envio: m.status_envio,
            gerado_por_ia: m.gerado_por_ia,
            resumo_midia: m.resumo_midia,
        }
    }
}

/// Evento realtime local na fronteira FFI. `payload` vai como JSON (string).
pub struct AtendimentoEventoFfi {
    pub tipo: String,
    pub tenant_id: String,
    pub payload_json: String,
}

impl From<AtendimentoEvento> for AtendimentoEventoFfi {
    fn from(e: AtendimentoEvento) -> Self {
        Self {
            tipo: e.tipo,
            tenant_id: e.tenant_id,
            payload_json: e.payload.to_string(),
        }
    }
}

/// Relatório de uma passada de sincronização na fronteira FFI.
pub struct SyncReportFfi {
    /// Ações aplicadas com sucesso no servidor.
    pub aplicadas: i64,
    /// Ações superadas pela resolução last-write-wins (não enviadas).
    pub descartadas_lww: i64,
    /// Ações que falharam no transporte (permanecem na fila para retry).
    pub falhas: i64,
}

impl From<SyncReport> for SyncReportFfi {
    fn from(r: SyncReport) -> Self {
        Self {
            aplicadas: r.aplicadas as i64,
            descartadas_lww: r.descartadas_lww as i64,
            falhas: r.falhas as i64,
        }
    }
}

/// Adapter do trait [`SyncTransport`] que delega cada operação a um callback
/// **Dart** assíncrono (via `flutter_rust_bridge`). Mantém o gRPC do lado Dart —
/// reusa o canal autenticado (`GrpcNativeApiClient`, com refresh de token), sem
/// um segundo cliente gRPC em Rust que ficaria defasado no refresh. Os callbacks
/// devolvem uma `String`: vazia = sucesso; não vazia = mensagem de erro (a ação
/// permanece na fila para nova tentativa).
struct DartSyncTransport<M, S>
where
    M: Fn(String, i64, i64, String) -> DartFnFuture<String> + Send + Sync,
    S: Fn(String, i64, String, String) -> DartFnFuture<String> + Send + Sync,
{
    on_move: M,
    on_send: S,
}

#[async_trait]
impl<M, S> SyncTransport for DartSyncTransport<M, S>
where
    M: Fn(String, i64, i64, String) -> DartFnFuture<String> + Send + Sync,
    S: Fn(String, i64, String, String) -> DartFnFuture<String> + Send + Sync,
{
    async fn move_atendimento_etapa(
        &self,
        action_id: Uuid,
        atendimento_id: i64,
        etapa_destino_id: i64,
        motivo: &str,
    ) -> Result<(), SyncError> {
        let erro = (self.on_move)(
            action_id.to_string(),
            atendimento_id,
            etapa_destino_id,
            motivo.to_string(),
        )
        .await;
        if erro.is_empty() {
            Ok(())
        } else {
            Err(SyncError::Transport(erro))
        }
    }

    async fn send_outbound_message(
        &self,
        action_id: Uuid,
        atendimento_id: i64,
        conteudo: &str,
        tipo: &str,
    ) -> Result<i64, SyncError> {
        let erro = (self.on_send)(
            action_id.to_string(),
            atendimento_id,
            conteudo.to_string(),
            tipo.to_string(),
        )
        .await;
        if erro.is_empty() {
            // O `sincronizar` ignora o id retornado (só marca como sincronizado).
            Ok(0)
        } else {
            Err(SyncError::Transport(erro))
        }
    }
}

/// Handle opaco do motor local exposto ao Dart. Guarda o runtime tokio e o
/// [`LocalEngine`]; não expõe estado interno ao Dart (opaco).
#[frb(opaque)]
pub struct LocalEngineApi {
    engine: Arc<LocalEngine>,
    rt: Arc<Runtime>,
}

impl LocalEngineApi {
    /// Abre o motor local: cria/migra o índice SQLite e prepara fila e cache.
    ///
    /// [db_path] é o arquivo do índice; [media_dir] o diretório do cache de mídia
    /// (ex.: sob `%APPDATA%` no Windows); [tenant_id] rotula eventos locais.
    #[frb]
    pub async fn open(
        db_path: String,
        media_dir: String,
        tenant_id: String,
    ) -> anyhow::Result<LocalEngineApi> {
        let rt = Arc::new(
            tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()?,
        );
        let config = LocalEngineConfig {
            db_path: PathBuf::from(db_path),
            media_dir: PathBuf::from(media_dir),
            tenant_id,
        };
        let rt_open = rt.clone();
        let engine = rt_open
            .spawn(async move { LocalEngine::abrir(config).await })
            .await?
            .map_err(anyhow::Error::from)?;
        Ok(LocalEngineApi {
            engine: Arc::new(engine),
            rt,
        })
    }

    /// Lista a fila de atendimentos por status/departamento (offline, índice).
    pub async fn list_atendimentos(
        &self,
        status: String,
        departamento_id: Option<i64>,
        limit: i64,
    ) -> anyhow::Result<Vec<AtendimentoResumoFfi>> {
        let engine = self.engine.clone();
        let rows = self
            .rt
            .spawn(async move {
                engine
                    .list_atendimentos(&status, departamento_id, limit)
                    .await
            })
            .await?
            .map_err(anyhow::Error::from)?;
        Ok(rows.into_iter().map(AtendimentoResumoFfi::from).collect())
    }

    /// Carrega o thread (histórico) de um atendimento (offline, índice).
    pub async fn get_thread(
        &self,
        atendimento_id: i64,
        limit: i64,
        offset: i64,
    ) -> anyhow::Result<Vec<MensagemThreadFfi>> {
        let engine = self.engine.clone();
        let rows = self
            .rt
            .spawn(async move { engine.get_thread(atendimento_id, limit, offset).await })
            .await?
            .map_err(anyhow::Error::from)?;
        Ok(rows.into_iter().map(MensagemThreadFfi::from).collect())
    }

    /// Move o atendimento de etapa: aplica otimista no índice e enfileira o sync.
    pub async fn move_atendimento_etapa(
        &self,
        atendimento_id: i64,
        etapa_destino_id: i64,
        motivo: String,
    ) -> anyhow::Result<()> {
        let engine = self.engine.clone();
        self.rt
            .spawn(async move {
                engine
                    .move_atendimento_etapa(atendimento_id, etapa_destino_id, &motivo)
                    .await
            })
            .await?
            .map_err(anyhow::Error::from)?;
        Ok(())
    }

    /// Envia mensagem outbound: grava pendente (id client-side) e enfileira o
    /// sync. Devolve o id local atribuído. `conteudo` é PII — nunca logar.
    pub async fn send_outbound_message(
        &self,
        atendimento_id: i64,
        conteudo: String,
        tipo: String,
    ) -> anyhow::Result<i64> {
        let engine = self.engine.clone();
        let id = self
            .rt
            .spawn(async move {
                engine
                    .send_outbound_message(atendimento_id, &conteudo, &tipo)
                    .await
            })
            .await?
            .map_err(anyhow::Error::from)?;
        Ok(id)
    }

    /// Garante uma mídia no cache local (baixa uma vez, valida por hash).
    pub async fn ensure_media(
        &self,
        url: String,
        sha256_esperado: String,
    ) -> anyhow::Result<String> {
        let engine = self.engine.clone();
        let caminho = self
            .rt
            .spawn(async move { engine.ensure_media(&url, &sha256_esperado).await })
            .await?
            .map_err(anyhow::Error::from)?;
        Ok(caminho.to_string_lossy().into_owned())
    }

    /// Ingesta (upsert) um resumo de atendimento no índice — alimenta o cache
    /// local a partir de dados vindos do servidor.
    pub async fn ingest_atendimento(&self, a: AtendimentoResumoFfi) -> anyhow::Result<()> {
        let engine = self.engine.clone();
        let resumo = AtendimentoResumo {
            id: a.id,
            contato_id: a.contato_id,
            status: a.status,
            departamento_id: a.departamento_id,
            fluxo_atendimento_id: a.fluxo_atendimento_id,
            etapa_atual_id: a.etapa_atual_id,
            assunto: a.assunto,
            prioridade: a.prioridade,
            atendente_humano_id: a.atendente_humano_id,
            data_inicio: a.data_inicio,
            data_ultima_mensagem: a.data_ultima_mensagem,
        };
        self.rt
            .spawn(async move { engine.ingest_atendimento(&resumo).await })
            .await?
            .map_err(anyhow::Error::from)?;
        Ok(())
    }

    /// Ingesta (upsert) uma mensagem no índice local.
    pub async fn ingest_mensagem(&self, m: MensagemThreadFfi) -> anyhow::Result<()> {
        let engine = self.engine.clone();
        let msg = MensagemThread {
            id: m.id,
            atendimento_id: m.atendimento_id,
            tipo: m.tipo,
            conteudo: m.conteudo,
            remetente: m.remetente,
            timestamp: m.timestamp,
            status_envio: m.status_envio,
            gerado_por_ia: m.gerado_por_ia,
            resumo_midia: m.resumo_midia,
        };
        self.rt
            .spawn(async move { engine.ingest_mensagem(&msg).await })
            .await?
            .map_err(anyhow::Error::from)?;
        Ok(())
    }

    /// Assina o stream local de eventos (mutações otimistas). Encaminha cada
    /// evento do bus `broadcast` do motor para o [sink] do Dart. Emite só os
    /// eventos locais; o merge com o realtime do servidor é da camada acima.
    pub async fn stream_atendimentos(
        &self,
        sink: StreamSink<AtendimentoEventoFfi>,
    ) -> anyhow::Result<()> {
        let mut rx = self.engine.stream_atendimentos();
        self.rt.spawn(async move {
            while let Ok(ev) = rx.recv().await {
                if sink.add(AtendimentoEventoFfi::from(ev)).is_err() {
                    break;
                }
            }
        });
        Ok(())
    }

    /// Sincroniza a fila offline com o servidor. A resolução last-write-wins e a
    /// marcação de sincronizadas ficam no `local_engine` (Rust); o **transporte**
    /// é injetado como dois callbacks Dart — [on_move] e [on_send] — que chamam o
    /// gRPC autenticado do lado Dart. Cada callback recebe o `action_id` (uuid,
    /// chave de idempotência) e devolve uma `String`: vazia = sucesso; não vazia =
    /// erro (a ação fica na fila para retry). `conteudo` é PII — nunca logar.
    pub async fn sincronizar(
        &self,
        on_move: impl Fn(String, i64, i64, String) -> DartFnFuture<String> + Send + Sync + 'static,
        on_send: impl Fn(String, i64, String, String) -> DartFnFuture<String> + Send + Sync + 'static,
    ) -> anyhow::Result<SyncReportFfi> {
        let engine = self.engine.clone();
        let transporte = DartSyncTransport { on_move, on_send };
        let report = self
            .rt
            .spawn(async move { engine.sincronizar(&transporte).await })
            .await?
            .map_err(anyhow::Error::from)?;
        Ok(SyncReportFfi::from(report))
    }
}
