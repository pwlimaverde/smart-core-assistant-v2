import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/treinamento_errors.dart';
import '../model/treinamento.dart';
import '../parameters/treinamento_parameters.dart';

TreinamentoError _inesperado(String operacao, Object e, StackTrace s) {
  developer.log(
    '$operacao: exceção fora da fronteira',
    name: 'treinamento_module.usecase',
    error: e,
    stackTrace: s,
  );
  return const TreinamentoInesperado();
}

final class ListarTreinamentosUsecase extends UsecaseBaseCallData<
    List<Treinamento>, List<Treinamento>, NoParams, TreinamentoError> {
  const ListarTreinamentosUsecase({required super.repository});

  @override
  ProcessData<List<Treinamento>, List<Treinamento>, NoParams, TreinamentoError>
      get process => (data, _) => Success(data);

  @override
  TreinamentoError onUnexpected(Object e, StackTrace s) =>
      _inesperado('listar treinamentos', e, s);
}

final class CriarTreinamentoUsecase extends UsecaseBaseCallData<Treinamento,
    Treinamento, CriarTreinamentoParameters, TreinamentoError> {
  const CriarTreinamentoUsecase({required super.repository});

  @override
  ProcessData<Treinamento, Treinamento, CriarTreinamentoParameters,
      TreinamentoError> get process => (data, _) => Success(data);

  @override
  TreinamentoError onUnexpected(Object e, StackTrace s) =>
      _inesperado('criar treinamento', e, s);
}

final class ObterTreinamentoUsecase extends UsecaseBaseCallData<Treinamento,
    Treinamento, TreinamentoIdParameters, TreinamentoError> {
  const ObterTreinamentoUsecase({required super.repository});

  @override
  ProcessData<Treinamento, Treinamento, TreinamentoIdParameters,
      TreinamentoError> get process => (data, _) => Success(data);

  @override
  TreinamentoError onUnexpected(Object e, StackTrace s) =>
      _inesperado('obter treinamento', e, s);
}

final class FinalizarTreinamentoUsecase extends UsecaseBaseCallData<Unit, Unit,
    FinalizarTreinamentoParameters, TreinamentoError> {
  const FinalizarTreinamentoUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, FinalizarTreinamentoParameters, TreinamentoError>
      get process => (data, _) => Success(data);

  @override
  TreinamentoError onUnexpected(Object e, StackTrace s) =>
      _inesperado('finalizar treinamento', e, s);
}

final class RemoverTreinamentoUsecase extends UsecaseBaseCallData<Unit, Unit,
    TreinamentoIdParameters, TreinamentoError> {
  const RemoverTreinamentoUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, TreinamentoIdParameters, TreinamentoError>
      get process => (data, _) => Success(data);

  @override
  TreinamentoError onUnexpected(Object e, StackTrace s) =>
      _inesperado('remover treinamento', e, s);
}
