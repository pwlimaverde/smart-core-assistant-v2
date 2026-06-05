//! Testes de integração entre `registrar()` e o `tracing_subscriber` real.
//!
//! Valida que o log estruturado emitido carrega os campos de correlação
//! (`error_code`, `trace_id`, `tenant_id`) e que nunca vaza PII nem detalhes
//! internos — confirmando a integração com a crate `observability`.

use std::io;
use std::sync::{Arc, Mutex};

use error_core::{registrar, AppError, ErrorContext};
use tracing::subscriber::with_default;
use tracing_subscriber::fmt::MakeWriter;

/// Writer em memória compartilhado para capturar a saída do subscriber no teste.
#[derive(Clone, Default)]
struct BufferWriter(Arc<Mutex<Vec<u8>>>);

impl BufferWriter {
    /// Devolve o conteúdo capturado como `String`.
    fn captured(&self) -> String {
        let buf = self.0.lock().expect("lock do buffer de log");
        String::from_utf8(buf.clone()).expect("log capturado deve ser UTF-8")
    }
}

impl io::Write for BufferWriter {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        self.0
            .lock()
            .expect("lock do buffer de log")
            .extend_from_slice(buf);
        Ok(buf.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

impl<'a> MakeWriter<'a> for BufferWriter {
    type Writer = BufferWriter;

    fn make_writer(&'a self) -> Self::Writer {
        self.clone()
    }
}

/// Executa `f` com um subscriber `fmt` capturando o log e devolve o texto emitido.
fn capturar_log<F: FnOnce()>(f: F) -> String {
    let writer = BufferWriter::default();
    let subscriber = tracing_subscriber::fmt()
        .with_writer(writer.clone())
        .with_ansi(false)
        .with_max_level(tracing::Level::TRACE)
        .finish();

    with_default(subscriber, f);
    writer.captured()
}

#[test]
fn registrar_warn_emite_correlacao_sem_pii() {
    // Auth → Severity::Warn; mensagem interna carrega dados sensíveis que NÃO podem vazar.
    let logged = capturar_log(|| {
        let err = AppError::Auth("usuário joao@empresa.com token eyJhbG".to_owned());
        let ctx = ErrorContext {
            trace_id: "int-trace-001".to_owned(),
            tenant_id: "tenant-test".to_owned(),
        };
        registrar(&err, &ctx);
    });

    // Correlação e código estável presentes.
    assert!(
        logged.contains("int-trace-001"),
        "log deve conter trace_id: {logged}"
    );
    assert!(
        logged.contains("tenant-test"),
        "log deve conter tenant_id: {logged}"
    );
    assert!(
        logged.contains("AUTH_INVALID_TOKEN"),
        "log deve conter error_code: {logged}"
    );
    assert!(
        logged.contains("WARN"),
        "Auth deve logar em nível WARN: {logged}"
    );

    // PII / segredos nunca aparecem.
    assert!(
        !logged.contains("joao@empresa.com"),
        "PII vazou no log: {logged}"
    );
    assert!(!logged.contains("eyJhbG"), "token vazou no log: {logged}");
}

#[test]
fn registrar_error_emite_nivel_error() {
    // Database (conexão) → Severity::Error.
    let logged = capturar_log(|| {
        let err = AppError::Database("SELECT secreto falhou: conexão recusada".to_owned());
        let ctx = ErrorContext {
            trace_id: "int-trace-002".to_owned(),
            tenant_id: "tenant-test".to_owned(),
        };
        registrar(&err, &ctx);
    });

    assert!(
        logged.contains("ERROR"),
        "falha de conexão deve logar em nível ERROR: {logged}"
    );
    assert!(
        logged.contains("DB_CONNECTION_FAILED"),
        "log deve conter error_code: {logged}"
    );
    assert!(
        logged.contains("int-trace-002"),
        "log deve conter trace_id: {logged}"
    );
    // Detalhe interno da query não pode vazar — só a public_message.
    assert!(
        !logged.contains("SELECT secreto"),
        "detalhe interno vazou no log: {logged}"
    );
    assert!(
        logged.contains("Erro ao acessar o banco de dados."),
        "public_message ausente: {logged}"
    );
}
