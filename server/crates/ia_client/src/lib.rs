//! Cliente gRPC do serviço `ia_engine`: port + adapter real (`tonic`) +
//! decorator de resiliência. Ver `client.rs` para o contrato, `tonic_client.rs`
//! para a implementação real e `resilient.rs` para timeout/retry/degradação.
//!
//! **Por que uma crate e não um módulo do worker:** o worker foi o primeiro
//! consumidor, mas não é o único — a tela de "testar pergunta" precisa do
//! mesmo caminho a partir do `runtime_api`. Duplicar o adapter criaria dois
//! lugares para configurar timeout, retry e degradação, que é justamente o que
//! o `resilient.rs` existe para centralizar.

pub mod client;
pub mod resilient;
pub mod tonic_client;

// Reexporta o que é consumido fora do módulo: a barreira de bot em `main.rs`
// (Embed -> QueryCompose -> Responder) e o pipeline de mídia N6.1
// (Transcribe/InterpretMedia). Os tipos de entrada de mídia
// (`MediaRefInput`/`TranscribeInput`/`InterpretMediaInput`) continuam acessíveis
// via caminho completo `ia_engine::client::*`. Analyse/Sentimento seguem
// implementados no client/adapter, ainda sem chamador no pipeline deste ciclo.
pub use client::{ChatTurnInput, EmbedInput, IaEngineClient, ResponderInput};
pub use resilient::ResilientIaEngine;
pub use tonic_client::TonicIaEngineClient;

#[cfg(any(test, feature = "mock"))]
pub use client::MockIaEngineClient;
