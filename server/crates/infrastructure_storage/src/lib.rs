//! Crate de infraestrutura de armazenamento de mídia do Smart Core Assistant v2.
//!
//! Biblioteca interna **exclusiva** do app `apps/data_storage`: é a única que fala
//! o protocolo S3 (via `aws-sdk-s3`). O backend é o **Cloudflare R2**
//! (S3-compatible), configurado por variáveis `S3_*` em dev e em produção.
//!
//! A mídia é transitória no servidor: o binário vive no bucket por uma janela
//! curta; o que é permanente é o ponteiro + resumo/analise no Postgres. Esta crate
//! provê o `put/get/presign/delete` que sustenta esse modelo.

pub mod connection;
pub mod errors;
pub mod keys;

use aws_sdk_s3::presigning::PresigningConfig;
use aws_sdk_s3::primitives::ByteStream;
use aws_sdk_s3::Client;
use std::time::Duration;
use uuid::Uuid;

pub use errors::StorageError;
pub use keys::{chave_midia, MediaType};

/// Cliente de armazenamento de objetos S3-compatible (MinIO/R2).
#[derive(Clone)]
pub struct StorageClient {
    client: Client,
    bucket: String,
}

impl StorageClient {
    /// Cria o cliente a partir de um `Client` e bucket já resolvidos.
    pub fn new(client: Client, bucket: String) -> Self {
        Self { client, bucket }
    }

    /// Cria o cliente lendo a configuração do ambiente (`S3_*`).
    pub fn from_env() -> Result<Self, StorageError> {
        let (client, bucket) = connection::criar_cliente()?;
        Ok(Self { client, bucket })
    }

    /// Nome do bucket configurado.
    pub fn bucket(&self) -> &str {
        &self.bucket
    }

    /// Garante a existência do bucket (cria no MinIO; verifica no R2).
    pub async fn garantir_bucket(&self) -> Result<(), StorageError> {
        connection::garantir_bucket(&self.client, &self.bucket).await
    }

    /// Aplica a regra de lifecycle do bucket (N4.3 — defesa em profundidade da
    /// retenção). Best-effort: nunca falha o boot do serviço.
    pub async fn garantir_lifecycle(&self, expiration_days: i32) {
        connection::garantir_lifecycle(&self.client, &self.bucket, expiration_days).await
    }

    /// Aplica a política de CORS do bucket (N5.3 — paridade Web; mídia entregue
    /// por presign para origem cross-site). Best-effort: nunca falha o boot.
    pub async fn garantir_cors(&self, allowed_origins: &[String]) {
        connection::garantir_cors(&self.client, &self.bucket, allowed_origins).await
    }

    /// Confirma o acesso ao bucket (healthcheck).
    pub async fn health(&self) -> Result<(), StorageError> {
        connection::health(&self.client, &self.bucket).await
    }

    /// Monta a chave plana de um arquivo de um inquilino: `{tenant_id}/{file_name}`.
    fn chave(tenant_id: Uuid, file_name: &str) -> String {
        format!("{tenant_id}/{file_name}")
    }

    /// Envia (upload) os bytes de um arquivo do inquilino para o bucket.
    #[tracing::instrument(skip(self, data), fields(tenant_id = %tenant_id, file_name = %file_name, bytes = data.len()), err)]
    pub async fn put(
        &self,
        tenant_id: Uuid,
        file_name: &str,
        data: &[u8],
    ) -> Result<String, StorageError> {
        let key = Self::chave(tenant_id, file_name);
        self.client
            .put_object()
            .bucket(&self.bucket)
            .key(&key)
            .body(ByteStream::from(data.to_vec()))
            .send()
            .await
            .map_err(|e| StorageError::Upload(e.to_string()))?;

        tracing::info!("objeto enviado ao storage");
        Ok(format!("s3://{}/{}", self.bucket, key))
    }

    /// Recupera os bytes de um arquivo do bucket.
    #[tracing::instrument(skip(self), fields(tenant_id = %tenant_id, file_name = %file_name), err)]
    pub async fn get(&self, tenant_id: Uuid, file_name: &str) -> Result<Vec<u8>, StorageError> {
        let key = Self::chave(tenant_id, file_name);
        let saida = self
            .client
            .get_object()
            .bucket(&self.bucket)
            .key(&key)
            .send()
            .await
            .map_err(|e| {
                let svc = e.into_service_error();
                if svc.is_no_such_key() {
                    StorageError::NotFound
                } else {
                    StorageError::S3(svc.to_string())
                }
            })?;

        let bytes = saida
            .body
            .collect()
            .await
            .map_err(|e| StorageError::S3(e.to_string()))?
            .into_bytes()
            .to_vec();
        Ok(bytes)
    }

    /// Gera uma URL pré-assinada (presigned GET) para download direto pelo cliente.
    #[tracing::instrument(skip(self), fields(tenant_id = %tenant_id, file_name = %file_name, ttl_segundos), err)]
    pub async fn presign(
        &self,
        tenant_id: Uuid,
        file_name: &str,
        ttl_segundos: u64,
    ) -> Result<String, StorageError> {
        let key = Self::chave(tenant_id, file_name);
        let cfg = PresigningConfig::expires_in(Duration::from_secs(ttl_segundos))
            .map_err(|e| StorageError::ConfigError(e.to_string()))?;
        let req = self
            .client
            .get_object()
            .bucket(&self.bucket)
            .key(&key)
            .presigned(cfg)
            .await
            .map_err(|e| StorageError::S3(e.to_string()))?;
        Ok(req.uri().to_string())
    }

    /// Remove fisicamente um objeto do bucket. Idempotente (o S3 não falha se ausente).
    #[tracing::instrument(skip(self), fields(tenant_id = %tenant_id, file_name = %file_name), err)]
    pub async fn delete(&self, tenant_id: Uuid, file_name: &str) -> Result<(), StorageError> {
        let key = Self::chave(tenant_id, file_name);
        self.client
            .delete_object()
            .bucket(&self.bucket)
            .key(&key)
            .send()
            .await
            .map_err(|e| StorageError::S3(e.to_string()))?;
        tracing::info!("objeto removido do storage");
        Ok(())
    }
}
