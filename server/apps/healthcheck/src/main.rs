//! Sonda de saúde dos serviços Rust, para uso no `healthcheck:` do compose.
//!
//! Existe porque `restart: unless-stopped` só reage a processo que **morre**.
//! Serviço travado — deadlock, pool de conexões esgotado, loop de consumo parado
//! — continua `running` indefinidamente, e a stack fica de pé sem funcionar. O
//! `ia_engine` já resolvia isso com `grpc.health.v1`; este binário leva o mesmo
//! tratamento aos oito serviços Rust.
//!
//! Dois modos, porque há dois tipos de serviço:
//!
//!   healthcheck rpc <SERVICO> [prazo_s]
//!       Para quem atende no `transport::Server` (data_postgres, data_redis,
//!       data_storage, data_whatsapp, control_plane, runtime_api): troca
//!       PING→PONG no endpoint que o próprio serviço abriu.
//!
//!   healthcheck batimento <ARQUIVO> [idade_max_s]
//!       Para quem não atende ninguém (worker): confere se o loop de consumo
//!       registrou passagem dentro da janela.
//!
//! Sai com 0 (saudável) ou 1 (não saudável) e imprime o motivo no stderr — o
//! `docker inspect` guarda essa saída em `.State.Health.Log`, que é por onde se
//! descobre o que houve depois do fato.

use std::time::Duration;

fn uso() -> ! {
    eprintln!(
        "uso:\n  healthcheck rpc <SERVICO> [prazo_s]\n  healthcheck batimento <ARQUIVO> [idade_max_s]"
    );
    std::process::exit(2);
}

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 {
        uso();
    }

    match args[1].as_str() {
        "rpc" => {
            let servico = &args[2];
            let prazo = args
                .get(3)
                .and_then(|s| s.parse().ok())
                .map(Duration::from_secs)
                .unwrap_or(Duration::from_secs(3));

            match transport::sondar_servico(servico, prazo).await {
                Ok(()) => std::process::exit(0),
                Err(e) => {
                    eprintln!("{servico}: sonda falhou: {e}");
                    std::process::exit(1);
                }
            }
        }
        "batimento" => {
            let arquivo = &args[2];
            let idade_max: u64 = args.get(3).and_then(|s| s.parse().ok()).unwrap_or(60);

            match transport::liveness::idade_segundos(arquivo) {
                Some(idade) if idade <= idade_max => std::process::exit(0),
                Some(idade) => {
                    eprintln!("batimento parado ha {idade}s (limite {idade_max}s)");
                    std::process::exit(1);
                }
                None => {
                    // Sem arquivo não é "serviço novo": o `start_period` do
                    // compose é quem cobre a janela de subida.
                    eprintln!("sem batimento em {arquivo}");
                    std::process::exit(1);
                }
            }
        }
        _ => uso(),
    }
}
