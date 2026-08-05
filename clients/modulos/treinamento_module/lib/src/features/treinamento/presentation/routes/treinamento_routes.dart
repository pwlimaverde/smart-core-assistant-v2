import 'package:dependencies_module/dependencies_module.dart';

import '../../../ensaio/domain/usecases/ensaio_usecases.dart';
import '../../../ensaio/presentation/controllers/ensaio_controllers.dart';
import '../../../intents/domain/usecases/intents_usecases.dart';
import '../../../intents/presentation/controllers/intents_controllers.dart';
import '../../domain/usecases/treinamento_usecases.dart';
import '../controllers/treinamento_controllers.dart';
import '../pages/treinamento_page.dart';

/// Rota do treinamento da IA.
///
/// Sob `/tenant/`, como as demais rotas administrativas do tenant: o guard do
/// app exige `tenant:admin` para esse prefixo, e treinar o assistente muda o
/// que ele responde a todos os clientes — não é ação de atendente.
final class TreinamentoRoute extends GetItModule {
  /// Menu lateral do app hospedeiro. Ver `OperacionalModule.drawerBuilder`: o
  /// menu mora no `tenant_module` e este módulo não pode depender dele.
  final Widget Function()? drawerBuilder;

  TreinamentoRoute({this.drawerBuilder});

  @override
  String get path => '/tenant/treinamento';

  @override
  Widget get page => TreinamentoPage(drawer: drawerBuilder?.call());

  @override
  void binds(Injector i) {
    i.controller<TreinamentoController>(
      () => TreinamentoController(
        listar: inject<ListarTreinamentosUsecase>(),
        criar: inject<CriarTreinamentoUsecase>(),
        finalizar: inject<FinalizarTreinamentoUsecase>(),
        remover: inject<RemoverTreinamentoUsecase>(),
      ),
    );
    i.controller<IntentsController>(
      () => IntentsController(
        listar: inject<ListarIntentsUsecase>(),
        criar: inject<CriarIntentUsecase>(),
        atualizar: inject<AtualizarIntentUsecase>(),
        remover: inject<RemoverIntentUsecase>(),
      ),
    );
    i.controller<EnsaioController>(
      () => EnsaioController(testar: inject<TestarPerguntaUsecase>()),
    );
  }
}
