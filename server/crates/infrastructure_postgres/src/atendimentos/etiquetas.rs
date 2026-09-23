use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct Etiqueta {
    pub id: i64,
    pub tenant_id: Uuid,
    pub nome: String,
    pub cor: String,
    pub descricao: String,
    pub ativo: bool,
    pub data_criacao: DateTime<Utc>,
}

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct Nota {
    pub id: i64,
    pub tenant_id: Uuid,
    pub atendimento_id: i32,
    pub texto: String,
    pub criado_por_id: Option<i32>,
    pub criado_em: DateTime<Utc>,
}

#[async_trait]
pub trait EtiquetaRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        nome: &str,
        cor: Option<&str>,
    ) -> Result<Etiqueta, DbError>;

    async fn listar_ativas(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<Etiqueta>, DbError>;

    async fn aplicar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        etiqueta_id: i64,
    ) -> Result<(), DbError>;

    async fn remover(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        etiqueta_id: i64,
    ) -> Result<(), DbError>;

    /// As etiquetas aplicadas a um atendimento.
    ///
    /// Diferente de `listar_ativas`, que é o catálogo do tenant: uma é o que
    /// existe para escolher, a outra é o que está colado nesta conversa.
    async fn listar_do_atendimento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<Vec<Etiqueta>, DbError>;
}

#[async_trait]
pub trait NotaRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        texto: &str,
        criado_por_id: Option<i32>,
    ) -> Result<Nota, DbError>;

    async fn listar_por_atendimento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<Vec<Nota>, DbError>;
}

pub struct PostgresEtiquetaRepository;
pub struct PostgresNotaRepository;

#[async_trait]
impl EtiquetaRepository for PostgresEtiquetaRepository {
    #[tracing::instrument(skip_all, fields(nome = %nome))]
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        nome: &str,
        cor: Option<&str>,
    ) -> Result<Etiqueta, DbError> {
        ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
        let cor_val = cor.unwrap_or("#a98f71");
        let row = sqlx::query_as!(
            Etiqueta,
            r#"INSERT INTO atu_etiqueta (tenant_id, nome, cor)
               VALUES ($1, $2, $3)
               RETURNING id, tenant_id, nome, cor, descricao, ativo, data_criacao"#,
            ctx.tenant_id,
            nome,
            cor_val
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }

    #[tracing::instrument(skip_all)]
    async fn listar_ativas(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<Etiqueta>, DbError> {
        let rows = sqlx::query_as!(
            Etiqueta,
            r#"SELECT id, tenant_id, nome, cor, descricao, ativo, data_criacao
               FROM atu_etiqueta
               WHERE tenant_id = $1 AND ativo = true
               ORDER BY nome"#,
            ctx.tenant_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id, etiqueta_id = etiqueta_id))]
    async fn aplicar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        etiqueta_id: i64,
    ) -> Result<(), DbError> {
        sqlx::query!(
            r#"INSERT INTO atu_etiqueta_atendimento (tenant_id, atendimento_id, etiqueta_id)
               VALUES ($1, $2, $3) ON CONFLICT DO NOTHING"#,
            ctx.tenant_id,
            atendimento_id,
            etiqueta_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id, etiqueta_id = etiqueta_id))]
    async fn remover(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        etiqueta_id: i64,
    ) -> Result<(), DbError> {
        sqlx::query!(
            r#"DELETE FROM atu_etiqueta_atendimento
               WHERE tenant_id = $1 AND atendimento_id = $2 AND etiqueta_id = $3"#,
            ctx.tenant_id,
            atendimento_id,
            etiqueta_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id))]
    async fn listar_do_atendimento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<Vec<Etiqueta>, DbError> {
        ctx.exigir_qualquer(&["atendimentos:read", "tenant:admin"])?;
        // Inclui as desativadas do catálogo: uma etiqueta aplicada e depois
        // desativada continua contando a história desta conversa, e sumir com
        // ela reescreveria o passado.
        let rows = sqlx::query_as!(
            Etiqueta,
            r#"SELECT e.id, e.tenant_id, e.nome, e.cor, e.descricao, e.ativo,
                      e.data_criacao
                 FROM atu_etiqueta e
                 JOIN atu_etiqueta_atendimento ea
                   ON ea.etiqueta_id = e.id AND ea.tenant_id = e.tenant_id
                WHERE e.tenant_id = $1 AND ea.atendimento_id = $2
                ORDER BY ea.aplicada_em"#,
            ctx.tenant_id,
            atendimento_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }
}

#[async_trait]
impl NotaRepository for PostgresNotaRepository {
    // `texto` é conteúdo livre do atendente: `skip_all` evita logá-lo.
    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id))]
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        texto: &str,
        criado_por_id: Option<i32>,
    ) -> Result<Nota, DbError> {
        let row = sqlx::query_as!(
            Nota,
            r#"INSERT INTO atu_nota (tenant_id, atendimento_id, texto, criado_por_id)
               VALUES ($1, $2, $3, $4)
               RETURNING id, tenant_id, atendimento_id, texto, criado_por_id, criado_em"#,
            ctx.tenant_id,
            atendimento_id,
            texto,
            criado_por_id
        )
        .fetch_one(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id))]
    async fn listar_por_atendimento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<Vec<Nota>, DbError> {
        let rows = sqlx::query_as!(
            Nota,
            r#"SELECT id, tenant_id, atendimento_id, texto, criado_por_id, criado_em
               FROM atu_nota
               WHERE tenant_id = $1 AND atendimento_id = $2
               ORDER BY criado_em DESC"#,
            ctx.tenant_id,
            atendimento_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }
}

/// P5 — apaga uma nota interna.
///
/// O `atendimento_id` entra no WHERE junto do id da nota: sem ele, um id
/// adivinhado apagaria nota de outra conversa do mesmo tenant.
#[tracing::instrument(skip_all, fields(nota_id = nota_id, atendimento_id = atendimento_id))]
pub async fn remover_nota(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    nota_id: i64,
    atendimento_id: i32,
) -> Result<bool, DbError> {
    ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
    let r = sqlx::query(
        "DELETE FROM atu_nota WHERE tenant_id = $1 AND id = $2 AND atendimento_id = $3",
    )
    .bind(ctx.tenant_id)
    .bind(nota_id)
    .bind(atendimento_id)
    .execute(&mut **tx)
    .await?;
    Ok(r.rows_affected() > 0)
}

/// P5 — o que volta de uma edição de etiqueta.
///
/// Struct em vez de tupla de cinco: o `clippy` recusa o tipo composto, e com
/// razão — quem lê a assinatura não adivinha a ordem de três `String`s.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct EtiquetaAtualizada {
    pub id: i64,
    pub nome: String,
    pub cor: String,
    pub descricao: String,
    pub ativo: bool,
}

/// P5 — renomeia/recolore uma etiqueta do catálogo.
#[tracing::instrument(skip_all, fields(etiqueta_id = id))]
pub async fn atualizar_etiqueta(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    id: i64,
    nome: &str,
    cor: &str,
    descricao: &str,
) -> Result<Option<EtiquetaAtualizada>, DbError> {
    ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
    let row = sqlx::query_as::<_, EtiquetaAtualizada>(
        r#"UPDATE atu_etiqueta
              SET nome = $1, cor = $2, descricao = $3
            WHERE tenant_id = $4 AND id = $5
        RETURNING id, nome, cor, descricao, ativo"#,
    )
    .bind(nome)
    .bind(cor)
    .bind(descricao)
    .bind(ctx.tenant_id)
    .bind(id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(DbError::from_sqlx_unique)?;
    Ok(row)
}

/// P5 — tira a etiqueta do catálogo **sem** apagá-la das conversas.
///
/// Desativar e não excluir: a etiqueta aplicada é história do atendimento, e
/// apagar a linha reescreveria o passado só porque o catálogo mudou.
#[tracing::instrument(skip_all, fields(etiqueta_id = id))]
pub async fn desativar_etiqueta(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    id: i64,
) -> Result<bool, DbError> {
    ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
    let r = sqlx::query("UPDATE atu_etiqueta SET ativo = false WHERE tenant_id = $1 AND id = $2")
        .bind(ctx.tenant_id)
        .bind(id)
        .execute(&mut **tx)
        .await?;
    Ok(r.rows_affected() > 0)
}

/// P14 — uma etiqueta que a IA acabou de colocar.
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct EtiquetaAplicadaPelaIa {
    pub id: i64,
    pub nome: String,
    pub confianca: f64,
}

/// P14 — nome de etiqueta e tipo de intenção na mesma forma, para casar
/// "Segunda via de boleto" com `segunda_via_boleto`: minúsculas, sem acento,
/// e `_`/`-` como espaço. Palavras curtas ("de", "da") ficam de fora, porque a
/// tag da intenção costuma omiti-las.
pub fn forma_de_comparacao(texto: &str) -> String {
    let sem_acento: String = texto
        .to_lowercase()
        .chars()
        .map(|c| match c {
            'á' | 'à' | 'â' | 'ã' | 'ä' => 'a',
            'é' | 'è' | 'ê' | 'ë' => 'e',
            'í' | 'ì' | 'î' | 'ï' => 'i',
            'ó' | 'ò' | 'ô' | 'õ' | 'ö' => 'o',
            'ú' | 'ù' | 'û' | 'ü' => 'u',
            'ç' => 'c',
            '_' | '-' => ' ',
            outro => outro,
        })
        .collect();
    sem_acento
        .split_whitespace()
        .filter(|p| p.len() > 2)
        .collect::<Vec<_>>()
        .join(" ")
}

/// P14 — quais etiquetas do catálogo casam com as intenções confiantes.
///
/// Regra pura, testada à parte: só intenção com confiança >= `piso`; só
/// etiqueta que já existe e está ativa (a IA **nunca cria** etiqueta — o
/// catálogo é curadoria do tenant); nada que esteja em `bloqueadas`.
pub fn etiquetas_para_as_intencoes(
    catalogo: &[(i64, String)],
    intencoes: &[(String, f64)],
    bloqueadas: &[i64],
    piso: f64,
) -> Vec<EtiquetaAplicadaPelaIa> {
    let mut saida: Vec<EtiquetaAplicadaPelaIa> = Vec::new();
    for (tipo, confianca) in intencoes {
        if *confianca < piso {
            continue;
        }
        let alvo = forma_de_comparacao(tipo);
        if alvo.is_empty() {
            continue;
        }
        for (id, nome) in catalogo {
            if bloqueadas.contains(id) || saida.iter().any(|e| e.id == *id) {
                continue;
            }
            if forma_de_comparacao(nome) == alvo {
                saida.push(EtiquetaAplicadaPelaIa {
                    id: *id,
                    nome: nome.clone(),
                    confianca: *confianca,
                });
            }
        }
    }
    saida
}

/// P14 — aplica as etiquetas das intenções, marcando `origem = 'ia'`.
///
/// Devolve só as que entraram agora: `ON CONFLICT DO NOTHING` deixa de fora a
/// que já estava, e ela não conta de novo na auditoria.
#[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id))]
pub async fn aplicar_etiquetas_por_intencao(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    atendimento_id: i32,
    intencoes: &[(String, f64)],
    piso: f64,
) -> Result<Vec<EtiquetaAplicadaPelaIa>, DbError> {
    ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
    if intencoes.iter().all(|(_, c)| *c < piso) {
        return Ok(Vec::new());
    }
    let catalogo = sqlx::query_as::<_, (i64, String)>(
        "SELECT id, nome FROM atu_etiqueta WHERE tenant_id = $1 AND ativo = true",
    )
    .bind(ctx.tenant_id)
    .fetch_all(&mut **tx)
    .await?;
    let bloqueadas: Vec<i64> = sqlx::query_as::<_, (i64,)>(
        "SELECT etiqueta_id FROM atu_etiqueta_bloqueada \
         WHERE tenant_id = $1 AND atendimento_id = $2",
    )
    .bind(ctx.tenant_id)
    .bind(atendimento_id)
    .fetch_all(&mut **tx)
    .await?
    .into_iter()
    .map(|(id,)| id)
    .collect();

    let candidatas = etiquetas_para_as_intencoes(&catalogo, intencoes, &bloqueadas, piso);
    let mut aplicadas = Vec::new();
    for e in candidatas {
        let r = sqlx::query(
            r#"INSERT INTO atu_etiqueta_atendimento (tenant_id, atendimento_id, etiqueta_id, origem)
               VALUES ($1, $2, $3, 'ia') ON CONFLICT DO NOTHING"#,
        )
        .bind(ctx.tenant_id)
        .bind(atendimento_id)
        .bind(e.id)
        .execute(&mut **tx)
        .await?;
        if r.rows_affected() > 0 {
            aplicadas.push(e);
        }
    }
    Ok(aplicadas)
}

/// P14 — a remoção feita por uma pessoa: a IA não recoloca no mesmo atendimento.
#[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id, etiqueta_id = etiqueta_id))]
pub async fn bloquear_etiqueta_para_ia(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    atendimento_id: i32,
    etiqueta_id: i64,
) -> Result<(), DbError> {
    sqlx::query(
        r#"INSERT INTO atu_etiqueta_bloqueada (tenant_id, atendimento_id, etiqueta_id, por_usuario_id)
           VALUES ($1, $2, $3, NULLIF($4, 0)) ON CONFLICT DO NOTHING"#,
    )
    .bind(ctx.tenant_id)
    .bind(atendimento_id)
    .bind(etiqueta_id)
    .bind(ctx.user_id)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

/// P14 — religar à mão desfaz o bloqueio.
#[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id, etiqueta_id = etiqueta_id))]
pub async fn desbloquear_etiqueta_para_ia(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    atendimento_id: i32,
    etiqueta_id: i64,
) -> Result<(), DbError> {
    sqlx::query(
        "DELETE FROM atu_etiqueta_bloqueada \
         WHERE tenant_id = $1 AND atendimento_id = $2 AND etiqueta_id = $3",
    )
    .bind(ctx.tenant_id)
    .bind(atendimento_id)
    .bind(etiqueta_id)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

/// P14 — as etiquetas deste atendimento que a IA colocou (para o ✨ da ficha).
#[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id))]
pub async fn etiquetas_da_ia(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    atendimento_id: i32,
) -> Result<Vec<i64>, DbError> {
    let rows = sqlx::query_as::<_, (i64,)>(
        "SELECT etiqueta_id FROM atu_etiqueta_atendimento \
         WHERE tenant_id = $1 AND atendimento_id = $2 AND origem = 'ia'",
    )
    .bind(ctx.tenant_id)
    .bind(atendimento_id)
    .fetch_all(&mut **tx)
    .await?;
    Ok(rows.into_iter().map(|(id,)| id).collect())
}

#[cfg(test)]
mod testes_p14 {
    use super::*;

    fn catalogo() -> Vec<(i64, String)> {
        vec![
            (1, "Segunda via de boleto".to_string()),
            (2, "Orçamento".to_string()),
            (3, "Reclamação".to_string()),
        ]
    }

    #[test]
    fn casa_tag_da_intencao_com_nome_da_etiqueta() {
        let r = etiquetas_para_as_intencoes(
            &catalogo(),
            &[
                ("segunda_via_boleto".into(), 0.9),
                ("orcamento".into(), 0.85),
            ],
            &[],
            0.8,
        );
        assert_eq!(r.iter().map(|e| e.id).collect::<Vec<_>>(), vec![1, 2]);
    }

    #[test]
    fn abaixo_do_piso_nao_etiqueta() {
        let r = etiquetas_para_as_intencoes(&catalogo(), &[("orcamento".into(), 0.5)], &[], 0.8);
        assert!(r.is_empty());
    }

    #[test]
    fn intencao_sem_etiqueta_no_catalogo_nao_cria_nada() {
        let r =
            etiquetas_para_as_intencoes(&catalogo(), &[("cancelamento".into(), 0.99)], &[], 0.8);
        assert!(r.is_empty());
    }

    #[test]
    fn removida_por_humano_nao_volta() {
        let r = etiquetas_para_as_intencoes(&catalogo(), &[("reclamacao".into(), 0.95)], &[3], 0.8);
        assert!(r.is_empty());
    }

    #[test]
    fn a_mesma_etiqueta_nao_entra_duas_vezes() {
        let r = etiquetas_para_as_intencoes(
            &catalogo(),
            &[("orcamento".into(), 0.9), ("Orçamento".into(), 0.95)],
            &[],
            0.8,
        );
        assert_eq!(r.len(), 1);
    }
}
