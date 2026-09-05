import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/conexoes_errors.dart';
import '../../domain/model/conexao.dart';
import '../../domain/parameters/conexoes_parameters.dart';

ConexoesError _traduzir(Object exception, String operacao) {
  final kind = classificarFalhaGrpc(exception);
  developer.log(
    '$operacao falhou: $kind',
    name: 'tenant_module.conexoes',
    error: exception,
  );
  return switch (kind) {
    GrpcFailureKind.notFound => const ConexaoNaoEncontrada(),
    GrpcFailureKind.invalidArgument ||
    GrpcFailureKind.alreadyExists ||
    // O provedor fora do ar chega como `failedPrecondition` do data_whatsapp:
    // é recusa da operação, não indisponibilidade nossa — e a mensagem dele
    // explica o que houve.
    GrpcFailureKind.failedPrecondition => ConexaoRecusada(
        exception is GrpcError ? exception.message : null,
      ),
    GrpcFailureKind.unauthenticated ||
    GrpcFailureKind.permissionDenied => const ConexoesAcessoNegado(),
    GrpcFailureKind.unavailable ||
    GrpcFailureKind.rateLimited => const ConexoesIndisponivel(),
    GrpcFailureKind.unknown => const ConexoesInesperado(),
  };
}

final class ListarConexoesRepository
    extends RepositoryBase<List<Conexao>, NoParams, ConexoesError> {
  const ListarConexoesRepository({required super.datasource});

  @override
  ConexoesError mapError(Object e, StackTrace s, NoParams p) =>
      _traduzir(e, 'listar conexões');
}

final class ReconectarConexaoRepository
    extends RepositoryBase<Unit, ConexaoIdParameters, ConexoesError> {
  const ReconectarConexaoRepository({required super.datasource});

  @override
  ConexoesError mapError(Object e, StackTrace s, ConexaoIdParameters p) =>
      _traduzir(e, 'reconectar');
}

final class RemoverConexaoRepository
    extends RepositoryBase<Unit, ConexaoIdParameters, ConexoesError> {
  const RemoverConexaoRepository({required super.datasource});

  @override
  ConexoesError mapError(Object e, StackTrace s, ConexaoIdParameters p) =>
      _traduzir(e, 'remover conexão');
}

final class CriarConexaoRepository
    extends RepositoryBase<ConexaoCriada, CriarConexaoParameters, ConexoesError> {
  const CriarConexaoRepository({required super.datasource});

  @override
  ConexoesError mapError(Object e, StackTrace s, CriarConexaoParameters p) =>
      _traduzir(e, 'criar conexão');
}

final class EstadoPareamentoRepository
    extends RepositoryBase<EstadoPareamento, ConexaoIdParameters, ConexoesError> {
  const EstadoPareamentoRepository({required super.datasource});

  @override
  ConexoesError mapError(Object e, StackTrace s, ConexaoIdParameters p) =>
      _traduzir(e, 'consultar pareamento');
}
