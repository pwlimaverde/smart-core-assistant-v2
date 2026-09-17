import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/ignorados_errors.dart';
import '../model/numero_ignorado.dart';
import '../parameters/ignorados_parameters.dart';

IgnoradosError _inesperado(String operacao, Object e, StackTrace s) {
  developer.log(
    '$operacao: exceção fora da fronteira',
    name: 'tenant_module.ignorados.usecase',
    error: e,
    stackTrace: s,
  );
  return const IgnoradosInesperado();
}

final class ListarIgnoradosUsecase
    extends
        UsecaseBaseCallData<
          List<NumeroIgnorado>,
          List<NumeroIgnorado>,
          NoParams,
          IgnoradosError
        > {
  const ListarIgnoradosUsecase({required super.repository});

  @override
  ProcessData<List<NumeroIgnorado>, List<NumeroIgnorado>, NoParams,
      IgnoradosError>
  get process =>
      (data, _) => Success(data);

  @override
  IgnoradosError onUnexpected(Object e, StackTrace s) =>
      _inesperado('listar números ignorados', e, s);
}

final class CriarIgnoradoUsecase
    extends
        UsecaseBaseCallData<
          NumeroIgnorado,
          NumeroIgnorado,
          CriarIgnoradoParameters,
          IgnoradosError
        > {
  const CriarIgnoradoUsecase({required super.repository});

  @override
  ProcessData<NumeroIgnorado, NumeroIgnorado, CriarIgnoradoParameters,
      IgnoradosError>
  get process =>
      (data, _) => Success(data);

  @override
  IgnoradosError onUnexpected(Object e, StackTrace s) =>
      _inesperado('criar número ignorado', e, s);
}

final class AtualizarIgnoradoUsecase
    extends
        UsecaseBaseCallData<
          Unit,
          Unit,
          AtualizarIgnoradoParameters,
          IgnoradosError
        > {
  const AtualizarIgnoradoUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, AtualizarIgnoradoParameters, IgnoradosError>
  get process =>
      (data, _) => Success(data);

  @override
  IgnoradosError onUnexpected(Object e, StackTrace s) =>
      _inesperado('atualizar número ignorado', e, s);
}

final class RemoverIgnoradoUsecase
    extends
        UsecaseBaseCallData<Unit, Unit, IgnoradoIdParameters, IgnoradosError> {
  const RemoverIgnoradoUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, IgnoradoIdParameters, IgnoradosError> get process =>
      (data, _) => Success(data);

  @override
  IgnoradosError onUnexpected(Object e, StackTrace s) =>
      _inesperado('remover número ignorado', e, s);
}
