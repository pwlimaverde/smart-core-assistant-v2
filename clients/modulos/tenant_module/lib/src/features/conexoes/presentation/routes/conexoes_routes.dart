import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/usecases/conexoes_usecases.dart';
import '../controllers/conexoes_controllers.dart';
import '../pages/conexoes_page.dart';

/// Gestão das conexões de WhatsApp — rota administrativa do tenant.
final class ConexoesRoute extends GetItModule {
  @override
  String get path => '/tenant/conexoes';

  @override
  Widget get page => const ConexoesPage();

  @override
  void binds(Injector i) {
    i.controller<ConexoesController>(
      () => ConexoesController(
        listar: inject<ListarConexoesUsecase>(),
        reconectar: inject<ReconectarConexaoUsecase>(),
        remover: inject<RemoverConexaoUsecase>(),
        criar: inject<CriarConexaoUsecase>(),
        pareamento: inject<EstadoPareamentoUsecase>(),
        respostaBot: inject<DefinirRespostaBotUsecase>(),
        // P7 — só existem onde o módulo inteiro está registrado; o quadro
        // embute o controller só para a faixa de aviso de conexão caída.
        desconectar: inject<DesconectarConexaoUsecase>(),
        definirDepartamento: inject<DefinirDepartamentoDaConexaoUsecase>(),
        detalhe: inject<DetalheDaConexaoUsecase>(),
      ),
    );
  }
}
