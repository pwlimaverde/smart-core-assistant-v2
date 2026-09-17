import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/ignorados_errors.dart';
import '../../domain/model/numero_ignorado.dart';
import '../../domain/parameters/ignorados_parameters.dart';

IgnoradosError _traduzir(Object exception, String operacao) {
  final kind = classificarFalhaGrpc(exception);
  developer.log(
    '$operacao falhou: $kind',
    name: 'tenant_module.ignorados',
    error: exception,
  );
  return switch (kind) {
    GrpcFailureKind.notFound => const IgnoradoNaoEncontrado(),
    // `alreadyExists` é o caso comum aqui: o par (tenant, telefone) é único, e
    // repetir o número é o erro que mais acontece nesta tela.
    GrpcFailureKind.invalidArgument ||
    GrpcFailureKind.alreadyExists ||
    GrpcFailureKind.failedPrecondition => IgnoradoRecusado(
      exception is GrpcError ? exception.message : null,
    ),
    GrpcFailureKind.unauthenticated => const IgnoradosSessaoExpirada(),
    GrpcFailureKind.permissionDenied => const IgnoradosAcessoNegado(),
    GrpcFailureKind.unavailable ||
    GrpcFailureKind.rateLimited => const IgnoradosIndisponivel(),
    GrpcFailureKind.unknown => const IgnoradosInesperado(),
  };
}

final class ListarIgnoradosRepository
    extends RepositoryBase<List<NumeroIgnorado>, NoParams, IgnoradosError> {
  const ListarIgnoradosRepository({required super.datasource});

  @override
  IgnoradosError mapError(Object e, StackTrace s, NoParams p) =>
      _traduzir(e, 'listar números ignorados');
}

final class CriarIgnoradoRepository
    extends
        RepositoryBase<
          NumeroIgnorado,
          CriarIgnoradoParameters,
          IgnoradosError
        > {
  const CriarIgnoradoRepository({required super.datasource});

  @override
  IgnoradosError mapError(Object e, StackTrace s, CriarIgnoradoParameters p) =>
      _traduzir(e, 'criar número ignorado');
}

final class AtualizarIgnoradoRepository
    extends RepositoryBase<Unit, AtualizarIgnoradoParameters, IgnoradosError> {
  const AtualizarIgnoradoRepository({required super.datasource});

  @override
  IgnoradosError mapError(
    Object e,
    StackTrace s,
    AtualizarIgnoradoParameters p,
  ) => _traduzir(e, 'atualizar número ignorado');
}

final class RemoverIgnoradoRepository
    extends RepositoryBase<Unit, IgnoradoIdParameters, IgnoradosError> {
  const RemoverIgnoradoRepository({required super.datasource});

  @override
  IgnoradosError mapError(Object e, StackTrace s, IgnoradoIdParameters p) =>
      _traduzir(e, 'remover número ignorado');
}
