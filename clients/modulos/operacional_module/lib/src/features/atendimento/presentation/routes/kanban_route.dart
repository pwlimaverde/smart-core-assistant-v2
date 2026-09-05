import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/streams/atendimento_evento_stream.dart';
import '../../domain/usecases/atendimento_usecases.dart';
import '../controllers/kanban_controller.dart';
import '../pages/kanban_page.dart';

/// Rota '/atendimentos' — o quadro de atendimento.
final class KanbanRoute extends GetItModule {
  /// Menu lateral do app que monta esta rota.
  ///
  /// Um builder, e não um widget pronto: o menu lê a rota atual do
  /// `GoRouterState` para marcar onde a pessoa está, e um widget construído no
  /// boot não teria esse contexto.
  final Widget Function()? drawerBuilder;

  /// Faixa de aviso acima do quadro (ver `KanbanPage.aviso`). Builder pelo mesmo
  /// motivo do menu: o widget precisa do contexto da rota, não do boot.
  final Widget Function()? avisoBuilder;

  KanbanRoute({this.drawerBuilder, this.avisoBuilder});

  @override
  String get path => '/atendimentos';

  @override
  Widget get page =>
      KanbanPage(drawer: drawerBuilder?.call(), aviso: avisoBuilder?.call());

  @override
  void binds(Injector i) {
    i.controller<KanbanController>(
      () => KanbanController(
        listUsecase: inject<ListAtendimentosUsecase>(),
        moveUsecase: inject<MoveAtendimentoEtapaUsecase>(),
        fluxosUsecase: inject<ListFluxosUsecase>(),
        colunasUsecase: inject<ListColunasUsecase>(),
        statusUsecase: inject<SetAtendimentoStatusUsecase>(),
        eventos: inject<AtendimentoEventoStream>(),
      ),
    );
  }
}
