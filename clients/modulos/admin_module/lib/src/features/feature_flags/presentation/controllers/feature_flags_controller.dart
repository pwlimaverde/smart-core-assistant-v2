import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import '../../domain/errors/feature_flags_errors.dart';
import '../../domain/usecases/feature_flags_usecases.dart';
import '../../domain/parameters/feature_flags_parameters.dart';
import '../../domain/model/feature_flag.dart';
import '../../../tenants/domain/errors/tenants_errors.dart';
import '../../../tenants/domain/model/tenant.dart';
import '../../../tenants/domain/usecases/tenants_usecases.dart';

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

  Future<void> fetchFeatureFlags() => execute(() => _listUsecase(noParams));

  Future<ReturnSuccessOrError<Unit, FeatureFlagsError>> setFeatureFlag({
    required String key,
    required bool enabledGlobally,
  }) async {
    final res = await _setUsecase(
      SetFeatureFlagParameters(key: key, enabledGlobally: enabledGlobally),
    );
    if (res is Success) {
      await fetchFeatureFlags();
    }
    return res;
  }

  Future<ReturnSuccessOrError<Unit, FeatureFlagsError>> setFeatureFlagOverride({
    required String key,
    required String tenantId,
    required bool enabled,
    required bool removeOverride,
  }) async {
    final res = await _setOverrideUsecase(
      SetFeatureFlagOverrideParameters(
        key: key,
        tenantId: tenantId,
        enabled: enabled,
        removeOverride: removeOverride,
      ),
    );
    if (res is Success) {
      await fetchFeatureFlags();
    }
    return res;
  }

  Future<ReturnSuccessOrError<List<Tenant>, TenantsError>> getTenants() =>
      _listTenantsUsecase(noParams);
}
