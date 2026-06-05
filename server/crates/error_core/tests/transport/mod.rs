#[cfg(feature = "grpc")]
use error_core::{AppError, to_status};
#[cfg(feature = "grpc")]
use tonic::Code;

#[cfg(feature = "grpc")]
#[test]
fn test_to_status_mapping() {
    // Valida o mapeamento de diversos tipos de AppError para gRPC tonic::Status

    // Erros de Autenticação -> Unauthenticated ou PermissionDenied
    let status = to_status(&AppError::Auth("token expirado".to_owned()));
    assert_eq!(status.code(), Code::Unauthenticated);
    assert_eq!(status.message(), "Credencial inválida ou ausente.");

    let status = to_status(&AppError::Auth("insufficient scope".to_owned()));
    assert_eq!(status.code(), Code::PermissionDenied);

    // Erros de Recursos Não Encontrados -> NotFound
    let status = to_status(&AppError::Database("record not found".to_owned()));
    assert_eq!(status.code(), Code::NotFound);
    assert_eq!(status.message(), "Recurso não encontrado.");

    let status = to_status(&AppError::Storage("file not found".to_owned()));
    assert_eq!(status.code(), Code::NotFound);

    // Erros de Validação -> InvalidArgument
    let status = to_status(&AppError::Validation("invalid name".to_owned()));
    assert_eq!(status.code(), Code::InvalidArgument);

    // Erros de Conflito / Duplicado -> AlreadyExists
    let status = to_status(&AppError::Conflict("duplicate resource".to_owned()));
    assert_eq!(status.code(), Code::AlreadyExists);

    // Erros de Banco de Dados ou Interno -> Internal
    let status = to_status(&AppError::Database("connection lost".to_owned()));
    assert_eq!(status.code(), Code::Internal);
    assert_eq!(status.message(), "Erro ao acessar o banco de dados.");

    let status = to_status(&AppError::Internal("fatal server error".to_owned()));
    assert_eq!(status.code(), Code::Internal);
    assert_eq!(status.message(), "Erro interno do servidor.");
}
