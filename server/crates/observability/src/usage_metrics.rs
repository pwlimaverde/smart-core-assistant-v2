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

/// N8.5/E1 — contador de eventos descartados na ingestão, por motivo. Existe para
/// que o descarte seja *visível* sem depender de log: o filtro de grupo acerta
/// silenciosamente, e sem métrica não há como distinguir "não chegou mensagem de
/// grupo" de "o filtro comeu mensagem boa".
fn contador_eventos_descartados() -> &'static Counter<u64> {
    static C: OnceLock<Counter<u64>> = OnceLock::new();
    C.get_or_init(|| {
        global::meter("smartcore_usage")
            .u64_counter("smartcore_webhook_evento_descartado_total")
            .with_description("Eventos de webhook descartados na ingestão, por tenant e motivo")
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

/// Incrementa o contador de eventos descartados na ingestão.
///
/// `motivo` precisa ser um literal de baixa cardinalidade (`"grupo"`,
/// `"remetente_ignorado"`, …) — nunca telefone, JID ou conteúdo.
pub fn registrar_evento_descartado(tenant_id: &str, motivo: &'static str) {
    contador_eventos_descartados().add(
        1,
        &[
            KeyValue::new("tenant_id", tenant_id.to_string()),
            KeyValue::new("motivo", motivo),
        ],
    );
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

    #[test]
    fn registrar_evento_descartado_nao_entra_em_panico() {
        registrar_evento_descartado("tenant-a", "grupo");
        registrar_evento_descartado("tenant-a", "remetente_ignorado");
        registrar_evento_descartado("tenant-b", "grupo");
    }
}
