use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct Cliente {
    pub id: i32,
    pub tenant_id: Uuid,
    pub nome_fantasia: String,
    pub slug: String,
    pub razao_social: Option<String>,
    pub tipo: Option<String>,
    pub cnpj: Option<String>,
    pub cpf: Option<String>,
    pub telefone: Option<String>,
    pub site: Option<String>,
    pub ramo_atividade: Option<String>,
    pub observacoes: Option<String>,
    pub cep: Option<String>,
    pub logradouro: Option<String>,
    pub numero: Option<String>,
    pub complemento: Option<String>,
    pub bairro: Option<String>,
    pub cidade: Option<String>,
    pub uf: Option<String>,
    pub pais: Option<String>,
    pub data_cadastro: DateTime<Utc>,
    pub ultima_atualizacao: DateTime<Utc>,
    pub ativo: bool,
    pub metadados: serde_json::Value,
}

#[async_trait]
pub trait ClienteRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        nome_fantasia: &str,
        tipo: Option<&str>,
        cnpj: Option<&str>,
        cpf: Option<&str>,
    ) -> Result<Cliente, DbError>;

    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<Cliente>, DbError>;

    async fn adicionar_contato(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        cliente_id: i32,
        contato_id: i32,
    ) -> Result<(), DbError>;

    async fn remover_contato(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        cliente_id: i32,
        contato_id: i32,
    ) -> Result<(), DbError>;

    async fn listar_ativos(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<Cliente>, DbError>;
}

pub struct PostgresClienteRepository;

#[async_trait]
impl ClienteRepository for PostgresClienteRepository {
    #[tracing::instrument(skip_all)]
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        nome_fantasia: &str,
        tipo: Option<&str>,
        cnpj: Option<&str>,
        cpf: Option<&str>,
    ) -> Result<Cliente, DbError> {
        ctx.exigir_qualquer(&["clientes:write", "tenant:admin"])?;
        let row = sqlx::query_as!(
            Cliente,
            r#"INSERT INTO oraculo_cliente (tenant_id, nome_fantasia, tipo, cnpj, cpf)
               VALUES ($1, $2, $3, $4, $5)
               RETURNING id, tenant_id, nome_fantasia, slug, razao_social, tipo,
                         cnpj, cpf, telefone, site, ramo_atividade, observacoes,
                         cep, logradouro, numero, complemento, bairro, cidade, uf, pais,
                         data_cadastro, ultima_atualizacao, ativo, metadados"#,
            ctx.tenant_id,
            nome_fantasia,
            tipo,
            cnpj,
            cpf
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(id = id))]
    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<Cliente>, DbError> {
        let row = sqlx::query_as!(
            Cliente,
            r#"SELECT id, tenant_id, nome_fantasia, slug, razao_social, tipo,
                      cnpj, cpf, telefone, site, ramo_atividade, observacoes,
                      cep, logradouro, numero, complemento, bairro, cidade, uf, pais,
                      data_cadastro, ultima_atualizacao, ativo, metadados
               FROM oraculo_cliente
               WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            id
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(cliente_id = cliente_id, contato_id = contato_id))]
    async fn adicionar_contato(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        cliente_id: i32,
        contato_id: i32,
    ) -> Result<(), DbError> {
        ctx.exigir_qualquer(&["clientes:write", "tenant:admin"])?;
        sqlx::query!(
            r#"INSERT INTO oraculo_cliente_contatos (tenant_id, cliente_id, contato_id)
               VALUES ($1, $2, $3) ON CONFLICT DO NOTHING"#,
            ctx.tenant_id,
            cliente_id,
            contato_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(cliente_id = cliente_id, contato_id = contato_id))]
    async fn remover_contato(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        cliente_id: i32,
        contato_id: i32,
    ) -> Result<(), DbError> {
        ctx.exigir_qualquer(&["clientes:write", "tenant:admin"])?;
        sqlx::query!(
            "DELETE FROM oraculo_cliente_contatos
             WHERE tenant_id = $1 AND cliente_id = $2 AND contato_id = $3",
            ctx.tenant_id,
            cliente_id,
            contato_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(limit = limit, offset = offset))]
    async fn listar_ativos(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<Cliente>, DbError> {
        ctx.exigir_qualquer(&["clientes:read", "tenant:admin"])?;
        let rows = sqlx::query_as!(
            Cliente,
            r#"SELECT id, tenant_id, nome_fantasia, slug, razao_social, tipo,
                      cnpj, cpf, telefone, site, ramo_atividade, observacoes,
                      cep, logradouro, numero, complemento, bairro, cidade, uf, pais,
                      data_cadastro, ultima_atualizacao, ativo, metadados
               FROM oraculo_cliente
               WHERE tenant_id = $1 AND ativo = true
               ORDER BY nome_fantasia
               LIMIT $2 OFFSET $3"#,
            ctx.tenant_id,
            limit,
            offset
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }
}

// ---------------------------------------------------------------------------
// B10 (N11 E5) — clientes (PJ/PF) na tela, e o vínculo com os contatos.
//
// Consultas sem macro, para não depender do cache offline do sqlx.
// ---------------------------------------------------------------------------

/// Os campos editáveis de um cliente. `None` = vazio.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct DadosCliente {
    pub nome_fantasia: String,
    pub razao_social: Option<String>,
    /// `pj` | `pf`.
    pub tipo: Option<String>,
    /// Só dígitos.
    pub cnpj: Option<String>,
    /// Só dígitos.
    pub cpf: Option<String>,
    pub telefone: Option<String>,
    pub site: Option<String>,
    pub ramo_atividade: Option<String>,
    pub observacoes: Option<String>,
    pub cep: Option<String>,
    pub logradouro: Option<String>,
    pub numero: Option<String>,
    pub complemento: Option<String>,
    pub bairro: Option<String>,
    pub cidade: Option<String>,
    pub uf: Option<String>,
}

/// Um cliente como a tela o mostra: textos vazios em vez de nulos, e quantos
/// contatos estão ligados a ele.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct ClienteResumo {
    pub id: i32,
    pub nome_fantasia: String,
    pub razao_social: String,
    pub tipo: String,
    pub cnpj: String,
    pub cpf: String,
    pub telefone: String,
    pub site: String,
    pub ramo_atividade: String,
    pub observacoes: String,
    pub cep: String,
    pub logradouro: String,
    pub numero: String,
    pub complemento: String,
    pub bairro: String,
    pub cidade: String,
    pub uf: String,
    pub ativo: bool,
    pub contatos: i64,
}

/// Um contato ligado a um cliente.
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct ContatoVinculado {
    pub id: i32,
    pub nome: String,
    pub telefone: String,
}

// Duas consultas inteiras em vez de uma lista de colunas interpolada: o sqlx
// recusa SQL montado em tempo de execução sem auditoria, e aqui não há nada
// dinâmico além dos parâmetros.
const SQL_LISTAR_CLIENTES: &str = r#"SELECT c.id, c.nome_fantasia,
    COALESCE(c.razao_social, '') AS razao_social, COALESCE(c.tipo, '') AS tipo,
    COALESCE(c.cnpj, '') AS cnpj, COALESCE(c.cpf, '') AS cpf,
    COALESCE(c.telefone, '') AS telefone, COALESCE(c.site, '') AS site,
    COALESCE(c.ramo_atividade, '') AS ramo_atividade,
    COALESCE(c.observacoes, '') AS observacoes, COALESCE(c.cep, '') AS cep,
    COALESCE(c.logradouro, '') AS logradouro, COALESCE(c.numero, '') AS numero,
    COALESCE(c.complemento, '') AS complemento, COALESCE(c.bairro, '') AS bairro,
    COALESCE(c.cidade, '') AS cidade, COALESCE(c.uf, '') AS uf, c.ativo,
    (SELECT COUNT(*) FROM oraculo_cliente_contatos cc
      WHERE cc.tenant_id = c.tenant_id AND cc.cliente_id = c.id) AS contatos
           FROM oraculo_cliente c
           WHERE c.tenant_id = $1 AND ($2 OR c.ativo)
             AND ($3 = '' OR c.nome_fantasia ILIKE '%' || $3 || '%'
                  OR COALESCE(c.razao_social, '') ILIKE '%' || $3 || '%'
                  OR COALESCE(c.cnpj, '') LIKE '%' || $3 || '%'
                  OR COALESCE(c.cpf, '') LIKE '%' || $3 || '%')
           ORDER BY c.ativo DESC, c.nome_fantasia
           LIMIT $4"#;

const SQL_BUSCAR_CLIENTE: &str = r#"SELECT c.id, c.nome_fantasia,
    COALESCE(c.razao_social, '') AS razao_social, COALESCE(c.tipo, '') AS tipo,
    COALESCE(c.cnpj, '') AS cnpj, COALESCE(c.cpf, '') AS cpf,
    COALESCE(c.telefone, '') AS telefone, COALESCE(c.site, '') AS site,
    COALESCE(c.ramo_atividade, '') AS ramo_atividade,
    COALESCE(c.observacoes, '') AS observacoes, COALESCE(c.cep, '') AS cep,
    COALESCE(c.logradouro, '') AS logradouro, COALESCE(c.numero, '') AS numero,
    COALESCE(c.complemento, '') AS complemento, COALESCE(c.bairro, '') AS bairro,
    COALESCE(c.cidade, '') AS cidade, COALESCE(c.uf, '') AS uf, c.ativo,
    (SELECT COUNT(*) FROM oraculo_cliente_contatos cc
      WHERE cc.tenant_id = c.tenant_id AND cc.cliente_id = c.id) AS contatos
           FROM oraculo_cliente c
           WHERE c.tenant_id = $1 AND c.id = $2"#;

fn cliente_da_linha(row: &sqlx::postgres::PgRow) -> Result<ClienteResumo, DbError> {
    use sqlx::Row;
    Ok(ClienteResumo {
        id: row.try_get("id")?,
        nome_fantasia: row.try_get("nome_fantasia")?,
        razao_social: row.try_get("razao_social")?,
        tipo: row.try_get("tipo")?,
        cnpj: row.try_get("cnpj")?,
        cpf: row.try_get("cpf")?,
        telefone: row.try_get("telefone")?,
        site: row.try_get("site")?,
        ramo_atividade: row.try_get("ramo_atividade")?,
        observacoes: row.try_get("observacoes")?,
        cep: row.try_get("cep")?,
        logradouro: row.try_get("logradouro")?,
        numero: row.try_get("numero")?,
        complemento: row.try_get("complemento")?,
        bairro: row.try_get("bairro")?,
        cidade: row.try_get("cidade")?,
        uf: row.try_get("uf")?,
        ativo: row.try_get("ativo")?,
        contatos: row.try_get("contatos")?,
    })
}

/// Clientes do tenant, ativos primeiro. `busca` casa nome fantasia, razão social
/// e documento; vazia = sem filtro.
pub async fn listar_clientes(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    busca: &str,
    incluir_inativos: bool,
    limite: i64,
) -> Result<Vec<ClienteResumo>, DbError> {
    ctx.exigir_qualquer(&["clientes:read", "tenant:admin"])?;
    let linhas = sqlx::query(SQL_LISTAR_CLIENTES)
        .bind(ctx.tenant_id)
        .bind(incluir_inativos)
        .bind(busca)
        .bind(limite)
        .fetch_all(&mut **tx)
        .await?;
    linhas.iter().map(cliente_da_linha).collect()
}

pub async fn buscar_cliente(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    id: i32,
) -> Result<Option<ClienteResumo>, DbError> {
    ctx.exigir_qualquer(&["clientes:read", "tenant:admin"])?;
    let linha = sqlx::query(SQL_BUSCAR_CLIENTE)
        .bind(ctx.tenant_id)
        .bind(id)
        .fetch_optional(&mut **tx)
        .await?;
    linha.as_ref().map(cliente_da_linha).transpose()
}

pub async fn criar_cliente(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    d: &DadosCliente,
) -> Result<i32, DbError> {
    ctx.exigir_qualquer(&["clientes:write", "tenant:admin"])?;
    let (id,): (i32,) = sqlx::query_as(
        r#"INSERT INTO oraculo_cliente
             (tenant_id, nome_fantasia, razao_social, tipo, cnpj, cpf, telefone,
              site, ramo_atividade, observacoes, cep, logradouro, numero,
              complemento, bairro, cidade, uf)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14,
                   $15, $16, $17)
           RETURNING id"#,
    )
    .bind(ctx.tenant_id)
    .bind(&d.nome_fantasia)
    .bind(&d.razao_social)
    .bind(&d.tipo)
    .bind(&d.cnpj)
    .bind(&d.cpf)
    .bind(&d.telefone)
    .bind(&d.site)
    .bind(&d.ramo_atividade)
    .bind(&d.observacoes)
    .bind(&d.cep)
    .bind(&d.logradouro)
    .bind(&d.numero)
    .bind(&d.complemento)
    .bind(&d.bairro)
    .bind(&d.cidade)
    .bind(&d.uf)
    .fetch_one(&mut **tx)
    .await?;
    Ok(id)
}

/// Quais campos a edição muda — é o que vai para a auditoria, nunca o valor.
pub fn campos_alterados(antes: &ClienteResumo, depois: &DadosCliente) -> Vec<&'static str> {
    let texto = |v: &Option<String>| v.clone().unwrap_or_default();
    let pares: [(&'static str, &str, String); 16] = [
        (
            "nome_fantasia",
            &antes.nome_fantasia,
            depois.nome_fantasia.clone(),
        ),
        (
            "razao_social",
            &antes.razao_social,
            texto(&depois.razao_social),
        ),
        ("tipo", &antes.tipo, texto(&depois.tipo)),
        ("cnpj", &antes.cnpj, texto(&depois.cnpj)),
        ("cpf", &antes.cpf, texto(&depois.cpf)),
        ("telefone", &antes.telefone, texto(&depois.telefone)),
        ("site", &antes.site, texto(&depois.site)),
        (
            "ramo_atividade",
            &antes.ramo_atividade,
            texto(&depois.ramo_atividade),
        ),
        (
            "observacoes",
            &antes.observacoes,
            texto(&depois.observacoes),
        ),
        ("cep", &antes.cep, texto(&depois.cep)),
        ("logradouro", &antes.logradouro, texto(&depois.logradouro)),
        ("numero", &antes.numero, texto(&depois.numero)),
        (
            "complemento",
            &antes.complemento,
            texto(&depois.complemento),
        ),
        ("bairro", &antes.bairro, texto(&depois.bairro)),
        ("cidade", &antes.cidade, texto(&depois.cidade)),
        ("uf", &antes.uf, texto(&depois.uf)),
    ];
    pares
        .into_iter()
        .filter(|(_, a, d)| *a != d.as_str())
        .map(|(campo, _, _)| campo)
        .collect()
}

pub async fn atualizar_cliente(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    id: i32,
    d: &DadosCliente,
) -> Result<bool, DbError> {
    ctx.exigir_qualquer(&["clientes:write", "tenant:admin"])?;
    let res = sqlx::query(
        r#"UPDATE oraculo_cliente
           SET nome_fantasia = $3, razao_social = $4, tipo = $5, cnpj = $6,
               cpf = $7, telefone = $8, site = $9, ramo_atividade = $10,
               observacoes = $11, cep = $12, logradouro = $13, numero = $14,
               complemento = $15, bairro = $16, cidade = $17, uf = $18,
               ultima_atualizacao = NOW()
           WHERE tenant_id = $1 AND id = $2"#,
    )
    .bind(ctx.tenant_id)
    .bind(id)
    .bind(&d.nome_fantasia)
    .bind(&d.razao_social)
    .bind(&d.tipo)
    .bind(&d.cnpj)
    .bind(&d.cpf)
    .bind(&d.telefone)
    .bind(&d.site)
    .bind(&d.ramo_atividade)
    .bind(&d.observacoes)
    .bind(&d.cep)
    .bind(&d.logradouro)
    .bind(&d.numero)
    .bind(&d.complemento)
    .bind(&d.bairro)
    .bind(&d.cidade)
    .bind(&d.uf)
    .execute(&mut **tx)
    .await?;
    Ok(res.rows_affected() > 0)
}

/// Tira (ou devolve) o cliente da lista. Os vínculos com contatos ficam.
pub async fn definir_cliente_ativo(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    id: i32,
    ativo: bool,
) -> Result<bool, DbError> {
    ctx.exigir_qualquer(&["clientes:write", "tenant:admin"])?;
    let res = sqlx::query(
        "UPDATE oraculo_cliente SET ativo = $3, ultima_atualizacao = NOW() \
         WHERE tenant_id = $1 AND id = $2",
    )
    .bind(ctx.tenant_id)
    .bind(id)
    .bind(ativo)
    .execute(&mut **tx)
    .await?;
    Ok(res.rows_affected() > 0)
}

pub async fn contatos_do_cliente(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    cliente_id: i32,
) -> Result<Vec<ContatoVinculado>, DbError> {
    ctx.exigir_qualquer(&["clientes:read", "tenant:admin"])?;
    let linhas: Vec<(i32, String, String)> = sqlx::query_as(
        r#"SELECT o.id,
                  COALESCE(NULLIF(o.nome_contato, ''), NULLIF(o.nome_perfil_whatsapp, ''), ''),
                  COALESCE(o.telefone, '')
           FROM oraculo_cliente_contatos cc
           JOIN oraculo_contato o ON o.id = cc.contato_id AND o.tenant_id = cc.tenant_id
           WHERE cc.tenant_id = $1 AND cc.cliente_id = $2
           ORDER BY 2, o.id"#,
    )
    .bind(ctx.tenant_id)
    .bind(cliente_id)
    .fetch_all(&mut **tx)
    .await?;
    Ok(linhas
        .into_iter()
        .map(|(id, nome, telefone)| ContatoVinculado { id, nome, telefone })
        .collect())
}

/// Liga ou desliga um contato de um cliente. `false` quando um dos dois não é
/// deste tenant.
///
/// A conferência é explícita: a chave estrangeira aceita um id de contato de
/// outro tenant (a RLS não vale para a checagem de FK), e sem ela dava para ligar
/// o cliente a um contato alheio.
pub async fn vincular_contato(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    cliente_id: i32,
    contato_id: i32,
    vincular: bool,
) -> Result<bool, DbError> {
    ctx.exigir_qualquer(&["clientes:write", "tenant:admin"])?;
    let (existem,): (bool,) = sqlx::query_as(
        r#"SELECT EXISTS (SELECT 1 FROM oraculo_cliente WHERE tenant_id = $1 AND id = $2)
              AND EXISTS (SELECT 1 FROM oraculo_contato WHERE tenant_id = $1 AND id = $3)"#,
    )
    .bind(ctx.tenant_id)
    .bind(cliente_id)
    .bind(contato_id)
    .fetch_one(&mut **tx)
    .await?;
    if !existem {
        return Ok(false);
    }
    let sql = if vincular {
        "INSERT INTO oraculo_cliente_contatos (tenant_id, cliente_id, contato_id) \
         VALUES ($1, $2, $3) ON CONFLICT DO NOTHING"
    } else {
        "DELETE FROM oraculo_cliente_contatos \
         WHERE tenant_id = $1 AND cliente_id = $2 AND contato_id = $3"
    };
    sqlx::query(sql)
        .bind(ctx.tenant_id)
        .bind(cliente_id)
        .bind(contato_id)
        .execute(&mut **tx)
        .await?;
    Ok(true)
}

#[cfg(test)]
mod tests_campos_alterados {
    use super::*;

    #[test]
    fn so_lista_o_que_mudou() {
        let antes = ClienteResumo {
            nome_fantasia: "Padaria Sol".into(),
            cnpj: "12345678000190".into(),
            cidade: "Recife".into(),
            ..Default::default()
        };
        let depois = DadosCliente {
            nome_fantasia: "Padaria Sol".into(),
            cnpj: Some("12345678000190".into()),
            cidade: Some("Olinda".into()),
            uf: Some("PE".into()),
            ..Default::default()
        };
        assert_eq!(campos_alterados(&antes, &depois), vec!["cidade", "uf"]);
    }
}
