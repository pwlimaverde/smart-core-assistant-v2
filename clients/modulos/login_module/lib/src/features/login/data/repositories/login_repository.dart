import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/auth_errors.dart';
import '../../domain/model/session.dart';
import '../../domain/parameters/login_parameters.dart';

/// Fronteira do login: traduz a falha técnica no erro fechado da operação.
///
/// O log registra a **natureza** da falha, nunca os `parameters` (que carregam a
/// senha) nem a mensagem do servidor sem filtro.
final class LoginRepository
    extends RepositoryBase<Session, LoginParameters, LoginError> {
  const LoginRepository({required super.datasource});

  @override
  LoginError mapError(
    Object exception,
    StackTrace stackTrace,
    LoginParameters parameters,
  ) {
    final kind = classificarFalhaGrpc(exception);
    developer.log(
      'login falhou: $kind',
      name: 'login_module.login',
      error: exception,
      stackTrace: stackTrace,
    );
    return switch (kind) {
      GrpcFailureKind.unauthenticated ||
      GrpcFailureKind.notFound ||
      GrpcFailureKind.permissionDenied => const CredenciaisInvalidas(),
      GrpcFailureKind.invalidArgument ||
      GrpcFailureKind.failedPrecondition => const LoginDadosInvalidos(),
      GrpcFailureKind.rateLimited => const LoginBloqueadoPorTentativas(),
      GrpcFailureKind.unavailable => const LoginIndisponivel(),
      GrpcFailureKind.alreadyExists ||
      GrpcFailureKind.unknown => const LoginInesperado(),
    };
  }
}
