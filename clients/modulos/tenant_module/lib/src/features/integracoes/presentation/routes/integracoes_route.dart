import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/usecases/integracoes_usecases.dart';
import '../controllers/atividade_controller.dart';
import '../controllers/integracoes_controller.dart';
import '../pages/integracoes_page.dart';

/// Rota '/tenant/integracoes' — aplicativos de IA conectados por OAuth (N13.8).
///
/// Sem RBAC de UI próprio, ao contrário das telas de convite e de usuários: o
/// recurso é **do próprio usuário**, e qualquer pessoa com sessão válida pode ver
/// e desconectar os aplicativos que ela mesma conectou. Restringir a
/// `tenant:admin` deixaria um `staff` sem meio de cortar um agente que ele
/// próprio autorizou — o oposto do que a tela existe para permitir.
final class IntegracoesRoute extends GetItModule {
  @override
  String get path => '/tenant/integracoes';

  @override
  Widget get page => const IntegracoesPage();

  @override
  void binds(Injector i) {
    i.controller<IntegracoesController>(
      () => IntegracoesController(
        listUsecase: inject<ListMcpGrantsUsecase>(),
        revokeUsecase: inject<RevokeMcpGrantUsecase>(),
        ajustarUsecase: inject<AjustarEscoposMcpGrantUsecase>(),
      ),
    );
    // B3 — aba "Atividade".
    i.controller<AtividadeController>(
      () => AtividadeController(listar: inject<ListarAtividadeUsecase>()),
    );
  }
}
