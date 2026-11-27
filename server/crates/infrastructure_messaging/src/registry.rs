use crate::{MessagingProvider, MessagingProviderError};
use std::collections::HashMap;
use std::sync::Arc;

/// Registry de provedores de mensageria.
#[derive(Clone)]
pub struct ProviderRegistry {
    map: Arc<HashMap<String, Arc<dyn MessagingProvider>>>,
}

impl Default for ProviderRegistry {
    fn default() -> Self {
        Self {
            map: Arc::new(HashMap::new()),
        }
    }
}

impl ProviderRegistry {
    pub fn builder() -> ProviderRegistryBuilder {
        ProviderRegistryBuilder::default()
    }

    pub fn resolve(
        &self,
        provider: &str,
    ) -> Result<Arc<dyn MessagingProvider>, MessagingProviderError> {
        self.map.get(provider).cloned().ok_or_else(|| {
            MessagingProviderError::Config(format!("provedor não registrado: {provider}"))
        })
    }

    /// Todos os provedores registrados, em ordem estável de chave (a tela não
    /// pode trocar a ordem dos cartões a cada carga).
    pub fn listar(&self) -> Vec<Arc<dyn MessagingProvider>> {
        let mut chaves: Vec<&String> = self.map.keys().collect();
        chaves.sort();
        chaves
            .into_iter()
            .filter_map(|k| self.map.get(k).cloned())
            .collect()
    }
}

#[derive(Default)]
pub struct ProviderRegistryBuilder {
    map: HashMap<String, Arc<dyn MessagingProvider>>,
}

impl ProviderRegistryBuilder {
    pub fn register(mut self, p: Arc<dyn MessagingProvider>) -> Self {
        self.map.insert(p.provider_name().to_string(), p);
        self
    }

    pub fn build(self) -> ProviderRegistry {
        ProviderRegistry {
            map: Arc::new(self.map),
        }
    }
}
