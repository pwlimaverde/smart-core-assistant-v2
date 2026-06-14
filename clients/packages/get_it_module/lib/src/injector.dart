import 'package:get_it/get_it.dart';

/// Fachada de registro de dependências sobre o GetIt.
///
/// Padroniza os três modos de provisão com semântica explícita, escondendo a
/// API crua do GetIt dos módulos. É instanciada internamente pelo package e
/// entregue ao módulo no momento dos `binds`; módulos nunca a criam à mão.
final class Injector {
  final GetIt _getIt;

  Injector(this._getIt);

  /// Nova instância a cada resolução. Não há descarte automático.
  void factory<T extends Object>(T Function() create) {
    _getIt.registerFactory<T>(create);
  }

  /// Instância única criada sob demanda (na primeira resolução).
  ///
  /// [dispose] é chamado quando o escopo dono é descartado — use-o para fechar
  /// Cubits (`dispose: (c) => c.close()`) e liberar recursos.
  void lazySingleton<T extends Object>(
    T Function() create, {
    void Function(T instance)? dispose,
  }) {
    _getIt.registerLazySingleton<T>(create, dispose: dispose);
  }

  /// Instância única criada imediatamente no registro.
  ///
  /// [dispose] é chamado quando o escopo dono é descartado.
  void singleton<T extends Object>(
    T instance, {
    void Function(T instance)? dispose,
  }) {
    _getIt.registerSingleton<T>(instance, dispose: dispose);
  }
}
