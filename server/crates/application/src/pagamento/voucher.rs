//! Provedor de pagamento por voucher: um código confirma a assinatura na hora.
//!
//! É o único provedor até o gateway ser escolhido, e continua útil depois — é
//! como se concedem períodos de cortesia, testes e migrações de cliente.
//!
//! Não fala SQL: o resgate é uma chamada `RedeemVoucher` ao `data_postgres`, que
//! é a única porta do banco. Toda a atomicidade vive lá (ver
//! `infrastructure_postgres::tenants::vouchers`).

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use contracts::MessageKind;
use error_core::AppError;
use std::time::Duration;
use uuid::Uuid;

use super::{
    DadosCobranca, DescricaoProvedor, IntencaoPagamento, ModoConfirmacao, ProvedorPagamento,
};
use crate::auth::login::montar_envelope_request;

/// Identificador estável do provedor no contrato com o cliente.
pub const ID_PROVEDOR: &str = "voucher";

/// Tempo máximo do RPC de resgate. Generoso o bastante para uma transação com
/// dois INSERTs, curto o bastante para não travar a tela do usuário.
const TIMEOUT_RESGATE: Duration = Duration::from_secs(10);

pub struct ProvedorVoucher {
    pg: transport::MuxClient,
}

impl ProvedorVoucher {
    pub fn novo(pg: transport::MuxClient) -> Self {
        Self { pg }
    }
}

#[async_trait]
impl ProvedorPagamento for ProvedorVoucher {
    fn descricao(&self) -> DescricaoProvedor {
        DescricaoProvedor {
            id: ID_PROVEDOR.to_string(),
            rotulo: "Tenho um código de ativação".to_string(),
            instrucao: "Informe o código recebido para liberar o acesso.".to_string(),
            requer_credencial: true,
            rotulo_credencial: "Código".to_string(),
            modo: ModoConfirmacao::Imediata,
        }
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %dados.tenant_id, plan_id = dados.plan_id))]
    async fn iniciar(&self, dados: &DadosCobranca) -> Result<IntencaoPagamento, AppError> {
        // O código nunca entra em span nem log: é credencial de campanha e
        // aparecer em log é o mesmo que distribuí-lo.
        if dados.credencial.trim().is_empty() {
            return Ok(IntencaoPagamento::Recusada {
                motivo: "codigo_vazio".to_string(),
                mensagem: "Informe o código de ativação.".to_string(),
            });
        }

        let req = montar_envelope_request(
            dados.tenant_id,
            &dados.traceparent,
            "RedeemVoucher",
            &serde_json::json!({
                "codigo": dados.credencial.trim(),
                "tenant_id": dados.tenant_id.to_string(),
                "ip": dados.ip,
            }),
        );

        let resp = self
            .pg
            .call(req, TIMEOUT_RESGATE)
            .await
            .map_err(|e| AppError::Database(format!("RPC RedeemVoucher falhou: {e:?}")))?;

        if resp.kind == MessageKind::Error as i32 {
            return Err(resp
                .error
                .map(|e| AppError::from_envelope(&e))
                .unwrap_or_else(|| AppError::Database("falha ao resgatar o código".to_string())));
        }

        let corpo: serde_json::Value = serde_json::from_slice(&resp.payload)
            .map_err(|e| AppError::Internal(format!("resposta de RedeemVoucher ilegível: {e}")))?;

        interpretar_resposta(&corpo)
    }
}

/// Traduz a resposta do `data_postgres` em [`IntencaoPagamento`].
///
/// Separada da chamada para ser testável sem transporte: é aqui que mora a
/// decisão de tratar recusa como resultado de negócio, e não como erro.
fn interpretar_resposta(corpo: &serde_json::Value) -> Result<IntencaoPagamento, AppError> {
    let concedido = corpo
        .get("concedido")
        .and_then(serde_json::Value::as_bool)
        .unwrap_or(false);

    if !concedido {
        return Ok(IntencaoPagamento::Recusada {
            motivo: corpo
                .get("motivo")
                .and_then(serde_json::Value::as_str)
                .unwrap_or("recusado")
                .to_string(),
            mensagem: corpo
                .get("mensagem")
                .and_then(serde_json::Value::as_str)
                .unwrap_or("Código inválido.")
                .to_string(),
        });
    }

    // Concedido: os três campos abaixo são o contrato do handler. Faltar
    // qualquer um significa resposta malformada — ativar assinatura com plano
    // ou prazo adivinhado seria pior do que falhar.
    let plan_id = corpo
        .get("plan_id")
        .and_then(serde_json::Value::as_i64)
        .ok_or_else(|| AppError::Internal("RedeemVoucher concedeu sem plan_id".to_string()))?
        as i32;

    let periodo_fim: DateTime<Utc> = corpo
        .get("periodo_fim")
        .and_then(serde_json::Value::as_str)
        .and_then(|s| DateTime::parse_from_rfc3339(s).ok())
        .map(|d| d.with_timezone(&Utc))
        .ok_or_else(|| AppError::Internal("RedeemVoucher concedeu sem periodo_fim".to_string()))?;

    let referencia = corpo
        .get("resgate_id")
        .and_then(serde_json::Value::as_str)
        .unwrap_or_default()
        .to_string();

    Ok(IntencaoPagamento::Confirmada {
        plan_id,
        periodo_fim,
        referencia,
    })
}

/// Dados de cobrança para o resgate de um voucher.
pub fn cobranca_com_codigo(
    tenant_id: Uuid,
    plan_id: i32,
    email: &str,
    codigo: &str,
    ip: &str,
    traceparent: &str,
) -> DadosCobranca {
    DadosCobranca {
        tenant_id,
        plan_id,
        email: email.to_string(),
        credencial: codigo.to_string(),
        ip: ip.to_string(),
        traceparent: traceparent.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn concessao_vira_intencao_confirmada() {
        let corpo = serde_json::json!({
            "concedido": true,
            "plan_id": 3,
            "periodo_fim": "2027-01-26T12:00:00Z",
            "resgate_id": "9f1c...",
        });

        let intencao = interpretar_resposta(&corpo).unwrap();
        match intencao {
            IntencaoPagamento::Confirmada {
                plan_id,
                periodo_fim,
                referencia,
            } => {
                assert_eq!(plan_id, 3);
                assert_eq!(periodo_fim.to_rfc3339(), "2027-01-26T12:00:00+00:00");
                assert_eq!(referencia, "9f1c...");
            }
            outro => panic!("esperava Confirmada, veio {outro:?}"),
        }
    }

    #[test]
    fn recusa_e_resultado_de_negocio_e_carrega_a_mensagem_do_banco() {
        let corpo = serde_json::json!({
            "concedido": false,
            "motivo": "esgotado",
            "mensagem": "Este código já atingiu o limite de usos.",
        });

        assert_eq!(
            interpretar_resposta(&corpo).unwrap(),
            IntencaoPagamento::Recusada {
                motivo: "esgotado".to_string(),
                mensagem: "Este código já atingiu o limite de usos.".to_string(),
            }
        );
    }

    #[test]
    fn concessao_sem_plano_ou_prazo_falha_em_vez_de_adivinhar() {
        // Ativar assinatura com plano ou validade inventados é pior do que errar
        // barulhentamente: o tenant sairia com acesso indevido e ninguém veria.
        let sem_plano = serde_json::json!({
            "concedido": true,
            "periodo_fim": "2027-01-26T12:00:00Z",
        });
        assert!(interpretar_resposta(&sem_plano).is_err());

        let sem_prazo = serde_json::json!({ "concedido": true, "plan_id": 1 });
        assert!(interpretar_resposta(&sem_prazo).is_err());

        let prazo_ilegivel = serde_json::json!({
            "concedido": true,
            "plan_id": 1,
            "periodo_fim": "26/01/2027",
        });
        assert!(interpretar_resposta(&prazo_ilegivel).is_err());
    }

    #[test]
    fn resposta_sem_campo_concedido_e_tratada_como_recusa() {
        // Fail closed: na dúvida, não libera acesso.
        let vazio = serde_json::json!({});
        assert!(matches!(
            interpretar_resposta(&vazio).unwrap(),
            IntencaoPagamento::Recusada { .. }
        ));
    }
}
