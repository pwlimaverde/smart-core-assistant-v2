# Return Success or Error (return_success_or_error)

- **Versão Recomendada:** 2.0.0
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-14
- **Propósito no Projeto:** Abstração tipada de result types para usecases, datasources e erros de domínio em features Flutter. Na 2.0.0 separa **fetch** (datasource) de **process** (regra de negócio CPU-bound), permitindo rodar o processamento pesado em isolate sem arrastar o datasource.
- **Documentação Oficial:** [https://pub.dev/packages/return_success_or_error](https://pub.dev/packages/return_success_or_error)

---

## 1. Contexto e Uso no Projeto

O pacote implementa um **sealed result type** (`ReturnSuccessOrError<R>`) que força o tratamento exaustivo de sucesso e erro via `switch` (Dart 3). Não há helpers (`fold`, `getOrNull`, `isSuccess`, `isError`, `getOrElse`) — a recuperação do valor é só por pattern matching.

**A mudança central da 2.0.0:** o usecase passou a ter **duas fases nítidas** e a subclasse implementa o getter **`process`** (função **estática síncrona**), não mais `run`:

```text
Parameters (carregam AppError, imutáveis/sendable)
  ↓
[UsecaseBaseCallData] FETCH      → datasource carrega o dado CRU (isolate principal; throw AppError em falha)
  ↓ short-circuit automático no erro (process nem é chamado)
[UsecaseBaseCallData/UsecaseBase] PROCESS  → process(data, parameters) — função ESTÁTICA, síncrona,
                                              CPU-bound; roda DIRETO ou em ISOLATE (runInIsolate)
  ↓
switch exaustivo (SuccessReturn | ErrorReturn) na Presentation/Controller
```

> **Por que separar:** na 1.0.0 o `runInIsolate` jogava todo o `run` (incluindo o datasource) para o isolate, o que quebrava com recursos nativos não-serializáveis (conexão de banco, socket). Na 2.0.0 o fetch fica sempre no isolate principal e **só o `process`** vai para o background.

---

## 2. API Pública v2.0.0

### 2.1 ReturnSuccessOrError (sealed type) — inalterado

```dart
@immutable
sealed class ReturnSuccessOrError<R> {
  const ReturnSuccessOrError();
  Object? get result; // refinado em cada subclasse
}

final class SuccessReturn<R> extends ReturnSuccessOrError<R> {
  const SuccessReturn({required R success});
  @override
  R get result;
}

final class ErrorReturn<R> extends ReturnSuccessOrError<R> {
  const ErrorReturn({required AppError error});
  @override
  AppError get result;
}
```

Recuperação só por `switch` exaustivo; dentro do `process` use `case SuccessReturn(:final result)` para desestruturar.

### 2.2 Unit e Nil (singletons para void/null) — inalterado

```dart
const unit = Unit(); // void como resultado de sucesso: SuccessReturn(success: unit)
const nil = Nil();   // null como resultado de sucesso: SuccessReturn(success: nil)
```

### 2.3 AppError (interface imutável) — inalterado

```dart
@immutable
abstract interface class AppError implements Exception {
  String get message;
  AppError copyWith({String? message}); // polimórfico: preserva o tipo concreto
}

final class ErrorGeneric implements AppError { /* impl pronta, == / hashCode / toString */ }
```

Enriquecimento sempre por `copyWith` (nunca mutação): `parameters.error.copyWith(message: "...")`.

### 2.4 ParametersReturnResult (contrato de parâmetros) — inalterado

```dart
abstract interface class ParametersReturnResult {
  AppError get error; // erro devolvido em falha
}

final class NoParams implements ParametersReturnResult {
  const NoParams({AppError? error});
}
```

> Imutabilidade reforçada na 2.0.0: o `parameters` é passado ao `process`, que pode rodar em isolate — logo precisa ser **sendable** (só dados, sem closures/handles vivos).

### 2.5 Datasource&lt;D&gt; (chamada externa) — contrato inalterado, papel mais estrito

```dart
abstract interface class Datasource<TypeDatasource> {
  Future<TypeDatasource> call(covariant ParametersReturnResult parameters);
}
```

**Só I/O — devolve o dado CRU**, sem parsing/regra de negócio. `try/catch` → `throw parameters.error.copyWith(...)`:

```dart
final class RemoteUserDatasource implements Datasource<List<Map<String, dynamic>>> {
  final ApiClient _api;
  const RemoteUserDatasource(this._api);

  @override
  Future<List<Map<String, dynamic>>> call(covariant FetchUserParams parameters) async {
    try {
      return await _api.getRows('/users/${parameters.userId}'); // dado cru
    } catch (e) {
      throw parameters.error.copyWith(message: "$e");
    }
  }
}
```

> A base captura essa exceção internamente (fase de fetch, no isolate principal), preserva o tipo concreto do `AppError` e enriquece com `Cod. 02-1`. O usecase **não** chama o datasource diretamente (o antigo `resultDatasource` é privado na 2.0.0).

### 2.6 Typedefs do `process`

```dart
/// Para UsecaseBaseCallData: recebe o dado já carregado pelo datasource.
typedef ProcessData<TypeUsecase, TypeDatasource> =
    ReturnSuccessOrError<TypeUsecase> Function(
      TypeDatasource data,
      ParametersReturnResult parameters,
    );

/// Para UsecaseBase: regra pura, recebe só os parâmetros.
typedef ProcessPure<TypeUsecase> =
    ReturnSuccessOrError<TypeUsecase> Function(
      ParametersReturnResult parameters,
    );
```

`process` é **síncrono** (`ReturnSuccessOrError`, não `Future`) e deve ser **estático/top-level** (não captura `this`).

### 2.7 UsecaseBase&lt;T&gt; (regra de negócio pura, sem datasource)

```dart
abstract base class UsecaseBase<TypeUsecase> {
  final bool runInIsolate;
  final bool monitorExecutionTime;
  const UsecaseBase({this.runInIsolate = false, this.monitorExecutionTime = false});

  @protected
  ProcessPure<TypeUsecase> get process; // a subclasse implementa ISTO

  Future<ReturnSuccessOrError<TypeUsecase>> call(covariant ParametersReturnResult parameters);
}
```

```dart
final class FibonacciUsecase extends UsecaseBase<int> {
  const FibonacciUsecase({super.runInIsolate});

  @override
  ProcessPure<int> get process => _process;

  static ReturnSuccessOrError<int> _process(ParametersReturnResult parameters) {
    final p = parameters as FibonacciParameters; // cast p/ tipo concreto
    if (p.n < 0) return ErrorReturn(error: p.error.copyWith(message: "n must be >= 0"));
    return SuccessReturn(success: _fib(p.n));
  }
}
```

### 2.8 UsecaseBaseCallData&lt;T, D&gt; (fetch + process)

```dart
abstract base class UsecaseBaseCallData<TypeUsecase, TypeDatasource> {
  final bool runInIsolate;        // afeta SOMENTE o process (fase 3)
  final bool monitorExecutionTime;
  UsecaseBaseCallData({
    required Datasource<TypeDatasource> datasource, // private named param: fica privado
    this.runInIsolate = false,
    this.monitorExecutionTime = false,
  });

  @protected
  ProcessData<TypeUsecase, TypeDatasource> get process; // a subclasse implementa ISTO

  Future<ReturnSuccessOrError<TypeUsecase>> call(covariant ParametersReturnResult parameters);
}
```

A base orquestra **fetch → short-circuit → process**. A subclasse só declara `process` (estático), que recebe o dado **cru já carregado**:

```dart
// D=List<Map>, T=SalesReport — datasource cru, parsing/agregação pesado no process (em isolate).
final class GerarSalesReportUsecase
    extends UsecaseBaseCallData<SalesReport, List<Map<String, dynamic>>> {
  GerarSalesReportUsecase({
    required super.datasource,
    super.runInIsolate,        // true → parsing pesado em background
    super.monitorExecutionTime,
  });

  @override
  ProcessData<SalesReport, List<Map<String, dynamic>>> get process => _process;

  static ReturnSuccessOrError<SalesReport> _process(
    List<Map<String, dynamic>> linhas,
    ParametersReturnResult parameters,
  ) {
    if (linhas.isEmpty) {
      return ErrorReturn(error: parameters.error.copyWith(message: "Sem dados"));
    }
    // ... CPU pesada: parse + agregação → objeto sendable
    return SuccessReturn(success: SalesReport(/* ... */));
  }
}
```

**Flags de execução:**
- `runInIsolate = true`: roda **apenas o `process`** em `Isolate.run`. O **fetch fica sempre no isolate principal** (datasources com recursos nativos funcionam). Falha dentro do isolate vira `ErrorReturn` (`Cod. IsolateCatch`).
- `monitorExecutionTime = true`: mede fetch+process e loga `(Direct)`/`(Isolate)` via `dart:developer`/`print` — só em dev.

> **Regra do isolate:** `process` estático (sem `this`); `Parameters` e o tipo de retorno `T` **sendable** (só primitivos). Ligue `runInIsolate` só quando o `process` for de fato pesado — abaixo de um certo volume, o custo de copiar dados entre isolates não compensa.

---

## 3. Guia de Uso Rápido: Parameters → Datasource → Usecase(process) → Switch

```dart
// 1) Parâmetros + erro de domínio (imutáveis/sendable)
final class FetchUserParams implements ParametersReturnResult {
  final String userId;
  @override
  final AppError error;
  const FetchUserParams({required this.userId, required this.error});
}

// 2) Datasource — só I/O, devolve o DTO cru
final class RemoteUserDatasource implements Datasource<UserDTO> {
  final http.Client _http;
  const RemoteUserDatasource(this._http);
  @override
  Future<UserDTO> call(covariant FetchUserParams p) async {
    try {
      final r = await _http.get(Uri.parse('https://api/users/${p.userId}'));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      return UserDTO.fromJson(json.decode(r.body));
    } catch (e) {
      throw p.error.copyWith(message: "$e");
    }
  }
}

// 3) Usecase — process estático mapeia DTO → domínio
final class FetchUserUsecase extends UsecaseBaseCallData<User, UserDTO> {
  FetchUserUsecase({required super.datasource, super.runInIsolate});

  @override
  ProcessData<User, UserDTO> get process => _process;

  static ReturnSuccessOrError<User> _process(UserDTO dto, ParametersReturnResult p) =>
      SuccessReturn(success: User.fromDTO(dto));
}

// 4) Consumo (Cubit/Controller) — switch exaustivo
final result = await fetchUserUsecase(FetchUserParams(userId: id, error: const UserError(message: 'Falha')));
switch (result) {
  case SuccessReturn(:final result): emit(UserLoaded(result));
  case ErrorReturn(:final result):   emit(UserError(result.message));
}
```

> No monorepo, o consumo na UI é padronizado pelo `BaseController.execute()` (Cubit + `ViewState<T>`) — ver `construcao-modulo-presentation.md`.

---

## 4. Boas Práticas

- **Imutabilidade:** `ReturnSuccessOrError`, `AppError`, `Parameters` e objetos de `domain/model/` são imutáveis. Enriqueça erro com `copyWith`, nunca mutação.
- **Tipo concreto do erro preservado:** `copyWith` é polimórfico — um `ApiError` continua `ApiError` até o controller.
- **Switch exaustivo:** nunca `if (result.isSuccess)` (não existe) — sempre `switch`.
- **Datasource só I/O; process só CPU:** toda chamada externa/assíncrona no datasource; todo parsing/agregação/validação no `process` (síncrono, estático).
- **Isolate consciente:** `runInIsolate: true` apenas para `process` pesado; `Parameters`/`T` sendable; o fetch nunca vai ao isolate.

---

## 5. Migração v1.0.0 → v2.0.0

| v1.0.0 | v2.0.0 |
| :-- | :-- |
| `@override Future<...> run(p) async => resultDatasource(p);` | `@override ProcessData<T,D> get process => _process;` + `static ReturnSuccessOrError<T> _process(D data, ParametersReturnResult p) => SuccessReturn(success: data);` |
| `run` fazia `switch` no `resultDatasource` para transformar | a transformação vai para `_process`, recebendo `data` (D já desempacotado) |
| `resultDatasource` exposto à subclasse | **privado** (fetch orquestrado pela base) |
| `runInIsolate` jogava todo o `run` (com datasource) ao isolate | `runInIsolate` afeta **só o process**; fetch sempre no principal |
| `run` assíncrono | `process` **síncrono** e **estático** |

**Removidos da API (continuam não existindo):** `fold`, `getOrNull`, `isSuccess`, `isError`, `getOrElse` — use `switch`.

---

## 6. Referências

- **Repositório:** [https://github.com/pwlimaverde/return_success_or_error](https://github.com/pwlimaverde/return_success_or_error)
- **Pub.dev:** [https://pub.dev/packages/return_success_or_error](https://pub.dev/packages/return_success_or_error)
- **Exemplo (`example/`):** features `check_connection` (`UsecaseBaseCallData<String,bool>`), `fibonacci` (`UsecaseBase<int>` em isolate) e `sales_report` (datasource cru → `process` pesado em isolate, com testes de paridade direto×isolate).
- **Licença:** MIT · **Conceitos:** Clean Architecture, Result Types, Sealed Classes (Dart 3), Isolates.

---

## Histórico de Atualizações

- **2026-06-14** — Atualizado para **2.0.0**. Reescrito o fluxo do usecase: subclasses implementam o getter **`process`** (função estática síncrona, `ProcessData`/`ProcessPure`) em vez de `run`; a base orquestra **fetch → short-circuit → process**; `runInIsolate` passou a afetar **só o `process`** (fetch sempre no isolate principal); `resultDatasource` deixou de ser exposto. Novo exemplo `sales_report`.
- **2026-06-14** — Criação do doc na versão 1.0.0.
