//! Servidor de releases do app Windows (Velopack) — Axum 0.8.
//!
//! Rotas:
//! - `GET  /health`                         → liveness.
//! - `GET  /api/installers/{canal}`         → manifesto dos instaladores do canal
//!   (metadado público: versão, arquivo, sha256, tamanho, notas). É o que o
//!   `control_plane` lê antes de assinar um ticket.
//! - `GET  /feed/{canal}/{arquivo}`         → feed do Velopack (`releases.{canal}.json`,
//!   `*.nupkg`, `RELEASES-{canal}`, `assets.{canal}.json`). Público com rate limit
//!   (decisão D2): o app instalado exige login de qualquer forma.
//! - `GET  /download/{versao}/{arquivo}?t=` → instalador (`*Setup.exe`), só com ticket
//!   HMAC válido emitido pelo `control_plane` (crate `release_ticket`).
//! - `POST /upload`                         → publicação pelo CI (Bearer token).
//!
//! Layout em disco (`RELEASES_DIR`):
//! ```text
//! {dir}/{canal}/installers.json
//! {dir}/{canal}/installers/{versao}/{arquivo}-Setup.exe
//! {dir}/{canal}/feed/releases.{canal}.json | *.nupkg | RELEASES-{canal} | assets.{canal}.json
//! {dir}/.staging/{uuid}/                   (upload em andamento; removido ao final)
//! ```
//!
//! Nada fora dessas pastas é servido: não existe `ServeDir` (achado G5 — o
//! diretório inteiro, `.env` incluso, ficava público). Todo nome que vira caminho
//! passa por uma allowlist de caracteres, então `..`, `/` e `\` nunca chegam ao
//! sistema de arquivos.

use axum::{
    extract::{ConnectInfo, DefaultBodyLimit, FromRequestParts, Multipart, Path, Query, State},
    http::{header, request::Parts, HeaderMap, HeaderValue, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use dashmap::DashMap;
use release_ticket::manifesto::{Instalador, ManifestoInstaladores};
use secrecy::{ExposeSecret, SecretString};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::path::{Path as FsPath, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use subtle::ConstantTimeEq;
use tokio::fs;
use tokio::io::AsyncWriteExt;
use tokio_util::io::ReaderStream;
use tower_http::trace::TraceLayer;
use tracing::{info, warn};

/// Canais aceitos. `stable` fica reservado para v1.0.0+ (o control_plane recusa).
pub const CANAIS: &[&str] = &["beta", "stable"];

/// Limites por IP e por minuto.
const LIMITE_DOWNLOAD: u32 = 30;
const LIMITE_FEED: u32 = 120;
const LIMITE_API: u32 = 60;
const LIMITE_UPLOAD: u32 = 5;
const JANELA: Duration = Duration::from_secs(60);

/// Acima disto o mapa de IPs é podado (evita crescimento sem limite).
const MAX_IPS_RASTREADOS: usize = 10_000;

// ============================================================================
// Configuração e estado
// ============================================================================

/// Configuração do servidor (lida do ambiente em `main.rs`).
pub struct Config {
    pub dir: PathBuf,
    /// `RELEASES_DOWNLOAD_SECRET`. Vazio = downloads recusados (fechado).
    pub segredo_download: String,
    /// `RELEASES_UPLOAD_TOKEN`. Obrigatório.
    pub token_upload: String,
    /// Tamanho máximo do corpo do upload.
    pub limite_upload_bytes: usize,
}

#[derive(Default)]
struct Limitador {
    janelas: DashMap<String, (u32, Instant)>,
}

impl Limitador {
    fn checar(&self, ip: &str, maximo: u32) -> Result<(), ApiErro> {
        let agora = Instant::now();
        if self.janelas.len() > MAX_IPS_RASTREADOS {
            self.janelas
                .retain(|_, (_, inicio)| agora.duration_since(*inicio) <= JANELA);
        }
        let mut entrada = self.janelas.entry(ip.to_string()).or_insert((0, agora));
        let (contagem, inicio) = entrada.value_mut();
        if agora.duration_since(*inicio) > JANELA {
            *contagem = 0;
            *inicio = agora;
        }
        *contagem += 1;
        if *contagem > maximo {
            warn!(ip = %ip, contagem = *contagem, "limite de requisições excedido");
            return Err(ApiErro::LimiteExcedido);
        }
        Ok(())
    }
}

struct AppState {
    dir: PathBuf,
    segredo_download: SecretString,
    /// Só o hash do token fica em memória: a comparação é entre dois digests de
    /// 32 bytes, em tempo constante, e não vaza o tamanho do token (achado G15).
    hash_token_upload: [u8; 32],
    lim_download: Limitador,
    lim_feed: Limitador,
    lim_api: Limitador,
    lim_upload: Limitador,
    /// Um upload por vez: a troca do feed precisa ser atômica do ponto de vista do app.
    trava_upload: tokio::sync::Mutex<()>,
}

/// Monta o roteador. Falha se o token de upload estiver vazio.
pub fn app(cfg: Config) -> anyhow::Result<Router> {
    if cfg.token_upload.trim().is_empty() {
        anyhow::bail!("RELEASES_UPLOAD_TOKEN vazio");
    }
    if cfg.segredo_download.is_empty() {
        warn!("RELEASES_DOWNLOAD_SECRET vazio: downloads de instalador serão recusados");
    }
    let state = Arc::new(AppState {
        dir: cfg.dir,
        segredo_download: SecretString::from(cfg.segredo_download),
        hash_token_upload: sha256(cfg.token_upload.as_bytes()),
        lim_download: Limitador::default(),
        lim_feed: Limitador::default(),
        lim_api: Limitador::default(),
        lim_upload: Limitador::default(),
        trava_upload: tokio::sync::Mutex::new(()),
    });

    Ok(Router::new()
        .route("/health", get(|| async { "ok" }))
        .route("/api/installers/{canal}", get(listar_instaladores))
        .route("/feed/{canal}/{arquivo}", get(servir_feed))
        .route("/download/{versao}/{arquivo}", get(baixar_instalador))
        .route(
            "/upload",
            post(publicar).layer(DefaultBodyLimit::max(cfg.limite_upload_bytes)),
        )
        .layer(TraceLayer::new_for_http())
        .with_state(state))
}

// ============================================================================
// Erros
// ============================================================================

#[derive(Debug)]
enum ApiErro {
    NaoAutorizado,
    TicketInvalido,
    NaoEncontrado,
    Invalido(String),
    LimiteExcedido,
    Indisponivel,
    Interno(String),
}

impl IntoResponse for ApiErro {
    fn into_response(self) -> Response {
        let (status, msg) = match self {
            ApiErro::NaoAutorizado => (StatusCode::UNAUTHORIZED, "não autorizado".to_string()),
            ApiErro::TicketInvalido => (
                StatusCode::UNAUTHORIZED,
                "ticket de download inválido ou expirado".to_string(),
            ),
            ApiErro::NaoEncontrado => (StatusCode::NOT_FOUND, "não encontrado".to_string()),
            ApiErro::Invalido(m) => (StatusCode::BAD_REQUEST, m),
            ApiErro::LimiteExcedido => (
                StatusCode::TOO_MANY_REQUESTS,
                "limite de requisições excedido".to_string(),
            ),
            ApiErro::Indisponivel => (
                StatusCode::SERVICE_UNAVAILABLE,
                "downloads desabilitados".to_string(),
            ),
            ApiErro::Interno(detalhe) => {
                // O detalhe vai para o log, nunca para o cliente.
                tracing::error!(detalhe = %detalhe, "erro interno");
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "erro interno".to_string(),
                )
            }
        };
        (status, Json(serde_json::json!({ "erro": msg }))).into_response()
    }
}

impl From<std::io::Error> for ApiErro {
    fn from(e: std::io::Error) -> Self {
        if e.kind() == std::io::ErrorKind::NotFound {
            ApiErro::NaoEncontrado
        } else {
            ApiErro::Interno(e.to_string())
        }
    }
}

// ============================================================================
// IP do cliente
// ============================================================================

/// IP do cliente para o rate limit. Atrás do Caddy vem no `X-Forwarded-For`
/// (primeiro elemento); sem proxy, do `ConnectInfo` do socket.
struct ClientIp(String);

impl<S: Send + Sync> FromRequestParts<S> for ClientIp {
    type Rejection = std::convert::Infallible;

    async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self, Self::Rejection> {
        let encaminhado = parts
            .headers
            .get("x-forwarded-for")
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.split(',').next())
            .map(|v| v.trim().to_string())
            .filter(|v| !v.is_empty());
        let ip = encaminhado
            .or_else(|| {
                parts
                    .extensions
                    .get::<ConnectInfo<SocketAddr>>()
                    .map(|c| c.0.ip().to_string())
            })
            .unwrap_or_else(|| "desconhecido".to_string());
        Ok(ClientIp(ip))
    }
}

// ============================================================================
// Validação de nomes (allowlist)
// ============================================================================

fn canal_valido(canal: &str) -> bool {
    CANAIS.contains(&canal)
}

/// Versão semver-like: começa com dígito; só `[0-9A-Za-z.-]`; sem `..`.
pub fn versao_valida(versao: &str) -> bool {
    !versao.is_empty()
        && versao.len() <= 64
        && versao.starts_with(|c: char| c.is_ascii_digit())
        && !versao.contains("..")
        && versao
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '-')
}

/// Nome de arquivo: só `[A-Za-z0-9._-]`, sem começar por `.` e sem `..`.
fn nome_seguro(nome: &str) -> bool {
    !nome.is_empty()
        && nome.len() <= 128
        && !nome.starts_with('.')
        && !nome.contains("..")
        && nome
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '-' || c == '_')
}

fn nome_instalador(nome: &str) -> bool {
    nome_seguro(nome) && nome.ends_with("Setup.exe")
}

/// Arquivos que o Velopack gera para o feed de um canal.
fn nome_feed(canal: &str, nome: &str) -> bool {
    let entre = |prefixo: &str, sufixo: &str| {
        nome.strip_prefix(prefixo)
            .and_then(|resto| resto.strip_suffix(sufixo))
            == Some(canal)
    };
    nome_seguro(nome)
        && (entre("releases.", ".json")
            || entre("assets.", ".json")
            || entre("RELEASES-", "")
            || nome.ends_with(".nupkg"))
}

// ============================================================================
// Manifesto dos instaladores
// ============================================================================

async fn ler_manifesto(caminho: &FsPath) -> Result<ManifestoInstaladores, ApiErro> {
    match fs::read(caminho).await {
        Ok(bytes) => serde_json::from_slice(&bytes)
            .map_err(|e| ApiErro::Interno(format!("installers.json inválido: {e}"))),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(ManifestoInstaladores::default()),
        Err(e) => Err(e.into()),
    }
}

/// Escreve num temporário e renomeia: quem lê nunca vê um JSON pela metade.
async fn gravar_atomico(destino: &FsPath, conteudo: &[u8]) -> Result<(), ApiErro> {
    let tmp = destino.with_extension(format!("tmp-{}", uuid::Uuid::new_v4()));
    fs::write(&tmp, conteudo).await?;
    fs::rename(&tmp, destino).await?;
    Ok(())
}

// ============================================================================
// Utilidades
// ============================================================================

fn sha256(dados: &[u8]) -> [u8; 32] {
    Sha256::digest(dados).into()
}

fn agora_unix() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

async fn servir_arquivo(caminho: PathBuf, nome: &str, anexo: bool) -> Result<Response, ApiErro> {
    let arquivo = fs::File::open(&caminho).await?;
    let meta = arquivo.metadata().await?;
    if !meta.is_file() {
        return Err(ApiErro::NaoEncontrado);
    }
    let tipo = if nome.ends_with(".json") {
        "application/json"
    } else {
        "application/octet-stream"
    };
    let mut headers = HeaderMap::new();
    headers.insert(header::CONTENT_TYPE, HeaderValue::from_static(tipo));
    headers.insert(header::CONTENT_LENGTH, HeaderValue::from(meta.len()));
    if anexo {
        // `nome` já passou pela allowlist: não há aspas nem quebra de linha.
        if let Ok(v) = HeaderValue::from_str(&format!("attachment; filename=\"{nome}\"")) {
            headers.insert(header::CONTENT_DISPOSITION, v);
        }
    }
    let corpo = axum::body::Body::from_stream(ReaderStream::new(arquivo));
    Ok((headers, corpo).into_response())
}

// ============================================================================
// Handlers
// ============================================================================

async fn listar_instaladores(
    State(st): State<Arc<AppState>>,
    ClientIp(ip): ClientIp,
    Path(canal): Path<String>,
) -> Result<Json<ManifestoInstaladores>, ApiErro> {
    st.lim_api.checar(&ip, LIMITE_API)?;
    if !canal_valido(&canal) {
        return Err(ApiErro::Invalido("canal inválido".into()));
    }
    Ok(Json(
        ler_manifesto(&st.dir.join(&canal).join("installers.json")).await?,
    ))
}

async fn servir_feed(
    State(st): State<Arc<AppState>>,
    ClientIp(ip): ClientIp,
    Path((canal, arquivo)): Path<(String, String)>,
) -> Result<Response, ApiErro> {
    st.lim_feed.checar(&ip, LIMITE_FEED)?;
    if !canal_valido(&canal) || !nome_feed(&canal, &arquivo) {
        return Err(ApiErro::NaoEncontrado);
    }
    servir_arquivo(
        st.dir.join(&canal).join("feed").join(&arquivo),
        &arquivo,
        false,
    )
    .await
}

async fn baixar_instalador(
    State(st): State<Arc<AppState>>,
    ClientIp(ip): ClientIp,
    Path((versao, arquivo)): Path<(String, String)>,
    Query(query): Query<HashMap<String, String>>,
) -> Result<Response, ApiErro> {
    st.lim_download.checar(&ip, LIMITE_DOWNLOAD)?;

    let segredo = st.segredo_download.expose_secret();
    if segredo.is_empty() {
        return Err(ApiErro::Indisponivel);
    }
    if !versao_valida(&versao) || !nome_instalador(&arquivo) {
        warn!(ip = %ip, evento = "release_download_ticket_rejected", motivo = "nome", "download recusado");
        return Err(ApiErro::NaoEncontrado);
    }
    let Some(ticket) = query.get("t") else {
        warn!(ip = %ip, evento = "release_download_ticket_rejected", motivo = "sem_ticket", "download recusado");
        return Err(ApiErro::TicketInvalido);
    };

    let claims = match release_ticket::verificar(ticket, segredo.as_bytes(), agora_unix()) {
        Ok(c) => c,
        Err(e) => {
            warn!(ip = %ip, evento = "release_download_ticket_rejected", motivo = %e, "download recusado");
            return Err(ApiErro::TicketInvalido);
        }
    };
    // O ticket autoriza UM arquivo de UMA versão: trocar a URL não serve.
    if claims.ver != versao || claims.file != arquivo || !canal_valido(&claims.ch) {
        warn!(ip = %ip, jti = %claims.jti, evento = "release_download_ticket_rejected", motivo = "recurso_divergente", "download recusado");
        return Err(ApiErro::TicketInvalido);
    }

    let caminho = st
        .dir
        .join(&claims.ch)
        .join("installers")
        .join(&versao)
        .join(&arquivo);
    let resposta = servir_arquivo(caminho, &arquivo, true).await?;
    info!(
        jti = %claims.jti,
        user_id = claims.sub,
        canal = %claims.ch,
        versao = %versao,
        arquivo = %arquivo,
        evento = "release_downloaded",
        "download autorizado"
    );
    Ok(resposta)
}

/// Arquivo recebido no upload, já gravado no staging.
struct Recebido {
    nome: String,
    sha256: String,
    tamanho: i64,
}

async fn publicar(
    State(st): State<Arc<AppState>>,
    ClientIp(ip): ClientIp,
    headers: HeaderMap,
    mut multipart: Multipart,
) -> Result<Json<serde_json::Value>, ApiErro> {
    st.lim_upload.checar(&ip, LIMITE_UPLOAD)?;

    let token = headers
        .get(header::AUTHORIZATION)
        .and_then(|h| h.to_str().ok())
        .and_then(|s| s.strip_prefix("Bearer "))
        .unwrap_or_default();
    let confere: bool = sha256(token.as_bytes())
        .as_slice()
        .ct_eq(st.hash_token_upload.as_slice())
        .into();
    if token.is_empty() || !confere {
        warn!(ip = %ip, evento = "release_upload_rejected", motivo = "token", "upload recusado");
        return Err(ApiErro::NaoAutorizado);
    }

    let _trava = st.trava_upload.lock().await;
    let staging = st
        .dir
        .join(".staging")
        .join(uuid::Uuid::new_v4().to_string());
    fs::create_dir_all(&staging).await?;
    let resultado = processar_upload(&st, &staging, &mut multipart).await;
    let _ = fs::remove_dir_all(&staging).await;

    match &resultado {
        Ok(v) => info!(ip = %ip, evento = "release_published", resumo = %v, "release publicada"),
        Err(e) => {
            warn!(ip = %ip, evento = "release_upload_rejected", motivo = ?e, "upload recusado")
        }
    }
    resultado.map(Json)
}

async fn processar_upload(
    st: &AppState,
    staging: &FsPath,
    multipart: &mut Multipart,
) -> Result<serde_json::Value, ApiErro> {
    let mut canal = String::new();
    let mut versao = String::new();
    let mut notas = String::new();
    let mut recebidos: Vec<Recebido> = Vec::new();

    let invalido = |m: &str| ApiErro::Invalido(m.to_string());

    while let Some(mut campo) = multipart
        .next_field()
        .await
        .map_err(|e| ApiErro::Invalido(format!("multipart inválido: {e}")))?
    {
        let nome_campo = campo.name().unwrap_or_default().to_string();
        match nome_campo.as_str() {
            "channel" | "version" | "notes" => {
                let texto = campo
                    .text()
                    .await
                    .map_err(|e| ApiErro::Invalido(format!("campo {nome_campo}: {e}")))?;
                if texto.len() > 64 * 1024 {
                    return Err(invalido("campo de texto grande demais"));
                }
                match nome_campo.as_str() {
                    "channel" => canal = texto.trim().to_string(),
                    "version" => versao = texto.trim().to_string(),
                    _ => notas = texto,
                }
            }
            "file" => {
                let nome = campo.file_name().unwrap_or_default().to_string();
                if !nome_seguro(&nome) {
                    return Err(ApiErro::Invalido(format!(
                        "nome de arquivo recusado: {nome:?}"
                    )));
                }
                if recebidos.iter().any(|r| r.nome == nome) {
                    return Err(ApiErro::Invalido(format!("arquivo repetido: {nome}")));
                }
                let mut destino = fs::File::create(staging.join(&nome)).await?;
                let mut hasher = Sha256::new();
                let mut tamanho: i64 = 0;
                while let Some(pedaco) = campo
                    .chunk()
                    .await
                    .map_err(|e| ApiErro::Invalido(format!("falha lendo {nome}: {e}")))?
                {
                    hasher.update(&pedaco);
                    tamanho += pedaco.len() as i64;
                    destino.write_all(&pedaco).await?;
                }
                destino.flush().await?;
                recebidos.push(Recebido {
                    nome,
                    sha256: hex::encode(hasher.finalize()),
                    tamanho,
                });
            }
            outro => return Err(ApiErro::Invalido(format!("campo desconhecido: {outro}"))),
        }
    }

    if !canal_valido(&canal) {
        return Err(invalido("channel inválido"));
    }
    if !versao_valida(&versao) {
        return Err(invalido("version inválida"));
    }

    let (instaladores, feed): (Vec<&Recebido>, Vec<&Recebido>) =
        recebidos.iter().partition(|r| nome_instalador(&r.nome));
    if instaladores.len() != 1 {
        return Err(invalido("envie exatamente um *Setup.exe"));
    }
    if let Some(r) = feed.iter().find(|r| !nome_feed(&canal, &r.nome)) {
        return Err(ApiErro::Invalido(format!(
            "arquivo fora do feed do canal {canal}: {}",
            r.nome
        )));
    }
    let feed_json = format!("releases.{canal}.json");
    if !feed.iter().any(|r| r.nome == feed_json) {
        return Err(ApiErro::Invalido(format!(
            "falta o {feed_json} do Velopack"
        )));
    }

    // 1) instalador da versão
    let instalador = instaladores[0];
    let dir_versao = st.dir.join(&canal).join("installers").join(&versao);
    fs::create_dir_all(&dir_versao).await?;
    fs::rename(
        staging.join(&instalador.nome),
        dir_versao.join(&instalador.nome),
    )
    .await?;

    // 2) pacotes do feed antes dos índices: quando o app enxergar o
    //    releases.{canal}.json novo, os .nupkg que ele cita já existem.
    let dir_feed = st.dir.join(&canal).join("feed");
    fs::create_dir_all(&dir_feed).await?;
    let (indices, pacotes): (Vec<&&Recebido>, Vec<&&Recebido>) =
        feed.iter().partition(|r| !r.nome.ends_with(".nupkg"));
    for r in pacotes.iter().chain(indices.iter()) {
        fs::rename(staging.join(&r.nome), dir_feed.join(&r.nome)).await?;
    }

    // 3) manifesto dos instaladores (substitui a mesma versão, se republicada)
    let caminho_manifesto = st.dir.join(&canal).join("installers.json");
    let mut manifesto = ler_manifesto(&caminho_manifesto).await?;
    manifesto.installers.retain(|i| i.version != versao);
    manifesto.installers.push(Instalador {
        version: versao.clone(),
        file_name: instalador.nome.clone(),
        sha256: instalador.sha256.clone(),
        size_bytes: instalador.tamanho,
        release_notes_md: notas,
        published_at_ms: agora_unix() * 1000,
    });
    let bytes = serde_json::to_vec_pretty(&manifesto)
        .map_err(|e| ApiErro::Interno(format!("serializar installers.json: {e}")))?;
    gravar_atomico(&caminho_manifesto, &bytes).await?;

    Ok(serde_json::json!({
        "status": "publicado",
        "channel": canal,
        "version": versao,
        "installer": instalador.nome,
        "sha256": instalador.sha256,
        "size_bytes": instalador.tamanho,
        "feed_files": feed.iter().map(|r| r.nome.clone()).collect::<Vec<_>>(),
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn versoes() {
        for ok in ["0.1.0", "0.2.0-beta.1", "1.0.0"] {
            assert!(versao_valida(ok), "{ok}");
        }
        for ruim in ["", "v1", "../1", "1..0", "1/0", "1\\0", &"1".repeat(70)] {
            assert!(!versao_valida(ruim), "{ruim}");
        }
    }

    #[test]
    fn nomes_de_arquivo() {
        assert!(nome_instalador("SmartCoreTenant-beta-Setup.exe"));
        assert!(!nome_instalador(".env"));
        assert!(!nome_instalador("..Setup.exe"));
        assert!(!nome_instalador("a/b-Setup.exe"));
        assert!(nome_feed("beta", "releases.beta.json"));
        assert!(nome_feed("beta", "RELEASES-beta"));
        assert!(nome_feed("beta", "SmartCoreTenant-0.2.0-beta.1-full.nupkg"));
        assert!(!nome_feed("beta", "releases.stable.json"));
        assert!(!nome_feed("beta", "server.log"));
    }
}
