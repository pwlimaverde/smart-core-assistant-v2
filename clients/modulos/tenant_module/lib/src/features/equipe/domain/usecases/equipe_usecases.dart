import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/equipe_errors.dart';
import '../model/equipe.dart';
import '../parameters/equipe_parameters.dart';

EquipeError _inesperado(String operacao, Object e, StackTrace s) {
  developer.log(
    '$operacao: exceção fora da fronteira',
    name: 'tenant_module.equipe.usecase',
    error: e,
    stackTrace: s,
  );
  return const EquipeInesperado();
}

final class CarregarEquipeUsecase
    extends UsecaseBaseCallData<Equipe, Equipe, NoParams, EquipeError> {
  const CarregarEquipeUsecase({required super.repository});

  @override
  ProcessData<Equipe, Equipe, NoParams, EquipeError> get process =>
      (data, _) => Success(data);

  @override
  EquipeError onUnexpected(Object e, StackTrace s) =>
      _inesperado('carregar equipe', e, s);
}

final class CriarDepartamentoUsecase extends UsecaseBaseCallData<Unit, Unit,
    CriarDepartamentoParameters, EquipeError> {
  const CriarDepartamentoUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, CriarDepartamentoParameters, EquipeError>
      get process => (data, _) => Success(data);

  @override
  EquipeError onUnexpected(Object e, StackTrace s) =>
      _inesperado('criar departamento', e, s);
}

final class AtualizarDepartamentoUsecase extends UsecaseBaseCallData<Unit, Unit,
    AtualizarDepartamentoParameters, EquipeError> {
  const AtualizarDepartamentoUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, AtualizarDepartamentoParameters, EquipeError>
      get process => (data, _) => Success(data);

  @override
  EquipeError onUnexpected(Object e, StackTrace s) =>
      _inesperado('atualizar departamento', e, s);
}

final class DesativarDepartamentoUsecase extends UsecaseBaseCallData<Unit, Unit,
    DepartamentoIdParameters, EquipeError> {
  const DesativarDepartamentoUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, DepartamentoIdParameters, EquipeError> get process =>
      (data, _) => Success(data);

  @override
  EquipeError onUnexpected(Object e, StackTrace s) =>
      _inesperado('desativar departamento', e, s);
}

final class CriarAtendenteUsecase extends UsecaseBaseCallData<Unit, Unit,
    CriarAtendenteParameters, EquipeError> {
  const CriarAtendenteUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, CriarAtendenteParameters, EquipeError> get process =>
      (data, _) => Success(data);

  @override
  EquipeError onUnexpected(Object e, StackTrace s) =>
      _inesperado('criar atendente', e, s);
}

final class AtualizarAtendenteUsecase extends UsecaseBaseCallData<Unit, Unit,
    AtualizarAtendenteParameters, EquipeError> {
  const AtualizarAtendenteUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, AtualizarAtendenteParameters, EquipeError>
      get process => (data, _) => Success(data);

  @override
  EquipeError onUnexpected(Object e, StackTrace s) =>
      _inesperado('atualizar atendente', e, s);
}

final class DesativarAtendenteUsecase extends UsecaseBaseCallData<Unit, Unit,
    AtendenteIdParameters, EquipeError> {
  const DesativarAtendenteUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, AtendenteIdParameters, EquipeError> get process =>
      (data, _) => Success(data);

  @override
  EquipeError onUnexpected(Object e, StackTrace s) =>
      _inesperado('desativar atendente', e, s);
}
