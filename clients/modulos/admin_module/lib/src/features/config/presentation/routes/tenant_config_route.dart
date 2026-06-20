import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/usecases/get_tenant_config_usecase.dart';
import '../../domain/usecases/update_tenant_config_usecase.dart';
import '../controllers/tenant_config_controller.dart';
import '../pages/tenant_config_page.dart';

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
