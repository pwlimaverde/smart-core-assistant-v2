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
        // N7.4: id negativo atribuído ATOMICAMENTE num único statement
        // (`INSERT ... SELECT COALESCE(MIN(id),0)-1 ...`), em vez de um
        // `SELECT MIN` seguido de `INSERT` separados — a mesma classe de corrida
        // corrigida em `OfflineQueue::enqueue` (duas conexões do pool podiam ler
        // o mesmo `MIN` antes de qualquer uma commitar, colidindo no id).
        let novo_id: i64 = sqlx::query_scalar(
            "INSERT INTO mensagens (id, atendimento_id, tipo, conteudo, remetente, \
             timestamp, status_envio, gerado_por_ia, resumo_midia) \
             SELECT COALESCE(MIN(id), 0) - 1, ?, ?, ?, ?, ?, 'pendente', 0, NULL \
             FROM mensagens WHERE id < 0 \
             RETURNING id",
        )
        .bind(atendimento_id)
        .bind(tipo)
        .bind(conteudo)
        .bind(remetente)
        .bind(timestamp)
        .fetch_one(&self.pool)
        .await?;
        Ok(novo_id)
    }

    /// Promove uma mensagem pendente (id client-side negativo) ao id definitivo
    /// do servidor após o sync. `UPDATE OR REPLACE`: se o servidor já tiver sido
    /// re-ingestado (linha com o id definitivo já existe), a pendente a substitui
    /// — sobra exatamente uma linha, sem duplicata fantasma. Idempotente: linha
    /// pendente ausente é no-op.
    pub async fn promover_mensagem_pendente(
        &self,
        local_id: i64,
        definitivo_id: i64,
    ) -> LocalResult<()> {
        sqlx::query(
            "UPDATE OR REPLACE mensagens SET id = ?, status_envio = 'enviado' WHERE id = ?",
        )
        .bind(definitivo_id)
        .bind(local_id)
        .execute(&self.pool)
        .await?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn resumo(id: i64, status: &str, departamento_id: Option<i64>) -> AtendimentoResumo {
        AtendimentoResumo {
            id,
            contato_id: 10,
            status: status.to_string(),
            departamento_id,
            fluxo_atendimento_id: None,
            etapa_atual_id: None,
            assunto: "assunto".to_string(),
            prioridade: "normal".to_string(),
            atendente_humano_id: None,
            data_inicio: 1_000,
            data_ultima_mensagem: None,
        }
    }

    fn mensagem(id: i64, atendimento_id: i64, timestamp: i64) -> MensagemThread {
        MensagemThread {
            id,
            atendimento_id,
            tipo: "texto".to_string(),
            conteudo: "oi".to_string(),
            remetente: "cliente".to_string(),
            timestamp,
            status_envio: "enviado".to_string(),
            gerado_por_ia: false,
            resumo_midia: None,
        }
    }

    #[tokio::test]
    async fn upsert_atendimento_insere_e_depois_atualiza_por_conflito() {
        let idx = SqliteIndex::open_in_memory().await.unwrap();
        idx.upsert_atendimento(&resumo(1, "fila", Some(5)))
            .await
            .unwrap();

        // Segunda chamada com o mesmo id deve atualizar (ON CONFLICT), não duplicar.
        idx.upsert_atendimento(&resumo(1, "em_atendimento", Some(5)))
            .await
            .unwrap();

        let lista = idx
            .list_atendimentos("em_atendimento", Some(5), 10)
            .await
            .unwrap();
        assert_eq!(lista.len(), 1);
        assert_eq!(lista[0].status, "em_atendimento");

        // O status antigo não deve mais aparecer.
        let antigos = idx.list_atendimentos("fila", Some(5), 10).await.unwrap();
        assert!(antigos.is_empty());
    }

    #[tokio::test]
    async fn list_atendimentos_com_departamento_none_ignora_o_filtro() {
        let idx = SqliteIndex::open_in_memory().await.unwrap();
        idx.upsert_atendimento(&resumo(1, "fila", Some(5)))
            .await
            .unwrap();
        idx.upsert_atendimento(&resumo(2, "fila", Some(9)))
            .await
            .unwrap();

        let todos = idx.list_atendimentos("fila", None, 10).await.unwrap();
        assert_eq!(todos.len(), 2);
    }

    #[tokio::test]
    async fn list_atendimentos_respeita_o_limit() {
        let idx = SqliteIndex::open_in_memory().await.unwrap();
        for i in 1..=5 {
            idx.upsert_atendimento(&resumo(i, "fila", None))
                .await
                .unwrap();
        }
        let pagina = idx.list_atendimentos("fila", None, 2).await.unwrap();
        assert_eq!(pagina.len(), 2);
    }

    #[tokio::test]
    async fn upsert_mensagem_insere_e_atualiza_por_conflito() {
        let idx = SqliteIndex::open_in_memory().await.unwrap();
        idx.upsert_mensagem(&mensagem(1, 100, 10)).await.unwrap();

        let mut atualizada = mensagem(1, 100, 10);
        atualizada.conteudo = "conteudo editado".to_string();
        idx.upsert_mensagem(&atualizada).await.unwrap();

        let thread = idx.get_thread(100, 10, 0).await.unwrap();
        assert_eq!(thread.len(), 1);
        assert_eq!(thread[0].conteudo, "conteudo editado");
    }

    #[tokio::test]
    async fn get_thread_ordena_por_timestamp_e_pagina_com_limit_offset() {
        let idx = SqliteIndex::open_in_memory().await.unwrap();
        idx.upsert_mensagem(&mensagem(1, 100, 30)).await.unwrap();
        idx.upsert_mensagem(&mensagem(2, 100, 10)).await.unwrap();
        idx.upsert_mensagem(&mensagem(3, 100, 20)).await.unwrap();

        let pagina1 = idx.get_thread(100, 2, 0).await.unwrap();
        assert_eq!(pagina1.iter().map(|m| m.id).collect::<Vec<_>>(), vec![2, 3]);

        let pagina2 = idx.get_thread(100, 2, 2).await.unwrap();
        assert_eq!(pagina2.iter().map(|m| m.id).collect::<Vec<_>>(), vec![1]);
    }

    #[tokio::test]
    async fn update_etapa_altera_a_etapa_atual_do_atendimento_existente() {
        let idx = SqliteIndex::open_in_memory().await.unwrap();
        idx.upsert_atendimento(&resumo(1, "fila", None))
            .await
            .unwrap();

        idx.update_etapa(1, 42).await.unwrap();

        let lista = idx.list_atendimentos("fila", None, 10).await.unwrap();
        assert_eq!(lista[0].etapa_atual_id, Some(42));
    }

    #[tokio::test]
    async fn update_etapa_em_atendimento_inexistente_retorna_not_found() {
        let idx = SqliteIndex::open_in_memory().await.unwrap();
        let err = idx.update_etapa(999, 1).await.unwrap_err();
        assert!(matches!(err, LocalEngineError::NotFound(_)));
    }

    #[tokio::test]
    async fn insert_pending_mensagem_atribui_ids_negativos_decrescentes() {
        let idx = SqliteIndex::open_in_memory().await.unwrap();
        let id1 = idx
            .insert_pending_mensagem(1, "primeira", "texto", "atendente", 100)
            .await
            .unwrap();
        let id2 = idx
            .insert_pending_mensagem(1, "segunda", "texto", "atendente", 200)
            .await
            .unwrap();

        assert_eq!(id1, -1);
        assert_eq!(id2, -2);

        let thread = idx.get_thread(1, 10, 0).await.unwrap();
        assert_eq!(thread.len(), 2);
        assert!(thread.iter().all(|m| m.status_envio == "pendente"));
    }

    /// N7.4 — regressão: `insert_pending_mensagem` atribui o id negativo num
    /// único statement (`INSERT ... SELECT COALESCE(MIN(id),0)-1 ...`), em vez
    /// de um `SELECT MIN` seguido de `INSERT` separados. Duas inserções
    /// concorrentes devem sempre sair com ids distintos, nunca colidindo.
    #[tokio::test]
    async fn insert_pending_mensagem_concorrente_atribui_ids_distintos() {
        let idx = SqliteIndex::open_in_memory().await.unwrap();
        let idx1 = idx.clone();
        let idx2 = idx.clone();

        let (id1, id2) = tokio::join!(
            idx1.insert_pending_mensagem(1, "a", "texto", "atendente", 100),
            idx2.insert_pending_mensagem(1, "b", "texto", "atendente", 200),
        );
        let (id1, id2) = (id1.unwrap(), id2.unwrap());

        assert_ne!(
            id1, id2,
            "duas inserções concorrentes não podem colidir no id"
        );
        let thread = idx.get_thread(1, 10, 0).await.unwrap();
        assert_eq!(
            thread.len(),
            2,
            "ambas as mensagens devem ter sido persistidas"
        );
    }

    #[tokio::test]
    async fn promover_mensagem_pendente_troca_o_id_e_marca_como_enviado() {
        let idx = SqliteIndex::open_in_memory().await.unwrap();
        let id_local = idx
            .insert_pending_mensagem(1, "oi", "texto", "atendente", 100)
            .await
            .unwrap();

        idx.promover_mensagem_pendente(id_local, 777).await.unwrap();

        let thread = idx.get_thread(1, 10, 0).await.unwrap();
        assert_eq!(thread.len(), 1);
        assert_eq!(thread[0].id, 777);
        assert_eq!(thread[0].status_envio, "enviado");
    }

    #[tokio::test]
    async fn promover_mensagem_pendente_sem_linha_correspondente_e_no_op() {
        let idx = SqliteIndex::open_in_memory().await.unwrap();
        // Nenhuma linha com id -5: a promoção não deve falhar nem criar nada.
        idx.promover_mensagem_pendente(-5, 777).await.unwrap();

        let thread = idx.get_thread(1, 10, 0).await.unwrap();
        assert!(thread.is_empty());
    }

    #[tokio::test]
    async fn promover_mensagem_pendente_substitui_quando_id_definitivo_ja_existe() {
        // Cenário de re-ingestão: o servidor já mandou a mensagem definitiva
        // (id 777) antes da promoção local rodar. UPDATE OR REPLACE deve deixar
        // exatamente uma linha, sem duplicata fantasma.
        let idx = SqliteIndex::open_in_memory().await.unwrap();
        idx.upsert_mensagem(&mensagem(777, 1, 500)).await.unwrap();
        let id_local = idx
            .insert_pending_mensagem(1, "pendente", "texto", "atendente", 100)
            .await
            .unwrap();

        idx.promover_mensagem_pendente(id_local, 777).await.unwrap();

        let thread = idx.get_thread(1, 10, 0).await.unwrap();
        assert_eq!(thread.len(), 1);
        assert_eq!(thread[0].id, 777);
    }
}
