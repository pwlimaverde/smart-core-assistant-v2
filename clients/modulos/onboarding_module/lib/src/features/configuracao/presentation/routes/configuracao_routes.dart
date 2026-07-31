import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/usecases/configuracao_usecases.dart';
import '../controllers/configuracao_controllers.dart';
import '../pages/assistente_page.dart';
import '../pages/configuracao_pronta_page.dart';
import '../pages/conexao_whatsapp_page.dart';
import '../pages/departamento_page.dart';

/// As quatro rotas da configuração inicial.
///
/// Diferente das do cadastro, estas exigem **sessão** — o tenant já entrou. O
/// guard as trata como rota autenticada comum.

final class ConexaoWhatsappRoute extends GetItModule {
  @override
  String get path => '/configuracao/whatsapp';

  @override
  Widget get page => const ConexaoWhatsappPage();

  @override
  void binds(Injector i) {
    i.controller<ConexaoController>(
      () => ConexaoController(
        criar: inject<CriarConexaoUsecase>(),
        estado: inject<EstadoConexaoUsecase>(),
        progresso: inject<ProgressoUsecase>(),
      ),
    );
  }
}

final class DepartamentoRoute extends GetItModule {
  @override
  String get path => '/configuracao/departamento';

  @override
  Widget get page => const DepartamentoPage();

  @override
  void binds(Injector i) {
    i.controller<DepartamentoController>(
      () => DepartamentoController(
        criar: inject<CriarDepartamentoUsecase>(),
        progresso: inject<ProgressoUsecase>(),
      ),
    );
  }
}

final class AssistenteRoute extends GetItModule {
  @override
  String get path => '/configuracao/assistente';

  @override
  Widget get page => const AssistentePage();

  @override
  void binds(Injector i) {
    i.controller<PersonaController>(
      () => PersonaController(
        definir: inject<DefinirPersonaUsecase>(),
        progresso: inject<ProgressoUsecase>(),
      ),
    );
  }
}

final class ConfiguracaoProntaRoute extends GetItModule {
  @override
  String get path => '/configuracao/pronto';

  @override
  Widget get page => const ConfiguracaoProntaPage();

  @override
  void binds(Injector i) {
    i.controller<ConclusaoConfiguracaoController>(
      () => ConclusaoConfiguracaoController(
        progresso: inject<ProgressoUsecase>(),
      ),
    );
  }
}
