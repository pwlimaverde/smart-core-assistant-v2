import 'package:dependencies_module/dependencies_module.dart';

import '../../../equipe/domain/usecases/equipe_usecases.dart';
import '../../domain/usecases/fluxos_usecases.dart';
import '../controllers/fluxos_controllers.dart';
import '../pages/etapas_fluxo_page.dart';
import '../pages/fluxos_page.dart';

/// Fluxos de atendimento — rota administrativa do tenant.
final class FluxosRoute extends GetItModule {
  @override
  String get path => '/tenant/fluxos';

  @override
  Widget get page => const FluxosPage();

  @override
  void binds(Injector i) {
    i.controller<FluxosController>(
      () => FluxosController(
        listar: inject<ListarFluxosUsecase>(),
        criar: inject<CriarFluxoUsecase>(),
        atualizar: inject<AtualizarFluxoUsecase>(),
        desativar: inject<DesativarFluxoUsecase>(),
        equipe: inject<CarregarEquipeUsecase>(),
      ),
    );
  }
}

/// Colunas de um fluxo. Rota própria, e não painel lateral: a lista de fluxos
/// e a de colunas são listas longas, e espremer as duas numa tela só sacrifica
/// as duas em janela estreita.
final class EtapasFluxoRoute extends GetItModule {
  @override
  String get path => '/tenant/fluxos/:id/etapas';

  @override
  Widget get page => const _EtapasFluxoDaRota();

  @override
  void binds(Injector i) {
    i.controller<EtapasFluxoController>(
      () => EtapasFluxoController(
        listar: inject<ListarEtapasUsecase>(),
        criar: inject<CriarEtapaUsecase>(),
        atualizar: inject<AtualizarEtapaUsecase>(),
        desativar: inject<DesativarEtapaUsecase>(),
        mover: inject<MoverEtapaUsecase>(),
      ),
    );
  }
}

/// Lê o `:id` do caminho e entrega à página.
///
/// O `page` do `GetItModule` é um getter sem `BuildContext`, então o parâmetro
/// da rota só pode ser lido aqui dentro. A página continua recebendo o id por
/// construtor — o que a mantém montável num teste sem roteador.
class _EtapasFluxoDaRota extends StatelessWidget {
  const _EtapasFluxoDaRota();

  @override
  Widget build(BuildContext context) {
    final bruto = GoRouterState.of(context).pathParameters['id'];
    return EtapasFluxoPage(fluxoId: int.tryParse(bruto ?? '') ?? 0);
  }
}
