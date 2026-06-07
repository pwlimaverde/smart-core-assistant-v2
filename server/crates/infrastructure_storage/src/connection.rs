//! Construção do cliente S3-compatible e verificação do bucket.
//!
//! O backend é o **Cloudflare R2** (S3-compatible), configurado por variáveis de
//! ambiente (`S3_*`) em dev e em produção. O `aws-sdk-s3` fala o protocolo S3 com
//! `endpoint_url` + `force_path_style`, sem `aws-config`.

use aws_sdk_s3::config::{BehaviorVersion, Credentials, Region};
use aws_sdk_s3::{Client, Config};

use crate::errors::StorageError;

/// Configuração de conexão lida do ambiente.
#[derive(Debug, Clone)]
pub struct S3Config {
    pub endpoint: String,
    pub region: String,
    pub access_key_id: String,
    pub secret_access_key: String,
    pub bucket: String,
    pub force_path_style: bool,
}

/// Lê uma variável de ambiente obrigatória, devolvendo erro de configuração claro.
fn env_obrigatoria(chave: &str) -> Result<String, StorageError> {
    std::env::var(chave)
        .map_err(|_| StorageError::ConfigError(format!("variável {chave} não configurada")))
}

impl S3Config {
    /// Carrega a configuração a partir das variáveis `S3_*`.
    ///
    /// `S3_REGION` assume `auto` (recomendado pelo R2) e `S3_FORCE_PATH_STYLE`
    /// assume `true` (exigido pelo MinIO e compatível com o R2) quando ausentes.
    pub fn from_env() -> Result<Self, StorageError> {
        Ok(Self {
            endpoint: env_obrigatoria("S3_ENDPOINT")?,
            region: std::env::var("S3_REGION").unwrap_or_else(|_| "auto".to_string()),
            access_key_id: env_obrigatoria("S3_ACCESS_KEY_ID")?,
            secret_access_key: env_obrigatoria("S3_SECRET_ACCESS_KEY")?,
            bucket: env_obrigatoria("S3_BUCKET")?,
            force_path_style: std::env::var("S3_FORCE_PATH_STYLE")
                .map(|v| v.eq_ignore_ascii_case("true"))
                .unwrap_or(true),
        })
    }
}

/// Monta o cliente S3 com credenciais explícitas (sem `aws-config`), endpoint
/// customizado e `force_path_style` — compatível com MinIO e Cloudflare R2.
pub fn criar_cliente_com_config(cfg: &S3Config) -> Client {
    let creds = Credentials::new(
        cfg.access_key_id.clone(),
        cfg.secret_access_key.clone(),
        None,
        None,
        "static",
    );
    let conf = Config::builder()
        .behavior_version(BehaviorVersion::latest())
        .region(Region::new(cfg.region.clone()))
        .endpoint_url(cfg.endpoint.clone())
        .credentials_provider(creds)
        .force_path_style(cfg.force_path_style)
        .build();
    Client::from_conf(conf)
}

/// Lê o ambiente e cria o cliente, devolvendo também o bucket configurado.
pub fn criar_cliente() -> Result<(Client, String), StorageError> {
    let cfg = S3Config::from_env()?;
    let client = criar_cliente_com_config(&cfg);
    tracing::info!(endpoint = %cfg.endpoint, bucket = %cfg.bucket, "cliente S3 criado");
    Ok((client, cfg.bucket))
}

/// Verifica a existência/acesso ao bucket (`head_bucket`).
///
/// O bucket do Cloudflare R2 é provisionado no painel da Cloudflare (o token de
/// acesso normalmente não tem permissão de criação de bucket). Portanto apenas
/// confirmamos o acesso; se o bucket não existir ou estiver inacessível, devolve
/// erro de configuração explícito (não tenta criar).
pub async fn garantir_bucket(client: &Client, bucket: &str) -> Result<(), StorageError> {
    client
        .head_bucket()
        .bucket(bucket)
        .send()
        .await
        .map(|_| {
            tracing::debug!(bucket = %bucket, "bucket acessível");
        })
        .map_err(|e| {
            StorageError::ConfigError(format!(
                "bucket '{bucket}' inexistente ou inacessível (provisione-o no painel do R2): {e}"
            ))
        })
}

/// Healthcheck simples: confirma o acesso ao bucket via `head_bucket`.
pub async fn health(client: &Client, bucket: &str) -> Result<(), StorageError> {
    client
        .head_bucket()
        .bucket(bucket)
        .send()
        .await
        .map(|_| ())
        .map_err(|e| StorageError::S3(format!("healthcheck do bucket '{bucket}' falhou: {e}")))
}
