import 'package:dependencies_module/dependencies_module.dart';
import 'package:login_module/login_module.dart' as login;

import 'auth_redirect.dart';

// Gerado por `flutter gen-l10n` a partir de lib/l10n/app_pt.arb.
import 'l10n/app_localizations.dart';

/// Widget raiz do Smart Core Admin.
///
/// Monta o GoRouter a partir dos módulos compostos no bootstrap e aplica
/// o tema + i18n. O redirect aplica o guard de boot + autenticação.
class SmartCoreAdminApp extends StatelessWidget {
  final List<AppModule> modules;

  const SmartCoreAdminApp({super.key, required this.modules});

  // Área autenticada placeholder (features de domínio entram em fases futuras).
  // Oferece logout para exercitar o fluxo completo até o guard redirecionar.
  static final _homeRoute = GoRoute(
    path: '/home',
    builder: (context, _) => AppScaffold(
      title: 'Smart Core Admin',
      actions: [
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Sair',
          onPressed: () => inject<login.AuthService>().logout(),
        ),
      ],
      body: const Center(child: Text('Autenticado.')),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final router = AppRouter(
      initialLocation: '/',
      routes: collectRoutes(modules),
      extraRoutes: [_homeRoute],
      // Reavalia o guard quando o boot conclui OU a autenticação muda.
      refreshListenable: Listenable.merge([
        inject<BootState>(),
        inject<login.AuthService>().authChanges,
      ]),
      redirect: _authRedirect,
    ).build();

    return MaterialApp.router(
      title: 'Smart Core Admin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light,
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('pt'),
    );
  }

  /// Guard de boot + autenticação + superusuário (resolve a partir do estado injetado).
  static String? _authRedirect(BuildContext context, GoRouterState state) {
    final auth = inject<login.AuthService>();
    return authRedirectTarget(
      booted: inject<BootState>().value,
      isAuthenticated: auth.isAuthenticated,
      isSuperuser: auth.currentSession?.isSuperuser ?? false,
      location: state.matchedLocation,
    );
  }
}
