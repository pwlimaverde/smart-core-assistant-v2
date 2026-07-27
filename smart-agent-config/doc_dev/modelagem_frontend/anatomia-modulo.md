# Anatomia de um Módulo

Este documento padroniza o que é um **módulo** no monorepo `smart-core-assistant-v2`, o que ele **expõe**, sua **estrutura física** e as **regras de dependência** entre módulos. Complementa os docs de infraestrutura ([get_it_module](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-package-get-it-module.md), [presentation_module](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-modulo-presentation.md), [navigation_module](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-modulo-navigation.md)).

---

## 1. Conceito: Módulo, Feature e Rota

- **Módulo** = unidade **independente e reutilizável** (`login_module`, `design_system_module`). Pode ser aproveitada em diferentes apps/contextos. Estende `AppModule`.
- **Feature** = uma **capacidade que o módulo expõe** ao app e a outros módulos. Há dois tipos:
  - **Feature de serviço** (programática): uma **interface pública** cuja implementação vive no **escopo global**. Ex.: `login_module` expõe `AuthService` com `login(...)`/`isAuthenticated`, consumido por outros módulos.
  - **Feature de rota** (UI): uma tela/fluxo. É um `GetItModule` (escopo de DI por tela). Um módulo pode expor **várias rotas**.
- **Rota** = a unidade de UI (`GetItModule`): `path` + `page` + `binds`.

> O módulo é a “caixa” reutilizável; as features são o que ela **expõe pela porta da frente** (`lib/<módulo>.dart`). O `src/` é interno e privado.

```text
login_module  (AppModule)
 ├─ expõe FEATURE de serviço:  AuthService     → escopo GLOBAL (globalBinds)
 └─ expõe FEATURE de rota:     /login (rota)   → escopo de tela (routes())
        ▲
        │ consome AuthService via inject<AuthService>()
 dashboard_module (AppModule)
 └─ expõe FEATURE de rota: /dashboard
```

---

## 2. Estrutura de Pastas de um Módulo

Cada módulo é um **módulo Flutter** em `clients/modulos/<nome>_module/`. A organização interna é **feature-first**: tudo em `src/` é agrupado por **feature** (`src/features/<feature>/`), e cada feature traz suas camadas (Clean Architecture). Um módulo pode conter **uma ou mais features**. Layout canônico (exemplo `login_module`, com a feature `login` que expõe **um serviço + uma rota**):

```text
clients/modulos/login_module/
├── pubspec.yaml
├── lib/
│   ├── login_module.dart                       # API PÚBLICO: classe LoginModule + AuthService
│   └── src/
│       ├── login_module.dart                   # AppModule: globalBinds + routes()
│       └── features/
│           └── login/                          # FEATURE auto-contida
│               ├── domain/                     # REGRA DE NEGÓCIO (contratos + usecases)
│               │   ├── errors/
│               │   │   └── auth_errors.dart          # sealed <Feature>Error + casos concretos
│               │   ├── services/
│               │   │   └── auth_service.dart         # interface PÚBLICA (feature de serviço)
│               │   ├── parameters/
│               │   │   └── login_parameters.dart     # extends Parameters (só dados)
│               │   ├── model/                        # objetos de domínio processados (sendable) — se houver
│               │   └── usecases/
│               │       └── login_usecase.dart        # extends UsecaseBaseCallData<TValue, TData, TParams, TError>
│               │
│               ├── data/                       # FONTES EXTERNAS + implementações
│               │   ├── datasources/
│               │   │   └── login_grpc_datasource.dart # implements Datasource<TData, TParams> (só I/O, sem try/catch)
│               │   ├── repositories/
│               │   │   └── login_repository.dart      # extends RepositoryBase + mapError (fronteira)
│               │   └── services/
│               │       └── auth_service_impl.dart     # implementação de AuthService
│               │
│               └── presentation/              # UI + ESTADO
│                   ├── routes/
│                   │   └── login_route.dart          # GetItModule (path + page + binds)
│                   ├── controllers/
│                   │   └── login_controller.dart     # extends BaseController<T>
│                   ├── pages/
│                   │   └── login_page.dart           # extends ModulePage<C, T>
│                   └── widgets/
│                       └── login_form.dart
│
└── test/
    └── features/login/
        ├── domain/usecases/login_usecase_test.dart
        └── presentation/controllers/login_controller_test.dart
```

Regras de organização:

- **Feature-first (padrão do projeto inteiro):** todo código de negócio/UI vive em `src/features/<feature>/` com as três camadas. Módulos só de infra (ex.: `core_module`) podem não ter `features/`, mas todo módulo de domínio segue este layout.
- O **export público** (`lib/login_module.dart`) expõe **só** as features: a classe do módulo e as **interfaces** de serviço. Tudo em `src/` é privado.
- **Entidades/DTOs compartilhados** vivem no package `domain_models` (protobuf). A feature só cria tipos próprios (em `domain/model/`) quando exclusivos dela — sempre **imutáveis e sendable** (podem cruzar a fronteira de um isolate no `process`).
- **Repository é obrigatório** (v3 da lib): o usecase depende de `Repository`, não de `Datasource`. É a fronteira que traduz exceção técnica em erro de domínio (`mapError`) — sem ela, o `Datasource` voltaria a conhecer o erro de negócio.
- **Um `Datasource`/`Repository`/`Usecase` por operação.** Quando o que varia é a **plataforma** (Web × desktop), acrescente um **gateway agregado** em `domain/gateways/` e ponha os datasources em cima dele — ver §8 do doc da lib.
- **Erro fechado por feature**: `sealed class <Feature>Error extends AppError` em `domain/errors/`. Nada de erro global compartilhado (o `domain_models` só expõe os **marcadores** transversais).

---

## 3. O API Público do Módulo

```dart
// lib/login_module.dart
library login_module;

export 'src/login_module.dart' show LoginModule;          // o módulo (AppModule)
export 'src/domain/services/auth_service.dart' show AuthService; // feature de serviço exposta
```

```dart
// src/login_module.dart
import 'package:dependencies_module/dependencies_module.dart';

import 'data/datasources/auth_grpc_datasource.dart';
import 'data/services/auth_service_impl.dart';
import 'domain/services/auth_service.dart';
import 'presentation/routes/login_route.dart';

final class LoginModule extends AppModule {
  /// Feature de serviço: implementação de AuthService no escopo GLOBAL,
  /// consumível por qualquer outro módulo via inject<AuthService>().
  @override
  void globalBinds(Injector i) {
    i.lazySingleton<AuthService>(
      () => AuthServiceImpl(
        datasource: AuthGrpcDatasource(api: inject<ApiClient>()),
      ),
    );
  }

  /// Feature de UI: as rotas que o módulo contribui.
  @override
  List<GetItModule> routes() => [LoginRoute()];
}
```

---

## 4. As Camadas (Clean Architecture)

### 4.1 Domain — interface pública, parâmetros e usecase

```dart
// domain/services/auth_service.dart  (PÚBLICO — outras features dependem disto)
abstract interface class AuthService {
  Future<ReturnSuccessOrError<Session>> login({
    required String email,
    required String password,
  });
  bool get isAuthenticated;
  Session? get currentSession;
}
```

```dart
// domain/parameters/login_parameters.dart
// Só dados: na v3 o parâmetro não carrega mais o erro. Atravessa as três
// camadas e chega ao mapError como contexto — então nunca entra em log (aqui
// carrega a senha).
final class LoginParameters extends Parameters {
  final String email;
  final String password;
  const LoginParameters({required this.email, required this.password});
}
```

```dart
// features/login/domain/usecases/login_usecase.dart
final class LoginUsecase
    extends UsecaseBaseCallData<Session, Session, LoginParameters, LoginError> {
  const LoginUsecase({required super.repository});

  // O getter `process` aponta para uma função ESTÁTICA (não captura `this`). A
  // base faz o fetch no repositório, curto-circuita no erro e chama `process`
  // com o dado já carregado e os parâmetros TIPADOS (sem cast).
  @override
  ProcessData<Session, Session, LoginParameters, LoginError> get process =>
      _process;

  // Obrigatório na v3: converte um bug do process num erro previsto da feature.
  @override
  LoginError onUnexpected(Object exception, StackTrace stackTrace) =>
      const LoginInesperado();

  static ReturnSuccessOrError<Session, LoginError> _process(
    Session session,
    LoginParameters parameters,
  ) => Success(session);
}
```

> O contrato completo do usecase (fluxo fetch → short-circuit → process, isolate só no `process`, `ProcessData`/`ProcessPure`) está em [construcao-feature-com-return-success-or-error.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-feature-com-return-success-or-error.md) §5.

### 4.2 Data — datasource e a implementação do serviço exposto

```dart
// data/datasources/login_grpc_datasource.dart
final class LoginGrpcDatasource implements Datasource<Session, LoginParameters> {
  final ApiClient _api;
  AuthGrpcDatasource({required ApiClient api}) : _api = api;

  @override
  Future<Session> call(covariant LoginParameters parameters) =>
      _api.auth.login(email: parameters.email, password: parameters.password);
}
```

```dart
// data/services/auth_service_impl.dart
final class AuthServiceImpl implements AuthService {
  final Datasource<Session> _datasource;
  Session? _session;

  AuthServiceImpl({required Datasource<Session> datasource})
      : _datasource = datasource;

  @override
  bool get isAuthenticated => _session != null;

  @override
  Session? get currentSession => _session;

  @override
  Future<ReturnSuccessOrError<Session>> login({
    required String email,
    required String password,
  }) async {
    final usecase = LoginUsecase(datasource: _datasource);
    final result = await usecase(LoginParameters(email: email, password: password));
    if (result case Success(:final value)) _session = value;
    return result;
  }
}
```

### 4.3 Presentation — rota, controller e página

```dart
// presentation/routes/login_route.dart
final class LoginRoute extends GetItModule {
  @override
  String get path => '/login';

  @override
  Widget get page => const LoginPage();

  @override
  void binds(Injector i) {
    // Consome a feature de serviço (AuthService) vinda do escopo global.
    i.controller<LoginController>(
      () => LoginController(auth: inject<AuthService>()),
    );
  }
}
```

```dart
// presentation/controllers/login_controller.dart
final class LoginController extends BaseController<Session> {
  final AuthService _auth;
  LoginController({required AuthService auth}) : _auth = auth;

  Future<void> signIn(String email, String password) =>
      execute(() => _auth.login(email: email, password: password));
}
```

---

## 5. Consumo Entre Módulos

Outro módulo consome a feature exposta **pela interface pública**, resolvida do escopo global. Ele importa o API público do `login_module`, não o `src/`.

```dart
// dashboard_module/src/presentation/routes/dashboard_route.dart
import 'package:login_module/login_module.dart'; // API público: AuthService

final class DashboardRoute extends GetItModule {
  @override
  String get path => '/dashboard';

  @override
  Widget get page => const DashboardPage();

  @override
  void binds(Injector i) {
    i.controller<DashboardController>(
      () => DashboardController(auth: inject<AuthService>()), // feature de outro módulo
    );
  }
}
```

O `DashboardController` pode chamar `_auth.isAuthenticated` / `_auth.currentSession` para saber o estado de autenticação — exatamente o exemplo de “uma feature que processa o login e traz o resultado para outros módulos”.

---

## 6. Onde Registrar Cada Coisa

| Tipo | Escopo | Onde declarar | Modo |
| :--- | :--- | :--- | :--- |
| Feature de serviço exposta (`AuthService`) | **Global** | `globalBinds` do módulo dono | `lazySingleton` |
| Clientes de infra (`ApiClient`, logger) | **Global** | `globalBinds` do `InfraModule` | `singleton`/`lazySingleton` |
| `Datasource`/`Usecase` exclusivos de uma tela | **Rota** | `binds` da rota | `lazySingleton` |
| `Controller` (Cubit) | **Rota** | `binds` da rota (`i.controller<>`) | lazySingleton + close |
| `Datasource`/`Usecase` usados por várias telas do mesmo módulo | **Global** | `globalBinds` do módulo | `lazySingleton` |

Regra: o que **atravessa fronteiras de módulo** ou precisa **viver além de uma tela** → escopo global (via `globalBinds`). O que é **exclusivo de uma tela** → `binds` da rota.

---

## 7. Regras de Dependência Entre Módulos

Os módulos **podem consumir features uns dos outros**, mas sempre pela **interface pública** e organizados em **camadas de domínio** para evitar ciclos.

```text
apps/*  ──▶ dependencies_module                 (infra unificada)
        └─▶ os módulos que ESTE app compõe (lista de AppModule)

dependencies_module ──▶ infra: design_system_module, core_module, presentation_module,
                         navigation_module, get_it_module, app_config, api_client, domain_models
                         ✗ NÃO depende de módulos de feature (evita ciclo)

módulo de feature ──▶ dependencies_module (infra)
                   ──▶ API PÚBLICO de módulos de camada inferior (ex.: login_module → AuthService)
                   ✗ NUNCA o `src/` de outro módulo   ✗ NUNCA um módulo de camada superior
```

Camadas (do mais básico ao mais alto), onde o de cima pode consumir o de baixo:

1. **Infra**: `get_it_module`, `app_config`, `api_client`, `domain_models`, `presentation_module`, `navigation_module`, `design_system_module`.
2. **Módulos de domínio base**: expõem serviços fundamentais consumidos por vários (ex.: `login_module` → `AuthService`).
3. **Módulos de feature**: consomem (2) e (1); compõem telas. Não são consumidos por (2).

Pontos críticos:

- **A composição de features é decisão do app**: o app lista os `AppModule` que inclui (Web Admin e Windows Tenant compõem conjuntos diferentes).
- **`dependencies_module` não exporta módulos de feature** — senão, como features importam `dependencies_module`, haveria ciclo. Features são agregadas só no app.
- **Dependência por interface**: um módulo importa do outro apenas o que está no API público (interfaces/serviços), nunca o `src/`.

---

## 8. Convenções de Nomenclatura

| Artefato | Arquivo (`snake_case`) | Classe (`PascalCase`) | Base/contrato |
| :--- | :--- | :--- | :--- |
| Módulo | `login_module.dart` | `LoginModule` | `extends AppModule` |
| Rota | `login_route.dart` | `LoginRoute` | `extends GetItModule` |
| Feature de serviço (interface) | `auth_service.dart` | `AuthService` | `abstract interface class` |
| Impl. do serviço | `auth_service_impl.dart` | `AuthServiceImpl` | `implements AuthService` |
| Controller | `login_controller.dart` | `LoginController` | `extends BaseController<T>` |
| Página | `login_page.dart` | `LoginPage` | `extends ModulePage<C, T>` |
| Usecase | `login_usecase.dart` | `LoginUsecase` | `extends UsecaseBaseCallData<TValue, TData, TParams, TError>` |
| Repositório | `login_repository.dart` | `LoginRepository` | `extends RepositoryBase<TData, TParams, TError>` |
| Datasource | `login_grpc_datasource.dart` | `LoginGrpcDatasource` | `implements Datasource<TData, TParams>` |
| Parâmetros | `login_parameters.dart` | `LoginParameters` | `extends Parameters` |
| Erros da feature | `login_errors.dart` | `LoginError` + casos | `sealed class ... extends AppError` |
| Gateway de plataforma (quando houver) | `atendimento_gateway.dart` | `AtendimentoGateway` | `abstract interface class` |

Demais convenções:

- Pasta do módulo sempre `<nome>_module/`; rota sempre `path: '/<rota>'` (kebab para compostos: `/tenant-detail`).
- **Estado sempre `ViewState<T>`** — nunca um sealed state por feature (telas ricas usam view-model composto em `T`).
- Sufixo do datasource indica o transporte (`...GrpcDatasource`, `...RestDatasource`, `...LocalDatasource`).
- Comentários em **pt-br**.

---

## 9. Checklist de Criação de um Novo Módulo

1. Criar `clients/modulos/<nome>_module/` com o layout da seção 2.
2. `pubspec.yaml`: depender de `dependencies_module` (+ API público de módulos de camada inferior que for consumir).
3. **Domain:** definir a(s) **interface(s) de serviço** expostas, `Parameters` e `Usecase`.
4. **Data:** `Datasource` (consome `api_client`) + **implementação** das interfaces de serviço.
5. **Presentation:** `Controller` (`BaseController`) + `Page` (`ModulePage`) + `Route` (`GetItModule`) por tela.
6. **Módulo:** `XxxModule extends AppModule` com `globalBinds` (serviços expostos) e `routes()` (telas).
7. **API público** (`lib/<nome>_module.dart`): exportar a classe do módulo e as interfaces de serviço — nunca o `src/`.
8. Registrar o módulo na lista de `AppModule` **do(s) app(s)** que o incluem.
9. **Testes:** usecase (mock do datasource) e controller (mock do serviço/usecase, `bloc_test`).
