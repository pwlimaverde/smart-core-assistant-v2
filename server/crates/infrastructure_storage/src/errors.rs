use error_core::{AppError, ErrorCode};
use thiserror::Error;

/// Único enum de erro exposto pela crate de armazenamento.
///
/// É o erro **específico** desta camada (ponte S3-compatible: MinIO em dev,
/// Cloudflare R2 em produção), mas todo `StorageError` deriva do núcleo
/// (`error_core`): expõe um [`ErrorCode`] estável via [`StorageError::code`] e
/// converte para [`AppError`] via `From`, padronizando os dados de erro em todo
/// o workspace.
#[derive(Debug, Error)]
pub enum StorageError {
    /// Objeto inexistente no bucket (ex.: `GetObject` com chave ausente).
    #[error("objeto não encontrado no storage")]
    NotFound,

    /// Falha ao enviar (upload) um objeto para o bucket.
    #[error("falha no upload do objeto: {0}")]
    Upload(String),

    /// Falha genérica do cliente S3 (download, delete, presign, head).
    #[error("erro do storage S3: {0}")]
    S3(String),

    /// Variável de ambiente ausente ou configuração inválida do cliente.
    #[error("erro de configuração do storage: {0}")]
    ConfigError(String),
}

impl StorageError {
    /// Código estável do núcleo (`error_core`) que identifica este erro de forma
    /// rastreável em logs, métricas e alertas. Mantém-se coerente com a conversão
    /// para [`AppError`].
    pub fn code(&self) -> ErrorCode {
        match self {
            Self::NotFound => ErrorCode::StorageNotFound,
            Self::Upload(_) => ErrorCode::StorageUploadFailed,
            // Demais falhas de IO de storage caem na variante genérica de delete/leitura.
            Self::S3(_) => ErrorCode::StorageDeleteFailed,
            Self::ConfigError(_) => ErrorCode::InternalError,
        }
    }
}

/// Ponte para o agregador do núcleo. A mensagem é construída de modo que
/// `AppError::code()` reclassifique para o **mesmo** [`ErrorCode`] de
/// [`StorageError::code`], garantindo coerência ponta a ponta.
impl From<StorageError> for AppError {
    fn from(err: StorageError) -> Self {
        match err {
            // "não encontrado" casa com a reclassificação de AppError → StorageNotFound.
            StorageError::NotFound => AppError::Storage("objeto não encontrado".into()),
            // "upload" casa com a reclassificação de AppError → StorageUploadFailed.
            StorageError::Upload(msg) => AppError::Storage(format!("falha no upload: {msg}")),
            // Genérico → StorageDeleteFailed.
            StorageError::S3(msg) => AppError::Storage(msg),
            // Configuração é falha interna do serviço.
            StorageError::ConfigError(msg) => AppError::Internal(msg),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formata_mensagens_das_variantes() {
        assert_eq!(
            StorageError::NotFound.to_string(),
            "objeto não encontrado no storage"
        );
        assert_eq!(
            StorageError::Upload("timeout".into()).to_string(),
            "falha no upload do objeto: timeout"
        );
        assert_eq!(
            StorageError::S3("conexão recusada".into()).to_string(),
            "erro do storage S3: conexão recusada"
        );
        assert_eq!(
            StorageError::ConfigError("S3_BUCKET ausente".into()).to_string(),
            "erro de configuração do storage: S3_BUCKET ausente"
        );
    }

    #[test]
    fn mapeia_cada_erro_para_o_code_do_nucleo() {
        assert_eq!(StorageError::NotFound.code(), ErrorCode::StorageNotFound);
        assert_eq!(
            StorageError::Upload("x".into()).code(),
            ErrorCode::StorageUploadFailed
        );
        assert_eq!(
            StorageError::S3("x".into()).code(),
            ErrorCode::StorageDeleteFailed
        );
        assert_eq!(
            StorageError::ConfigError("x".into()).code(),
            ErrorCode::InternalError
        );
    }

    #[test]
    fn converte_para_app_error_preservando_o_code() {
        // Garante a coerência ponta a ponta na conversão de StorageError para AppError.
        let casos = [
            StorageError::NotFound,
            StorageError::Upload("dup".into()),
            StorageError::S3("io".into()),
        ];
        for caso in casos {
            let code_origem = caso.code();
            let app: AppError = caso.into();
            assert_eq!(
                app.code(),
                code_origem,
                "AppError::code() divergiu de StorageError::code() para {code_origem}"
            );
        }
    }
}
