import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import '../../domain/model/feature_flag.dart';
import '../../domain/model/tenant.dart';
import '../../domain/usecases/list_feature_flags_usecase.dart';
import '../../domain/usecases/set_feature_flag_usecase.dart';
import '../../domain/usecases/set_feature_flag_override_usecase.dart';
import '../../domain/usecases/list_tenants_usecase.dart';

final class FeatureFlagsController extends BaseController<List<FeatureFlag>> {
  final ListFeatureFlagsUsecase _listUsecase;
  final SetFeatureFlagUsecase _setUsecase;
  final SetFeatureFlagOverrideUsecase _setOverrideUsecase;
  final ListTenantsUsecase _listTenantsUsecase;

  FeatureFlagsController({
    required this._listUsecase,
    required this._setUsecase,
    required this._setOverrideUsecase,
    required this._listTenantsUsecase,
  });

  Future<void> fetchFeatureFlags() => execute(() => _listUsecase.call());

  Future<ReturnSuccessOrError<Unit>> setFeatureFlag({
    required String key,
    required bool enabledGlobally,
  }) async {
    final res = await _setUsecase.call(key: key, enabledGlobally: enabledGlobally);
    if (res is SuccessReturn<Unit>) {
      await fetchFeatureFlags();
    }
    return res;
  }

  Future<ReturnSuccessOrError<Unit>> setFeatureFlagOverride({
    required String key,
    required String tenantId,
    required bool enabled,
    required bool removeOverride,
  }) async {
    final res = await _setOverrideUsecase.call(
      key: key,
      tenantId: tenantId,
      enabled: enabled,
      removeOverride: removeOverride,
    );
    if (res is SuccessReturn<Unit>) {
      await fetchFeatureFlags();
    }
    return res;
  }

  Future<ReturnSuccessOrError<List<Tenant>>> getTenants() => _listTenantsUsecase.call();
}
