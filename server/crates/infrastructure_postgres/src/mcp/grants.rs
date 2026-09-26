//! Repositório de `mcp_oauth_grant` — o consentimento OAuth 2.1 de um usuário a
//! um cliente MCP externo.
//!
//! # Por que aqui não há `sqlx::query_as!`
//!
//! O resto da crate usa as macros com verificação em tempo de compilação, que
//! dependem do cache `.sqlx/` gerado por `cargo sqlx prepare` contra um banco
//! com a migration já aplicada. Esse cache não pode ser produzido no servidor de
//! produção (compilar o workspace ali derruba a stack por falta de memória) e um
//! `.sqlx` desatualizado quebra o `cargo sqlx prepare --check` do CI. As queries
//! deste arquivo são, por isso, verificadas em tempo de execução — as colunas são
//! extraídas por nome e os tipos casados no `FromRow` logo abaixo, que é o ponto
//! único onde um erro de schema apareceria (e aparece em teste de integração,
//! não em produção).
//!
//! # Regra de segurança que o arquivo inteiro serve
//!
//! O refresh token **nunca** existe em claro aqui: o AS gera o token opaco,
//! guarda o SHA-256 do segredo e devolve o claro ao cliente uma única vez
//! (SHA-256 e não argon2id — a justificativa está na migration 0032). Rotação é
//! obrigatória (spec OAuth 2.1 para clientes públicos) e o reuso de um hash já
//! rotacionado é tratado como roubo — [`revogar_por_reuso`] derruba o grant
//! inteiro em vez de só recusar a chamada.

use chrono::{DateTime, Utc};
use sqlx::{Postgres, Row, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

/// Um consentimento como ele é lido do banco. `refresh_token_hash` fica de fora
/// de propósito: nenhuma tela nem RPC precisa dele, e não devolvê-lo elimina a
/// chance de vazar por serialização descuidada.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct McpGrant {
    pub id: Uuid,
    pub tenant_id: Uuid,
    pub user_id: i32,
    pub client_id: String,
    pub client_name: String,
    pub redirect_uri: String,
    pub scopes: Vec<String>,
    pub last_used_at: Option<DateTime<Utc>>,
    pub revoked_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

impl McpGrant {
    fn da_linha(row: &sqlx::postgres::PgRow) -> Result<Self, DbError> {
        let scopes: serde_json::Value = row.try_get("scopes")?;
        Ok(Self {
            id: row.try_get("id")?,
            tenant_id: row.try_get("tenant_id")?,
            user_id: row.try_get("user_id")?,
            client_id: row.try_get("client_id")?,
            client_name: row.try_get("client_name")?,
            redirect_uri: row.try_get("redirect_uri")?,
            scopes: escopos_do_json(&scopes),
            last_used_at: row.try_get("last_used_at")?,
            revoked_at: row.try_get("revoked_at")?,
            created_at: row.try_get("created_at")?,
        })
    }
}

/// Grant + hash do refresh, para o caminho de renovação de token. Não sai do
/// `control_plane`: é o único ponto que precisa comparar hashes.
#[derive(Debug, Clone)]
pub struct McpGrantComSegredo {
    pub grant: McpGrant,
    pub refresh_token_hash: Option<String>,
}

fn escopos_do_json(valor: &serde_json::Value) -> Vec<String> {
    valor
        .as_array()
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str().map(str::to_string))
                .collect()
        })
        .unwrap_or_default()
}

// As colunas são repetidas por extenso em cada query, e não extraídas para uma
// constante interpolada com `format!`. Não é descuido: o `sqlx::query` aceita
// apenas `&'static str`, e uma string montada em tempo de execução é recusada na
// compilação — "dynamic SQL strings should be audited for possible injections".
// O diagnóstico está certo: a conveniência de não repetir dez nomes de coluna
// não vale abrir a porta para SQL montado com `format!` neste arquivo, ainda que
// aqui a interpolação fosse de uma constante nossa.

/// Registra (ou atualiza) o consentimento do usuário a um cliente.
///
/// Reconsentir com o mesmo cliente **substitui** os escopos em vez de acumular:
/// o usuário vê uma tela nova, aprova um conjunto novo, e é esse conjunto que
/// vale. Acumular silenciosamente seria ampliar permissão sem que ninguém
/// tivesse dito sim àquela ampliação.
#[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, user_id = ctx.user_id))]
pub async fn registrar_consentimento(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    client_id: &str,
    client_name: &str,
    redirect_uri: &str,
    escopos: &[String],
    created_ip: Option<&str>,
) -> Result<McpGrant, DbError> {
    let escopos_json = serde_json::json!(escopos);

    // Revoga um consentimento anterior do mesmo par (usuário, cliente) antes de
    // gravar o novo. Sem isso a tela de aplicativos conectados mostraria a mesma
    // integração duas vezes e "Desconectar" só cortaria uma delas.
    sqlx::query(
        "UPDATE mcp_oauth_grant
            SET revoked_at = NOW(), refresh_token_hash = NULL
          WHERE tenant_id = $1 AND user_id = $2 AND client_id = $3 AND revoked_at IS NULL",
    )
    .bind(ctx.tenant_id)
    .bind(ctx.user_id)
    .bind(client_id)
    .execute(&mut **tx)
    .await?;

    let row = sqlx::query(
        "INSERT INTO mcp_oauth_grant
             (tenant_id, user_id, client_id, client_name, redirect_uri, scopes, created_ip)
         VALUES ($1, $2, $3, $4, $5, $6, $7::inet)
         RETURNING id, tenant_id, user_id, client_id, client_name, redirect_uri,
                   scopes, last_used_at, revoked_at, created_at",
    )
    .bind(ctx.tenant_id)
    .bind(ctx.user_id)
    .bind(client_id)
    .bind(client_name)
    .bind(redirect_uri)
    .bind(&escopos_json)
    .bind(created_ip)
    .fetch_one(&mut **tx)
    .await
    .map_err(DbError::from_sqlx_unique)?;

    McpGrant::da_linha(&row)
}

/// Lista os consentimentos **do próprio usuário**. Não existe variante que liste
/// os de outra pessoa: a tela é pessoal, e um `tenant:admin` curioso não tem
/// motivo para ver com que agente o colega conectou.
///
/// Só entram os que de fato conectaram. O consentimento grava o grant e devolve
/// o code; quem o converte em conexão é o cliente, ao trocá-lo no
/// `/oauth/token` — e é lá que `refresh_token_hash` e `last_used_at` são
/// preenchidos, sempre juntos. Um grant sem hash é uma autorização que o
/// cliente abandonou no meio: a pessoa clicou "autorizar", e nada do outro lado
/// completou.
///
/// Mostrar isso como "aplicativo conectado" foi o que confundiu o diagnóstico
/// em 12/09/2026: o Claude descartava o code por outro motivo, a tela do
/// produto listava a conexão assim mesmo, e a leitura do banco parecia dizer
/// que o vínculo existia. A tela precisa afirmar o que aconteceu, não o que se
/// tentou.
#[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, user_id = ctx.user_id))]
pub async fn listar_do_usuario(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
) -> Result<Vec<McpGrant>, DbError> {
    let rows = sqlx::query(
        "SELECT id, tenant_id, user_id, client_id, client_name, redirect_uri,
                scopes, last_used_at, revoked_at, created_at
           FROM mcp_oauth_grant
          WHERE tenant_id = $1 AND user_id = $2 AND revoked_at IS NULL
                AND refresh_token_hash IS NOT NULL
          ORDER BY created_at DESC",
    )
    .bind(ctx.tenant_id)
    .bind(ctx.user_id)
    .fetch_all(&mut **tx)
    .await?;

    rows.iter().map(McpGrant::da_linha).collect()
}

/// Revoga um grant do próprio usuário. `false` quando o grant não existe, é de
/// outra pessoa ou já estava revogado — os três casos são indistinguíveis de
/// propósito, para não confirmar a existência de grant alheio.
#[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, user_id = ctx.user_id, grant_id = %grant_id))]
pub async fn revogar(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    grant_id: Uuid,
) -> Result<bool, DbError> {
    let resultado = sqlx::query(
        "UPDATE mcp_oauth_grant
            SET revoked_at = NOW(), refresh_token_hash = NULL
          WHERE id = $1 AND tenant_id = $2 AND user_id = $3 AND revoked_at IS NULL",
    )
    .bind(grant_id)
    .bind(ctx.tenant_id)
    .bind(ctx.user_id)
    .execute(&mut **tx)
    .await?;

    Ok(resultado.rows_affected() > 0)
}

/// Grava o hash do refresh token corrente (emissão inicial ou rotação).
#[tracing::instrument(skip_all, fields(grant_id = %grant_id))]
pub async fn definir_refresh_hash(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    grant_id: Uuid,
    hash: &str,
) -> Result<(), DbError> {
    sqlx::query(
        "UPDATE mcp_oauth_grant
            SET refresh_token_hash = $1, last_used_at = NOW()
          WHERE id = $2 AND tenant_id = $3 AND revoked_at IS NULL",
    )
    .bind(hash)
    .bind(grant_id)
    .bind(tenant_id)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

/// Busca um grant ativo pelo id, trazendo o hash do refresh para comparação.
#[tracing::instrument(skip_all, fields(grant_id = %grant_id))]
pub async fn buscar_ativo_com_segredo(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    grant_id: Uuid,
) -> Result<Option<McpGrantComSegredo>, DbError> {
    let row = sqlx::query(
        "SELECT id, tenant_id, user_id, client_id, client_name, redirect_uri,
                scopes, last_used_at, revoked_at, created_at, refresh_token_hash
           FROM mcp_oauth_grant
          WHERE id = $1 AND tenant_id = $2 AND revoked_at IS NULL",
    )
    .bind(grant_id)
    .bind(tenant_id)
    .fetch_optional(&mut **tx)
    .await?;

    match row {
        Some(row) => {
            let refresh_token_hash: Option<String> = row.try_get("refresh_token_hash")?;
            Ok(Some(McpGrantComSegredo {
                grant: McpGrant::da_linha(&row)?,
                refresh_token_hash,
            }))
        }
        None => Ok(None),
    }
}

/// Como [`buscar_ativo_com_segredo`], mas só pelo id — para a renovação do
/// token, em que o tenant ainda não é conhecido (o refresh token carrega só o
/// id do grant).
///
/// Exige o pool com BYPASSRLS: pela RLS, sem tenant na sessão a linha é
/// invisível. Era exatamente o defeito: a renovação buscava com tenant nulo, o
/// `tenant_id = $2` nunca casava, e TODA renovação falhava em silêncio — o
/// cliente MCP perdia a sessão a cada 15 minutos. O id do grant é UUID
/// aleatório, e a rota é interna (só o `control_plane` a alcança).
#[tracing::instrument(skip_all, fields(grant_id = %grant_id))]
pub async fn buscar_ativo_com_segredo_por_id(
    admin_pool: &sqlx::PgPool,
    grant_id: Uuid,
) -> Result<Option<McpGrantComSegredo>, DbError> {
    let row = sqlx::query(
        "SELECT id, tenant_id, user_id, client_id, client_name, redirect_uri,
                scopes, last_used_at, revoked_at, created_at, refresh_token_hash
           FROM mcp_oauth_grant
          WHERE id = $1 AND revoked_at IS NULL",
    )
    .bind(grant_id)
    .fetch_optional(admin_pool)
    .await?;

    match row {
        Some(row) => {
            let refresh_token_hash: Option<String> = row.try_get("refresh_token_hash")?;
            Ok(Some(McpGrantComSegredo {
                grant: McpGrant::da_linha(&row)?,
                refresh_token_hash,
            }))
        }
        None => Ok(None),
    }
}

/// Derruba o grant por detecção de reuso de refresh token já rotacionado.
///
/// Não é "recusar a requisição": um refresh antigo sendo apresentado significa
/// que **duas** partes têm o token — a legítima, que já rotacionou, e outra. Sem
/// saber qual das duas está falando, a única resposta segura é encerrar o
/// consentimento e obrigar a reconectar pelo navegador.
#[tracing::instrument(skip_all, fields(grant_id = %grant_id))]
pub async fn revogar_por_reuso(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    grant_id: Uuid,
) -> Result<(), DbError> {
    sqlx::query(
        "UPDATE mcp_oauth_grant
            SET revoked_at = NOW(), refresh_token_hash = NULL
          WHERE id = $1 AND tenant_id = $2",
    )
    .bind(grant_id)
    .bind(tenant_id)
    .execute(&mut **tx)
    .await?;

    tracing::warn!(
        %grant_id,
        %tenant_id,
        "refresh token reutilizado após rotação: grant revogado por suspeita de roubo"
    );
    Ok(())
}

/// Marca uso do grant. Preguiçoso de propósito: é chamado no caminho quente de
/// emissão de token e um `UPDATE` por chamada não justifica a escrita.
#[tracing::instrument(skip_all, fields(grant_id = %grant_id))]
pub async fn marcar_uso(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    grant_id: Uuid,
) -> Result<(), DbError> {
    sqlx::query(
        "UPDATE mcp_oauth_grant
            SET last_used_at = NOW()
          WHERE id = $1 AND tenant_id = $2
            AND (last_used_at IS NULL OR last_used_at < NOW() - INTERVAL '5 minutes')",
    )
    .bind(grant_id)
    .bind(tenant_id)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn escopos_do_json_extrai_array_de_strings() {
        let valor = serde_json::json!(["atendimentos:read", "clientes:read"]);
        assert_eq!(
            escopos_do_json(&valor),
            vec!["atendimentos:read".to_string(), "clientes:read".to_string()]
        );
    }

    #[test]
    fn escopos_do_json_descarta_entradas_nao_texto() {
        // Um jsonb corrompido à mão não deve virar escopo `null` ou `42`.
        let valor = serde_json::json!(["atendimentos:read", 42, null]);
        assert_eq!(
            escopos_do_json(&valor),
            vec!["atendimentos:read".to_string()]
        );
    }

    #[test]
    fn escopos_do_json_de_valor_nao_array_e_lista_vazia() {
        assert!(escopos_do_json(&serde_json::json!({})).is_empty());
        assert!(escopos_do_json(&serde_json::Value::Null).is_empty());
    }

    #[test]
    fn mcp_grant_serializado_nao_carrega_refresh_hash() {
        // Blindagem contra regressão: se alguém acrescentar o campo ao struct
        // por conveniência, este teste cai antes de o hash chegar a uma tela.
        let grant = McpGrant {
            id: Uuid::nil(),
            tenant_id: Uuid::nil(),
            user_id: 1,
            client_id: "https://claude.ai/mcp-client".to_string(),
            client_name: "Claude".to_string(),
            redirect_uri: "https://claude.ai/api/mcp/auth_callback".to_string(),
            scopes: vec!["atendimentos:read".to_string()],
            last_used_at: None,
            revoked_at: None,
            created_at: Utc::now(),
        };
        let json = serde_json::to_string(&grant).unwrap();
        assert!(!json.contains("refresh"));
        assert!(!json.contains("hash"));
    }
}

/// B7 (doc 35-agentes F4) — resultado de ajustar as permissões de um grant.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AjusteDeEscopos {
    /// Escopos gravados, na ordem em que o grant já os tinha.
    Ajustado(Vec<String>),
    /// Grant inexistente, de outra pessoa ou já revogado — indistinguíveis de
    /// propósito, como em [`revogar`].
    NaoEncontrado,
    /// O pedido inclui permissão que o grant não tem.
    AmpliaAcesso,
}

/// A regra do ajuste: **só reduz**. `None` quando o pedido inclui algo que o
/// grant não tem — ampliar acesso tem de passar pela tela de consentimento, onde
/// quem aprova vê o que está dando.
pub fn escopos_reduzidos(atuais: &[String], pedidos: &[String]) -> Option<Vec<String>> {
    if pedidos.iter().any(|p| !atuais.contains(p)) {
        return None;
    }
    Some(
        atuais
            .iter()
            .filter(|a| pedidos.contains(a))
            .cloned()
            .collect(),
    )
}

/// Reduz os escopos de um grant do próprio usuário, sem tocar no refresh token.
///
/// O agente continua conectado e sente a mudança na renovação seguinte: o
/// `control_plane` reintersecta os escopos do grant a cada refresh.
#[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, user_id = ctx.user_id, grant_id = %grant_id))]
pub async fn reduzir_escopos(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    grant_id: Uuid,
    pedidos: &[String],
) -> Result<AjusteDeEscopos, DbError> {
    let row = sqlx::query(
        "SELECT scopes
           FROM mcp_oauth_grant
          WHERE id = $1 AND tenant_id = $2 AND user_id = $3 AND revoked_at IS NULL
                AND refresh_token_hash IS NOT NULL
          FOR UPDATE",
    )
    .bind(grant_id)
    .bind(ctx.tenant_id)
    .bind(ctx.user_id)
    .fetch_optional(&mut **tx)
    .await?;
    let Some(row) = row else {
        return Ok(AjusteDeEscopos::NaoEncontrado);
    };
    let atuais: serde_json::Value = row.try_get("scopes")?;
    let Some(novos) = escopos_reduzidos(&escopos_do_json(&atuais), pedidos) else {
        return Ok(AjusteDeEscopos::AmpliaAcesso);
    };

    sqlx::query("UPDATE mcp_oauth_grant SET scopes = $1 WHERE id = $2 AND tenant_id = $3")
        .bind(serde_json::json!(novos))
        .bind(grant_id)
        .bind(ctx.tenant_id)
        .execute(&mut **tx)
        .await?;
    Ok(AjusteDeEscopos::Ajustado(novos))
}

#[cfg(test)]
mod tests_ajuste_de_escopos {
    use super::escopos_reduzidos;

    fn v(itens: &[&str]) -> Vec<String> {
        itens.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn reduz_mantendo_a_ordem_do_grant() {
        let atuais = v(&["atendimentos:read", "atendimentos:write", "clientes:read"]);
        let pedidos = v(&["clientes:read", "atendimentos:read"]);
        assert_eq!(
            escopos_reduzidos(&atuais, &pedidos),
            Some(v(&["atendimentos:read", "clientes:read"]))
        );
    }

    #[test]
    fn pedido_com_permissao_nova_nao_passa() {
        let atuais = v(&["atendimentos:read"]);
        assert_eq!(
            escopos_reduzidos(&atuais, &v(&["atendimentos:write"])),
            None
        );
        assert_eq!(
            escopos_reduzidos(&atuais, &v(&["atendimentos:read", "tenant:admin"])),
            None
        );
    }
}
