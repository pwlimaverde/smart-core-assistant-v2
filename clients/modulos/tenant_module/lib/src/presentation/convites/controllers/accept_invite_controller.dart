import 'package:presentation_module/presentation_module.dart';

import '../../../domain/model/tenant_user.dart';
import '../../../domain/usecases/accept_invite_usecase.dart';

/// Controller da tela pública de aceite de convite (sem sessão).
final class AcceptInviteController extends BaseController<AcceptedTenantUser> {
  final AcceptInviteUsecase _acceptUsecase;

  AcceptInviteController({required this._acceptUsecase});

  Future<void> accept({
    required String token,
    required String username,
    required String email,
    required String password,
  }) =>
      execute(() => _acceptUsecase.call(
            token: token,
            username: username,
            email: email,
            password: password,
          ));
}
