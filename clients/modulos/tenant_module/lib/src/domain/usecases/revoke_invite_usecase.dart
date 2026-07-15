import 'package:return_success_or_error/return_success_or_error.dart';

import '../services/tenant_admin_service.dart';

final class RevokeInviteUsecase {
  final TenantAdminService _service;

  const RevokeInviteUsecase({required this._service});

  Future<ReturnSuccessOrError<Unit>> call(String inviteId) => _service.revokeInvite(inviteId);
}
