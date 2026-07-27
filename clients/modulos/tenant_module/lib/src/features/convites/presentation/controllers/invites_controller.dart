import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/convites_errors.dart';
import '../../domain/model/tenant_invite.dart';
import '../../domain/parameters/convites_parameters.dart';
import '../../domain/usecases/convites_usecases.dart';

/// Controller da tela de convites do tenant.
///
/// Devolve o resultado de criar/revogar em vez de emitir estado de erro: a lista
/// continua exibida e a falha aparece em snackbar. Só o carregamento da lista
/// passa pelo [BaseController.execute].
final class InvitesController extends BaseController<List<TenantInvite>> {
  final ListInvitesUsecase _listUsecase;
  final CreateInviteUsecase _createUsecase;
  final RevokeInviteUsecase _revokeUsecase;

  InvitesController({
    required this._listUsecase,
    required this._createUsecase,
    required this._revokeUsecase,
  });

  Future<void> fetchInvites() => execute(() => _listUsecase(noParams));

  Future<ReturnSuccessOrError<TenantInviteCreated, ConvitesError>>
  createInvite({
    required String email,
    required String name,
    required String role,
    List<String> modulePermissions = const [],
    List<int> flowPermissions = const [],
  }) async {
    final res = await _createUsecase(
      CreateInviteParameters(
        email: email,
        name: name,
        role: role,
        modulePermissions: modulePermissions,
        flowPermissions: flowPermissions,
      ),
    );
    if (res is Success) await fetchInvites();
    return res;
  }

  Future<ReturnSuccessOrError<Unit, ConvitesError>> revokeInvite(
    String inviteId,
  ) async {
    final res = await _revokeUsecase(
      RevokeInviteParameters(inviteId: inviteId),
    );
    if (res is Success) await fetchInvites();
    return res;
  }
}
