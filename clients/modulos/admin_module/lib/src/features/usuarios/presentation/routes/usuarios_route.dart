import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/usecases/usuarios_usecases.dart';
import '../controllers/usuarios_controller.dart';
import '../pages/usuarios_page.dart';

final class UsuariosRoute extends GetItModule {
  @override
  String get path => '/admin/usuarios';

  @override
  Widget get page => const UsuariosPage();

  @override
  void binds(Injector i) {
    i.controller<UsuariosController>(
      () => UsuariosController(
        listar: inject<ListarUsuariosUsecase>(),
        definirAtivo: inject<DefinirUsuarioAtivoUsecase>(),
        migrar: GetIt.instance.isRegistered<MigrarEscoposUsecase>()
            ? inject<MigrarEscoposUsecase>()
            : null,
      ),
    );
  }
}
