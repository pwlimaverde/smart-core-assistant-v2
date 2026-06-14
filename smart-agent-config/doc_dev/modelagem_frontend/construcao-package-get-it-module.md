# Especificação de Construção do Package `get_it_module`

Este documento detalha a estrutura de arquivos, dependências e implementação de código do package de infraestrutura **`get_it_module`**. Ele fornece a solução padrão de injeção de dependências modular do monorepo `smart-core-assistant-v2`, baseada em **dois níveis de escopo do GetIt** atrelados ao **ciclo de vida do Flutter**.

A meta de design é tornar a declaração de um módulo **declarativa e mínima**, inspirada no gerenciamento de módulos do **GetX** (`Bindings`) e do **Flutter Modular** (`Module`):

> Um **módulo** (`AppModule`) é uma unidade reutilizável que expõe **features**: serviços globais (consumidos por outros módulos) e rotas de UI. Cada **rota** (`GetItModule`) declara `path` + `page` + `binds`. O package resolve sozinho a criação dos escopos, o registro e o descarte automático.

---

## 1. Dois Conceitos, Dois Níveis de Escopo

| Conceito | Contrato | O que é |
| :--- | :--- | :--- |
| **Módulo** | `AppModule` | Unidade reutilizável e independente (`login_module`, `design_system_module`). Expõe features via `globalBinds` (serviços) e `routes()` (telas). |
| **Rota** | `GetItModule` | Uma tela/fluxo com escopo de DI próprio (`path` + `page` + `binds`). Um módulo pode expor várias. |

A injeção é organizada em **dois níveis de escopo**, evitando duplicação:

| Nível | Quem registra | Quando | Quando descarta | Para quê |
| :--- | :--- | :--- | :--- | :--- |
| **Global** (escopo-base) | `AppModule.globalBinds` de todos os módulos, agregados no boot | Uma vez, no boot | Só ao encerrar o app | Features de serviço compartilhadas: `ApiClient`, `AuthService`, sessão, logger. |
| **Rota** (escopo empilhado) | `GetItModule.binds` | Ao abrir a tela | Ao fechar a tela (pop) | Dependências exclusivas da tela: Controllers, Usecases de tela. |

**Regra de ouro:** se um binding é usado por mais de uma rota/módulo, ele sobe para o escopo **global** (via `globalBinds` do módulo dono) — não se duplica entre rotas. O GetIt resolve do escopo da rota (topo) descendo até o base, então toda rota enxerga os serviços globais automaticamente.

```text
┌─────────────────────────────────────────────┐
│ Escopo de ROTA (LoginRoute)                 │ ← Controllers/Usecases da tela (efêmeros)
│   LoginController, LoginUsecase             │
├─────────────────────────────────────────────┤
│ Escopo-base / GLOBAL                        │ ← features de serviço (vida longa)
│   ApiClient, AuthService, SessionService    │   expostas pelos globalBinds dos módulos
└─────────────────────────────────────────────┘
       resolução do GetIt: rota → base
```

---

## 2. A Fachada de Provisão (`Injector`)

Os módulos não usam a API crua do GetIt. Eles recebem um `Injector` com **três modos de provisão** de semântica explícita:

| Modo | Comportamento | Uso típico |
| :--- | :--- | :--- |
| `factory<T>(create)` | **Nova instância a cada resolução**. Sem dispose automático. | Objetos sem estado ou descartáveis a cada uso. |
| `lazySingleton<T>(create, {dispose})` | **Instância única**, criada na primeira resolução. | Padrão para Cubits e serviços. |
| `singleton<T>(instance, {dispose})` | **Instância única**, criada imediatamente no registro. | Serviços que precisam existir já no boot (ex.: logger global). |

A resolução em qualquer lugar do app é feita pelo helper top-level `inject<T>()`, que desacopla a UI do GetIt diretamente.

---

## 3. Localização e Estrutura de Diretórios

O package é construído sob `clients/packages/get_it_module/`.

```text
clients/packages/get_it_module/
├── pubspec.yaml
└── lib/
    ├── get_it_module.dart                 # Ponto de exportação pública
    └── src/
        ├── injector.dart                  # Fachada Injector (factory/lazySingleton/singleton)
        ├── app_module.dart                # Contrato AppModule + installModules/collectRoutes
        ├── get_it_module_base.dart        # Contrato da rota GetItModule (path + page + binds)
        ├── get_it_module_scope.dart       # Widget interno de ciclo de vida do escopo
        └── inject.dart                    # Helper top-level inject<T>()
```

---

## 4. Configuração de Dependências (`pubspec.yaml`)

```yaml
name: get_it_module
description: Infraestrutura de injeção de dependências modular (escopo global + escopos de feature) via GetIt atrelado ao ciclo de vida do Flutter.
version: 2.0.0
publish_to: 'none'

environment:
  sdk: ^3.12.2
  flutter: ">=3.44.0"

dependencies:
  flutter:
    sdk: flutter

  # Localizador de serviços
  get_it: ^9.2.1
```

> Requisito de API do `get_it`: o design usa `pushNewScope`, `dropScope(scopeName)`, `hasScope(scopeName)` e `registerSingleton/registerLazySingleton/registerFactory` com callback `dispose`. Todos presentes no `get_it` 9.x (inalterados desde o 7.x). No `get_it` 9.0 o disposal passou a ser **estritamente LIFO** (o parâmetro `strictDisposalOrder` foi removido) — o que reforça o design de descarte por nome de escopo (`dropScope(scopeName)`). Mantém-se o `dropScope` protegido por `if (hasScope(...))`.

---

## 5. Código de Implementação do Package

### 5.1 Fachada de Provisão (`lib/src/injector.dart`)

```dart
import 'package:get_it/get_it.dart';

/// Fachada de registro de dependências sobre o GetIt.
///
/// Padroniza os três modos de provisão com semântica explícita, escondendo a
/// API crua do GetIt dos módulos. É instanciada internamente pelo package e
/// entregue ao módulo no momento dos `binds`; módulos nunca a criam à mão.
final class Injector {
  final GetIt _getIt;

  Injector(this._getIt);

  /// Nova instância a cada resolução. Não há descarte automático.
  void factory<T extends Object>(T Function() create) {
    _getIt.registerFactory<T>(create);
  }

  /// Instância única criada sob demanda (na primeira resolução).
  ///
  /// [dispose] é chamado quando o escopo dono é descartado — use-o para fechar
  /// Cubits (`dispose: (c) => c.close()`) e liberar recursos.
  void lazySingleton<T extends Object>(
    T Function() create, {
    void Function(T instance)? dispose,
  }) {
    _getIt.registerLazySingleton<T>(create, dispose: dispose);
  }

  /// Instância única criada imediatamente no registro.
  ///
  /// [dispose] é chamado quando o escopo dono é descartado.
  void singleton<T extends Object>(
    T instance, {
    void Function(T instance)? dispose,
  }) {
    _getIt.registerSingleton<T>(instance, dispose: dispose);
  }
}
```

### 5.2 Contrato do Módulo (`lib/src/app_module.dart`)

```dart
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

/// Registra os serviços globais de todos os [modules] no escopo-base do GetIt.
/// Chamar uma única vez no boot, antes de `runApp`.
void installModules(List<AppModule> modules) {
  final injector = Injector(GetIt.instance);
  for (final module in modules) {
    module.globalBinds(injector);
  }
}

/// Coleta todas as rotas expostas pelos [modules] (insumo para o `AppRouter`).
List<GetItModule> collectRoutes(List<AppModule> modules) =>
    [for (final module in modules) ...module.routes()];

/// Executa apenas as bootTasks por estágio — paralelo dentro do estágio,
/// sequencial entre estágios. Pressupõe que [installModules] já rodou (no
/// `main`). É o que a rota de splash chama. Ver construcao-bootstrap-inicializacao.md.
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
```

> O registro lazy desacopla **ordem de registro** de **ordem de criação**: por isso `installModules` é síncrono e sem ordem, e só os `init()` assíncronos (em `bootTasks`) respeitam estágios. **Duas formas de uso, exclusivas entre si:** (a) com splash em Flutter — `main` chama `installModules` e a rota `/` chama `runBootTasks`; (b) sem splash — `main` chama só `bootModules` antes do `runApp`. O monorepo adota (a).

### 5.3 Contrato da Rota (`lib/src/get_it_module_base.dart`)

```dart
import 'package:flutter/widgets.dart';

import 'get_it_module_scope.dart';
import 'injector.dart';

/// Contrato de uma **rota** (uma tela/fluxo) com escopo de DI próprio.
///
/// É a unidade de UI exposta por um [AppModule] em `routes()`. Descreve:
///  - [path]/[name]: a URL da rota (consumida pelo roteador);
///  - [page]: a tela raiz exibida quando a rota é aberta;
///  - [binds]: as dependências exclusivas desta tela, registradas em um escopo
///    isolado e descartadas quando a tela é fechada.
///
/// Serviços compartilhados NÃO entram aqui — eles são features de serviço,
/// expostas via [AppModule.globalBinds] no escopo global, e resolvidas via
/// [inject] (o escopo da rota fica acima do escopo-base).
abstract base class GetItModule {
  /// Caminho/URL desta rota (ex.: '/login', '/tenants').
  ///
  /// Consumido pelo roteador central (ver `navigation_module`) para montar a
  /// rota do go_router. É só uma String — o `get_it_module` não depende do
  /// go_router.
  String get path;

  /// Nome opcional da rota, para navegação por nome (go_router named routes).
  /// Quando nulo, navega-se por [path].
  String? get name => null;

  /// Tela raiz do módulo.
  Widget get page;

  /// Registra as dependências exclusivas da feature no escopo do módulo.
  ///
  /// Chamado uma única vez ao abrir o módulo. Tudo o que for criado aqui é
  /// descartado quando o módulo é fechado (pop da rota).
  void binds(Injector i);

  /// Resolve o módulo em um widget pronto para navegação, com o ciclo de vida
  /// do escopo do GetIt atrelado ao ciclo de vida da tela. O nome do escopo é
  /// gerado por **montagem** dentro do [GetItModuleScope] (não por instância do
  /// módulo), pois o roteador reaproveita a mesma instância entre navegações.
  Widget toRoute() => GetItModuleScope(module: this);
}
```

### 5.4 Widget Interno de Escopo (`lib/src/get_it_module_scope.dart`)

```dart
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';

import 'get_it_module_base.dart';
import 'injector.dart';

/// Widget interno que conecta o ciclo de vida da tela ao escopo do GetIt.
///
/// Em [initState] empilha um novo escopo nomeado e registra os binds da
/// feature. Em [dispose] descarta exatamente esse escopo pelo nome, chamando
/// o `dispose` de cada dependência local registrada.
///
/// O nome do escopo é gerado por **montagem** (a partir do `identityHashCode`
/// deste State), garantindo unicidade mesmo quando o roteador reaproveita a
/// mesma instância do módulo entre navegações ou empilha a mesma rota.
///
/// É construído pelo package via [GetItModule.toRoute]; os módulos de feature
/// nunca o instanciam diretamente.
class GetItModuleScope extends StatefulWidget {
  final GetItModule module;

  const GetItModuleScope({super.key, required this.module});

  @override
  State<GetItModuleScope> createState() => _GetItModuleScopeState();
}

class _GetItModuleScopeState extends State<GetItModuleScope> {
  final GetIt _getIt = GetIt.instance;

  /// Único por montagem deste widget.
  late final String _scopeName =
      '${widget.module.runtimeType}#${identityHashCode(this)}';

  @override
  void initState() {
    super.initState();
    // Novo escopo isolado, acima do escopo-base global: os registros a seguir
    // ficam atrelados a ele e enxergam os bindings globais por baixo.
    _getIt.pushNewScope(scopeName: _scopeName);
    widget.module.binds(Injector(_getIt));
  }

  @override
  void dispose() {
    // dropScope remove o escopo pelo nome (não depende da ordem da pilha),
    // evitando descartar o escopo errado em navegações não-LIFO (abas/replace).
    if (_getIt.hasScope(_scopeName)) {
      _getIt.dropScope(_scopeName);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.module.page;
}
```

### 5.5 Helper de Resolução (`lib/src/inject.dart`)

```dart
import 'package:get_it/get_it.dart';

/// Resolve uma dependência registrada, buscando do escopo de feature ativo até
/// o escopo-base global.
///
/// É a forma padrão de obter Cubits e serviços na UI, mantendo as telas
/// desacopladas da API direta do GetIt.
T inject<T extends Object>() => GetIt.instance.get<T>();
```

### 5.6 Arquivo de Exportação Principal (`lib/get_it_module.dart`)

```dart
library get_it_module;

// Superfície pública mínima: contratos + fachada + helper de resolução.
export 'src/app_module.dart';        // AppModule, BootStage, BootTask, installModules, collectRoutes, runBootTasks, bootModules
export 'src/get_it_module_base.dart'; // GetItModule (rota)
export 'src/injector.dart';
export 'src/inject.dart';

// get_it_module_scope.dart NÃO é exportado: é detalhe interno do package.
```

---

## 6. Integração nos Aplicativos e Módulos de Feature

### 6.1 Módulo de infra (só serviços globais, sem rotas)

```dart
import 'package:get_it_module/get_it_module.dart';
import 'package:api_client/api_client.dart';

/// Módulo de infraestrutura do app: serviços de vida longa, sem telas.
final class InfraModule extends AppModule {
  @override
  void globalBinds(Injector i) {
    i.singleton<Logger>(Logger());
    i.lazySingleton<ApiClient>(() => ApiClient());
  }
}
```

### 6.2 Módulo que expõe uma feature de serviço + uma rota

```dart
import 'package:get_it_module/get_it_module.dart';

/// Feature PÚBLICA exposta pelo login_module (consumida por outros módulos).
abstract interface class AuthService {
  Future<bool> login({required String email, required String password});
  bool get isAuthenticated;
}

final class LoginModule extends AppModule {
  /// Feature de serviço: a implementação de AuthService vai pro escopo global.
  @override
  void globalBinds(Injector i) {
    i.lazySingleton<AuthService>(() => AuthServiceImpl(api: inject<ApiClient>()));
  }

  /// Feature de UI: a rota /login.
  @override
  List<GetItModule> routes() => [LoginRoute()];
}
```

### 6.3 Rota (`GetItModule`) consumindo features globais

```dart
import 'package:get_it_module/get_it_module.dart';
import 'package:flutter/widgets.dart';

import 'presentation/login_page.dart';
import 'presentation/login_controller.dart';

final class LoginRoute extends GetItModule {
  @override
  String get path => '/login';

  @override
  Widget get page => const LoginPage();

  @override
  void binds(Injector i) {
    // AuthService vem do escopo global; o controller é exclusivo desta tela.
    i.lazySingleton<LoginController>(
      () => LoginController(auth: inject<AuthService>()),
      dispose: (controller) => controller.close(), // fechado ao sair da tela
    );
  }
}
```

> Convenção para controllers (Cubits): registre-os como `lazySingleton` com `dispose: (c) => c.close()`. Na prática, o `presentation_module` empacota esse padrão no atalho `i.controller<C>()` — use-o nas features. Aqui mostramos o primitivo equivalente, pois o `get_it_module` não depende de `bloc`.

### 6.4 Bootstrap no `main.dart` do app

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // O app COMPÕE os módulos que ele inclui.
  final modules = <AppModule>[
    InfraModule(),   // serviços de infra
    LoginModule(),   // expõe AuthService + rota /login
    // DashboardModule(), TenantModule(), ...
  ];

  // 1) registra os serviços globais de todos os módulos no escopo-base.
  installModules(modules);

  // 2) o AppRouter (navigation_module) agrega as rotas via collectRoutes(modules).
  runApp(SmartCoreAdminApp(modules: modules));
}
```

### 6.5 Abrindo a rota na navegação

A navegação é baseada em **go_router**, montada centralmente pelo `AppRouter` (ver `navigation_module`). O `AppRouter` recebe as rotas agregadas (`collectRoutes(modules)`) e cria cada `GoRoute` construindo `route.toRoute()`.

```dart
// No widget raiz do app, a partir da lista de módulos composta no main:
final router = AppRouter(
  initialLocation: '/login',
  routes: collectRoutes(modules), // achata as routes() de todos os AppModule
).build();

// Navegação a partir de qualquer lugar (extensions do go_router)
context.go('/tenants');     // substitui a pilha (URL muda)
context.push('/tenants');   // empilha sobre a atual
```

> Parâmetros de rota (path/query) e objetos (`extra`) são lidos **dentro da page** via `GoRouterState.of(context)`, sem a rota precisar conhecê-los — o que mantém o `get_it_module` livre do go_router. Detalhes em [construcao-modulo-navigation.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-modulo-navigation.md).

### 6.6 Consumo na UI da rota

O `inject<T>()` resolve qualquer dependência do escopo ativo (rota → global). Abaixo, o uso direto do helper; nas features, a página estende `ModulePage` (do `presentation_module`), que já faz esse `inject` e a renderização por estado.

```dart
import 'package:get_it_module/get_it_module.dart';
import 'package:dependencies_module/dependencies_module.dart';
import 'package:flutter/material.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Resolve do escopo ativo (feature → global), sem injeção manual por context.
    final controller = inject<LoginController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: BlocBuilder<LoginController, ViewState<Session>>(
        bloc: controller,
        builder: (context, state) => const Center(child: Text('Formulário de Login')),
      ),
    );
  }
}
```

---

## 7. Guia de Decisão: onde e como registrar

| Pergunta | Resposta |
| :--- | :--- |
| O binding é usado por **mais de uma** rota/módulo? | Exponha-o no `globalBinds` do **módulo dono** (escopo global). |
| O binding é **exclusivo** de uma tela? | Registre nos `binds` da **rota** (`GetItModule`). |
| É um **Cubit** ou tem estado/recurso a liberar? | `lazySingleton` com `dispose`. |
| É **stateless** e barato, e cada uso quer instância nova? | `factory`. |
| Precisa existir **já no boot** (eager)? | `singleton`. |
| Pode ser criado **só quando usado**? | `lazySingleton`. |

---

## 8. Ciclo de Vida (resumo)

```text
BOOT do app
  └─ installModules([InfraModule(), LoginModule(), ...])
       └─ roda globalBinds de cada módulo → serviços no escopo-base

push da rota  ──▶ initState do GetItModuleScope
                  ├─ pushNewScope(scopeName)        // escopo isolado, acima do global
                  └─ route.binds(Injector)          // dependências da tela

build           ──▶ renderiza route.page
                     inject<T>() resolve rota → global

pop da rota   ──▶ dispose do GetItModuleScope
                  └─ dropScope(scopeName)           // descarta a rota
                                                    // (dispose dos Cubits/Usecases)

ENCERRAMENTO do app
  └─ escopo-base global é liberado pelo runtime
```

Pontos-chave do design:

- **Módulo (`AppModule`) expõe features** → serviços globais (`globalBinds`) + rotas (`routes()`); features consumidas entre módulos via `inject<T>()`.
- **Dois níveis de escopo** → serviço compartilhado no global (sem duplicação), efêmero na rota.
- **`Injector` com três modos** → semântica de provisão explícita, sem vazar o GetIt.
- **Escopo nomeado por montagem** → sem colisão mesmo com a mesma rota empilhada duas vezes ou com a instância reaproveitada pelo roteador.
- **`dropScope` por nome** → robusto contra navegação não-LIFO.
- **`inject<T>()`** → resolução única e desacoplada em todo o app.
- **`path`/`name` na rota** → navegação por URL (go_router) montada centralmente pelo `AppRouter`, sem o package depender do go_router.

---

## 9. Inicialização Assíncrona e Evoluções Futuras

A **inicialização assíncrona ordenada** de dependências globais (abrir banco/storage, conectar `ApiClient`, restaurar sessão) **já é especificada**: cada `AppModule` declara `bootTasks()` com `BootStage`, e `runBootTasks`/`bootModules` as executam (paralelo dentro do estágio, sequencial entre estágios). Detalhes em [construcao-bootstrap-inicializacao.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-bootstrap-inicializacao.md).

Fora do escopo da v2.0:

- **Sub-rotas por módulo**: múltiplas telas internas compartilhando o mesmo escopo de feature, com a `page` atual virando a rota raiz.
- **Binds assíncronos por rota** (`Future<void> bindsAsync` no `GetItModuleScope`): inicialização atrelada à **abertura de uma tela específica** (não ao boot do app), com loading local gerenciado pelo escopo — complementa o `bootTasks` (que é boot global).
- **Escopos intermediários compartilhados**: para um grupo de features que compartilham estado entre si mas não com o app inteiro (ex.: um fluxo multi-tela), um nível de escopo opcional entre o global e a feature.
