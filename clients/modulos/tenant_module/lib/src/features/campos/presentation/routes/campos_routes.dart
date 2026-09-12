import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/usecases/campos_usecases.dart';
import '../controllers/campos_controller.dart';
import '../pages/campos_page.dart';

/// Campos do cartão de atendimento — rota administrativa do tenant (N9 E13).
final class CamposRoute extends GetItModule {
  @override
  String get path => '/tenant/campos';

  @override
  Widget get page => const CamposPage();

  @override
  void binds(Injector i) {
    i.controller<CamposController>(
      () => CamposController(
        listar: inject<ListarCamposUsecase>(),
        criar: inject<CriarCampoUsecase>(),
        atualizar: inject<AtualizarCampoUsecase>(),
        desativar: inject<DesativarCampoUsecase>(),
      ),
    );
  }
}
