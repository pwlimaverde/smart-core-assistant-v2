import 'package:api_client/api_client.dart';
import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/model/windows_download_link.dart';
import '../../domain/errors/windows_downloads_errors.dart';

/// Datasource para requisições gRPC de download do Windows.
class GetWindowsDownloadLinkDatasource {
  final AdminServiceClient client;

  GetWindowsDownloadLinkDatasource({required this.client});

  /// Chama o RPC GetWindowsDownloadLink do admin service.
  Future<Result<WindowsDownloadLink, AppException>> call({
    required String channel,
    required String version,
  }) async {
    try {
      // Cria a requisição protobuf
      final request = GetWindowsDownloadLinkRequest()
        ..channel = channel
        ..version = version;

      // Chamada gRPC
      final response = await client.getWindowsDownloadLink(request);

      // Mapeia para o modelo de domínio
      final downloadLink = WindowsDownloadLink(
        url: response.url,
        version: response.version,
        fileName: response.fileName,
        sizeBytes: response.sizeBytes.toInt(),
        sha256: response.sha256,
        releaseNotesMd: response.releaseNotesMd,
        expiresAtMs: response.expiresAtMs,
      );

      return Success(downloadLink);
    } on GrpcError catch (e) {
      return Failure(_mapGrpcErrorToException(e));
    } catch (e, stackTrace) {
      return Failure(AppException(
        message: 'Erro ao obter link de download: $e',
        code: 'unknown_error',
        stackTrace: stackTrace,
      ));
    }
  }

  /// Mapeia erros gRPC para exceções específicas do domínio.
  AppException _mapGrpcErrorToException(GrpcError error) {
    switch (error.code) {
      case GrpcErrorCode.permissionDenied:
      case GrpcErrorCode.unauthenticated:
        return NotSuperuserError();
      case GrpcErrorCode.invalidArgument:
        return InvalidChannelError('beta');
      case GrpcErrorCode.failedPrecondition:
        return ReleasesNotConfiguredError();
      case GrpcErrorCode.notFound:
        return NoReleaseFoundError('beta');
      default:
        return AppException(
          message: 'Erro ao obter link: ${error.message}',
          code: 'grpc_error_${error.code}',
          stackTrace: StackTrace.current,
        );
    }
  }
}
