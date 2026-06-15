import 'package:get_it/get_it.dart';

import 'get_it_module_base.dart';
import 'injector.dart';

/// Contrato de um **módulo** reutilizável e independente
/// (ex.: `login_module`, `design_system_module`).
///
/// Um módulo expõe FEATURES para o app e para outros módulos:
///  - [globalBinds]: registra serviços no escopo-base global, consumidos por
///    qualquer rota/módulo via [inject]. São as features de serviço — ex.: a
///    implementação de `AuthService` exposta pelo `login_module`.
///  - [routes]: as telas/fluxos de UI que o módulo contribui ao roteador. Cada
///    rota é um [GetItModule] com escopo de DI próprio. Um módulo pode expor
///    várias rotas (ou nenhuma — ex.: um módulo só de serviços).
abstract base class AppModule {
  /// Serviços expostos no escopo global. Sobrescreva para registrar a
  /// implementação das features de serviço do módulo. Padrão: nada.
  void globalBinds(Injector i) {}

  /// Rotas expostas pelo módulo. Padrão: nenhuma.
  List<GetItModule> routes() => const [];

  /// Tarefas de inicialização assíncrona deste módulo. Padrão: nenhuma.
  /// Rodam UMA vez no boot (via [runBootTasks]), depois de [installModules] e
  /// antes das rotas abrirem. Ver construcao-bootstrap-inicializacao.md.
  List<BootTask> bootTasks() => const [];
}

/// Estágios de boot, executados em ordem. Tarefas do MESMO estágio rodam em
/// paralelo (Future.wait); estágios diferentes rodam em sequência.
enum BootStage {
  infra, // I/O de plataforma: LocalStorage.init, abrir DB, conectar ApiClient
  service, // serviços de domínio que dependem da infra (warmups)
  session, // hidratação de sessão: ler token/tenant, validar/sincronizar
}

/// Unidade de trabalho assíncrono de boot, declarada por um módulo.
final class BootTask {
  final BootStage stage;
  final Future<void> Function() run;
  const BootTask(this.stage, this.run);
}

/// Registra os serviços globais de todos os [modules] no escopo-base do GetIt.
/// Chamar uma única vez no boot, antes de `runApp`.
void installModules(List<AppModule> modules) {
  final injector = Injector(GetIt.instance);
  for (final module in modules) {
    module.globalBinds(injector);
  }
}

/// Coleta todas as rotas expostas pelos [modules] (insumo para o `AppRouter`).
List<GetItModule> collectRoutes(List<AppModule> modules) => [
  for (final module in modules) ...module.routes(),
];

/// Executa apenas as bootTasks por estágio — paralelo dentro do estágio,
/// sequencial entre estágios. Pressupõe que [installModules] já rodou (no
/// `main`). É o que a rota de splash chama.
Future<void> runBootTasks(List<AppModule> modules) async {
  final tasks = [for (final m in modules) ...m.bootTasks()];
  for (final stage in BootStage.values) {
    await Future.wait(tasks.where((t) => t.stage == stage).map((t) => t.run()));
  }
}

/// Combo registro + boot, para a variante "tudo no `main` antes do runApp"
/// (sem splash em Flutter). NÃO use junto com [installModules] — registraria
/// os globais duas vezes.
Future<void> bootModules(List<AppModule> modules) async {
  installModules(modules);
  await runBootTasks(modules);
}
