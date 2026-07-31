//! Vouchers de ativação: concessão de plano por um período, mediante código.
//!
//! É o primeiro provedor da porta de pagamento do cadastro (ver
//! `application::pagamento`) — não um cupom de desconto: o voucher não abate
//! valor, ele confirma a assinatura na hora.
//!
//! **O ponto delicado deste módulo é o resgate.** O erro clássico em cupom é
//! consultar, decidir que está válido e só depois gravar: dois cadastros
//! simultâneos passam ambos pela consulta antes de qualquer um gravar, e o
//! código é usado duas vezes. Aqui verificação e escrita são **um único
//! `UPDATE ... RETURNING`** — mesmo desenho de [`aceitar_convite`], que consome
//! o convite com `WHERE used = FALSE` antes de criar registro algum.
//!
//! Consultas em modo runtime (`sqlx::query_as::<_, T>`, sem a macro `!`), como
//! em [`crate::tenants::quota`]: as tabelas nascem nesta versão e a macro exigiria
//! `cargo sqlx prepare` contra um banco que só as terá depois da migration
//! aplicada — precondição que já quebrou o ambiente compartilhado uma vez.

use chrono::{DateTime, Duration, Utc};
use sqlx::{PgPool, Postgres, Row, Transaction};
use uuid::Uuid;

use crate::errors::DbError;

/// Voucher como está no banco.
#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct Voucher {
    pub id: Uuid,
    pub codigo: String,
    pub descricao: String,
    pub plan_id: i32,
    pub duracao_dias: i32,
    pub max_resgates: i32,
    pub resgates_usados: i32,
    pub valido_de: DateTime<Utc>,
    pub valido_ate: Option<DateTime<Utc>>,
    pub revogado_em: Option<DateTime<Utc>>,
    pub motivo_revogacao: String,
    pub created_at: DateTime<Utc>,
}

/// Voucher com o nome do plano resolvido, para a listagem do painel.
///
/// `flatten` nos dois lados: o `sqlx` lê as colunas do voucher direto da mesma
/// linha do JOIN, e o `serde` mantém o JSON plano — o painel recebe os campos do
/// voucher no mesmo nível de `plan_name`, sem um objeto aninhado a desempacotar.
#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct VoucherListItem {
    #[sqlx(flatten)]
    #[serde(flatten)]
    pub voucher: Voucher,
    pub plan_name: String,
}

/// Uma concessão registrada.
#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct VoucherResgate {
    pub id: Uuid,
    pub voucher_id: Uuid,
    pub tenant_id: Uuid,
    pub plan_id: i32,
    pub periodo_inicio: DateTime<Utc>,
    pub periodo_fim: DateTime<Utc>,
    pub ip: String,
    pub redeemed_at: DateTime<Utc>,
}

/// O que o voucher concede, devolvido pelo `UPDATE` do resgate.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Concessao {
    pub voucher_id: Uuid,
    pub plan_id: i32,
    pub duracao_dias: i32,
}

impl Concessao {
    /// Fim do período concedido a partir de `inicio`.
    pub fn periodo_fim(&self, inicio: DateTime<Utc>) -> DateTime<Utc> {
        inicio + Duration::days(i64::from(self.duracao_dias))
    }
}

/// Por que um código foi recusado. Serve **só para a mensagem ao usuário**: a
/// decisão de recusar já foi tomada pelo `UPDATE` que não afetou linha nenhuma.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecusaVoucher {
    Inexistente,
    Revogado,
    Expirado,
    AindaNaoVigente,
    Esgotado,
}

impl RecusaVoucher {
    /// Mensagem para o usuário final. Deliberadamente **não** distingue
    /// "inexistente" de "revogado": um código de campanha é enumerável, e
    /// confirmar que ele já existiu entrega informação a quem está sondando.
    pub fn mensagem(&self) -> &'static str {
        match self {
            Self::Inexistente | Self::Revogado => "Código inválido.",
            Self::Expirado => "Este código expirou.",
            Self::AindaNaoVigente => "Este código ainda não está válido.",
            Self::Esgotado => "Este código já atingiu o limite de usos.",
        }
    }

    /// Discriminante estável para log/auditoria (aqui, sim, o motivo real).
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Inexistente => "inexistente",
            Self::Revogado => "revogado",
            Self::Expirado => "expirado",
            Self::AindaNaoVigente => "ainda_nao_vigente",
            Self::Esgotado => "esgotado",
        }
    }
}

/// Resultado do resgate. A recusa é caso de negócio, não erro: `Result` fica
/// reservado para falha de infraestrutura.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ResultadoResgate {
    Concedido(Concessao),
    Recusado(RecusaVoucher),
}

/// Forma canônica do código: maiúsculas, sem espaços nas pontas.
///
/// "DevTeste", "devteste " e "DEVTESTE" são o mesmo voucher — a coluna
/// `codigo_normalizado` tem UNIQUE sobre este valor, então o banco também
/// impede que duas grafias do mesmo código coexistam.
pub fn normalizar_codigo(codigo: &str) -> String {
    codigo.trim().to_uppercase()
}

/// Consome um resgate do voucher.
///
/// `check` e `update` num só statement: as condições de validade estão no
/// `WHERE` do mesmo `UPDATE` que incrementa `resgates_usados`. Duas transações
/// concorrentes disputam a linha e só uma passa — a outra encontra
/// `resgates_usados` já incrementado e sai com zero linhas.
///
/// Zero linhas não diz **por quê**; para isso há [`diagnosticar_recusa`], uma
/// consulta secundária que só existe para compor a mensagem.
#[tracing::instrument(skip_all)]
pub async fn resgatar(
    tx: &mut Transaction<'_, Postgres>,
    codigo: &str,
) -> Result<ResultadoResgate, DbError> {
    let normalizado = normalizar_codigo(codigo);

    let row = sqlx::query(
        "UPDATE tenants_voucher \
            SET resgates_usados = resgates_usados + 1 \
          WHERE codigo_normalizado = $1 \
            AND revogado_em IS NULL \
            AND NOW() >= valido_de \
            AND (valido_ate IS NULL OR NOW() <= valido_ate) \
            AND (max_resgates = 0 OR resgates_usados < max_resgates) \
        RETURNING id, plan_id, duracao_dias",
    )
    .bind(&normalizado)
    .fetch_optional(&mut **tx)
    .await?;

    match row {
        Some(r) => Ok(ResultadoResgate::Concedido(Concessao {
            voucher_id: r.get("id"),
            plan_id: r.get("plan_id"),
            duracao_dias: r.get("duracao_dias"),
        })),
        None => Ok(ResultadoResgate::Recusado(
            diagnosticar_recusa(tx, &normalizado).await?,
        )),
    }
}

/// Descobre o motivo da recusa. Recebe o código **já normalizado**.
///
/// Só roda no caminho de falha; a ordem das checagens define qual motivo
/// prevalece quando mais de um se aplica (revogado ganha de expirado, porque é
/// a decisão explícita de um humano).
async fn diagnosticar_recusa(
    tx: &mut Transaction<'_, Postgres>,
    normalizado: &str,
) -> Result<RecusaVoucher, DbError> {
    let row = sqlx::query(
        "SELECT revogado_em, valido_de, valido_ate, max_resgates, resgates_usados \
           FROM tenants_voucher WHERE codigo_normalizado = $1",
    )
    .bind(normalizado)
    .fetch_optional(&mut **tx)
    .await?;

    let Some(r) = row else {
        return Ok(RecusaVoucher::Inexistente);
    };

    let agora = Utc::now();
    let revogado_em: Option<DateTime<Utc>> = r.get("revogado_em");
    let valido_de: DateTime<Utc> = r.get("valido_de");
    let valido_ate: Option<DateTime<Utc>> = r.get("valido_ate");
    let max_resgates: i32 = r.get("max_resgates");
    let resgates_usados: i32 = r.get("resgates_usados");

    Ok(classificar_recusa(
        agora,
        revogado_em.is_some(),
        valido_de,
        valido_ate,
        max_resgates,
        resgates_usados,
    ))
}

/// Regra pura da classificação (testável sem banco).
fn classificar_recusa(
    agora: DateTime<Utc>,
    revogado: bool,
    valido_de: DateTime<Utc>,
    valido_ate: Option<DateTime<Utc>>,
    max_resgates: i32,
    resgates_usados: i32,
) -> RecusaVoucher {
    if revogado {
        return RecusaVoucher::Revogado;
    }
    if agora < valido_de {
        return RecusaVoucher::AindaNaoVigente;
    }
    if valido_ate.is_some_and(|ate| agora > ate) {
        return RecusaVoucher::Expirado;
    }
    if max_resgates != 0 && resgates_usados >= max_resgates {
        return RecusaVoucher::Esgotado;
    }
    // Nenhuma condição visível explica a recusa: outra transação consumiu a
    // última vaga entre o UPDATE e este SELECT. Do ponto de vista de quem
    // digitou, o código acabou.
    RecusaVoucher::Esgotado
}

/// Registra a concessão. **Faz parte do resgate**, não é auditoria opcional:
/// a `UNIQUE (voucher_id, tenant_id)` é o que impede uma retentativa de rede do
/// mesmo cadastro de consumir o código duas vezes — o `UPDATE` atômico resolve
/// concorrência entre cadastros distintos, não repetição do mesmo.
///
/// Deve rodar na **mesma transação** do [`resgatar`]: a violação da unique
/// derruba a transação inteira e devolve o resgate.
#[tracing::instrument(skip_all, fields(voucher_id = %voucher_id, tenant_id = %tenant_id))]
#[allow(clippy::too_many_arguments)]
pub async fn registrar_resgate(
    tx: &mut Transaction<'_, Postgres>,
    voucher_id: Uuid,
    tenant_id: Uuid,
    plan_id: i32,
    periodo_inicio: DateTime<Utc>,
    periodo_fim: DateTime<Utc>,
    ip: &str,
) -> Result<VoucherResgate, DbError> {
    let row = sqlx::query_as::<_, VoucherResgate>(
        "INSERT INTO tenants_voucher_redemption \
             (voucher_id, tenant_id, plan_id, periodo_inicio, periodo_fim, ip) \
         VALUES ($1, $2, $3, $4, $5, $6) \
         RETURNING id, voucher_id, tenant_id, plan_id, periodo_inicio, periodo_fim, ip, redeemed_at",
    )
    .bind(voucher_id)
    .bind(tenant_id)
    .bind(plan_id)
    .bind(periodo_inicio)
    .bind(periodo_fim)
    .bind(ip)
    .fetch_one(&mut **tx)
    .await
    .map_err(DbError::from_sqlx_unique)?;
    Ok(row)
}

/// Cria um voucher (operação de superusuário).
#[tracing::instrument(skip_all, fields(codigo))]
#[allow(clippy::too_many_arguments)]
pub async fn criar(
    pool: &PgPool,
    codigo: &str,
    descricao: &str,
    plan_id: i32,
    duracao_dias: i32,
    max_resgates: i32,
    valido_ate: Option<DateTime<Utc>>,
    created_by_id: Option<i32>,
) -> Result<Voucher, DbError> {
    let codigo = codigo.trim();
    if codigo.is_empty() {
        return Err(DbError::ConfigError("código do voucher vazio".into()));
    }
    let normalizado = normalizar_codigo(codigo);

    let row = sqlx::query_as::<_, Voucher>(
        "INSERT INTO tenants_voucher \
             (codigo, codigo_normalizado, descricao, plan_id, duracao_dias, max_resgates, valido_ate, created_by_id) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8) \
         RETURNING id, codigo, descricao, plan_id, duracao_dias, max_resgates, resgates_usados, \
                   valido_de, valido_ate, revogado_em, motivo_revogacao, created_at",
    )
    .bind(codigo)
    .bind(&normalizado)
    .bind(descricao)
    .bind(plan_id)
    .bind(duracao_dias)
    .bind(max_resgates)
    .bind(valido_ate)
    .bind(created_by_id)
    .fetch_one(pool)
    .await
    .map_err(DbError::from_sqlx_unique)?;
    Ok(row)
}

/// Lista os vouchers com o nome do plano, mais recentes primeiro.
#[tracing::instrument(skip_all)]
pub async fn listar(pool: &PgPool) -> Result<Vec<VoucherListItem>, DbError> {
    let rows = sqlx::query_as::<_, VoucherListItem>(
        "SELECT v.id, v.codigo, v.descricao, v.plan_id, v.duracao_dias, v.max_resgates, \
                v.resgates_usados, v.valido_de, v.valido_ate, v.revogado_em, \
                v.motivo_revogacao, v.created_at, p.name AS plan_name \
           FROM tenants_voucher v \
           JOIN tenants_plan p ON p.id = v.plan_id \
          ORDER BY v.created_at DESC",
    )
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

/// Revoga um voucher: bloqueia **novos** resgates e não toca nas assinaturas já
/// concedidas — revogar um código não rescinde contrato firmado. Para encerrar
/// uma conta específica existe `SetTenantActive`.
///
/// Idempotente por construção (`WHERE revogado_em IS NULL`): revogar duas vezes
/// devolve `false` na segunda, sem sobrescrever quem revogou e quando.
#[tracing::instrument(skip_all, fields(voucher_id = %voucher_id))]
pub async fn revogar(
    pool: &PgPool,
    voucher_id: Uuid,
    revogado_por_id: Option<i32>,
    motivo: &str,
) -> Result<bool, DbError> {
    let res = sqlx::query(
        "UPDATE tenants_voucher \
            SET revogado_em = NOW(), revogado_por_id = $1, motivo_revogacao = $2 \
          WHERE id = $3 AND revogado_em IS NULL",
    )
    .bind(revogado_por_id)
    .bind(motivo)
    .bind(voucher_id)
    .execute(pool)
    .await?;
    Ok(res.rows_affected() > 0)
}

/// Histórico de resgates de um voucher (mais recentes primeiro).
#[tracing::instrument(skip_all, fields(voucher_id = %voucher_id))]
pub async fn listar_resgates(
    pool: &PgPool,
    voucher_id: Uuid,
) -> Result<Vec<VoucherResgate>, DbError> {
    let rows = sqlx::query_as::<_, VoucherResgate>(
        "SELECT id, voucher_id, tenant_id, plan_id, periodo_inicio, periodo_fim, ip, redeemed_at \
           FROM tenants_voucher_redemption \
          WHERE voucher_id = $1 \
          ORDER BY redeemed_at DESC",
    )
    .bind(voucher_id)
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normaliza_caixa_e_espacos() {
        assert_eq!(normalizar_codigo(" devteste "), "DEVTESTE");
        assert_eq!(normalizar_codigo("DevTeste"), "DEVTESTE");
        assert_eq!(normalizar_codigo("DEVTESTE"), "DEVTESTE");
    }

    #[test]
    fn periodo_fim_soma_a_duracao_ao_inicio() {
        let inicio = DateTime::parse_from_rfc3339("2026-07-30T12:00:00Z")
            .unwrap()
            .with_timezone(&Utc);
        let concessao = Concessao {
            voucher_id: Uuid::new_v4(),
            plan_id: 1,
            duracao_dias: 180,
        };
        assert_eq!(
            concessao.periodo_fim(inicio).to_rfc3339(),
            "2027-01-26T12:00:00+00:00"
        );
    }

    fn agora() -> DateTime<Utc> {
        DateTime::parse_from_rfc3339("2026-07-30T12:00:00Z")
            .unwrap()
            .with_timezone(&Utc)
    }

    #[test]
    fn revogacao_prevalece_sobre_expiracao() {
        // Um humano decidiu desligar o código; esse é o motivo a registrar.
        let expirado_ontem = agora() - Duration::days(1);
        assert_eq!(
            classificar_recusa(agora(), true, agora(), Some(expirado_ontem), 1, 0),
            RecusaVoucher::Revogado
        );
    }

    #[test]
    fn classifica_janela_de_validade() {
        let amanha = agora() + Duration::days(1);
        let ontem = agora() - Duration::days(1);
        assert_eq!(
            classificar_recusa(agora(), false, amanha, None, 1, 0),
            RecusaVoucher::AindaNaoVigente
        );
        assert_eq!(
            classificar_recusa(agora(), false, ontem, Some(ontem), 1, 0),
            RecusaVoucher::Expirado
        );
    }

    #[test]
    fn classifica_esgotamento_respeitando_ilimitado() {
        let ontem = agora() - Duration::days(1);
        assert_eq!(
            classificar_recusa(agora(), false, ontem, None, 1, 1),
            RecusaVoucher::Esgotado
        );
        // max_resgates = 0 é ilimitado: nenhum uso o esgota. Chegar aqui só
        // acontece na corrida perdida, que também se reporta como esgotado.
        assert_eq!(
            classificar_recusa(agora(), false, ontem, None, 0, 9_999),
            RecusaVoucher::Esgotado
        );
    }

    #[test]
    fn mensagem_ao_usuario_nao_confirma_existencia_do_codigo() {
        // Enumerar códigos não pode render informação: revogado e inexistente
        // dizem a mesma coisa a quem digitou.
        assert_eq!(
            RecusaVoucher::Revogado.mensagem(),
            RecusaVoucher::Inexistente.mensagem()
        );
        // Já o log distingue.
        assert_ne!(
            RecusaVoucher::Revogado.as_str(),
            RecusaVoucher::Inexistente.as_str()
        );
    }
}
