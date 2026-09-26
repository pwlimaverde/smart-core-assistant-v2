//! Registro rastreável de erros — vincula `AppError` a `trace_id` e `tenant_id`
//! e emite log estruturado via `tracing` sem vazar PII ou detalhes internos.

use tracing::{error, warn};

use crate::{
    code::ErrorCode,
    error::{AppError, Severity},
};

/// Contexto de correlação obrigatório para registrar um erro rastreável.
pub struct ErrorContext {
    /// ID de rastreamento distribuído (gerado pela `observability`).
    pub trace_id: String,
    /// Identificador do tenant (multi-tenancy).
    pub tenant_id: String,
}

/// Estrutura completa do registro de erro — aparece no JSON de log.
#[derive(Debug)]
pub struct ErrorReport {
    pub error_code: ErrorCode,
    pub severity: Severity,
    pub trace_id: String,
    pub tenant_id: String,
    /// Mensagem segura para o cliente (nunca detalhe interno).
    pub public_message: String,
    /// Contexto adicional para diagnóstico interno (opcional).
    pub context: Option<String>,
}

impl ErrorReport {
    /// Constrói um `ErrorReport` a partir do `AppError` e do contexto de correlação.
    pub fn from_error(err: &AppError, ctx: &ErrorContext) -> Self {
        Self {
            error_code: err.code(),
            severity: err.severity(),
            trace_id: ctx.trace_id.clone(),
            tenant_id: ctx.tenant_id.clone(),
            public_message: err.public_message().to_owned(),
            context: None,
        }
    }

    /// Adiciona contexto interno de diagnóstico (não exposto ao cliente).
    pub fn with_context(mut self, ctx: impl Into<String>) -> Self {
        self.context = Some(ctx.into());
        self
    }
}

/// Registra um `AppError` via `tracing` com campos de correlação.
///
/// - Usa `error!()` para `Severity::Error` e `warn!()` para `Severity::Warn`.
/// - Nunca inclui PII, stack trace ou mensagem interna no campo `message`.
pub fn registrar(err: &AppError, ctx: &ErrorContext) {
    registrar_no_rpc(err, ctx, "");
}

/// Igual a [`registrar`], dizendo também **qual RPC** falhou e, quando a culpa
/// é da entrada (validação, conflito), **por quê**.
///
/// Sem isso o log dizia só "Dados de entrada inválidos." — sem a operação e sem
/// o motivo, um erro visto no teste não levava a lugar nenhum. O motivo passa por
/// [`detalhe_sem_dados`]: é texto escrito pelo desenvolvedor ("id ausente",
/// "missing field `nome`"), mas a mensagem do serde ecoa o valor recebido, e
/// esse valor pode ser dado pessoal. Erros de infraestrutura continuam sem
/// detalhe: ali a mensagem vem do driver e pode trazer SQL e valores.
pub fn registrar_no_rpc(err: &AppError, ctx: &ErrorContext, rpc: &str) {
    let report = ErrorReport::from_error(err, ctx);
    let detalhe = match err {
        AppError::Validation(m) | AppError::Conflict(m) => detalhe_sem_dados(m),
        _ => String::new(),
    };

    match report.severity {
        Severity::Error => {
            error!(
                error_code = %report.error_code,
                trace_id   = %report.trace_id,
                tenant_id  = %report.tenant_id,
                message    = %report.public_message,
                rpc        = %rpc,
                "Erro de aplicação registrado"
            );
        }
        Severity::Warn => {
            warn!(
                error_code = %report.error_code,
                trace_id   = %report.trace_id,
                tenant_id  = %report.tenant_id,
                message    = %report.public_message,
                rpc        = %rpc,
                detalhe    = %detalhe,
                "Aviso de aplicação registrado"
            );
        }
    }
}

/// Motivo de erro seguro para log: sem valor entre aspas, sem sequência longa
/// de dígitos (telefone, CPF, documento) e sem e-mail, com teto de 200
/// caracteres. Nomes de campo entre crases ficam, porque são eles que dizem o
/// que faltou.
pub fn detalhe_sem_dados(msg: &str) -> String {
    fn despejar(saida: &mut String, digitos: &mut String) {
        if digitos.len() >= 6 {
            saida.push('…');
        } else {
            saida.push_str(digitos);
        }
        digitos.clear();
    }

    let mut saida = String::with_capacity(msg.len().min(200));
    let mut digitos = String::new();
    let mut entre_aspas = false;
    for c in msg.chars() {
        if c == '"' {
            despejar(&mut saida, &mut digitos);
            entre_aspas = !entre_aspas;
            saida.push('"');
            if entre_aspas {
                saida.push('…');
            }
            continue;
        }
        if entre_aspas {
            continue;
        }
        if c.is_ascii_digit() {
            digitos.push(c);
            continue;
        }
        despejar(&mut saida, &mut digitos);
        saida.push(c);
    }
    despejar(&mut saida, &mut digitos);

    let sem_email: Vec<&str> = saida
        .split(' ')
        .map(|palavra| {
            if palavra.contains('@') {
                "…@…"
            } else {
                palavra
            }
        })
        .collect();
    sem_email.join(" ").chars().take(200).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detalhe_mantem_o_motivo_e_esconde_o_valor() {
        assert_eq!(detalhe_sem_dados("id ausente"), "id ausente");
        assert_eq!(
            detalhe_sem_dados("missing field `nome` at line 1 column 20"),
            "missing field `nome` at line 1 column 20"
        );
        assert_eq!(
            detalhe_sem_dados("invalid type: string \"Maria da Silva\", expected i64"),
            "invalid type: string \"…\", expected i64"
        );
    }

    #[test]
    fn detalhe_esconde_telefone_e_email_sem_aspas() {
        assert_eq!(
            detalhe_sem_dados("contato 5588981061874 já existe"),
            "contato … já existe"
        );
        assert_eq!(
            detalhe_sem_dados("email joao@exemplo.com inválido"),
            "email …@… inválido"
        );
    }

    #[test]
    fn detalhe_tem_teto() {
        assert_eq!(detalhe_sem_dados(&"a".repeat(500)).chars().count(), 200);
    }

    #[test]
    fn test_error_report_creation() {
        let err = AppError::Auth("token expirado".to_string());
        let ctx = ErrorContext {
            trace_id: "trace-id-123".to_string(),
            tenant_id: "tenant-id-456".to_string(),
        };

        // Testa construção do ErrorReport
        let report = ErrorReport::from_error(&err, &ctx);
        assert_eq!(report.error_code, ErrorCode::AuthExpiredToken);
        assert_eq!(report.severity, Severity::Warn);
        assert_eq!(report.trace_id, "trace-id-123");
        assert_eq!(report.tenant_id, "tenant-id-456");
        assert_eq!(report.public_message, "Credencial inválida ou ausente.");
        assert!(report.context.is_none());

        // Testa builder com contexto
        let report_with_ctx = report.with_context("contexto interno de teste");
        assert_eq!(
            report_with_ctx.context.unwrap(),
            "contexto interno de teste"
        );
    }

    #[test]
    fn test_registrar_flows() {
        // Garante que a função registrar executa sem erros/pânico para ambas severidades
        let ctx = ErrorContext {
            trace_id: "trace-id-123".to_string(),
            tenant_id: "tenant-id-456".to_string(),
        };

        let err_warn = AppError::Auth("token expirado".to_string());
        let err_error = AppError::Database("conexão falhou".to_string());

        // Deve registrar logs estruturados no tracing sem causar pânico
        registrar(&err_warn, &ctx);
        registrar(&err_error, &ctx);
    }
}
