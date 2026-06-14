import 'package:api_client/api_client.dart';
import 'package:app_config/app_config.dart';
import 'package:get_it_module/get_it_module.dart';
import 'package:navigation_module/navigation_module.dart';

import 'no_op/auth_service_no_op.dart';
import 'no_op/local_storage_service_no_op.dart';
import 'no_op/session_service_impl.dart';
import 'services/auth_service.dart';
import 'services/local_storage_service.dart';
import 'services/session_service.dart';

/// Módulo de infraestrutura: serviços de vida longa + tarefas de boot.
///
/// Deve ser o primeiro na lista de módulos compostos pelo app.
/// Depende de packages/módulos diretamente — nunca de `dependencies_module`
/// (evita ciclo: dependencies_module reexporta core_module).
final class InfraModule extends AppModule {
  final AppConfig config;
  InfraModule(this.config);

  @override
  void globalBinds(Injector i) {
    i.singleton<AppConfig>(config);
    i.singleton<BootState>(BootState());
    i.singleton<SessionService>(SessionServiceImpl());
    i.lazySingleton<LocalStorageService>(() => LocalStorageServiceNoOp());
    i.lazySingleton<AuthService>(() => AuthServiceNoOp());
    i.lazySingleton<ApiClient>(() => ApiClientStub(config: config));
  }

  @override
  List<BootTask> bootTasks() => [
    BootTask(BootStage.infra, () => inject<LocalStorageService>().init()),
    BootTask(BootStage.infra, () => inject<ApiClient>().connect()),
    BootTask(BootStage.session, () => inject<AuthService>().checkCurrentUser()),
  ];
}
