//! Crate de infraestrutura de armazenamento de mídia do Smart Core Assistant v2.
//! Encapsula o acesso a arquivos do inquilino sujeitos a políticas de segurança.

use std::path::PathBuf;
use uuid::Uuid;

/// Cliente para gerenciar o armazenamento físico/local de mídias de tenants.
#[derive(Clone)]
pub struct StorageClient {
    base_path: PathBuf,
}

impl StorageClient {
    /// Inicializa o StorageClient com o diretório base.
    pub fn new(base_path: PathBuf) -> Self {
        Self { base_path }
    }

    /// Salva dados de um arquivo no storage do inquilino.
    pub async fn put(&self, tenant_id: Uuid, file_name: &str, data: &[u8]) -> anyhow::Result<String> {
        let tenant_dir = self.base_path.join(tenant_id.to_string());
        std::fs::create_dir_all(&tenant_dir)?;
        let file_path = tenant_dir.join(file_name);
        std::fs::write(&file_path, data)?;
        
        tracing::info!(
            file_name = %file_name,
            tenant_id = %tenant_id,
            "Arquivo salvo com sucesso no storage do inquilino."
        );
        
        Ok(format!("storage://{}/{}", tenant_id, file_name))
    }

    /// Recupera os bytes de um arquivo do storage.
    pub async fn get(&self, tenant_id: Uuid, file_name: &str) -> anyhow::Result<Vec<u8>> {
        let file_path = self.base_path.join(tenant_id.to_string()).join(file_name);
        if !file_path.exists() {
            anyhow::bail!("Arquivo não encontrado no storage: {}", file_name);
        }
        let data = std::fs::read(&file_path)?;
        Ok(data)
    }

    /// Gera uma URL temporária assinada (presigned URL) para acesso externo ao arquivo.
    pub async fn presign(&self, tenant_id: Uuid, file_name: &str, _ttl_segundos: u64) -> anyhow::Result<String> {
        // Retorna URL de acesso mockada (simulando MinIO/S3)
        Ok(format!("http://localhost:9000/media-bucket/{}/{}?token=mock_signed_token", tenant_id, file_name))
    }

    /// Remove fisicamente um arquivo do storage.
    pub async fn delete(&self, tenant_id: Uuid, file_name: &str) -> anyhow::Result<()> {
        let file_path = self.base_path.join(tenant_id.to_string()).join(file_name);
        if file_path.exists() {
            std::fs::remove_file(&file_path)?;
            tracing::info!(file_name = %file_name, tenant_id = %tenant_id, "Arquivo de mídia deletado fisicamente.");
        }
        Ok(())
    }
}

