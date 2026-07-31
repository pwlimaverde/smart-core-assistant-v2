//! Adapter Postgres do domínio Voucher.
//!
//! O único ponto que merece atenção é [`PgVoucherStore::resgatar`]: o resgate e
//! o registro da concessão precisam ser **uma transação só**. O `UPDATE` atômico
//! de `vouchers::resgatar` impede que dois cadastros consumam a mesma vaga; a
//! `UNIQUE (voucher_id, tenant_id)` do registro impede que uma retentativa do
//! mesmo cadastro consuma duas. Só funciona se a violação da unique desfizer o
//! incremento — daí o rollback explícito no caminho de erro.

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

use infrastructure_postgres::tenants::vouchers::{
    self, RecusaVoucher, ResultadoResgate, VoucherListItem, VoucherResgate,
};
use infrastructure_postgres::DbError;

use crate::ports::{DesfechoResgate, VoucherStore};

/// `tenants_voucher` e `tenants_voucher_redemption` são tabelas globais do SaaS
/// (sem RLS), então o pool de runtime basta — não há política a satisfazer.
#[derive(Clone)]
pub struct PgVoucherStore {
    pub pool: PgPool,
}

impl PgVoucherStore {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

fn voucher_para_json(item: &VoucherListItem) -> serde_json::Value {
    let v = &item.voucher;
    serde_json::json!({
        "id": v.id.to_string(),
        "codigo": v.codigo,
        "descricao": v.descricao,
        "plan_id": v.plan_id,
        "plan_name": item.plan_name,
        "duracao_dias": v.duracao_dias,
        "max_resgates": v.max_resgates,
        "resgates_usados": v.resgates_usados,
        "valido_de": v.valido_de.timestamp_millis(),
        "valido_ate": v.valido_ate.map(|d| d.timestamp_millis()).unwrap_or(0),
        "revogado_em": v.revogado_em.map(|d| d.timestamp_millis()).unwrap_or(0),
        "motivo_revogacao": v.motivo_revogacao,
        "created_at": v.created_at.timestamp_millis(),
    })
}

fn resgate_para_json(r: &VoucherResgate) -> serde_json::Value {
    serde_json::json!({
        "id": r.id.to_string(),
        "voucher_id": r.voucher_id.to_string(),
        "tenant_id": r.tenant_id.to_string(),
        "plan_id": r.plan_id,
        "periodo_inicio": r.periodo_inicio.timestamp_millis(),
        "periodo_fim": r.periodo_fim.timestamp_millis(),
        "ip": r.ip,
        "redeemed_at": r.redeemed_at.timestamp_millis(),
    })
}

#[async_trait]
impl VoucherStore for PgVoucherStore {
    #[tracing::instrument(skip_all, fields(tenant_id = %tenant_id))]
    async fn resgatar(
        &self,
        codigo: &str,
        tenant_id: Uuid,
        ip: &str,
    ) -> Result<DesfechoResgate, DbError> {
        let mut tx = self.pool.begin().await?;

        let concessao = match vouchers::resgatar(&mut tx, codigo).await? {
            ResultadoResgate::Concedido(c) => c,
            ResultadoResgate::Recusado(recusa) => {
                tx.rollback().await?;
                return Ok(recusa_para_desfecho(recusa));
            }
        };

        let periodo_inicio = Utc::now();
        let periodo_fim = concessao.periodo_fim(periodo_inicio);

        let registro = vouchers::registrar_resgate(
            &mut tx,
            concessao.voucher_id,
            tenant_id,
            concessao.plan_id,
            periodo_inicio,
            periodo_fim,
            ip,
        )
        .await;

        match registro {
            Ok(r) => {
                tx.commit().await?;
                Ok(DesfechoResgate::Concedido {
                    resgate_id: r.id,
                    plan_id: r.plan_id,
                    periodo_inicio: r.periodo_inicio,
                    periodo_fim: r.periodo_fim,
                })
            }
            // Este tenant já resgatou este voucher: retentativa, não fraude. O
            // rollback devolve o incremento — sem ele, uma rede instável comeria
            // as vagas de um código de campanha.
            Err(DbError::UniqueViolation(_)) => {
                tx.rollback().await?;
                tracing::info!(
                    tenant_id = %tenant_id,
                    "resgate repetido do mesmo voucher pelo mesmo tenant; devolvendo a vaga"
                );
                Ok(DesfechoResgate::Recusado {
                    motivo: "ja_resgatado".to_string(),
                    mensagem: "Este código já foi usado nesta conta.".to_string(),
                })
            }
            Err(e) => {
                tx.rollback().await?;
                Err(e)
            }
        }
    }

    #[tracing::instrument(skip_all)]
    async fn criar(
        &self,
        codigo: &str,
        descricao: &str,
        plan_id: i32,
        duracao_dias: i32,
        max_resgates: i32,
        valido_ate: Option<DateTime<Utc>>,
        created_by_id: Option<i32>,
    ) -> Result<serde_json::Value, DbError> {
        let voucher = vouchers::criar(
            &self.pool,
            codigo,
            descricao,
            plan_id,
            duracao_dias,
            max_resgates,
            valido_ate,
            created_by_id,
        )
        .await?;

        // A criação não faz JOIN; o nome do plano vem na listagem seguinte.
        Ok(voucher_para_json(&VoucherListItem {
            voucher,
            plan_name: String::new(),
        }))
    }

    #[tracing::instrument(skip_all)]
    async fn listar(&self) -> Result<Vec<serde_json::Value>, DbError> {
        let itens = vouchers::listar(&self.pool).await?;
        Ok(itens.iter().map(voucher_para_json).collect())
    }

    #[tracing::instrument(skip_all, fields(voucher_id = %voucher_id))]
    async fn revogar(
        &self,
        voucher_id: Uuid,
        revogado_por_id: Option<i32>,
        motivo: &str,
    ) -> Result<bool, DbError> {
        vouchers::revogar(&self.pool, voucher_id, revogado_por_id, motivo).await
    }

    #[tracing::instrument(skip_all, fields(voucher_id = %voucher_id))]
    async fn listar_resgates(&self, voucher_id: Uuid) -> Result<Vec<serde_json::Value>, DbError> {
        let resgates = vouchers::listar_resgates(&self.pool, voucher_id).await?;
        Ok(resgates.iter().map(resgate_para_json).collect())
    }
}

/// Traduz a recusa da camada de persistência no desfecho do port.
fn recusa_para_desfecho(recusa: RecusaVoucher) -> DesfechoResgate {
    DesfechoResgate::Recusado {
        motivo: recusa.as_str().to_string(),
        mensagem: recusa.mensagem().to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recusa_preserva_o_motivo_real_para_log_e_generaliza_a_mensagem() {
        let revogado = recusa_para_desfecho(RecusaVoucher::Revogado);
        let inexistente = recusa_para_desfecho(RecusaVoucher::Inexistente);

        let (
            DesfechoResgate::Recusado {
                motivo: m1,
                mensagem: msg1,
            },
            DesfechoResgate::Recusado {
                motivo: m2,
                mensagem: msg2,
            },
        ) = (revogado, inexistente)
        else {
            panic!("recusa deveria produzir Recusado");
        };

        assert_ne!(m1, m2, "o log precisa distinguir os motivos");
        assert_eq!(
            msg1, msg2,
            "o usuário não pode descobrir que o código existiu"
        );
    }
}
