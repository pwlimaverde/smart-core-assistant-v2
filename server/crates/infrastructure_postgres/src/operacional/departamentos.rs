use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct Departamento {
    pub id: i32,
    pub tenant_id: Uuid,
    pub nome: String,
    pub slug: String,
    pub descricao: Option<String>,
    pub ativo: bool,
    pub telefone_instancia: Option<String>,
    pub api_key: Option<String>,
    pub configuracoes: serde_json::Value,
    pub metadados: serde_json::Value,
    pub data_criacao: DateTime<Utc>,
}

#[async_trait]
pub trait DepartamentoRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        nome: &str,
        descricao: Option<&str>,
    ) -> Result<Departamento, DbError>;

    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<Departamento>, DbError>;

    async fn listar_ativos(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<Departamento>, DbError>;

    /// Renomeia e reescreve a descrição.
    ///
    /// O `slug` NÃO muda: ele é referência estável, e há registros que apontam
    /// para o departamento por ele.
    async fn atualizar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
        nome: &str,
        descricao: Option<&str>,
        ativo: bool,
    ) -> Result<bool, DbError>;

    /// Desativa em vez de apagar.
    ///
    /// Atendimentos e atendentes apontam para o departamento; remover a linha
    /// levaria histórico junto. Inativo some das listas de trabalho e continua
    /// respondendo pelo que já passou por ele.
    async fn desativar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<bool, DbError>;

    /// Valida as credenciais recebidas do webhook da Evolution API.
    async fn buscar_por_api_key(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        api_key: &str,
    ) -> Result<Option<Departamento>, DbError>;
}

/// Slug a partir do nome: minúsculas, sem acento, separado por hífen.
///
/// Existe porque a coluna `slug` é `NOT NULL DEFAULT ''` e ninguém a preenchia —
/// todo departamento nascia com slug vazio. Com `UNIQUE (tenant_id, slug)`, o
/// primeiro entrava e **o segundo sempre colidia**: um tenant só conseguia ter
/// um departamento, e o erro que chegava à tela era "erro ao acessar o banco de
/// dados", que não diz nada a quem está cadastrando.
///
/// Acento vira a letra base (`Ações` → `acoes`) para o slug não depender de
/// codificação. O que sobra fora de `[a-z0-9-]` vira hífen, e hífens repetidos
/// ou nas pontas são removidos.
fn slug_do_nome(nome: &str) -> String {
    const COM_ACENTO: &str = "áàâãäéèêëíìîïóòôõöúùûüçñ";
    const SEM_ACENTO: [&str; 24] = [
        "a", "a", "a", "a", "a", "e", "e", "e", "e", "i", "i", "i", "i", "o", "o", "o", "o", "o",
        "u", "u", "u", "u", "c", "n",
    ];

    let mut saida = String::with_capacity(nome.len());
    for c in nome.to_lowercase().chars() {
        if let Some(pos) = COM_ACENTO.chars().position(|a| a == c) {
            saida.push_str(SEM_ACENTO[pos]);
        } else if c.is_ascii_alphanumeric() {
            saida.push(c);
        } else if !saida.ends_with('-') {
            saida.push('-');
        }
    }

    let slug = saida.trim_matches('-').to_string();
    // Nome só de símbolos ("!!!") esvaziaria o slug e recriaria a colisão que
    // esta função veio resolver. O banco decide o id; aqui basta não colidir.
    if slug.is_empty() {
        "departamento".to_string()
    } else {
        slug
    }
}

pub struct PostgresDepartamentoRepository;

#[async_trait]
impl DepartamentoRepository for PostgresDepartamentoRepository {
    #[tracing::instrument(skip_all, fields(nome = %nome))]
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        nome: &str,
        descricao: Option<&str>,
    ) -> Result<Departamento, DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin"])?;
        let slug = slug_do_nome(nome);
        let row = sqlx::query_as!(
            Departamento,
            r#"INSERT INTO oraculo_departamento (tenant_id, nome, descricao, slug)
               VALUES ($1, $2, $3, $4)
               RETURNING id, tenant_id, nome, slug, descricao, ativo,
                         telefone_instancia, api_key, configuracoes, metadados, data_criacao"#,
            ctx.tenant_id,
            nome,
            descricao,
            slug
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
    ) -> Result<Option<Departamento>, DbError> {
        let row = sqlx::query_as!(
            Departamento,
            r#"SELECT id, tenant_id, nome, slug, descricao, ativo,
                      telefone_instancia, api_key, configuracoes, metadados, data_criacao
               FROM oraculo_departamento
               WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            id
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all)]
    async fn listar_ativos(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<Departamento>, DbError> {
        ctx.exigir_qualquer(&["operacional:read", "tenant:admin"])?;
        let rows = sqlx::query_as!(
            Departamento,
            r#"SELECT id, tenant_id, nome, slug, descricao, ativo,
                      telefone_instancia, api_key, configuracoes, metadados, data_criacao
               FROM oraculo_departamento
               WHERE tenant_id = $1 AND ativo = true
               ORDER BY nome"#,
            ctx.tenant_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

    // `api_key` é credencial: `skip_all`.
    #[tracing::instrument(skip_all)]
    #[tracing::instrument(skip_all, fields(id = id))]
    async fn atualizar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
        nome: &str,
        descricao: Option<&str>,
        ativo: bool,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin"])?;
        let res = sqlx::query!(
            r#"UPDATE oraculo_departamento
                  SET nome = $1, descricao = $2, ativo = $3
                WHERE id = $4 AND tenant_id = $5"#,
            nome,
            descricao,
            ativo,
            id,
            ctx.tenant_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(res.rows_affected() > 0)
    }

    #[tracing::instrument(skip_all, fields(id = id))]
    async fn desativar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin"])?;
        let res = sqlx::query!(
            "UPDATE oraculo_departamento SET ativo = false WHERE id = $1 AND tenant_id = $2",
            id,
            ctx.tenant_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(res.rows_affected() > 0)
    }

    async fn buscar_por_api_key(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        api_key: &str,
    ) -> Result<Option<Departamento>, DbError> {
        let row = sqlx::query_as!(
            Departamento,
            r#"SELECT id, tenant_id, nome, slug, descricao, ativo,
                      telefone_instancia, api_key, configuracoes, metadados, data_criacao
               FROM oraculo_departamento
               WHERE tenant_id = $1 AND api_key = $2"#,
            ctx.tenant_id,
            api_key
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }
}

#[cfg(test)]
mod tests {
    use super::slug_do_nome;

    // O slug vazio era o defeito: com `NOT NULL DEFAULT ''` e
    // `UNIQUE (tenant_id, slug)`, o primeiro departamento entrava e o SEGUNDO
    // colidia — um tenant só conseguia ter um. Estes testes fixam que nomes
    // diferentes geram slugs diferentes, que é o que destrava o cadastro.

    #[test]
    fn nomes_diferentes_geram_slugs_diferentes() {
        assert_ne!(slug_do_nome("Vendas"), slug_do_nome("Suporte"));
        assert_eq!(slug_do_nome("Vendas"), "vendas");
        assert_eq!(slug_do_nome("Suporte Técnico"), "suporte-tecnico");
    }

    #[test]
    fn acento_vira_letra_base() {
        // O slug não pode depender de codificação: "Ações" e "Acoes" viram o
        // mesmo identificador estável.
        assert_eq!(slug_do_nome("Ações"), "acoes");
        assert_eq!(slug_do_nome("Manutenção"), "manutencao");
        assert_eq!(slug_do_nome("Pós-Venda"), "pos-venda");
    }

    #[test]
    fn simbolos_e_espacos_nao_deixam_hifen_solto() {
        assert_eq!(slug_do_nome("  Vendas   Online  "), "vendas-online");
        assert_eq!(slug_do_nome("Vendas / Trocas"), "vendas-trocas");
        assert_eq!(slug_do_nome("A&B"), "a-b");
    }

    #[test]
    fn nome_so_de_simbolos_nao_volta_a_colidir() {
        // Um slug vazio recriaria exatamente o bug que esta função corrige.
        assert_eq!(slug_do_nome("!!!"), "departamento");
        assert_eq!(slug_do_nome("---"), "departamento");
        assert!(!slug_do_nome("@#$").is_empty());
    }

    #[test]
    fn nomes_que_diferem_so_por_caixa_colidem_de_proposito() {
        // "Vendas" e "vendas" SÃO o mesmo departamento para quem usa. Colidir
        // aqui é o comportamento certo: o banco recusa e o handler responde
        // "já existe um departamento com esse nome", em vez de criar duplicata
        // que ninguém distingue na tela.
        assert_eq!(slug_do_nome("Vendas"), slug_do_nome("vendas"));
        assert_eq!(slug_do_nome("VENDAS"), slug_do_nome("Vendas"));
    }
}
