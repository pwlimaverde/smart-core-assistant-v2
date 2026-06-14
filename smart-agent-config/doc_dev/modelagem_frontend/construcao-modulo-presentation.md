# Especificação de Construção do Módulo `presentation_module`

Este documento detalha a estrutura de arquivos, dependências e implementação do módulo de infraestrutura **`presentation_module`**. Ele padroniza a **camada de apresentação** de todas as features do monorepo `smart-core-assistant-v2`: o modelo de **estado genérico** (`ViewState<T>`), a **base de controller** (`BaseController<T>`, integrada ao `return_success_or_error`) e as **bases de página** (`ModulePage` e `ViewStateBuilder`).

Trabalha em conjunto com o package [get_it_module](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-package-get-it-module.md):

> O `get_it_module` resolve **injeção e ciclo de vida**. O `presentation_module` resolve **estado e renderização**. O `GetItModule` de cada feature amarra os dois: declara a `page` (que estende as bases daqui) e registra o controller nos `binds`.

---

## 1. Por que é um Módulo (e não um Package)

Pela taxonomia da arquitetura (`packages/` = Dart puro, sem imports de Flutter), qualquer artefato que dependa do Flutter SDK é um **módulo**. Como `presentation_module` expõe widgets (`ModulePage`, `ViewStateBuilder`) e usa `flutter_bloc`, ele vive em `clients/modulos/presentation_module/`.

Os **controllers** continuam testáveis em Dart puro: `BaseController` estende `Cubit` do package `bloc` (puro), sem depender da árvore de widgets. Apenas as bases de página exigem Flutter.

---

## 2. As Três Responsabilidades

| Camada | Classe | Papel |
| :--- | :--- | :--- |
| **Estado** | `ViewState<T>` (selado) | Estados padronizados de qualquer tela: `Initial`, `Loading`, `Success<T>`, `Error(AppError)`. |
| **Controller** | `BaseController<T>` | `Cubit<ViewState<T>>` com `execute()` que roda um usecase (`ReturnSuccessOrError<T>`) e mapeia para os estados. |
| **Página** | `ModulePage` / `ViewStateBuilder` | Renderização declarativa por estado; resolve o controller via `inject<C>()`. |

**Estado sempre genérico:** toda tela usa `ViewState<T>`. Para telas com múltiplos pedaços de estado, `T` é um **view-model composto** (um `record` ou uma classe imutável que agrega os campos da tela). Não se cria sealed state por feature.

---

## 3. Localização e Estrutura de Diretórios

```text
clients/modulos/presentation_module/
├── pubspec.yaml
└── lib/
    ├── presentation_module.dart           # Ponto de exportação pública
    └── src/
        ├── view_state.dart                # ViewState<T> selado
        ├── base_controller.dart           # BaseController<T> extends Cubit<ViewState<T>>
        ├── controller_binds.dart          # extension ControllerBinds on Injector
        ├── module_page.dart               # ModulePage<C, T> (página opinativa)
        └── view_state_builder.dart        # ViewStateBuilder<C, T> (builder flexível)
```

---

## 4. Configuração de Dependências (`pubspec.yaml`)

```yaml
name: presentation_module
description: Bases de apresentação (ViewState genérico, BaseController e páginas) padronizando Cubit + Clean Architecture sobre o get_it_module.
version: 1.0.0
publish_to: 'none'

environment:
  sdk: ^3.12.2
  flutter: ">=3.44.0"

dependencies:
  flutter:
    sdk: flutter

  # Gerência de estado
  bloc: ^9.2.1
  flutter_bloc: ^9.1.1

  # DI e ciclo de vida (Injector, inject, GetItModule)
  get_it_module:
    path: ../../packages/get_it_module

  # Result type, AppError e UsecaseBase (pub.dev)
  return_success_or_error: ^2.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  bloc_test: ^10.0.0
  mocktail: ^1.0.5
```

> O `return_success_or_error` (v2.0.0, Dart puro) é consumido do **pub.dev** — declaração simples por versão (`^2.0.0`), sem `git:`/`path:`. É a lib que padroniza usecase, `Datasource`, `AppError` e o tipo selado `ReturnSuccessOrError`. Guia de uso nas features: [construcao-feature-com-return-success-or-error.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-feature-com-return-success-or-error.md).

---

## 5. Código de Implementação

### 5.1 Estado Genérico (`lib/src/view_state.dart`)

```dart
import 'package:return_success_or_error/return_success_or_error.dart';

/// Estado genérico de uma tela gerenciada por um BaseController.
///
/// Toda tela do monorepo usa este modelo selado. Quando uma tela tem vários
/// pedaços de estado, [T] deve ser um view-model composto (record ou classe
/// imutável) — não se cria um sealed state por feature.
sealed class ViewState<T> {
  const ViewState();
}

/// Estado inicial, antes de qualquer ação.
final class InitialState<T> extends ViewState<T> {
  const InitialState();
}

/// Operação em andamento.
final class LoadingState<T> extends ViewState<T> {
  const LoadingState();
}

/// Operação concluída com sucesso, carregando o dado [data].
final class SuccessState<T> extends ViewState<T> {
  final T data;
  const SuccessState(this.data);
}

/// Operação falhou, carregando o [AppError] do return_success_or_error.
final class ErrorState<T> extends ViewState<T> {
  final AppError error;
  const ErrorState(this.error);
}
```

### 5.2 Controller Base (`lib/src/base_controller.dart`)

```dart
import 'package:bloc/bloc.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import 'view_state.dart';

/// Base de todos os controllers de tela.
///
/// É um `Cubit<ViewState<T>>` que começa em [InitialState]. O método
/// [execute] elimina o boilerplate de try/catch/emit: roda um usecase que
/// retorna [ReturnSuccessOrError] e mapeia o resultado para os estados.
abstract class BaseController<T> extends Cubit<ViewState<T>> {
  BaseController() : super(InitialState<T>());

  /// Emite [LoadingState], executa [task] e mapeia o resultado:
  ///  - [SuccessReturn] → [SuccessState];
  ///  - [ErrorReturn]   → [ErrorState] (carregando o [AppError]).
  ///
  /// O mapeamento usa `switch` exaustivo sobre o tipo selado
  /// [ReturnSuccessOrError]. A lib (v2.0.0) **não** expõe `fold`/`getOrElse`/
  /// `isSuccess` — o pattern matching é a única forma de recuperar o valor, e o
  /// compilador garante que ambos os casos sejam tratados.
  Future<void> execute(
    Future<ReturnSuccessOrError<T>> Function() task,
  ) async {
    emit(LoadingState<T>());
    final result = await task();
    switch (result) {
      case SuccessReturn<T>():
        emit(SuccessState<T>(result.result));
      case ErrorReturn<T>():
        emit(ErrorState<T>(result.result));
    }
  }
}
```

### 5.3 Atalho de Registro de Controller (`lib/src/controller_binds.dart`)

Mantém o `get_it_module` desacoplado do `bloc`: o atalho que registra o controller já fechando-o no dispose é uma **extension** sobre o `Injector`.

```dart
import 'package:bloc/bloc.dart';
import 'package:get_it_module/get_it_module.dart';

/// Açúcar sintático sobre o Injector para registrar controllers.
extension ControllerBinds on Injector {
  /// Registra um controller (Cubit/Bloc) como lazySingleton no escopo do
  /// módulo, fechando-o automaticamente (`close()`) quando o escopo é
  /// descartado (pop da tela).
  void controller<C extends BlocBase>(C Function() create) {
    lazySingleton<C>(create, dispose: (c) => c.close());
  }
}
```

### 5.4 Página Opinativa (`lib/src/module_page.dart`)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it_module/get_it_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import 'base_controller.dart';
import 'view_state.dart';

/// Página base para telas "um controller, um estado".
///
/// Resolve o controller via [inject], escuta o [ViewState] e renderiza o
/// método correspondente. A subclasse implementa apenas [onSuccess]; os demais
/// estados têm defaults sobrescrevíveis. [onInit] é um gancho de ciclo de vida
/// chamado UMA vez na montagem (ex.: disparar a carga inicial / bootstrap).
abstract class ModulePage<C extends BaseController<T>, T> extends StatefulWidget {
  const ModulePage({super.key});

  /// Controller resolvido do escopo ativo (feature → global).
  C get controller => inject<C>();

  /// Chamado uma vez quando a página é montada. Padrão: nada.
  /// Sobrescreva para disparar a ação inicial da tela (ex.: controller.load()).
  void onInit(BuildContext context) {}

  /// Estado inicial (default: vazio). Sobrescreva para tela de boas-vindas etc.
  Widget onInitial(BuildContext context) => const SizedBox.shrink();

  /// Carregando (default: spinner centralizado).
  Widget onLoading(BuildContext context) =>
      const Center(child: CircularProgressIndicator());

  /// Erro (default: mensagem do AppError centralizada).
  /// Recomendação: sobrescrever usando o ErrorMessageMapper (i18n) —
  /// ver construcao-apresentacao-erro-i18n.md.
  Widget onError(BuildContext context, AppError error) =>
      Center(child: Text(error.message));

  /// Sucesso — único método obrigatório.
  Widget onSuccess(BuildContext context, T data);

  @override
  State<ModulePage<C, T>> createState() => _ModulePageState<C, T>();
}

class _ModulePageState<C extends BaseController<T>, T>
    extends State<ModulePage<C, T>> {
  @override
  void initState() {
    super.initState();
    // Dispara o gancho de inicialização após o primeiro frame, garantindo
    // contexto/escopo prontos (o controller já está no escopo da rota).
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.onInit(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<C, ViewState<T>>(
      bloc: widget.controller,
      builder: (context, state) => switch (state) {
        InitialState<T>() => widget.onInitial(context),
        LoadingState<T>() => widget.onLoading(context),
        ErrorState<T>(:final error) => widget.onError(context, error),
        SuccessState<T>(:final data) => widget.onSuccess(context, data),
      },
    );
  }
}
```

### 5.5 Builder Flexível (`lib/src/view_state_builder.dart`)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it_module/get_it_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import 'base_controller.dart';
import 'view_state.dart';

/// Renderiza o [ViewState] de um controller em qualquer ponto da árvore
/// (ex.: dentro de um Scaffold próprio, com AppBar e várias regiões).
///
/// Resolve o controller via [inject] por padrão, ou usa um [controller]
/// explícito. Todos os estados, exceto [onSuccess], têm defaults.
class ViewStateBuilder<C extends BaseController<T>, T> extends StatelessWidget {
  final C? controller;
  final WidgetBuilder? onInitial;
  final WidgetBuilder? onLoading;
  final Widget Function(BuildContext context, AppError error)? onError;
  final Widget Function(BuildContext context, T data) onSuccess;

  const ViewStateBuilder({
    super.key,
    required this.onSuccess,
    this.controller,
    this.onInitial,
    this.onLoading,
    this.onError,
  });

  @override
  Widget build(BuildContext context) {
    final c = controller ?? inject<C>();
    return BlocBuilder<C, ViewState<T>>(
      bloc: c,
      builder: (context, state) => switch (state) {
        InitialState<T>() =>
          onInitial?.call(context) ?? const SizedBox.shrink(),
        LoadingState<T>() =>
          onLoading?.call(context) ??
              const Center(child: CircularProgressIndicator()),
        ErrorState<T>(:final error) =>
          onError?.call(context, error) ?? Center(child: Text(error.message)),
        SuccessState<T>(:final data) => onSuccess(context, data),
      },
    );
  }
}
```

### 5.6 Exportação Pública (`lib/presentation_module.dart`)

```dart
library presentation_module;

export 'src/view_state.dart';
export 'src/base_controller.dart';
export 'src/controller_binds.dart';
export 'src/module_page.dart';
export 'src/view_state_builder.dart';
```

---

## 6. Uso Completo numa Feature

Junção das três camadas + o `GetItModule`. Note quão pouco código cada arquivo da feature tem.

### 6.1 Controller

```dart
import 'package:presentation_module/presentation_module.dart';
import 'package:domain_models/domain_models.dart';

final class TenantController extends BaseController<List<Tenant>> {
  final GetTenantsUsecase _getTenants;

  TenantController({required GetTenantsUsecase getTenants})
      : _getTenants = getTenants;

  Future<void> loadTenants() => execute(() => _getTenants(NoParams()));
}
```

### 6.2 Página (variante opinativa `ModulePage`)

```dart
import 'package:flutter/material.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:domain_models/domain_models.dart';

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

### 6.3 Página (variante flexível `ViewStateBuilder`)

Quando a tela precisa de `Scaffold`/`AppBar` próprios e um FAB que dispara a ação:

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
        onSuccess: (context, tenants) => ListView.builder(
          itemCount: tenants.length,
          itemBuilder: (_, i) => ListTile(title: Text(tenants[i].name)),
        ),
      ),
    );
  }
}
```

### 6.4 Rota (amarra DI + estado)

A rota (`GetItModule`) liga o controller à tela. Ela é exposta por um módulo (`AppModule`) em `routes()` — ver [anatomia-modulo.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/anatomia-modulo.md).

```dart
import 'package:get_it_module/get_it_module.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:flutter/widgets.dart';

final class TenantRoute extends GetItModule {
  @override
  String get path => '/tenants';

  @override
  Widget get page => const TenantListPage();

  @override
  void binds(Injector i) {
    // controller<> registra como lazySingleton e fecha no dispose do escopo.
    i.controller<TenantController>(
      () => TenantController(getTenants: inject<GetTenantsUsecase>()),
    );
  }
}
```

---

## 7. View-Model Composto (telas com múltiplos estados)

Como o estado é sempre `ViewState<T>`, telas ricas compõem o `T`:

```dart
/// View-model imutável de uma tela de formulário + lista.
final class TenantScreenData {
  final List<Tenant> tenants;
  final String filter;
  final bool isSubmitting;

  const TenantScreenData({
    required this.tenants,
    this.filter = '',
    this.isSubmitting = false,
  });

  TenantScreenData copyWith({List<Tenant>? tenants, String? filter, bool? isSubmitting}) =>
      TenantScreenData(
        tenants: tenants ?? this.tenants,
        filter: filter ?? this.filter,
        isSubmitting: isSubmitting ?? this.isSubmitting,
      );
}

// Controller: BaseController<TenantScreenData>
// Página:     ModulePage<TenantController, TenantScreenData>
```

Para granularidade fina sem reconstruir a tela toda, combine com `BlocSelector` (do `flutter_bloc`) dentro do `onSuccess`.

---

## 8. Teste do Controller (Dart puro, sem Flutter)

`execute()` torna o teste trivial: basta mockar o usecase para devolver `SuccessReturn`/`ErrorReturn` e verificar a sequência de estados.

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
    'emite [Loading, Success] quando o usecase retorna SuccessReturn',
    build: () {
      when(() => usecase(any())).thenAnswer(
        (_) async => SuccessReturn(success: [Tenant(id: '1', name: 'A')]),
      );
      return controller;
    },
    act: (c) => c.loadTenants(),
    expect: () => [
      isA<LoadingState<List<Tenant>>>(),
      isA<SuccessState<List<Tenant>>>()
          .having((s) => s.data, 'data', hasLength(1)),
    ],
  );

  blocTest<TenantController, ViewState<List<Tenant>>>(
    'emite [Loading, Error] quando o usecase retorna ErrorReturn',
    build: () {
      when(() => usecase(any())).thenAnswer(
        (_) async => ErrorReturn(error: const ErrorGeneric(message: 'Falha')),
      );
      return controller;
    },
    act: (c) => c.loadTenants(),
    expect: () => [
      isA<LoadingState<List<Tenant>>>(),
      isA<ErrorState<List<Tenant>>>()
          .having((s) => s.error.message, 'message', contains('Falha')),
    ],
  );
}
```

---

## 9. Resumo das Decisões de Design

- **Estado sempre genérico** (`ViewState<T>`) → padronização total; telas complexas usam view-model composto em `T`.
- **`execute()` no `BaseController`** → integra com `return_success_or_error`; controllers ficam quase sem boilerplate e testáveis em Dart puro.
- **Duas bases de página** → `ModulePage` (opinativa, mínimo código, com gancho `onInit` na montagem) e `ViewStateBuilder` (flexível, para Scaffold próprio).
- **Apresentação de erro padronizada** → o `onError` default mostra a mensagem; features mapeiam `AppError`→i18n via `ErrorMessageMapper` (inline/snackbar/dialog). Ver [construcao-apresentacao-erro-i18n.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-apresentacao-erro-i18n.md).
- **`presentation_module` é módulo, não package** → contém widgets/flutter_bloc; respeita a regra `packages/` = Dart puro.
- **`get_it_module` permanece só DI** → o acoplamento ao `bloc` fica isolado aqui, via a extension `controller<>` sobre o `Injector`.
- **Reexport pelo `dependencies_module`** → a feature importa um lugar só, mas as responsabilidades seguem separadas.
