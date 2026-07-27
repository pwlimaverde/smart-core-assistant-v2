import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/tenant_config_errors.dart';
import '../model/tenant_config.dart';
import '../parameters/tenant_config_parameters.dart';

/// Casos de uso da feature `tenant_config`.
///
/// Os `process` são passthrough: a regra de negócio destas operações vive no
/// servidor (é o painel do superusuário). O que a base agrega aqui é o
/// `onUnexpected` — nenhuma exceção do processamento escapa para o controller.

void _logBug(String operacao, Object exception, StackTrace stackTrace) =>
    developer.log(
      'process de \$operacao quebrou',
      name: 'admin_module.tenant_config',
      error: exception,
      stackTrace: stackTrace,
    );

/// Lê a configuração de IA/persona de um tenant.
final class GetTenantConfigUsecase
    extends
        UsecaseBaseCallData<
          TenantConfig,
          TenantConfig,
          GetTenantConfigParameters,
          TenantConfigError
        > {
  const GetTenantConfigUsecase({required super.repository});

  @override
  ProcessData<
    TenantConfig,
    TenantConfig,
    GetTenantConfigParameters,
    TenantConfigError
  >
  get process => _process;

  @override
  TenantConfigError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('getTenantConfig', exception, stackTrace);
    return const TenantConfigInesperado();
  }

  static ReturnSuccessOrError<TenantConfig, TenantConfigError> _process(
    TenantConfig data,
    GetTenantConfigParameters parameters,
  ) => Success(data);
}

/// Grava a configuração de IA/persona de um tenant.
final class UpdateTenantConfigUsecase
    extends
        UsecaseBaseCallData<
          Unit,
          Unit,
          UpdateTenantConfigParameters,
          TenantConfigError
        > {
  const UpdateTenantConfigUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, UpdateTenantConfigParameters, TenantConfigError>
  get process => _process;

  @override
  TenantConfigError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('updateTenantConfig', exception, stackTrace);
    return const TenantConfigInesperado();
  }

  static ReturnSuccessOrError<Unit, TenantConfigError> _process(
    Unit data,
    UpdateTenantConfigParameters parameters,
  ) => Success(data);
}
