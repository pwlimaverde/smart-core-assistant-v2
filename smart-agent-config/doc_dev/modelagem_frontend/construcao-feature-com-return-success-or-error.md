# Construção de Feature com `return_success_or_error` (v3.0.1)

Como se escreve uma operação de negócio nos clients Flutter. Vale para todos os
módulos: `login_module`, `operacional_module`, `tenant_module`, `admin_module`.

> **Atualizado na fase C1** (migração v2 → v3). A v3 é uma reformulação
> *breaking*: erro parametrizado e fechado por feature, camada `Repository`
> obrigatória, `Datasource` burro. A §10 lista o que mudou.

---

## 1. As três camadas

```text
Datasource  →  Repository  →  Usecase
   (I/O)       (fronteira)     (regra)
```

| Camada | Responsabilidade | Nunca faz |
|---|---|---|
| `Datasource<TData, TParams>` | Chama o mundo externo e converte a resposta no modelo de domínio | Não captura exceção, não conhece erro de domínio |
| `RepositoryBase<TData, TParams, TError>` | Captura a exceção técnica e a traduz num erro do conjunto fechado da feature (`mapError`) | Não tem regra de negócio |
| `UsecaseBaseCallData<TValue, TData, TParams, TError>` | Orquestra fetch → curto-circuito → `process`; converte bug em erro previsto (`onUnexpected`) | Não faz I/O |

O resultado de tudo é um `ReturnSuccessOrError<TValue, TError>`: `Success(valor)`
ou `Failure(erro)`. **Nenhuma exceção atravessa as camadas.**

---

## 2. O erro é fechado por feature

Cada feature declara os erros que pode produzir numa hierarquia `sealed`. É isso
que torna o `switch` exaustivo — o compilador cobra o tratamento de cada caso, e
um erro novo quebra a compilação em vez de passar silencioso.

```dart
sealed class TenantsError extends AppError {
  const TenantsError(super.message);
}

final class TenantsAcessoNegado extends TenantsError with UnauthorizedFailure {
  const TenantsAcessoNegado()
    : super('Somente o superusuário pode administrar tenants.');
}

final class TenantsConflito extends TenantsError {
  const TenantsConflito()
    : super('Já existe um tenant com este slug ou e-mail.');
}

final class TenantsInesperado extends TenantsError with UnexpectedFailure {
  const TenantsInesperado()
    : super('Não foi possível concluir a operação. Tente novamente.');
}
```

### 2.1 Um conjunto por feature ou por operação?

**Regra:** um conjunto por feature quando as operações compartilham o repertório
de falha; um por operação quando o repertório divergir de verdade.

| Situação | Exemplo no repo |
|---|---|
| **Por feature** — CRUD sobre o mesmo recurso, mesmas falhas | As 8 features do `admin_module`: listar/criar/atualizar tenants podem todas receber acesso negado, conflito, dado inválido |
| **Por operação** — repertórios diferentes | `login_module`: "credenciais inválidas" não existe no logout; "sem sessão persistida" só existe no refresh |
| **Por operação** — uma delas é pública | `tenant_module`: `acceptInvite` não tem "acesso negado" (o convidado ainda não tem conta) |

### 2.2 Marcadores transversais

Erro fechado por feature significa que a apresentação não tem um tipo comum a que
reagir. Os **marcadores** do `domain_models` resolvem isso sem reabrir o conjunto:

```dart
base mixin NetworkFailure on AppError {}       // ofereça nova tentativa
base mixin UnauthorizedFailure on AppError {}  // o guard derruba a sessão
base mixin ValidationFailure on AppError {}    // destaque o campo
base mixin UnexpectedFailure on AppError {}    // mensagem genérica + log
```

O `ErrorMessageMapper` casa pelo marcador; o erro concreto continua fechado na
feature.

### 2.3 Regra de segurança do caso "inesperado"

O caso marcado com `UnexpectedFailure` **nunca** concatena a exceção na mensagem.
O texto é fixo e genérico; a exceção e o stack trace vão para `developer.log`.

Antes da C1 o padrão era `ErrorNetwork(message: '$e')` e
`parameters.error.copyWith(message: '$e')` — caminho de arquivo do servidor e
endereço de serviço interno chegavam à tela. O `ErrorMessageMapper` hoje impõe a
mensagem genérica como defesa em profundidade.

---

## 3. Parameters: só dados

```dart
final class CreateTenantParameters extends Parameters {
  final String name;
  final String slug;
  final int ownerId;
  final String email;
  final String phone;

  const CreateTenantParameters({
    required this.name,
    required this.slug,
    required this.ownerId,
    required this.email,
    required this.phone,
  });
}
```

Um `Parameters` por operação. Ele atravessa as três camadas e chega ao `mapError`
como contexto — então **objetos com segredo (senha, token, chave de API) nunca
entram em log**, nem via `parameters`. Operações sem entrada usam o singleton
`noParams`.

---

## 4. Datasource: burro, sem `try/catch`

```dart
final class CreateTenantDatasource
    implements Datasource<Tenant, CreateTenantParameters> {
  final proto.AdminServiceClient _client;

  const CreateTenantDatasource({required this._client});

  @override
  Future<Tenant> call(CreateTenantParameters parameters) async {
    final resp = await _client.createTenant(
      proto.CreateTenantRequest(
        name: parameters.name,
        slug: parameters.slug,
        ownerId: parameters.ownerId,
        email: parameters.email,
        phone: parameters.phone,
      ),
    );
    return Tenant.doProto(resp.tenant);
  }
}
```

A exceção sobe crua, com todo o contexto, para o `mapError`. Campos opcionais do
protobuf chegam como `0`/vazio — normalize para `null` aqui.

---

## 5. Repository: a fronteira

```dart
final class CreateTenantRepository
    extends RepositoryBase<Tenant, CreateTenantParameters, TenantsError> {
  const CreateTenantRepository({required super.datasource});

  @override
  TenantsError mapError(
    Object exception,
    StackTrace stackTrace,
    CreateTenantParameters parameters,
  ) {
    final kind = classificarFalhaGrpc(exception);
    developer.log(
      'createTenant falhou: $kind',
      name: 'admin_module.tenants',
      error: exception,
      stackTrace: stackTrace,
    );
    return switch (kind) {
      GrpcFailureKind.unauthenticated ||
      GrpcFailureKind.permissionDenied => const TenantsAcessoNegado(),
      GrpcFailureKind.alreadyExists => const TenantsConflito(),
      GrpcFailureKind.unavailable => const TenantsIndisponivel(),
      _ => const TenantsInesperado(),
    };
  }
}
```

`classificarFalhaGrpc` (do `api_client`) traduz o status code numa
`GrpcFailureKind` **sem semântica de domínio**; o `mapError` decide o que aquela
natureza significa na feature. A tabela de status codes existe **uma vez** no
monorepo — antes eram quatro cópias de `mapGrpcError`, uma por módulo.

`mapError` é abstrato de propósito: toda exceção precisa de um destino previsto.

---

## 6. Usecase: a regra

```dart
final class CreateTenantUsecase
    extends UsecaseBaseCallData<
      Tenant, Tenant, CreateTenantParameters, TenantsError> {
  const CreateTenantUsecase({required super.repository});

  @override
  ProcessData<Tenant, Tenant, CreateTenantParameters, TenantsError>
      get process => _process;

  @override
  TenantsError onUnexpected(Object exception, StackTrace stackTrace) {
    developer.log('process de createTenant quebrou',
        name: 'admin_module.tenants', error: exception, stackTrace: stackTrace);
    return const TenantsInesperado();
  }

  static ReturnSuccessOrError<Tenant, TenantsError> _process(
    Tenant data,
    CreateTenantParameters parameters,
  ) => Success(data);
}
```

O `process` é uma função **estática** (não captura `this`) que recebe o dado bruto
já carregado e os parâmetros tipados. Passthrough é legítimo: o valor da base está
no `onUnexpected` e no curto-circuito.

Quando há regra de verdade, ela vive aqui — não na tela. Exemplos no repo:

- `GetThreadUsecase` ordena as mensagens por **timestamp**, não por id: no desktop
  a mensagem pendente de sync tem id negativo provisório e apareceria no topo do
  histórico.
- `ListInvitesUsecase` põe os convites pendentes primeiro: a tela existe para agir
  sobre o que está pendente.

> **Cuidado:** o `process` roda **depois** do fetch. Validação de entrada não cabe
> nele — isso é da apresentação (desabilitar o botão) e do servidor
> (`invalidArgument` → erro de validação no `mapError`).

`UsecaseBase` (sem `CallData`) é para regra pura, sem fonte de dados.

---

## 7. Streams não passam pela lib

A lib modela request/response: um `ReturnSuccessOrError` descreve *um* desfecho.
Um fluxo contínuo tem N desfechos e um ciclo de vida (abre, cai, reconecta).

Para stream, declare um **port de domínio próprio**:

```dart
abstract interface class AtendimentoEventoStream {
  Stream<AtendimentoEvento> abrir();
}
```

Erro e encerramento chegam como erro/fim do próprio `Stream`; a política de
reconexão (backoff + jitter) vive na apresentação, onde está o ciclo de vida da
tela.

---

## 8. Quando a plataforma varia, e não a operação

O `operacional_module` lê do gRPC-Web no browser e do motor local Rust (SQLite +
fila offline) no desktop. Aí o que varia é a **plataforma**, não a operação:

- um **gateway agregado** (`AtendimentoGateway`) por plataforma, escolhido por
  import condicional, mantém coerentes as quatro operações e o stream — no desktop
  todas compartilham o mesmo índice e a mesma fila;
- os `Datasource` da lib ficam **em cima** dele: adaptadores finos, um por
  operação, que traduzem `Parameters` → chamada do gateway.

Quebrar isso em oito classes (4 operações × 2 plataformas) espalharia essa
coerência por uma matriz.

O gateway também é burro. Ele embrulha a falha do FFI em `LocalEngineFalha`
(exceção **técnica**, não erro de domínio) para que o `mapError` distinga "o
armazenamento local falhou" de "a rede falhou" — desfechos com ações diferentes
para o usuário.

---

## 9. Consumo na apresentação

`BaseController.execute` recebe o resultado e emite os estados:

```dart
Future<void> fetchTenants() => execute(() => _listUsecase(noParams));
```

O genérico do erro é **por chamada**, não por controller — o mesmo controller
orquestra usecases de features vizinhas. Na fronteira da UI o erro é degradado
para `AppError`, que é tudo de que `ErrorState` precisa: uma mensagem.

Ações de escrita costumam **devolver** o resultado em vez de emitir estado de
erro, para a lista continuar exibida e a falha aparecer em snackbar:

```dart
Future<ReturnSuccessOrError<Tenant, TenantsError>> createTenant({...}) async {
  final res = await _createUsecase(CreateTenantParameters(...));
  if (res is Success) await fetchTenants();   // recarrega só em sucesso
  return res;
}
```

Na tela, sempre pelo mapper:

```dart
if (res case Failure(:final error)) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(ErrorMessageMapper.map(error))),
  );
}
```

---

## 10. O que mudou da v2 para a v3

| v2 | v3 |
|---|---|
| `ReturnSuccessOrError<T>` | `ReturnSuccessOrError<TValue, TError>` |
| `SuccessReturn(success: v)` / `.result` | `Success(v)` / `.value` |
| `ErrorReturn(error: e)` / `.result` | `Failure(e)` / `.error` |
| `Datasource<T>` fazia `throw parameters.error` | `Datasource<TData, TParams>` deixa a exceção subir |
| sem camada de fronteira | `RepositoryBase` + `mapError` **obrigatório** |
| `ParametersReturnResult` com `AppError get error` | `Parameters`, só dados |
| `implements AppError` + `copyWith` | `extends AppError` (é `base`), sem `copyWith` |
| exceção do `process` virava cópia do erro dos parâmetros | `onUnexpected` **obrigatório**, nos dois caminhos |
| `process` recebia `ParametersReturnResult` e fazia cast | `process` recebe `TParams` tipado |
| erros globais em `domain_models` | conjunto `sealed` por feature + marcadores |

---

## 11. Testes de uma feature

| Alvo | O que provar |
|---|---|
| **Datasource** | conversão protobuf→modelo (campos, listas vazias, opcionais `0`→`null`); a exceção do client **sobe crua** |
| **Repository** | um caso por `GrpcFailureKind` → erro esperado; a mensagem do erro **não contém** o texto da exceção |
| **Usecase** | sucesso; curto-circuito (repositório falha → `process` não roda); `onUnexpected` (repositório fora do contrato → erro previsto); a regra, quando existe |
| **Controller** | `Initial → Loading → Success` e `→ Error`; recarga condicional após mutação |
| **Page** | render de cada estado, diálogo principal, ação chamando o controller |

Ferramentas e armadilhas conhecidas:

- `api_client/testing.dart`: `respostaGrpc`, `falhaGrpc`, `streamGrpc`,
  `streamGrpcComFalha` — o `ResponseFuture`/`ResponseStream` dos stubs gerados não
  se constrói sem um `ClientCall` real.
- Monte a **cadeia real** trocando só o stub gRPC (ou o gateway): o teste passa a
  cobrir conversão, `mapError` e `process`, não só a orquestração de estado.
- Curto-circuito **não chama o `process`** — teste o sucesso de cada operação, ou
  metade dos `process` nunca roda.
- Página que lê `GoRouterState` precisa de um `GoRouter` real em volta.
- Página que importa `dart:js_interop` (download no browser) **não carrega na VM**
  do `flutter test`; cubra o comportamento pelo controller.
