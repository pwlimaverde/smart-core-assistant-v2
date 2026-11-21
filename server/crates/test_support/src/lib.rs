//! Apoio aos testes de integração do Smart Core Assistant v2.
//!
//! Não há ambiente local (plano `servidor-reestruturacao-dev-prod`, Fase R4):
//! os testes de integração rodam na CI, onde Postgres (pgvector) e Redis sobem
//! como service containers nas portas abaixo (ver `.github/workflows/ci.yml`).
//!
//! Antes, este módulo abria um túnel SSH até o banco da VPS quando a porta
//! local estava fechada. Essa rota deixou de existir — o banco da dev não
//! publica mais porta no host. Agora ele só confere que a infra de teste está
//! de pé e, se não estiver, falha dizendo o que fazer, em vez de pendurar numa
//! conexão.

use std::net::{SocketAddr, TcpStream};
use std::sync::Once;
use std::time::Duration;

/// Porta do Postgres de teste (deve bater com o `DATABASE_URL` da CI).
const PORTA_POSTGRES: u16 = 5434;

/// Executado no máximo uma vez por processo de teste (cada binário de teste do
/// Cargo é um processo separado, então o primeiro teste de cada um verifica).
static VERIFICACAO: Once = Once::new();

/// Garante que o Postgres de teste está aceitando conexões antes de qualquer
/// teste que dependa do banco. Barato (um probe TCP) e idempotente no processo.
///
/// O nome vem da época do túnel SSH e foi mantido para não mexer nos
/// chamadores; hoje a função só verifica — não abre túnel nem processo nenhum.
pub fn ensure_tunnel() {
    VERIFICACAO.call_once(|| {
        assert!(
            porta_aberta(PORTA_POSTGRES),
            "Postgres de teste indisponível em 127.0.0.1:{PORTA_POSTGRES}.\n\
             Os testes de integração rodam na CI (service containers de Postgres e Redis).\n\
             Não existe ambiente local nem túnel para o banco da VPS: faça push e veja o job \
             `Rust — lint e testes`. Para rodar fora da CI, suba um Postgres (pgvector) em \
             {PORTA_POSTGRES} e um Redis em 6379/6380."
        );
    });
}

/// Testa se uma porta TCP local está aceitando conexões (com timeout curto).
fn porta_aberta(porta: u16) -> bool {
    let endereco = SocketAddr::from(([127, 0, 0, 1], porta));
    TcpStream::connect_timeout(&endereco, Duration::from_millis(500)).is_ok()
}
