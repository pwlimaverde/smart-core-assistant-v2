import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/fluxos_errors.dart';
import '../model/fluxo.dart';
import '../parameters/fluxos_parameters.dart';

FluxosError _inesperado(String operacao, Object e, StackTrace s) {
  developer.log(
    '$operacao: exceção fora da fronteira',
    name: 'tenant_module.fluxos.usecase',
    error: e,
    stackTrace: s,
  );
  return const FluxosInesperado();
}

final class ListarFluxosUsecase extends UsecaseBaseCallData<List<Fluxo>,
    List<Fluxo>, NoParams, FluxosError> {
  const ListarFluxosUsecase({required super.repository});

  @override
  ProcessData<List<Fluxo>, List<Fluxo>, NoParams, FluxosError> get process =>
      (data, _) => Success(data);

  @override
  FluxosError onUnexpected(Object e, StackTrace s) =>
      _inesperado('listar fluxos', e, s);
}

final class CriarFluxoUsecase
    extends UsecaseBaseCallData<Unit, Unit, CriarFluxoParameters, FluxosError> {
  const CriarFluxoUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, CriarFluxoParameters, FluxosError> get process =>
      (data, _) => Success(data);

  @override
  FluxosError onUnexpected(Object e, StackTrace s) =>
      _inesperado('criar fluxo', e, s);
}

final class AtualizarFluxoUsecase extends UsecaseBaseCallData<Unit, Unit,
    AtualizarFluxoParameters, FluxosError> {
  const AtualizarFluxoUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, AtualizarFluxoParameters, FluxosError> get process =>
      (data, _) => Success(data);

  @override
  FluxosError onUnexpected(Object e, StackTrace s) =>
      _inesperado('atualizar fluxo', e, s);
}

final class DesativarFluxoUsecase
    extends UsecaseBaseCallData<Unit, Unit, FluxoIdParameters, FluxosError> {
  const DesativarFluxoUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, FluxoIdParameters, FluxosError> get process =>
      (data, _) => Success(data);

  @override
  FluxosError onUnexpected(Object e, StackTrace s) =>
      _inesperado('desativar fluxo', e, s);
}

final class ListarEtapasUsecase extends UsecaseBaseCallData<List<EtapaFluxo>,
    List<EtapaFluxo>, FluxoIdParameters, FluxosError> {
  const ListarEtapasUsecase({required super.repository});

  @override
  ProcessData<List<EtapaFluxo>, List<EtapaFluxo>, FluxoIdParameters,
      FluxosError> get process => (data, _) => Success(data);

  @override
  FluxosError onUnexpected(Object e, StackTrace s) =>
      _inesperado('listar etapas', e, s);
}

final class CriarEtapaUsecase
    extends UsecaseBaseCallData<Unit, Unit, CriarEtapaParameters, FluxosError> {
  const CriarEtapaUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, CriarEtapaParameters, FluxosError> get process =>
      (data, _) => Success(data);

  @override
  FluxosError onUnexpected(Object e, StackTrace s) =>
      _inesperado('criar etapa', e, s);
}

final class AtualizarEtapaUsecase extends UsecaseBaseCallData<Unit, Unit,
    AtualizarEtapaParameters, FluxosError> {
  const AtualizarEtapaUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, AtualizarEtapaParameters, FluxosError> get process =>
      (data, _) => Success(data);

  @override
  FluxosError onUnexpected(Object e, StackTrace s) =>
      _inesperado('atualizar etapa', e, s);
}

final class DesativarEtapaUsecase
    extends UsecaseBaseCallData<Unit, Unit, EtapaIdParameters, FluxosError> {
  const DesativarEtapaUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, EtapaIdParameters, FluxosError> get process =>
      (data, _) => Success(data);

  @override
  FluxosError onUnexpected(Object e, StackTrace s) =>
      _inesperado('remover etapa', e, s);
}

final class MoverEtapaUsecase
    extends UsecaseBaseCallData<bool, bool, MoverEtapaParameters, FluxosError> {
  const MoverEtapaUsecase({required super.repository});

  @override
  ProcessData<bool, bool, MoverEtapaParameters, FluxosError> get process =>
      (data, _) => Success(data);

  @override
  FluxosError onUnexpected(Object e, StackTrace s) =>
      _inesperado('mover etapa', e, s);
}
