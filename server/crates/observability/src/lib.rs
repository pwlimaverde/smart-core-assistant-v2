//! Crate de instrumentação, telemetria e auditoria estruturada do Smart Core Assistant v2.
//!
//! Fornece a fundação de observabilidade para todos os serviços do sistema,
//! integrando logs estruturados (JSON no terminal), exportação de spans via
//! OpenTelemetry gRPC (Loki/Tempo/Prometheus) e persistência assíncrona
//! de logs de auditoria de negócio e segurança no banco de dados com RLS.

pub mod audit;
pub mod propagation;
pub mod span_helpers;
pub mod telemetry;
pub mod usage_metrics;

#[cfg(feature = "pool-metrics")]
pub mod pool_metrics;

// Re-exports de conveniência
pub use audit::{AuditLogPayload, AuditLogger};
#[cfg(feature = "pool-metrics")]
pub use pool_metrics::monitorar_pool;
pub use propagation::{extrair_contexto, injetar_contexto_atual, HashMapCarrier, HashMapExtractor};
pub use telemetry::{init_telemetry, shutdown_telemetry};

// Re-export do opentelemetry para evitar dependência direta em outras crates
pub use opentelemetry;
