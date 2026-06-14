# Especificação de Construção do Módulo `navigation_module`

Este documento detalha a estrutura, dependências e implementação do módulo de infraestrutura **`navigation_module`**. Ele padroniza a **navegação** de todos os apps do monorepo `smart-core-assistant-v2`, baseada em **go_router** (Navigator 2.0, orientado a URL — essencial para o `smart-core-admin` Web).

Princípio de desenho, alinhado ao `get_it_module`:

> Cada **rota** (`GetItModule`) **declara apenas seu `path`** (uma String). O `navigation_module` converte cada rota em uma `GoRoute`, e o `AppRouter` agrega as rotas de todos os módulos (via `collectRoutes`) num único `GoRouter`. Assim o `get_it_module` permanece **livre do go_router**, e cada rota continua autocontida (path + page + binds).

---

## 1. Divisão de Responsabilidades

| Camada | Onde | Papel |
| :--- | :--- | :--- |
| Declaração da rota | `GetItModule.path` / `.name` (no `get_it_module`) | Cada rota diz **qual** é sua URL. |
| Conversão para `GoRoute` | `ModuleRoute` extension (aqui) | Transforma a rota em `GoRoute`, construindo `toRoute()` (casca de escopo de DI). |
| Agregação e roteador | `AppRouter` (aqui) | Junta as rotas (`collectRoutes(modules)`) + guards num `GoRouter`. |
| Navegação no app | `context.go` / `context.push` (go_router) | Disparo da navegação por URL a partir da UI. |

Por conter `go_router` (dependência de Flutter), é um **módulo** (`clients/modulos/`), não um package Dart puro.

---

## 2. Estrutura de Diretórios

```text
clients/modulos/navigation_module/
├── pubspec.yaml
└── lib/
    ├── navigation_module.dart          # Exportação pública (reexporta go_router)
    └── src/
        ├── module_route.dart           # extension ModuleRoute on GetItModule
        ├── boot_state.dart             # BootState (ValueNotifier<bool>) p/ barreira de boot
        └── app_router.dart             # AppRouter: agrega módulos em um GoRouter
```

---

## 3. Configuração de Dependências (`pubspec.yaml`)

```yaml
name: navigation_module
description: Navegação baseada em go_router, agregando as rotas declaradas pelos GetItModule num roteador central.
version: 1.0.0
publish_to: 'none'

environment:
  sdk: ^3.12.2
  flutter: ">=3.44.0"

dependencies:
  flutter:
    sdk: flutter

  # Roteamento baseado em URL (Navigator 2.0)
  go_router: ^17.3.0   # estável mais recente (exige Flutter >= 3.38 / Dart >= 3.10)

  # Contrato de módulo (path/name, toRoute)
  get_it_module:
    path: ../../packages/get_it_module
```

---

## 4. Código de Implementação

### 4.1 Conversão Rota → `GoRoute` (`lib/src/module_route.dart`)

```dart
import 'package:get_it_module/get_it_module.dart';
import 'package:go_router/go_router.dart';

/// Converte uma rota [GetItModule] em uma [GoRoute].
extension ModuleRoute on GetItModule {
  /// Usa o `path`/`name` declarados pela rota e constrói a casca de escopo
  /// de DI via [GetItModule.toRoute]. O escopo é criado ao entrar na rota e
  /// descartado ao sair (dispose do widget pelo go_router).
  GoRoute toGoRoute() => GoRoute(
        path: path,
        name: name,
        builder: (context, state) => toRoute(),
      );
}
```

### 4.2 Roteador Central (`lib/src/app_router.dart`)

```dart
import 'package:get_it_module/get_it_module.dart';
import 'package:go_router/go_router.dart';

import 'module_route.dart';

/// Monta o [GoRouter] central a partir das rotas agregadas dos módulos.
///
/// O app passa `routes: collectRoutes(modules)` (a lista achatada das `routes()`
/// de todos os [AppModule]), a rota inicial e, opcionalmente, um [redirect]
/// para guards de autenticação/boot e rotas avulsas (`extraRoutes`).
///
/// O [refreshListenable] reavalia o `redirect` quando seu valor muda — usado
/// pela barreira de boot ([BootState]) e por mudanças de sessão.
final class AppRouter {
  final List<GetItModule> routes;
  final String initialLocation;
  final List<GoRoute> extraRoutes;
  final GoRouterRedirect? redirect;
  final Listenable? refreshListenable;

  AppRouter({
    required this.routes,
    required this.initialLocation,
    this.extraRoutes = const [],
    this.redirect,
    this.refreshListenable,
  });

  GoRouter build() => GoRouter(
        initialLocation: initialLocation,
        redirect: redirect,
        refreshListenable: refreshListenable,
        routes: [
          ...routes.map((r) => r.toGoRoute()),
          ...extraRoutes,
        ],
      );
}
```

### 4.3 Barreira de Boot (`lib/src/boot_state.dart`)

Estado observável que indica se o [bootstrap em estágios](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-bootstrap-inicializacao.md) terminou. Enquanto `false`, o `redirect` segura tudo na rota de splash; ao virar `true`, o `refreshListenable` reavalia e libera a navegação. Registrado como `singleton` global pelo `InfraModule`.

```dart
import 'package:flutter/foundation.dart';

/// Sinaliza a conclusão do boot em estágios. Usado como refreshListenable do
/// GoRouter: ao completar, o redirect reavalia e libera as rotas.
final class BootState extends ValueNotifier<bool> {
  BootState() : super(false);
  void complete() => value = true;
}
```

### 4.3 Exportação Pública (`lib/navigation_module.dart`)

```dart
library navigation_module;

// Reexporta o go_router para que as features tenham context.go/push,
// GoRoute e GoRouterState sem importar o package diretamente.
export 'package:go_router/go_router.dart';

export 'src/module_route.dart';
export 'src/boot_state.dart';
export 'src/app_router.dart';
```

---

## 5. Integração no App

### 5.1 Bootstrap + roteador no `main.dart`

O app só **registra** os globais (sync) e sobe a UI; a inicialização assíncrona ordenada roda na **rota de splash** (`/`), segurada pela barreira de boot. Ver [construcao-bootstrap-inicializacao.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-bootstrap-inicializacao.md).

```dart
import 'package:flutter/material.dart';
import 'package:dependencies_module/dependencies_module.dart';

// O app compõe os módulos que inclui (cada um expõe serviços e/ou rotas).
final _modules = <AppModule>[
  InfraModule(config),       // registra SessionService, BootState, ApiClient... + bootTasks(infra)
  LoginModule(),             // bootTasks(session): checkCurrentUser
  TenantModule(),
  InitialLoadingModule(),    // rota de splash '/'
];

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Registro síncrono (lazy) dos globais de todos os módulos no escopo-base.
  installModules(_modules);
  // Disponibiliza a lista de módulos ao splash, que roda runBootTasks nela.
  GetIt.instance.registerSingleton<List<AppModule>>(_modules);

  // O boot assíncrono (runBootTasks) roda DENTRO da rota '/', não aqui.
  runApp(const SmartCoreAdminApp());
}

class SmartCoreAdminApp extends StatelessWidget {
  const SmartCoreAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = AppRouter(
      initialLocation: '/',                 // splash; o redirect decide o destino
      routes: collectRoutes(_modules),
      refreshListenable: inject<BootState>(), // reavalia ao concluir o boot
      redirect: _bootRedirect,
    ).build();

    return MaterialApp.router(
      title: 'Smart Core Admin',
      theme: AppTheme.light,                 // tema do design_system_module
      darkTheme: AppTheme.dark,
      routerConfig: router,
    );
  }
}

/// Guard único: barreira de boot + autenticação.
/// Ver construcao-bootstrap-inicializacao.md (§4) e construcao-apresentacao-erro-i18n.md.
String? _bootRedirect(BuildContext context, GoRouterState state) {
  final booted = inject<BootState>().value;
  // Enquanto o boot não termina, tudo fica preso na splash '/'.
  if (!booted) return state.matchedLocation == '/' ? null : '/';

  final authed = inject<SessionService>().token != null;
  if (state.matchedLocation == '/') return authed ? '/tenants' : '/login';
  if (!authed && state.matchedLocation != '/login') return '/login';
  if (authed && state.matchedLocation == '/login') return '/tenants';
  return null;
}
```

> A sessão é lida do `SessionService` (não de `AuthService.isAuthenticated`), hidratado no estágio `session` do boot — ver [construcao-bootstrap-inicializacao.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-bootstrap-inicializacao.md) §3.

### 5.2 Navegação a partir da UI

```dart
context.go('/tenants');          // substitui a pilha; a URL muda
context.push('/tenants');        // empilha sobre a tela atual
context.goNamed('tenant-detail', pathParameters: {'id': tenant.id});
```

### 5.3 Rotas com parâmetros

A rota declara o path com parâmetro; a **page** lê via `GoRouterState.of(context)` — a rota e o `get_it_module` não precisam conhecer os parâmetros.

```dart
// Rota
final class TenantDetailRoute extends GetItModule {
  @override
  String get path => '/tenant/:id';

  @override
  String? get name => 'tenant-detail';

  @override
  Widget get page => const TenantDetailPage();

  @override
  void binds(Injector i) {
    i.controller<TenantDetailController>(
      () => TenantDetailController(getTenant: inject<GetTenantUsecase>()),
    );
  }
}

// Page
class TenantDetailPage extends StatelessWidget {
  const TenantDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final id = GoRouterState.of(context).pathParameters['id']!;
    // dispara a carga inicial com o parâmetro de rota
    return ... // usa inject<TenantDetailController>() e o id
  }
}
```

Para passar objetos complexos (não serializáveis na URL), use `extra`:

```dart
context.push('/tenant/${tenant.id}', extra: tenant);
// na page: final tenant = GoRouterState.of(context).extra as Tenant?;
```

---

## 6. Navegação Disparada por Estado (sem poluir o controller)

O `BaseController` é Dart puro e **não** deve conhecer `BuildContext`. Para navegar após uma ação (ex.: login bem-sucedido), a **page** observa o estado com `BlocListener` e navega:

```dart
BlocListener<LoginController, ViewState<Session>>(
  bloc: inject<LoginController>(),
  listener: (context, state) {
    if (state is SuccessState<Session>) {
      context.go('/tenants');
    }
  },
  child: const LoginForm(),
);
```

> Alternativa (quando muitos controllers precisam navegar): registrar um `NavigationService` global que encapsula o `GoRouter` (via `rootNavigatorKey`) e expõe `go/push`. Mantém os controllers testáveis ao depender de uma abstração, não do `BuildContext`. Fica como evolução, se a necessidade surgir.

---

## 7. Interação com o Ciclo de Vida do Escopo de DI

- Numa `GoRoute` com `builder`, ao **sair** da rota o widget é removido e o `dispose` do `GetItModuleScope` roda → `dropScope` libera os Cubits/Usecases da feature. O comportamento casa exatamente com o esperado.
- **Atenção** a configurações que mantêm páginas vivas (ex.: `StatefulShellRoute` com keep-alive ou abas persistentes): o `dispose` não ocorre enquanto a página permanece montada, então o escopo segue ativo de propósito. Documentar caso shells aninhados sejam adotados (evolução "sub-rotas por módulo").

---

## 8. Resumo das Decisões de Design

- **go_router (Navigator 2.0)** → URL, deep-link, voltar/avançar do browser e refresh nativos no web admin.
- **Módulo declara `path`; `AppRouter` agrega** → feature autocontida + roteamento central unificado.
- **`get_it_module` continua livre do go_router** → a conversão `toGoRoute()` é uma extension isolada neste módulo.
- **Parâmetros lidos na page via `GoRouterState.of(context)`** → o contrato da rota permanece `page`-based e simples.
- **Guards via `redirect`** → autenticação centralizada usando serviços do escopo global.
- **Barreira de boot via `BootState` + `refreshListenable`** → rotas presas na splash `/` até o bootstrap em estágios concluir; robusto a deep-link no web admin.
- **Navegação por estado via `BlocListener`** → controllers seguem Dart puro e testáveis.
