//! Índice local em SQLite: leitura rápida offline da fila/thread e aplicação
//! otimista das mutações do atendente antes do sync.

use std::path::Path;
use std::str::FromStr;

use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::SqlitePool;

use crate::error::{LocalEngineError, LocalResult};
use crate::models::{AtendimentoResumo, MensagemThread};

/// Migrations embutidas no binário (resolvidas em tempo de compilação).
static MIGRATOR: sqlx::migrate::Migrator = sqlx::migrate!("./migrations");

/// Índice local respaldado por um pool SQLite.
#[derive(Clone)]
pub struct SqliteIndex {
    pool: SqlitePool,
}

impl SqliteIndex {
    /// Abre (ou cria) o índice em disco e roda as migrations pendentes.
    pub async fn open(db_path: &Path) -> LocalResult<Self> {
        let opts = SqliteConnectOptions::new()
            .filename(db_path)
            .create_if_missing(true);
        let pool = SqlitePoolOptions::new()
            .max_connections(4)
            .connect_with(opts)
            .await?;
        MIGRATOR.run(&pool).await?;
        Ok(Self { pool })
    }

    /// Abre um índice em memória (uma única conexão) — usado em testes.
    pub async fn open_in_memory() -> LocalResult<Self> {
        let opts = SqliteConnectOptions::from_str("sqlite::memory:")
            .map_err(|e| LocalEngineError::Storage(e.to_string()))?;
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect_with(opts)
            .await?;
        MIGRATOR.run(&pool).await?;
        Ok(Self { pool })
    }

    /// Pool subjacente — compartilhado com a fila offline (mesmo arquivo).
    pub(crate) fn pool(&self) -> &SqlitePool {
        &self.pool
    }

    /// Insere ou atualiza um resumo de atendimento no índice.
    pub async fn upsert_atendimento(&self, a: &AtendimentoResumo) -> LocalResult<()> {
        sqlx::query(
            "INSERT INTO atendimentos (id, contato_id, status, departamento_id, \
             fluxo_atendimento_id, etapa_atual_id, assunto, prioridade, \
             atendente_humano_id, data_inicio, data_ultima_mensagem) \
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) \
             ON CONFLICT(id) DO UPDATE SET \
             contato_id = excluded.contato_id, status = excluded.status, \
             departamento_id = excluded.departamento_id, \
             fluxo_atendimento_id = excluded.fluxo_atendimento_id, \
             etapa_atual_id = excluded.etapa_atual_id, assunto = excluded.assunto, \
             prioridade = excluded.prioridade, \
             atendente_humano_id = excluded.atendente_humano_id, \
             data_inicio = excluded.data_inicio, \
             data_ultima_mensagem = excluded.data_ultima_mensagem",
        )
        .bind(a.id)
        .bind(a.contato_id)
        .bind(&a.status)
        .bind(a.departamento_id)
        .bind(a.fluxo_atendimento_id)
        .bind(a.etapa_atual_id)
        .bind(&a.assunto)
        .bind(&a.prioridade)
        .bind(a.atendente_humano_id)
        .bind(a.data_inicio)
        .bind(a.data_ultima_mensagem)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// Lista a fila por status (e opcionalmente por departamento), mais recentes
    /// primeiro.
    pub async fn list_atendimentos(
        &self,
        status: &str,
        departamento_id: Option<i64>,
        limit: i64,
    ) -> LocalResult<Vec<AtendimentoResumo>> {
        let rows = sqlx::query_as::<_, AtendimentoResumo>(
            "SELECT id, contato_id, status, departamento_id, fluxo_atendimento_id, \
             etapa_atual_id, assunto, prioridade, atendente_humano_id, data_inicio, \
             data_ultima_mensagem FROM atendimentos \
             WHERE status = ? AND (? IS NULL OR departamento_id = ?) \
             ORDER BY COALESCE(data_ultima_mensagem, data_inicio) DESC LIMIT ?",
        )
        .bind(status)
        .bind(departamento_id)
        .bind(departamento_id)
        .bind(limit)
        .fetch_all(&self.pool)
        .await?;
        Ok(rows)
    }

    /// Insere ou atualiza uma mensagem no índice.
    pub async fn upsert_mensagem(&self, m: &MensagemThread) -> LocalResult<()> {
        sqlx::query(
            "INSERT INTO mensagens (id, atendimento_id, tipo, conteudo, remetente, \
             timestamp, status_envio, gerado_por_ia, resumo_midia) \
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) \
             ON CONFLICT(id) DO UPDATE SET \
             atendimento_id = excluded.atendimento_id, tipo = excluded.tipo, \
             conteudo = excluded.conteudo, remetente = excluded.remetente, \
             timestamp = excluded.timestamp, status_envio = excluded.status_envio, \
             gerado_por_ia = excluded.gerado_por_ia, resumo_midia = excluded.resumo_midia",
        )
        .bind(m.id)
        .bind(m.atendimento_id)
        .bind(&m.tipo)
        .bind(&m.conteudo)
        .bind(&m.remetente)
        .bind(m.timestamp)
        .bind(&m.status_envio)
        .bind(m.gerado_por_ia)
        .bind(&m.resumo_midia)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// Carrega o thread (histórico) de um atendimento, mais antigas primeiro.
    pub async fn get_thread(
        &self,
        atendimento_id: i64,
        limit: i64,
        offset: i64,
    ) -> LocalResult<Vec<MensagemThread>> {
        let rows = sqlx::query_as::<_, MensagemThread>(
            "SELECT id, atendimento_id, tipo, conteudo, remetente, timestamp, \
             status_envio, gerado_por_ia, resumo_midia FROM mensagens \
             WHERE atendimento_id = ? ORDER BY timestamp ASC, id ASC LIMIT ? OFFSET ?",
        )
        .bind(atendimento_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await?;
        Ok(rows)
    }

    /// Aplica otimisticamente a mudança de etapa (drag-and-drop no Kanban). O
    /// RBAC fino é 100% server-side; aqui é só o reflexo local.
    pub async fn update_etapa(
        &self,
        atendimento_id: i64,
        etapa_destino_id: i64,
    ) -> LocalResult<()> {
        let res = sqlx::query("UPDATE atendimentos SET etapa_atual_id = ? WHERE id = ?")
            .bind(etapa_destino_id)
            .bind(atendimento_id)
            .execute(&self.pool)
            .await?;
        if res.rows_affected() == 0 {
            return Err(LocalEngineError::NotFound(format!(
                "atendimento {atendimento_id}"
            )));
        }
        Ok(())
    }

    /// Insere uma mensagem outbound ainda **pendente** (feita offline). Recebe
    /// um id client-side negativo para não colidir com ids reais do servidor
    /// (positivos); o id definitivo chega no sync. Devolve o id atribuído.
    pub async fn insert_pending_mensagem(
        &self,
        atendimento_id: i64,
        conteudo: &str,
        tipo: &str,
        remetente: &str,
        timestamp: i64,
    ) -> LocalResult<i64> {
        // Próximo id negativo: um a menos que o menor id atual (ou -1).
        let menor: Option<i64> = sqlx::query_scalar("SELECT MIN(id) FROM mensagens WHERE id < 0")
            .fetch_one(&self.pool)
            .await?;
        let novo_id = menor.unwrap_or(0) - 1;

        sqlx::query(
            "INSERT INTO mensagens (id, atendimento_id, tipo, conteudo, remetente, \
             timestamp, status_envio, gerado_por_ia, resumo_midia) \
             VALUES (?, ?, ?, ?, ?, ?, 'pendente', 0, NULL)",
        )
        .bind(novo_id)
        .bind(atendimento_id)
        .bind(tipo)
        .bind(conteudo)
        .bind(remetente)
        .bind(timestamp)
        .execute(&self.pool)
        .await?;
        Ok(novo_id)
    }
}
