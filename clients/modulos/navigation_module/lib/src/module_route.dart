import 'package:get_it_module/get_it_module.dart';
import 'package:go_router/go_router.dart';

/// Converte uma rota [GetItModule] em uma [GoRoute].
extension ModuleRoute on GetItModule {
  /// Usa o `path`/`name` declarados pela rota e constrói a casca de escopo
  /// de DI via [GetItModule.toRoute]. O escopo é criado ao entrar na rota e
  /// descartado ao sair (dispose do widget pelo go_router).
  GoRoute toGoRoute() =>
      GoRoute(path: path, name: name, builder: (context, state) => toRoute());
}
