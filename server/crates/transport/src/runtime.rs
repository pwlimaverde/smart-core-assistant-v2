// transport/src/runtime.rs  (comentários em pt-br)
use crate::codec::Codec;
use crate::error::TransportError;
use crate::framing::{read_frame, write_frame, Frame};
use contracts::Envelope;
use std::collections::HashMap;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::net::TcpListener;
#[cfg(unix)]
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::{mpsc, oneshot, Mutex};
use tokio::time::{timeout, Duration};

#[derive(Debug, Clone)]
pub enum Endpoint {
    Uds(PathBuf),
    Tcp(SocketAddr),
}

impl Endpoint {
    pub fn parse(s: &str) -> anyhow::Result<Self> {
        if let Some(path) = s.strip_prefix("unix://") {
            Ok(Endpoint::Uds(PathBuf::from(path)))
        } else if let Some(addr_str) = s.strip_prefix("tcp://") {
            let addr: SocketAddr = addr_str.parse()?;
            Ok(Endpoint::Tcp(addr))
        } else {
            anyhow::bail!(
                "Formato de endpoint invalido: {}. Deve comecar com unix:// ou tcp://",
                s
            )
        }
    }
}

/// Multiplexa varias chamadas na mesma conexao (o que o HTTP/2 da ao gRPC de graca).
pub struct MuxClient {
    tx: mpsc::Sender<Frame>,
    pendentes: Arc<Mutex<HashMap<u128, oneshot::Sender<Frame>>>>,
    codec: Box<dyn Codec>,
}

impl MuxClient {
    pub fn new<S>(stream: S, codec: Box<dyn Codec>) -> Self
    where
        S: AsyncRead + AsyncWrite + Send + Unpin + 'static,
    {
        let (tx, mut rx) = mpsc::channel::<Frame>(100);
        let pendentes = Arc::new(Mutex::new(HashMap::<u128, oneshot::Sender<Frame>>::new()));
        let pendentes_clone = pendentes.clone();

        let (mut read_half, mut write_half) = tokio::io::split(stream);

        // Loop de escrita: consome do canal rx e envia no socket
        tokio::spawn(async move {
            while let Some(frame) = rx.recv().await {
                if let Err(e) = write_frame(&mut write_half, &frame).await {
                    tracing::error!("Erro de escrita no loop do cliente: {:?}", e);
                    break;
                }
            }
        });

        // Loop de leitura: lê do socket e envia para o oneshot correspondente
        let pendentes_loop = pendentes.clone();
        tokio::spawn(async move {
            loop {
                match read_frame(&mut read_half).await {
                    Ok(frame) => {
                        let mut map = pendentes_loop.lock().await;
                        if let Some(tx_resp) = map.remove(&frame.corr_id) {
                            let _ = tx_resp.send(frame);
                        } else {
                            tracing::warn!(
                                "Resposta recebida sem chamada pendente para corr_id: {}",
                                frame.corr_id
                            );
                        }
                    }
                    Err(e) => {
                        tracing::error!("Erro de leitura no loop do cliente (conexao possivelmente fechada): {:?}", e);
                        break;
                    }
                }
            }
        });

        Self {
            tx,
            pendentes: pendentes_clone,
            codec,
        }
    }

    /// Executa uma chamada request/reply síncrona com timeout.
    pub async fn call(&self, env: Envelope, prazo: Duration) -> Result<Envelope, TransportError> {
        let corr_id = uuid::Uuid::now_v7().as_u128();
        let (resp_tx, resp_rx) = oneshot::channel();

        // Registrar a oneshot pendente antes de enviar
        self.pendentes.lock().await.insert(corr_id, resp_tx);

        let body = self.codec.encode(&env).to_vec();
        let frame = Frame {
            flags: 0,
            corr_id,
            body,
        };

        if self.tx.send(frame).await.is_err() {
            self.pendentes.lock().await.remove(&corr_id);
            return Err(TransportError::Closed);
        }

        // Aguardar resposta com timeout
        let resp_frame = match timeout(prazo, resp_rx).await {
            Ok(Ok(f)) => f,
            Ok(Err(_)) => {
                return Err(TransportError::Closed);
            }
            Err(_) => {
                self.pendentes.lock().await.remove(&corr_id);
                return Err(TransportError::Timeout);
            }
        };

        self.codec.decode(&resp_frame.body)
    }
}

pub type Handler =
    Arc<dyn Fn(Envelope) -> futures_util::future::BoxFuture<'static, Envelope> + Send + Sync>;

pub struct Server {
    endpoint: Endpoint,
    handlers: Arc<HashMap<String, Handler>>,
    codec_name: String,
}

impl Server {
    pub fn new(endpoint: Endpoint, codec_name: &str) -> Self {
        Self {
            endpoint,
            handlers: Arc::new(HashMap::new()),
            codec_name: codec_name.to_string(),
        }
    }

    pub fn from_env(svc_name: &str) -> Self {
        let env_key = format!("SMARTCORE_{}_ENDPOINT", svc_name.to_uppercase());
        let endpoint_str = std::env::var(&env_key)
            .unwrap_or_else(|_| format!("unix:///var/run/smartcore/{}.sock", svc_name));
        let endpoint = Endpoint::parse(&endpoint_str).unwrap_or_else(|_| {
            // Fallback para Windows usando caminho local
            Endpoint::Uds(PathBuf::from(format!(
                "c:/temp/smartcore_{}.sock",
                svc_name
            )))
        });

        let codec_key = format!("SMARTCORE_{}_CODEC", svc_name.to_uppercase());
        let codec_name = std::env::var(&codec_key).unwrap_or_else(|_| "flatbuffers".to_string());

        Self::new(endpoint, &codec_name)
    }

    pub fn route<F>(mut self, method: &str, handler: F) -> Self
    where
        F: Fn(Envelope) -> futures_util::future::BoxFuture<'static, Envelope>
            + Send
            + Sync
            + 'static,
    {
        let handlers = Arc::get_mut(&mut self.handlers).unwrap();
        handlers.insert(method.to_string(), Arc::new(handler));
        self
    }

    pub async fn run(self) -> anyhow::Result<()> {
        let handlers = self.handlers.clone();
        let codec_name = self.codec_name.clone();

        match self.endpoint {
            Endpoint::Uds(path) => {
                #[cfg(unix)]
                {
                    // Se o socket UDS ja existir, remove-o
                    if path.exists() {
                        let _ = std::fs::remove_file(&path);
                    }

                    // Garantir diretorio pai
                    if let Some(parent) = path.parent() {
                        std::fs::create_dir_all(parent)?;
                    }

                    let listener = UnixListener::bind(&path)?;
                    tracing::info!("Servidor UDS rodando em {:?}", path);

                    loop {
                        let (stream, _) = listener.accept().await?;
                        let handlers_clone = handlers.clone();
                        let codec_name_clone = codec_name.clone();
                        tokio::spawn(async move {
                            if let Err(e) =
                                handle_connection(stream, handlers_clone, codec_name_clone).await
                            {
                                tracing::error!("Erro lidando com conexao UDS: {:?}", e);
                            }
                        });
                    }
                }
                #[cfg(not(unix))]
                {
                    anyhow::bail!("Unix Domain Sockets nao sao suportados em Windows. Endpoint solicitado: {:?}", path);
                }
            }
            Endpoint::Tcp(addr) => {
                let listener = TcpListener::bind(addr).await?;
                tracing::info!("Servidor TCP rodando em {}", addr);

                loop {
                    let (stream, _) = listener.accept().await?;
                    let handlers_clone = handlers.clone();
                    let codec_name_clone = codec_name.clone();
                    tokio::spawn(async move {
                        if let Err(e) =
                            handle_connection(stream, handlers_clone, codec_name_clone).await
                        {
                            tracing::error!("Erro lidando com conexao TCP: {:?}", e);
                        }
                    });
                }
            }
        }
    }
}

async fn handle_connection<S>(
    stream: S,
    handlers: Arc<HashMap<String, Handler>>,
    codec_name: String,
) -> anyhow::Result<()>
where
    S: AsyncRead + AsyncWrite + Send + Unpin + 'static,
{
    let (mut read_half, mut write_half) = tokio::io::split(stream);

    // Inicializar o canal de escrita uma única vez por conexão
    let (write_tx, mut write_rx) = mpsc::channel::<Frame>(100);

    // Spawnar a task de escrita em background que detém write_half
    tokio::spawn(async move {
        while let Some(f) = write_rx.recv().await {
            if let Err(e) = write_frame(&mut write_half, &f).await {
                tracing::error!("Erro ao responder frame de escrita: {:?}", e);
                break;
            }
        }
    });

    loop {
        // Ler proximo frame do cliente
        let frame = match read_frame(&mut read_half).await {
            Ok(f) => f,
            Err(e) => {
                // EOF ou erro de conexao
                if e.kind() != std::io::ErrorKind::UnexpectedEof {
                    tracing::debug!("Conexao terminada: {:?}", e);
                }
                break;
            }
        };

        let handlers_clone = handlers.clone();
        let codec_clone = match codec_name.as_str() {
            "grpc" => Box::new(crate::codec::GrpcCodec) as Box<dyn Codec>,
            _ => Box::new(crate::codec::FlatbuffersCodec) as Box<dyn Codec>,
        };

        let write_tx_clone = write_tx.clone();
        tokio::spawn(async move {
            // Decodificar o envelope
            match codec_clone.decode(&frame.body) {
                Ok(env) => {
                    let method = env.method.clone();
                    let response_env = if let Some(handler) = handlers_clone.get(&method) {
                        handler(env).await
                    } else {
                        // Retornar erro de metodo nao encontrado
                        Envelope {
                            tenant_id: env.tenant_id.clone(),
                            schema_version: env.schema_version,
                            message_id: uuid::Uuid::now_v7().to_string(),
                            causation_id: env.message_id.clone(),
                            traceparent: env.traceparent.clone(),
                            occurred_at: chrono::Utc::now().timestamp_millis(),
                            kind: contracts::MessageKind::Error as i32,
                            method: env.method.clone(),
                            payload: vec![],
                            error: Some(contracts::ErrorEnvelope {
                                code: "METHOD_NOT_FOUND".to_string(),
                                category: contracts::ErrorCategory::NotFound as i32,
                                severity: contracts::Severity::Error as i32,
                                message: format!(
                                    "Metodo {} nao suportado por este servidor",
                                    method
                                ),
                                user_message: "errors.method_not_found".to_string(),
                                user_message_fallback: "Recurso solicitado nao encontrado."
                                    .to_string(),
                                retryable: false,
                                trace_id: env.traceparent.clone(),
                                source_svc: "transport_runtime".to_string(),
                                details: vec![],
                                occurred_at: chrono::Utc::now().timestamp_millis(),
                            }),
                        }
                    };

                    let resp_body = codec_clone.encode(&response_env).to_vec();
                    let resp_frame = Frame {
                        flags: if response_env.kind == contracts::MessageKind::Error as i32 {
                            crate::framing::flags::IS_ERROR
                        } else {
                            0
                        },
                        corr_id: frame.corr_id,
                        body: resp_body,
                    };

                    let _ = write_tx_clone.send(resp_frame).await;
                }
                Err(e) => {
                    tracing::error!("Erro de decodificacao de frame: {:?}", e);
                }
            }
        });
    }

    Ok(())
}

/// Conecta a um microsserviço com base em suas variáveis de ambiente de endpoint e codec.
pub async fn conectar_cliente(svc_name: &str) -> anyhow::Result<MuxClient> {
    let env_key = format!("SMARTCORE_{}_ENDPOINT", svc_name.to_uppercase());
    let endpoint_str = std::env::var(&env_key)
        .unwrap_or_else(|_| format!("unix:///var/run/smartcore/{}.sock", svc_name));
    let endpoint = Endpoint::parse(&endpoint_str)?;

    let codec_key = format!("SMARTCORE_{}_CODEC", svc_name.to_uppercase());
    let codec_name = std::env::var(&codec_key).unwrap_or_else(|_| "flatbuffers".to_string());
    let codec: Box<dyn Codec> = match codec_name.as_str() {
        "grpc" => Box::new(crate::codec::GrpcCodec),
        _ => Box::new(crate::codec::FlatbuffersCodec),
    };

    match endpoint {
        Endpoint::Uds(path) => {
            #[cfg(unix)]
            {
                let stream = tokio::net::UnixStream::connect(path).await?;
                Ok(MuxClient::new(stream, codec))
            }
            #[cfg(not(unix))]
            {
                anyhow::bail!(
                    "Unix Domain Sockets nao sao suportados em Windows. Endpoint: {:?}",
                    path
                );
            }
        }
        Endpoint::Tcp(addr) => {
            let stream = tokio::net::TcpStream::connect(addr).await?;
            Ok(MuxClient::new(stream, codec))
        }
    }
}
