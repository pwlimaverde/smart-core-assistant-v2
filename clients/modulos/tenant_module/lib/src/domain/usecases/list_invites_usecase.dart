import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/tenant_invite.dart';
import '../services/tenant_admin_service.dart';

final class ListInvitesUsecase {
  final TenantAdminService _service;

  const ListInvitesUsecase({required this._service});

  Future<ReturnSuccessOrError<List<TenantInvite>>> call() => _service.listInvites();
}
