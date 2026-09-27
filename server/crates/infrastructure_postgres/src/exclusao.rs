//! Exclusão definitiva, separada de desativar (doc_dev/planejamento/39).
//!
//! Três estados, em todas as entidades que o usuário manipula:
//!
//! - **ativo** — em uso;
//! - **inativo** — `ativo = false`: sai de uso, continua nas listas de gestão e
//!   volta com "Reativar";
//! - **excluído** — `excluido_em` preenchido: some do painel, das seleções, da
//!   IA, das filas, dos relatórios e das estatísticas, e **não volta**. Se for
//!   preciso, cria-se outro. A linha fica só para a auditoria.
//!
//! Excluir também desliga o `ativo` (onde a tabela o tem). É o que faz todo
//! filtro "só ativos" que já existia esconder o excluído sem mudança — o filtro
//! explícito de `excluido_em` só precisa estar onde inativos aparecem.
//!
//! O SQL é montado a partir de [`TipoExcluivel`], uma lista fechada: nome de
//! tabela e de coluna nunca vêm de fora, por isso o `AssertSqlSafe`.

use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};

use crate::{DbError, RequestContext};

/// O que pode ser excluído. O nome (`contato`, `numero_ignorado`…) é o que
/// trafega no contrato e fica na auditoria.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TipoExcluivel {
    Contato,
    Cliente,
    Atendimento,
    Departamento,
    Fluxo,
    Etapa,
    Atendente,
    Campo,
    Etiqueta,
    Nota,
    Intencao,
    Treinamento,
    NumeroIgnorado,
    Conexao,
}

impl TipoExcluivel {
    pub const TODOS: [TipoExcluivel; 14] = [
        Self::Contato,
        Self::Cliente,
        Self::Atendimento,
        Self::Departamento,
        Self::Fluxo,
        Self::Etapa,
        Self::Atendente,
        Self::Campo,
        Self::Etiqueta,
        Self::Nota,
        Self::Intencao,
        Self::Treinamento,
        Self::NumeroIgnorado,
        Self::Conexao,
    ];

    pub fn nome(self) -> &'static str {
        match self {
            Self::Contato => "contato",
            Self::Cliente => "cliente",
            Self::Atendimento => "atendimento",
            Self::Departamento => "departamento",
            Self::Fluxo => "fluxo",
            Self::Etapa => "etapa",
            Self::Atendente => "atendente",
            Self::Campo => "campo",
            Self::Etiqueta => "etiqueta",
            Self::Nota => "nota",
            Self::Intencao => "intencao",
            Self::Treinamento => "treinamento",
            Self::NumeroIgnorado => "numero_ignorado",
            Self::Conexao => "conexao",
        }
    }

    pub fn de_nome(nome: &str) -> Option<Self> {
        Self::TODOS.into_iter().find(|t| t.nome() == nome)
    }

    fn tabela(self) -> &'static str {
        match self {
            Self::Contato => "oraculo_contato",
            Self::Cliente => "oraculo_cliente",
            Self::Atendimento => "oraculo_atendimento",
            Self::Departamento => "oraculo_departamento",
            Self::Fluxo => "oraculo_fluxo_atendimento",
            Self::Etapa => "oraculo_etapa_fluxo",
            Self::Atendente => "oraculo_atendente",
            Self::Campo => "atu_campo_personalizado",
            Self::Etiqueta => "atu_etiqueta",
            Self::Nota => "atu_nota",
            Self::Intencao => "treinamento_querycompose",
            Self::Treinamento => "oraculo_treinamento",
            Self::NumeroIgnorado => "whatsapp_whitelist",
            Self::Conexao => "whatsapp_instance",
        }
    }

    /// A coluna de "inativo" — `None` onde a entidade não tem esse estado.
    pub fn coluna_ativo(self) -> Option<&'static str> {
        match self {
            Self::Atendimento | Self::Nota | Self::Intencao | Self::Treinamento => None,
            Self::NumeroIgnorado | Self::Conexao => Some("active"),
            _ => Some("ativo"),
        }
    }

    /// Como o item se apresenta na lista de excluídos (tabela aliasada `t`).
    fn rotulo_sql(self) -> &'static str {
        match self {
            Self::Contato => {
                "COALESCE(NULLIF(t.nome_contato, ''), NULLIF(t.nome_perfil_whatsapp, ''), t.telefone)"
            }
            Self::Cliente => "t.nome_fantasia",
            Self::Atendimento => "COALESCE(NULLIF(t.assunto, ''), 'Conversa ' || t.id)",
            Self::Nota => "LEFT(t.texto, 80)",
            Self::Intencao | Self::Treinamento => "t.grupo || '/' || t.tag",
            Self::NumeroIgnorado => "COALESCE(NULLIF(t.name, ''), t.phone_number)",
            Self::Conexao => "t.name",
            _ => "t.nome",
        }
    }

    /// Escopos que podem excluir — os mesmos de quem hoje desativa ou remove.
    pub fn escopos(self) -> &'static [&'static str] {
        match self {
            Self::Contato | Self::Cliente => &["clientes:write", "tenant:admin"],
            Self::Atendimento | Self::Nota | Self::Etiqueta => {
                &["atendimentos:write", "tenant:admin"]
            }
            Self::Fluxo | Self::Etapa => &["kanban:admin", "tenant:admin"],
            Self::Departamento | Self::Atendente | Self::NumeroIgnorado | Self::Conexao => {
                &["operacional:admin", "tenant:admin"]
            }
            Self::Campo => &["configuracoes:write", "tenant:admin"],
            Self::Intencao | Self::Treinamento => &["treinamento:write", "tenant:admin"],
        }
    }

    /// O que mais muda na linha além de `excluido_em`/`excluido_por_id`.
    fn efeitos(self) -> &'static str {
        match self {
            // A conversa em andamento é encerrada: sai do quadro e a próxima
            // mensagem do cliente abre outra.
            Self::Atendimento => {
                ", status = CASE WHEN status IN ('resolvido', 'cancelado', 'arquivado') \
                   THEN status ELSE 'arquivado' END, data_fim = COALESCE(data_fim, NOW())"
            }
            // Solta o login: ele pode ser ligado a outro atendente.
            Self::Atendente => ", disponivel = false, usuario_id = NULL",
            // Sem vetor, nenhuma busca da IA a encontra.
            Self::Intencao => ", embedding = NULL",
            Self::Treinamento => ", treinamento_vetorizado = false",
            Self::Conexao => ", connection_state = 'disconnected'",
            _ => "",
        }
    }
}

/// O desfecho de um pedido de exclusão.
#[derive(Debug, Clone, PartialEq)]
pub enum ResultadoExclusao {
    /// Excluído agora. `cascata` são os ids das conversas que foram junto (só
    /// na exclusão de contato).
    Excluido { cascata: Vec<i64> },
    /// Não existe, é de outro tenant ou já estava excluído.
    NaoEncontrado,
    /// Em uso: a exclusão deixaria conversas órfãs. A mensagem diz o que fazer.
    EmUso(String),
}

/// Exclui um item. Definitivo: não há restauração.
#[tracing::instrument(skip_all, fields(tipo = tipo.nome(), id = id))]
pub async fn excluir(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    tipo: TipoExcluivel,
    id: i64,
) -> Result<ResultadoExclusao, DbError> {
    ctx.exigir_qualquer(tipo.escopos())?;

    if let Some(motivo) = em_uso(tx, ctx, tipo, id).await? {
        return Ok(ResultadoExclusao::EmUso(motivo));
    }

    let desliga = tipo
        .coluna_ativo()
        .map(|c| format!(", {c} = false"))
        .unwrap_or_default();
    let sql = format!(
        "UPDATE {tabela} \
            SET excluido_em = NOW(), excluido_por_id = NULLIF($3, 0){desliga}{efeitos} \
          WHERE tenant_id = $1 AND id = $2 AND excluido_em IS NULL",
        tabela = tipo.tabela(),
        efeitos = tipo.efeitos(),
    );
    let afetadas = sqlx::query(sqlx::AssertSqlSafe(sql))
        .bind(ctx.tenant_id)
        .bind(id)
        .bind(ctx.user_id)
        .execute(&mut **tx)
        .await?
        .rows_affected();
    if afetadas == 0 {
        return Ok(ResultadoExclusao::NaoEncontrado);
    }

    let cascata = match tipo {
        // Contato excluído com conversa visível no quadro seria meia exclusão.
        TipoExcluivel::Contato => {
            let sql = format!(
                "UPDATE oraculo_atendimento \
                    SET excluido_em = NOW(), excluido_por_id = NULLIF($3, 0){efeitos} \
                  WHERE tenant_id = $1 AND contato_id = $2 AND excluido_em IS NULL \
                  RETURNING id::bigint",
                efeitos = TipoExcluivel::Atendimento.efeitos(),
            );
            sqlx::query_scalar::<_, i64>(sqlx::AssertSqlSafe(sql))
                .bind(ctx.tenant_id)
                .bind(id)
                .bind(ctx.user_id)
                .fetch_all(&mut **tx)
                .await?
        }
        // Os trechos vetorizados são derivados do texto: saem de fato, para a
        // busca da IA não achar o material excluído.
        TipoExcluivel::Treinamento => {
            sqlx::query(
                "DELETE FROM oraculo_documento WHERE tenant_id = $1 AND treinamento_id = $2",
            )
            .bind(ctx.tenant_id)
            .bind(id)
            .execute(&mut **tx)
            .await?;
            Vec::new()
        }
        _ => Vec::new(),
    };

    Ok(ResultadoExclusao::Excluido { cascata })
}

/// Recusa excluir o que ainda segura conversa em andamento (decisão D3 do doc
/// 39): excluir por baixo deixaria o cartão num fluxo, etapa ou atendente que o
/// painel não mostra mais.
async fn em_uso(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    tipo: TipoExcluivel,
    id: i64,
) -> Result<Option<String>, DbError> {
    let (coluna, oque) = match tipo {
        TipoExcluivel::Departamento => ("departamento_id", "neste departamento"),
        TipoExcluivel::Fluxo => ("fluxo_atendimento_id", "neste fluxo"),
        TipoExcluivel::Etapa => ("etapa_atual_id", "nesta etapa"),
        TipoExcluivel::Atendente => ("atendente_humano_id", "com este atendente"),
        _ => return Ok(None),
    };
    let sql = format!(
        "SELECT COUNT(*) FROM oraculo_atendimento \
          WHERE tenant_id = $1 AND {coluna} = $2 AND excluido_em IS NULL \
            AND status NOT IN ('resolvido', 'cancelado', 'arquivado')"
    );
    let abertas: i64 = sqlx::query_scalar(sqlx::AssertSqlSafe(sql))
        .bind(ctx.tenant_id)
        .bind(id)
        .fetch_one(&mut **tx)
        .await?;
    if abertas > 0 {
        return Ok(Some(format!(
            "há {abertas} conversa(s) em andamento {oque}: encerre ou mova-as antes de excluir"
        )));
    }

    // Departamento com fluxo vivo: o fluxo ficaria pendurado num setor que não
    // aparece mais.
    if tipo == TipoExcluivel::Departamento {
        let fluxos: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM oraculo_fluxo_atendimento \
              WHERE tenant_id = $1 AND departamento_id = $2 AND excluido_em IS NULL",
        )
        .bind(ctx.tenant_id)
        .bind(id)
        .fetch_one(&mut **tx)
        .await?;
        if fluxos > 0 {
            return Ok(Some(format!(
                "há {fluxos} fluxo(s) neste departamento: exclua-os antes"
            )));
        }
    }
    Ok(None)
}

/// Desativa ou reativa. Excluído não reativa — a exclusão é definitiva.
///
/// Genérico para cobrir o que não tinha caminho de volta (etapa, etiqueta) com
/// a mesma regra das demais. `None` = a entidade não tem estado inativo.
#[tracing::instrument(skip_all, fields(tipo = tipo.nome(), id = id, ativo = ativo))]
pub async fn definir_ativo(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    tipo: TipoExcluivel,
    id: i64,
    ativo: bool,
) -> Result<Option<bool>, DbError> {
    ctx.exigir_qualquer(tipo.escopos())?;
    let Some(coluna) = tipo.coluna_ativo() else {
        return Ok(None);
    };
    let sql = format!(
        "UPDATE {tabela} SET {coluna} = $3 \
          WHERE tenant_id = $1 AND id = $2 AND excluido_em IS NULL",
        tabela = tipo.tabela(),
    );
    let afetadas = sqlx::query(sqlx::AssertSqlSafe(sql))
        .bind(ctx.tenant_id)
        .bind(id)
        .bind(ativo)
        .execute(&mut **tx)
        .await?
        .rows_affected();
    Ok(Some(afetadas > 0))
}

/// Um item excluído, como a aba "Excluídos" da auditoria o mostra.
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct ItemExcluido {
    pub tipo: String,
    pub id: i64,
    pub rotulo: String,
    pub excluido_em: DateTime<Utc>,
    /// E-mail (ou login) de quem excluiu; vazio quando foi o sistema.
    pub excluido_por: String,
}

/// Os excluídos do tenant, do mais recente ao mais antigo. Somente leitura.
#[tracing::instrument(skip_all, fields(limite = limite))]
pub async fn listar_excluidos(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    tipo: Option<TipoExcluivel>,
    limite: i64,
) -> Result<Vec<ItemExcluido>, DbError> {
    ctx.exigir_qualquer(&["tenant:admin"])?;
    let tipos: Vec<TipoExcluivel> = match tipo {
        Some(t) => vec![t],
        None => TipoExcluivel::TODOS.to_vec(),
    };
    let mut itens = Vec::new();
    for t in tipos {
        let sql = format!(
            "SELECT t.id::bigint, {rotulo}::text, t.excluido_em, \
                    COALESCE(NULLIF(u.email, ''), u.username, '') \
               FROM {tabela} t \
               LEFT JOIN auth_user u ON u.id = t.excluido_por_id \
              WHERE t.tenant_id = $1 AND t.excluido_em IS NOT NULL \
              ORDER BY t.excluido_em DESC \
              LIMIT $2",
            rotulo = t.rotulo_sql(),
            tabela = t.tabela(),
        );
        let linhas: Vec<(i64, Option<String>, DateTime<Utc>, String)> =
            sqlx::query_as(sqlx::AssertSqlSafe(sql))
                .bind(ctx.tenant_id)
                .bind(limite)
                .fetch_all(&mut **tx)
                .await?;
        itens.extend(
            linhas
                .into_iter()
                .map(|(id, rotulo, excluido_em, excluido_por)| ItemExcluido {
                    tipo: t.nome().to_string(),
                    id,
                    rotulo: rotulo.unwrap_or_default(),
                    excluido_em,
                    excluido_por,
                }),
        );
    }
    itens.sort_by(|a, b| b.excluido_em.cmp(&a.excluido_em));
    itens.truncate(limite.max(0) as usize);
    Ok(itens)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn todo_tipo_tem_nome_unico_e_volta_pelo_nome() {
        let mut vistos = std::collections::HashSet::new();
        for t in TipoExcluivel::TODOS {
            assert!(vistos.insert(t.nome()), "nome repetido: {}", t.nome());
            assert_eq!(TipoExcluivel::de_nome(t.nome()), Some(t));
        }
        assert_eq!(TipoExcluivel::de_nome("usuario"), None);
    }

    #[test]
    fn so_tenant_admin_e_escritores_do_tipo_podem_excluir() {
        for t in TipoExcluivel::TODOS {
            assert!(t.escopos().contains(&"tenant:admin"), "{}", t.nome());
            assert!(t.escopos().len() >= 2, "{}", t.nome());
        }
    }

    #[test]
    fn inativo_so_existe_onde_ha_coluna() {
        assert_eq!(TipoExcluivel::Atendimento.coluna_ativo(), None);
        assert_eq!(TipoExcluivel::Nota.coluna_ativo(), None);
        assert_eq!(TipoExcluivel::Conexao.coluna_ativo(), Some("active"));
        assert_eq!(TipoExcluivel::Etapa.coluna_ativo(), Some("ativo"));
    }
}
