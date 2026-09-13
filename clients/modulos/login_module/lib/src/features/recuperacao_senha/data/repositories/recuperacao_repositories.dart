import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/recuperacao_errors.dart';
import '../../domain/parameters/recuperacao_parameters.dart';

/// O log registra a natureza da falha, nunca os `parameters`: um carrega o
/// e-mail de alguém, o outro o token e a senha nova.
void _log(String operacao, Object exception, StackTrace stackTrace) =>
    developer.log(
      '$operacao falhou: ${classificarFalhaGrpc(exception)}',
      name: 'login_module.recuperacao_senha',
      error: exception,
      stackTrace: stackTrace,
    );

final class SolicitarRedefinicaoRepository
    extends
        RepositoryBase<
          Unit,
          SolicitarRedefinicaoParameters,
          SolicitarRedefinicaoError
        > {
  const SolicitarRedefinicaoRepository({required super.datasource});

  @override
  SolicitarRedefinicaoError mapError(
    Object exception,
    StackTrace stackTrace,
    SolicitarRedefinicaoParameters parameters,
  ) {
    _log('solicitarRedefinicao', exception, stackTrace);
    return switch (classificarFalhaGrpc(exception)) {
      GrpcFailureKind.rateLimited => const RedefinicaoMuitosPedidos(),
      GrpcFailureKind.unavailable => const SolicitarRedefinicaoIndisponivel(),
      _ => const SolicitarRedefinicaoInesperado(),
    };
  }
}

final class RedefinirSenhaRepository
    extends
        RepositoryBase<Unit, RedefinirSenhaParameters, RedefinirSenhaError> {
  const RedefinirSenhaRepository({required super.datasource});

  @override
  RedefinirSenhaError mapError(
    Object exception,
    StackTrace stackTrace,
    RedefinirSenhaParameters parameters,
  ) {
    _log('redefinirSenha', exception, stackTrace);
    return switch (classificarFalhaGrpc(exception)) {
      // O servidor diz `failedPrecondition` para o link que não vale e
      // `invalidArgument` para a senha fraca — é o que permite à tela dizer
      // "peça outro link" num caso e "escolha outra senha" no outro.
      GrpcFailureKind.failedPrecondition ||
      GrpcFailureKind.notFound ||
      GrpcFailureKind.unauthenticated ||
      GrpcFailureKind.permissionDenied => const LinkDeRedefinicaoInvalido(),
      GrpcFailureKind.invalidArgument => const SenhaRecusada(),
      GrpcFailureKind.rateLimited => const RedefinirSenhaMuitasTentativas(),
      GrpcFailureKind.unavailable => const RedefinirSenhaIndisponivel(),
      GrpcFailureKind.alreadyExists ||
      GrpcFailureKind.unknown => const RedefinirSenhaInesperado(),
    };
  }
}
