import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/treinamento_errors.dart';
import '../../domain/model/treinamento.dart';
import '../../domain/parameters/treinamento_parameters.dart';

/// Fronteira do treinamento: traduz falha de transporte em erro de domínio.
TreinamentoError _traduzir(Object exception, String operacao) {
  final kind = classificarFalhaGrpc(exception);
  developer.log(
    '$operacao falhou: $kind',
    name: 'treinamento_module.treinamento',
    error: exception,
  );
  return switch (kind) {
    GrpcFailureKind.invalidArgument => TreinamentoDadosInvalidos(
        exception is GrpcError ? exception.message : null,
      ),
    // O servidor recusa por `Validation` tanto dado inválido quanto
    // "não encontrado" — para quem está na tela, ambos querem dizer
    // "esse treinamento não serve", e a mensagem dele já explica qual é.
    GrpcFailureKind.notFound => const TreinamentoDadosInvalidos(
        'Este treinamento não existe mais. Atualize a lista.',
      ),
    GrpcFailureKind.alreadyExists => const TreinamentoDadosInvalidos(
        'Já existe um treinamento com essa tag neste grupo.',
      ),
    GrpcFailureKind.unauthenticated ||
    GrpcFailureKind.permissionDenied => const TreinamentoNaoAutorizado(),
    GrpcFailureKind.unavailable ||
    GrpcFailureKind.rateLimited ||
    GrpcFailureKind.failedPrecondition => const TreinamentoIndisponivel(),
    GrpcFailureKind.unknown => const TreinamentoInesperado(),
  };
}

final class ListarTreinamentosRepository
    extends RepositoryBase<List<Treinamento>, NoParams, TreinamentoError> {
  const ListarTreinamentosRepository({required super.datasource});

  @override
  TreinamentoError mapError(Object e, StackTrace s, NoParams p) =>
      _traduzir(e, 'listar treinamentos');
}

final class CriarTreinamentoRepository extends RepositoryBase<Treinamento,
    CriarTreinamentoParameters, TreinamentoError> {
  const CriarTreinamentoRepository({required super.datasource});

  @override
  TreinamentoError mapError(Object e, StackTrace s, CriarTreinamentoParameters p) =>
      _traduzir(e, 'criar treinamento');
}

final class ObterTreinamentoRepository extends RepositoryBase<Treinamento,
    TreinamentoIdParameters, TreinamentoError> {
  const ObterTreinamentoRepository({required super.datasource});

  @override
  TreinamentoError mapError(Object e, StackTrace s, TreinamentoIdParameters p) =>
      _traduzir(e, 'obter treinamento');
}

final class FinalizarTreinamentoRepository extends RepositoryBase<Unit,
    FinalizarTreinamentoParameters, TreinamentoError> {
  const FinalizarTreinamentoRepository({required super.datasource});

  @override
  TreinamentoError mapError(
    Object e,
    StackTrace s,
    FinalizarTreinamentoParameters p,
  ) =>
      _traduzir(e, 'finalizar treinamento');
}

final class RemoverTreinamentoRepository
    extends RepositoryBase<Unit, TreinamentoIdParameters, TreinamentoError> {
  const RemoverTreinamentoRepository({required super.datasource});

  @override
  TreinamentoError mapError(Object e, StackTrace s, TreinamentoIdParameters p) =>
      _traduzir(e, 'remover treinamento');
}
