import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/usecases/contatos_usecases.dart';
import '../controllers/contatos_controllers.dart';
import '../pages/contatos_page.dart';

/// Contatos — rota administrativa do tenant.
final class ContatosRoute extends GetItModule {
  @override
  String get path => '/tenant/contatos';

  @override
  Widget get page => const ContatosPage();

  @override
  void binds(Injector i) {
    i.controller<ContatosController>(
      () => ContatosController(listar: inject<ListarContatosUsecase>()),
    );
  }
}
