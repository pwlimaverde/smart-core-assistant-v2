import 'package:dependencies_module/dependencies_module.dart';

import '../../../domain/usecases/accept_invite_usecase.dart';
import '../controllers/accept_invite_controller.dart';
import '../pages/accept_invite_page.dart';

/// Rota PÚBLICA '/aceitar-convite' (sem sessão) — excluída do guard de
/// autenticação em `tenantAuthRedirectTarget`.
final class AcceptInviteRoute extends GetItModule {
  @override
  String get path => '/aceitar-convite';

  @override
  Widget get page => const AcceptInvitePage();

  @override
  void binds(Injector i) {
    i.controller<AcceptInviteController>(
      () => AcceptInviteController(acceptUsecase: inject<AcceptInviteUsecase>()),
    );
  }
}
