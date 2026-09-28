import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/transferencia_errors.dart';
import '../model/transferencia.dart';
import '../parameters/transferencia_parameters.dart';

TransferenciaError _inesperado(String operacao, Object e, StackTrace s) {
  developer.log(
    '$operacao: exceção fora da fronteira',
    name: 'tenant_module.transferencia.usecase',
    error: e,
    stackTrace: s,
  );
  return const TransferenciaInesperado();
}

final class CarregarTransferenciaUsecase
    extends
        UsecaseBaseCallData<
          PainelTransferencia,
          PainelTransferencia,
          NoParams,
          TransferenciaError
        > {
  const CarregarTransferenciaUsecase({required super.repository});

  @override
  ProcessData<
    PainelTransferencia,
    PainelTransferencia,
    NoParams,
    TransferenciaError
  >
  get process =>
      (data, _) => Success(data);

  @override
  TransferenciaError onUnexpected(Object e, StackTrace s) =>
      _inesperado('carregar transferência', e, s);
}

final class SalvarRegraUsecase
    extends
        UsecaseBaseCallData<
          RegraDeTransferencia,
          RegraDeTransferencia,
          SalvarRegraParameters,
          TransferenciaError
        > {
  const SalvarRegraUsecase({required super.repository});

  @override
  ProcessData<
    RegraDeTransferencia,
    RegraDeTransferencia,
    SalvarRegraParameters,
    TransferenciaError
  >
  get process =>
      (data, _) => Success(data);

  @override
  TransferenciaError onUnexpected(Object e, StackTrace s) =>
      _inesperado('salvar regra', e, s);
}

final class DefinirRegraAtivaUsecase
    extends
        UsecaseBaseCallData<
          RegraDeTransferencia,
          RegraDeTransferencia,
          RegraAtivaParameters,
          TransferenciaError
        > {
  const DefinirRegraAtivaUsecase({required super.repository});

  @override
  ProcessData<
    RegraDeTransferencia,
    RegraDeTransferencia,
    RegraAtivaParameters,
    TransferenciaError
  >
  get process =>
      (data, _) => Success(data);

  @override
  TransferenciaError onUnexpected(Object e, StackTrace s) =>
      _inesperado('ativar/desativar regra', e, s);
}

final class DefinirSinaisUsecase
    extends
        UsecaseBaseCallData<
          ConfiguracaoDeTransferencia,
          ConfiguracaoDeTransferencia,
          SinaisParameters,
          TransferenciaError
        > {
  const DefinirSinaisUsecase({required super.repository});

  @override
  ProcessData<
    ConfiguracaoDeTransferencia,
    ConfiguracaoDeTransferencia,
    SinaisParameters,
    TransferenciaError
  >
  get process =>
      (data, _) => Success(data);

  @override
  TransferenciaError onUnexpected(Object e, StackTrace s) =>
      _inesperado('alterar sinais', e, s);
}

final class TestarRegraUsecase
    extends
        UsecaseBaseCallData<
          ResultadoTesteRegra,
          ResultadoTesteRegra,
          TestarRegraParameters,
          TransferenciaError
        > {
  const TestarRegraUsecase({required super.repository});

  @override
  ProcessData<
    ResultadoTesteRegra,
    ResultadoTesteRegra,
    TestarRegraParameters,
    TransferenciaError
  >
  get process =>
      (data, _) => Success(data);

  @override
  TransferenciaError onUnexpected(Object e, StackTrace s) =>
      _inesperado('testar regra', e, s);
}

final class GerarSugestoesUsecase
    extends UsecaseBaseCallData<int, int, NoParams, TransferenciaError> {
  const GerarSugestoesUsecase({required super.repository});

  @override
  ProcessData<int, int, NoParams, TransferenciaError> get process =>
      (data, _) => Success(data);

  @override
  TransferenciaError onUnexpected(Object e, StackTrace s) =>
      _inesperado('gerar sugestões', e, s);
}
