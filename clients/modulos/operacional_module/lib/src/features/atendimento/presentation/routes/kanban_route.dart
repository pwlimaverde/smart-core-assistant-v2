import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/streams/atendimento_evento_stream.dart';
import '../../domain/usecases/atendimento_usecases.dart';
import '../controllers/kanban_controller.dart';
import '../pages/kanban_page.dart';

/// Rota '/atendimentos' — fila/Kanban por departamento (WS-6.2/6.4).
final class KanbanRoute extends GetItModule {
  @override
  String get path => '/atendimentos';

  @override
  Widget get page => const KanbanPage();

  @override
  void binds(Injector i) {
    i.controller<KanbanController>(
      () => KanbanController(
        listUsecase: inject<ListAtendimentosUsecase>(),
        moveUsecase: inject<MoveAtendimentoEtapaUsecase>(),
        eventos: inject<AtendimentoEventoStream>(),
      ),
    );
  }
}
