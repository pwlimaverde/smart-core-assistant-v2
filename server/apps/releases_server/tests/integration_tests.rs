//! Matriz V1–V14 do releases_server contra o roteador REAL (`releases_server::app`),
//! via `tower::ServiceExt::oneshot` — sem porta de rede e sem reimplementar handler.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use axum::Router;
use http_body_util::BodyExt;
use release_ticket::{Claims, TTL_SEGUNDOS, VERSAO_FORMATO};
use std::time::{SystemTime, UNIX_EPOCH};
use tempfile::TempDir;
use tower::ServiceExt;

const SEGREDO: &str = "segredo-de-download-de-teste-32b!";
const TOKEN: &str = "token-de-upload-de-teste";
const VERSAO: &str = "0.2.0-beta.1";
const SETUP: &str = "SmartCoreTenant-beta-Setup.exe";
const CONTEUDO_SETUP: &[u8] = b"MZ conteudo de teste do instalador";

fn agora() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64
}

fn montar(dir: &TempDir, segredo: &str) -> Router {
    releases_server::app(releases_server::Config {
        dir: dir.path().to_path_buf(),
        segredo_download: segredo.to_string(),
        token_upload: TOKEN.to_string(),
        limite_upload_bytes: 10 * 1024 * 1024,
    })
    .expect("config válida")
}

/// Cria um instalador publicado direto no disco (sem passar pelo upload).
fn semear_instalador(dir: &TempDir) {
    let pasta = dir.path().join("beta/installers").join(VERSAO);
    std::fs::create_dir_all(&pasta).unwrap();
    std::fs::write(pasta.join(SETUP), CONTEUDO_SETUP).unwrap();
}

fn ticket(segredo: &str, ver: &str, file: &str, iat: i64) -> String {
    let claims = Claims {
        v: VERSAO_FORMATO,
        kid: "teste".into(),
        jti: "jti-teste".into(),
        sub: 1,
        ver: ver.into(),
        file: file.into(),
        ch: "beta".into(),
        iat,
        exp: iat + TTL_SEGUNDOS,
    };
    release_ticket::assinar(&claims, segredo.as_bytes()).unwrap()
}

async fn get(app: &Router, uri: &str) -> (StatusCode, Vec<u8>) {
    let resp = app
        .clone()
        .oneshot(Request::get(uri).body(Body::empty()).unwrap())
        .await
        .unwrap();
    let status = resp.status();
    let corpo = resp
        .into_body()
        .collect()
        .await
        .unwrap()
        .to_bytes()
        .to_vec();
    (status, corpo)
}

const FRONTEIRA: &str = "----fronteira-de-teste";

/// Monta um corpo multipart/form-data: campos de texto + arquivos.
fn multipart(campos: &[(&str, &str)], arquivos: &[(&str, &[u8])]) -> Vec<u8> {
    let mut corpo = Vec::new();
    for (nome, valor) in campos {
        corpo.extend_from_slice(
            format!(
                "--{FRONTEIRA}\r\nContent-Disposition: form-data; name=\"{nome}\"\r\n\r\n{valor}\r\n"
            )
            .as_bytes(),
        );
    }
    for (nome, dados) in arquivos {
        corpo.extend_from_slice(
            format!(
                "--{FRONTEIRA}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{nome}\"\r\nContent-Type: application/octet-stream\r\n\r\n"
            )
            .as_bytes(),
        );
        corpo.extend_from_slice(dados);
        corpo.extend_from_slice(b"\r\n");
    }
    corpo.extend_from_slice(format!("--{FRONTEIRA}--\r\n").as_bytes());
    corpo
}

async fn upload(app: &Router, token: Option<&str>, corpo: Vec<u8>) -> (StatusCode, Vec<u8>) {
    let mut req = Request::post("/upload").header(
        "content-type",
        format!("multipart/form-data; boundary={FRONTEIRA}"),
    );
    if let Some(t) = token {
        req = req.header("authorization", format!("Bearer {t}"));
    }
    let resp = app
        .clone()
        .oneshot(req.body(Body::from(corpo)).unwrap())
        .await
        .unwrap();
    let status = resp.status();
    let corpo = resp
        .into_body()
        .collect()
        .await
        .unwrap()
        .to_bytes()
        .to_vec();
    (status, corpo)
}

fn corpo_upload_completo() -> Vec<u8> {
    multipart(
        &[
            ("channel", "beta"),
            ("version", VERSAO),
            ("notes", "Primeira beta"),
        ],
        &[
            ("SmartCoreTenant-0.2.0-beta.1-full.nupkg", b"PK pacote"),
            ("RELEASES-beta", b"indice legado"),
            ("releases.beta.json", br#"{"Assets":[]}"#),
            (SETUP, CONTEUDO_SETUP),
        ],
    )
}

#[tokio::test]
async fn v1_health_responde_200() {
    let dir = TempDir::new().unwrap();
    let app = montar(&dir, SEGREDO);
    assert_eq!(get(&app, "/health").await.0, StatusCode::OK);
}

#[tokio::test]
async fn v2_manifesto_de_canal_vazio_e_canal_invalido() {
    let dir = TempDir::new().unwrap();
    let app = montar(&dir, SEGREDO);
    let (status, corpo) = get(&app, "/api/installers/beta").await;
    assert_eq!(status, StatusCode::OK);
    let v: serde_json::Value = serde_json::from_slice(&corpo).unwrap();
    assert_eq!(v["installers"].as_array().unwrap().len(), 0);
    assert_eq!(
        get(&app, "/api/installers/nightly").await.0,
        StatusCode::BAD_REQUEST
    );
}

#[tokio::test]
async fn v3_download_com_ticket_valido_devolve_o_arquivo() {
    let dir = TempDir::new().unwrap();
    semear_instalador(&dir);
    let app = montar(&dir, SEGREDO);
    let t = ticket(SEGREDO, VERSAO, SETUP, agora());
    let (status, corpo) = get(&app, &format!("/download/{VERSAO}/{SETUP}?t={t}")).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(corpo, CONTEUDO_SETUP);
}

#[tokio::test]
async fn v4_ticket_expirado_recusa_401() {
    let dir = TempDir::new().unwrap();
    semear_instalador(&dir);
    let app = montar(&dir, SEGREDO);
    let t = ticket(SEGREDO, VERSAO, SETUP, agora() - TTL_SEGUNDOS - 5);
    let (status, _) = get(&app, &format!("/download/{VERSAO}/{SETUP}?t={t}")).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn v5_ticket_assinado_com_outro_segredo_recusa_401() {
    let dir = TempDir::new().unwrap();
    semear_instalador(&dir);
    let app = montar(&dir, SEGREDO);
    let t = ticket("segredo-de-atacante", VERSAO, SETUP, agora());
    let (status, _) = get(&app, &format!("/download/{VERSAO}/{SETUP}?t={t}")).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn v6_sem_ticket_recusa_401() {
    let dir = TempDir::new().unwrap();
    semear_instalador(&dir);
    let app = montar(&dir, SEGREDO);
    let (status, _) = get(&app, &format!("/download/{VERSAO}/{SETUP}")).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn v7_ticket_de_outro_arquivo_nao_serve_401() {
    let dir = TempDir::new().unwrap();
    semear_instalador(&dir);
    let app = montar(&dir, SEGREDO);
    let t = ticket(SEGREDO, "0.1.0", SETUP, agora());
    let (status, _) = get(&app, &format!("/download/{VERSAO}/{SETUP}?t={t}")).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn v8_path_traversal_codificado_nao_escapa() {
    let dir = TempDir::new().unwrap();
    std::fs::write(dir.path().join("segredo.txt"), b"nao pode sair").unwrap();
    let app = montar(&dir, SEGREDO);
    let t = ticket(SEGREDO, "..", "segredo.txt", agora());
    for uri in [
        format!("/download/%2e%2e/segredo.txt?t={t}"),
        format!("/download/..%2F..%2F/{SETUP}?t={t}"),
        "/feed/beta/..%2F..%2Fsegredo.txt".to_string(),
    ] {
        let (status, corpo) = get(&app, &uri).await;
        assert_ne!(status, StatusCode::OK, "{uri}");
        assert!(!corpo.starts_with(b"nao pode sair"), "{uri}");
    }
}

#[tokio::test]
async fn v9_feed_nao_publica_arquivos_fora_da_allowlist() {
    let dir = TempDir::new().unwrap();
    let feed = dir.path().join("beta/feed");
    std::fs::create_dir_all(&feed).unwrap();
    std::fs::write(feed.join(".env"), b"RELEASES_UPLOAD_TOKEN=x").unwrap();
    std::fs::write(feed.join("server.log"), b"log").unwrap();
    std::fs::write(feed.join("releases.beta.json"), br#"{"Assets":[]}"#).unwrap();
    let app = montar(&dir, SEGREDO);
    assert_eq!(get(&app, "/feed/beta/.env").await.0, StatusCode::NOT_FOUND);
    assert_eq!(
        get(&app, "/feed/beta/server.log").await.0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        get(&app, "/feed/beta/releases.beta.json").await.0,
        StatusCode::OK
    );
}

#[tokio::test]
async fn v10_rate_limit_de_download_em_30_por_minuto() {
    let dir = TempDir::new().unwrap();
    semear_instalador(&dir);
    let app = montar(&dir, SEGREDO);
    let t = ticket(SEGREDO, VERSAO, SETUP, agora());
    let uri = format!("/download/{VERSAO}/{SETUP}?t={t}");
    for i in 0..30 {
        assert_eq!(get(&app, &uri).await.0, StatusCode::OK, "requisição {i}");
    }
    assert_eq!(get(&app, &uri).await.0, StatusCode::TOO_MANY_REQUESTS);
}

#[tokio::test]
async fn v11_upload_sem_token_ou_com_token_errado_recusa_401() {
    let dir = TempDir::new().unwrap();
    let app = montar(&dir, SEGREDO);
    assert_eq!(
        upload(&app, None, corpo_upload_completo()).await.0,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        upload(&app, Some("errado"), corpo_upload_completo())
            .await
            .0,
        StatusCode::UNAUTHORIZED
    );
    assert!(!dir.path().join("beta").exists(), "nada pode ser gravado");
}

#[tokio::test]
async fn v12_upload_valido_publica_feed_instalador_e_manifesto() {
    let dir = TempDir::new().unwrap();
    let app = montar(&dir, SEGREDO);
    let (status, corpo) = upload(&app, Some(TOKEN), corpo_upload_completo()).await;
    assert_eq!(
        status,
        StatusCode::OK,
        "{}",
        String::from_utf8_lossy(&corpo)
    );

    // feed do Velopack
    assert_eq!(
        get(&app, "/feed/beta/releases.beta.json").await.1,
        br#"{"Assets":[]}"#
    );
    assert_eq!(
        get(&app, "/feed/beta/SmartCoreTenant-0.2.0-beta.1-full.nupkg")
            .await
            .0,
        StatusCode::OK
    );

    // manifesto com o hash calculado pelo servidor
    let (_, corpo) = get(&app, "/api/installers/beta").await;
    let v: serde_json::Value = serde_json::from_slice(&corpo).unwrap();
    let inst = &v["installers"][0];
    assert_eq!(inst["version"], VERSAO);
    assert_eq!(inst["file_name"], SETUP);
    assert_eq!(inst["size_bytes"], CONTEUDO_SETUP.len() as i64);
    assert_eq!(inst["release_notes_md"], "Primeira beta");
    assert_eq!(inst["sha256"].as_str().unwrap().len(), 64);

    // e o instalador sai com ticket
    let t = ticket(SEGREDO, VERSAO, SETUP, agora());
    let (status, corpo) = get(&app, &format!("/download/{VERSAO}/{SETUP}?t={t}")).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(corpo, CONTEUDO_SETUP);

    // republicar a mesma versão não duplica a entrada; staging foi limpo
    assert_eq!(
        upload(&app, Some(TOKEN), corpo_upload_completo()).await.0,
        StatusCode::OK
    );
    let (_, corpo) = get(&app, "/api/installers/beta").await;
    let v: serde_json::Value = serde_json::from_slice(&corpo).unwrap();
    assert_eq!(v["installers"].as_array().unwrap().len(), 1);
    let staging = dir.path().join(".staging");
    assert_eq!(std::fs::read_dir(staging).unwrap().count(), 0);
}

#[tokio::test]
async fn v13_upload_incompleto_ou_com_nome_proibido_recusa_400() {
    let dir = TempDir::new().unwrap();
    let app = montar(&dir, SEGREDO);
    let sem_feed = multipart(
        &[("channel", "beta"), ("version", VERSAO)],
        &[(SETUP, CONTEUDO_SETUP)],
    );
    assert_eq!(
        upload(&app, Some(TOKEN), sem_feed).await.0,
        StatusCode::BAD_REQUEST
    );
    let nome_proibido = multipart(
        &[("channel", "beta"), ("version", VERSAO)],
        &[(".env", b"x"), (SETUP, CONTEUDO_SETUP)],
    );
    assert_eq!(
        upload(&app, Some(TOKEN), nome_proibido).await.0,
        StatusCode::BAD_REQUEST
    );
    let canal_ruim = multipart(
        &[("channel", "nightly"), ("version", VERSAO)],
        &[("releases.nightly.json", b"{}"), (SETUP, CONTEUDO_SETUP)],
    );
    assert_eq!(
        upload(&app, Some(TOKEN), canal_ruim).await.0,
        StatusCode::BAD_REQUEST
    );
    assert!(!dir.path().join("beta/installers").exists());
}

#[tokio::test]
async fn v14_sem_segredo_de_download_o_download_fica_fechado() {
    let dir = TempDir::new().unwrap();
    semear_instalador(&dir);
    let app = montar(&dir, "");
    let t = ticket(SEGREDO, VERSAO, SETUP, agora());
    let (status, _) = get(&app, &format!("/download/{VERSAO}/{SETUP}?t={t}")).await;
    assert_eq!(status, StatusCode::SERVICE_UNAVAILABLE);
}

#[test]
fn token_de_upload_vazio_impede_a_subida() {
    let dir = TempDir::new().unwrap();
    let r = releases_server::app(releases_server::Config {
        dir: dir.path().to_path_buf(),
        segredo_download: SEGREDO.into(),
        token_upload: "  ".into(),
        limite_upload_bytes: 1024,
    });
    assert!(r.is_err());
}
