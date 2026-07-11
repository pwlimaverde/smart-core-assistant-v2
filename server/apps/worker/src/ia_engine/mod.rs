//! Cliente gRPC do serviço `ia_engine` (fase N2): port + adapter real (`tonic`) +
//! decorator de resiliência. Ver `client.rs` para o contrato, `tonic_client.rs`
//! para a implementação real e `resilient.rs` para timeout/retry/degradação.

pub mod client;
pub mod resilient;
pub mod tonic_client;

// Reexporta só o que é consumido hoje fora do módulo (barreira de bot em
// `main.rs`: caminho Embed -> QueryCompose -> Responder). Os demais tipos
// (Transcribe/InterpretMedia/Analyse/Sentimento) já estão implementados e
// testados no client/adapter — ver `client.rs` — mas ainda não têm chamador no
// pipeline de mensagens deste ciclo (fica para uma continuação: exige estender
// `domain_whatsapp::NormalizedMessage` com URL de mídia). Acessíveis via
// caminho completo `ia_engine::client::*` quando forem ligados.
pub use client::{
    ChatTurnInput, EmbedInput, IaEngineClient, LlmProviderConfigInput, ResponderInput,
};
pub use resilient::ResilientIaEngine;
pub use tonic_client::TonicIaEngineClient;

#[cfg(test)]
pub use client::MockIaEngineClient;
