//! Construção do cliente S3-compatible e verificação do bucket.
//!
//! O backend é o **Cloudflare R2** (S3-compatible), configurado por variáveis de
//! ambiente (`S3_*`) em dev e em produção. O `aws-sdk-s3` fala o protocolo S3 com
//! `endpoint_url` + `force_path_style`, sem `aws-config`.

use aws_sdk_s3::config::{BehaviorVersion, Credentials, Region};
use aws_sdk_s3::types::{
    BucketLifecycleConfiguration, CorsConfiguration, CorsRule, ExpirationStatus,
    LifecycleExpiration, LifecycleRule, LifecycleRuleFilter,
};
use aws_sdk_s3::{Client, Config};
use secrecy::{ExposeSecret, SecretString};

use crate::errors::StorageError;

/// Configuração de conexão lida do ambiente.
///
/// N4.4: `secret_access_key` em `SecretString` — impede vazamento acidental via
/// `Debug`/log (o `#[derive(Debug)]` do `secrecy` redige o valor automaticamente).
#[derive(Debug, Clone)]
pub struct S3Config {
    pub endpoint: String,
    pub region: String,
    pub access_key_id: String,
    pub secret_access_key: SecretString,
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
            secret_access_key: SecretString::from(env_obrigatoria("S3_SECRET_ACCESS_KEY")?),
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
        cfg.secret_access_key.expose_secret().to_string(),
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

/// Aplica a regra de lifecycle do bucket (N4.3 — defesa em profundidade da
/// retenção de mídia). A purga primária continua aplicativa (scheduler →
/// `media.purge` → `StorageClient::delete`, que respeita a política por plano e
/// preserva o resumo/análise no Postgres); esta regra é uma rede de segurança
/// adicional no próprio bucket, com margem conservadora (deve ser bem maior que a
/// retenção por plano — ver `S3_LIFECYCLE_EXPIRATION_DAYS`).
///
/// Best-effort: falha aqui não impede o boot do serviço (loga e segue). Providers
/// S3 sem suporte a lifecycle (ex.: MinIO em dev, dependendo da versão) não devem
/// travar o boot de `data_storage`.
pub async fn garantir_lifecycle(client: &Client, bucket: &str, expiration_days: i32) {
    if expiration_days <= 0 {
        tracing::info!("lifecycle do bucket desabilitado (S3_LIFECYCLE_EXPIRATION_DAYS <= 0)");
        return;
    }

    let regra = match LifecycleRule::builder()
        .id("smartcore-expira-midia")
        .status(ExpirationStatus::Enabled)
        .filter(LifecycleRuleFilter::builder().prefix("").build())
        .expiration(LifecycleExpiration::builder().days(expiration_days).build())
        .build()
    {
        Ok(r) => r,
        Err(e) => {
            tracing::warn!("falha ao montar regra de lifecycle do bucket: {e}");
            return;
        }
    };

    let config = match BucketLifecycleConfiguration::builder().rules(regra).build() {
        Ok(c) => c,
        Err(e) => {
            tracing::warn!("falha ao montar lifecycle configuration do bucket: {e}");
            return;
        }
    };

    match client
        .put_bucket_lifecycle_configuration()
        .bucket(bucket)
        .lifecycle_configuration(config)
        .send()
        .await
    {
        Ok(_) => tracing::info!(
            bucket = %bucket,
            expiration_days,
            "lifecycle do bucket aplicado (defesa em profundidade da retenção de mídia)"
        ),
        Err(e) => tracing::warn!(
            bucket = %bucket,
            "falha ao aplicar lifecycle do bucket (best-effort, prosseguindo): {e}"
        ),
    }
}

/// Aplica a política de CORS do bucket (N5.3 — paridade Web). A mídia é entregue
/// ao Flutter Web por **URL pré-assinada** (presigned GET) direto do R2, ou seja,
/// numa origem (`*.r2.cloudflarestorage.com`) diferente da do app. O browser aplica
/// CORS a esses `fetch`/`<img>`/`<video src>` cross-origin mesmo com presign — o
/// presign autentica a requisição, mas não isenta a política de CORS. Sem esta
/// regra, a mídia falha silenciosamente no cliente Web.
///
/// **Pegadinha de range request:** players de mídia HTML5 fazem *range requests*
/// (seek em áudio/vídeo) e leem `Content-Range`/`Accept-Ranges`/`Content-Length`
/// da resposta. Se esses headers não estiverem em `expose_headers`, o browser os
/// oculta do JS/player e o seek quebra silenciosamente — mesmo com o CORS
/// "funcionando" para o GET simples. Por isso eles são expostos explicitamente.
///
/// Best-effort: falha aqui não impede o boot do serviço (loga e segue). Providers
/// S3 sem suporte a `put_bucket_cors` não devem travar o boot de `data_storage`.
/// A origem da verdade da política versionada é `infra/r2-cors.json`; as origens
/// chegam aqui via `S3_CORS_ALLOWED_ORIGINS` (comma-separated) no boot.
pub async fn garantir_cors(client: &Client, bucket: &str, allowed_origins: &[String]) {
    if allowed_origins.is_empty() {
        tracing::info!("CORS do bucket desabilitado (S3_CORS_ALLOWED_ORIGINS vazio)");
        return;
    }

    let regra = match CorsRule::builder()
        .set_allowed_origins(Some(allowed_origins.to_vec()))
        .allowed_methods("GET")
        .allowed_methods("HEAD")
        .allowed_headers("*")
        .expose_headers("Content-Range")
        .expose_headers("Accept-Ranges")
        .expose_headers("Content-Length")
        .expose_headers("ETag")
        .max_age_seconds(3600)
        .build()
    {
        Ok(r) => r,
        Err(e) => {
            tracing::warn!("falha ao montar regra de CORS do bucket: {e}");
            return;
        }
    };

    let config = match CorsConfiguration::builder().cors_rules(regra).build() {
        Ok(c) => c,
        Err(e) => {
            tracing::warn!("falha ao montar CORS configuration do bucket: {e}");
            return;
        }
    };

    match client
        .put_bucket_cors()
        .bucket(bucket)
        .cors_configuration(config)
        .send()
        .await
    {
        Ok(_) => tracing::info!(
            bucket = %bucket,
            origins = ?allowed_origins,
            "CORS do bucket aplicado (paridade Web — mídia entregue por presign)"
        ),
        Err(e) => tracing::warn!(
            bucket = %bucket,
            "falha ao aplicar CORS do bucket (best-effort, prosseguindo): {e}"
        ),
    }
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
