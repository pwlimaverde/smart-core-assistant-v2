import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../../domain/model/tenant_config.dart';
import '../../../domain/usecases/get_my_tenant_config_usecase.dart';
import '../../../domain/usecases/update_my_tenant_config_usecase.dart';

final class TenantOwnConfigController extends BaseController<TenantConfig> {
  final GetMyTenantConfigUsecase _getUsecase;
  final UpdateMyTenantConfigUsecase _updateUsecase;

  TenantOwnConfigController({
    required this._getUsecase,
    required this._updateUsecase,
  });

  Future<void> fetchConfig() => execute(() => _getUsecase.call());

  Future<ReturnSuccessOrError<Unit>> updateConfig(TenantConfig config) async {
    final res = await _updateUsecase.call(config);
    if (res is SuccessReturn<Unit>) {
      await fetchConfig();
    }
    return res;
  }
}
