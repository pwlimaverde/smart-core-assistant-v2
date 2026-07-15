import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/tenant_invite.dart';
import '../services/tenant_admin_service.dart';

final class CreateInviteUsecase {
  final TenantAdminService _service;

  const CreateInviteUsecase({required this._service});

  Future<ReturnSuccessOrError<TenantInviteCreated>> call({
    required String email,
    required String name,
    required String role,
    List<String> modulePermissions = const [],
    List<int> flowPermissions = const [],
  }) =>
      _service.createInvite(
        email: email,
        name: name,
        role: role,
        modulePermissions: modulePermissions,
        flowPermissions: flowPermissions,
      );
}
