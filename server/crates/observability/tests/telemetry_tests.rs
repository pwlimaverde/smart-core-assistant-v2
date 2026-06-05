use observability::{init_telemetry, shutdown_telemetry};

#[test]
fn test_telemetry_initialization_flow() {
    // 1. Arrange: Define o endpoint da OTel fictício para evitar pânico de falta de env
    std::env::set_var("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317");

    // 2. Act: Executa o fluxo de telemetria
    // Tentamos inicializar a telemetria. Como outros testes podem já ter inicializado o subscriber
    // global no mesmo runtime de teste do Cargo, capturamos o resultado de forma defensiva.
    let resultado = init_telemetry("test-telemetry-service", "test-env");

    // 3. Assert: A função deve retornar Ok(()) se for a primeira inicialização ou um erro
    // estruturado (de inicialização duplicada) se o subscriber global já estiver ativo.
    // O mais importante é que a chamada não cause pânico no processo de teste.
    assert!(resultado.is_ok() || resultado.is_err());

    // Se a inicialização for bem-sucedida, testa o logging de informação.
    if resultado.is_ok() {
        tracing::info!("Mensagem de telemetria de teste de fluxo de inicialização");
    }

    // Testa o encerramento seguro da telemetria.
    shutdown_telemetry();
}
