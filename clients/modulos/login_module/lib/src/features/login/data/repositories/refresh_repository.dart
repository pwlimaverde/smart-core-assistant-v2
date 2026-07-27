import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/auth_errors.dart';
import '../../domain/model/session.dart';
import '../../domain/parameters/refresh_parameters.dart';

/// Fronteira do refresh.
///
/// A distinção que importa aqui: [RefreshRejeitado] (o servidor recusou o token)
/// derruba a sessão local; [RefreshIndisponivel] (não deu para falar com o
/// servidor) **não** — o access token em memória pode ainda estar válido, e
/// deslogar por instabilidade de rede seria hostil.
final class RefreshRepository
    extends RepositoryBase<Session, RefreshParameters, RefreshError> {
  const RefreshRepository({required super.datasource});

  @override
  RefreshError mapError(
    Object exception,
    StackTrace stackTrace,
    RefreshParameters parameters,
  ) {
    final kind = classificarFalhaGrpc(exception);
    developer.log(
      'refresh falhou: $kind',
      name: 'login_module.refresh',
      error: exception,
      stackTrace: stackTrace,
    );
    return switch (kind) {
      GrpcFailureKind.unauthenticated ||
      GrpcFailureKind.permissionDenied ||
      GrpcFailureKind.notFound ||
      GrpcFailureKind.invalidArgument ||
      GrpcFailureKind.failedPrecondition => const RefreshRejeitado(),
      GrpcFailureKind.unavailable ||
      GrpcFailureKind.rateLimited => const RefreshIndisponivel(),
      GrpcFailureKind.alreadyExists ||
      GrpcFailureKind.unknown => const RefreshInesperado(),
    };
  }
}
