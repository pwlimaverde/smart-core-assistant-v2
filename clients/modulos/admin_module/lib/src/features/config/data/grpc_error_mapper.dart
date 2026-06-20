import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:api_client/api_client.dart';

/// Traduz um [GrpcError] da borda gRPC-Web num [AppError] tipado de domínio.
AppError mapGrpcError(GrpcError e, AppError fallback) {
  switch (e.code) {
    case StatusCode.unauthenticated:
      return const ErrorUnauthorized();
    case StatusCode.permissionDenied:
      return const ErrorUnauthorized(message: 'Acesso negado.');
    case StatusCode.invalidArgument:
      return const ErrorValidation();
    case StatusCode.resourceExhausted:
      return const ErrorAuth(
        message: 'Muitas tentativas. Aguarde antes de tentar novamente.',
      );
    case StatusCode.unavailable:
    case StatusCode.deadlineExceeded:
      return const ErrorNetwork();
    default:
      return fallback;
  }
}
