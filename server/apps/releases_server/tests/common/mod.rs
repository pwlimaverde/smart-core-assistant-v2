//! Fixtures e utilitários para testes de integração do releases server.

use chrono::Utc;
use hmac::{Hmac, Mac};
use sha2::{Digest, Sha256};
use std::path::PathBuf;
use tempfile::TempDir;
use uuid::Uuid;

type HmacSha256 = Hmac<Sha256>;

/// Secret compartilhado para testes HMAC.
pub const TEST_DOWNLOAD_SECRET: &str = "test-secret-key-for-hmac-validation";
pub const TEST_UPLOAD_TOKEN: &str = "test-bearer-token-for-uploads";

/// Cria um diretório temporário com estrutura de releases para teste.
///
/// Retorna (TempDir, caminho absoluto) para que o caller possa usar a path
/// e manter o TempDir vivo até o fim do teste.
pub fn setup_releases_dir() -> anyhow::Result<(TempDir, PathBuf)> {
    let temp_dir = TempDir::new()?;
    let releases_dir = temp_dir.path().to_path_buf();

    // Criar subdiretórios para versões
    std::fs::create_dir_all(releases_dir.join("0.1.0"))?;
    std::fs::create_dir_all(releases_dir.join("0.2.0"))?;

    // Criar arquivo Setup.exe de teste (arquivo dummy)
    let setup_content = b"MZ\x90\x00"; // Minimal PE header signature
    std::fs::write(
        releases_dir.join("0.1.0/SmartCoreTenant-win-Setup.exe"),
        setup_content,
    )?;
    std::fs::write(
        releases_dir.join("0.2.0/SmartCoreTenant-win-Setup.exe"),
        setup_content,
    )?;

    // Criar arquivo .nupkg (dummy)
    std::fs::write(
        releases_dir.join("0.1.0/SmartCoreTenant.1.0.0.nupkg"),
        b"PK",
    )?;

    // Criar manifesto releases.beta.json
    let beta_manifest = serde_json::json!({
        "releases": [
            {
                "version": "0.1.0",
                "url": "https://example.com/releases/0.1.0/SmartCoreTenant-win-Setup.exe",
                "sha256": "abc123",
                "file_name": "SmartCoreTenant-win-Setup.exe",
                "size_bytes": 50000000,
                "release_notes_md": "Beta release"
            },
            {
                "version": "0.2.0",
                "url": "https://example.com/releases/0.2.0/SmartCoreTenant-win-Setup.exe",
                "sha256": "def456",
                "file_name": "SmartCoreTenant-win-Setup.exe",
                "size_bytes": 51000000,
                "release_notes_md": "Beta hotfix"
            }
        ]
    });

    std::fs::write(
        releases_dir.join("releases.beta.json"),
        serde_json::to_string_pretty(&beta_manifest)?,
    )?;

    // Criar manifesto releases.stable.json
    let stable_manifest = serde_json::json!({
        "releases": [
            {
                "version": "0.1.0",
                "url": "https://example.com/releases/0.1.0/SmartCoreTenant-win-Setup.exe",
                "sha256": "abc123",
                "file_name": "SmartCoreTenant-win-Setup.exe",
                "size_bytes": 50000000,
                "release_notes_md": "Stable release"
            }
        ]
    });

    std::fs::write(
        releases_dir.join("releases.stable.json"),
        serde_json::to_string_pretty(&stable_manifest)?,
    )?;

    Ok((temp_dir, releases_dir))
}

/// Gera um ticket HMAC válido para download.
///
/// O ticket tem formato: `claims_hash.signature`
/// - `claims_hash`: SHA256 hexadecimal do JSON das claims
/// - `signature`: HMAC-SHA256 hexadecimal do mesmo JSON, usando TEST_DOWNLOAD_SECRET
pub fn generate_valid_ticket(version: &str, filename: &str) -> String {
    let jti = Uuid::new_v7().to_string();
    let iat = Utc::now().timestamp();
    let exp = iat + 300; // 5 minutos no futuro

    let claims_json = format!(
        r#"{{"v":"1","kid":"rs-dl-001","jti":"{}","ver":"{}","file":"{}","iat":{},"exp":{}}}"#,
        jti, version, filename, iat, exp
    );

    let claims_hash = sha256_hex(claims_json.as_bytes());

    let mut mac = HmacSha256::new_from_slice(TEST_DOWNLOAD_SECRET.as_bytes())
        .expect("HMAC can take key of any size");
    mac.update(claims_json.as_bytes());
    let signature = hex::encode(mac.finalize().into_bytes());

    format!("{}.{}", claims_hash, signature)
}

/// Gera um ticket HMAC expirado (exp < now).
pub fn generate_expired_ticket(version: &str, filename: &str) -> String {
    let jti = Uuid::new_v7().to_string();
    let iat = Utc::now().timestamp() - 600; // 10 minutos atrás
    let exp = iat + 300; // expirou 5 minutos atrás

    let claims_json = format!(
        r#"{{"v":"1","kid":"rs-dl-001","jti":"{}","ver":"{}","file":"{}","iat":{},"exp":{}}}"#,
        jti, version, filename, iat, exp
    );

    let claims_hash = sha256_hex(claims_json.as_bytes());

    let mut mac = HmacSha256::new_from_slice(TEST_DOWNLOAD_SECRET.as_bytes())
        .expect("HMAC can take key of any size");
    mac.update(claims_json.as_bytes());
    let signature = hex::encode(mac.finalize().into_bytes());

    format!("{}.{}", claims_hash, signature)
}

/// Gera um ticket com payload adulterado (signature inválida).
pub fn generate_tampered_ticket(version: &str, filename: &str) -> String {
    let jti = Uuid::new_v7().to_string();
    let iat = Utc::now().timestamp();
    let exp = iat + 300;

    let claims_json = format!(
        r#"{{"v":"1","kid":"rs-dl-001","jti":"{}","ver":"{}","file":"{}","iat":{},"exp":{}}}"#,
        jti, version, filename, iat, exp
    );

    let claims_hash = sha256_hex(claims_json.as_bytes());

    // Usar secret errado propositalmente
    let wrong_secret = "wrong-secret-key";
    let mut mac = HmacSha256::new_from_slice(wrong_secret.as_bytes())
        .expect("HMAC can take key of any size");
    mac.update(claims_json.as_bytes());
    let invalid_signature = hex::encode(mac.finalize().into_bytes());

    format!("{}.{}", claims_hash, invalid_signature)
}

fn sha256_hex(data: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    hex::encode(hasher.finalize())
}

/// Cria um client HTTP reqwest pré-configurado para os testes.
pub fn test_client() -> reqwest::Client {
    reqwest::Client::new()
}
