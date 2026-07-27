import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/auth_errors.dart';
import '../../domain/parameters/logout_parameters.dart';

/// Fronteira do logout. Todos os casos são informativos — o serviço limpa a
/// sessão local de qualquer forma (falha aberta).
final class LogoutRepository
    extends RepositoryBase<Unit, LogoutParameters, LogoutError> {
  const LogoutRepository({required super.datasource});

  @override
  LogoutError mapError(
    Object exception,
    StackTrace stackTrace,
    LogoutParameters parameters,
  ) {
    final kind = classificarFalhaGrpc(exception);
    developer.log(
      'logout falhou: $kind',
      name: 'login_module.logout',
      error: exception,
      stackTrace: stackTrace,
    );
    return switch (kind) {
      GrpcFailureKind.unauthenticated ||
      GrpcFailureKind.permissionDenied ||
      GrpcFailureKind.notFound ||
      GrpcFailureKind.invalidArgument ||
      GrpcFailureKind.failedPrecondition => const LogoutRejeitado(),
      GrpcFailureKind.unavailable ||
      GrpcFailureKind.rateLimited => const LogoutIndisponivel(),
      GrpcFailureKind.alreadyExists ||
      GrpcFailureKind.unknown => const LogoutInesperado(),
    };
  }
}
