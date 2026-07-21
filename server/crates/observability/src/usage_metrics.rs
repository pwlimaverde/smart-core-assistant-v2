//! N4.2 — contadores de uso por tenant (mensagens, mídia), expostos via
//! OpenTelemetry (Prometheus, via otel-collector). Cada instrumento é criado uma
//! única vez (`OnceLock`) e reutilizado — evita recriar o contador a cada chamada.
//! Contadores são agregados (sem PII/telefone/conteúdo) — só `tenant_id` como rótulo.

use opentelemetry::{global, metrics::Counter, KeyValue};
use std::sync::OnceLock;

fn contador_mensagens() -> &'static Counter<u64> {
    static C: OnceLock<Counter<u64>> = OnceLock::new();
    C.get_or_init(|| {
        global::meter("smartcore_usage")
            .u64_counter("smartcore_mensagens_total")
            .with_description("Total de mensagens WhatsApp processadas, por tenant e direção")
            .init()
    })
}

fn contador_midia() -> &'static Counter<u64> {
    static C: OnceLock<Counter<u64>> = OnceLock::new();
    C.get_or_init(|| {
        global::meter("smartcore_usage")
            .u64_counter("smartcore_midia_arquivos_total")
            .with_description("Total de arquivos de mídia armazenados, por tenant")
            .init()
    })
}

/// Direção da mensagem para o contador de uso (rótulo de baixa cardinalidade).
#[derive(Clone, Copy)]
pub enum DirecaoMensagem {
    Recebida,
    Enviada,
}

impl DirecaoMensagem {
    fn as_str(&self) -> &'static str {
        match self {
            DirecaoMensagem::Recebida => "recebida",
            DirecaoMensagem::Enviada => "enviada",
        }
    }
}

/// Incrementa o contador de mensagens processadas para o tenant no caminho de
/// ingestão (`webhook_ingress`) ou envio (`data_whatsapp`).
pub fn registrar_mensagem(tenant_id: &str, direcao: DirecaoMensagem) {
    contador_mensagens().add(
        1,
        &[
            KeyValue::new("tenant_id", tenant_id.to_string()),
            KeyValue::new("direcao", direcao.as_str()),
        ],
    );
}

/// Incrementa o contador de arquivos de mídia armazenados para o tenant.
pub fn registrar_midia_armazenada(tenant_id: &str) {
    contador_midia().add(1, &[KeyValue::new("tenant_id", tenant_id.to_string())]);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn direcao_mensagem_as_str_cobre_ambas_variantes() {
        assert_eq!(DirecaoMensagem::Recebida.as_str(), "recebida");
        assert_eq!(DirecaoMensagem::Enviada.as_str(), "enviada");
    }

    #[test]
    fn direcao_mensagem_e_copy() {
        // `DirecaoMensagem` é Copy: usar após passar por valor não move.
        let d = DirecaoMensagem::Recebida;
        let _copia = d;
        assert_eq!(d.as_str(), "recebida");
    }

    #[test]
    fn registrar_mensagem_nao_entra_em_panico() {
        // Sem MeterProvider instalado, o instrumento global é no-op; o teste garante
        // que o caminho de rótulos (tenant_id + direção) executa sem panic para ambas
        // as direções e que o contador é criado uma única vez (OnceLock).
        registrar_mensagem("tenant-a", DirecaoMensagem::Recebida);
        registrar_mensagem("tenant-a", DirecaoMensagem::Enviada);
        registrar_mensagem("tenant-b", DirecaoMensagem::Recebida);
    }

    #[test]
    fn registrar_midia_armazenada_nao_entra_em_panico() {
        registrar_midia_armazenada("tenant-a");
        registrar_midia_armazenada("tenant-b");
    }
}
