import 'package:dependencies_module/dependencies_module.dart';
import 'package:login_module/login_module.dart' as login;

import '../../domain/services/cadastro_sessao.dart';
import '../../domain/usecases/cadastro_usecases.dart';
import '../controllers/cadastro_controllers.dart';
import '../pages/cadastro_dados_page.dart';
import '../pages/cadastro_pagamento_page.dart';
import '../pages/cadastro_plano_page.dart';
import '../pages/cadastro_pronto_page.dart';

/// As quatro rotas do wizard. Todas públicas — o guard do app libera o prefixo
/// `/cadastro`. Cada uma registra só o controller do seu passo; o estado que
/// atravessa as telas vive no [CadastroSessao] global.

final class CadastroDadosRoute extends GetItModule {
  @override
  String get path => '/cadastro';

  @override
  Widget get page => const CadastroDadosPage();

  @override
  void binds(Injector i) {
    i.controller<DadosController>(
      () => DadosController(
        iniciar: inject<IniciarCadastroUsecase>(),
        verificarSlug: inject<VerificarSlugUsecase>(),
        sessao: inject<CadastroSessao>(),
      ),
    );
  }
}

final class CadastroPlanoRoute extends GetItModule {
  @override
  String get path => '/cadastro/plano';

  @override
  Widget get page => const CadastroPlanoPage();

  @override
  void binds(Injector i) {
    i.controller<PlanoController>(
      () => PlanoController(
        listar: inject<ListarPlanosUsecase>(),
        selecionar: inject<SelecionarPlanoUsecase>(),
        sessao: inject<CadastroSessao>(),
      ),
    );
  }
}

final class CadastroPagamentoRoute extends GetItModule {
  @override
  String get path => '/cadastro/pagamento';

  @override
  Widget get page => const CadastroPagamentoPage();

  @override
  void binds(Injector i) {
    i.controller<PagamentoController>(
      () => PagamentoController(
        listar: inject<ListarProvedoresUsecase>(),
        confirmar: inject<ConfirmarPagamentoUsecase>(),
        sessao: inject<CadastroSessao>(),
      ),
    );
  }
}

final class CadastroProntoRoute extends GetItModule {
  @override
  String get path => '/cadastro/pronto';

  @override
  Widget get page => const CadastroProntoPage();

  @override
  void binds(Injector i) {
    i.controller<ConclusaoController>(
      () => ConclusaoController(
        status: inject<StatusCadastroUsecase>(),
        sessao: inject<CadastroSessao>(),
        auth: inject<login.AuthService>(),
      ),
    );
  }
}
