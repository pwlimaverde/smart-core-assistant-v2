// transport/src/liveness.rs  (comentários em pt-br)
//
// Batimento de vida para serviços que NÃO atendem requisições.
//
// Quem serve o `transport::Server` é sondável de fora: basta um PING. O `worker`
// não serve nada — ele só consome do barramento —, então "porta respondendo" não
// existe como sinal. Um worker com o loop de consumo travado continua sendo um
// processo saudável para o Docker, e as mensagens simplesmente param de ser
// processadas sem que nada acuse.
//
// A saída é o inverso: o próprio loop registra que deu uma volta, tocando um
// arquivo. A sonda externa lê a idade desse arquivo. O ponto importante é ONDE o
// batimento é registrado — dentro do loop de consumo, depois do read do Redis.
// Um batimento disparado por uma task própria de timer continuaria fresco com o
// consumo parado, que é justamente a falha que queremos enxergar.

use std::sync::atomic::{AtomicU64, Ordering};

/// Piso entre duas escritas. O loop do consumidor gira a cada ~1s; sem o piso
/// seriam 86 mil escritas por dia num arquivo que ninguém lê nesse ritmo.
const INTERVALO_MIN_SEGUNDOS: u64 = 5;

static ULTIMO_BATIMENTO: AtomicU64 = AtomicU64::new(0);

fn agora_epoch() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// Caminho do arquivo de batimento, quando o serviço foi configurado para tal.
/// Sem a variável, o batimento é inteiramente inerte — serviços que se sondam
/// por PING não pagam nada por isso.
pub fn caminho() -> Option<String> {
    std::env::var("SMARTCORE_LIVENESS_FILE")
        .ok()
        .filter(|s| !s.is_empty())
}

/// Registra que o loop deu mais uma volta. Silencioso por opção: falha de
/// escrita aqui não pode derrubar o processamento de mensagens, e o próprio
/// envelhecimento do arquivo já denuncia o problema à sonda.
pub fn bater() {
    let Some(caminho) = caminho() else {
        return;
    };

    let agora = agora_epoch();
    let anterior = ULTIMO_BATIMENTO.load(Ordering::Relaxed);
    if agora.saturating_sub(anterior) < INTERVALO_MIN_SEGUNDOS {
        return;
    }
    // Se outra task passou por aqui no intervalo, ela que escreva — uma só basta.
    if ULTIMO_BATIMENTO
        .compare_exchange(anterior, agora, Ordering::Relaxed, Ordering::Relaxed)
        .is_err()
    {
        return;
    }

    if let Err(e) = std::fs::write(&caminho, agora.to_string()) {
        tracing::debug!(erro = ?e, caminho = %caminho, "Falha ao gravar o batimento de vida");
    }
}

/// Idade do último batimento, em segundos. `None` quando o arquivo não existe
/// ou está ilegível — para a sonda, ambos os casos são falha.
pub fn idade_segundos(caminho: &str) -> Option<u64> {
    let conteudo = std::fs::read_to_string(caminho).ok()?;
    let gravado: u64 = conteudo.trim().parse().ok()?;
    Some(agora_epoch().saturating_sub(gravado))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sem_a_variavel_o_batimento_e_inerte() {
        // Serviços sondados por PING não configuram o arquivo; `bater()` não
        // pode falhar nem criar nada nesse caso.
        std::env::remove_var("SMARTCORE_LIVENESS_FILE");
        assert!(caminho().is_none());
        bater(); // não deve entrar em pânico
    }

    #[test]
    fn idade_de_arquivo_inexistente_e_ausente() {
        // Arquivo que não existe não é "idade zero": é ausência de sinal, e a
        // sonda precisa tratar como falha em vez de como serviço recém-iniciado.
        assert!(idade_segundos("/caminho/que/nao/existe/batimento").is_none());
    }

    #[test]
    fn idade_e_lida_de_volta_do_arquivo_gravado() {
        let dir = std::env::temp_dir().join(format!("smartcore_liveness_{}", uuid::Uuid::now_v7()));
        std::fs::create_dir_all(&dir).unwrap();
        let arquivo = dir.join("batimento");
        std::fs::write(&arquivo, agora_epoch().to_string()).unwrap();

        let idade = idade_segundos(arquivo.to_str().unwrap());

        assert!(idade.is_some());
        assert!(idade.unwrap() <= 2, "batimento recém-gravado deve ser novo");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
