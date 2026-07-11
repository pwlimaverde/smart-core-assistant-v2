//! Adapter real do `IaEngineClient`: fala gRPC HTTP/2 de verdade (`tonic`) com o
//! serviço Python `ia_engine` — não usa o protocolo interno `transport::MuxClient`
//! (esse é só para Rust↔Rust). `traceparent` viaja via metadata gRPC (W3C
//! TraceContext), nunca como campo de mensagem — mesma convenção de
//! `runtime_api/src/grpc_web.rs::traceparent_do_metadata`.

use async_trait::async_trait;
use contracts::grpc::ai as pb;
use tonic::transport::Channel;
use tonic::Request;

use crate::ia_engine::client::*;

#[derive(Clone)]
pub struct TonicIaEngineClient {
    client: pb::ia_engine_service_client::IaEngineServiceClient<Channel>,
}

impl TonicIaEngineClient {
    /// Conecta ao `ia_engine` (`connect_lazy`: não bloqueia no boot do worker —
    /// a primeira chamada real dispara a conexão; falhas de conectividade viram
    /// `IaEngineError::Unavailable` naturalmente, tratadas pelo `ResilientIaEngine`).
    pub fn connect_lazy(endpoint: &str) -> anyhow::Result<Self> {
        let channel = Channel::from_shared(endpoint.to_string())?.connect_lazy();
        Ok(Self {
            client: pb::ia_engine_service_client::IaEngineServiceClient::new(channel),
        })
    }
}

fn mapear_status(status: tonic::Status) -> IaEngineError {
    use tonic::Code;
    match status.code() {
        Code::DeadlineExceeded => IaEngineError::Timeout,
        Code::Unavailable | Code::ResourceExhausted => {
            IaEngineError::Unavailable(status.message().to_string())
        }
        Code::InvalidArgument | Code::NotFound => {
            IaEngineError::Invalid(status.message().to_string())
        }
        _ => IaEngineError::Internal(status.message().to_string()),
    }
}

fn com_traceparent<T>(payload: T, traceparent: &str) -> Request<T> {
    let mut req = Request::new(payload);
    if let Ok(val) = traceparent.parse() {
        req.metadata_mut().insert("traceparent", val);
    }
    req
}

fn provider_para_proto(cfg: LlmProviderConfigInput) -> pb::LlmProviderConfig {
    pb::LlmProviderConfig {
        provider: cfg.provider,
        model: cfg.model,
        api_key: cfg.api_key,
        temperature: cfg.temperature,
        extra_params: vec![],
    }
}

fn media_para_proto(m: MediaRefInput) -> pb::MediaRef {
    pb::MediaRef {
        url: m.url,
        mimetype: m.mimetype,
        file_name: m.file_name,
    }
}

fn historico_para_proto(turnos: Vec<ChatTurnInput>) -> pb::ChatHistory {
    pb::ChatHistory {
        turnos: turnos
            .into_iter()
            .map(|t| pb::ChatTurn {
                role: t.role,
                conteudo: t.conteudo,
            })
            .collect(),
    }
}

#[async_trait]
impl IaEngineClient for TonicIaEngineClient {
    async fn transcribe(
        &self,
        req: TranscribeInput,
        traceparent: &str,
    ) -> Result<TranscribeOutput, IaEngineError> {
        let payload = pb::TranscribeRequest {
            tenant_id: req.tenant_id,
            media: Some(media_para_proto(req.media)),
            language: req.language,
            transcription_provider: Some(provider_para_proto(req.transcription_provider)),
        };
        let mut client = self.client.clone();
        let resp = client
            .transcribe(com_traceparent(payload, traceparent))
            .await
            .map_err(mapear_status)?
            .into_inner();
        Ok(TranscribeOutput {
            transcricao: resp.transcricao,
            resumo: resp.resumo,
        })
    }

    async fn interpret_media(
        &self,
        req: InterpretMediaInput,
        traceparent: &str,
    ) -> Result<InterpretMediaOutput, IaEngineError> {
        let payload = pb::InterpretMediaRequest {
            tenant_id: req.tenant_id,
            media: Some(media_para_proto(req.media)),
            media_type: req.media_type,
            vision_provider: Some(provider_para_proto(req.vision_provider)),
        };
        let mut client = self.client.clone();
        let resp = client
            .interpret_media(com_traceparent(payload, traceparent))
            .await
            .map_err(mapear_status)?
            .into_inner();
        Ok(InterpretMediaOutput {
            analise: resp.analise,
            resumo: resp.resumo,
        })
    }

    async fn analyse(
        &self,
        req: AnalyseInput,
        traceparent: &str,
    ) -> Result<AnalyseOutput, IaEngineError> {
        let payload = pb::AnalyseRequest {
            tenant_id: req.tenant_id,
            mensagem: req.mensagem,
            historico: Some(historico_para_proto(req.historico)),
            valid_intent_types: req.valid_intent_types,
            valid_entity_types: req.valid_entity_types,
            llm: Some(provider_para_proto(req.llm)),
        };
        let mut client = self.client.clone();
        let resp = client
            .analyse(com_traceparent(payload, traceparent))
            .await
            .map_err(mapear_status)?
            .into_inner();
        Ok(AnalyseOutput {
            intents: resp
                .intents
                .into_iter()
                .map(|i| IntentOutput {
                    tipo: i.tipo,
                    confianca: i.confianca,
                })
                .collect(),
            entidades: resp
                .entidades
                .into_iter()
                .map(|e| EntidadeOutput {
                    tipo: e.tipo,
                    valor: e.valor,
                    confianca: e.confianca,
                })
                .collect(),
        })
    }

    async fn embed(
        &self,
        req: EmbedInput,
        traceparent: &str,
    ) -> Result<EmbedOutput, IaEngineError> {
        let payload = pb::EmbedRequest {
            tenant_id: req.tenant_id,
            textos: req.textos,
            embeddings_provider: Some(provider_para_proto(req.embeddings_provider)),
        };
        let mut client = self.client.clone();
        let resp = client
            .embed(com_traceparent(payload, traceparent))
            .await
            .map_err(mapear_status)?
            .into_inner();
        Ok(EmbedOutput {
            embeddings: resp.embeddings.into_iter().map(|e| e.valores).collect(),
        })
    }

    async fn responder(
        &self,
        req: ResponderInput,
        traceparent: &str,
    ) -> Result<ResponderOutput, IaEngineError> {
        let payload = pb::ResponderRequest {
            tenant_id: req.tenant_id,
            atendimento_id: req.atendimento_id,
            mensagem: req.mensagem,
            historico: Some(historico_para_proto(req.historico)),
            fluxos_disponiveis: req
                .fluxos_disponiveis
                .into_iter()
                .map(|(key, value)| pb::KeyValuePair { key, value })
                .collect(),
            dados_empresa: req.dados_empresa,
            dados_treinamento: req.dados_treinamento,
            campos_coletados: req
                .campos_coletados
                .into_iter()
                .map(|c| pb::CampoColetado {
                    slug: c.slug,
                    nome: c.nome,
                    valor: c.valor,
                })
                .collect(),
            campos_pendentes: req
                .campos_pendentes
                .into_iter()
                .map(|c| pb::CampoPendente {
                    slug: c.slug,
                    nome: c.nome,
                    descricao: c.descricao,
                    hint: c.hint,
                })
                .collect(),
            llm: Some(provider_para_proto(req.llm)),
            embeddings_provider: Some(provider_para_proto(req.embeddings_provider)),
            similarity_threshold: req.similarity_threshold,
        };
        let mut client = self.client.clone();
        let resp = client
            .responder(com_traceparent(payload, traceparent))
            .await
            .map_err(mapear_status)?
            .into_inner();
        Ok(ResponderOutput {
            resposta_texto: resp.resposta_texto,
            transferir_atendimento: resp.transferir_atendimento,
            fluxo_transferencia: resp.fluxo_transferencia,
            confiabilidade: resp.confiabilidade,
        })
    }

    async fn sentimento(
        &self,
        req: SentimentoInput,
        traceparent: &str,
    ) -> Result<SentimentoOutput, IaEngineError> {
        let payload = pb::SentimentoRequest {
            tenant_id: req.tenant_id,
            historico: Some(historico_para_proto(req.historico)),
            llm: Some(provider_para_proto(req.llm)),
        };
        let mut client = self.client.clone();
        let resp = client
            .sentimento(com_traceparent(payload, traceparent))
            .await
            .map_err(mapear_status)?
            .into_inner();
        Ok(SentimentoOutput {
            nota: resp.nota,
            sentimento: resp.sentimento,
            feedback: resp.feedback,
        })
    }
}
