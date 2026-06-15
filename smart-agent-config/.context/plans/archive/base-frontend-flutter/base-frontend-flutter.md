---
status: in_progress
generated: 2026-06-14
updated: 2026-06-14
slug: base-frontend-flutter
scale: LARGE
artifacts:
  plano_completo: "./base-frontend-flutter/plano_completo_base-frontend-flutter.md"
  info_aux: "./base-frontend-flutter/info_aux_base-frontend-flutter.md"
phases:
  - id: "phase-p"
    name: "Planning — escopo da base, grafo de conexão e versões fixadas"
    prevc: "P"
    agent: "architect-specialist"
    status: "completed"
  - id: "phase-r"
    name: "Review — cascata de dependências, Pub Workspaces e contratos de infra"
    prevc: "R"
    agent: "architect-specialist"
    status: "completed"
  - id: "phase-e"
    name: "Execution — cronograma: packages → módulos → agregador → splash → app"
    prevc: "E"
    agent: "frontend-specialist"
    status: "completed"
  - id: "phase-v"
    name: "Validation — melos analyze/test por etapa + app sobe no Chrome"
    prevc: "V"
    agent: "test-writer"
    status: "completed"
  - id: "phase-c"
    name: "Confirmation — final-review e arquivamento dotcontext"
    prevc: "C"
    agent: "frontend-specialist"
    status: "in_progress"
---

# Base do Monorepo Frontend Flutter — `base-frontend-flutter`

> Plano **canônico** (leve). A verdade técnica detalhada está nos artefatos abaixo.
> Construção **greenfield**: `clients/` é montada do zero, em cronograma incremental
> (cada etapa entrega um pacote/módulo compilável e validável isoladamente).
> Arquitetura: `smart-agent-config/doc_dev/modelagem_frontend/`.

## Artefatos

- **Plano completo (verdade técnica):**
  [`./base-frontend-flutter/plano_completo_base-frontend-flutter.md`](./base-frontend-flutter/plano_completo_base-frontend-flutter.md)
- **Documentação auxiliar (Pub Workspaces + versões das libs):**
  [`./base-frontend-flutter/info_aux_base-frontend-flutter.md`](./base-frontend-flutter/info_aux_base-frontend-flutter.md)

## Objetivo

Montar a **base estrutural** do frontend Flutter — injeção de dependências modular, estado
padronizado, navegação, design system, configuração por ambiente e a casca do app Web admin —
pronta para receber features de domínio depois. **Apenas infraestrutura, SEM regra de negócio.**

**Dentro do escopo:** workspace Dart (Pub Workspaces) + Melos; packages `app_config`,
`domain_models` (stub), `get_it_module`, `api_client` (stub); módulos `presentation_module`,
`design_system_module`, `navigation_module`, `core_module`, `dependencies_module`,
`initial_loading_module`; app `smart-core-admin` (Web) + i18n base.

**Fora do escopo:** `login_module` e features de domínio + guard de auth real; transporte real
no `api_client` (gRPC/FlatBuffers) + DTOs `.proto` em `domain_models`; apps
`smart-core-windows-tenant`/`smart-core-web-tenant`; `plugins/`.

## Versões fixadas (estáveis mais recentes — Dart 3.12.2 / Flutter 3.44.2)

`bloc ^9.2.1` · `flutter_bloc ^9.1.1` · `get_it ^9.2.1` · `go_router ^17.3.0` · `intl ^0.20.2`
· `uuid ^4.5.3` · `return_success_or_error ^2.0.0` (pub.dev) · `melos ^7.8.2` ·
`bloc_test ^10.0.0` · `mocktail ^1.0.5` · `flutter_lints ^6.0.0`.

## Grafo de conexão (cascata de dependências)

`app_config` / `domain_models` / `get_it_module` (base) → `api_client`, `presentation_module`,
`design_system_module`, `navigation_module` → `core_module` (InfraModule + contratos) →
`dependencies_module` (âncora de imports) → `initial_loading_module` (splash) →
`smart-core-admin` (app). `core_module` depende de packages/módulos diretamente (nunca de
`dependencies_module`); `dependencies_module` reexporta só infra; features/app importam um lugar só.

## Cronograma (fase E — detalhe no plano completo)

| Etapa | Entrega | Validação |
|---|---|---|
| **0** | Esqueleto do workspace (`pubspec.yaml` raiz + `workspace:` + Melos) | `flutter pub get` na raiz; `melos --version` |
| **1** | Packages: `app_config`, `domain_models`, `get_it_module`, `api_client` | `flutter analyze`; teste de escopo/boot do `get_it_module` |
| **2** | Módulos: `presentation_module`, `design_system_module`, `navigation_module`, `core_module` | `bloc_test` do `BaseController`; teste do `AppRouter`/`InfraModule` |
| **3** | `dependencies_module` (agregador) | analyze + consumidor que importa só o agregador |
| **4** | `initial_loading_module` (splash + boot por estágios) | `bloc_test` do controller |
| **5** | `smart-core-admin` (casca + i18n) | `flutter run -d chrome -t lib/main_dev.dart` |
| **6** | Qualidade: `melos run analyze`/`test`, `dart format` | 0 issues; testes verdes |

## Fases PREVC

| Fase | Nome | Agente | Status |
|---|---|---|---|
| **P** | Planning — escopo, grafo de conexão e versões | Architect Specialist | ✅ completed |
| **R** | Review — cascata, Pub Workspaces, contratos de infra | Architect Specialist | ✅ completed |
| **E** | Execution — cronograma packages→módulos→agregador→splash→app | Frontend Specialist | ⏳ pending |
| **V** | Validation — `melos analyze`/`test` por etapa + app no Chrome | Test Writer | ⏳ pending |
| **C** | Confirmation — final-review e arquivamento | Frontend Specialist | ⏳ pending |

## Decisões-chave

1. **Pub Workspaces nativo (Dart ≥ 3.6):** `pubspec.yaml` raiz com `workspace:` + cada membro
   com `resolution: workspace`; lock único na raiz. Melos 7.x para scripts (`analyze`/`test`).
2. **Versões mais recentes estáveis** (tabela acima); APIs usadas (Cubit, escopos GetIt,
   `redirect`/`refreshListenable`) estáveis nessas majors.
3. **`get_it_module`** é package Flutter (usa `GetItModuleScope`); demais packages são Dart-puro.
4. **Construção incremental:** cada etapa compila/valida isolada antes da próxima.
5. **Estado sempre `ViewState<T>`; UI só trata `AppError`; controllers sem `BuildContext`.**

## Observabilidade & Auditoria

Frontend estrutural: **sem evento de `audit_log`** (auditoria é backend). Disciplina:
**erro rastreável** (`AppError`→`ErrorState`→`ErrorMessageMapper`); **não-vazamento** (proibido
logar token/refresh do `SessionService`; `ApiClient.connect()` loga só endpoint/status; sem
credenciais no código; endpoints via `--dart-define`).

## Verificação

`cd clients` → `flutter pub get` (lock único) → `melos run analyze` (0 issues) →
`melos run test` → `cd apps/smart-core-admin && flutter run -d chrome -t lib/main_dev.dart`
(splash boota, `BootState` libera a barreira). Branch `feature/setup-flutter-web-admin`
(gitflow); commits sem auto-referência; comentários pt-br.
