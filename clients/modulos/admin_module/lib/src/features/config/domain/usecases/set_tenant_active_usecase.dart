import 'package:return_success_or_error/return_success_or_error.dart';

import '../services/admin_service.dart';

final class SetTenantActiveUsecase {
  final AdminService _service;

  const SetTenantActiveUsecase({required this._service});

  Future<ReturnSuccessOrError<Unit>> call({
    required String id,
    required bool active,
  }) =>
      _service.setTenantActive(id: id, active: active);
}
