// observability/src/ciclo_de_vida.rs  (comentários em pt-br)
//
// Três buracos do ciclo de vida dos serviços, fechados aqui:
//
// 1. **Panic invisível.** Um panic dentro de `tokio::spawn` mata só aquela task.
//    O processo segue vivo, o Docker vê `running`, e a funcionalidade daquela
//    task simplesmente deixou de existir. Sem hook, nem o log estruturado sai
//    direito — o default do Rust escreve texto solto no stderr, que no Loki vira
//    uma linha sem campos.
//
// 2. **Task crítica que termina em silêncio.** Os loops de background (relay do
//    outbox, consumidor de auditoria, reprocessamento da PEL) são infinitos por
//    natureza: se um deles retorna, é anomalia. Antes, retornavam para um
//    `tokio::spawn` que ninguém observava.
//
// 3. **Parada bruta.** Nenhum dos serviços escutava SIGTERM. Todo deploy matava
//    conexões em voo no meio do processamento e, de quebra, perdia os spans e
//    logs que ainda não tinham sido exportados — justamente os do encerramento.

use crate::AuditLogger;

/// Instala o hook global de panic: registra o evento como log estruturado antes
/// de deixar o comportamento padrão seguir.
///
/// Deliberadamente **não** aborta o processo. Abortar em qualquer panic
/// transformaria um panic num handler de requisição — disparável por uma
/// requisição malformada — em queda do serviço inteiro. Para a task de
/// background, cujo panic é fatal de fato, quem trata é [`supervisionar`].
pub fn instalar_hook_de_panic(servico: &'static str) {
    let anterior = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let mensagem = info
            .payload()
            .downcast_ref::<&str>()
            .map(|s| s.to_string())
            .or_else(|| info.payload().downcast_ref::<String>().cloned())
            .unwrap_or_else(|| "panic sem mensagem".to_string());

        let local = info
            .location()
            .map(|l| format!("{}:{}", l.file(), l.line()))
            .unwrap_or_else(|| "local desconhecido".to_string());

        tracing::error!(
            servico = %servico,
            local = %local,
            mensagem = %mensagem,
            "PANIC em task do servico"
        );

        anterior(info);
    }));
}

/// Roda uma task de background cujo término é, por si só, uma falha do serviço.
///
/// Se a task retorna ou entra em pânico, o evento é auditado e o processo é
/// encerrado com código 1 — que é o comportamento **desejado**: o container
/// morre, o Docker reinicia, e o serviço volta com todos os loops de pé. A
/// alternativa (seguir vivo com um loop a menos) é a falha silenciosa que este
/// módulo existe para eliminar.
pub fn supervisionar<F>(nome: &'static str, servico: &'static str, audit: AuditLogger, tarefa: F)
where
    F: std::future::Future<Output = ()> + Send + 'static,
{
    tokio::spawn(async move {
        let resultado = tokio::spawn(tarefa).await;

        let motivo = match resultado {
            Ok(()) => "a task retornou (loops de background nao deveriam terminar)".to_string(),
            Err(e) if e.is_panic() => "a task entrou em panico".to_string(),
            Err(e) => format!("a task foi encerrada: {e}"),
        };

        tracing::error!(
            servico = %servico, tarefa = %nome, motivo = %motivo,
            "Task critica encerrada; derrubando o processo para que o supervisor o reinicie"
        );
        audit.error_global(
            "service.tarefa_critica_encerrada",
            &format!("Task critica '{nome}' do servico {servico} encerrou: {motivo}"),
            serde_json::json!({ "servico": servico, "tarefa": nome, "motivo": motivo }),
            None,
            None,
            None,
        );

        // Dá um instante para a auditoria sair pelo barramento e para os spans
        // pendentes serem exportados. Sem isso, o evento que explica a queda
        // morre junto com o processo.
        tokio::time::sleep(std::time::Duration::from_millis(500)).await;
        crate::shutdown_telemetry();
        std::process::exit(1);
    });
}

/// Resolve quando chega SIGTERM (o que o `docker stop` manda) ou Ctrl+C.
///
/// SIGTERM é o que importa em produção: sem escutá-lo, o Docker espera o prazo
/// de graça inteiro e mata o processo no braço — perdendo o que estava em voo.
pub async fn aguardar_sinal_de_parada() {
    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};
        let mut sigterm = match signal(SignalKind::terminate()) {
            Ok(s) => s,
            Err(e) => {
                tracing::error!(erro = ?e, "Nao foi possivel registrar SIGTERM; so Ctrl+C");
                let _ = tokio::signal::ctrl_c().await;
                return;
            }
        };
        tokio::select! {
            _ = sigterm.recv() => tracing::info!("SIGTERM recebido; encerrando."),
            _ = tokio::signal::ctrl_c() => tracing::info!("Ctrl+C recebido; encerrando."),
        }
    }
    #[cfg(not(unix))]
    {
        let _ = tokio::signal::ctrl_c().await;
        tracing::info!("Ctrl+C recebido; encerrando.");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hook_de_panic_nao_engole_o_panic() {
        // O hook enriquece o registro, mas o panic tem de continuar sendo panic:
        // engoli-lo transformaria falha em corrupção silenciosa.
        instalar_hook_de_panic("teste");
        let resultado = std::panic::catch_unwind(|| panic!("falha proposital"));
        assert!(resultado.is_err());
        let _ = std::panic::take_hook();
    }

    #[tokio::test]
    async fn sinal_de_parada_nao_resolve_sozinho() {
        // Sem sinal nenhum, a espera precisa ficar pendente — se resolvesse na
        // hora, todo serviço encerraria logo após subir.
        let esperou = tokio::time::timeout(
            std::time::Duration::from_millis(150),
            aguardar_sinal_de_parada(),
        )
        .await;
        assert!(
            esperou.is_err(),
            "a espera pelo sinal deveria ficar pendente"
        );
    }
}
