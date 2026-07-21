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

#[cfg(test)]
mod tests {
    use super::*;
    use tonic::Code;

    // Mapeamento de status gRPC → IaEngineError: cada Code deve virar a variante certa,
    // pois é isso que o `ResilientIaEngine` usa para decidir se retenta.

    #[test]
    fn mapear_status_deadline_vira_timeout() {
        let err = mapear_status(tonic::Status::new(Code::DeadlineExceeded, "estourou"));
        assert!(matches!(err, IaEngineError::Timeout));
    }

    #[test]
    fn mapear_status_unavailable_vira_unavailable() {
        let err = mapear_status(tonic::Status::new(Code::Unavailable, "fora do ar"));
        match err {
            IaEngineError::Unavailable(m) => assert_eq!(m, "fora do ar"),
            outro => panic!("esperava Unavailable, veio {outro:?}"),
        }
    }

    #[test]
    fn mapear_status_resource_exhausted_vira_unavailable() {
        // ResourceExhausted (rate limit) é transitório → tratado como Unavailable (retentável).
        let err = mapear_status(tonic::Status::new(Code::ResourceExhausted, "limite"));
        assert!(matches!(err, IaEngineError::Unavailable(_)));
        assert!(err.retentavel());
    }

    #[test]
    fn mapear_status_invalid_argument_vira_invalid() {
        let err = mapear_status(tonic::Status::new(Code::InvalidArgument, "campo ruim"));
        match err {
            IaEngineError::Invalid(m) => assert_eq!(m, "campo ruim"),
            outro => panic!("esperava Invalid, veio {outro:?}"),
        }
        assert!(!mapear_status(tonic::Status::new(Code::InvalidArgument, "x")).retentavel());
    }

    #[test]
    fn mapear_status_not_found_vira_invalid() {
        let err = mapear_status(tonic::Status::new(Code::NotFound, "sumiu"));
        assert!(matches!(err, IaEngineError::Invalid(_)));
    }

    #[test]
    fn mapear_status_desconhecido_vira_internal() {
        // Qualquer código fora dos casos explícitos cai no ramo default → Internal.
        let err = mapear_status(tonic::Status::new(Code::Internal, "boom"));
        match err {
            IaEngineError::Internal(m) => assert_eq!(m, "boom"),
            outro => panic!("esperava Internal, veio {outro:?}"),
        }
    }

    #[test]
    fn com_traceparent_valido_injeta_metadata() {
        let traceparent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01";
        let req = com_traceparent(42u32, traceparent);
        let val = req
            .metadata()
            .get("traceparent")
            .expect("traceparent deveria estar no metadata");
        assert_eq!(val.to_str().unwrap(), traceparent);
        assert_eq!(*req.get_ref(), 42);
    }

    #[test]
    fn com_traceparent_invalido_nao_injeta_metadata() {
        // Caractere de controle (quebra de linha) não é um valor de metadata gRPC
        // válido: o parse falha e o header simplesmente não é inserido (sem panic,
        // sem propagar erro).
        let req = com_traceparent(1u32, "trace\ninválido");
        assert!(req.metadata().get("traceparent").is_none());
    }

    #[test]
    fn provider_para_proto_mapeia_campos() {
        let cfg = LlmProviderConfigInput {
            provider: "openai".to_string(),
            model: "gpt-4o".to_string(),
            api_key: "segredo".to_string(),
            temperature: 0.7,
        };
        let pb = provider_para_proto(cfg);
        assert_eq!(pb.provider, "openai");
        assert_eq!(pb.model, "gpt-4o");
        assert_eq!(pb.api_key, "segredo");
        assert_eq!(pb.temperature, 0.7);
        assert!(pb.extra_params.is_empty());
    }

    #[test]
    fn media_para_proto_mapeia_campos() {
        let m = MediaRefInput {
            url: "http://midia/a.ogg".to_string(),
            mimetype: "audio/ogg".to_string(),
            file_name: "a.ogg".to_string(),
        };
        let pb = media_para_proto(m);
        assert_eq!(pb.url, "http://midia/a.ogg");
        assert_eq!(pb.mimetype, "audio/ogg");
        assert_eq!(pb.file_name, "a.ogg");
    }

    #[test]
    fn historico_para_proto_preserva_ordem_e_conteudo() {
        let turnos = vec![
            ChatTurnInput {
                role: "user".to_string(),
                conteudo: "oi".to_string(),
            },
            ChatTurnInput {
                role: "assistant".to_string(),
                conteudo: "olá".to_string(),
            },
        ];
        let pb = historico_para_proto(turnos);
        assert_eq!(pb.turnos.len(), 2);
        assert_eq!(pb.turnos[0].role, "user");
        assert_eq!(pb.turnos[0].conteudo, "oi");
        assert_eq!(pb.turnos[1].role, "assistant");
        assert_eq!(pb.turnos[1].conteudo, "olá");
    }

    #[test]
    fn historico_para_proto_vazio_gera_lista_vazia() {
        let pb = historico_para_proto(vec![]);
        assert!(pb.turnos.is_empty());
    }

    #[tokio::test]
    async fn connect_lazy_com_endpoint_valido_retorna_ok() {
        // `connect_lazy` não abre conexão, mas o `connect_lazy` do hyper exige estar
        // dentro de um runtime Tokio (registra o reactor). Não há I/O de rede aqui.
        let cliente = TonicIaEngineClient::connect_lazy("http://127.0.0.1:50051");
        assert!(cliente.is_ok());
    }

    #[test]
    fn connect_lazy_com_endpoint_invalido_retorna_err() {
        // URI malformada é rejeitada por `Channel::from_shared` antes de qualquer I/O.
        let cliente = TonicIaEngineClient::connect_lazy("http://exemplo com espaco");
        assert!(cliente.is_err());
    }
}
