import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/usecases/config_usecases.dart';
import '../controllers/tenant_own_config_controller.dart';
import '../pages/tenant_own_config_page.dart';

/// Rota '/tenant/config' — configuração do próprio tenant (N3.3).
final class TenantOwnConfigRoute extends GetItModule {
  @override
  String get path => '/tenant/config';

  @override
  Widget get page => const TenantOwnConfigPage();

  @override
  void binds(Injector i) {
    i.controller<TenantOwnConfigController>(
      () => TenantOwnConfigController(
        getUsecase: inject<GetMyTenantConfigUsecase>(),
        updateUsecase: inject<UpdateMyTenantConfigUsecase>(),
      ),
    );
  }
}
