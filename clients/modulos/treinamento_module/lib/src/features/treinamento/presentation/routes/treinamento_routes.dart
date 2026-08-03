import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/usecases/treinamento_usecases.dart';
import '../controllers/treinamento_controllers.dart';
import '../pages/treinamento_page.dart';

/// Rota do treinamento da IA.
///
/// Sob `/tenant/`, como as demais rotas administrativas do tenant: o guard do
/// app exige `tenant:admin` para esse prefixo, e treinar o assistente muda o
/// que ele responde a todos os clientes — não é ação de atendente.
final class TreinamentoRoute extends GetItModule {
  @override
  String get path => '/tenant/treinamento';

  @override
  Widget get page => const TreinamentoPage();

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
  }
}
