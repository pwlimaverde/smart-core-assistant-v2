# Fase C1 — Reconstrução dos clients Flutter sobre `return_success_or_error` 3.0.1

> **Status:** **CONCLUÍDA** em 2026-07-27 (planejada em 2026-07-26).
> **Escopo:** `clients/` (5 packages, 10 módulos, 2 apps). Nada de `server/` ou `ia_engine/`.
> **Branch:** `feature/clients-rsoe-v3` (a partir da `dev`), um commit por etapa.
> **Idioma:** documentação e comentários em pt-br; identificadores em inglês (padrão do repo).

---

## 1. Objetivo

Três entregas em um único ciclo:

1. **Migrar os clients para a v3.0.1** da lib (hoje `^2.0.0`), que é uma reformulação
   *breaking* do tratamento de erro: erro **parametrizado e fechado por feature**, nova
   camada **`Repository`** obrigatória, `Datasource` burro, `Parameters` sem erro,
   `Success`/`Failure` no lugar de `SuccessReturn`/`ErrorReturn`, `onUnexpected` e
   `mapError` abstratos.
2. **Separar as features de verdade** e endereçar as violações de SOLID que a estrutura
   atual acumulou (um god-service de 24 métodos, um god-datasource de 746 linhas, usecases
   anêmicos que só delegam).
3. **Fechar a cobertura de testes** — hoje 107 dos 235 arquivos de produção (≈6.900 linhas)
   não são carregados por **nenhum** teste, e a métrica oficial esconde isso.

---

## 2. Baseline medido (2026-07-26)

```
.\infra\test-flutter.ps1 -Coverage     → 337 testes, tudo verde, analyze limpo
```

| Métrica | Valor |
|---|---|
| Testes executados | **337** (17 pacotes; `local_engine_ffi` sem `test/`) |
| Cobertura publicada ("significativa") | **95,1%** (1145/1204 linhas) |
| Cobertura real do lcov agregado | **74,9%** (1165/1555 linhas) |
| Linhas hoje **fora** do denominador | 351 (`data/datasources`, `presentation/pages`, `presentation/routes`) — cobertas em **5,7%** |
| Arquivos de produção | 235 (excluídos protobuf gerado, bindings frb, cargokit, example) |
| Arquivos **sem nenhum teste** | **107** (≈6.911 linhas) |

Os 14 maiores arquivos sem teste algum:

| Linhas | Arquivo |
|---|---|
| 689 | `admin_module/.../presentation/pages/billing_page.dart` |
| 446 | `admin_module/.../presentation/pages/audit_page.dart` |
| 438 | `admin_module/.../presentation/pages/tenant_config_page.dart` |
| 375 | `admin_module/.../presentation/pages/tenants_page.dart` |
| 331 | `admin_module/.../presentation/pages/core_settings_page.dart` |
| 329 | `operacional_module/.../data/datasources/atendimento_local_engine_data_source.dart` |
| 327 | `admin_module/.../presentation/pages/feature_flags_page.dart` |
| 322 | `admin_module/.../presentation/pages/dashboard_page.dart` |
| 287 | `tenant_module/.../presentation/convites/pages/invites_page.dart` |
| 271 | `tenant_module/lib/src/data/datasources/tenant_admin_grpc_datasource.dart` |
| 250 | `admin_module/.../presentation/pages/evolution_page.dart` |
| 186 | `tenant_module/.../presentation/usuarios/pages/tenant_users_page.dart` |
| 170 | `tenant_module/.../presentation/config/pages/tenant_own_config_page.dart` |
| 154 | `admin_module/lib/src/admin_module.dart` |

> A exclusão de `datasources|pages|routes` está codificada **em dois lugares**:
> `infra/test-flutter.ps1:176` e `.github/workflows/ci.yml:333` (ratchet com piso 85%).
> Ambos serão corrigidos na etapa C1.10 — sem isso, o número continua não dizendo a verdade.

Ambiente confirmado: **Dart 3.12.2 / Flutter 3.44.2**; a lib exige `sdk: ^3.12.0`. Compatível.

---

## 3. Achados no código atual (o que a migração precisa consertar)

### 3.1 God-service e god-datasource no `admin_module`
- `domain/services/admin_service.dart`: **uma interface com 24 métodos** para 8 assuntos
  distintos (settings, tenants, billing, flags, auditoria, evolution, dashboard, config).
  Violação direta de ISP/SRP — todo controller depende da interface inteira.
- `data/services/admin_service_impl.dart` (433 linhas): o **mesmo** `try/catch` repetido 24
  vezes (`on AppError` → `ErrorReturn`; `catch` → `ErrorNetwork('$e')`). É exatamente o
  papel que a v3 dá ao `RepositoryBase.mapError`.
- `data/datasources/admin_grpc_datasource.dart` (746 linhas): 24 chamadas gRPC + 24
  mapeamentos proto→modelo num único arquivo.
- **Uma única "feature" `config`** abriga tudo. O doc `anatomia-modulo.md` já manda
  feature-first; a estrutura não obedece.

### 3.2 Usecases anêmicos
`ListTenantsUsecase`, `UpdateTenantUsecase` e os outros 22 **não estendem base nenhuma** da
lib: são wrappers de uma linha sobre o god-service, com parâmetros nomeados soltos em vez de
um `Parameters`. Não há `process`, não há `Repository`, não há erro tipado por feature —
a lib está no `pubspec` mas praticamente não é usada onde deveria.

Mesmo padrão em `tenant_module` (8 usecases) e `operacional_module` (4).
Só o `login_module` usa `UsecaseBaseCallData` de verdade (3 usecases).

### 3.3 `tenant_module` sem `features/`
Estrutura é `src/{data,domain,presentation}` com a apresentação subdividida por assunto
(`convites`, `usuarios`, `config`) — invertida em relação ao padrão do repo (feature-first,
camadas dentro da feature).

### 3.4 Erros: 5 tipos globais para 39 operações
`domain_models` expõe `ErrorAuth`, `ErrorUnauthorized`, `ErrorNetwork`, `ErrorValidation`,
`ErrorLocalEngine` — todos `implements AppError` (a v3 torna `AppError` uma `base class`:
`implements` deixa de compilar) com `copyWith` (saiu do contrato na v3). Nenhum conjunto é
fechado por feature, então nenhum `switch` de erro é exaustivo hoje.

### 3.5 O que já está bom e será preservado
- `presentation_module` (`BaseController`/`ViewState`/`ModulePage`/`ViewStateBuilder`) tem
  desenho correto e trata o erro como `AppError` na fronteira da UI — muda pouco.
- `login_module`: separação de camadas correta, `AuthServiceImpl` com estado de sessão
  legítimo (single-flight de refresh, notifier para o guard do GoRouter).
- `design_system_module` (96,9%) e `api_client` (100%): mantidos.
- Os fluxos de tela e o comportamento visual — **decisão: preservar** (nada de redesenho).

---

## 4. Decisões de arquitetura

### D1 — Erros: hierarquia `sealed` por feature + mixins marcadores transversais
Cada feature declara o seu conjunto fechado:

```dart
// login_module/lib/src/features/login/domain/errors/login_errors.dart
sealed class LoginError extends AppError {
  const LoginError(super.message);
}

final class CredenciaisInvalidas extends LoginError {
  const CredenciaisInvalidas() : super('E-mail ou senha inválidos.');
}

final class LoginBloqueadoPorTentativas extends LoginError {
  const LoginBloqueadoPorTentativas()
      : super('Muitas tentativas. Aguarde antes de tentar novamente.');
}

final class LoginIndisponivel extends LoginError with NetworkFailure {
  const LoginIndisponivel() : super('Servidor indisponível. Tente novamente.');
}

final class LoginInesperado extends LoginError with UnexpectedFailure {
  const LoginInesperado() : super('Ocorreu um erro inesperado. Tente novamente.');
}
```

`domain_models` deixa de exportar erros concretos e passa a exportar **marcadores**, que dão
tratamento transversal sem quebrar a exaustividade de cada feature:

```dart
// packages/domain_models/lib/src/errors/failure_markers.dart
mixin NetworkFailure {}       // servidor indisponível / sem conexão
mixin UnauthorizedFailure {}  // sessão expirada → guard derruba a sessão
mixin ValidationFailure {}    // entrada inválida → realça o campo
mixin UnexpectedFailure {}    // bug convertido por onUnexpected/mapError
```

**Regra de segurança (herdada de `security.md`):** o caso "inesperado" **nunca** concatena a
exceção na mensagem exibida. O texto é fixo e genérico; a exceção e o stack trace vão para
`developer.log` dentro do `mapError`/`onUnexpected`. Isso corrige o comportamento atual
(`ErrorNetwork(message: '$e')` e `parameters.error.copyWith(message: '$e')`), que joga o
detalhe técnico na tela.

### D2 — A fronteira da UI continua em `AppError`
Como toda hierarquia de feature estende `AppError`, `ViewState.ErrorState`, `ModulePage.onError`
e `ViewStateBuilder.onError` seguem tipados em `AppError`, sem parâmetro extra. `BaseController`
ganha só um genérico local no método:

```dart
Future<void> execute<E extends AppError>(
  Future<ReturnSuccessOrError<T, E>> Function() task,
) async {
  emit(LoadingState<T>());
  switch (await task()) {
    case Success(:final value): emit(SuccessState<T>(value));
    case Failure(:final error): emit(ErrorState<T>(error));
  }
}
```

Exaustividade fica onde há decisão de negócio (usecase, repository, controller); a UI, que só
precisa de uma mensagem, não paga o custo de propagar `E` por toda a árvore de widgets.

### D3 — `Repository` por operação; a camada "Service" god-object morre
`AdminService`/`AdminServiceImpl`, `TenantAdminService`/`Impl` e `AtendimentoService`/`Impl`
são **deletados**. Cada operação passa a ter o seu trio `Datasource → Repository → Usecase`, e
o controller depende dos usecases (como já depende hoje).

**Exceção justificada:** `AuthService` do `login_module` **permanece** — não é um god-object,
é uma feature de serviço com estado (sessão em memória, refresh single-flight, `Listenable`
para o guard). Ele passa a orquestrar os usecases v3 em vez de falar com datasources.

### D4 — Classificação de `GrpcError` centralizada, tradução na feature
Os 4 `grpc_error_mapper.dart` duplicados (um por módulo) são substituídos por um
classificador único no `api_client` (que já é a fronteira gRPC):

```dart
// packages/api_client/lib/src/errors/grpc_failure_kind.dart
enum GrpcFailureKind { unauthenticated, permissionDenied, invalidArgument,
                       notFound, rateLimited, unavailable, unknown }

GrpcFailureKind classificarFalhaGrpc(Object exception);
```

Cada `mapError` traduz a **categoria** para um caso do seu conjunto fechado — a tabela de
status codes existe uma vez, e a semântica de domínio fica na feature:

```dart
@override
LoginError mapError(Object exception, StackTrace stackTrace, LoginParameters parameters) {
  developer.log('login falhou', error: exception, stackTrace: stackTrace,
      name: 'login_module');            // e-mail/senha JAMAIS entram no log
  return switch (classificarFalhaGrpc(exception)) {
    GrpcFailureKind.unauthenticated => const CredenciaisInvalidas(),
    GrpcFailureKind.invalidArgument  => const LoginDadosInvalidos(),
    GrpcFailureKind.rateLimited      => const LoginBloqueadoPorTentativas(),
    GrpcFailureKind.unavailable      => const LoginIndisponivel(),
    _                                 => const LoginInesperado(),
  };
}
```

### D5 — Streams ficam fora da lib, em port próprio
`streamAtendimentos()` não tem representação em `ReturnSuccessOrError` (a lib é
request/response). Vira um port dedicado — `domain/streams/atendimento_evento_port.dart` —
implementado no `data/`, consumido direto pelo `ChatController`/`KanbanController`, que já
possuem a política de reconexão (backoff + jitter). Nada de embrulhar stream em resultado.

### D6 — `runInIsolate` só onde há CPU-bound real
Os `process` desta base de código são passthrough (`Success(data)`) ou transformações
triviais. `runInIsolate` fica **desligado** em todos, exceto onde a medição justifique:
candidato único é `exportTenantsCsv` (gera `List<int>` de CSV). Decide-se com medição na
etapa C1.7, não por palpite.

### D7 — Um `Parameters` por operação, mesmo com um campo
Operações sem entrada usam `noParams` (singleton). Nada de parâmetros nomeados soltos no
`call` do usecase: é o `Parameters` que atravessa as três camadas e que o `mapError` recebe
como contexto.

### D8 — Estrutura física canônica de uma operação
```text
features/<feature>/
├── domain/
│   ├── errors/<feature>_errors.dart          # sealed <Feature>Error + casos
│   ├── model/                                # só tipos exclusivos da feature
│   ├── parameters/<operacao>_parameters.dart  # extends Parameters
│   └── usecases/<operacao>_usecase.dart       # UsecaseBaseCallData<...>
├── data/
│   ├── datasources/<operacao>_grpc_datasource.dart   # Datasource<TData, TParams>, sem try/catch
│   └── repositories/<operacao>_repository.dart       # RepositoryBase + mapError
└── presentation/
    ├── controllers/ pages/ routes/ widgets/          # preservados
```

---

## 5. Padrão canônico (referência de implementação)

Exemplo completo — `tenants/list` do `admin_module`:

```dart
// domain/parameters/list_tenants_parameters.dart
final class ListTenantsParameters extends Parameters {
  final bool apenasAtivos;
  const ListTenantsParameters({this.apenasAtivos = false});
}

// data/datasources/list_tenants_grpc_datasource.dart
// Burro: I/O e mapeamento proto→modelo. NENHUM try/catch — a exceção sobe crua.
final class ListTenantsGrpcDatasource
    implements Datasource<List<Tenant>, ListTenantsParameters> {
  final AdminServiceClient _client;
  const ListTenantsGrpcDatasource({required AdminServiceClient client})
      : _client = client;

  @override
  Future<List<Tenant>> call(ListTenantsParameters parameters) async {
    final resp = await _client.listTenants(ListTenantsRequest());
    return resp.tenants.map(Tenant.doProto).toList(growable: false);
  }
}

// data/repositories/list_tenants_repository.dart
// Fronteira: traduz exceção técnica em erro do conjunto fechado da feature.
final class ListTenantsRepository extends RepositoryBase<
    List<Tenant>, ListTenantsParameters, TenantsError> {
  const ListTenantsRepository({required super.datasource});

  @override
  TenantsError mapError(Object exception, StackTrace stackTrace,
      ListTenantsParameters parameters) {
    developer.log('listTenants falhou', error: exception,
        stackTrace: stackTrace, name: 'admin_module.tenants');
    return switch (classificarFalhaGrpc(exception)) {
      GrpcFailureKind.unauthenticated || GrpcFailureKind.permissionDenied =>
        const TenantsAcessoNegado(),
      GrpcFailureKind.unavailable => const TenantsIndisponivel(),
      _ => const TenantsInesperado(),
    };
  }
}

// domain/usecases/list_tenants_usecase.dart
final class ListTenantsUsecase extends UsecaseBaseCallData<
    List<Tenant>, List<Tenant>, ListTenantsParameters, TenantsError> {
  const ListTenantsUsecase({required super.repository});

  @override
  ProcessData<List<Tenant>, List<Tenant>, ListTenantsParameters, TenantsError>
      get process => _process;

  @override
  TenantsError onUnexpected(Object exception, StackTrace stackTrace) {
    developer.log('process de listTenants quebrou', error: exception,
        stackTrace: stackTrace, name: 'admin_module.tenants');
    return const TenantsInesperado();
  }

  // Regra da feature: o filtro de ativos é decisão de negócio, não de I/O.
  static ReturnSuccessOrError<List<Tenant>, TenantsError> _process(
    List<Tenant> data,
    ListTenantsParameters parameters,
  ) => Success(parameters.apenasAtivos
        ? data.where((t) => t.active).toList(growable: false)
        : data);
}
```

---

## 6. Inventário: 39 operações + 1 stream, em 16 features

### `login_module` → 1 feature (`login`), 3 operações + storage
`login`, `refresh`, `logout` · erros: `LoginError`, `RefreshError`, `LogoutError`
(o `TokenLocalDatasource`/`SecureLocalStorage` continua fonte do `refresh`).

### `operacional_module` → 1 feature (`atendimento`), 4 operações + 1 stream
`listAtendimentos`, `getThread`, `moveAtendimentoEtapa`, `sendOutboundMessage`
+ port de stream (D5) · erro: `AtendimentoError`.
Datasource duplo (remoto gRPC / local engine FFI) preservado via factory por plataforma.

### `tenant_module` → 3 features, 8 operações
| Feature | Operações |
|---|---|
| `convites` | `createInvite`, `listInvites`, `revokeInvite`, `acceptInvite` |
| `usuarios` | `listTenantUsers`, `updateTenantUser` |
| `config` | `getMyTenantConfig`, `updateMyTenantConfig` |

### `admin_module` → 8 features, 24 operações
| Feature | Operações |
|---|---|
| `core_settings` | `list`, `upsert`, `delete` |
| `tenants` | `list`, `get`, `create`, `update`, `setActive`, `generateAccessCode`, `exportCsv` |
| `tenant_config` | `get`, `update` |
| `billing` | `listPlans`, `createPlan`, `updatePlan`, `listSubscriptions`, `registerPayment`, `listPayments` |
| `feature_flags` | `list`, `set`, `setOverride` |
| `audit` | `queryAuditLog` |
| `evolution` | `testConnection` |
| `dashboard` | `getServiceHealth`, `getDashboardSummary` |

**Volume estimado:** ~165 arquivos criados/reescritos, ~60 deletados (god-services,
god-datasources, mappers duplicados, usecases anêmicos).

---

## 7. Etapas

Cada etapa termina com `flutter analyze` limpo e testes verdes **no pacote tocado**, e um
commit próprio. O workspace só volta a compilar inteiro no fim de C1.8 — é o custo de uma
migração *breaking* num pub workspace, e a razão da branch dedicada.

| Etapa | Entregável | Aceite |
|---|---|---|
| **C1.0** | Branch; bump `return_success_or_error: ^3.0.1` nos 7 pubspecs; `dart pub get`; este documento | `pubspec.lock` em 3.0.1 |
| **C1.1** | `domain_models`: mixins marcadores; remoção dos 5 erros globais; testes | pacote verde, 100% |
| **C1.2** | `api_client`: `GrpcFailureKind` + `classificarFalhaGrpc`; testes de cada status code | pacote verde, 100% |
| **C1.3** | `presentation_module`: `execute<E>`, `ErrorMessageMapper` por marcador; testes | pacote verde, 100% |
| **C1.4** | `login_module`: feature `login` completa (3 ops), `AuthServiceImpl` sobre usecases | módulo verde |
| **C1.5** | `operacional_module`: 4 ops + port de stream; controllers adaptados | módulo verde |
| **C1.6** | `tenant_module`: reestruturado em 3 features, 8 ops | módulo verde |
| **C1.7** | `admin_module`: 8 features, 24 ops (**8 commits**, um por feature) | módulo verde |
| **C1.8** | `core_module`, `navigation_module`, apps: wiring/DI/guard | **workspace inteiro verde** |
| **C1.9** | Cobertura: os 107 arquivos sem teste (páginas, datasources, DI dos módulos) | ver §8 |
| **C1.10** | Docs (`construcao-feature-com-return-success-or-error.md` → v3, `anatomia-modulo.md`, changelog) + `test-flutter.ps1` e `ci.yml` sem as exclusões, ratchet novo | CI verde |

---

## 8. Plano de testes e cobertura

### Por camada (o que cada teste prova)
| Alvo | Casos obrigatórios |
|---|---|
| **Datasource** | mapeamento proto→modelo (campos, listas vazias, enums); a exceção do client **sobe crua** (nada de try/catch engolindo) |
| **Repository** | um caso por `GrpcFailureKind` → erro esperado da feature; sucesso devolve `Success` com o dado; **a mensagem do erro não contém o texto da exceção** |
| **Usecase** | sucesso; **curto-circuito** (repository falha → `process` não é chamado); `onUnexpected` (process lança → `Failure` do caso previsto); regra de negócio quando existe |
| **Controller** | `Initial → Loading → Success` e `→ Error` (bloc_test), recarga após mutação |
| **Page/Widget** | render de cada `ViewState`, ação principal chamando o controller, campos obrigatórios |
| **Módulo (DI)** | cada tipo registrado resolve (`inject<T>()`), rotas expostas |

Estimativa: **337 → ~750 testes**.

### Cobertura — alvo e exclusões
Alvo: **100% de linhas** nos pacotes de produção, com exclusões explícitas e justificadas:

| Exclusão | Motivo |
|---|---|
| `packages/api_client/lib/src/generated/**` | protobuf gerado |
| `packages/local_engine_ffi/lib/src/rust/**`, `cargokit/**`, `example/**` | bindings frb e ferramenta de build |
| `apps/*/lib/main.dart` | bootstrap de processo (coberto por boot/E2E) |
| `modulos/dependencies_module` | somente `export` |

**Sai da lista de exclusões:** `data/datasources/**` e `presentation/{pages,routes}/**`. Eram
5,7% cobertos e valem 351 linhas — passam a contar. Datasource é testável com mock do client
gRPC (é o que o `admin_service_impl_test.dart` já faz hoje); página é testável com
`testWidgets`. **Sem golden tests** — divergência de renderização de fonte entre Windows local
e o runner Linux do CI produz falso vermelho sem ganho real.

---

## 9. Riscos

| Risco | Mitigação |
|---|---|
| Workspace vermelho entre C1.1 e C1.8 | branch dedicada; análise/teste por pacote em foco; merge só com tudo verde |
| `admin_module` é metade do trabalho (24 ops) | 8 commits, um por feature, cada um verde isoladamente |
| Ratchet do CI (piso 85%) quebra ao remover as exclusões | ajuste do piso no **mesmo** commit que remove a exclusão (C1.10) |
| `AuthServiceImpl` tem estado sutil (single-flight, notifier) | testes atuais preservados como rede; migração de tipos sem tocar a lógica |
| `atendimento_local_engine_data_source` (329 linhas) exige mock do FFI | fake do binding na fronteira Dart; o `local_engine` Rust já é coberto do lado servidor |
| Diff grande dificulta revisão | commit por etapa/feature, com o inventário desta §6 como mapa |

---

## 10. Checklist de aceite final

- [ ] `return_success_or_error: ^3.0.1` em todos os pubspecs; nenhuma referência a
      `SuccessReturn`, `ErrorReturn`, `ParametersReturnResult`, `copyWith` de erro ou
      `implements AppError` restante no repo.
- [ ] 16 features com conjunto de erros `sealed` próprio; nenhum `switch` de erro com braço
      `default` em domínio/controller.
- [ ] Nenhum arquivo de produção com mais de ~200 linhas em `data/`; god-services deletados.
- [ ] `.\infra\test-flutter.ps1 -Coverage` verde, com o denominador honesto (sem as três
      exclusões antigas) e ≥ o alvo definido em §8.
- [ ] Docs de frontend descrevendo a v3 (`Datasource → Repository → Usecase`).
- [ ] `ci.yml` verde na branch antes do merge na `dev`.


---

## 12. Resultado (2026-07-27)

Executada em 11 commits na branch `feature/clients-rsoe-v3`, um por etapa.

| Métrica | Antes | Depois |
|---|---|---|
| Testes | 337 | **675** |
| Cobertura publicada | 95,1% (denominador maquiado) | **79,6%** (denominador honesto) |
| Denominador | 1.204 linhas | 3.631 linhas |
| Arquivos de produção sem teste algum | 107 | 7 páginas parcialmente cobertas |
| Features | 4 módulos, 1 delas com 24 operações | **16 features** |
| God-objects | 3 (24, 8 e 5 métodos) | 0 |
| Cópias de `mapGrpcError` | 4 | 1 classificador central |
| Pacotes em 100% de linhas | — | 9 |

### O que não foi fechado

718 das 741 linhas ainda descobertas estão nos **diálogos e formulários das sete
páginas do `admin_module`**. Cada diálogo tem 50–100 linhas de formulário, e
fechá-los exige teste de interação campo a campo. A renderização, os estados
(carregado/erro), a navegação por abas e um diálogo completo (novo tenant) já
estão cobertos.

O piso do ratchet no CI ficou em **78%** — o valor medido com margem pequena.
Ao fechar os diálogos, suba o piso no mesmo commit.

### Correção pós-push (CI vermelho no 22897f4)

O passo de cobertura Flutter reprovou com **77,8%**. Não era o cálculo: seis
arquivos de teste (`test/features/.../data/...`, quatro do `login_module` e dois
do `operacional_module`) casavam a regra genérica `data/` do `.gitignore` e nunca
foram commitados — 185 linhas cobertas que o CI contava como descobertas. A
exceção que já existia para o mesmo problema cobria só `clients/**/lib/**/data/`;
foi estendida para `test/` e `integration_test/`, e o check do
`infra/test-flutter.ps1` (que olhava apenas `lib/`) passou a cobrir os três.

**A cobertura do CI é ~79,3%, não 79,6%:** nove linhas de construtores `const` em
`feature_flags_errors.dart` contam como executadas na VM local e não na do runner.
Diferença de instrumentação, único arquivo afetado — mas a margem real sobre o
piso é ~1,3 ponto, não 1,6.

### Desvios em relação ao plano

1. **`AuditPage` sem widget test** (§8 previa todas as páginas): importa
   `dart:js_interop` para o download do CSV e não carrega na VM do `flutter test`.
   Coberta pelo controller.
2. **Arquivos agregados por camada** em vez de um arquivo por operação
   (`<feature>_datasources.dart`, `_repositories.dart`, `_usecases.dart`): são a
   mesma costura repetida N vezes, e 165 arquivos de 15 linhas atrapalhariam a
   navegação mais do que ajudariam. A separação por camada e por feature — o que
   importa para as dependências — está preservada.
3. **Gateway agregado no `operacional_module`** (não previsto): o eixo de variação
   ali é a plataforma, não a operação. Ver §8 do doc da lib.
