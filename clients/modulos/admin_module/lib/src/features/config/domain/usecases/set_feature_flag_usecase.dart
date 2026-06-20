import 'package:return_success_or_error/return_success_or_error.dart';

import '../services/admin_service.dart';

final class SetFeatureFlagUsecase {
  final AdminService _service;

  const SetFeatureFlagUsecase({required this._service});

  Future<ReturnSuccessOrError<Unit>> call({
    required String key,
    required bool enabledGlobally,
  }) =>
      _service.setFeatureFlag(key: key, enabledGlobally: enabledGlobally);
}
