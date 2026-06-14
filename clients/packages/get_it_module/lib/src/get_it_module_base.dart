import 'package:flutter/widgets.dart';

import 'get_it_module_scope.dart';
import 'injector.dart';

/// Contrato de uma **rota** (uma tela/fluxo) com escopo de DI próprio.
///
/// É a unidade de UI exposta por um [AppModule] em `routes()`. Descreve:
///  - [path]/[name]: a URL da rota (consumida pelo roteador);
///  - [page]: a tela raiz exibida quando a rota é aberta;
///  - [binds]: as dependências exclusivas desta tela, registradas em um escopo
///    isolado e descartadas quando a tela é fechada.
///
/// Serviços compartilhados NÃO entram aqui — eles são features de serviço,
/// expostas via [AppModule.globalBinds] no escopo global, e resolvidas via
/// [inject] (o escopo da rota fica acima do escopo-base).
abstract base class GetItModule {
  /// Caminho/URL desta rota (ex.: '/login', '/tenants').
  String get path;

  /// Nome opcional da rota, para navegação por nome (go_router named routes).
  String? get name => null;

  /// Tela raiz do módulo.
  Widget get page;

  /// Registra as dependências exclusivas da feature no escopo do módulo.
  ///
  /// Chamado uma única vez ao abrir o módulo. Tudo o que for criado aqui é
  /// descartado quando o módulo é fechado (pop da rota).
  void binds(Injector i);

  /// Resolve o módulo em um widget pronto para navegação, com o ciclo de vida
  /// do escopo do GetIt atrelado ao ciclo de vida da tela.
  Widget toRoute() => GetItModuleScope(module: this);
}
