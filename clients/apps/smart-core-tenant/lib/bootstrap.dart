import 'package:dependencies_module/dependencies_module.dart';
import 'package:initial_loading_module/initial_loading_module.dart';
import 'package:login_module/login_module.dart';
import 'package:onboarding_module/onboarding_module.dart';
import 'package:operacional_module/operacional_module.dart';
import 'package:tenant_module/tenant_module.dart';

import 'app.dart';
import 'platform/url_strategy.dart';

/// Compõe os módulos, registra os serviços globais e sobe o app.
///
/// Chamado pelos entrypoints flavor-específicos (main_dev / main_prod).
/// O boot assíncrono (runBootTasks) roda DENTRO da rota '/', não aqui.
///
/// Este app é exclusivo de sessões de TENANT (donos/funcionários) — o painel
/// do superusuário da plataforma é o `smart-core-admin`, que não hospeda mais
/// o `OperacionalModule` (movido para cá, já que o workspace é dos
/// funcionários do tenant, não do superusuário).
Future<void> bootstrap(AppConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Path URL strategy: URLs limpas sob /v2/tenant/ (sem '#'); combina com
  // --base-href /v2/tenant/ e o SPA fallback (try_files) do Caddy. Sem isso,
  // refresh/deep-link em /v2/tenant/login retornaria 404. Só faz sentido na
  // Web — no desktop (Windows) é no-op (import condicional).
  usePlatformUrlStrategy();

  // Ordem importa: InfraModule primeiro (registra SessionService/ApiClient);
  // LoginModule depois (registra AuthService/LocalStorageService reais).
  final modules = <AppModule>[
    InfraModule(config),
    LoginModule(),
    // Depois do LoginModule: o passo final do wizard entra na conta pelo
    // `AuthService` que aquele módulo registra.
    OnboardingModule(),
    OperacionalModule(),
    TenantModule(),
    InitialLoadingModule(),
  ];

  // Registro síncrono dos serviços globais no escopo-base.
  installModules(modules);
  // Disponibiliza a lista de módulos ao splash (InitialLoadingRoute).
  GetIt.instance.registerSingleton<List<AppModule>>(modules);

  runApp(SmartCoreTenantApp(modules: modules));
}
