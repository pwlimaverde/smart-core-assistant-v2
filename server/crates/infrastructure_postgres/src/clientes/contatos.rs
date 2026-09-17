use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct Contato {
    pub id: i32,
    pub tenant_id: Uuid,
    pub telefone: Option<String>,
    pub nome_contato: Option<String>,
    pub slug: String,
    pub email: Option<String>,
    pub nome_perfil_whatsapp: Option<String>,
    pub data_cadastro: DateTime<Utc>,
    pub ultima_interacao: DateTime<Utc>,
    pub ativo: bool,
    pub metadados: serde_json::Value,
    pub foto_perfil: Option<String>,
    pub foto_perfil_url_origem: Option<String>,
}

/// O que se pode mudar num contato já cadastrado (C4).
///
/// `None` em qualquer campo é "não mexe nisso" — diferente de string vazia,
/// que é "apaga o que estava lá". A distinção importa porque a tela manda o
/// formulário inteiro em toda edição.
#[derive(Debug, Clone, Default)]
pub struct EdicaoContato {
    pub nome_contato: Option<String>,
    pub email: Option<String>,
    pub telefone: Option<String>,
}

#[async_trait]
pub trait ContatoRepository: Send + Sync {
    async fn salvar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        telefone: &str,
        nome_contato: Option<&str>,
    ) -> Result<Contato, DbError>;

    /// Cadastra um contato de propósito, antes de qualquer mensagem (C4).
    ///
    /// Separado de [`ContatoRepository::salvar`], que é upsert: aquele existe
    /// para a ingestão, onde encontrar o contato de novo é o caso normal.
    /// Aqui, telefone repetido é um engano de quem digita — devolver em
    /// silêncio o contato de outra pessoa seria pior que recusar.
    async fn criar_manual(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        telefone: &str,
        nome_contato: Option<&str>,
        email: Option<&str>,
    ) -> Result<Contato, DbError>;

    /// Edita nome, e-mail e — sob condição — telefone.
    ///
    /// Devolve `Ok(false)` quando o id não existe no tenant.
    async fn atualizar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
        edicao: EdicaoContato,
    ) -> Result<bool, DbError>;

    /// Some da lista sem perder o histórico: as conversas continuam
    /// referenciando o contato, e apagar de verdade as deixaria órfãs.
    async fn desativar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
        ativo: bool,
    ) -> Result<bool, DbError>;

    /// Quantos atendimentos o contato já teve.
    ///
    /// É o que decide se o telefone ainda pode mudar: um contato que já
    /// conversou tem histórico amarrado àquele número, e trocá-lo passaria as
    /// mensagens de uma pessoa para outra.
    async fn contar_atendimentos(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        contato_id: i32,
    ) -> Result<i64, DbError>;

    async fn buscar_por_telefone(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        telefone: &str,
    ) -> Result<Option<Contato>, DbError>;

    /// Lista os contatos do tenant, mais recentes primeiro pela última
    /// interação — quem falou agora é quem se procura.
    ///
    /// `busca` casa contra nome, telefone e nome do perfil do WhatsApp: são as
    /// três formas de lembrar de alguém, e obrigar a escolher qual campo
    /// pesquisar seria pedir que a pessoa adivinhe como o contato foi salvo.
    /// `limite` existe porque a lista cresce sem teto com o uso.
    async fn listar_por_tenant(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        busca: Option<&str>,
        limite: i64,
    ) -> Result<Vec<Contato>, DbError>;

    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<Contato>, DbError>;

    async fn listar_recentes(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        limit: i64,
    ) -> Result<Vec<Contato>, DbError>;

    async fn atualizar_ultima_interacao(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        contato_id: i32,
    ) -> Result<(), DbError>;
}

pub struct PostgresContatoRepository;

#[async_trait]
impl ContatoRepository for PostgresContatoRepository {
    // `telefone`/`nome_contato` são PII: `skip_all` mantém-nos fora do span.
    #[tracing::instrument(skip_all)]
    async fn salvar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        telefone: &str,
        nome_contato: Option<&str>,
    ) -> Result<Contato, DbError> {
        ctx.exigir_qualquer(&["clientes:write", "tenant:admin"])?;
        // ON CONFLICT atualiza apenas nome_contato e ultima_interacao
        let row = sqlx::query_as!(
            Contato,
            r#"INSERT INTO oraculo_contato (tenant_id, telefone, nome_contato)
               VALUES ($1, $2, $3)
               ON CONFLICT (tenant_id, telefone) DO UPDATE
                   SET nome_contato = COALESCE(EXCLUDED.nome_contato, oraculo_contato.nome_contato),
                       ultima_interacao = NOW()
               RETURNING id, tenant_id, telefone, nome_contato, slug, email,
                         nome_perfil_whatsapp, data_cadastro, ultima_interacao,
                         ativo, metadados, foto_perfil, foto_perfil_url_origem"#,
            ctx.tenant_id,
            telefone,
            nome_contato
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }

    // PII de novo: nada de telefone/nome/e-mail no span.
    #[tracing::instrument(skip_all)]
    async fn criar_manual(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        telefone: &str,
        nome_contato: Option<&str>,
        email: Option<&str>,
    ) -> Result<Contato, DbError> {
        ctx.exigir_qualquer(&["clientes:write", "tenant:admin"])?;
        // Sem ON CONFLICT: o unique (tenant_id, telefone) vira
        // `DbError::UniqueViolation`, e é essa a resposta certa — quem digitou
        // um número que já existe precisa saber disso, não receber a ficha
        // alheia como se tivesse acabado de criá-la.
        let row = sqlx::query_as!(
            Contato,
            r#"INSERT INTO oraculo_contato (tenant_id, telefone, nome_contato, email)
               VALUES ($1, $2, $3, $4)
               RETURNING id, tenant_id, telefone, nome_contato, slug, email,
                         nome_perfil_whatsapp, data_cadastro, ultima_interacao,
                         ativo, metadados, foto_perfil, foto_perfil_url_origem"#,
            ctx.tenant_id,
            telefone,
            nome_contato,
            email
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(id = id))]
    async fn atualizar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
        edicao: EdicaoContato,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["clientes:write", "tenant:admin"])?;
        // `COALESCE($n, coluna)` faz o `None` significar "não mexe" num
        // statement só. A alternativa seria montar o UPDATE por concatenação,
        // que é exatamente o que `query_as!` existe para evitar.
        let afetadas = sqlx::query!(
            r#"UPDATE oraculo_contato
                  SET nome_contato = COALESCE($3::text, nome_contato),
                      email        = COALESCE($4::text, email),
                      telefone     = COALESCE($5::text, telefone)
                WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            id,
            edicao.nome_contato,
            edicao.email,
            edicao.telefone
        )
        .execute(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?
        .rows_affected();
        Ok(afetadas > 0)
    }

    #[tracing::instrument(skip_all, fields(id = id, ativo = ativo))]
    async fn desativar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
        ativo: bool,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["clientes:write", "tenant:admin"])?;
        let afetadas = sqlx::query!(
            "UPDATE oraculo_contato SET ativo = $3 WHERE tenant_id = $1 AND id = $2",
            ctx.tenant_id,
            id,
            ativo
        )
        .execute(&mut **tx)
        .await?
        .rows_affected();
        Ok(afetadas > 0)
    }

    #[tracing::instrument(skip_all, fields(contato_id = contato_id))]
    async fn contar_atendimentos(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        contato_id: i32,
    ) -> Result<i64, DbError> {
        let total = sqlx::query_scalar!(
            "SELECT COUNT(*) FROM oraculo_atendimento WHERE tenant_id = $1 AND contato_id = $2",
            ctx.tenant_id,
            contato_id
        )
        .fetch_one(&mut **tx)
        .await?;
        Ok(total.unwrap_or(0))
    }

    #[tracing::instrument(skip_all)]
    async fn buscar_por_telefone(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        telefone: &str,
    ) -> Result<Option<Contato>, DbError> {
        let row = sqlx::query_as!(
            Contato,
            r#"SELECT id, tenant_id, telefone, nome_contato, slug, email,
                      nome_perfil_whatsapp, data_cadastro, ultima_interacao,
                      ativo, metadados, foto_perfil, foto_perfil_url_origem
               FROM oraculo_contato
               WHERE tenant_id = $1 AND telefone = $2"#,
            ctx.tenant_id,
            telefone
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(id = id))]
    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<Contato>, DbError> {
        let row = sqlx::query_as!(
            Contato,
            r#"SELECT id, tenant_id, telefone, nome_contato, slug, email,
                      nome_perfil_whatsapp, data_cadastro, ultima_interacao,
                      ativo, metadados, foto_perfil, foto_perfil_url_origem
               FROM oraculo_contato
               WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            id
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(limit = limit))]
    async fn listar_recentes(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        limit: i64,
    ) -> Result<Vec<Contato>, DbError> {
        ctx.exigir_qualquer(&["clientes:read", "tenant:admin"])?;
        let rows = sqlx::query_as!(
            Contato,
            r#"SELECT id, tenant_id, telefone, nome_contato, slug, email,
                      nome_perfil_whatsapp, data_cadastro, ultima_interacao,
                      ativo, metadados, foto_perfil, foto_perfil_url_origem
               FROM oraculo_contato
               WHERE tenant_id = $1 AND ativo = true
               ORDER BY ultima_interacao DESC
               LIMIT $2"#,
            ctx.tenant_id,
            limit
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

    #[tracing::instrument(skip_all, fields(contato_id = contato_id))]
    async fn atualizar_ultima_interacao(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        contato_id: i32,
    ) -> Result<(), DbError> {
        sqlx::query!(
            "UPDATE oraculo_contato SET ultima_interacao = NOW()
             WHERE tenant_id = $1 AND id = $2",
            ctx.tenant_id,
            contato_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all)]
    async fn listar_por_tenant(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        busca: Option<&str>,
        limite: i64,
    ) -> Result<Vec<Contato>, DbError> {
        ctx.exigir_qualquer(&["clientes:read", "atendimentos:read", "tenant:admin"])?;
        // `$2 IS NULL` no mesmo statement em vez de dois SQLs: a diferença é um
        // filtro, não uma consulta diferente.
        let rows = sqlx::query_as!(
            Contato,
            r#"SELECT id, tenant_id, telefone, nome_contato, slug, email,
                      nome_perfil_whatsapp, data_cadastro, ultima_interacao,
                      ativo, metadados, foto_perfil, foto_perfil_url_origem
               FROM oraculo_contato
               WHERE tenant_id = $1
                 AND ($2::text IS NULL
                      OR nome_contato ILIKE '%' || $2 || '%'
                      OR telefone ILIKE '%' || $2 || '%'
                      OR nome_perfil_whatsapp ILIKE '%' || $2 || '%')
               ORDER BY ultima_interacao DESC
               LIMIT $3"#,
            ctx.tenant_id,
            busca,
            limite
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }
}

/// P8 — nome de perfil e foto vindos do evento `CONTACTS` do provedor.
///
/// **Só atualiza quem já existe.** O evento pode trazer a agenda inteira do
/// aparelho, e criar contato a partir dele encheria a base de gente que nunca
/// escreveu para o tenant — com todo o custo de LGPD que isso implica.
///
/// Campo vazio não apaga o que está gravado: o provedor manda o que tem, e uma
/// atualização parcial não pode zerar o nome que alguém digitou à mão.
///
/// `false` no retorno = ninguém com esse telefone no tenant, que é o caso comum
/// e não é erro.
#[tracing::instrument(skip_all)]
pub async fn atualizar_perfil_whatsapp(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    telefone: &str,
    nome_perfil: Option<&str>,
    foto_url: Option<&str>,
) -> Result<bool, DbError> {
    let r = sqlx::query(
        r#"UPDATE oraculo_contato
              SET nome_perfil_whatsapp = COALESCE(NULLIF($3, ''), nome_perfil_whatsapp),
                  foto_perfil_url_origem = COALESCE(NULLIF($4, ''), foto_perfil_url_origem)
            WHERE tenant_id = $1 AND telefone = $2"#,
    )
    .bind(ctx.tenant_id)
    .bind(telefone)
    .bind(nome_perfil.unwrap_or_default())
    .bind(foto_url.unwrap_or_default())
    .execute(&mut **tx)
    .await?;
    Ok(r.rows_affected() > 0)
}
