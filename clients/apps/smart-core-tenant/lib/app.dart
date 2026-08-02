import 'dart:async';

import 'package:dependencies_module/dependencies_module.dart';
import 'package:login_module/login_module.dart' as login;
import 'package:onboarding_module/onboarding_module.dart'
    show PortaoConfiguracao;

import 'auth_redirect.dart';

// Gerado por `flutter gen-l10n` a partir de lib/l10n/app_pt.arb.
import 'l10n/app_localizations.dart';

/// Widget raiz do Smart Core Tenant.
///
/// Monta o GoRouter a partir dos módulos compostos no bootstrap (workspace
/// operacional + painel administrativo do tenant) e aplica o tema + i18n. O
/// redirect aplica o guard de boot + autenticação de sessão de tenant.
class SmartCoreTenantApp extends StatelessWidget {
  final List<AppModule> modules;

  const SmartCoreTenantApp({super.key, required this.modules});

  @override
  Widget build(BuildContext context) {
    final router = AppRouter(
      initialLocation: '/',
      routes: collectRoutes(modules),
      // Reavalia o guard quando o boot conclui OU a autenticação muda.
      // O portão entra aqui porque o guard depende dele: quando a consulta do
      // progresso responde, a rota precisa ser reavaliada.
      refreshListenable: Listenable.merge([
        inject<BootState>(),
        inject<login.AuthService>().authChanges,
        inject<PortaoConfiguracao>(),
      ]),
      redirect: _authRedirect,
    ).build();

    return MaterialApp.router(
      title: 'Smart Core Tenant',
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

  /// Guard de boot + autenticação + persona de tenant (resolve a partir do
  /// estado injetado).
  static String? _authRedirect(BuildContext context, GoRouterState state) {
    final auth = inject<login.AuthService>();
    final portao = inject<PortaoConfiguracao>();
    final ehTenant = auth.isAuthenticated &&
        !(auth.currentSession?.isSuperuser ?? false);

    // Dispara a consulta do progresso na primeira navegação com sessão de
    // tenant; o `PortaoConfiguracao` ignora chamadas repetidas e notifica o
    // router quando a resposta chega. Sem sessão, esquece o que sabia — a
    // próxima pode ser de outro tenant.
    if (ehTenant) {
      unawaited(portao.avaliar());
    } else if (portao.pendente != null) {
      portao.limpar();
    }

    return tenantAuthRedirectTarget(
      booted: inject<BootState>().value,
      isAuthenticated: auth.isAuthenticated,
      isSuperuser: auth.currentSession?.isSuperuser ?? false,
      scopes: auth.currentSession?.scopes ?? const [],
      location: state.matchedLocation,
      onboardingPendente: portao.pendente,
      onboardingPasso: portao.passo,
    );
  }
}
