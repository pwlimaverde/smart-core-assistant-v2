import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/usecases/painel_usecases.dart';
import '../controllers/painel_controllers.dart';
import '../pages/painel_page.dart';

/// Painel do tenant — a primeira tela depois do login.
final class PainelRoute extends GetItModule {
  @override
  String get path => '/tenant/painel';

  @override
  Widget get page => const PainelPage();

  @override
  void binds(Injector i) {
    i.controller<PainelController>(
      () => PainelController(carregar: inject<CarregarPainelUsecase>()),
    );
  }
}
