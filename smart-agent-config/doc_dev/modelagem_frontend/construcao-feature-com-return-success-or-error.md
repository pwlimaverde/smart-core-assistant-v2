# Construção de Feature com `return_success_or_error` (v2.0.0)

Este documento padroniza **como uma feature constrói sua regra de negócio** no monorepo `smart-core-assistant-v2` usando a biblioteca **`return_success_or_error`** (v2.0.0, Dart puro, consumida do pub.dev). É o guia de referência para os blocos `domain/` e `data/` de **qualquer feature de qualquer módulo** — complementa a [anatomia-modulo.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/anatomia-modulo.md) (estrutura física por feature e camadas) e a [construcao-modulo-presentation.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-modulo-presentation.md) (como o controller consome o usecase).

> **Padrão obrigatório do projeto:** **toda** capacidade de negócio é uma **feature** organizada em camadas (Clean Architecture) cujo núcleo é um **usecase** que devolve `ReturnSuccessOrError<T>`. A feature **nunca** propaga `Exception` cru para a UI; a falha sempre vira um `AppError` tipado dentro de um `ErrorReturn`. Este padrão vale para o projeto inteiro — todos os módulos seguem a mesma anatomia de feature.

> **A grande mudança da 2.0.0 (leia primeiro):** o usecase foi dividido em **duas fases nítidas** — o **fetch** (carregar o dado pelo datasource) e o **process** (regra de negócio/parsing sobre o dado já carregado). A base orquestra o fetch sozinha (sempre no isolate principal) e chama o seu **`process`** — uma **função estática síncrona** — com o dado bruto. O `runInIsolate` agora joga **só o `process`** para um isolate de background, **sem arrastar o datasource** (e seus recursos nativos: conexão de banco, socket, etc.). Não se sobrescreve mais `run`, e `resultDatasource` deixou de ser exposto. Detalhes na §5 e na §9.

---

## 1. Os Cinco Blocos da Biblioteca

| Bloco | Contrato | Papel na feature |
| :--- | :--- | :--- |
| `ReturnSuccessOrError<R>` | tipo **selado** (`SuccessReturn<R>` \| `ErrorReturn<R>`) | O retorno de todo usecase. Recuperado **só** por `switch` exaustivo. |
| `AppError` | `abstract interface class implements Exception` | O erro padronizado e **imutável** do domínio. `ErrorGeneric` é a impl. pronta. |
| `ParametersReturnResult` | `abstract interface class` | Carrega os dados da chamada + o `AppError` a exibir se ela falhar. `NoParams` para chamadas sem dados. |
| `Datasource<TypeDatasource>` | `abstract interface class` | A chamada externa (gRPC/REST/local). Retorna o dado **cru** **ou** faz `throw` no `AppError` dos parâmetros. **Só I/O — sem regra de negócio.** |
| `UsecaseBase<T>` / `UsecaseBaseCallData<T, D>` | `abstract base class` | A regra de negócio, exposta como o getter **`process`** (função estática). `UsecaseBase` = regra pura; `UsecaseBaseCallData` = fetch (datasource) + process. |

Dois typedefs públicos descrevem o contrato do `process`:

| Typedef | Assinatura | Usado por |
| :--- | :--- | :--- |
| `ProcessData<T, D>` | `ReturnSuccessOrError<T> Function(D data, ParametersReturnResult parameters)` | `UsecaseBaseCallData<T, D>` |
| `ProcessPure<T>` | `ReturnSuccessOrError<T> Function(ParametersReturnResult parameters)` | `UsecaseBase<T>` |

Importa-se tudo de um único barrel (já reexportado pelo `dependencies_module`):

```dart
import 'package:return_success_or_error/return_success_or_error.dart';
```

---

## 2. O Resultado Selado: `switch`, nunca `fold`

`ReturnSuccessOrError<R>` é um `sealed class` com exatamente dois casos. O valor é recuperado por **pattern matching exaustivo** — o compilador obriga a tratar os dois ramos.

```dart
final ReturnSuccessOrError<Session> result = await usecase(parameters);

switch (result) {
  case SuccessReturn<Session>():
    final session = result.result; // R (Session)
  case ErrorReturn<Session>():
    final error = result.result;   // AppError
}
```

> A lib **não expõe** `fold`, `isSuccess`, `isError`, `getOrNull` ou `getOrElse` — o `switch` exaustivo é a única forma de recuperar o valor (e a mais segura: novos casos quebrariam a compilação, não o runtime). Dentro do `process`, o padrão `case SuccessReturn(:final result)` desestrutura direto o valor.

Singletons de conveniência para sucessos sem dado:

- `unit` (`Unit`) — representa `void` como resultado: `SuccessReturn(success: unit)`.
- `nil` (`Nil`) — representa `null` como resultado: `SuccessReturn(success: nil)`.

---

## 3. Os Parâmetros: `implements ParametersReturnResult`

A interface é **pura**: sua única exigência é expor o `AppError get error` que será devolvido se a operação falhar. Declare os campos `final` e mantenha o objeto **imutável e _sendable_** (só dados, sem closures/handles vivos). Imutabilidade é exigência forte na 2.0.0: o `parameters` é passado ao `process`, que **pode rodar em um isolate** — logo precisa cruzar a fronteira do isolate com segurança.

```dart
// domain/parameters/sales_report_parameters.dart
final class SalesReportParameters implements ParametersReturnResult {
  final int mes;
  final int ano;

  @override
  final AppError error;

  const SalesReportParameters({
    required this.mes,
    required this.ano,
    required this.error,
  });
}
```

Quando a operação não exige dados extras, use `NoParams`, passando o erro do contexto:

```dart
final params = NoParams(error: const ErrorAuth(message: 'Falha ao carregar tenants'));
```

> O `AppError` pode ser um campo `final` (como acima) ou um getter (`AppError get error => const ErrorAuth(...)`). Use o campo quando o erro variar por chamada; use o getter quando for fixo do tipo.

---

## 4. O Datasource: `implements Datasource<D>` (só I/O, devolve dado **cru**)

O datasource é a **fronteira externa** (gRPC via `api_client`, REST, storage local, driver de banco). Sua **única** responsabilidade é o I/O: envolva a lógica em `try/catch`, retorne o **dado cru tipado** em caso de sucesso, ou faça **`throw` no `AppError` dos parâmetros** em caso de falha. **Não** faça parsing/agregação/regra de negócio aqui — isso é trabalho do `process` (que pode ir para um isolate).

```dart
// data/datasources/fake_sales_datasource.dart
final class FakeSalesDatasource
    implements Datasource<List<Map<String, dynamic>>> {
  final SalesApiClient _api;
  const FakeSalesDatasource({required SalesApiClient api}) : _api = api;

  @override
  Future<List<Map<String, dynamic>>> call(
    covariant SalesReportParameters parameters,
  ) async {
    try {
      // Só I/O assíncrono (não bloqueia o event loop). Devolve linhas CRUAS,
      // exatamente como vêm do banco/driver — sem processá-las.
      return await _api.fetchSales(mes: parameters.mes, ano: parameters.ano);
    } catch (e) {
      // Preserva o erro de domínio dos parâmetros, anexando a causa crua.
      throw parameters.error.copyWith(message: "$e");
    }
  }
}
```

**Como a base trata isso (fase de fetch):** a base chama o datasource **dentro de um `try/catch` próprio** (no isolate principal), encapsula o sucesso em `SuccessReturn` e converte a exceção em `ErrorReturn`, preservando o **tipo concreto** do `AppError` e enriquecendo a mensagem com o ponto de captura (`Cod. 02-1`). A subclasse do usecase **não** vê esse passo — ele é interno (o antigo `resultDatasource` virou privado).

Convenções:

- O parâmetro de `call` é `covariant` — tipe-o com sua `Parameters` concreta.
- **Sufixo indica o transporte:** `...GrpcDatasource`, `...RestDatasource`, `...LocalDatasource`.
- O datasource é Dart puro sempre que possível (sem Flutter) e vive em `data/datasources/`.
- **O fetch roda sempre no isolate principal** — então datasources com **recursos nativos** (conexão de banco, socket, handle de arquivo) funcionam normalmente, mesmo com `runInIsolate: true`.

---

## 5. O Usecase: implementa o getter `process` (função estática)

Há duas bases (`abstract base class`); a subclasse é sempre `final class`. **Não se sobrescreve `run` nem `call`** — a subclasse implementa apenas o getter **`process`**, apontando para uma **função estática**. Invocar o usecase (`await usecase(params)`) chama o `call` (concreto na base), que orquestra tudo.

### 5.1 O fluxo de três fases (`UsecaseBaseCallData`)

A base orquestra sozinha:

```
1. FETCH      → chama o datasource (privado) no ISOLATE PRINCIPAL.
                Sucesso → embrulha em SuccessReturn<D>. Falha → ErrorReturn<D> (Cod. 02-1).
2. SHORT-CIRCUIT → se o fetch falhou, devolve o erro e o `process` NEM É CHAMADO.
3. PROCESS    → com o dado bruto D já carregado, executa o `process`
                (DIRETO ou em ISOLATE de background, conforme `runInIsolate`).
```

> **Por que o `process` é uma função estática?** É ela que roda dentro do `Isolate.run` quando `runInIsolate: true`. Se fosse um método de instância, capturaria `this` — e arrastaria o **datasource** (com seus recursos nativos não-serializáveis) para o isolate, quebrando a execução. Por isso o `process` recebe **tudo** de que precisa via parâmetros (`data` + `parameters`) e **não acessa campos da instância**. Se precisar de campos específicos do parâmetro, faça o **cast** de `parameters` para o tipo concreto **dentro** da função.

### 5.2 `UsecaseBaseCallData<T, D>` — fetch + process

`T` = tipo final do usecase; `D` = tipo **cru** do datasource. O datasource é passado por `super.datasource` (private named parameter) e permanece **privado**; a subclasse só declara o `process`.

**Caso simples — passthrough (D == T):** o datasource já devolve o tipo final; o `process` só embrulha.

```dart
// domain/usecases/login_usecase.dart
final class LoginUsecase extends UsecaseBaseCallData<Session, Session> {
  LoginUsecase({required super.datasource, super.runInIsolate});

  @override
  ProcessData<Session, Session> get process => _process;

  // Estática: o datasource já entregou a Session; só repassa.
  static ReturnSuccessOrError<Session> _process(
    Session session,
    ParametersReturnResult parameters,
  ) => SuccessReturn(success: session);
}
```

**Caso com transformação/regra de negócio (D ≠ T):** o `process` mapeia o dado cru e pode devolver um erro de negócio.

```dart
// domain/usecases/check_connection_usecase.dart  (D=bool, T=String)
final class CheckConnectionUsecase extends UsecaseBaseCallData<String, bool> {
  CheckConnectionUsecase({required super.datasource, super.runInIsolate});

  @override
  ProcessData<String, bool> get process => _process;

  static ReturnSuccessOrError<String> _process(
    bool online,
    ParametersReturnResult parameters,
  ) => online
      ? const SuccessReturn(success: 'Conectado')
      : ErrorReturn(error: parameters.error.copyWith(message: 'Offline'));
}
```

**Caso pesado — datasource cru + `process` em isolate (a estratégia-chave da 2.0.0):** o datasource devolve **linhas cruas** e o `process` faz o parsing/agregação **pesado** em um isolate, sem travar a UI. O resultado é um objeto de domínio imutável (`domain/model/`).

```dart
// domain/usecases/gerar_sales_report_usecase.dart  (D=List<Map>, T=SalesReport)
final class GerarSalesReportUsecase
    extends UsecaseBaseCallData<SalesReport, List<Map<String, dynamic>>> {
  GerarSalesReportUsecase({
    required super.datasource,
    super.runInIsolate,        // true → o parsing pesado roda em background
    super.monitorExecutionTime,
  });

  @override
  ProcessData<SalesReport, List<Map<String, dynamic>>> get process => _process;

  // Estática: parse + agregação CPU-bound. Roda no isolate quando configurado.
  static ReturnSuccessOrError<SalesReport> _process(
    List<Map<String, dynamic>> linhas,
    ParametersReturnResult parameters,
  ) {
    if (linhas.isEmpty) {
      return ErrorReturn(
        error: parameters.error.copyWith(message: 'Sem vendas no período'),
      );
    }
    var faturamento = 0.0;
    var itens = 0;
    final porProduto = <String, double>{};
    for (final row in linhas) {
      final qtd = row['quantidade'] as int;
      final total = qtd * (row['valor_unitario'] as num).toDouble();
      faturamento += total;
      itens += qtd;
      porProduto.update(row['produto'] as String, (a) => a + total,
          ifAbsent: () => total);
    }
    final maisVendido =
        porProduto.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return SuccessReturn(
      success: SalesReport(
        totalItens: itens,
        faturamentoTotal: faturamento,
        ticketMedio: faturamento / linhas.length,
        produtoMaisVendido: maisVendido,
      ),
    );
  }
}
```

O objeto de domínio processado vive em `domain/model/` e é **imutável e _sendable_** (só primitivos), para poder cruzar a fronteira do isolate:

```dart
// domain/model/sales_report.dart
final class SalesReport {
  final int totalItens;
  final double faturamentoTotal;
  final double ticketMedio;
  final String produtoMaisVendido;
  const SalesReport({
    required this.totalItens,
    required this.faturamentoTotal,
    required this.ticketMedio,
    required this.produtoMaisVendido,
  });
}
```

### 5.3 `UsecaseBase<T>` — regra de negócio pura (sem datasource)

Para cálculos/validações que não tocam fronteira externa. O construtor é `const`. O `process` é `ProcessPure<T>` (recebe só `parameters`).

```dart
// domain/usecases/fibonacci_usecase.dart
final class FibonacciUsecase extends UsecaseBase<int> {
  const FibonacciUsecase({super.runInIsolate});

  @override
  ProcessPure<int> get process => _process;

  static ReturnSuccessOrError<int> _process(ParametersReturnResult parameters) {
    final params = parameters as FibonacciParameters; // cast p/ o tipo concreto
    if (params.n < 0) {
      return ErrorReturn(error: params.error.copyWith(message: 'n must be >= 0'));
    }
    return SuccessReturn(success: _fib(params.n));
  }

  static int _fib(int n) { /* iterativo, CPU-bound */ return n; }
}
```

### 5.4 Execução em Isolate (`runInIsolate`) e medição

- `runInIsolate: true` faz **apenas o `process`** rodar em `Isolate.run`. **O fetch do datasource sempre roda no isolate principal** — por isso datasources com recursos nativos funcionam mesmo com isolate ligado. Falhas dentro do isolate viram `ErrorReturn` automaticamente (`Cod. IsolateCatch`).
- Pré-requisitos para o isolate: `process` **estático** (sem `this`); `parameters` **imutável/sendable**; e o tipo de retorno `T` também **sendable** (objetos de `domain/model/` com só primitivos atendem).
- **O `process` é síncrono** (`ReturnSuccessOrError`, não `Future`): reforça que essa fase é CPU-bound pura. Toda chamada externa/assíncrona pertence ao **datasource**.
- `monitorExecutionTime: true` mede fetch + process e loga `(Direct)` ou `(Isolate)` via `dart:developer` — só para profiling em dev (compare os dois caminhos por volume); mantenha `false` em produção.

```dart
// Pesado → vale o isolate quando o volume compensa o custo de cópia entre isolates.
final usecase = GerarSalesReportUsecase(
  datasource: SalesGrpcDatasource(api: inject<ApiClient>()),
  runInIsolate: true,
);
final result = await usecase(SalesReportParameters(
  mes: 6, ano: 2026, error: const ErrorGeneric(message: 'Falha no relatório'),
));
```

> **Regra prática:** ligue `runInIsolate` só quando o `process` for de fato pesado (parsing/agregação de muitas linhas, criptografia, cálculo). Para processamento leve, o custo de copiar dados entre isolates não compensa — deixe `false`.

---

## 6. Erros de Domínio: estenda `AppError` por categoria

`AppError` é **imutável**: para enriquecer, use `copyWith` (que preserva o tipo concreto), nunca mutação. `ErrorGeneric` serve para casos triviais, mas a feature deve declarar **tipos de erro por categoria** — é o que o `ErrorMessageMapper` (i18n) usa para escolher a mensagem amigável (ver [construcao-apresentacao-erro-i18n.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-apresentacao-erro-i18n.md)).

```dart
@immutable
final class ErrorAuth implements AppError {
  @override
  final String message;

  const ErrorAuth({required this.message});

  @override
  ErrorAuth copyWith({String? message}) => ErrorAuth(message: message ?? this.message);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ErrorAuth && other.message == message;

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => '$runtimeType - $message';
}
```

> A interface `AppError` é consumida com `implements`, então **não herda** `==`/`hashCode`/`toString`. Implemente-os no erro custom quando quiser igualdade por valor (útil em asserts de teste) ou um `toString` legível — exatamente como o `ErrorGeneric` faz.

Categorias recomendadas (subtipos de `AppError`, reconhecidos pelo `ErrorMessageMapper`): `ErrorNetwork`, `ErrorUnauthorized`, `ErrorValidation`, `ErrorAuth`, além do `ErrorGeneric` como fallback.

---

## 7. Onde Vive Cada Arquivo (arquitetura por feature)

O padrão de organização do projeto inteiro é **feature-first**: dentro de um módulo, cada feature é uma pasta auto-contida com suas camadas. Layout canônico de uma feature:

```text
src/features/<feature>/
├── domain/
│   ├── parameters/<feature>_parameters.dart   # implements ParametersReturnResult (imutável/sendable)
│   ├── model/<objeto>.dart                     # objeto de domínio processado (imutável/sendable) — opcional
│   ├── services/<feature>_service.dart         # interface PÚBLICA (só se a feature expõe serviço)
│   └── usecases/<acao>_usecase.dart            # extends UsecaseBase(CallData) + getter `process` estático
├── data/
│   ├── datasources/<feature>_<transporte>_datasource.dart  # implements Datasource<D> (só I/O); usa api_client
│   └── services/<feature>_service_impl.dart    # implementação do serviço exposto (se houver)
└── presentation/
    ├── routes/<feature>_route.dart             # GetItModule (path + page + binds)
    ├── controllers/<feature>_controller.dart   # extends BaseController<T> → chama execute()
    ├── pages/<feature>_page.dart               # ModulePage / ViewStateBuilder
    └── widgets/<...>.dart
```

> Um **módulo** agrupa **uma ou mais features** sob `src/features/`. Features puramente de cálculo (sem UI) trazem só `domain/` (+ `data/` se houver datasource); features de tela trazem as três camadas. A estrutura física detalhada do módulo está na [anatomia-modulo.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/anatomia-modulo.md).

A ponte com a UI é o `BaseController.execute()`, que roda o usecase e faz o `switch` para `ViewState` (ver [construcao-modulo-presentation.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-modulo-presentation.md) §5.2):

```dart
final class SalesReportController extends BaseController<SalesReport> {
  final GerarSalesReportUsecase _gerar;
  SalesReportController({required GerarSalesReportUsecase gerar}) : _gerar = gerar;

  Future<void> gerar(int mes, int ano) => execute(
        () => _gerar(SalesReportParameters(
          mes: mes, ano: ano,
          error: const ErrorGeneric(message: 'Falha ao gerar relatório'),
        )),
      );
}
```

> **Sem Repository por padrão.** O usecase consome o `Datasource` diretamente. Só crie um `Repository` (ou um `Service` que combina usecases) quando precisar **orquestrar múltiplos datasources/usecases** ou manter estado entre chamadas (ex.: `AuthService` que guarda a `Session` — ver [anatomia-modulo.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/anatomia-modulo.md) §4.2).

---

## 8. Testes

### 8.1 Usecase (Dart puro, `package:test` ou `flutter_test`)

Mocka-se/fake-a o `Datasource` e verifica-se o resultado por `switch`. O novo fluxo permite testar quatro coisas: sucesso, **paridade direto×isolate**, **short-circuit** de erro do fetch, e erro de negócio do `process`.

```dart
const params = SalesReportParameters(
  mes: 6, ano: 2026,
  error: ErrorGeneric(message: 'Falha ao gerar relatório'),
);

test('processa as linhas cruas no objeto SalesReport (caminho direto)', () async {
  final usecase = GerarSalesReportUsecase(
    datasource: const FakeSalesDatasource(linhas: 1000),
  );
  final data = await usecase(params);
  switch (data) {
    case SuccessReturn<SalesReport>():
      expect(data.result.totalItens, equals(3000));
    case ErrorReturn<SalesReport>():
      fail('Esperava SuccessReturn: ${data.result.message}');
  }
});

test('o caminho isolate produz o MESMO resultado do direto', () async {
  final direto = GerarSalesReportUsecase(
      datasource: const FakeSalesDatasource(linhas: 5000), runInIsolate: false);
  final isolado = GerarSalesReportUsecase(
      datasource: const FakeSalesDatasource(linhas: 5000), runInIsolate: true);
  final a = await direto(params);
  final b = await isolado(params);
  expect(a, isA<SuccessReturn<SalesReport>>());
  expect(b, isA<SuccessReturn<SalesReport>>());
  // ...comparar campos de (a.result) e (b.result): devem ser iguais.
});

test('falha do datasource vira ErrorReturn enriquecido (Cod. 02-1)', () async {
  final usecase = GerarSalesReportUsecase(
    datasource: const FakeSalesDatasource(shouldThrow: true),
    runInIsolate: true, // mesmo com isolate, o fetch (e seu erro) é no principal
  );
  final data = await usecase(params);
  switch (data) {
    case SuccessReturn<SalesReport>():
      fail('Esperava ErrorReturn');
    case ErrorReturn<SalesReport>():
      expect(data.result.message, contains('Cod. 02-1'));
  }
});

test('regra de negócio do process (período sem vendas) vira ErrorReturn', () async {
  final usecase = GerarSalesReportUsecase(
    datasource: const FakeSalesDatasource(linhas: 0),
  );
  final data = await usecase(params);
  expect(data, isA<ErrorReturn<SalesReport>>());
});
```

### 8.2 Controller (`bloc_test`)

Mocka-se o usecase para devolver `SuccessReturn`/`ErrorReturn` e verifica-se a sequência de `ViewState` — padrão detalhado em [construcao-modulo-presentation.md](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/modelagem_frontend/construcao-modulo-presentation.md) §8.

---

## 9. Mudanças da v1.0.0 → v2.0.0 (o que ajustar no código existente)

| Aspecto | v1.0.0 (antigo) | **v2.0.0 (atual)** |
| :--- | :--- | :--- |
| Método/contrato do usecase | sobrescreve `run(parameters)` (assíncrono) | implementa o getter **`process`** → **função estática** (`ProcessData`/`ProcessPure`), **síncrona** |
| Fetch do datasource | a subclasse chamava `resultDatasource(parameters)` | **orquestrado pela base** (privado); a subclasse nunca chama o fetch |
| Short-circuit no erro do fetch | manual (a subclasse fazia `switch` no `resultDatasource`) | **automático** — se o fetch falha, o `process` nem é chamado |
| O que `runInIsolate` afeta | **todo o `run`** (incluindo o datasource) → quebrava com recursos nativos | **só o `process`**; o fetch fica sempre no isolate principal |
| Assinatura do `process` | n/a (era `run`, assíncrono) | `ProcessData<T,D>(D data, ParametersReturnResult p)` / `ProcessPure<T>(ParametersReturnResult p)` — **síncrono**, **estático** |
| Acesso a `this`/datasource no processamento | possível (era método de instância) | **proibido** — `process` é estático; receba tudo por parâmetro (cast do `parameters`) |
| Objeto processado pesado | misturado no `run` | datasource devolve **cru**; `process` agrega no `domain/model/` (sendable), opcionalmente em isolate |

**Migração mecânica de um usecase v1.0.0:**

1. Troque `@override Future<ReturnSuccessOrError<T>> run(P p) async => resultDatasource(p);` por:
   `@override ProcessData<T, D> get process => _process;` + a função estática `static ReturnSuccessOrError<T> _process(D data, ParametersReturnResult p) => SuccessReturn(success: data);`
2. Se o `run` antigo fazia `switch` no `resultDatasource` para transformar/validar, mova essa lógica para dentro do `_process`, agora recebendo `data` (o `D` já desempacotado) em vez do `ReturnSuccessOrError<D>`.
3. Mova qualquer parsing/agregação pesado para o `_process` e considere `runInIsolate: true`.
4. Garanta que `Parameters` e o tipo de retorno `T` sejam **imutáveis/sendable** (necessário para o isolate).

**O que se mantém:** o `switch` sobre `SuccessReturn`/`ErrorReturn`, o `AppError` carregado pelos parâmetros, `Unit`/`Nil` para sucessos sem dado, o `Datasource` que faz `throw parameters.error.copyWith(...)`, e a separação datasource → usecase → controller.

---

## 10. Checklist da Regra de Negócio de uma Feature

1. **Parameters** (`domain/parameters/`): `implements ParametersReturnResult`, `final`/**imutável e sendable**, expõe o `AppError get error` (campo ou getter). Ou `NoParams` se sem dados.
2. **Model** (`domain/model/`, opcional): objeto de domínio processado, **imutável e sendable** (só primitivos) — necessário se o `process` pesado roda em isolate.
3. **Datasource** (`data/datasources/`): `implements Datasource<D>`, **só I/O**, `try/catch` → `throw parameters.error.copyWith(...)`; devolve o dado **cru**; sufixo do transporte.
4. **Usecase** (`domain/usecases/`): `final class extends UsecaseBaseCallData<T, D>` (com datasource) ou `UsecaseBase<T>` (puro); implementa **`get process`** apontando para uma **função estática síncrona** (`ProcessData`/`ProcessPure`). Não sobrescreve `run`/`call`; não acessa `this`.
5. **Erro tipado**: estenda `AppError` por categoria (ou `ErrorGeneric` em casos triviais); imutável, com `copyWith`/`==`/`toString`.
6. **Recuperação**: sempre `switch` exaustivo — nunca `fold`/`getOrNull`.
7. **Isolate**: `runInIsolate: true` só para `process` CPU-bound pesado; `Parameters` e `T` precisam ser sendable. O fetch nunca vai para o isolate.
8. **Controller**: `BaseController<T>` + `execute(() => usecase(params))` — sem `try/catch` na UI.
9. **Testes**: usecase (fake/mock do datasource + `switch`; paridade direto×isolate; short-circuit de erro) e controller (`bloc_test`).
