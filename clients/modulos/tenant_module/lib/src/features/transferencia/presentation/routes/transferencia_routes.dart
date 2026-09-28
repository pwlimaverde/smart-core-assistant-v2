import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/usecases/transferencia_usecases.dart';
import '../controllers/transferencia_controller.dart';
import '../pages/transferencia_page.dart';

/// "Transferência para atendente" — configuração do negócio (plano
/// ia-engine-jev).
final class TransferenciaRoute extends GetItModule {
  @override
  String get path => '/tenant/transferencia';

  @override
  Widget get page => const TransferenciaPage();

  @override
  void binds(Injector i) {
    i.controller<TransferenciaController>(
      () => TransferenciaController(
        carregar: inject<CarregarTransferenciaUsecase>(),
        salvar: inject<SalvarRegraUsecase>(),
        ativa: inject<DefinirRegraAtivaUsecase>(),
        sinais: inject<DefinirSinaisUsecase>(),
        testar: inject<TestarRegraUsecase>(),
        sugestoes: inject<GerarSugestoesUsecase>(),
      ),
    );
  }
}
