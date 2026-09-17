import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/usecases/ignorados_usecases.dart';
import '../controllers/ignorados_controller.dart';
import '../pages/ignorados_page.dart';

/// Os números ignorados — rota administrativa do tenant.
final class IgnoradosRoute extends GetItModule {
  @override
  String get path => '/tenant/ignorados';

  @override
  Widget get page => const IgnoradosPage();

  @override
  void binds(Injector i) {
    i.controller<IgnoradosController>(
      () => IgnoradosController(
        listar: inject<ListarIgnoradosUsecase>(),
        criar: inject<CriarIgnoradoUsecase>(),
        atualizar: inject<AtualizarIgnoradoUsecase>(),
        remover: inject<RemoverIgnoradoUsecase>(),
      ),
    );
  }
}
