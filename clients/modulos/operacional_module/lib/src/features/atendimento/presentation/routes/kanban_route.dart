import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/model/contato_para_atendimento.dart';
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

  /// C3 — ver `KanbanPage.buscarContatos`.
  final BuscarContatos? buscarContatos;

  /// B5 — ver `KanbanController.usuarioAtual`.
  final int? Function()? usuarioAtual;

  KanbanRoute({
    this.drawerBuilder,
    this.avisoBuilder,
    this.buscarContatos,
    this.usuarioAtual,
  });

  @override
  String get path => '/atendimentos';

  @override
  Widget get page => KanbanPage(
    drawer: drawerBuilder?.call(),
    aviso: avisoBuilder?.call(),
    buscarContatos: buscarContatos,
  );

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
        usuarioAtual: usuarioAtual,
        // P4 — as ações do supervisor. Opcionais na rota pelo mesmo motivo do
        // controller: um app que não registrou o módulo inteiro ainda abre o
        // quadro, só sem o menu completo.
        atribuirUsecase: _seRegistrado<AtribuirAtendimentoUsecase>(),
        prioridadeUsecase: _seRegistrado<DefinirPrioridadeUsecase>(),
        transferirUsecase: _seRegistrado<TransferirParaFluxoUsecase>(),
        exportarUsecase: _seRegistrado<ExportarQuadroUsecase>(),
        revisadoUsecase: _seRegistrado<MarcarRevisadoUsecase>(),
      ),
    );
  }
}

/// Só injeta o que o app registrou — `inject` de um tipo ausente lança.
T? _seRegistrado<T extends Object>() =>
    GetIt.instance.isRegistered<T>() ? inject<T>() : null;
