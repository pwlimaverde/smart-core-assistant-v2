import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/transferencia_errors.dart';
import '../../domain/model/transferencia.dart';
import '../../domain/parameters/transferencia_parameters.dart';

TransferenciaError _traduzir(Object exception, String operacao) {
  final kind = classificarFalhaGrpc(exception);
  developer.log(
    '$operacao falhou: $kind',
    name: 'tenant_module.transferencia',
    error: exception,
  );
  return switch (kind) {
    GrpcFailureKind.invalidArgument ||
    GrpcFailureKind.alreadyExists ||
    GrpcFailureKind.failedPrecondition ||
    GrpcFailureKind.notFound => TransferenciaRecusada(
      exception is GrpcError ? exception.message : null,
    ),
    GrpcFailureKind.unauthenticated => const TransferenciaSessaoExpirada(),
    GrpcFailureKind.permissionDenied => const TransferenciaAcessoNegado(),
    GrpcFailureKind.unavailable ||
    GrpcFailureKind.rateLimited => const TransferenciaIndisponivel(),
    GrpcFailureKind.unknown => const TransferenciaInesperado(),
  };
}

final class CarregarTransferenciaRepository
    extends RepositoryBase<PainelTransferencia, NoParams, TransferenciaError> {
  const CarregarTransferenciaRepository({required super.datasource});

  @override
  TransferenciaError mapError(Object e, StackTrace s, NoParams p) =>
      _traduzir(e, 'carregar transferência');
}

final class SalvarRegraRepository
    extends
        RepositoryBase<
          RegraDeTransferencia,
          SalvarRegraParameters,
          TransferenciaError
        > {
  const SalvarRegraRepository({required super.datasource});

  @override
  TransferenciaError mapError(
    Object e,
    StackTrace s,
    SalvarRegraParameters p,
  ) => _traduzir(e, 'salvar regra');
}

final class DefinirRegraAtivaRepository
    extends
        RepositoryBase<
          RegraDeTransferencia,
          RegraAtivaParameters,
          TransferenciaError
        > {
  const DefinirRegraAtivaRepository({required super.datasource});

  @override
  TransferenciaError mapError(Object e, StackTrace s, RegraAtivaParameters p) =>
      _traduzir(e, 'ativar/desativar regra');
}

final class DefinirSinaisRepository
    extends
        RepositoryBase<
          ConfiguracaoDeTransferencia,
          SinaisParameters,
          TransferenciaError
        > {
  const DefinirSinaisRepository({required super.datasource});

  @override
  TransferenciaError mapError(Object e, StackTrace s, SinaisParameters p) =>
      _traduzir(e, 'alterar sinais');
}

final class TestarRegraRepository
    extends
        RepositoryBase<
          ResultadoTesteRegra,
          TestarRegraParameters,
          TransferenciaError
        > {
  const TestarRegraRepository({required super.datasource});

  @override
  TransferenciaError mapError(
    Object e,
    StackTrace s,
    TestarRegraParameters p,
  ) => _traduzir(e, 'testar regra');
}

final class GerarSugestoesRepository
    extends RepositoryBase<int, NoParams, TransferenciaError> {
  const GerarSugestoesRepository({required super.datasource});

  @override
  TransferenciaError mapError(Object e, StackTrace s, NoParams p) =>
      _traduzir(e, 'gerar sugestões');
}
