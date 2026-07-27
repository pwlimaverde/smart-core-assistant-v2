import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/core_settings_errors.dart';
import '../model/core_setting.dart';
import '../parameters/core_settings_parameters.dart';

/// Casos de uso da feature `core_settings`.
///
/// Os `process` são passthrough: a regra de negócio destas operações vive no
/// servidor (é o painel do superusuário). O que a base agrega aqui é o
/// `onUnexpected` — nenhuma exceção do processamento escapa para o controller.

void _logBug(String operacao, Object exception, StackTrace stackTrace) =>
    developer.log(
      'process de \$operacao quebrou',
      name: 'admin_module.core_settings',
      error: exception,
      stackTrace: stackTrace,
    );

/// Lista as configurações globais do sistema.
final class ListCoreSettingsUsecase
    extends
        UsecaseBaseCallData<
          List<CoreSetting>,
          List<CoreSetting>,
          NoParams,
          CoreSettingsError
        > {
  const ListCoreSettingsUsecase({required super.repository});

  @override
  ProcessData<List<CoreSetting>, List<CoreSetting>, NoParams, CoreSettingsError>
  get process => _process;

  @override
  CoreSettingsError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('listCoreSettings', exception, stackTrace);
    return const CoreSettingsInesperado();
  }

  static ReturnSuccessOrError<List<CoreSetting>, CoreSettingsError> _process(
    List<CoreSetting> data,
    NoParams parameters,
  ) => Success(data);
}

/// Cria ou atualiza uma configuração global.
final class UpsertCoreSettingUsecase
    extends
        UsecaseBaseCallData<
          Unit,
          Unit,
          UpsertCoreSettingParameters,
          CoreSettingsError
        > {
  const UpsertCoreSettingUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, UpsertCoreSettingParameters, CoreSettingsError>
  get process => _process;

  @override
  CoreSettingsError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('upsertCoreSetting', exception, stackTrace);
    return const CoreSettingsInesperado();
  }

  static ReturnSuccessOrError<Unit, CoreSettingsError> _process(
    Unit data,
    UpsertCoreSettingParameters parameters,
  ) => Success(data);
}

/// Remove uma configuração global.
final class DeleteCoreSettingUsecase
    extends
        UsecaseBaseCallData<
          Unit,
          Unit,
          DeleteCoreSettingParameters,
          CoreSettingsError
        > {
  const DeleteCoreSettingUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, DeleteCoreSettingParameters, CoreSettingsError>
  get process => _process;

  @override
  CoreSettingsError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('deleteCoreSetting', exception, stackTrace);
    return const CoreSettingsInesperado();
  }

  static ReturnSuccessOrError<Unit, CoreSettingsError> _process(
    Unit data,
    DeleteCoreSettingParameters parameters,
  ) => Success(data);
}
