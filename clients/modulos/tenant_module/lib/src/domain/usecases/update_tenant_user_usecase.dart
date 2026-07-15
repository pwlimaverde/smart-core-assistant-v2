import 'package:return_success_or_error/return_success_or_error.dart';

import '../services/tenant_admin_service.dart';

final class UpdateTenantUserUsecase {
  final TenantAdminService _service;

  const UpdateTenantUserUsecase({required this._service});

  Future<ReturnSuccessOrError<Unit>> call({
    required int userId,
    String? role,
    List<String>? modulePermissions,
    List<int>? flowPermissions,
  }) =>
      _service.updateTenantUser(
        userId: userId,
        role: role,
        modulePermissions: modulePermissions,
        flowPermissions: flowPermissions,
      );
}
