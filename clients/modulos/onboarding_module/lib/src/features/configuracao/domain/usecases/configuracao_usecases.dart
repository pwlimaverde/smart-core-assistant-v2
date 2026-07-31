import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/configuracao_errors.dart';
import '../model/configuracao_models.dart';
import '../parameters/configuracao_parameters.dart';

/// Usecases da configuração guiada.

ConfiguracaoError _inesperado(String operacao, Object e, StackTrace s) {
  developer.log(
    'process de $operacao quebrou',
    name: 'onboarding_module.configuracao',
    error: e,
    stackTrace: s,
  );
  return const ConfiguracaoInesperada();
}

final class CriarConexaoUsecase extends UsecaseBaseCallData<ConexaoWhatsapp,
    ConexaoWhatsapp, CriarConexaoParameters, ConfiguracaoError> {
  const CriarConexaoUsecase({required super.repository});

  /// Sem `id` não há como consultar o pareamento — a tela ficaria esperando um
  /// QR que nunca chega.
  @override
  ProcessData<ConexaoWhatsapp, ConexaoWhatsapp, CriarConexaoParameters,
          ConfiguracaoError>
      get process => (data, _) => data.id <= 0
          ? const Failure(ConfiguracaoInesperada())
          : Success(data);

  @override
  ConfiguracaoError onUnexpected(Object e, StackTrace s) =>
      _inesperado('criar conexão', e, s);
}

final class EstadoConexaoUsecase extends UsecaseBaseCallData<EstadoConexao,
    EstadoConexao, EstadoConexaoParameters, ConfiguracaoError> {
  const EstadoConexaoUsecase({required super.repository});

  @override
  ProcessData<EstadoConexao, EstadoConexao, EstadoConexaoParameters,
      ConfiguracaoError> get process => (data, _) => Success(data);

  @override
  ConfiguracaoError onUnexpected(Object e, StackTrace s) =>
      _inesperado('consultar conexão', e, s);
}

final class CriarDepartamentoUsecase extends UsecaseBaseCallData<Departamento,
    Departamento, CriarDepartamentoParameters, ConfiguracaoError> {
  const CriarDepartamentoUsecase({required super.repository});

  @override
  ProcessData<Departamento, Departamento, CriarDepartamentoParameters,
      ConfiguracaoError> get process => (data, _) => Success(data);

  @override
  ConfiguracaoError onUnexpected(Object e, StackTrace s) =>
      _inesperado('criar departamento', e, s);
}

final class DefinirPersonaUsecase extends UsecaseBaseCallData<Unit, Unit,
    PersonaParameters, ConfiguracaoError> {
  const DefinirPersonaUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, PersonaParameters, ConfiguracaoError> get process =>
      (data, _) => Success(data);

  @override
  ConfiguracaoError onUnexpected(Object e, StackTrace s) =>
      _inesperado('definir persona', e, s);
}

final class ProgressoUsecase extends UsecaseBaseCallData<ProgressoOnboarding,
    ProgressoOnboarding, ProgressoParameters, ConfiguracaoError> {
  const ProgressoUsecase({required super.repository});

  @override
  ProcessData<ProgressoOnboarding, ProgressoOnboarding, ProgressoParameters,
      ConfiguracaoError> get process => (data, _) => Success(data);

  @override
  ConfiguracaoError onUnexpected(Object e, StackTrace s) =>
      _inesperado('registrar progresso', e, s);
}
