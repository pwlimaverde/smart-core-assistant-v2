use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct Treinamento {
    pub id: i32,
    pub tenant_id: Uuid,
    pub tag: String,
    pub grupo: String,
    pub conteudo: Option<String>,
    pub treinamento_finalizado: bool,
    pub treinamento_vetorizado: bool,
    pub data_criacao: DateTime<Utc>,
    pub data_atualizacao: DateTime<Utc>,
}

#[async_trait]
pub trait TreinamentoRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        tag: &str,
        grupo: &str,
        conteudo: Option<&str>,
    ) -> Result<Treinamento, DbError>;

    async fn buscar_por_tag_grupo(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        tag: &str,
        grupo: &str,
    ) -> Result<Option<Treinamento>, DbError>;

    async fn marcar_finalizado(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        treinamento_id: i32,
    ) -> Result<(), DbError>;

    async fn marcar_vetorizado(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        treinamento_id: i32,
    ) -> Result<(), DbError>;

    async fn listar_pendentes_vetorizacao(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<Treinamento>, DbError>;

    /// Varredura CROSS-TENANT do scheduler: o que foi finalizado e ainda não
    /// virou vetor, de toda a base.
    ///
    /// Exige pool com BYPASSRLS (`admin_pool`) — no pool de aplicação a RLS
    /// devolve zero linhas em silêncio, e a fila pareceria sempre vazia.
    async fn listar_pendentes_global(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        limite: i64,
    ) -> Result<Vec<Treinamento>, DbError>;

    /// Lista tudo do tenant, do mais recente para o mais antigo.
    ///
    /// É o que a tela de acompanhamento mostra: os três estados (rascunho,
    /// aguardando vetorização e vetorizado) convivem na mesma lista, porque
    /// quem treinou precisa ver o que ficou pelo caminho.
    async fn listar_por_tenant(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<Treinamento>, DbError>;

    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        treinamento_id: i32,
    ) -> Result<Option<Treinamento>, DbError>;

    /// Substitui o conteúdo — o aceite da revisão, quando o texto foi editado.
    ///
    /// Zera `treinamento_vetorizado`: o conteúdo mudou, e os vetores antigos
    /// já não representam o texto. A revetorização é do worker.
    async fn atualizar_conteudo(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        treinamento_id: i32,
        conteudo: &str,
    ) -> Result<bool, DbError>;

    /// Remove o treinamento e, por cascata, seus documentos.
    async fn remover(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        treinamento_id: i32,
    ) -> Result<bool, DbError>;
}

pub struct PostgresTreinamentoRepository;

#[async_trait]
impl TreinamentoRepository for PostgresTreinamentoRepository {
    #[tracing::instrument(skip_all, fields(tag = %tag, grupo = %grupo))]
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        tag: &str,
        grupo: &str,
        conteudo: Option<&str>,
    ) -> Result<Treinamento, DbError> {
        ctx.exigir_qualquer(&["treinamento:write", "tenant:admin"])?;
        let row = sqlx::query_as!(
            Treinamento,
            r#"INSERT INTO oraculo_treinamento (tenant_id, tag, grupo, conteudo)
               VALUES ($1, $2, $3, $4)
               RETURNING id, tenant_id, tag, grupo, conteudo,
                         treinamento_finalizado, treinamento_vetorizado,
                         data_criacao, data_atualizacao"#,
            ctx.tenant_id,
            tag,
            grupo,
            conteudo
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(tag = %tag, grupo = %grupo))]
    async fn buscar_por_tag_grupo(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        tag: &str,
        grupo: &str,
    ) -> Result<Option<Treinamento>, DbError> {
        let row = sqlx::query_as!(
            Treinamento,
            r#"SELECT id, tenant_id, tag, grupo, conteudo,
                      treinamento_finalizado, treinamento_vetorizado,
                      data_criacao, data_atualizacao
               FROM oraculo_treinamento
               WHERE tenant_id = $1 AND tag = $2 AND grupo = $3"#,
            ctx.tenant_id,
            tag,
            grupo
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(treinamento_id = treinamento_id))]
    async fn marcar_finalizado(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        treinamento_id: i32,
    ) -> Result<(), DbError> {
        ctx.exigir_qualquer(&["treinamento:write", "tenant:admin"])?;
        sqlx::query!(
            r#"UPDATE oraculo_treinamento
               SET treinamento_finalizado = true, data_atualizacao = NOW()
               WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            treinamento_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(treinamento_id = treinamento_id))]
    async fn marcar_vetorizado(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        treinamento_id: i32,
    ) -> Result<(), DbError> {
        sqlx::query!(
            r#"UPDATE oraculo_treinamento
               SET treinamento_vetorizado = true, data_atualizacao = NOW()
               WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            treinamento_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all)]
    async fn listar_pendentes_vetorizacao(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<Treinamento>, DbError> {
        ctx.exigir_qualquer(&["treinamento:read", "tenant:admin"])?;
        let rows = sqlx::query_as!(
            Treinamento,
            r#"SELECT id, tenant_id, tag, grupo, conteudo,
                      treinamento_finalizado, treinamento_vetorizado,
                      data_criacao, data_atualizacao
               FROM oraculo_treinamento
               WHERE tenant_id = $1
                 AND treinamento_finalizado = true AND treinamento_vetorizado = false
               ORDER BY data_criacao"#,
            ctx.tenant_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

    #[tracing::instrument(skip_all, fields(limite = limite))]
    async fn listar_pendentes_global(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        limite: i64,
    ) -> Result<Vec<Treinamento>, DbError> {
        ctx.exigir_qualquer(&["treinamento:read", "tenant:admin"])?;
        // Cross-tenant por desenho (scheduler): sem `WHERE tenant_id`, e por
        // isso exige o pool com BYPASSRLS.
        let rows = sqlx::query_as::<_, Treinamento>(
            r#"SELECT id, tenant_id, tag, grupo, conteudo,
                      treinamento_finalizado, treinamento_vetorizado,
                      data_criacao, data_atualizacao
               FROM oraculo_treinamento
               WHERE treinamento_finalizado = true AND treinamento_vetorizado = false
               ORDER BY data_criacao ASC
               LIMIT $1"#,
        )
        .bind(limite)
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

    #[tracing::instrument(skip_all)]
    async fn listar_por_tenant(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<Treinamento>, DbError> {
        ctx.exigir_qualquer(&["treinamento:read", "tenant:admin"])?;
        let rows = sqlx::query_as!(
            Treinamento,
            r#"SELECT id, tenant_id, tag, grupo, conteudo,
                      treinamento_finalizado, treinamento_vetorizado,
                      data_criacao, data_atualizacao
               FROM oraculo_treinamento
               WHERE tenant_id = $1
               ORDER BY data_criacao DESC"#,
            ctx.tenant_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

    #[tracing::instrument(skip_all, fields(treinamento_id))]
    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        treinamento_id: i32,
    ) -> Result<Option<Treinamento>, DbError> {
        ctx.exigir_qualquer(&["treinamento:read", "tenant:admin"])?;
        let row = sqlx::query_as!(
            Treinamento,
            r#"SELECT id, tenant_id, tag, grupo, conteudo,
                      treinamento_finalizado, treinamento_vetorizado,
                      data_criacao, data_atualizacao
               FROM oraculo_treinamento
               WHERE id = $1 AND tenant_id = $2"#,
            treinamento_id,
            ctx.tenant_id
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(treinamento_id))]
    async fn atualizar_conteudo(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        treinamento_id: i32,
        conteudo: &str,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["treinamento:write", "tenant:admin"])?;
        let res = sqlx::query!(
            r#"UPDATE oraculo_treinamento
                  SET conteudo = $1,
                      treinamento_vetorizado = false,
                      data_atualizacao = NOW()
                WHERE id = $2 AND tenant_id = $3"#,
            conteudo,
            treinamento_id,
            ctx.tenant_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(res.rows_affected() > 0)
    }

    #[tracing::instrument(skip_all, fields(treinamento_id))]
    async fn remover(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        treinamento_id: i32,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["treinamento:write", "tenant:admin"])?;
        let res = sqlx::query!(
            "DELETE FROM oraculo_treinamento WHERE id = $1 AND tenant_id = $2",
            treinamento_id,
            ctx.tenant_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(res.rows_affected() > 0)
    }
}

/// B9 (N10 E6) — a avaliação de um ensaio de pergunta.
///
/// Não é um joinha: `resposta_corrigida` é a correção supervisionada de quem
/// treina. Pergunta e correção são texto livre do operador e podem citar dado de
/// cliente — por isso existem só aqui, nunca em log ou auditoria.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct NovoFeedbackTeste {
    pub pergunta: String,
    pub resposta_bot: String,
    /// `None` quando a pessoa só avaliou, sem escrever a resposta certa.
    pub resposta_corrigida: Option<String>,
    /// `boa` | `ruim`.
    pub avaliacao: String,
    pub confiabilidade: f64,
    pub comportamento_aplicado: String,
}

/// Grava a avaliação. Os trechos consultados não têm id no resultado do RAG, então
/// `documentos_ids` fica vazio; o comportamento aplicado vai em `intents_json`.
#[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, avaliacao = %novo.avaliacao))]
pub async fn registrar_feedback_teste(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    novo: &NovoFeedbackTeste,
) -> Result<i32, DbError> {
    ctx.exigir_qualquer(&["treinamento:write", "tenant:admin"])?;
    let (id,): (i32,) = sqlx::query_as(
        r#"INSERT INTO treinamento_query_test_feedback
             (tenant_id, mensagem_original, resposta_bot, resposta_corrigida,
              avaliacao, confiabilidade, intents_json)
           VALUES ($1, $2, $3, $4, $5, $6, $7)
           RETURNING id"#,
    )
    .bind(ctx.tenant_id)
    .bind(&novo.pergunta)
    .bind(&novo.resposta_bot)
    .bind(&novo.resposta_corrigida)
    .bind(&novo.avaliacao)
    .bind(novo.confiabilidade)
    .bind(serde_json::json!({ "comportamento_aplicado": novo.comportamento_aplicado }))
    .fetch_one(&mut **tx)
    .await?;
    Ok(id)
}

/// B9 (N10 E5) — um treinamento enviado como arquivo, já conferido no bucket.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct NovoTreinamentoComArquivo {
    pub tag: String,
    pub grupo: String,
    /// Chave do objeto no bucket, gerada pelo servidor em
    /// [`chave_de_treinamento`]. Nunca vem do cliente sem essa origem.
    pub chave: String,
    pub nome_arquivo: String,
    pub mimetype: String,
    /// Tamanho real, lido do bucket — não o que o cliente declarou.
    pub bytes: i64,
}

/// B9 — um arquivo esperando a extração de texto (fila do scheduler).
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct ExtracaoPendente {
    pub id: i32,
    pub tenant_id: String,
    pub chave: String,
    pub nome: String,
    pub mimetype: String,
}

/// B9 — o que a extração devolveu.
#[derive(Debug, Clone, PartialEq)]
pub enum ResultadoExtracao {
    Texto(String),
    /// Motivo pronto para quem treinou ler.
    Falha(String),
}

/// Onde o arquivo de treinamento mora no bucket. O `data_storage` prefixa o
/// tenant, então ele não repete aqui.
pub fn chave_de_treinamento() -> String {
    format!("treinamento/{}", Uuid::now_v7())
}

/// A quota do plano comporta mais `bytes`? Mesma regra do upload de mídia: limite
/// 0 é plano sem teto, e esquema antigo sem a coluna conta como "sem limite".
pub async fn quota_comporta(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    bytes: i64,
) -> Result<bool, DbError> {
    let uso: Option<(i64, i64)> = sqlx::query_as(
        r#"SELECT COALESCE(u.total_bytes, 0), COALESCE(p.max_storage_bytes, 0)
           FROM tenants_tenant t
           LEFT JOIN tenants_storage_usage u ON u.tenant_id = t.id
           LEFT JOIN tenants_subscription s ON s.tenant_id = t.id
           LEFT JOIN tenants_plan p ON p.id = s.plan_id
           WHERE t.id = $1"#,
    )
    .bind(tenant_id)
    .fetch_optional(&mut **tx)
    .await
    .unwrap_or(None);
    Ok(match uso {
        Some((usado, limite)) => limite <= 0 || usado + bytes <= limite,
        None => true,
    })
}

/// Cria (ou substitui, na mesma dupla tag+grupo) um treinamento por arquivo.
///
/// Nasce sem conteúdo e com a extração **pendente**: o texto chega pelo job do
/// scheduler, e daí o ciclo é o de sempre (revisar → finalizar → vetorizar). Os
/// bytes entram na contabilidade de armazenamento na mesma transação.
#[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, bytes = novo.bytes))]
pub async fn criar_com_arquivo(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    novo: &NovoTreinamentoComArquivo,
) -> Result<i32, DbError> {
    ctx.exigir_qualquer(&["treinamento:write", "tenant:admin"])?;
    let (id,): (i32,) = sqlx::query_as(
        r#"INSERT INTO oraculo_treinamento
             (tenant_id, tag, grupo, conteudo, treinamento_finalizado,
              treinamento_vetorizado, arquivo_chave, arquivo_nome,
              arquivo_mimetype, arquivo_bytes, extracao_status)
           VALUES ($1, $2, $3, NULL, false, false, $4, $5, $6, $7, 'pendente')
           ON CONFLICT (tenant_id, tag, grupo) DO UPDATE
             SET conteudo = NULL,
                 treinamento_finalizado = false,
                 treinamento_vetorizado = false,
                 arquivo_chave = EXCLUDED.arquivo_chave,
                 arquivo_nome = EXCLUDED.arquivo_nome,
                 arquivo_mimetype = EXCLUDED.arquivo_mimetype,
                 arquivo_bytes = EXCLUDED.arquivo_bytes,
                 extracao_status = 'pendente',
                 extracao_erro = NULL,
                 data_atualizacao = NOW()
           RETURNING id"#,
    )
    .bind(ctx.tenant_id)
    .bind(&novo.tag)
    .bind(&novo.grupo)
    .bind(&novo.chave)
    .bind(&novo.nome_arquivo)
    .bind(&novo.mimetype)
    .bind(novo.bytes)
    .fetch_one(&mut **tx)
    .await?;

    sqlx::query(
        r#"INSERT INTO tenants_storage_usage (tenant_id, total_bytes)
           VALUES ($1, $2)
           ON CONFLICT (tenant_id)
           DO UPDATE SET total_bytes = tenants_storage_usage.total_bytes + $2,
                         updated_at = NOW()"#,
    )
    .bind(ctx.tenant_id)
    .bind(novo.bytes)
    .execute(&mut **tx)
    .await?;
    Ok(id)
}

/// A fila da extração, de toda a base. Exige o pool com BYPASSRLS, como a fila
/// de vetorização.
pub async fn listar_extracoes_pendentes(
    tx: &mut Transaction<'_, Postgres>,
    limite: i64,
) -> Result<Vec<ExtracaoPendente>, DbError> {
    let linhas: Vec<(i32, Uuid, String, String, String)> = sqlx::query_as(
        r#"SELECT id, tenant_id, arquivo_chave,
                  COALESCE(arquivo_nome, ''), COALESCE(arquivo_mimetype, '')
           FROM oraculo_treinamento
           WHERE extracao_status = 'pendente' AND arquivo_chave IS NOT NULL
           ORDER BY data_criacao ASC
           LIMIT $1"#,
    )
    .bind(limite)
    .fetch_all(&mut **tx)
    .await?;
    Ok(linhas
        .into_iter()
        .map(|(id, tenant_id, chave, nome, mimetype)| ExtracaoPendente {
            id,
            tenant_id: tenant_id.to_string(),
            chave,
            nome,
            mimetype,
        })
        .collect())
}

/// Grava o resultado da extração. Só age sobre o que ainda está pendente: um
/// arquivo substituído no meio do caminho não recebe o texto do anterior.
#[tracing::instrument(skip_all, fields(tenant_id = %tenant_id, treinamento_id = id))]
pub async fn registrar_extracao(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    id: i32,
    resultado: &ResultadoExtracao,
) -> Result<bool, DbError> {
    let (conteudo, status, erro) = match resultado {
        ResultadoExtracao::Texto(texto) => (Some(texto.as_str()), "extraido", None),
        ResultadoExtracao::Falha(motivo) => (None, "falhou", Some(motivo.as_str())),
    };
    let res = sqlx::query(
        r#"UPDATE oraculo_treinamento
           SET conteudo = COALESCE($3, conteudo),
               extracao_status = $4,
               extracao_erro = $5,
               data_atualizacao = NOW()
           WHERE tenant_id = $1 AND id = $2 AND extracao_status = 'pendente'"#,
    )
    .bind(tenant_id)
    .bind(id)
    .bind(conteudo)
    .bind(status)
    .bind(erro)
    .execute(&mut **tx)
    .await?;
    Ok(res.rows_affected() > 0)
}

/// Nome do arquivo, situação e erro da extração, por treinamento. Só aparecem
/// os que vieram de arquivo.
pub async fn situacao_dos_arquivos(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    ids: &[i32],
) -> Result<std::collections::HashMap<i32, (String, String, String)>, DbError> {
    if ids.is_empty() {
        return Ok(std::collections::HashMap::new());
    }
    let linhas: Vec<(i32, String, String, String)> = sqlx::query_as(
        r#"SELECT id, COALESCE(arquivo_nome, ''), COALESCE(extracao_status, ''),
                  COALESCE(extracao_erro, '')
           FROM oraculo_treinamento
           WHERE tenant_id = $1 AND id = ANY($2) AND arquivo_chave IS NOT NULL"#,
    )
    .bind(ctx.tenant_id)
    .bind(ids)
    .fetch_all(&mut **tx)
    .await?;
    Ok(linhas
        .into_iter()
        .map(|(id, nome, status, erro)| (id, (nome, status, erro)))
        .collect())
}

/// P17 — uma avaliação do teste de resposta, para a revisão.
///
/// Pergunta e correção são texto livre do operador e podem citar cliente:
/// viajam até a tela de quem treina, nunca para log nem auditoria.
#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct AvaliacaoDeTeste {
    pub id: i32,
    pub pergunta: String,
    pub resposta_bot: String,
    pub resposta_corrigida: Option<String>,
    pub avaliacao: String,
    pub confiabilidade: f64,
    pub created_at: DateTime<Utc>,
}

/// P17 — as avaliações ainda não tratadas, as ruins primeiro (são as que pedem
/// ação), depois as mais novas.
#[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
pub async fn listar_avaliacoes_pendentes(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    limite: i64,
) -> Result<Vec<AvaliacaoDeTeste>, DbError> {
    ctx.exigir_qualquer(&["treinamento:read", "treinamento:write", "tenant:admin"])?;
    let rows = sqlx::query_as::<_, AvaliacaoDeTeste>(
        r#"SELECT id, mensagem_original AS pergunta, resposta_bot, resposta_corrigida,
                  avaliacao, confiabilidade, created_at
             FROM treinamento_query_test_feedback
            WHERE tenant_id = $1 AND tratada_em IS NULL
            ORDER BY (avaliacao = 'ruim') DESC, created_at DESC
            LIMIT $2"#,
    )
    .bind(ctx.tenant_id)
    .bind(limite.clamp(1, 200))
    .fetch_all(&mut **tx)
    .await?;
    Ok(rows)
}

/// P17 — tira a avaliação da lista de revisão. `false` = já estava tratada ou
/// não é deste tenant.
#[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, id = id))]
pub async fn marcar_avaliacao_tratada(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    id: i32,
) -> Result<bool, DbError> {
    ctx.exigir_qualquer(&["treinamento:write", "tenant:admin"])?;
    let r = sqlx::query(
        r#"UPDATE treinamento_query_test_feedback
              SET tratada_em = NOW()
            WHERE tenant_id = $1 AND id = $2 AND tratada_em IS NULL"#,
    )
    .bind(ctx.tenant_id)
    .bind(id)
    .execute(&mut **tx)
    .await?;
    Ok(r.rows_affected() > 0)
}
