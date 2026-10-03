//! Binário do servidor de releases. Toda a lógica mora em `lib.rs`.
//!
//! Ambiente:
//! - `RELEASES_DIR`              (padrão `/data/releases`)
//! - `RELEASES_UPLOAD_TOKEN`     (obrigatório)
//! - `RELEASES_DOWNLOAD_SECRET`  (vazio = downloads de instalador recusados)
//! - `RELEASES_BIND`             (padrão `0.0.0.0:8086`)
//! - `RELEASES_MAX_UPLOAD_MB`    (padrão 500)

use std::net::SocketAddr;
use std::path::PathBuf;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new("releases_server=info,tower_http=info")),
        )
        .with_target(true)
        .json()
        .init();

    let dir = std::env::var("RELEASES_DIR").unwrap_or_else(|_| "/data/releases".to_string());
    let token_upload = std::env::var("RELEASES_UPLOAD_TOKEN")
        .map_err(|_| anyhow::anyhow!("RELEASES_UPLOAD_TOKEN não definido (obrigatório)"))?;
    let segredo_download = std::env::var("RELEASES_DOWNLOAD_SECRET").unwrap_or_default();
    let limite_mb: usize = std::env::var("RELEASES_MAX_UPLOAD_MB")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(500);
    let bind = std::env::var("RELEASES_BIND").unwrap_or_else(|_| "0.0.0.0:8086".to_string());

    let app = releases_server::app(releases_server::Config {
        dir: PathBuf::from(&dir),
        segredo_download,
        token_upload,
        limite_upload_bytes: limite_mb * 1024 * 1024,
    })?;

    let listener = tokio::net::TcpListener::bind(&bind).await?;
    tracing::info!(bind = %bind, dir = %dir, "releases_server no ar");
    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .with_graceful_shutdown(sinal_de_parada())
    .await?;
    Ok(())
}

/// Ctrl+C ou SIGTERM (o `docker stop` manda SIGTERM; como PID 1 sem handler, o
/// processo só morreria no SIGKILL do timeout).
async fn sinal_de_parada() {
    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};
        match signal(SignalKind::terminate()) {
            Ok(mut term) => {
                tokio::select! {
                    _ = tokio::signal::ctrl_c() => {}
                    _ = term.recv() => {}
                }
            }
            Err(_) => {
                let _ = tokio::signal::ctrl_c().await;
            }
        }
    }
    #[cfg(not(unix))]
    {
        let _ = tokio::signal::ctrl_c().await;
    }
}
