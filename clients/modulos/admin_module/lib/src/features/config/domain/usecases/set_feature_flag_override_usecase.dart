import 'package:return_success_or_error/return_success_or_error.dart';

import '../services/admin_service.dart';

final class SetFeatureFlagOverrideUsecase {
  final AdminService _service;

  const SetFeatureFlagOverrideUsecase({required this._service});

  Future<ReturnSuccessOrError<Unit>> call({
    required String key,
    required String tenantId,
    required bool enabled,
    required bool removeOverride,
  }) =>
      _service.setFeatureFlagOverride(
        key: key,
        tenantId: tenantId,
        enabled: enabled,
        removeOverride: removeOverride,
      );
}
