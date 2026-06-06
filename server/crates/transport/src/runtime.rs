// transport/src/runtime.rs  (comentários em pt-br)
use crate::codec::Codec;
use crate::error::TransportError;
use crate::framing::{read_frame, write_frame, Frame};
use contracts::Envelope;
use std::collections::HashMap;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::net::TcpListener;
#[cfg(unix)]
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::{mpsc, oneshot, Mutex};
use tokio::time::{sleep, timeout, Duration};

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

// Parâmetros de resiliência do cliente (keepalive + reconexão com backoff).
const KEEPALIVE_INTERVALO: Duration = Duration::from_secs(15);
const KEEPALIVE_TIMEOUT: Duration = Duration::from_secs(5);
const BACKOFF_INICIAL: Duration = Duration::from_millis(100);
const BACKOFF_MAX: Duration = Duration::from_secs(10);
const MAX_TENTATIVAS_RECONEXAO: u32 = 6;

/// Uma sessão multiplexada sobre uma única conexão física (UDS ou TCP).
/// Mantém o mapa de chamadas pendentes (corr_id → oneshot) e um sinalizador de saúde
/// que os loops de leitura/escrita derrubam quando a conexão cai.
struct Conexao {
    tx: mpsc::Sender<Frame>,
    pendentes: Arc<Mutex<HashMap<u128, oneshot::Sender<Frame>>>>,
    saudavel: Arc<AtomicBool>,
}

impl Conexao {
    /// Monta os loops de leitura/escrita sobre o stream e devolve a conexão pronta.
    fn nova<S>(stream: S) -> Arc<Self>
    where
        S: AsyncRead + AsyncWrite + Send + Unpin + 'static,
    {
        let (tx, mut rx) = mpsc::channel::<Frame>(100);
        let pendentes = Arc::new(Mutex::new(HashMap::<u128, oneshot::Sender<Frame>>::new()));
        let saudavel = Arc::new(AtomicBool::new(true));

        let (mut read_half, mut write_half) = tokio::io::split(stream);

        // Loop de escrita: consome do canal rx e envia no socket. Ao falhar, marca a
        // conexão como morta para disparar a reconexão na próxima chamada.
        let saudavel_w = saudavel.clone();
        tokio::spawn(async move {
            while let Some(frame) = rx.recv().await {
                if let Err(e) = write_frame(&mut write_half, &frame).await {
                    tracing::error!("Erro de escrita no loop do cliente: {:?}", e);
                    break;
                }
            }
            saudavel_w.store(false, Ordering::SeqCst);
        });

        // Loop de leitura: lê do socket e entrega ao oneshot correspondente (inclui PONGs,
        // que são roteados pelo mesmo corr_id do PING). Ao cair, marca a conexão como morta.
        let pendentes_loop = pendentes.clone();
        let saudavel_r = saudavel.clone();
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
                        tracing::debug!("Loop de leitura encerrado (conexao fechada): {:?}", e);
                        break;
                    }
                }
            }
            saudavel_r.store(false, Ordering::SeqCst);
        });

        Arc::new(Self {
            tx,
            pendentes,
            saudavel,
        })
    }

    fn esta_saudavel(&self) -> bool {
        self.saudavel.load(Ordering::SeqCst)
    }

    fn marcar_morta(&self) {
        self.saudavel.store(false, Ordering::SeqCst);
    }

    /// Registra a chamada pendente e envia o frame; devolve o receiver da resposta.
    async fn enviar(&self, frame: Frame) -> Result<oneshot::Receiver<Frame>, TransportError> {
        let (resp_tx, resp_rx) = oneshot::channel();
        let corr_id = frame.corr_id;
        self.pendentes.lock().await.insert(corr_id, resp_tx);
        if self.tx.send(frame).await.is_err() {
            self.pendentes.lock().await.remove(&corr_id);
            self.marcar_morta();
            return Err(TransportError::Closed);
        }
        Ok(resp_rx)
    }

    async fn remover_pendente(&self, corr_id: u128) {
        self.pendentes.lock().await.remove(&corr_id);
    }
}

/// Dispara um ping periódico (PING→PONG) para detectar conexão morta de forma proativa.
/// Encerra-se sozinho quando a conexão é marcada como não saudável.
fn iniciar_keepalive(conexao: Arc<Conexao>) {
    tokio::spawn(async move {
        let mut ticker = tokio::time::interval(KEEPALIVE_INTERVALO);
        ticker.tick().await; // descarta o primeiro tick imediato
        loop {
            ticker.tick().await;
            if !conexao.esta_saudavel() {
                break;
            }
            let corr_id = uuid::Uuid::now_v7().as_u128();
            let ping = Frame {
                flags: crate::framing::flags::PING,
                corr_id,
                body: Vec::new(),
            };
            let resp_rx = match conexao.enviar(ping).await {
                Ok(rx) => rx,
                Err(_) => break,
            };
            match timeout(KEEPALIVE_TIMEOUT, resp_rx).await {
                Ok(Ok(_)) => {} // PONG recebido: conexão viva
                _ => {
                    tracing::warn!("Keepalive sem PONG no prazo; marcando conexao como morta.");
                    conexao.remover_pendente(corr_id).await;
                    conexao.marcar_morta();
                    break;
                }
            }
        }
    });
}

/// Cliente resiliente que multiplexa várias chamadas na mesma conexão (o que o HTTP/2 dá ao
/// gRPC de graça) e reconecta com backoff exponencial + jitter quando a conexão cai, mantendo
/// keepalive ativo. O `codec` é independente da conexão e sobrevive às reconexões.
pub struct MuxClient {
    endpoint: Endpoint,
    codec: Box<dyn Codec>,
    conexao: Mutex<Option<Arc<Conexao>>>,
}

impl MuxClient {
    /// Conecta a um endpoint estabelecendo já a primeira conexão (falha cedo se indisponível).
    pub async fn conectar(endpoint: Endpoint, codec: Box<dyn Codec>) -> anyhow::Result<Self> {
        let cliente = Self {
            endpoint,
            codec,
            conexao: Mutex::new(None),
        };
        let conexao = cliente.reconectar_com_backoff().await.map_err(|_| {
            anyhow::anyhow!(
                "Falha ao conectar ao endpoint {:?} apos multiplas tentativas",
                cliente.endpoint
            )
        })?;
        iniciar_keepalive(conexao.clone());
        *cliente.conexao.lock().await = Some(conexao);
        Ok(cliente)
    }

    /// Disca o endpoint uma vez e monta a conexão multiplexada.
    async fn discar(&self) -> anyhow::Result<Arc<Conexao>> {
        match &self.endpoint {
            Endpoint::Uds(path) => {
                #[cfg(unix)]
                {
                    let stream = UnixStream::connect(path).await?;
                    Ok(Conexao::nova(stream))
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
                Ok(Conexao::nova(stream))
            }
        }
    }

    /// Tenta reconectar com backoff exponencial e jitter, respeitando um teto de tentativas.
    async fn reconectar_com_backoff(&self) -> Result<Arc<Conexao>, TransportError> {
        let mut atraso = BACKOFF_INICIAL;
        for tentativa in 1..=MAX_TENTATIVAS_RECONEXAO {
            match self.discar().await {
                Ok(conexao) => {
                    if tentativa > 1 {
                        tracing::info!(tentativa, "Reconexao ao endpoint bem-sucedida.");
                    }
                    return Ok(conexao);
                }
                Err(e) => {
                    tracing::warn!(
                        tentativa,
                        atraso_ms = atraso.as_millis() as u64,
                        erro = %e,
                        "Falha ao conectar; aguardando backoff."
                    );
                    if tentativa == MAX_TENTATIVAS_RECONEXAO {
                        break;
                    }
                    sleep(atraso + jitter(atraso)).await;
                    atraso = (atraso * 2).min(BACKOFF_MAX);
                }
            }
        }
        Err(TransportError::Closed)
    }

    /// Garante uma conexão saudável, reconectando (sob lock) quando a atual caiu.
    async fn garantir_conexao(&self) -> Result<Arc<Conexao>, TransportError> {
        let mut guard = self.conexao.lock().await;
        if let Some(c) = guard.as_ref() {
            if c.esta_saudavel() {
                return Ok(c.clone());
            }
        }
        let nova = self.reconectar_com_backoff().await?;
        iniciar_keepalive(nova.clone());
        *guard = Some(nova.clone());
        Ok(nova)
    }

    async fn invalidar_conexao(&self) {
        *self.conexao.lock().await = None;
    }

    /// Executa uma chamada request/reply síncrona com timeout. Reconecta e repete uma vez
    /// quando a conexão cai durante o envio/espera; o timeout do chamador NÃO dispara reconexão.
    pub async fn call(&self, env: Envelope, prazo: Duration) -> Result<Envelope, TransportError> {
        let body = self.codec.encode(&env).to_vec();
        for _ in 0..2 {
            let conexao = self.garantir_conexao().await?;
            let corr_id = uuid::Uuid::now_v7().as_u128();
            let frame = Frame {
                flags: 0,
                corr_id,
                body: body.clone(),
            };

            let resp_rx = match conexao.enviar(frame).await {
                Ok(rx) => rx,
                Err(_) => {
                    self.invalidar_conexao().await;
                    continue;
                }
            };

            match timeout(prazo, resp_rx).await {
                Ok(Ok(f)) => return self.codec.decode(&f.body),
                Ok(Err(_)) => {
                    // Canal fechado pelo loop de leitura: a conexão caiu — reconectar e repetir.
                    self.invalidar_conexao().await;
                    continue;
                }
                Err(_) => {
                    conexao.remover_pendente(corr_id).await;
                    return Err(TransportError::Timeout);
                }
            }
        }
        Err(TransportError::Closed)
    }
}

/// Jitter pseudo-aleatório de até ~1/3 do atraso base, sem dependência externa de RNG.
fn jitter(base: Duration) -> Duration {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.subsec_nanos())
        .unwrap_or(0) as u64;
    let teto = (base.as_millis() as u64 / 3).max(1);
    Duration::from_millis(nanos % teto)
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

        // Keepalive: responde PING com PONG (mesmo corr_id, corpo vazio) sem passar pelos handlers.
        if frame.flags & crate::framing::flags::PING != 0 {
            let pong = Frame {
                flags: crate::framing::flags::PONG,
                corr_id: frame.corr_id,
                body: Vec::new(),
            };
            let _ = write_tx.send(pong).await;
            continue;
        }

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

    // Cliente resiliente: estabelece a conexão inicial e passa a manter keepalive +
    // reconexão automática com backoff a cada `call`.
    MuxClient::conectar(endpoint, codec).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_unix_domain_socket_endpoint_correctly() {
        // Arrange
        let endpoint_str = "unix:///var/run/test.sock";
        
        // Act
        let parsed = Endpoint::parse(endpoint_str);
        
        // Assert
        assert!(parsed.is_ok());
        match parsed.unwrap() {
            Endpoint::Uds(path) => {
                assert_eq!(path.to_str().unwrap(), "/var/run/test.sock");
            }
            _ => panic!("Esperava Endpoint::Uds"),
        }
    }

    #[test]
    fn parses_tcp_socket_endpoint_correctly() {
        // Arrange
        let endpoint_str = "tcp://127.0.0.1:8080";
        
        // Act
        let parsed = Endpoint::parse(endpoint_str);
        
        // Assert
        assert!(parsed.is_ok());
        match parsed.unwrap() {
            Endpoint::Tcp(addr) => {
                assert_eq!(addr.ip().to_string(), "127.0.0.1");
                assert_eq!(addr.port(), 8080);
            }
            _ => panic!("Esperava Endpoint::Tcp"),
        }
    }

    #[test]
    fn fails_to_parse_endpoint_with_invalid_protocol() {
        // Arrange
        let endpoint_str = "invalid://var/run/test.sock";
        
        // Act
        let parsed = Endpoint::parse(endpoint_str);
        
        // Assert
        assert!(parsed.is_err());
    }
}

