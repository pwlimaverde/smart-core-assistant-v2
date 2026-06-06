use opentelemetry::propagation::{Extractor, Injector};
use std::collections::HashMap;

/// Carrier para injetar metadados de trace em um HashMap (ex.: Redis Streams, envelopes JSON).
pub struct HashMapCarrier<'a>(pub &'a mut HashMap<String, String>);

impl<'a> Injector for HashMapCarrier<'a> {
    fn set(&mut self, key: &str, value: String) {
        self.0.insert(key.to_string(), value);
    }
}

/// Carrier para extrair metadados de trace a partir de um HashMap.
pub struct HashMapExtractor<'a>(pub &'a HashMap<String, String>);

impl<'a> Extractor for HashMapExtractor<'a> {
    fn get(&self, key: &str) -> Option<&str> {
        self.0.get(key).map(|s| s.as_str())
    }

    fn keys(&self) -> Vec<&str> {
        self.0.keys().map(|s| s.as_str()).collect()
    }
}

// ============================================================
// Helpers Globais de Propagação
// ============================================================

/// Injeta o trace context atual em um HashMap de metadados.
/// Usar antes de despachar eventos no Redis Streams ou payload de mensagens.
pub fn injetar_contexto_atual(metadados: &mut HashMap<String, String>) {
    let context = opentelemetry::Context::current();
    opentelemetry::global::get_text_map_propagator(|propagator| {
        propagator.inject_context(&context, &mut HashMapCarrier(metadados));
    });
}

/// Extrai o trace context a partir de um HashMap de metadados e retorna o Context correspondente.
/// Usar ao receber um evento no Worker ou gateway para restaurar a cadeia de spans.
pub fn extrair_contexto(metadados: &HashMap<String, String>) -> opentelemetry::Context {
    opentelemetry::global::get_text_map_propagator(|propagator| {
        propagator.extract(&HashMapExtractor(metadados))
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use opentelemetry::global;
    use opentelemetry::trace::{
        SpanContext, SpanId, TraceContextExt, TraceFlags, TraceId, TraceState,
    };
    use opentelemetry_sdk::propagation::TraceContextPropagator;
    use std::collections::HashMap;

    #[test]
    fn test_trace_context_propagation_hashmap() {
        // Garante que o propagador W3C TraceContext está registrado para o teste
        global::set_text_map_propagator(TraceContextPropagator::new());

        let mut metadados = HashMap::new();

        // Cria IDs fictícios de Trace e Span
        let trace_id = TraceId::from_hex("0123456789abcdef0123456789abcdef").unwrap();
        let span_id = SpanId::from_hex("0123456789abcdef").unwrap();
        let span_context = SpanContext::new(
            trace_id,
            span_id,
            TraceFlags::default(),
            false,
            TraceState::default(),
        );

        // Anexa o SpanContext remoto ao contexto atual da thread
        let context = opentelemetry::Context::current().with_remote_span_context(span_context);
        let _guard = context.attach();

        // Injeta os metadados da thread atual no HashMap
        injetar_contexto_atual(&mut metadados);

        // Assevera que a chave de especificação 'traceparent' está presente
        assert!(
            metadados.contains_key("traceparent"),
            "Metadados deveriam conter 'traceparent'"
        );
        let traceparent_val = metadados.get("traceparent").unwrap();
        assert!(
            traceparent_val.contains("0123456789abcdef0123456789abcdef"),
            "Valor de traceparent deve conter o trace_id"
        );

        // Extrai o contexto de volta a partir do HashMap
        let extracted_ctx = extrair_contexto(&metadados);
        let extracted_span_ctx = extracted_ctx.span();
        let extracted_span_context = extracted_span_ctx.span_context();

        // Assevera que os IDs recuperados coincidem com os injetados
        assert_eq!(extracted_span_context.trace_id(), trace_id);
        assert_eq!(extracted_span_context.span_id(), span_id);
    }
}
