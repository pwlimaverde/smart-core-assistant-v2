import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/tenant_config_errors.dart';
import '../../domain/usecases/tenant_config_usecases.dart';
import '../../domain/parameters/tenant_config_parameters.dart';
import '../../domain/model/tenant_config.dart';

final class TenantConfigController extends BaseController<TenantConfig> {
  final GetTenantConfigUsecase _getUsecase;
  final UpdateTenantConfigUsecase _updateUsecase;

  TenantConfigController({
    required this._getUsecase,
    required this._updateUsecase,
  });

  Future<void> fetchConfig(String tenantId) =>
      execute(() => _getUsecase(GetTenantConfigParameters(tenantId: tenantId)));

  Future<ReturnSuccessOrError<Unit, TenantConfigError>> updateConfig({
    required String tenantId,
    required TenantConfig config,
  }) async {
    final res = await _updateUsecase(
      UpdateTenantConfigParameters(tenantId: tenantId, config: config),
    );
    if (res is Success) {
      await fetchConfig(tenantId);
    }
    return res;
  }
}
