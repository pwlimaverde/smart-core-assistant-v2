import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/usecases/pagamento_usecases.dart';
import '../controllers/pagamento_controller.dart';
import '../pages/pagamento_page.dart';

/// Rota '/conta/pagamento' — quitar a assinatura já logado.
///
/// **Fora de `/tenant/`** de propósito: aquele prefixo é de administração do
/// tenant (equipe, fluxos, configuração), e cobrança é assunto da *conta*. O
/// RBAC não muda — o guard exige `tenant:admin` nas duas —, mas a separação
/// mantém honesto o significado do prefixo.
final class PagamentoRoute extends GetItModule {
  @override
  String get path => '/conta/pagamento';

  @override
  Widget get page => const PagamentoPage();

  @override
  void binds(Injector i) {
    i.controller<PagamentoController>(
      () => PagamentoController(quitar: inject<QuitarAssinaturaUsecase>()),
    );
  }
}
