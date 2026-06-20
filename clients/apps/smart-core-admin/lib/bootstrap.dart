import 'package:dependencies_module/dependencies_module.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:initial_loading_module/initial_loading_module.dart';
import 'package:login_module/login_module.dart';
import 'package:admin_module/admin_module.dart';

import 'app.dart';

/// Compõe os módulos, registra os serviços globais e sobe o app.
///
/// Chamado pelos entrypoints flavor-específicos (main_dev / main_prod).
/// O boot assíncrono (runBootTasks) roda DENTRO da rota '/', não aqui.
Future<void> bootstrap(AppConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Path URL strategy: URLs limpas sob /v2/admin/ (sem '#'); combina com
  // --base-href /v2/admin/ e o SPA fallback (try_files) do Caddy. Sem isso,
  // refresh/deep-link em /v2/admin/login retornaria 404.
  usePathUrlStrategy();

  // Ordem importa: InfraModule primeiro (registra SessionService/ApiClient);
  // LoginModule depois (registra AuthService/LocalStorageService reais).
  final modules = <AppModule>[
    InfraModule(config),
    LoginModule(),
    AdminModule(),
    InitialLoadingModule(),
  ];

  // Registro síncrono dos serviços globais no escopo-base.
  installModules(modules);
  // Disponibiliza a lista de módulos ao splash (InitialLoadingRoute).
  GetIt.instance.registerSingleton<List<AppModule>>(modules);

  runApp(SmartCoreAdminApp(modules: modules));
}
