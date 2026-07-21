//! Cliente gRPC do serviço `ia_engine` (fase N2): port + adapter real (`tonic`) +
//! decorator de resiliência. Ver `client.rs` para o contrato, `tonic_client.rs`
//! para a implementação real e `resilient.rs` para timeout/retry/degradação.

pub mod client;
pub mod resilient;
pub mod tonic_client;

// Reexporta o que é consumido fora do módulo: a barreira de bot em `main.rs`
// (Embed -> QueryCompose -> Responder) e o pipeline de mídia N6.1
// (Transcribe/InterpretMedia). Os tipos de entrada de mídia
// (`MediaRefInput`/`TranscribeInput`/`InterpretMediaInput`) continuam acessíveis
// via caminho completo `ia_engine::client::*`. Analyse/Sentimento seguem
// implementados no client/adapter, ainda sem chamador no pipeline deste ciclo.
pub use client::{
    ChatTurnInput, EmbedInput, IaEngineClient, LlmProviderConfigInput, ResponderInput,
};
pub use resilient::ResilientIaEngine;
pub use tonic_client::TonicIaEngineClient;

#[cfg(test)]
pub use client::MockIaEngineClient;
