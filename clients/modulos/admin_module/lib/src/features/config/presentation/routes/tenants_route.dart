import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/usecases/list_tenants_usecase.dart';
import '../../domain/usecases/create_tenant_usecase.dart';
import '../../domain/usecases/update_tenant_usecase.dart';
import '../../domain/usecases/set_tenant_active_usecase.dart';
import '../../domain/usecases/generate_access_code_usecase.dart';
import '../controllers/tenants_controller.dart';
import '../pages/tenants_page.dart';

final class TenantsRoute extends GetItModule {
  @override
  String get path => '/admin/tenants';

  @override
  Widget get page => const TenantsPage();

  @override
  void binds(Injector i) {
    i.controller<TenantsController>(
      () => TenantsController(
        listUsecase: inject<ListTenantsUsecase>(),
        createUsecase: inject<CreateTenantUsecase>(),
        updateUsecase: inject<UpdateTenantUsecase>(),
        setActiveUsecase: inject<SetTenantActiveUsecase>(),
        generateAccessCodeUsecase: inject<GenerateAccessCodeUsecase>(),
      ),
    );
  }
}
