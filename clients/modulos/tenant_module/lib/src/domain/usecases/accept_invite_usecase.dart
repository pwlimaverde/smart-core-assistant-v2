import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/tenant_user.dart';
import '../services/tenant_admin_service.dart';

final class AcceptInviteUsecase {
  final TenantAdminService _service;

  const AcceptInviteUsecase({required this._service});

  Future<ReturnSuccessOrError<AcceptedTenantUser>> call({
    required String token,
    required String username,
    required String email,
    required String password,
  }) =>
      _service.acceptInvite(
        token: token,
        username: username,
        email: email,
        password: password,
      );
}
