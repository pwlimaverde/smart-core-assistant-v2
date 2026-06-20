import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/usecases/list_tenants_usecase.dart';
import '../../domain/usecases/test_evolution_connection_usecase.dart';
import '../controllers/evolution_controller.dart';
import '../pages/evolution_page.dart';

final class EvolutionRoute extends GetItModule {
  @override
  String get path => '/admin/evolution';

  @override
  Widget get page => const EvolutionPage();

  @override
  void binds(Injector i) {
    i.controller<EvolutionController>(
      () => EvolutionController(
        listTenantsUsecase: inject<ListTenantsUsecase>(),
        testConnectionUsecase: inject<TestEvolutionConnectionUsecase>(),
      ),
    );
  }
}
