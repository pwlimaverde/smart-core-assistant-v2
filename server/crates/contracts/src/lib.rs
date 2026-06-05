pub mod envelope;
pub use envelope::TenantEnvelope;

pub mod grpc {
    pub mod contracts {
        tonic::include_proto!("smartcore.contracts");
    }
    pub mod events {
        tonic::include_proto!("smartcore.contracts.events");
    }
    pub mod queries {
        tonic::include_proto!("smartcore.contracts.queries");
    }
    pub mod ai {
        tonic::include_proto!("smartcore.contracts.ai");
    }
}

// Re-exportar mensagens gRPC principais na raiz do crate para facilitar o uso
pub use grpc::contracts::{Envelope, MessageKind, ErrorEnvelope, ErrorCategory, Severity, KeyValue};

// Módulo que engloba a geração de código consolidada do FlatBuffers
#[allow(unused_imports, dead_code, clippy::all)]
pub mod fbs_generated {
    include!(concat!(env!("OUT_DIR"), "/all_schemas_generated.rs"));
}

// Mapeamento amigável para expor as structs FlatBuffers exatamente no caminho esperado
pub mod fbs {
    pub mod envelope {
        pub use crate::fbs_generated::smartcore::contracts::{Envelope, EnvelopeArgs, MessageKind};
    }
    pub mod errors {
        pub use crate::fbs_generated::smartcore::contracts::{ErrorEnvelope, ErrorEnvelopeArgs, ErrorCategory, Severity, KeyValue, KeyValueArgs};
    }
    pub mod message {
        pub use crate::fbs_generated::smartcore::contracts::{MessageReceived, MessageReceivedArgs, MessageUpdate, MessageUpdateArgs};
    }
    pub mod persistence {
        pub use crate::fbs_generated::smartcore::contracts::{MessagePersisted, MessagePersistedArgs};
    }
    pub mod conversation {
        pub use crate::fbs_generated::smartcore::contracts::{GetConversationRequest, GetConversationRequestArgs, GetConversationResponse, GetConversationResponseArgs};
    }
    pub mod auth {
        pub use crate::fbs_generated::smartcore::contracts::{RegisterRequest, RegisterRequestArgs, LoginRequest, LoginRequestArgs, AuthResponse, AuthResponseArgs};
    }
    pub mod ai_engine {
        pub use crate::fbs_generated::smartcore::contracts::{AiRequest, AiRequestArgs, AiResponse, AiResponseArgs};
    }
}
