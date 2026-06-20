import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/tenant_config.dart';
import '../../domain/usecases/get_tenant_config_usecase.dart';
import '../../domain/usecases/update_tenant_config_usecase.dart';

final class TenantConfigController extends BaseController<TenantConfig> {
  final GetTenantConfigUsecase _getUsecase;
  final UpdateTenantConfigUsecase _updateUsecase;

  TenantConfigController({
    required this._getUsecase,
    required this._updateUsecase,
  });

  Future<void> fetchConfig(String tenantId) => execute(() => _getUsecase.call(tenantId));

  Future<ReturnSuccessOrError<Unit>> updateConfig({
    required String tenantId,
    required TenantConfig config,
  }) async {
    final res = await _updateUsecase.call(tenantId: tenantId, config: config);
    if (res is SuccessReturn<Unit>) {
      await fetchConfig(tenantId);
    }
    return res;
  }
}
