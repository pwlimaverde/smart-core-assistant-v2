//! Origem da requisição em curso (quem pediu: painel, app ou agente MCP).
//!
//! A borda (`runtime_api`) conhece o `user-agent` de quem chamou, mas monta os
//! envelopes para os serviços de dados em dezenas de lugares — e a maioria
//! esquecia de copiá-lo. Resultado: a mesma ação chegava ao `audit_log` com a
//! origem num caminho e sem ela em outro, e "o que o agente fez" ficava
//! incompleto. Aqui a origem é guardada uma vez por requisição, num
//! task-local, e o [`crate::MuxClient`] a põe em todo envelope que sair sem.

use std::future::Future;

tokio::task_local! {
    static ORIGEM: String;
}

/// Executa `futuro` com `origem` como a origem da requisição em curso.
pub async fn com_origem<F: Future>(origem: String, futuro: F) -> F::Output {
    ORIGEM.scope(origem, futuro).await
}

/// A origem da requisição em curso, se houver e não for vazia.
///
/// Fora de [`com_origem`] (worker, scheduler, tarefas soltas com
/// `tokio::spawn`) não há origem: o envelope segue como foi montado.
pub fn origem_atual() -> Option<String> {
    ORIGEM
        .try_with(|o| o.clone())
        .ok()
        .filter(|o| !o.is_empty())
}

/// Completa o `user_agent` do envelope com a origem em curso, sem sobrescrever.
pub fn completar_origem(env: &mut contracts::Envelope) {
    if env.user_agent.is_empty() {
        if let Some(origem) = origem_atual() {
            env.user_agent = origem;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn envelope_sem_origem_recebe_a_da_requisicao() {
        let env = com_origem("SmartCoreAssistant-MCP/arquivar (grant g)".into(), async {
            let mut env = contracts::Envelope::default();
            completar_origem(&mut env);
            env
        })
        .await;
        assert_eq!(env.user_agent, "SmartCoreAssistant-MCP/arquivar (grant g)");
    }

    #[tokio::test]
    async fn origem_ja_preenchida_nao_e_sobrescrita() {
        let env = com_origem("outra".into(), async {
            let mut env = contracts::Envelope {
                user_agent: "Mozilla/5.0 Flutter".into(),
                ..Default::default()
            };
            completar_origem(&mut env);
            env
        })
        .await;
        assert_eq!(env.user_agent, "Mozilla/5.0 Flutter");
    }

    #[tokio::test]
    async fn fora_de_uma_requisicao_nao_ha_origem() {
        let mut env = contracts::Envelope::default();
        completar_origem(&mut env);
        assert_eq!(env.user_agent, "");
        assert!(origem_atual().is_none());
    }
}
