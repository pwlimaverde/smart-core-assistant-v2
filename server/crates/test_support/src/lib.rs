//! Apoio aos testes de integração do Smart Core Assistant v2.
//!
//! Os bancos (PostgreSQL e Redis) rodam no Docker da Hostinger e são acessados
//! localmente através de um túnel SSH (ver `infra/tunnel.ps1`), que mapeia:
//!   - `localhost:5434` -> Postgres remoto
//!   - `localhost:6380` -> Redis remoto
//!
//! Antes, era preciso abrir o túnel manualmente antes de rodar `cargo test`.
//! Este módulo torna isso automático e idempotente: na primeira vez que um teste
//! precisa do banco, garantimos que o túnel está de pé (subindo o `ssh` se preciso).
//! Assim basta `cd server && cargo test`.

use std::collections::HashMap;
use std::net::{SocketAddr, TcpStream};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::Once;
use std::time::{Duration, Instant};

/// Porta local do Postgres exposta pelo túnel (deve bater com o `DATABASE_URL`).
const PORTA_POSTGRES_LOCAL: u16 = 5434;
/// Porta local do Redis exposta pelo túnel (deve bater com o `REDIS_URL`).
const PORTA_REDIS_LOCAL: u16 = 6380;

/// Executado no máximo uma vez por processo de teste (cada binário de teste do
/// Cargo é um processo separado, então o primeiro teste de cada um valida o túnel).
static TUNEL_ONCE: Once = Once::new();

/// Garante que o túnel SSH para a Hostinger esteja ativo antes de qualquer teste
/// que dependa do banco. É barato quando o túnel já está aberto (apenas um probe
/// de TCP) e idempotente entre múltiplas chamadas no mesmo processo.
///
/// Em caso de falha (não conseguir subir o túnel), aborta com mensagem clara —
/// é melhor o teste falhar explicando o motivo do que pendurar numa conexão.
pub fn ensure_tunnel() {
    TUNEL_ONCE.call_once(|| {
        if porta_aberta(PORTA_POSTGRES_LOCAL) {
            // Túnel já está de pé (provavelmente aberto manualmente ou por outro
            // binário de teste anterior). Nada a fazer.
            return;
        }

        match iniciar_tunnel() {
            Ok(()) => aguardar_tunnel(),
            Err(motivo) => panic!(
                "Não foi possível iniciar o túnel SSH automaticamente para os testes: {motivo}.\n\
                 Alternativa: abra o túnel manualmente em outro terminal com `cd infra; .\\tunnel.ps1`."
            ),
        }
    });
}

/// Testa se uma porta TCP local está aceitando conexões (com timeout curto).
fn porta_aberta(porta: u16) -> bool {
    let endereco = SocketAddr::from(([127, 0, 0, 1], porta));
    TcpStream::connect_timeout(&endereco, Duration::from_millis(500)).is_ok()
}

/// Sobe o processo `ssh` em background, mapeando as portas do Docker remoto para
/// localhost. O processo fica rodando após o término do teste (assim como o túnel
/// manual), de modo que execuções e binários de teste seguintes o reaproveitam.
fn iniciar_tunnel() -> Result<(), String> {
    let env = carregar_env_deploy()?;

    let host = env
        .get("HOSTINGER_SSH_HOST")
        .ok_or("HOSTINGER_SSH_HOST ausente em infra/.env.deploy")?;
    let user = env
        .get("HOSTINGER_SSH_USER")
        .ok_or("HOSTINGER_SSH_USER ausente em infra/.env.deploy")?;
    let ssh_port = env.get("HOSTINGER_SSH_PORT").map(String::as_str).unwrap_or("22");
    let postgres_port = env.get("POSTGRES_PORT").map(String::as_str).unwrap_or("5434");
    let redis_port = env.get("REDIS_PORT").map(String::as_str).unwrap_or("6380");

    let mut cmd = Command::new("ssh");
    cmd.arg("-p")
        .arg(ssh_port)
        .arg("-N")
        // Não pendurar pedindo senha/confirmação: usa chave; falha rápido se não der.
        .arg("-o")
        .arg("BatchMode=yes")
        .arg("-o")
        .arg("StrictHostKeyChecking=accept-new")
        .arg("-o")
        .arg("ExitOnForwardFailure=yes")
        .arg("-o")
        .arg("ServerAliveInterval=30")
        // Mapeia Postgres e Redis remotos para as portas locais que os testes usam.
        .arg("-L")
        .arg(format!("{PORTA_POSTGRES_LOCAL}:localhost:{postgres_port}"))
        .arg("-L")
        .arg(format!("{PORTA_REDIS_LOCAL}:localhost:{redis_port}"))
        .arg(format!("{user}@{host}"))
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());

    // Usa a chave dedicada quando informada (evita depender do agente SSH).
    if let Some(identity) = env.get("HOSTINGER_SSH_IDENTITY_FILE") {
        if !identity.is_empty() {
            cmd.arg("-i").arg(identity);
        }
    }

    // Desacopla o processo do binário de teste para que o túnel sobreviva ao fim
    // dos testes (DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP).
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x0000_0008 | 0x0000_0200);
    }

    cmd.spawn()
        .map(|_filho| ())
        .map_err(|e| format!("falha ao executar `ssh`: {e}"))
}

/// Aguarda o túnel ficar pronto (porta do Postgres aceitando conexões), com timeout.
fn aguardar_tunnel() {
    let inicio = Instant::now();
    let limite = Duration::from_secs(25);
    while inicio.elapsed() < limite {
        if porta_aberta(PORTA_POSTGRES_LOCAL) {
            return;
        }
        std::thread::sleep(Duration::from_millis(300));
    }
    panic!(
        "O túnel SSH foi iniciado mas a porta local {PORTA_POSTGRES_LOCAL} não respondeu em {}s.\n\
         Verifique as credenciais/chave em infra/.env.deploy ou abra o túnel manualmente com `cd infra; .\\tunnel.ps1`.",
        limite.as_secs()
    );
}

/// Procura `infra/.env.deploy` subindo a árvore de diretórios a partir do cwd do
/// teste (que é a raiz da crate em execução) e o carrega num mapa chave=valor.
fn carregar_env_deploy() -> Result<HashMap<String, String>, String> {
    let caminho = localizar_env_deploy()
        .ok_or("infra/.env.deploy não encontrado (necessário para abrir o túnel SSH)")?;
    let conteudo = std::fs::read_to_string(&caminho)
        .map_err(|e| format!("falha ao ler {}: {e}", caminho.display()))?;

    let mut mapa = HashMap::new();
    for linha in conteudo.lines() {
        let linha = linha.trim();
        if linha.is_empty() || linha.starts_with('#') {
            continue;
        }
        if let Some((chave, valor)) = linha.split_once('=') {
            let chave = chave.trim().to_string();
            let valor = valor.trim().trim_matches('"').trim_matches('\'').to_string();
            mapa.insert(chave, valor);
        }
    }
    Ok(mapa)
}

/// Sobe na hierarquia procurando por `infra/.env.deploy`.
fn localizar_env_deploy() -> Option<PathBuf> {
    let mut dir = std::env::current_dir().ok()?;
    loop {
        let candidato = dir.join("infra").join(".env.deploy");
        if candidato.exists() {
            return Some(candidato);
        }
        if !dir.pop() {
            return None;
        }
    }
}
