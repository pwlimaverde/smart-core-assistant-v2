import 'package:dependencies_module/dependencies_module.dart';

import '../controllers/tenants_controller.dart';
import '../pages/tenants_page.dart';
import '../../domain/usecases/tenants_usecases.dart';

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
