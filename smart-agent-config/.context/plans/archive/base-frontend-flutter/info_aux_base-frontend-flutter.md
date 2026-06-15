# Documentação Auxiliar — Base do Monorepo Frontend Flutter

> Gerado em: 2026-06-14
> Plano canônico: `.context/plans/base-frontend-flutter.md`
> Plano completo: `.context/plans/base-frontend-flutter/plano_completo_base-frontend-flutter.md`
> Stack: **Flutter/Dart** (Dart SDK 3.12.2 / Flutter 3.44.2)

Fase de **base estrutural** do `clients/` (greenfield) — packages estruturais, módulos de
infra e a casca do app. **Sem regra de negócio.** `api_client`/`domain_models` são stubs.

---

## 1. Pub Workspaces (configuração oficial do Dart)

Fonte: https://dart.dev/tools/pub/workspaces e https://dart.dev/tools/pub/pubspec

- **Disponível a partir do Dart SDK 3.6.0.** Globs no campo `workspace:` desde Dart 3.11.
- **`pubspec.yaml` raiz** precisa de:
  - `name` (obrigatório; convenção `_` ou nome do monorepo),
  - `publish_to: 'none'`,
  - `environment.sdk` com lower bound ≥ 3.6.0 (usamos `^3.12.2`),
  - campo **`workspace:`** com a lista de caminhos dos membros (relativos à raiz).
- **Cada membro** precisa de:
  - **`resolution: workspace`**,
  - `environment.sdk` compatível (≥ 3.6.0).
- **Um único** `pubspec.lock` + `.dart_tool/package_config.json` na raiz, compartilhado por
  todos os membros. O pub limpa locks/configs em diretórios intermediários.
- Membros devem ficar **dentro da árvore de diretórios** da raiz.
- Interdependências por `path: ../outro` continuam válidas (resolvidas localmente).
- `flutter pub get` (ou `dart pub get`) em **qualquer** nível resolve o lock único.
- `dart pub workspace list` lista os membros.

**Exemplo raiz:**
```yaml
name: smart_core_clients
publish_to: 'none'
environment:
  sdk: ^3.12.2
workspace:
  - packages/app_config
  - packages/get_it_module
  - apps/smart-core-admin
dev_dependencies:
  melos: ^7.8.2
melos:
  name: smart_core_clients
  scripts:
    analyze: { run: melos exec -- flutter analyze . }
    test: { run: melos exec --dir-exists=test -- flutter test }
```

**Exemplo membro:**
```yaml
name: app_config
environment:
  sdk: ^3.12.2
resolution: workspace
```

**Melos 7.x** usa os Pub Workspaces nativos; a config do Melos (scripts/versionamento) vive na
seção `melos:` do pubspec raiz. Não há `melos.yaml` standalone.

---

## 2. Versões fixadas (estáveis mais recentes — compatíveis com Dart 3.12.2 / Flutter 3.44.2)

Fonte: páginas pub.dev (versão + changelog + environment), verificado 2026-06-14.

| Package | Versão | SDK/Flutter mín. | Notas |
| :-- | :-- | :-- | :-- |
| `bloc` | `^9.2.1` | Dart ≥ 2.14 | API `Cubit` estável. |
| `flutter_bloc` | `^9.1.1` | Dart ≥ 2.14 | `BlocProvider`/`BlocBuilder`/`BlocListener`/`Cubit` estáveis no 9.x. |
| `get_it` | `^9.2.1` | Dart ≥ 2.14 | `pushNewScope`/`dropScope`/`hasScope`/`registerLazySingleton(dispose:)` estáveis. |
| `go_router` | `^17.3.0` | Flutter ≥ 3.38 / Dart ≥ 3.10 | `redirect`/`refreshListenable`/`GoRoute.builder`/`MaterialApp.router` estáveis. |
| `intl` | `^0.20.2` | — | export com `hide TextDirection`. |
| `uuid` | `^4.5.3` | — | `Uuid().v4()` igual. |
| `return_success_or_error` | `^2.0.0` | Dart ≥ 3.12.0 | pub.dev, publisher `pwlimaverde`, MIT. Usecase via `process` estático (fetch/process separados). |
| `melos` | `^7.8.2` (dev) | Dart ≥ 3.6.0 | Pub Workspaces nativo. |
| `bloc_test` | `^10.0.0` (dev) | Dart ≥ 2.14 | compatível com bloc 9.x. |
| `mocktail` | `^1.0.5` (dev) | — | mocks. |
| `flutter_lints` | `^6.0.0` (dev) | — | lints. |

Todas as APIs usadas pela arquitetura (Cubit; escopos do GetIt; `redirect`/`refreshListenable`
do go_router; `switch` exaustivo do `return_success_or_error`) são estáveis nessas majors.

---

## 3. API do `return_success_or_error` 2.0.0

Detalhe completo em `doc_dev/libs/flutter/return_success_or_error.md` e no guia de feature
`doc_dev/modelagem_frontend/construcao-feature-com-return-success-or-error.md`. Essencial:
- `sealed ReturnSuccessOrError<R>` → `SuccessReturn<R>(success:)` / `ErrorReturn<R>(error:)`,
  getter `result`. Consumo **só** por `switch` exaustivo (sem `fold`/`getOrNull`/`isSuccess`).
- `AppError` (abstract interface; `message`, `copyWith`); `ErrorGeneric` pronto.
- `ParametersReturnResult` (`error`); `NoParams`. Imutáveis/**sendable** (cruzam o isolate).
- `Datasource<D>` (`Future<D> call(...)` — só I/O; dado **cru** ou `throw`).
- `UsecaseBase<T>` / `UsecaseBaseCallData<T,D>` — a subclasse implementa o getter **`process`**
  (função **estática síncrona**: `ProcessPure<T>` / `ProcessData<T,D>`), **não** `run`. A base
  orquestra **fetch → short-circuit → process**; `runInIsolate` afeta **só o `process`** (o
  fetch fica sempre no isolate principal); `resultDatasource` é privado.

> Usecases/Datasources/Parameters pertencem às **features** (fora desta base). Aqui só o
> `BaseController.execute()` consome `ReturnSuccessOrError` via `switch` — inalterado na 2.0.0.

---

## 4. Serviços externos
**Nenhum nesta fase.** `api_client` é stub (Dart puro, `connect()` no-op). gRPC/gRPC-Web/
FlatBuffers + autenticação JWT + Envelope ficam para fase futura.

---

## 5. Observabilidade & Auditoria (frontend)
**Sem evento de `audit_log`** em todas as etapas (intencional — auditoria é backend, via
`transport::bus`→`data_postgres`). Disciplina equivalente:
- **Erro rastreável:** `AppError` → `ErrorState<T>` (`BaseController.execute` com `switch`) →
  `ErrorMessageMapper` (mensagem localizada). UI nunca trata `Exception` cru.
- **Não-vazamento:** `SessionService` guarda token/refresh — proibido logar; `ApiClient.connect()`
  loga só endpoint/status; sem credenciais no código; endpoints via `--dart-define`.

---

## 6. Referências
- Arquitetura: `smart-agent-config/doc_dev/modelagem_frontend/` (anatomia-modulo, arquitetura-
  monorepo-frontend, construcao-package-get-it-module, construcao-modulo-presentation,
  construcao-modulo-navigation, construcao-modulo-design-system, construcao-bootstrap-
  inicializacao, construcao-apresentacao-erro-i18n, construcao-feature-com-return-success-or-error).
- Central de libs: `doc_dev/libs/flutter/{go_router,melos,return_success_or_error,flutter_bloc,get_it,mocktail}.md`.
- Pub Workspaces: https://dart.dev/tools/pub/workspaces
