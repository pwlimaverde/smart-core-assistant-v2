//! Porta de pagamento do cadastro de tenant.
//!
//! O gateway ainda não foi escolhido, e o cadastro não podia esperar por essa
//! decisão. A saída foi construir o passo de pagamento contra uma **porta**, com
//! um provedor concreto — o voucher — que confirma na hora. Um gateway real
//! entra depois como mais uma implementação desta mesma trait, sem tocar no
//! wizard nem na máquina de estados da assinatura.
//!
//! O ponto que torna isso possível é [`IntencaoPagamento`] ter duas formas desde
//! o primeiro dia: `Confirmada` (voucher) e `Redirect` (gateway). O cliente já
//! trata as duas, então plugar o Stripe ou o Asaas é registrar um provedor — não
//! reescrever tela.

pub mod voucher;

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use error_core::AppError;
use std::sync::Arc;
use uuid::Uuid;

/// O que se sabe sobre a cobrança no momento de iniciá-la.
#[derive(Debug, Clone)]
pub struct DadosCobranca {
    /// Tenant já criado, ainda inativo, aguardando a confirmação.
    pub tenant_id: Uuid,
    pub plan_id: i32,
    pub email: String,
    /// Valor digitado pelo usuário para este provedor — o código, no caso do
    /// voucher. Vazio para provedores que não pedem nada (o gateway leva o
    /// cliente para fora e volta pelo webhook).
    pub credencial: String,
    /// Origem da tentativa, registrada junto ao resgate para investigar abuso.
    pub ip: String,
    pub traceparent: String,
}

/// Como a confirmação chega para um provedor.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ModoConfirmacao {
    /// Resposta imediata: o provedor decide na própria chamada (voucher).
    Imediata,
    /// O usuário sai para pagar e a confirmação chega depois (gateway/webhook).
    /// O cliente acompanha por `GetSignupStatus`.
    Assincrona,
}

/// O que o cliente precisa saber para desenhar a opção na tela — sem conhecer
/// nenhum provedor por nome. É isto que faz a tela de pagamento sobreviver à
/// entrada de um gateway.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct DescricaoProvedor {
    /// Identificador estável usado na chamada de confirmação (ex.: `voucher`).
    pub id: String,
    /// Nome exibido ao usuário.
    pub rotulo: String,
    /// Frase de apoio abaixo do rótulo.
    pub instrucao: String,
    /// `true` quando há um campo a preencher (o código do voucher).
    pub requer_credencial: bool,
    /// Rótulo do campo, quando houver.
    pub rotulo_credencial: String,
    pub modo: ModoConfirmacao,
}

/// Resultado de iniciar uma cobrança.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IntencaoPagamento {
    /// Pago: a assinatura pode ser ativada agora, até `periodo_fim`.
    Confirmada {
        plan_id: i32,
        periodo_fim: DateTime<Utc>,
        /// Rastro do que confirmou (id do resgate, id da cobrança externa).
        referencia: String,
    },
    /// O usuário precisa concluir o pagamento fora do app.
    Redirect { url: String, referencia: String },
    /// Recusado por regra de negócio — não é erro de infraestrutura. A
    /// `mensagem` já vem pronta para o usuário final; o `motivo` é o
    /// discriminante estável para log e auditoria.
    Recusada { motivo: String, mensagem: String },
}

/// Um meio de pagamento plugável.
#[async_trait]
pub trait ProvedorPagamento: Send + Sync {
    fn descricao(&self) -> DescricaoProvedor;

    /// Inicia (e, quando o modo é imediato, conclui) a cobrança.
    async fn iniciar(&self, dados: &DadosCobranca) -> Result<IntencaoPagamento, AppError>;
}

/// Provedores habilitados nesta instalação.
///
/// A ordem é a de exibição. Hoje nasce só com o voucher; quando houver gateway,
/// o registro é montado a partir da configuração e o resto do sistema não muda.
#[derive(Clone, Default)]
pub struct RegistroProvedores {
    provedores: Vec<Arc<dyn ProvedorPagamento>>,
}

impl RegistroProvedores {
    pub fn novo(provedores: Vec<Arc<dyn ProvedorPagamento>>) -> Self {
        Self { provedores }
    }

    /// Descrições para o cliente montar a tela de pagamento.
    pub fn descrever(&self) -> Vec<DescricaoProvedor> {
        self.provedores.iter().map(|p| p.descricao()).collect()
    }

    /// Resolve o provedor pelo `id` da descrição. `None` = id desconhecido, que
    /// a borda traduz em erro de validação — nunca em "escolhe qualquer um".
    pub fn obter(&self, id: &str) -> Option<Arc<dyn ProvedorPagamento>> {
        self.provedores
            .iter()
            .find(|p| p.descricao().id == id)
            .cloned()
    }

    pub fn vazio(&self) -> bool {
        self.provedores.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct ProvedorFalso(&'static str);

    #[async_trait]
    impl ProvedorPagamento for ProvedorFalso {
        fn descricao(&self) -> DescricaoProvedor {
            DescricaoProvedor {
                id: self.0.to_string(),
                rotulo: "Falso".into(),
                instrucao: String::new(),
                requer_credencial: false,
                rotulo_credencial: String::new(),
                modo: ModoConfirmacao::Imediata,
            }
        }

        async fn iniciar(&self, _dados: &DadosCobranca) -> Result<IntencaoPagamento, AppError> {
            unreachable!("teste só exercita o registro")
        }
    }

    #[test]
    fn resolve_provedor_por_id_e_preserva_a_ordem_de_exibicao() {
        let registro = RegistroProvedores::novo(vec![
            Arc::new(ProvedorFalso("voucher")),
            Arc::new(ProvedorFalso("cartao")),
        ]);

        let ids: Vec<_> = registro.descrever().into_iter().map(|d| d.id).collect();
        assert_eq!(ids, vec!["voucher", "cartao"]);
        assert!(registro.obter("cartao").is_some());
    }

    #[test]
    fn id_desconhecido_nao_cai_em_provedor_arbitrario() {
        let registro = RegistroProvedores::novo(vec![Arc::new(ProvedorFalso("voucher"))]);
        assert!(registro.obter("pix").is_none());
        assert!(!registro.vazio());
        assert!(RegistroProvedores::default().vazio());
    }
}
