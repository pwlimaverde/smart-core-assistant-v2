import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/usecases/convites_usecases.dart';
import '../controllers/invites_controller.dart';
import '../pages/invites_page.dart';

/// Rota '/tenant/convites' — gerar/listar/revogar convites (N3.1). RBAC de UI
/// (escopo `tenant:admin`) aplicado no guard global do app
/// (`tenantAuthRedirectTarget`, prefixo `/tenant/`).
final class InvitesRoute extends GetItModule {
  @override
  String get path => '/tenant/convites';

  @override
  Widget get page => const InvitesPage();

  @override
  void binds(Injector i) {
    i.controller<InvitesController>(
      () => InvitesController(
        listUsecase: inject<ListInvitesUsecase>(),
        createUsecase: inject<CreateInviteUsecase>(),
        revokeUsecase: inject<RevokeInviteUsecase>(),
      ),
    );
  }
}
