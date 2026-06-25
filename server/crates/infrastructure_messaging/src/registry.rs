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
