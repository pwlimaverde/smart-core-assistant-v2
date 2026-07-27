# Arquitetura de Modelagem Frontend — Monorepo Flutter/Dart

Este documento define os padrões e diretrizes arquiteturais para o desenvolvimento de aplicações frontend em Flutter/Dart no monorepo `smart-core-assistant-v2`. O objetivo é garantir que todas as aplicações compartilhem uma base sólida, performática, desacoplada e 100% modular, apoiada em três infraestruturas padronizadas: **`get_it_module`** (injeção de dependências e ciclo de vida), **`presentation_module`** (gerência de estado com `BaseController`/`ViewState` sobre Cubit) e **`navigation_module`** (navegação por URL com go_router).

---

## 1. Filosofia de Arquitetura e Separação de Responsabilidades

Para garantir o máximo desempenho, portabilidade e independência de compilação, o frontend do projeto é dividido em quatro categorias claras de pastas com propósitos técnicos estritos: **Apps (Cascas)**, **Módulos (Flutter Compartilhado)**, **Packages (Dart Puro)** e **Plugins (Código Nativo)**.

### Tabela Comparativa de Componentes

| Categoria | Stack Base | Depende de `flutter`? | Objetivo Principal | Exemplo |
| :--- | :--- | :--- | :--- | :--- |
| **Apps (Cascas)** | Flutter Executável | Sim | Servir de ponte e casca de compilação para plataformas nativas ou Web. | `smart-core-admin` |
| **Módulos** | Flutter Library | Sim | Telas compartilhadas, design system, widgets e controle de estado do Flutter. | `design_system_module` |
| **Packages** | Dart Puro | **Não** | Lógica de negócios pura, clientes gRPC, DTOs e utilitários não visuais. | `api_client` |
| **Plugins** | Flutter Plugin | Sim | Comunicação direta com APIs nativas dos S.O. (C++, Java/Kotlin, Swift). | `local_notification_plugin` |

---

## 2. Estrutura de Diretórios (`clients/`)

A organização do monorepo segue a divisão física destas responsabilidades dentro do diretório `clients/`:

```
clients/
├── apps/                           # APLICATIVOS (Cascas de Compilação / Pontes)
│   ├── smart-core-admin/           # App executável para Web Admin (Superusuário)
│   ├── smart-core-windows-tenant/  # App executável para Windows Tenant (Desktop)
│   └── smart-core-web-tenant/      # App executável para Web Tenant (Futuro)
│
├── modulos/                        # MÓDULOS (Flutter SDK / UI Compartilhada)
│   ├── dependencies_module/        # Agregador e Exportador Central de Dependências
│   ├── design_system_module/       # Design System comum (temas, cores, fontes, widgets base)
│   ├── core_module/                # InfraModule (AppModule de serviços globais) + config de UI
│   ├── presentation_module/        # Bases de apresentação (ViewState, BaseController, ModulePage)
│   ├── navigation_module/          # Navegação go_router (AppRouter + ModuleRoute)
│   └── login_module/               # Telas e controladores de autenticação (Feature)
│
├── packages/                       # PACKAGES (Dart Puro / Pacotes de Infraestrutura)
│   ├── get_it_module/              # Package de controle e gestão de DI modular
│   ├── app_config/                 # AppConfig imutável (flavor, endpoints, flags) por ambiente
│   ├── api_client/                 # Cliente gRPC/gRPC-Web único de comunicação
│   └── domain_models/              # Modelos de dados e DTOs gerados via Protobuf
│
└── plugins/                        # PLUGINS (Código Nativo / Específicos por Plataforma)
    └── local_hardware_plugin/      # Plugin para acessar chamadas de hardware do Windows (C++)
```

### 2.1 Configuração do Workspace (Pub Workspaces + Melos)

O monorepo usa **Pub Workspaces** — o mecanismo nativo do Dart (a partir do SDK 3.6) para
resolver vários pacotes juntos, com um **único** `pubspec.lock` e `.dart_tool/` na raiz de
`clients/`. O **Melos** (≥ 7.x, que adota os Pub Workspaces nativos) entra apenas para scripts
de conveniência (`analyze`, `test`) — não há `melos.yaml` standalone; sua configuração vive na
seção `melos:` do `pubspec.yaml` raiz.

**`clients/pubspec.yaml` (raiz do workspace):**

```yaml
name: smart_core_clients
publish_to: 'none'
environment:
  sdk: ^3.12.2

# Lista dos pacotes membros (relativos à raiz).
workspace:
  - packages/app_config
  - packages/domain_models
  - packages/get_it_module
  - packages/api_client
  - modulos/presentation_module
  - modulos/design_system_module
  - modulos/navigation_module
  - modulos/core_module
  - modulos/dependencies_module
  - modulos/initial_loading_module
  - apps/smart-core-admin

dev_dependencies:
  melos: ^7.8.2

melos:
  name: smart_core_clients
  scripts:
    analyze: { run: melos exec -- flutter analyze . }
    test: { run: melos exec --dir-exists=test -- flutter test }
```

**Cada pacote membro** declara `resolution: workspace` (além do `environment.sdk` compatível):

```yaml
name: app_config
environment:
  sdk: ^3.12.2
resolution: workspace
```

> As dependências internas por `path:` continuam válidas — o workspace as resolve localmente.
> `flutter pub get` (ou `dart pub get`) em **qualquer** nível atualiza o lock único da raiz;
> `melos run analyze` / `melos run test` varrem todos os pacotes.

---

## 3. Detalhamento Técnico e Regras de Construção

### 3.1 Apps (Cascas de Compilação)
**O que são:** Os pontos de entrada de compilação que encapsulam o código nativo específico de cada plataforma (pastas `web/`, `windows/`, etc.).

**Regras estritas:**
- **Zero Lógica de Negócio:** Não devem conter telas ou controladores no diretório `lib/`.
- **Main Mínima:** O arquivo `lib/main.dart` deve apenas compor a lista de `AppModule` que o app inclui, registrar seus serviços globais uma única vez (`installModules(modules)`), montar o roteador via `AppRouter(routes: collectRoutes(modules))` + guards e subir um `MaterialApp.router`.
- **Dependência Única:** Devem depender do `dependencies_module` local via path relativo no `pubspec.yaml` e apenas utilizar o que é exportado por ele.

---

### 3.2 Módulos (Flutter SDK / UI Compartilhada)
**O que são:** Bibliotecas reutilizáveis que dependem do SDK do Flutter. Servem para construir interfaces de usuário, layouts, reatividade visual (Cubit) e fluxos comuns que utilizam a árvore de widgets.

**Injeção de Dependências e Ciclo de Vida (dois níveis de escopo):**

- Um **módulo** estende `AppModule` e expõe **features**: serviços globais (`globalBinds`) e rotas (`routes()`). O app compõe os módulos; `installModules` registra os serviços globais de todos e `collectRoutes` agrega as rotas.
- A injeção é organizada em **dois níveis**: um **escopo global** (serviços expostos pelos `globalBinds` dos módulos) com o que é compartilhado, e **escopos de rota** efêmeros, criados ao abrir uma tela. Ambos fornecidos pelo package **`get_it_module`**.
- Os módulos não usam a API crua do GetIt: declaram dependências pela fachada `Injector` (`factory` / `lazySingleton` / `singleton`).
- Cada **rota** estende o contrato `GetItModule`, declarando `path`, `page` e `binds`.
- **Regra de não-duplicação:** se um binding é usado por mais de uma rota/módulo, ele sobe para o escopo **global** (via `globalBinds` do módulo dono) — não se duplica. O GetIt resolve do escopo da rota até o escopo-base, então o global é visível em qualquer rota.
- As dependências exclusivas de UI (Cubits e Usecases de tela) são registradas só quando a página do módulo é aberta e limpas automaticamente quando a tela é fechada.

**Estado e Renderização (camada de apresentação):**

- A gerência de estado e a renderização por estado são padronizadas pelo módulo **`presentation_module`**, que fornece o estado genérico `ViewState<T>`, a base `BaseController<T>` (integrada ao `return_success_or_error`) e as bases de página `ModulePage`/`ViewStateBuilder`.
- Os controllers estendem `BaseController<T>` e usam `execute()` para rodar usecases (`ReturnSuccessOrError<T>`) sem boilerplate de try/catch/emit. As páginas estendem `ModulePage` ou usam `ViewStateBuilder`, resolvendo o controller via `inject<C>()`.
- O `GetItModule` da feature amarra as duas infraestruturas: declara a `page` (que estende as bases de apresentação) e registra o controller nos `binds` via o atalho `i.controller<C>()`.
- Especificação detalhada em [construcao-modulo-presentation.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-modulo-presentation.md).

**Navegação (go_router):**

- A navegação é baseada em **go_router** (URL-first, ideal para o web admin), padronizada pelo módulo **`navigation_module`**.
- Cada **rota** (`GetItModule`) declara seu `path` (e `name` opcional). O `AppRouter` recebe as rotas agregadas (`collectRoutes(modules)`) num único `GoRouter`, com guards de autenticação via `redirect`.
- A casca de escopo de DI (`toRoute()`) é construída pela rota, então o escopo nasce ao entrar e é descartado ao sair. Parâmetros de rota são lidos na page via `GoRouterState.of(context)`.
- O `get_it_module` **não** depende do go_router: a conversão rota→`GoRoute` é uma extension isolada no `navigation_module`. Especificação em [construcao-modulo-navigation.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-modulo-navigation.md).
- A inicialização assíncrona ordenada de dependências (abrir storage, conectar `ApiClient`, restaurar sessão) roda numa **rota de splash** (`/`), com as demais rotas presas por uma **barreira de boot** (`BootState` + `refreshListenable`) até concluir. Padrão em [construcao-bootstrap-inicializacao.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-bootstrap-inicializacao.md).

---

### 3.3 Packages (Dart Puro)
**O que são:** Bibliotecas puramente lógicas em Dart que **não** dependem do SDK do Flutter. Isso garante que o código de regras de negócios, modelagem, transporte e algoritmos possa ser compilado em qualquer ambiente Dart puro (incluindo consoles e testes unitários instantâneos), sem o peso ou a necessidade do pipeline de renderização do Flutter.

**Regras estritas:**
- **Sem imports do Flutter:** É expressamente proibido importar qualquer pacote que dependa do Flutter SDK (como `package:flutter/material.dart` ou `package:flutter/widgets.dart`).
- **Versão Limpa de Dart:** O `pubspec.yaml` não deve listar o `flutter:` sob dependências. Deve declarar apenas dependências Dart puras (ex: `http`, `grpc`, `protobuf`, `get_it`).

---

### 3.4 Plugins (Pontes Nativas)
**O que são:** Pacotes do Flutter que estendem a capacidade do framework fazendo a ponte entre o Dart e as APIs nativas do sistema operacional por meio de *MethodChannels* ou FFI. Devem ser criados apenas quando há a necessidade real de escrever código nativo de baixo nível para Windows (C++), Android (Java/Kotlin) ou iOS (Swift/Objective-C).

---

## 4. O Package de Infraestrutura Modular (`get_it_module`)

Para evitar a duplicação de lógica e manter a conformidade com as regras de Clean Code, a lógica de injeção baseada em escopos é empacotada no package **`get_it_module`**. Os módulos de negócio apenas o importam para herdar seus comportamentos e contratos.

*A especificação técnica detalhada de implementação deste pacote está descrita em [construcao-package-get-it-module.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-package-get-it-module.md).*

### 4.1 Módulo (`AppModule`) que expõe um serviço + uma rota
Um **módulo** estende `AppModule` e expõe **features**: serviços globais (`globalBinds`) consumidos por outros módulos, e rotas (`routes()`). Cada **rota** é um `GetItModule` (`path` + `page` + `binds`) — o package resolve escopo, ciclo de vida e rota automaticamente.

```dart
import 'package:get_it_module/get_it_module.dart';
import 'package:dependencies_module/dependencies_module.dart';

import 'data/services/auth_service_impl.dart';
import 'domain/services/auth_service.dart';
import 'presentation/routes/login_route.dart';

/// Módulo reutilizável: expõe AuthService (serviço) + a rota /login.
final class LoginModule extends AppModule {
  @override
  void globalBinds(Injector i) {
    // Feature de serviço: implementação no escopo global, vista por outros módulos.
    i.lazySingleton<AuthService>(() => AuthServiceImpl(api: inject<ApiClient>()));
  }

  @override
  List<GetItModule> routes() => [LoginRoute()];
}

/// Rota: uma tela com escopo de DI próprio.
final class LoginRoute extends GetItModule {
  @override
  String get path => '/login';

  @override
  Widget get page => const LoginPage();

  @override
  void binds(Injector i) {
    // controller<>(): lazySingleton + close no dispose. Consome a feature global.
    i.controller<LoginController>(() => LoginController(auth: inject<AuthService>()));
  }
}
```

O app compõe a lista de `AppModule`; `installModules` registra os serviços globais e o `AppRouter` agrega as rotas via `collectRoutes`. Detalhes em [construcao-modulo-navigation.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-modulo-navigation.md) e [anatomia-modulo.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/anatomia-modulo.md).

### 4.2 Consumo na UI da Feature
A página estende `ModulePage` (do `presentation_module`), que resolve o controller via `inject<C>()` e renderiza conforme o `ViewState`. A subclasse implementa apenas `onSuccess`:

```dart
import 'package:dependencies_module/dependencies_module.dart';
import 'package:flutter/material.dart';

import '../controllers/login_controller.dart';

class LoginPage extends ModulePage<LoginController, Session> {
  const LoginPage({super.key});

  @override
  Widget onSuccess(BuildContext context, Session session) {
    return Center(child: Text('Bem-vindo, ${session.userName}'));
  }
}
```

O padrão completo de controller, estado e teste está na [seção 7](#7-preceitos-de-clean-code-estado-padronizado-e-tdd) e em [construcao-modulo-presentation.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-modulo-presentation.md).

---

## 5. Comunicação entre Módulos e Configurações de Dependências

A comunicação entre os componentes do monorepo é organizada em uma **hierarquia em cascata** gerida centralmente pelo `dependencies_module`.

### 5.1 O Papel do `dependencies_module`
Este módulo atua como a **âncora de versões** do ecossistema. Ele centraliza as dependências externas e exporta-as de forma unificada:

1. **Configuração de Pubspec (`dependencies_module/pubspec.yaml`):**
   ```yaml
   name: dependencies_module
   publish_to: 'none'
   version: 0.0.1

   environment:
     sdk: ^3.12.2

   resolution: workspace

   dependencies:
     flutter:
       sdk: flutter

     # Módulos Locais Relativos
     design_system_module:
       path: ../design_system_module
     core_module:
       path: ../core_module
     presentation_module:
       path: ../presentation_module # Bases de estado, controller e página
     navigation_module:
       path: ../navigation_module # Navegação go_router (AppRouter, ModuleRoute)

     # Pacotes Dart Puros Locais (DI e Modelagem)
     get_it_module:
       path: ../../packages/get_it_module # Fornece AppModule, GetItModule, Injector e inject
     api_client:
       path: ../../packages/api_client
     domain_models:
       path: ../../packages/domain_models

     # Pacotes Externos Unificados
     get_it: ^9.2.1
     flutter_bloc: ^9.1.1
     bloc: ^9.2.1
     intl: ^0.20.2
     uuid: ^4.5.3
     return_success_or_error: ^2.0.0 # pub.dev — usecase (process), Datasource, AppError, Result selado
   ```

2. **Exposição no Arquivo de Entrada (`lib/dependencies_module.dart`):**
   ```dart
   // Módulos internos
   export 'package:design_system_module/design_system_module.dart';
   export 'package:core_module/core_module.dart';
   export 'package:presentation_module/presentation_module.dart'; // ViewState, BaseController, páginas
   export 'package:navigation_module/navigation_module.dart'; // AppRouter, ModuleRoute, go_router

   // Pacotes de infraestrutura e Dart Puros do monorepo
   export 'package:get_it_module/get_it_module.dart'; // Exporta AppModule, GetItModule, Injector e inject
   export 'package:api_client/api_client.dart';
   export 'package:domain_models/domain_models.dart';

   // Dependências externas de infraestrutura e reatividade
   export 'package:flutter/material.dart';
   export 'package:get_it/get_it.dart';
   export 'package:flutter_bloc/flutter_bloc.dart';
   export 'package:bloc/bloc.dart';
   export 'package:return_success_or_error/return_success_or_error.dart'; // Result type e AppError
   export 'package:intl/intl.dart' hide TextDirection; // Evita conflito com material.dart
   export 'package:uuid/uuid.dart';
   ```

---

## 6. Novo Sistema de Variáveis Privadas (Dart 3.12)

A partir do Dart 3.12, é adotado o padrão de **Private Named Parameters** em construtores para diminuir o boilerplate de inicialização de variáveis privadas (`_campo`).

### Exemplo de Uso:
```dart
class AppController {
  final String _apiEndpoint;
  final bool _debugMode;

  AppController({
    required this._apiEndpoint,
    required this._debugMode,
  });

  void initialize() {
    print('Conectando em $_apiEndpoint com debug: $_debugMode');
  }
}
```

---

## 7. Preceitos de Clean Code, Estado Padronizado e TDD

A gerência de estado da UI é padronizada pelo módulo `presentation_module`: o estado genérico `ViewState<T>`, a base `BaseController<T>` (um `Cubit<ViewState<T>>` com `execute()`) e as bases de página. Os controllers consomem usecases que retornam `ReturnSuccessOrError<T>` (do package `return_success_or_error`), o que elimina o boilerplate de `try/catch/emit`.

A especificação detalhada das bases está em [construcao-modulo-presentation.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-modulo-presentation.md). Os exemplos abaixo mostram o padrão aplicado.

### 7.1 Controller (estende `BaseController`, sem boilerplate)

```dart
import 'package:presentation_module/presentation_module.dart';
import 'package:domain_models/domain_models.dart';

/// Controller de tela: Dart puro, testável sem Flutter.
/// O estado é sempre ViewState<T>; aqui T = List<Tenant>.
final class TenantController extends BaseController<List<Tenant>> {
  final GetTenantsUsecase _getTenants;

  TenantController({required GetTenantsUsecase getTenants})
      : _getTenants = getTenants;

  // execute() emite Loading e mapeia ReturnSuccessOrError → Success/Error.
  Future<void> loadTenants() => execute(() => _getTenants(NoParams()));
}
```

### 7.2 Consumo de Estado na UI (View)

Variante opinativa com `ModulePage` (a subclasse só implementa `onSuccess`):

```dart
class TenantListPage extends ModulePage<TenantController, List<Tenant>> {
  const TenantListPage({super.key});

  @override
  Widget onSuccess(BuildContext context, List<Tenant> tenants) {
    return ListView.builder(
      itemCount: tenants.length,
      itemBuilder: (_, i) => ListTile(title: Text(tenants[i].name)),
    );
  }
}
```

Variante flexível com `ViewStateBuilder` (Scaffold/AppBar/FAB próprios):

```dart
class TenantListPage extends StatelessWidget {
  const TenantListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = inject<TenantController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Tenants')),
      floatingActionButton: FloatingActionButton(
        onPressed: controller.loadTenants,
        child: const Icon(Icons.refresh),
      ),
      body: ViewStateBuilder<TenantController, List<Tenant>>(
        controller: controller,
        onSuccess: (_, tenants) => ListView.builder(
          itemCount: tenants.length,
          itemBuilder: (_, i) => ListTile(title: Text(tenants[i].name)),
        ),
      ),
    );
  }
}
```

### 7.3 Convenção de Escrita de Testes Unitários de Controller (`bloc_test`)

O `execute()` torna o teste direto: mocka-se o usecase para devolver `Success`/`Failure` e verifica-se a sequência de `ViewState`. Melhor ainda: monte a cadeia real (`Datasource → Repository → Usecase`) trocando só o stub gRPC, e o mesmo teste cobre a conversão e o `mapError`.

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:presentation_module/presentation_module.dart';

class MockGetTenantsUsecase extends Mock implements GetTenantsUsecase {}

void main() {
  late MockGetTenantsUsecase usecase;
  late TenantController controller;

  setUp(() {
    usecase = MockGetTenantsUsecase();
    controller = TenantController(getTenants: usecase);
  });

  tearDown(() => controller.close());

  blocTest<TenantController, ViewState<List<Tenant>>>(
    'emite [Loading, Success] quando o usecase retorna Success',
    build: () {
      when(() => usecase(any())).thenAnswer(
        (_) async => Success([Tenant(id: '1', name: 'Tenant A')]),
      );
      return controller;
    },
    act: (c) => c.loadTenants(),
    expect: () => [
      isA<LoadingState<List<Tenant>>>(),
      isA<SuccessState<List<Tenant>>>().having((s) => s.data, 'data', hasLength(1)),
    ],
    verify: (_) => verify(() => usecase(any())).called(1),
  );

  blocTest<TenantController, ViewState<List<Tenant>>>(
    'emite [Loading, Error] quando o usecase retorna Failure',
    build: () {
      when(() => usecase(any())).thenAnswer(
        (_) async => const Failure(TenantsIndisponivel()),
      );
      return controller;
    },
    act: (c) => c.loadTenants(),
    expect: () => [
      isA<LoadingState<List<Tenant>>>(),
      isA<ErrorState<List<Tenant>>>()
          .having((s) => s.error.message, 'message', contains('Erro de API')),
    ],
  );
}
```

---

## 8. Configuração por App e Ambientes (`AppConfig` / Flavors)

Cada app tem necessidades de configuração distintas (endpoints, transporte, flags). Em especial, o **Windows Tenant usa transporte TCP** enquanto o **Web Admin** usa HTTP/gRPC-Web. Isso é centralizado num `AppConfig` imutável, injetado no escopo global no boot.

### 8.1 O contrato `AppConfig`

Vive em um **package Dart puro** (ex.: `app_config`), para ser importável por apps e pelo `core_module` sem violar as regras de dependência.

```dart
enum AppFlavor { dev, staging, prod }

final class AppConfig {
  final AppFlavor flavor;
  final String apiEndpoint;   // ex.: 'https://api...' ou 'tcp://host:50051'
  final bool enableLogging;

  const AppConfig({
    required this.flavor,
    required this.apiEndpoint,
    this.enableLogging = false,
  });

  bool get isProd => flavor == AppFlavor.prod;
}
```

### 8.2 Injeção no escopo global

O `InfraModule` (um `AppModule` sem rotas) **recebe** o `AppConfig` e o usa para construir os serviços de infra (ex.: o endpoint do `ApiClient`). Assim a configuração não é um singleton estático escondido — é uma dependência explícita.

```dart
final class InfraModule extends AppModule {
  final AppConfig config;
  InfraModule(this.config);

  @override
  void globalBinds(Injector i) {
    i.singleton<AppConfig>(config);
    i.lazySingleton<ApiClient>(() => ApiClient(endpoint: config.apiEndpoint));
  }
}
```

### 8.3 Flavors via entrypoints

Cada ambiente é um entrypoint que monta seu `AppConfig` e chama um bootstrap comum. Evita `if (flavor == ...)` espalhado e permite builds distintos (`flutter run -t lib/main_dev.dart`).

```dart
// lib/bootstrap.dart  (comum a todos os flavors)
Future<void> bootstrap(AppConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();
  // O app compõe seus módulos; InfraModule injeta a config nos serviços globais.
  final modules = <AppModule>[
    InfraModule(config), LoginModule(), InitialLoadingModule(), /* ... */
  ];
  // Registro síncrono (lazy) dos globais; o init assíncrono ordenado roda na
  // rota de splash via runBootTasks — ver construcao-bootstrap-inicializacao.md.
  installModules(modules);
  GetIt.instance.registerSingleton<List<AppModule>>(modules);
  runApp(SmartCoreAdminApp(modules: modules));
}

// lib/main_dev.dart
void main() => bootstrap(const AppConfig(
      flavor: AppFlavor.dev,
      apiEndpoint: 'tcp://localhost:50051', // Windows Tenant: TCP
      enableLogging: true,
    ));

// lib/main_prod.dart
void main() => bootstrap(const AppConfig(
      flavor: AppFlavor.prod,
      apiEndpoint: 'https://api.smartcore.app',
    ));
```

> Endpoints sensíveis podem vir de `String.fromEnvironment('API_ENDPOINT')` (via `--dart-define`) em vez de hardcoded, mantendo segredos fora do código.

---

## 9. Mapa de Padrões Especificados

Toda a padronização do frontend está detalhada nos documentos abaixo. **Não há pendências em aberto** — os itens antes listados como "próximas fases" (G/H/I) foram especificados:

| Tema | Documento | Resolve |
| :--- | :--- | :--- |
| Infra de DI modular (escopos, `AppModule`/`GetItModule`, `Injector`) | [construcao-package-get-it-module.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-package-get-it-module.md) | — |
| Apresentação (`ViewState`, `BaseController`, `ModulePage`) | [construcao-modulo-presentation.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-modulo-presentation.md) | — |
| Navegação (go_router, `AppRouter`, guards, barreira de boot) | [construcao-modulo-navigation.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-modulo-navigation.md) | — |
| Anatomia de um módulo (features, camadas, regras de dependência) | [anatomia-modulo.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/anatomia-modulo.md) | — |
| **Regra de negócio da feature com `return_success_or_error` v2.0.0** (parameters, datasource, usecase `process`, fetch→short-circuit→process, isolate só no process, testes) | [construcao-feature-com-return-success-or-error.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-feature-com-return-success-or-error.md) | — |
| **Bootstrap em estágios / splash (init assíncrono ordenado)** | [construcao-bootstrap-inicializacao.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-bootstrap-inicializacao.md) | **H** |
| **Apresentação de erro + i18n** | [construcao-apresentacao-erro-i18n.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-apresentacao-erro-i18n.md) | **G** |
| **Design System (tokens, tema, widgets base) + aplicação do tema** | [construcao-modulo-design-system.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-modulo-design-system.md) | **I** |

> Ao surgir um novo eixo de padronização, criar um `construcao-*.md` próprio nesta pasta e referenciá-lo aqui — mantendo este mapa como índice único da modelagem frontend.
