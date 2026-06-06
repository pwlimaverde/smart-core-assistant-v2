// transport/src/codec.rs  (comentários em pt-br)
use crate::error::TransportError;
use bytes::Bytes;
use contracts::Envelope;
use prost::Message;

/// Serializa/deserializa o envelope. Desacoplado do canal.
pub trait Codec: Send + Sync {
    fn nome(&self) -> &'static str; // "flatbuffers" | "grpc"
    fn encode(&self, env: &Envelope) -> Bytes; // envelope → bytes do fio
    fn decode(&self, raw: &[u8]) -> Result<Envelope, TransportError>;
}

/// Codec padrão — zero-copy na leitura do payload (FlatBuffers).
pub struct FlatbuffersCodec;

impl Codec for FlatbuffersCodec {
    fn nome(&self) -> &'static str {
        "flatbuffers"
    }

    fn encode(&self, env: &Envelope) -> Bytes {
        let mut fbb = flatbuffers::FlatBufferBuilder::new();

        // 1. Criar os campos de erro se existirem
        let error_offset = env.error.as_ref().map(|err| {
            let code_offset = fbb.create_string(&err.code);
            let msg_offset = fbb.create_string(&err.message);
            let user_msg_offset = fbb.create_string(&err.user_message);
            let user_msg_fb_offset = fbb.create_string(&err.user_message_fallback);
            let trace_id_offset = fbb.create_string(&err.trace_id);
            let source_svc_offset = fbb.create_string(&err.source_svc);

            // Criar KeyValue details
            let mut det_offsets = Vec::new();
            for kv in &err.details {
                let k_offset = fbb.create_string(&kv.key);
                let v_offset = fbb.create_string(&kv.value);

                let kv_args = contracts::fbs::errors::KeyValueArgs {
                    key: Some(k_offset),
                    value: Some(v_offset),
                };
                det_offsets.push(contracts::fbs::errors::KeyValue::create(&mut fbb, &kv_args));
            }
            let details_vector = fbb.create_vector(&det_offsets);

            let err_args = contracts::fbs::errors::ErrorEnvelopeArgs {
                code: Some(code_offset),
                category: contracts::fbs::errors::ErrorCategory(err.category),
                severity: contracts::fbs::errors::Severity(err.severity),
                message: Some(msg_offset),
                user_message: Some(user_msg_offset),
                user_message_fallback: Some(user_msg_fb_offset),
                retryable: err.retryable,
                trace_id: Some(trace_id_offset),
                source_svc: Some(source_svc_offset),
                details: Some(details_vector),
                occurred_at: err.occurred_at,
            };
            contracts::fbs::errors::ErrorEnvelope::create(&mut fbb, &err_args)
        });

        // 2. Criar os offsets de string/vetores para o Envelope
        let tenant_id_offset = fbb.create_string(&env.tenant_id);
        let message_id_offset = fbb.create_string(&env.message_id);
        let causation_id_offset = fbb.create_string(&env.causation_id);
        let traceparent_offset = fbb.create_string(&env.traceparent);
        let method_offset = fbb.create_string(&env.method);
        let payload_offset = fbb.create_vector(&env.payload);

        // 3. Criar a tabela Envelope
        let env_args = contracts::fbs::envelope::EnvelopeArgs {
            tenant_id: Some(tenant_id_offset),
            schema_version: env.schema_version,
            message_id: Some(message_id_offset),
            causation_id: Some(causation_id_offset),
            traceparent: Some(traceparent_offset),
            occurred_at: env.occurred_at,
            kind: contracts::fbs::envelope::MessageKind(env.kind),
            method: Some(method_offset),
            payload: Some(payload_offset),
            error: error_offset,
        };
        let root = contracts::fbs::envelope::Envelope::create(&mut fbb, &env_args);
        fbb.finish(root, None);

        Bytes::copy_from_slice(fbb.finished_data())
    }

    fn decode(&self, raw: &[u8]) -> Result<Envelope, TransportError> {
        let fbs_env = flatbuffers::root::<contracts::fbs::envelope::Envelope>(raw)
            .map_err(|e| TransportError::Codec(format!("Erro ao ler root FlatBuffers: {:?}", e)))?;

        // Converter de volta para a struct do gRPC
        let tenant_id = fbs_env.tenant_id().unwrap_or("").to_string();
        let message_id = fbs_env.message_id().unwrap_or("").to_string();
        let causation_id = fbs_env.causation_id().unwrap_or("").to_string();
        let traceparent = fbs_env.traceparent().unwrap_or("").to_string();
        let method = fbs_env.method().unwrap_or("").to_string();

        let payload = fbs_env
            .payload()
            .map(|p| p.bytes().to_vec())
            .unwrap_or_default();

        let error = fbs_env.error().map(|err| {
            let code = err.code().unwrap_or("").to_string();
            let message = err.message().unwrap_or("").to_string();
            let user_message = err.user_message().unwrap_or("").to_string();
            let user_message_fallback = err.user_message_fallback().unwrap_or("").to_string();
            let trace_id = err.trace_id().unwrap_or("").to_string();
            let source_svc = err.source_svc().unwrap_or("").to_string();

            let mut details = Vec::new();
            if let Some(dets) = err.details() {
                for i in 0..dets.len() {
                    let kv = dets.get(i);
                    details.push(contracts::grpc::contracts::KeyValue {
                        key: kv.key().unwrap_or("").to_string(),
                        value: kv.value().unwrap_or("").to_string(),
                    });
                }
            }

            contracts::ErrorEnvelope {
                code,
                category: err.category().0,
                severity: err.severity().0,
                message,
                user_message,
                user_message_fallback,
                retryable: err.retryable(),
                trace_id,
                source_svc,
                details,
                occurred_at: err.occurred_at(),
            }
        });

        Ok(Envelope {
            tenant_id,
            schema_version: fbs_env.schema_version(),
            message_id,
            causation_id,
            traceparent,
            occurred_at: fbs_env.occurred_at(),
            kind: fbs_env.kind().0,
            method,
            payload,
            error,
        })
    }
}

/// Codec fallback — usa prost/tonic por baixo (Protobuf).
pub struct GrpcCodec;

impl Codec for GrpcCodec {
    fn nome(&self) -> &'static str {
        "grpc"
    }

    fn encode(&self, env: &Envelope) -> Bytes {
        let mut buf = Vec::new();
        env.encode(&mut buf).unwrap(); // Infallible para a struct autogerada
        Bytes::from(buf)
    }

    fn decode(&self, raw: &[u8]) -> Result<Envelope, TransportError> {
        Envelope::decode(raw).map_err(|e| {
            TransportError::Codec(format!("Erro ao decodificar Protobuf/gRPC: {:?}", e))
        })
    }
}

/// Seleção por config: SMARTCORE_<SVC>_CODEC=flatbuffers|grpc (default flatbuffers).
pub fn from_env(svc: &str) -> Box<dyn Codec> {
    match std::env::var(format!("SMARTCORE_{}_CODEC", svc.to_uppercase())).as_deref() {
        Ok("grpc") => Box::new(GrpcCodec),
        _ => Box::new(FlatbuffersCodec), // padrão
    }
}
