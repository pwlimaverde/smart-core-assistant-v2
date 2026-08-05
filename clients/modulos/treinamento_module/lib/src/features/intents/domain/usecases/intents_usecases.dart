import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/intents_errors.dart';
import '../model/intent.dart';
import '../parameters/intents_parameters.dart';

IntentsError _inesperado(String operacao, Object e, StackTrace s) {
  developer.log(
    '$operacao: exceção fora da fronteira',
    name: 'treinamento_module.intents.usecase',
    error: e,
    stackTrace: s,
  );
  return const IntentsInesperado();
}

final class ListarIntentsUsecase extends UsecaseBaseCallData<List<IntentIa>,
    List<IntentIa>, NoParams, IntentsError> {
  const ListarIntentsUsecase({required super.repository});

  @override
  ProcessData<List<IntentIa>, List<IntentIa>, NoParams, IntentsError> get process =>
      (data, _) => Success(data);

  @override
  IntentsError onUnexpected(Object e, StackTrace s) =>
      _inesperado('listar intenções', e, s);
}

final class CriarIntentUsecase extends UsecaseBaseCallData<Unit, Unit,
    CriarIntentParameters, IntentsError> {
  const CriarIntentUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, CriarIntentParameters, IntentsError> get process =>
      (data, _) => Success(data);

  @override
  IntentsError onUnexpected(Object e, StackTrace s) =>
      _inesperado('criar intenção', e, s);
}

final class AtualizarIntentUsecase extends UsecaseBaseCallData<Unit, Unit,
    AtualizarIntentParameters, IntentsError> {
  const AtualizarIntentUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, AtualizarIntentParameters, IntentsError>
      get process => (data, _) => Success(data);

  @override
  IntentsError onUnexpected(Object e, StackTrace s) =>
      _inesperado('atualizar intenção', e, s);
}

final class RemoverIntentUsecase extends UsecaseBaseCallData<Unit, Unit,
    IntentIdParameters, IntentsError> {
  const RemoverIntentUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, IntentIdParameters, IntentsError> get process =>
      (data, _) => Success(data);

  @override
  IntentsError onUnexpected(Object e, StackTrace s) =>
      _inesperado('remover intenção', e, s);
}
