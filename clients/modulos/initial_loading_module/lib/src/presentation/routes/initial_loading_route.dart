import 'package:dependencies_module/dependencies_module.dart';

import '../controllers/initial_loading_controller.dart';
import '../pages/initial_loading_page.dart';

/// Rota da splash '/' — registra o controller e expõe a página.
final class InitialLoadingRoute extends GetItModule {
  @override
  String get path => '/';

  @override
  Widget get page => const InitialLoadingPage();

  @override
  void binds(Injector i) {
    i.controller<InitialLoadingController>(
      () => InitialLoadingController(
        modules: inject<List<AppModule>>(),
        bootState: inject<BootState>(),
      ),
    );
  }
}
