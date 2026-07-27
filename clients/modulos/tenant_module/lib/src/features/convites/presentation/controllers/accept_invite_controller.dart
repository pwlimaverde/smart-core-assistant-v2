import 'package:presentation_module/presentation_module.dart';

import '../../domain/model/accepted_tenant_user.dart';
import '../../domain/parameters/convites_parameters.dart';
import '../../domain/usecases/convites_usecases.dart';

/// Controller da tela pública de aceite de convite (sem sessão).
final class AcceptInviteController extends BaseController<AcceptedTenantUser> {
  final AcceptInviteUsecase _acceptUsecase;

  AcceptInviteController({required this._acceptUsecase});

  Future<void> accept({
    required String token,
    required String username,
    required String email,
    required String password,
  }) => execute(
    () => _acceptUsecase(
      AcceptInviteParameters(
        token: token,
        username: username,
        email: email,
        password: password,
      ),
    ),
  );
}
