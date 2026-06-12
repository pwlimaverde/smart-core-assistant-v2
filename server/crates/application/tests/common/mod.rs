/// Mutex global usado para serializar a execução de testes de integração
/// que alteram variáveis de ambiente globais de endpoint do processo.
pub static TEST_MUTEX: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());
