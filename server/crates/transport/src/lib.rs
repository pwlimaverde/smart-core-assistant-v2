// transport/src/lib.rs  (comentários em pt-br)
pub mod error;
pub mod codec;
pub mod framing;
pub mod runtime;
pub mod bus;

// Re-exportações públicas para facilitar o uso por outros crates
pub use error::TransportError;
pub use codec::{Codec, FlatbuffersCodec, GrpcCodec, from_env};
pub use framing::Frame;
pub use runtime::{Endpoint, MuxClient, Server, Handler, conectar_cliente};
