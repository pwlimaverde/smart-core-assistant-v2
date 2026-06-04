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
