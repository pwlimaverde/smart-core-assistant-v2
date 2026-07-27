import 'package:dependencies_module/dependencies_module.dart';

import '../controllers/evolution_controller.dart';
import '../pages/evolution_page.dart';
import '../../domain/usecases/evolution_usecases.dart';
import '../../../tenants/domain/usecases/tenants_usecases.dart';

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
