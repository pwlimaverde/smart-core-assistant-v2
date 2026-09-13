import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/usecases/clientes_usecases.dart';
import '../controllers/clientes_controllers.dart';
import '../pages/clientes_page.dart';

/// B10 (N11 E5) — clientes do tenant.
final class ClientesRoute extends GetItModule {
  @override
  String get path => '/tenant/clientes';

  @override
  Widget get page => const ClientesPage();

  @override
  void binds(Injector i) {
    i.controller<ClientesController>(
      () => ClientesController(
        listar: inject<ListarClientesUsecase>(),
        salvar: inject<SalvarClienteUsecase>(),
        definirAtivo: inject<DefinirClienteAtivoUsecase>(),
        contatos: inject<ListarContatosDoClienteUsecase>(),
        vincular: inject<VincularContatoUsecase>(),
      ),
    );
  }
}
