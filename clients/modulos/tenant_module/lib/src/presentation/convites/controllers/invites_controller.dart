import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../../domain/model/tenant_invite.dart';
import '../../../domain/usecases/create_invite_usecase.dart';
import '../../../domain/usecases/list_invites_usecase.dart';
import '../../../domain/usecases/revoke_invite_usecase.dart';

final class InvitesController extends BaseController<List<TenantInvite>> {
  final ListInvitesUsecase _listUsecase;
  final CreateInviteUsecase _createUsecase;
  final RevokeInviteUsecase _revokeUsecase;

  InvitesController({
    required this._listUsecase,
    required this._createUsecase,
    required this._revokeUsecase,
  });

  Future<void> fetchInvites() => execute(() => _listUsecase.call());

  Future<ReturnSuccessOrError<TenantInviteCreated>> createInvite({
    required String email,
    required String name,
    required String role,
    List<String> modulePermissions = const [],
    List<int> flowPermissions = const [],
  }) async {
    final res = await _createUsecase.call(
      email: email,
      name: name,
      role: role,
      modulePermissions: modulePermissions,
      flowPermissions: flowPermissions,
    );
    if (res is SuccessReturn<TenantInviteCreated>) {
      await fetchInvites();
    }
    return res;
  }

  Future<ReturnSuccessOrError<Unit>> revokeInvite(String inviteId) async {
    final res = await _revokeUsecase.call(inviteId);
    if (res is SuccessReturn<Unit>) {
      await fetchInvites();
    }
    return res;
  }
}
