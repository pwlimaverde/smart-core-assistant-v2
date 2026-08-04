import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/usecases/equipe_usecases.dart';
import '../controllers/equipe_controllers.dart';
import '../pages/equipe_page.dart';

/// Departamentos e atendentes — rota administrativa do tenant.
final class EquipeRoute extends GetItModule {
  @override
  String get path => '/tenant/equipe';

  @override
  Widget get page => const EquipePage();

  @override
  void binds(Injector i) {
    i.controller<EquipeController>(
      () => EquipeController(
        carregar: inject<CarregarEquipeUsecase>(),
        criar: inject<CriarDepartamentoUsecase>(),
        atualizar: inject<AtualizarDepartamentoUsecase>(),
        desativar: inject<DesativarDepartamentoUsecase>(),
      ),
    );
  }
}
