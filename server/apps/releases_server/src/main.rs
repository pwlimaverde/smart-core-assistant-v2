use axum::{
    extract::{multipart::Multipart, Path, State},
    http::{header, status, HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, post},
    Router,
};
use serde::{Deserialize, Serialize};
use secrecy::{Secret, SecretString};
use sha2::{Digest, Sha256};
use std::sync::Arc;
use tokio::net::TcpListener;
use tower_http::{
    compression::CompressionLayer, cors::CorsLayer, services::ServeDir,
    trace::TraceLayer,
};
use tracing::{debug, error, info, instrument, warn};
use tracing_subscriber::EnvFilter;

// ============================================================================
// Types & State
// ============================================================================

#[derive(Clone)]
struct AppState {
    releases_dir: String,
    upload_token: SecretString,
}

#[derive(Serialize, Deserialize, Clone)]
struct ReleaseInfo {
    version: String,
    url: String,
    sha256: String,
    mandatory: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    release_notes: Option<String>,
}

#[derive(Deserialize)]
struct UploadRequest {
    version: String,
}

#[derive(Serialize)]
struct UploadResponse {
    status: String,
    version: String,
    message: String,
}

#[derive(Debug)]
enum ApiError {
    Unauthorized,
    InvalidVersion,
    FileNotFound,
    IoError(String),
    InvalidMultipart(String),
    InvalidHash,
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, error_message) = match self {
            ApiError::Unauthorized => (
                StatusCode::UNAUTHORIZED,
                "Invalid or missing authorization token",
            ),
            ApiError::InvalidVersion => (StatusCode::BAD_REQUEST, "Invalid version format"),
            ApiError::FileNotFound => (StatusCode::NOT_FOUND, "Release not found"),
            ApiError::IoError(msg) => (StatusCode::INTERNAL_SERVER_ERROR, &msg),
            ApiError::InvalidMultipart(msg) => (StatusCode::BAD_REQUEST, &msg),
            ApiError::InvalidHash => (
                StatusCode::INTERNAL_SERVER_ERROR,
                "Hash verification failed",
            ),
        };

        (status, error_message).into_response()
    }
}

// ============================================================================
// Handlers
// ============================================================================

#[instrument(skip(state), fields(channel = "stable"))]
async fn get_releases(State(state): State<Arc<AppState>>) -> Result<String, ApiError> {
    debug!("Checking latest release");

    // TODO: Load from releases.win.json
    let release = ReleaseInfo {
        version: "0.1.0".to_string(),
        url: "https://releases.smartcoreassistant.com.br/download/0.1.0/app-0.1.0-full.nupkg"
            .to_string(),
        sha256: "abcd1234".to_string(),
        mandatory: false,
        release_notes: Some("Initial release".to_string()),
    };

    info!(version = %release.version, "Release found");

    Ok(serde_json::to_string(&release).map_err(|e| {
        error!("JSON serialization error: {}", e);
        ApiError::IoError("Failed to serialize release info".to_string())
    })?)
}

#[instrument(skip(state, auth), fields(auth_length = auth.len()))]
async fn upload_release(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    mut multipart: Multipart,
) -> Result<String, ApiError> {
    // Validate Bearer token
    let auth = headers
        .get(header::AUTHORIZATION)
        .and_then(|h| h.to_str().ok())
        .and_then(|s| s.strip_prefix("Bearer "))
        .map(|s| s.to_string());

    if auth.is_none() {
        warn!("Upload attempted without authorization header");
        return Err(ApiError::Unauthorized);
    }

    // Constant-time comparison
    let provided_token = auth.unwrap();
    let expected_token = state.upload_token.expose_secret();

    if !constant_time_compare(provided_token.as_bytes(), expected_token.as_bytes()) {
        warn!("Upload attempted with invalid token (first 8 chars of hash: {})",
              &sha256_hex(&provided_token)[0..8]);
        return Err(ApiError::Unauthorized);
    }

    info!("Upload authorized, processing multipart");

    // TODO: Extract version, file from multipart
    // TODO: Validate filename pattern
    // TODO: Stream to disk, verify SHA256
    // TODO: Update releases.win.json atomically

    let response = UploadResponse {
        status: "success".to_string(),
        version: "0.1.0".to_string(),
        message: "Upload successful".to_string(),
    };

    info!(version = %response.version, "Upload completed");

    Ok(serde_json::to_string(&response).map_err(|e| {
        error!("JSON serialization error: {}", e);
        ApiError::IoError("Failed to serialize response".to_string())
    })?)
}

#[instrument(skip(state), fields(version = %version, filename = %filename))]
async fn download_release(
    State(state): State<Arc<AppState>>,
    Path((version, filename)): Path<(String, String)>,
) -> Result<impl IntoResponse, ApiError> {
    debug!("Download requested");

    // TODO: Validate version & filename format
    // TODO: Serve from /opt/smartcore/releases/{version}/{filename}
    // TODO: Return with Content-Type, Content-Length

    info!("Download completed");

    Ok((StatusCode::OK, "file content here"))
}

#[instrument(skip(state))]
async fn healthcheck(State(_state): State<Arc<AppState>>) -> StatusCode {
    debug!("Health check");
    StatusCode::OK
}

// ============================================================================
// Utilities
// ============================================================================

fn sha256_hex(data: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data.as_bytes());
    hex::encode(hasher.finalize())
}

fn constant_time_compare(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut result = 0u8;
    for (x, y) in a.iter().zip(b.iter()) {
        result |= x ^ y;
    }
    result == 0
}

// ============================================================================
// Main
// ============================================================================

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::from_default_env()
                .add_directive("releases_server=debug".parse()?)
                .add_directive("tower_http=debug".parse()?),
        )
        .with_target(true)
        .with_thread_ids(true)
        .init();

    info!("Starting releases server");

    let releases_dir = std::env::var("RELEASES_DIR").unwrap_or_else(|_| {
        warn!("RELEASES_DIR not set, using default: /tmp/releases");
        "/tmp/releases".to_string()
    });

    let upload_token = std::env::var("UPLOAD_TOKEN").map(SecretString::new)?;

    let state = Arc::new(AppState {
        releases_dir: releases_dir.clone(),
        upload_token,
    });

    // Build router
    let app = Router::new()
        .route("/api/releases", get(get_releases))
        .route("/upload", post(upload_release))
        .route("/download/:version/:filename", get(download_release))
        .route("/health", get(healthcheck))
        .nest_service(
            "/releases",
            ServeDir::new(&releases_dir).append_index_html_on_directories(false),
        )
        .layer(TraceLayer::new_for_http())
        .layer(
            CompressionLayer::new()
                .gzip(true)
                .br(true)
                .compress_when(tower_http::compression::predicate::SizeAbove::new(256)),
        )
        .layer(
            CorsLayer::new()
                .allow_origin("https://smartcoreassistant.com.br".parse()?),
        )
        .with_state(state);

    // Bind and serve
    let listener = TcpListener::bind("0.0.0.0:8086").await?;
    info!("Server listening on http://0.0.0.0:8086");

    axum::serve(listener, app).await?;

    Ok(())
}
