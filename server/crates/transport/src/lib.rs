// transport/src/lib.rs  (comentários em pt-br)
pub mod bus;
pub mod codec;
pub mod error;
pub mod framing;
pub mod liveness;
pub mod runtime;

// Re-exportações públicas para facilitar o uso por outros crates
pub use codec::{from_env, Codec, FlatbuffersCodec, GrpcCodec};
pub use error::TransportError;
pub use framing::Frame;
pub use runtime::{
    conectar_cliente, sondar_endpoint, sondar_servico, Endpoint, Handler, MuxClient, Server,
};
