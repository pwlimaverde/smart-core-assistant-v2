//! Decorator de resiliência do `IaEngineClient`: timeout + retry bounded com
//! backoff curto, só para erros transitórios (`Timeout`/`Unavailable`). Nunca
//! inventa uma resposta — se as tentativas se esgotarem, devolve o erro ao
//! chamador; quem decide o fallback textual é a barreira de bot em `main.rs`
//! (nunca trava o atendimento por uma falha da IA).

use async_trait::async_trait;
use std::time::Duration;

use crate::ia_engine::client::*;

fn env_ms(key: &str, default: u64) -> u64 {
    std::env::var(key)
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(default)
}

/// Backoff curto entre tentativas — mesmo espírito do retry de
/// `processar_mensagem_persistida` (fase N1).
const BACKOFF_SECS: [u64; 3] = [0, 1, 2];

pub struct ResilientIaEngine<C: IaEngineClient> {
    inner: C,
    timeout_text: Duration,
    timeout_media: Duration,
}

impl<C: IaEngineClient> ResilientIaEngine<C> {
    pub fn new(inner: C) -> Self {
        Self {
            inner,
            timeout_text: Duration::from_millis(env_ms(
                "SMARTCORE_IA_ENGINE_TIMEOUT_TEXT_MS",
                8_000,
            )),
            timeout_media: Duration::from_millis(env_ms(
                "SMARTCORE_IA_ENGINE_TIMEOUT_MEDIA_MS",
                30_000,
            )),
        }
    }

    /// Executa `op` sob timeout + retry bounded. `op` é chamada de novo a cada
    /// tentativa (precisa ser barata de reconstruir — os DTOs de entrada são
    /// clonados pelos chamadores em `main.rs`).
    async fn com_resiliencia<T, F, Fut>(
        &self,
        timeout: Duration,
        mut op: F,
    ) -> Result<T, IaEngineError>
    where
        F: FnMut() -> Fut,
        Fut: std::future::Future<Output = Result<T, IaEngineError>>,
    {
        let mut ultimo_erro = IaEngineError::Internal("nenhuma tentativa executada".to_string());
        for (tentativa, atraso) in BACKOFF_SECS.iter().enumerate() {
            if *atraso > 0 {
                tokio::time::sleep(Duration::from_secs(*atraso)).await;
            }
            let resultado = tokio::time::timeout(timeout, op()).await;
            match resultado {
                Ok(Ok(valor)) => return Ok(valor),
                Ok(Err(erro)) => {
                    if !erro.retentavel() {
                        return Err(erro);
                    }
                    tracing::warn!(
                        tentativa = tentativa,
                        "ia_engine: chamada falhou (retentável): {}",
                        erro
                    );
                    ultimo_erro = erro;
                }
                Err(_) => {
                    tracing::warn!(tentativa = tentativa, "ia_engine: timeout na chamada");
                    ultimo_erro = IaEngineError::Timeout;
                }
            }
        }
        Err(ultimo_erro)
    }
}

#[async_trait]
impl<C: IaEngineClient> IaEngineClient for ResilientIaEngine<C> {
    async fn transcribe(
        &self,
        req: TranscribeInput,
        traceparent: &str,
    ) -> Result<TranscribeOutput, IaEngineError> {
        self.com_resiliencia(self.timeout_media, || {
            self.inner.transcribe(req.clone(), traceparent)
        })
        .await
    }

    async fn interpret_media(
        &self,
        req: InterpretMediaInput,
        traceparent: &str,
    ) -> Result<InterpretMediaOutput, IaEngineError> {
        self.com_resiliencia(self.timeout_media, || {
            self.inner.interpret_media(req.clone(), traceparent)
        })
        .await
    }

    async fn analyse(
        &self,
        req: AnalyseInput,
        traceparent: &str,
    ) -> Result<AnalyseOutput, IaEngineError> {
        self.com_resiliencia(self.timeout_text, || {
            self.inner.analyse(req.clone(), traceparent)
        })
        .await
    }

    async fn embed(
        &self,
        req: EmbedInput,
        traceparent: &str,
    ) -> Result<EmbedOutput, IaEngineError> {
        self.com_resiliencia(self.timeout_text, || {
            self.inner.embed(req.clone(), traceparent)
        })
        .await
    }

    async fn responder(
        &self,
        req: ResponderInput,
        traceparent: &str,
    ) -> Result<ResponderOutput, IaEngineError> {
        self.com_resiliencia(self.timeout_text, || {
            self.inner.responder(req.clone(), traceparent)
        })
        .await
    }

    async fn sentimento(
        &self,
        req: SentimentoInput,
        traceparent: &str,
    ) -> Result<SentimentoOutput, IaEngineError> {
        self.com_resiliencia(self.timeout_text, || {
            self.inner.sentimento(req.clone(), traceparent)
        })
        .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;

    /// `EmbedInput` é o DTO mais simples da trait — usado para testar o
    /// decorator sem precisar montar os demais.
    fn embed_req() -> EmbedInput {
        EmbedInput {
            tenant_id: "t".to_string(),
            textos: vec!["oi".to_string()],
            embeddings_provider: LlmProviderConfigInput::default(),
        }
    }

    #[tokio::test]
    async fn retenta_em_erro_transitorio_e_eventualmente_ok() {
        let chamadas = Arc::new(AtomicUsize::new(0));
        let chamadas_h = chamadas.clone();

        let mut mock = MockIaEngineClient::new();
        mock.expect_embed().times(2).returning(move |_, _| {
            let n = chamadas_h.fetch_add(1, Ordering::SeqCst);
            if n == 0 {
                Err(IaEngineError::Unavailable("simulado".to_string()))
            } else {
                Ok(EmbedOutput {
                    embeddings: vec![vec![0.1, 0.2]],
                })
            }
        });

        let resiliente = ResilientIaEngine::new(mock);
        let resultado = resiliente.embed(embed_req(), "").await;
        assert!(resultado.is_ok());
        assert_eq!(chamadas.load(Ordering::SeqCst), 2);
    }

    #[tokio::test]
    async fn nao_retenta_erro_definitivo() {
        let mut mock = MockIaEngineClient::new();
        mock.expect_embed()
            .times(1)
            .returning(|_, _| Err(IaEngineError::Invalid("payload ruim".to_string())));

        let resiliente = ResilientIaEngine::new(mock);
        let resultado = resiliente.embed(embed_req(), "").await;
        assert!(matches!(resultado, Err(IaEngineError::Invalid(_))));
    }

    #[tokio::test]
    async fn esgota_tentativas_e_devolve_ultimo_erro() {
        let mut mock = MockIaEngineClient::new();
        mock.expect_embed()
            .times(3)
            .returning(|_, _| Err(IaEngineError::Unavailable("sempre fora".to_string())));

        let resiliente = ResilientIaEngine::new(mock);
        let resultado = resiliente.embed(embed_req(), "").await;
        assert!(matches!(resultado, Err(IaEngineError::Unavailable(_))));
    }
}
