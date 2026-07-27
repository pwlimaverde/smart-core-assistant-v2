import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/usecases/usuarios_usecases.dart';
import '../controllers/tenant_users_controller.dart';
import '../pages/tenant_users_page.dart';

/// Rota '/tenant/usuarios' — gestão de usuários e `flow_permissions` (N3.2).
final class TenantUsersRoute extends GetItModule {
  @override
  String get path => '/tenant/usuarios';

  @override
  Widget get page => const TenantUsersPage();

  @override
  void binds(Injector i) {
    i.controller<TenantUsersController>(
      () => TenantUsersController(
        listUsecase: inject<ListTenantUsersUsecase>(),
        updateUsecase: inject<UpdateTenantUserUsecase>(),
      ),
    );
  }
}
