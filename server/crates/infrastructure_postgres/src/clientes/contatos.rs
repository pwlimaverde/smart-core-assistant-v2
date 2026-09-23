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

/// P15 — o que a análise encontrou e pode ir para o cadastro do contato.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct ValoresDoContato {
    pub nome: Option<String>,
    pub email: Option<String>,
    /// Os demais tipos (cidade, documento, empresa…), um valor por tipo.
    pub extras: serde_json::Map<String, serde_json::Value>,
}

/// Nome aceitável para o cadastro: 2 a 100 caracteres, sem dígito.
fn nome_valido(v: &str) -> bool {
    let n = v.chars().count();
    (2..=100).contains(&n) && !v.chars().any(|c| c.is_ascii_digit())
}

/// E-mail com a forma mínima de um e-mail: uma `@`, os dois lados preenchidos,
/// ponto no domínio, sem espaço, até 254 caracteres.
fn email_valido(v: &str) -> bool {
    if v.len() > 254 || v.contains(char::is_whitespace) {
        return false;
    }
    let mut partes = v.split('@');
    match (partes.next(), partes.next(), partes.next()) {
        (Some(local), Some(dominio), None) => {
            !local.is_empty()
                && dominio.contains('.')
                && !dominio.starts_with('.')
                && !dominio.ends_with('.')
        }
        _ => false,
    }
}

/// P15 — regra pura: das entidades da análise, o que pode entrar no cadastro.
///
/// Só confiança >= `piso`, um valor por tipo (o mais confiante), e nome e
/// e-mail só com formato válido. Os tipos que não são nome nem e-mail vão para
/// `extras` — o cadastro não tem coluna para eles, e o `metadados` guarda.
pub fn valores_para_o_contato(entidades: &[(String, String, f64)], piso: f64) -> ValoresDoContato {
    let mut melhor: std::collections::BTreeMap<String, (String, f64)> = Default::default();
    for (tipo, valor, confianca) in entidades {
        let valor = valor.trim();
        if *confianca < piso || valor.is_empty() {
            continue;
        }
        let tipo = match tipo.trim().to_lowercase().as_str() {
            "nome" | "name" | "pessoa" | "person" => "nome".to_string(),
            "email" | "e-mail" | "e_mail" => "email".to_string(),
            outro => outro.to_string(),
        };
        let entra = melhor.get(&tipo).is_none_or(|(_, c)| confianca > c);
        if entra {
            melhor.insert(tipo, (valor.to_string(), *confianca));
        }
    }

    let mut saida = ValoresDoContato::default();
    for (tipo, (valor, _)) in melhor {
        match tipo.as_str() {
            "nome" if nome_valido(&valor) => saida.nome = Some(valor),
            "email" if email_valido(&valor) => saida.email = Some(valor.to_lowercase()),
            "nome" | "email" => {}
            _ => {
                saida.extras.insert(tipo, serde_json::Value::String(valor));
            }
        }
    }
    saida
}

/// P15 — completa o cadastro do contato do atendimento, **só no que está vazio**.
///
/// O cliente que diz "meu nome é João" na conversa não pode renomear o cadastro
/// que o operador corrigiu ontem. Os extras entram em `metadados.entidades`
/// somando às chaves que já existem, nunca substituindo — o que já estava lá
/// ganha (`jsonb ||` dá precedência ao lado direito).
///
/// Devolve os NOMES dos campos preenchidos, nunca os valores.
#[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id))]
pub async fn enriquecer_contato_do_atendimento(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    atendimento_id: i32,
    valores: &ValoresDoContato,
) -> Result<(i32, Vec<String>), DbError> {
    ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
    let atual = sqlx::query_as::<_, (i32, Option<String>, Option<String>)>(
        r#"SELECT c.id, c.nome_contato, c.email
             FROM oraculo_atendimento a
             JOIN oraculo_contato c ON c.id = a.contato_id AND c.tenant_id = a.tenant_id
            WHERE a.tenant_id = $1 AND a.id = $2"#,
    )
    .bind(ctx.tenant_id)
    .bind(atendimento_id)
    .fetch_optional(&mut **tx)
    .await?;
    let Some((contato_id, nome_atual, email_atual)) = atual else {
        return Ok((0, Vec::new()));
    };
    let vazio = |v: &Option<String>| v.as_deref().map(str::trim).unwrap_or("").is_empty();

    let novo_nome = valores.nome.as_deref().filter(|_| vazio(&nome_atual));
    let novo_email = valores.email.as_deref().filter(|_| vazio(&email_atual));
    let extras = serde_json::Value::Object(valores.extras.clone());

    let mut campos = Vec::new();
    if novo_nome.is_some() {
        campos.push("nome_contato".to_string());
    }
    if novo_email.is_some() {
        campos.push("email".to_string());
    }
    if !valores.extras.is_empty() {
        campos.push("metadados.entidades".to_string());
    }
    if campos.is_empty() {
        return Ok((contato_id, campos));
    }

    sqlx::query(
        r#"UPDATE oraculo_contato
              SET nome_contato = COALESCE($3, nome_contato),
                  email = COALESCE($4, email),
                  metadados = jsonb_set(
                      COALESCE(metadados, '{}'::jsonb),
                      '{entidades}',
                      $5::jsonb || COALESCE(metadados->'entidades', '{}'::jsonb)
                  )
            WHERE tenant_id = $1 AND id = $2"#,
    )
    .bind(ctx.tenant_id)
    .bind(contato_id)
    .bind(novo_nome)
    .bind(novo_email)
    .bind(extras)
    .execute(&mut **tx)
    .await
    .map_err(DbError::from_sqlx_unique)?;
    Ok((contato_id, campos))
}

/// P15 — o que a IA já guardou do contato, para a ficha mostrar.
#[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id))]
pub async fn entidades_do_contato(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    atendimento_id: i32,
) -> Result<serde_json::Value, DbError> {
    let row = sqlx::query_as::<_, (Option<serde_json::Value>,)>(
        r#"SELECT c.metadados->'entidades'
             FROM oraculo_atendimento a
             JOIN oraculo_contato c ON c.id = a.contato_id AND c.tenant_id = a.tenant_id
            WHERE a.tenant_id = $1 AND a.id = $2"#,
    )
    .bind(ctx.tenant_id)
    .bind(atendimento_id)
    .fetch_optional(&mut **tx)
    .await?;
    Ok(row
        .and_then(|(v,)| v)
        .filter(|v| v.is_object())
        .unwrap_or_else(|| serde_json::json!({})))
}

#[cfg(test)]
mod testes_p15 {
    use super::*;

    fn e(tipo: &str, valor: &str, c: f64) -> (String, String, f64) {
        (tipo.into(), valor.into(), c)
    }

    #[test]
    fn nome_e_email_validos_entram() {
        let v = valores_para_o_contato(
            &[
                e("nome", "João Silva", 0.9),
                e("email", "Joao@Exemplo.com", 0.95),
            ],
            0.8,
        );
        assert_eq!(v.nome.as_deref(), Some("João Silva"));
        assert_eq!(v.email.as_deref(), Some("joao@exemplo.com"));
    }

    #[test]
    fn abaixo_do_piso_nao_entra() {
        let v = valores_para_o_contato(&[e("email", "a@b.com", 0.5)], 0.8);
        assert_eq!(v, ValoresDoContato::default());
    }

    #[test]
    fn email_sem_formato_e_nome_com_digito_ficam_de_fora() {
        let v = valores_para_o_contato(
            &[
                e("email", "joao arroba exemplo", 0.99),
                e("nome", "Cliente 123", 0.99),
            ],
            0.8,
        );
        assert!(v.email.is_none());
        assert!(v.nome.is_none());
        assert!(v.extras.is_empty());
    }

    #[test]
    fn o_mais_confiante_de_cada_tipo_ganha() {
        let v = valores_para_o_contato(
            &[e("email", "a@b.com", 0.85), e("email", "c@d.com", 0.97)],
            0.8,
        );
        assert_eq!(v.email.as_deref(), Some("c@d.com"));
    }

    #[test]
    fn outros_tipos_vao_para_os_extras() {
        let v = valores_para_o_contato(&[e("cidade", "Recife", 0.9)], 0.8);
        assert_eq!(
            v.extras.get("cidade").and_then(|x| x.as_str()),
            Some("Recife")
        );
    }

    #[test]
    fn sinonimos_de_nome_e_email() {
        let v = valores_para_o_contato(
            &[
                e("PERSON", "Ana Lima", 0.9),
                e("e-mail", "ana@x.com.br", 0.9),
            ],
            0.8,
        );
        assert_eq!(v.nome.as_deref(), Some("Ana Lima"));
        assert_eq!(v.email.as_deref(), Some("ana@x.com.br"));
    }
}
