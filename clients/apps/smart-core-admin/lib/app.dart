import 'package:dependencies_module/dependencies_module.dart';

// Gerado por `flutter gen-l10n` a partir de lib/l10n/app_pt.arb.
import 'l10n/app_localizations.dart';

/// Widget raiz do Smart Core Admin.
///
/// Monta o GoRouter a partir dos módulos compostos no bootstrap e aplica
/// o tema + i18n. O redirect mantém tudo na splash '/' até o boot concluir.
class SmartCoreAdminApp extends StatelessWidget {
  final List<AppModule> modules;

  const SmartCoreAdminApp({super.key, required this.modules});

  // Rota placeholder para a tela pós-boot (substituída pelo login_module em fase futura).
  static final _readyRoute = GoRoute(
    path: '/ready',
    builder: (_, _) => const Scaffold(
      body: Center(child: Text('Boot concluído — aguardando login_module')),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final router = AppRouter(
      initialLocation: '/',
      routes: collectRoutes(modules),
      extraRoutes: [_readyRoute],
      refreshListenable: inject<BootState>(),
      redirect: _bootRedirect,
    ).build();

    return MaterialApp.router(
      title: 'Smart Core Admin',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('pt'),
    );
  }

  /// Guard de boot: mantém tudo na splash '/' até BootState.value = true.
  /// Guard de auth real entrará com o login_module em fase futura.
  static String? _bootRedirect(BuildContext context, GoRouterState state) {
    final booted = inject<BootState>().value;
    if (!booted) {
      return state.matchedLocation == '/' ? null : '/';
    }
    // Após boot: placeholder (sem login real nesta base)
    if (state.matchedLocation == '/') return '/ready';
    return null;
  }
}
