import 'package:api_client/api_client.dart';
import 'package:app_config/app_config.dart';
import 'package:get_it_module/get_it_module.dart';
import 'package:navigation_module/navigation_module.dart';

import 'no_op/session_service_impl.dart';
import 'services/auth_service.dart';
import 'services/local_storage_service.dart';
import 'services/session_service.dart';

/// Módulo de infraestrutura: serviços de vida longa + tarefas de boot.
///
/// Deve ser o primeiro na lista de módulos compostos pelo app.
/// Depende de packages/módulos diretamente — nunca de `dependencies_module`
/// (evita ciclo: dependencies_module reexporta core_module).
///
/// `ApiClient`, `AuthService` e `LocalStorageService` NÃO são registrados aqui:
/// suas implementações reais vêm do `login_module` (que compõe depois do
/// InfraModule e registra-as via `globalBinds`). Isso mantém o `core_module`
/// neutro (VM+web+desktop): há duas implementações concretas de `ApiClient`
/// (gRPC-Web arrastando `package:web`, e gRPC nativo sobre `dart:io`), escolhidas
/// por import condicional na factory do `login_module`. As `bootTasks` apenas
/// consomem os contratos (`ApiClient` é interface).
final class InfraModule extends AppModule {
  final AppConfig config;
  InfraModule(this.config);

  @override
  void globalBinds(Injector i) {
    i.singleton<AppConfig>(config);
    i.singleton<BootState>(BootState());
    i.singleton<SessionService>(SessionServiceImpl());
  }

  @override
  List<BootTask> bootTasks() => [
    BootTask(BootStage.infra, () => inject<LocalStorageService>().init()),
    BootTask(BootStage.infra, () => inject<ApiClient>().connect()),
    BootTask(BootStage.session, () => inject<AuthService>().checkCurrentUser()),
  ];
}
