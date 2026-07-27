import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/config_errors.dart';
import '../model/tenant_config.dart';
import '../parameters/config_parameters.dart';

void _logBug(String operacao, Object exception, StackTrace stackTrace) =>
    developer.log(
      'process de $operacao quebrou',
      name: 'tenant_module.config',
      error: exception,
      stackTrace: stackTrace,
    );

final class GetMyTenantConfigUsecase
    extends
        UsecaseBaseCallData<
          TenantConfig,
          TenantConfig,
          NoParams,
          TenantConfigError
        > {
  const GetMyTenantConfigUsecase({required super.repository});

  @override
  ProcessData<TenantConfig, TenantConfig, NoParams, TenantConfigError>
  get process => _process;

  @override
  TenantConfigError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('getMyTenantConfig', exception, stackTrace);
    return const ConfigInesperado();
  }

  static ReturnSuccessOrError<TenantConfig, TenantConfigError> _process(
    TenantConfig data,
    NoParams parameters,
  ) => Success(data);
}

final class UpdateMyTenantConfigUsecase
    extends
        UsecaseBaseCallData<
          Unit,
          Unit,
          UpdateMyTenantConfigParameters,
          TenantConfigError
        > {
  const UpdateMyTenantConfigUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, UpdateMyTenantConfigParameters, TenantConfigError>
  get process => _process;

  @override
  TenantConfigError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('updateMyTenantConfig', exception, stackTrace);
    return const ConfigInesperado();
  }

  static ReturnSuccessOrError<Unit, TenantConfigError> _process(
    Unit data,
    UpdateMyTenantConfigParameters parameters,
  ) => const Success(unit);
}
