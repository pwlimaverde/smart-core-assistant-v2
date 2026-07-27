import 'package:dependencies_module/dependencies_module.dart';

import '../controllers/tenant_config_controller.dart';
import '../pages/tenant_config_page.dart';
import '../../domain/usecases/tenant_config_usecases.dart';

final class TenantConfigRoute extends GetItModule {
  @override
  String get path => '/admin/tenant-config';

  @override
  Widget get page => const TenantConfigPage();

  @override
  void binds(Injector i) {
    i.controller<TenantConfigController>(
      () => TenantConfigController(
        getUsecase: inject<GetTenantConfigUsecase>(),
        updateUsecase: inject<UpdateTenantConfigUsecase>(),
      ),
    );
  }
}
