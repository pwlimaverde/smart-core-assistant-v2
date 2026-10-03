//! Módulo de releases: geração de tickets HMAC-SHA256 para download de aplicativos.
//!
//! Responsabilidades:
//! - Ler manifesto de releases (releases.*.json montado read-only)
//! - Validar versão e canal
//! - Gerar ticket HMAC-SHA256
//! - Publicar evento `release_download_link_issued` em security:stream

use chrono::Utc;
use contracts::{Envelope, MessageKind};
use error_core::AppError;
use hmac::{Hmac, Mac};
use observability::AuditLogPayload;
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use std::path::PathBuf;
use std::time::Duration;
use uuid::Uuid;

type HmacSha256 = Hmac<Sha256>;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReleaseInfo {
    pub version: String,
    pub url: String,
    pub sha256: String,
    pub file_name: String,
    pub size_bytes: i64,
    pub release_notes_md: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReleasesManifest {
    pub releases: Vec<ReleaseInfo>,
}

#[derive(Debug, Clone, Serialize)]
pub struct DownloadTicket {
    pub ticket: String,
    pub url: String,
    pub version: String,
    pub file_name: String,
    pub size_bytes: i64,
    pub sha256: String,
    pub release_notes_md: Option<String>,
    pub expires_at_ms: i64,
}

/// Gera ticket HMAC-SHA256 para download de release.
///
/// Claims format: {v, kid, jti (uuid7), sub (user_id), ver, file, ch, iat, exp=iat+300}
pub async fn issue_release_download_ticket(
    channel: &str,
    version: &str,
    user_id: i64,
    secret: &str,
    base_url: &str,
    manifests_dir: &PathBuf,
) -> Result<DownloadTicket, AppError> {
    // 1. Ler manifesto (releases.{channel}.json)
    let manifest_path = manifests_dir.join(format!("releases.{}.json", channel));

    let manifest_content = tokio::fs::read_to_string(&manifest_path)
        .await
        .map_err(|e| {
            AppError::Validation(format!(
                "Não foi possível ler manifesto de releases: {}",
                e
            ))
        })?;

    let manifest: ReleasesManifest = serde_json::from_str(&manifest_content).map_err(|e| {
        AppError::Validation(format!(
            "Manifesto de releases inválido: {}",
            e
        ))
    })?;

    // 2. Buscar versão
    let release = manifest
        .releases
        .iter()
        .find(|r| r.version == version)
        .ok_or_else(|| {
            AppError::NotFound(format!(
                "Versão {} não encontrada no canal {}",
                version, channel
            ))
        })?;

    // 3. Gerar ticket HMAC-SHA256
    let jti = Uuid::new_v7().to_string();
    let iat = Utc::now().timestamp();
    let exp = iat + 300; // 5 minutos

    let claims_json = format!(
        r#"{{"v":"1","kid":"cp-rel-001","jti":"{}","sub":{},"ver":"{}","file":"{}","ch":"{}","iat":{},"exp":{}}}"#,
        jti, user_id, version, release.file_name, channel, iat, exp
    );

    let mut mac = HmacSha256::new_from_slice(secret.as_bytes())
        .map_err(|_| AppError::Internal("HMAC key inválida".to_string()))?;
    mac.update(claims_json.as_bytes());

    let signature = hex::encode(mac.finalize().into_bytes());
    let claims_hash = sha256_hex(claims_json.as_bytes());
    let ticket = format!("{}.{}", claims_hash, signature);

    let download_url = format!(
        "{}/download/{}/{}?t={}",
        base_url, version, release.file_name, ticket
    );

    let expires_at_ms = (exp as i64) * 1000;

    Ok(DownloadTicket {
        ticket,
        url: download_url,
        version: release.version.clone(),
        file_name: release.file_name.clone(),
        size_bytes: release.size_bytes,
        sha256: release.sha256.clone(),
        release_notes_md: release.release_notes_md.clone(),
        expires_at_ms,
    })
}

/// Publica evento de auditoria de release download link emitido.
pub async fn publicar_evento_link_emitido(
    redis_conn: &mut redis::aio::ConnectionManager,
    tenant_id: Option<Uuid>,
    user_id: i64,
    channel: &str,
    version: &str,
    traceparent: &str,
) -> Result<(), AppError> {
    let audit_payload = AuditLogPayload {
        tenant_id,
        level: "INFO".to_string(),
        service: "control_plane".to_string(),
        trace_id: Some(traceparent.to_string()),
        event: "releases.download_link_issued".to_string(),
        message: format!(
            "Link de download de release emitido: {} v{} para usuário {}",
            channel, version, user_id
        ),
        context: serde_json::json!({
            "channel": channel,
            "version": version,
            "user_id": user_id
        }),
        user_id: Some(user_id),
        ip_address: None,
        user_agent: None,
    };

    let audit_event = contracts::TenantEnvelope::novo(
        tenant_id.unwrap_or_else(Uuid::nil),
        "security.audit",
        audit_payload,
    )
    .com_traceparent(traceparent.to_string());

    transport::bus::publicar_evento_seguranca(redis_conn, &audit_event)
        .await
        .map_err(|e| AppError::Internal(format!("Falha ao publicar auditoria: {}", e)))
}

// ============================================================================
// Utilities
// ============================================================================

fn sha256_hex(data: &[u8]) -> String {
    let mut hasher = sha2::Sha256::new();
    sha2::Digest::update(&mut hasher, data);
    hex::encode(hasher.finalize())
}
