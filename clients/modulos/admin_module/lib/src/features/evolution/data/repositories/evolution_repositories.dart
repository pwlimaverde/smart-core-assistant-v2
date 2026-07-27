import 'dart:developer' as developer;

import 'package:api_client/api_client.dart'
    show GrpcFailureKind, classificarFalhaGrpc;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/evolution_errors.dart';
import '../../domain/model/evolution_connection_result.dart';
import '../../domain/parameters/evolution_parameters.dart';

/// Fronteiras da feature `evolution`.
///
/// A tradução é compartilhada: as operações são CRUD sobre o mesmo recurso e
/// têm o mesmo repertório de falha, então dividem um conjunto de erro e um
/// `mapError`. O log registra a natureza da falha e a operação.

EvolutionError _mapEvolution(
  String operacao,
  Object exception,
  StackTrace stackTrace,
) {
  final kind = classificarFalhaGrpc(exception);
  developer.log(
    '\$operacao falhou: \$kind',
    name: 'admin_module.evolution',
    error: exception,
    stackTrace: stackTrace,
  );
  return switch (kind) {
    GrpcFailureKind.unauthenticated ||
    GrpcFailureKind.permissionDenied => const EvolutionAcessoNegado(),
    GrpcFailureKind.notFound => const EvolutionNaoEncontrado(),
    GrpcFailureKind.alreadyExists => const EvolutionConflito(),
    GrpcFailureKind.invalidArgument ||
    GrpcFailureKind.failedPrecondition => const EvolutionDadosInvalidos(),
    GrpcFailureKind.unavailable ||
    GrpcFailureKind.rateLimited => const EvolutionIndisponivel(),
    GrpcFailureKind.unknown => const EvolutionInesperado(),
  };
}

final class TestEvolutionConnectionRepository
    extends
        RepositoryBase<
          EvolutionConnectionResult,
          TestEvolutionConnectionParameters,
          EvolutionError
        > {
  const TestEvolutionConnectionRepository({required super.datasource});

  @override
  EvolutionError mapError(
    Object exception,
    StackTrace stackTrace,
    TestEvolutionConnectionParameters parameters,
  ) => _mapEvolution('testEvolutionConnection', exception, stackTrace);
}
