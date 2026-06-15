# Plano Completo — Base do Monorepo Frontend Flutter (`clients/`)

> Feature: `base-frontend-flutter`
> Branch: `feature/setup-flutter-web-admin`
> Escopo: **infraestrutura pura, SEM regra de negócio** — packages estruturais, módulos de
> infra e a casca do app cliente.
> Arquitetura: `smart-agent-config/doc_dev/modelagem_frontend/`.
> Versões e configuração de workspace: `info_aux_base-frontend-flutter.md` (2026-06-14).

Construção **greenfield** (a pasta `clients/` é criada do zero), em **cronograma incremental**:
cada etapa entrega um pacote/módulo **compilável e validável isoladamente** antes de seguir.
A ordem segue a **cascata de dependências** (de baixo p/ cima): packages estruturais → módulos
de infra → agregador → módulo de bootstrap → app cliente.

---

## 1. Objetivo e fronteiras

**Objetivo:** montar a base estrutural do frontend Flutter — injeção de dependências modular,
estado padronizado, navegação, design system, configuração por ambiente e a casca do app Web
admin — pronta para receber features de domínio depois.

**Dentro do escopo:**
- Workspace Dart (Pub Workspaces) + Melos para scripts.
- Packages: `app_config`, `domain_models` (stub), `get_it_module`, `api_client` (stub).
- Módulos: `presentation_module`, `design_system_module`, `navigation_module`, `core_module`,
  `dependencies_module`, `initial_loading_module`.
- App: `smart-core-admin` (Web) como casca mínima + i18n base.

**Fora do escopo (fases futuras):**
- `login_module` e qualquer feature de domínio (dashboard, tenants, atendimentos) + guard de
  autenticação real.
- Transporte real no `api_client` (gRPC/gRPC-Web/FlatBuffers) e geração de DTOs `.proto` em
  `domain_models`.
- Apps `smart-core-windows-tenant` / `smart-core-web-tenant` e `plugins/`.

---

## 2. Versões fixadas (mais recentes estáveis — Dart 3.12.2 / Flutter 3.44.2)

| Package | Constraint | Tipo |
| :-- | :-- | :-- |
| `bloc` | `^9.2.1` | externo |
| `flutter_bloc` | `^9.1.1` | externo |
| `get_it` | `^9.2.1` | externo |
| `go_router` | `^17.3.0` | externo |
| `intl` | `^0.20.2` | externo |
| `uuid` | `^4.5.3` | externo |
| `return_success_or_error` | `^2.0.0` (pub.dev) | externo |
| `melos` | `^7.8.2` (dev) | tooling |
| `bloc_test` | `^10.0.0` (dev) | teste |
| `mocktail` | `^1.0.5` (dev) | teste |
| `flutter_lints` | `^6.0.0` (dev) | lint |

SDK em todos os membros: `environment: { sdk: ^3.12.2, flutter: ">=3.44.0" }` (packages
Dart-puro omitem `flutter`).

---

## 3. Grafo de conexão entre os componentes

```
                 app_config        domain_models         get_it_module
                  (Dart puro)        (Dart puro)        (Flutter; só get_it)
                      │                  │                     │
                      ├──────► api_client ◄──────┐             │
                      │        (Dart puro)        │            │
                      │                           │            │
   design_system   presentation_module     navigation_module   │
   (Flutter)       (get_it_module +         (get_it_module +    │
                    bloc + r_s_o_e)          go_router)         │
        │                 │                      │              │
        └───────┬─────────┴──────────┬───────────┴──────────────┘
                │                    │
                ▼                    ▼
             core_module (InfraModule + contratos de serviço)
                │   depende de: app_config, api_client, get_it_module,
                │               navigation_module, presentation_module
                ▼
          dependencies_module  ── reexporta tudo de infra (âncora de imports)
                │
                ▼
        initial_loading_module (splash; depende de dependencies_module)
                │
                ▼
          smart-core-admin (app; depende de dependencies_module + initial_loading_module)
```

**Regras de conexão (invioláveis):**
- Packages Dart-puro (`app_config`, `domain_models`, `api_client`) **não** importam Flutter.
  `get_it_module` é a exceção (usa `flutter/widgets` no `GetItModuleScope`).
- `core_module` depende dos packages/módulos **diretamente**, nunca de `dependencies_module`
  (que reexporta `core_module` para cima) — evita ciclo.
- `dependencies_module` reexporta **só infra** (nunca módulos de feature).
- Features (e o app) importam **um lugar só**: `package:dependencies_module/dependencies_module.dart`.

---

## 4. Cronograma de desenvolvimento (passo a passo, validável por partes)

> Convenção: ao final de cada etapa, adicionar o novo pacote ao `workspace:` do
> `clients/pubspec.yaml`, rodar `flutter pub get` na raiz e `flutter analyze` no pacote
> (meta: **0 issues**). Onde indicado, escrever o teste mínimo e rodar `flutter test`.

---

### Etapa 0 — Esqueleto do workspace

**Entrega:** árvore de pastas + workspace Pub + Melos resolvendo vazio.

**Arquivos:**
- `clients/pubspec.yaml` (raiz do workspace):
  ```yaml
  name: smart_core_clients
  publish_to: 'none'
  environment:
    sdk: ^3.12.2

  # Pub Workspaces (Dart >= 3.6): membros adicionados a cada etapa.
  workspace:
    # - packages/app_config        (Etapa 1.1)
    # - packages/domain_models     (Etapa 1.2)
    # - packages/get_it_module     (Etapa 1.3)
    # - packages/api_client        (Etapa 1.4)
    # - modulos/presentation_module
    # - modulos/design_system_module
    # - modulos/navigation_module
    # - modulos/core_module
    # - modulos/dependencies_module
    # - modulos/initial_loading_module
    # - apps/smart-core-admin

  dev_dependencies:
    melos: ^7.8.2

  # Scripts do Melos 7.x (mora no pubspec raiz; não há melos.yaml).
  melos:
    name: smart_core_clients
    scripts:
      analyze:
        run: melos exec -- flutter analyze .
      test:
        run: melos exec --dir-exists=test -- flutter test
  ```
- `clients/analysis_options.yaml` — `include: package:flutter_lints/flutter.yaml`.
- `clients/.gitignore` — `.dart_tool/`, `build/`, `*.iml`, `pubspec.lock` (avaliar versionar
  o lock único; por ora ignorar).
- Pastas vazias: `clients/{apps,modulos,packages,plugins}/` (`.gitkeep` em `plugins/`).

**Validação:** `cd clients && flutter pub get` (workspace vazio resolve ok) e
`dart pub global activate melos && melos --version`.

**Observabilidade & Auditoria:** sem evento (estrutura de pastas).

---

### Etapa 1 — Packages estruturais

> Base da cascata. Cada um é independente e validável sozinho.

#### 1.1 `packages/app_config` (Dart puro)

**Entrega:** configuração imutável por ambiente.

**Arquivos:** `pubspec.yaml`, `lib/app_config.dart` (barrel), `lib/src/app_config.dart`.
```dart
// lib/src/app_config.dart
enum AppFlavor { dev, staging, prod }

/// Configuração imutável do app, injetada no escopo global no boot.
final class AppConfig {
  final AppFlavor flavor;
  final String apiEndpoint;   // 'https://api...' ou 'tcp://host:50051'
  final bool enableLogging;
  const AppConfig({
    required this.flavor,
    required this.apiEndpoint,
    this.enableLogging = false,
  });
  bool get isProd => flavor == AppFlavor.prod;
}
```
`pubspec.yaml`: `environment.sdk: ^3.12.2`, `resolution: workspace`, **sem** `flutter:`.

**Validação:** `flutter analyze` (0 issues).

#### 1.2 `packages/domain_models` (Dart puro, stub)

**Entrega:** ponto de extensão para DTOs futuros (vazio agora).

**Arquivos:** `pubspec.yaml`, `lib/domain_models.dart`.
```dart
/// Modelos de domínio / DTOs compartilhados do monorepo.
///
/// Stub estrutural: receberá os tipos gerados dos `.proto` do backend em fase
/// futura. Sem tipos nesta base.
library domain_models;
```
`pubspec.yaml`: Dart puro, `resolution: workspace`.

**Validação:** `flutter analyze`.

#### 1.3 `packages/get_it_module` (Flutter library)

**Entrega:** injeção de dependências modular em dois níveis de escopo + boot por estágios.
Implementação completa conforme `construcao-package-get-it-module.md`.

**Arquivos:**
- `lib/src/injector.dart` — `Injector` (`factory` / `lazySingleton` / `singleton`, com `dispose`).
- `lib/src/app_module.dart` — `AppModule` (base: `globalBinds`, `routes`, `bootTasks`),
  `BootStage { infra, service, session }`, `BootTask`, `installModules`, `collectRoutes`,
  `runBootTasks` (paralelo intra-estágio / sequencial inter-estágios), `bootModules`.
- `lib/src/get_it_module_base.dart` — `GetItModule` (`path` / `name` / `page` / `binds` / `toRoute`).
- `lib/src/get_it_module_scope.dart` — `GetItModuleScope` (StatefulWidget: `pushNewScope`/
  `dropScope` por nome de montagem). **Não exportado** (detalhe interno).
- `lib/src/inject.dart` — `inject<T>()`.
- `lib/get_it_module.dart` — barrel (exporta `app_module`, `get_it_module_base`, `injector`,
  `inject`).
- `pubspec.yaml`: `flutter: sdk`, `get_it: ^9.2.1`, `resolution: workspace`.

> `get_it ^9` mantém `pushNewScope(scopeName:)`, `dropScope(scopeName)`, `hasScope(scopeName)`,
> `registerFactory`/`registerLazySingleton(dispose:)`/`registerSingleton`. Envolver `dropScope`
> em `if (hasScope(...))`.

Trecho central de `app_module.dart`:
```dart
enum BootStage { infra, service, session }

final class BootTask {
  final BootStage stage;
  final Future<void> Function() run;
  const BootTask(this.stage, this.run);
}

abstract base class AppModule {
  void globalBinds(Injector i) {}
  List<GetItModule> routes() => const [];
  List<BootTask> bootTasks() => const [];
}

void installModules(List<AppModule> modules) {
  final injector = Injector(GetIt.instance);
  for (final m in modules) { m.globalBinds(injector); }
}

List<GetItModule> collectRoutes(List<AppModule> modules) =>
    [for (final m in modules) ...m.routes()];

Future<void> runBootTasks(List<AppModule> modules) async {
  final tasks = [for (final m in modules) ...m.bootTasks()];
  for (final stage in BootStage.values) {
    await Future.wait(tasks.where((t) => t.stage == stage).map((t) => t.run()));
  }
}
```

**Validação (teste mínimo):** `flutter test` —
- `installModules` registra um serviço global resolvível por `inject<T>()`.
- `runBootTasks` roda estágios em ordem (`infra` antes de `session`).

#### 1.4 `packages/api_client` (Dart puro, stub)

**Entrega:** contrato único de comunicação (sem transporte real).

**Arquivos:** `pubspec.yaml`, `lib/api_client.dart` (barrel), `lib/src/api_client.dart`.
```dart
import 'package:app_config/app_config.dart';

/// Cliente único de comunicação com o backend (gRPC/gRPC-Web em fase futura).
abstract interface class ApiClient {
  Future<void> connect();
}

/// Stub estrutural: `connect()` é no-op. NÃO loga segredos — só endpoint/status.
final class ApiClientStub implements ApiClient {
  final AppConfig _config;
  const ApiClientStub({required AppConfig config}) : _config = config;

  @override
  Future<void> connect() async {
    if (_config.enableLogging) {
      // ignore: avoid_print
      print('ApiClient.connect → endpoint=${_config.apiEndpoint} status=stub-ok');
    }
  }
}
```
`pubspec.yaml`: depende de `app_config`, `domain_models` (path/workspace); Dart puro;
`resolution: workspace`.

**Validação:** `flutter analyze`.

**Observabilidade & Auditoria (Etapa 1):** sem `audit_log` (frontend estrutural). Disciplina
de **não-vazamento** já fixada: `ApiClient.connect()` loga só endpoint/status, nunca segredos.

---

### Etapa 2 — Módulos de infraestrutura

#### 2.1 `modulos/presentation_module`

**Entrega:** estado padronizado + controller base + bases de página.

**Arquivos:**
- `lib/src/view_state.dart` — `sealed ViewState<T>` → `InitialState` / `LoadingState` /
  `SuccessState<T>(data)` / `ErrorState<T>(error: AppError)`.
- `lib/src/base_controller.dart` — `BaseController<T> extends Cubit<ViewState<T>>` com
  `execute()` (mapeia `ReturnSuccessOrError` via `switch` exaustivo):
  ```dart
  Future<void> execute(Future<ReturnSuccessOrError<T>> Function() task) async {
    emit(LoadingState<T>());
    final result = await task();
    switch (result) {
      case SuccessReturn<T>(): emit(SuccessState<T>(result.result));
      case ErrorReturn<T>():   emit(ErrorState<T>(result.result));
    }
  }
  ```
- `lib/src/module_page.dart` — `ModulePage<C extends BaseController<T>, T>` (StatefulWidget;
  `onInit`, defaults de `onInitial`/`onLoading`/`onError`, `onSuccess` abstrato; resolve
  `inject<C>()`).
- `lib/src/view_state_builder.dart` — `ViewStateBuilder<C, T>`.
- `lib/src/controller_binds.dart` — `extension ControllerBinds on Injector { void controller<C extends BlocBase>(...) }` (lazySingleton + `close()` no dispose).
- `lib/presentation_module.dart` — barrel.
- `pubspec.yaml`: `flutter`, `bloc: ^9.2.1`, `flutter_bloc: ^9.1.1`, `return_success_or_error: ^2.0.0`, `get_it_module` (workspace), dev `bloc_test: ^10.0.0`, `mocktail: ^1.0.5`; `resolution: workspace`.

**Validação (teste mínimo):** `bloc_test` — `BaseController.execute` emite `[Loading, Success]`
e `[Loading, Error]` mockando a tarefa para `SuccessReturn`/`ErrorReturn`.

**Observabilidade & Auditoria:** sem `audit_log`. **Erro rastreável**: toda falha vira
`AppError` em `ErrorState<T>`; UI nunca trata `Exception` cru.

#### 2.2 `modulos/design_system_module`

**Entrega:** tokens, tema e widgets base (tema dark Material 3).

**Arquivos:**
- `lib/src/tokens/` — `app_colors.dart`, `app_typography.dart`, `app_spacing.dart`, `app_radius.dart`.
- `lib/src/theme/app_theme.dart` — `AppTheme.light` / `AppTheme.dark` (`useMaterial3: true`).
- `lib/src/widgets/` — `primary_button.dart`, `app_text_field.dart`, `app_card.dart`,
  `app_scaffold.dart`, `app_error_view.dart` (mensagem + `onRetry`, usado pelo `onError` default).
- `lib/design_system_module.dart` — barrel (tokens + tema + widgets).
- `pubspec.yaml`: só `flutter`; `resolution: workspace`.

**Validação:** `flutter analyze` (+ widget test opcional de `PrimaryButton`).

**Observabilidade & Auditoria:** sem evento (UI pura).

#### 2.3 `modulos/navigation_module`

**Entrega:** roteador central URL-first + barreira de boot.

**Arquivos:**
- `lib/src/module_route.dart` — `extension ModuleRoute on GetItModule { GoRoute toGoRoute() }`.
- `lib/src/app_router.dart` — `AppRouter` (`routes`, `initialLocation`, `extraRoutes`,
  `redirect`, `refreshListenable`; `build()` → `GoRouter`).
- `lib/src/boot_state.dart` — `BootState extends ValueNotifier<bool>` (`complete()`).
- `lib/navigation_module.dart` — barrel (reexporta `go_router`).
- `pubspec.yaml`: `flutter`, `go_router: ^17.3.0`, `get_it_module` (workspace); `resolution: workspace`.
```dart
final class AppRouter {
  final List<GetItModule> routes;
  final String initialLocation;
  final List<GoRoute> extraRoutes;
  final GoRouterRedirect? redirect;
  final Listenable? refreshListenable;
  AppRouter({required this.routes, required this.initialLocation,
    this.extraRoutes = const [], this.redirect, this.refreshListenable});

  GoRouter build() => GoRouter(
        initialLocation: initialLocation,
        redirect: redirect,
        refreshListenable: refreshListenable,
        routes: [...routes.map((r) => r.toGoRoute()), ...extraRoutes],
      );
}
```

**Validação (teste mínimo):** `AppRouter(...).build().configuration.routes` contém o nº de
rotas esperado para uma lista de `GetItModule` fake.

**Observabilidade & Auditoria:** sem evento. `redirect` lê `SessionService.token` mas nunca o loga.

#### 2.4 `modulos/core_module`

**Entrega:** `InfraModule` (serviços globais + boot) + contratos de serviço com impls no-op.

**Arquivos:**
- `lib/src/services/` — contratos `abstract interface`: `SessionService` (token/tenant),
  `LocalStorageService` (`init()`), `AuthService` (`checkCurrentUser()`).
- `lib/src/no_op/` — `SessionServiceImpl` (estado em memória), `LocalStorageServiceNoOp`,
  `AuthServiceNoOp` (apenas para o boot fechar; **sem lógica de negócio**).
- `lib/src/infra_module.dart` — `InfraModule extends AppModule`.
- `lib/core_module.dart` — barrel (contratos + `InfraModule`).
- `pubspec.yaml`: `flutter`, `get_it_module`, `app_config`, `api_client`, `navigation_module`
  (todos workspace); `resolution: workspace`.
```dart
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
```

**Validação (teste mínimo):** `installModules([InfraModule(cfg)])` + `runBootTasks` completa;
`inject<AppConfig>()`/`inject<BootState>()` resolvem.

**Observabilidade & Auditoria:** sem `audit_log`. **Não-vazamento**: `SessionServiceImpl`
guarda token/refresh — proibido logar. Ponto único futuro de logging estruturado.

---

### Etapa 3 — Agregador (`modulos/dependencies_module`)

**Entrega:** âncora de versões e ponto único de import.

**Arquivos:** `pubspec.yaml`, `lib/dependencies_module.dart`.
```dart
// Módulos internos
export 'package:design_system_module/design_system_module.dart';
export 'package:core_module/core_module.dart';
export 'package:presentation_module/presentation_module.dart';
export 'package:navigation_module/navigation_module.dart';

// Packages do monorepo
export 'package:get_it_module/get_it_module.dart';
export 'package:api_client/api_client.dart';
export 'package:domain_models/domain_models.dart';
export 'package:app_config/app_config.dart';

// Externas
export 'package:flutter/material.dart';
export 'package:get_it/get_it.dart';
export 'package:flutter_bloc/flutter_bloc.dart';
export 'package:bloc/bloc.dart';
export 'package:return_success_or_error/return_success_or_error.dart';
export 'package:intl/intl.dart' hide TextDirection;
export 'package:uuid/uuid.dart';
```
`pubspec.yaml`: depende dos 4 módulos internos + 4 packages + externas (`get_it: ^9.2.1`,
`flutter_bloc: ^9.1.1`, `bloc: ^9.2.1`, `intl: ^0.20.2`, `uuid: ^4.5.3`,
`return_success_or_error: ^2.0.0`); `resolution: workspace`. **Não** exporta módulos de feature.

**Validação:** `flutter analyze`; um arquivo de teste que importa só `dependencies_module` e
referencia `AppModule`, `ViewState`, `AppRouter`, `AppConfig` (prova de superfície única).

**Observabilidade & Auditoria:** sem evento (agregador).

---

### Etapa 4 — Módulo de bootstrap (`modulos/initial_loading_module`)

**Entrega:** splash que roda o boot por estágios e libera a barreira.

**Arquivos:**
- `lib/src/presentation/controllers/initial_loading_controller.dart`:
  ```dart
  final class InitialLoadingController extends BaseController<void> {
    final List<AppModule> _modules;
    final BootState _bootState;
    InitialLoadingController({required List<AppModule> modules, required BootState bootState})
        : _modules = modules, _bootState = bootState;

    Future<void> bootstrap() => execute(() async {
          await runBootTasks(_modules);   // installModules já rodou no main
          _bootState.complete();          // refreshListenable reavalia o redirect
          return const SuccessReturn(success: null);
        });
  }
  ```
- `lib/src/presentation/pages/initial_loading_page.dart` — `ModulePage`; `onInit` dispara
  `bootstrap()`; `onSuccess` retorna `SizedBox.shrink()` (quem navega é o `redirect`).
- `lib/src/presentation/routes/initial_loading_route.dart` — `GetItModule` (path `/`),
  binds resolvendo `inject<List<AppModule>>()` e `inject<BootState>()`.
- `lib/src/initial_loading_module.dart` — `InitialLoadingModule extends AppModule` (rota `/`).
- `lib/initial_loading_module.dart` — barrel.
- `pubspec.yaml`: depende de `dependencies_module`; `resolution: workspace`.

**Validação (teste mínimo):** `bloc_test` do controller emite `[Loading, Success]` e chama
`BootState.complete()`.

**Observabilidade & Auditoria:** sem `audit_log`. **Erro rastreável**: falha de boot →
`ErrorState` no splash; `BootState` segue `false` e barra as rotas.

---

### Etapa 5 — App cliente (`apps/smart-core-admin`)

**Entrega:** casca Web mínima que compõe os módulos, sobe o roteador e fecha o ciclo de boot.

**Arquivos:**
- `lib/bootstrap.dart`:
  ```dart
  Future<void> bootstrap(AppConfig config) async {
    WidgetsFlutterBinding.ensureInitialized();
    final modules = <AppModule>[
      InfraModule(config),
      InitialLoadingModule(),   // rota de splash '/'
    ];
    installModules(modules);
    GetIt.instance.registerSingleton<List<AppModule>>(modules);
    runApp(const SmartCoreAdminApp());
  }
  ```
- `lib/main_dev.dart` / `lib/main_prod.dart` — entrypoints com `AppConfig` por flavor.
- `lib/main.dart` — delega para `main_dev`.
- `lib/app.dart` — `SmartCoreAdminApp` (`MaterialApp.router`):
  ```dart
  final modules = inject<List<AppModule>>();
  final router = AppRouter(
    initialLocation: '/',
    routes: collectRoutes(modules),
    refreshListenable: inject<BootState>(),
    redirect: _bootRedirect,
  ).build();
  return MaterialApp.router(
    theme: AppTheme.light, darkTheme: AppTheme.dark,
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('pt'),
  );
  ```
  `_bootRedirect`: enquanto `!BootState.value`, prende em `/`; após boot, segue para a rota
  placeholder (guard de auth real entra com o `login_module`, fora desta base).
- i18n: `l10n.yaml`, `lib/l10n/app_pt.arb` (chaves de erro genéricas) + `ErrorMessageMapper`
  no `presentation_module` (ou consumido aqui).
- `web/` (index.html, manifest), `pubspec.yaml` (`flutter`, `dependencies_module`,
  `initial_loading_module`, `cupertino_icons`; `flutter: generate: true`; `resolution: workspace`).

**Validação (end-to-end):** `flutter run -d chrome -t lib/main_dev.dart` → splash `/` →
`runBootTasks` completa (`LocalStorage.init` + `ApiClient.connect` no-op) → `BootState.complete()`
libera a barreira → rota placeholder de "boot concluído".

**Observabilidade & Auditoria:** sem `audit_log`. **Não-vazamento**: nenhuma credencial no
código; endpoints sensíveis via `--dart-define`/`String.fromEnvironment`.

---

### Etapa 6 — Qualidade e fechamento

- `melos run analyze` → **0 issues** em todos os pacotes.
- `melos run test` → todos os testes verdes.
- `dart format` em todo o `clients/`.
- Conferir o grafo de dependências (sem ciclos; `core_module` não importa `dependencies_module`;
  `dependencies_module` não exporta features).

---

## 5. Configuração do workspace (referência rápida)

**Raiz `clients/pubspec.yaml`:** `name` obrigatório, `publish_to: 'none'`,
`environment.sdk: ^3.12.2`, campo `workspace:` listando os membros, `dev_dependencies.melos`,
seção `melos.scripts`. Há **um único** `pubspec.lock` + `.dart_tool/` na raiz.

**Cada membro:** `resolution: workspace` + `environment.sdk: ^3.12.2` (+ `flutter` quando é
pacote Flutter). Dependências internas por `path:` continuam válidas e são resolvidas
localmente pelo workspace.

**Resolver:** `flutter pub get` (ou `dart pub get`) em qualquer nível atualiza o lock único.
`melos run analyze` / `melos run test` para varrer todos os pacotes.

---

## 6. Regras invioláveis (checagem final)

- Packages Dart-puro (`app_config`/`domain_models`/`api_client`) sem `flutter:`; `get_it_module`
  é a única exceção.
- `core_module` depende de packages/módulos diretamente, **não** de `dependencies_module`.
- `dependencies_module` reexporta só infra; features importam um lugar só.
- Estado sempre `ViewState<T>`; UI só trata `AppError`; controllers sem `BuildContext`.
- Comentários em **pt-br**; commits sem auto-referência; gitflow.

---

## 7. Observabilidade & Auditoria (resumo)

Base de **frontend estrutural**: **sem evento de `audit_log`** (auditoria é backend, via
`transport::bus`→`data_postgres`; o frontend não acessa estado sensível de tenant nesta base).
Disciplina equivalente, desde já: **erro rastreável** (`AppError` → `ErrorState<T>` no
`BaseController.execute` → `ErrorMessageMapper` localizado); **não-vazamento** (proibido logar
token/refresh do `SessionService`; `ApiClient.connect()` loga só endpoint/status; sem
credenciais no código; endpoints via `--dart-define`). Logging estruturado real entra com o
`InfraModule`/`api_client` em fase futura (padronizando `flavor/env` e, depois, `tenant_id`/
`trace_id` alinhados ao Envelope do backend).
