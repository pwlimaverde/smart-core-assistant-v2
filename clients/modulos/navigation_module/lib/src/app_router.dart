import 'package:flutter/foundation.dart';
import 'package:get_it_module/get_it_module.dart';
import 'package:go_router/go_router.dart';

import 'module_route.dart';

/// Monta o [GoRouter] central a partir das rotas agregadas dos módulos.
///
/// O app passa `routes: collectRoutes(modules)` (a lista achatada das `routes()`
/// de todos os [AppModule]), a rota inicial e, opcionalmente, um [redirect]
/// para guards de autenticação/boot e rotas avulsas (`extraRoutes`).
///
/// O [refreshListenable] reavalia o `redirect` quando seu valor muda — usado
/// pela barreira de boot ([BootState]) e por mudanças de sessão.
final class AppRouter {
  final List<GetItModule> routes;
  final String initialLocation;
  final List<GoRoute> extraRoutes;
  final GoRouterRedirect? redirect;
  final Listenable? refreshListenable;

  AppRouter({
    required this.routes,
    required this.initialLocation,
    this.extraRoutes = const [],
    this.redirect,
    this.refreshListenable,
  });

  GoRouter build() => GoRouter(
    initialLocation: initialLocation,
    redirect: redirect,
    refreshListenable: refreshListenable,
    routes: [...routes.map((r) => r.toGoRoute()), ...extraRoutes],
  );
}
