import 'package:api_client/api_client.dart';
import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Traduz um [GrpcError] da borda gRPC-Web num [AppError] tipado de domínio.
///
/// `permissionDenied` cobre tanto a ausência de escopo quanto o RBAC fino por
/// fluxo (`flow_permissions`, WS-5a) — o filtro é 100% server-side; a UI só
/// precisa exibir "acesso negado", nunca reimplementar a checagem.
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
