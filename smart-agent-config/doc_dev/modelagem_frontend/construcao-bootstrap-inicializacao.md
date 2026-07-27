# Especificação de Construção do Bootstrap em Estágios (Inicialização Ordenada)

Este documento padroniza a **inicialização ordenada de dependências** no monorepo `smart-core-assistant-v2`. Resolve a pendência **H** ("Bootstrap assíncrono / splash") registrada na §9 de [arquitetura-monorepo-frontend.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/arquitetura-monorepo-frontend.md).

Trabalha sobre o [get_it_module](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-package-get-it-module.md) (DI e ciclo de vida), o [presentation_module](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-modulo-presentation.md) (splash como `ModulePage`) e o [navigation_module](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-modulo-navigation.md) (liberação de rotas via `redirect`).

---

## 1. O Problema: Ordem entre Dependências

Algumas dependências precisam terminar de inicializar **antes** de outras serem sequer construídas:

- **Módulos de feature** consomem **serviços** (`AuthService`, `ApiClient`) já vivos na árvore de injeção.
- **Serviços** dependem de **infraestrutura de I/O** já inicializada (abrir `LocalStorage`/DB, conectar `ApiClient`).
- A **infraestrutura** precisa rodar primeiro, no boot.

A cascata é **Initial Load (I/O) → Services → Módulos (UI)**. Dentro de cada fase as tarefas rodam **em paralelo**; entre fases, **em sequência**.

> **Regra central:** paralelo *dentro* do estágio (`Future.wait`), sequencial *entre* estágios (`await` por estágio).

### 1.1 Princípio que destrava o registro

O `get_it_module` registra serviços como `lazySingleton`: a instância **só é criada no primeiro `inject<T>()`**. Logo o **registro de todos os globais é síncrono e sem ordem** (`installModules`); o que precisa respeitar ordem é apenas o **side-effect assíncrono de `init()`** (abrir DB, conectar canal), que deve rodar **antes** do primeiro `inject` daquele serviço. O problema reduz-se a: *rodar os `init()` na ordem certa, antes de liberar as rotas*.

---

## 2. Contrato de Boot (`get_it_module`)

A orquestração — antes provida pelo `Service.to` do `return_success_or_error` (deprecado) — passa a viver no package de DI, sem god-singleton.

### 2.1 `BootStage`, `BootTask` e `AppModule.bootTasks()`

```dart
// src/app_module.dart

/// Estágios de boot, executados em ordem. Tarefas do MESMO estágio rodam em
/// paralelo (Future.wait); estágios diferentes rodam em sequência.
enum BootStage {
  infra,    // I/O de plataforma: LocalStorage.init, abrir DB, conectar ApiClient
  service,  // serviços de domínio que dependem da infra (warmups)
  session,  // hidratação de sessão: ler token/tenant, validar/sincronizar
}

/// Unidade de trabalho assíncrono de boot, declarada por um módulo.
final class BootTask {
  final BootStage stage;
  final Future<void> Function() run;
  const BootTask(this.stage, this.run);
}

abstract base class AppModule {
  void globalBinds(Injector i) {}
  List<GetItModule> routes() => const [];

  /// Tarefas de inicialização assíncrona deste módulo. Padrão: nenhuma.
  /// Rodam UMA vez no boot, depois de installModules e antes das rotas abrirem.
  List<BootTask> bootTasks() => const [];
}
```

### 2.2 Orquestrador (`runBootTasks` / `bootModules`)

Duas funções, exclusivas entre si conforme o disparo do boot:

```dart
/// Executa apenas as bootTasks por estágio — paralelo dentro do estágio,
/// sequencial entre estágios. Pressupõe installModules já rodado (no main).
/// É o que a rota de splash chama.
Future<void> runBootTasks(List<AppModule> modules) async {
  final tasks = [for (final m in modules) ...m.bootTasks()];
  for (final stage in BootStage.values) {
    await Future.wait(tasks.where((t) => t.stage == stage).map((t) => t.run()));
  }
}

/// Combo registro + boot, para a variante "tudo no main antes do runApp"
/// (sem splash em Flutter). Reaproveita a semântica do antigo Service.to:
///   installModules ≈ initDependences (registro);  Future.wait ≈ initServices.
Future<void> bootModules(List<AppModule> modules) async {
  installModules(modules);
  await runBootTasks(modules);
}
```

> **O monorepo adota o splash em Flutter:** o `main` chama `installModules` (registro síncrono) e a rota `/` chama `runBootTasks`. O `bootModules` (combo) existe para a variante sem splash. Símbolos exportados em `get_it_module.dart`: `BootStage`, `BootTask`, `runBootTasks`, `bootModules`.

---

## 3. Sessão em Memória: `SessionService` (não singleton estático)

O detentor de sessão é o `SessionService` do `core_module` (já existente), registrado como `singleton` global. A hidratação a partir do disco é feita por `AuthService.checkCurrentUser()` (também já no `core_module`), que lê o `LocalStorageService` e popula o `SessionService`. O `ApiClient` lê o token **tardiamente** de `inject<SessionService>().token` a cada request.

> **Não** se usa `ServiceInitializer` nem qualquer singleton estático: tudo é resolvido via `inject<T>()`, preservando o modelo de escopos do `get_it_module` e a testabilidade.

Mapa das fases do app sobre os estágios:

| Estágio | Tarefa | Quem expõe |
| :--- | :--- | :--- |
| `infra` | `LocalStorageService.init()`, `ApiClient.connect()` | `InfraModule` |
| `service` | warmups opcionais | módulos de serviço |
| `session` | `AuthService.checkCurrentUser()` → popula `SessionService`; se autenticado, `validateSessionAndSync` | `login_module` |

---

## 4. Liberação das Rotas: Guard do go_router

Como o app é **web admin URL-first**, deep-link a `/dashboard` é possível. A liberação **não** é navegação manual no splash — é um `redirect` central que segura tudo em `/` até o boot terminar, reagindo a um `refreshListenable`.

```dart
// navigation_module
final class BootState extends ValueNotifier<bool> {
  BootState() : super(false);
  void complete() => value = true;
}

String? bootRedirect(BuildContext ctx, GoRouterState state) {
  final booted = inject<BootState>().value;
  if (!booted) return state.matchedLocation == '/' ? null : '/';

  final authed = inject<SessionService>().token != null;
  if (state.matchedLocation == '/') return authed ? '/dashboard' : '/login';
  if (!authed && _isProtected(state.matchedLocation)) return '/login';
  return null;
}

// GoRouter(refreshListenable: inject<BootState>(), redirect: bootRedirect, ...)
```

O splash dispara o boot e, ao concluir, chama `inject<BootState>().complete()`. O router reavalia e move `/` → `/dashboard` | `/login` sozinho — sem race, sem deep-link furando a barreira.

---

## 5. Hook de Ciclo de Vida no `ModulePage`

O `ModulePage` ganha um hook `onInit(BuildContext)` (default vazio), chamado uma vez na montagem (via `StatefulWidget` interno), para o splash disparar o boot ao aparecer.

```dart
// presentation_module/module_page.dart (trecho)
/// Chamado uma vez quando a página é montada. Padrão: nada.
void onInit(BuildContext context) {}
```

---

## 6. O `initial_loading_module` (reescrito)

Remove o `ServiceInitializer`. O controller recebe a lista de `AppModule` por injeção e roda o `runBootTasks`.

```dart
// presentation/controllers/initial_loading_controller.dart
final class InitialLoadingController extends BaseController<void> {
  final List<AppModule> _modules;
  final BootState _bootState;

  InitialLoadingController({
    required List<AppModule> modules,
    required BootState bootState,
  })  : _modules = modules,
        _bootState = bootState;

  Future<void> bootstrap() => execute(() async {
        // installModules já rodou no main; aqui só as bootTasks por estágio.
        await runBootTasks(_modules);
        _bootState.complete();
        return const Success(null);
      });
}
```

```dart
// presentation/pages/initial_loading_page.dart (trecho)
@override
void onInit(BuildContext context) => controller.bootstrap();

@override
Widget onSuccess(BuildContext context, void data) => const SizedBox.shrink();
// NÃO navega: o redirect do go_router cuida da transição quando BootState=true.
```

```dart
// presentation/routes/initial_loading_route.dart (trecho)
@override
void binds(Injector i) {
  i.controller<InitialLoadingController>(
    () => InitialLoadingController(
      modules: inject<List<AppModule>>(),
      bootState: inject<BootState>(),
    ),
  );
}
```

> A lista de `AppModule` é registrada como global pelo app no boot (`i.singleton<List<AppModule>>(modules)`), permitindo o splash orquestrar sem conhecer cada módulo.

---

## 7. Sequência Ponta a Ponta

```text
main.dart
 ├─ WidgetsFlutterBinding.ensureInitialized()
 ├─ modules = [InfraModule(config), LoginModule(), DashboardModule(), InitialLoadingModule()]
 ├─ installModules(modules) + registrar List<AppModule> e BootState como globais
 └─ runApp(AdminApp(modules))            // BootState=false → router preso em '/'

Rota '/' (InitialLoadingPage.onInit) → controller.bootstrap()
 └─ await runBootTasks(modules):
        infra:   Future.wait([LocalStorage.init(), ApiClient.connect()])
        service: Future.wait([...warmups])
        session: AuthService.checkCurrentUser() → SessionService populado
     SuccessState → inject<BootState>().complete()

router (refreshListenable) reavalia redirect
 └─ SessionService.token != null ? '/dashboard' : '/login'
```

Módulos de feature abrem **depois** de `BootState=true`; ao injetar `AuthService`/`ApiClient`, a infra e a sessão já rodaram → nunca veem nulo/obsoleto.

---

## 8. Lista de Mudanças por Arquivo

| Alvo | Ação | Detalhe |
| :--- | :--- | :--- |
| `packages/get_it_module` `src/app_module.dart` | MODIFY | `BootStage`, `BootTask`, `AppModule.bootTasks()`, `runBootTasks()`, `bootModules()` |
| `packages/get_it_module` `get_it_module.dart` | MODIFY | Exportar os novos símbolos |
| `modulos/presentation_module` `src/module_page.dart` | MODIFY | Hook `onInit(BuildContext)` via State interno |
| `modulos/navigation_module` | NEW | `BootState`; `AppRouter` com `refreshListenable` e `bootRedirect` |
| `modulos/core_module` | KEEP | Contratos `LocalStorageService`/`AuthService`/`SessionService`; `checkCurrentUser()` lê o `LocalStorage` e popula o `SessionService` |
| `InfraModule` (em `core_module` ou no app) | NEW | `globalBinds`: `AppConfig`/`SessionService`/`BootState` (singleton), `LocalStorageService`/`ApiClient` (lazy, token via `inject<SessionService>()`); `bootTasks()` → `infra` |
| `modulos/login_module` | MODIFY | `bootTasks()` → `session`: `inject<AuthService>().checkCurrentUser()` |
| `modulos/initial_loading_module` | DELETE/MODIFY | Remover `ServiceInitializer`; controller/page/route conforme §6 |
| `apps/smart-core-admin` `main.dart`/`bootstrap.dart` | MODIFY | Compor `modules`, `installModules`, registrar `List<AppModule>`+`BootState`, `runApp` (o `runBootTasks` roda no splash) |

---

## 9. Plano de Verificação

- **Primeiro boot, sem dados:** estágios em ordem; `token == null` → guard `/` → `/login`. Deep-link em `/dashboard` durante o boot fica preso em `/`.
- **Sessão salva:** após restart, `checkCurrentUser` repopula `SessionService`; request no Dashboard sai com `Authorization` lido tardiamente.
- **Falha de estágio:** exceção em `infra` → `runBootTasks` rejeita → `ErrorState` no splash com "Recarregar"; `BootState` segue `false`, rotas barradas.
- **Logout:** `AuthService.logout()` limpa `SessionService`+`LocalStorage`; guard leva a `/login`.
- **Ordem (unitário, Dart puro):** `runBootTasks` com tarefas instrumentadas provando paralelismo intra-estágio e sequência inter-estágios.

---

## 10. Resumo das Decisões de Design

- **Orquestração no `get_it_module`** (`BootStage`/`BootTask`/`bootModules`) → coeso com `installModules`/`collectRoutes`, sem god-singleton.
- **Registro lazy desacopla ordem-de-registro de ordem-de-criação** → só os `init()` assíncronos precisam ser ordenados.
- **Paralelo dentro do estágio, sequencial entre estágios** → mesma semântica do antigo `Service.to`, declarativa.
- **Sessão no `SessionService`** (não `ServiceInitializer`) → contrato existente, hidratado por `checkCurrentUser`, tudo via `inject<T>()`.
- **Liberação por `redirect` + `BootState`** → seguro a deep-link no web admin; splash não navega.
