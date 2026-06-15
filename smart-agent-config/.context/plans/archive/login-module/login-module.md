---
status: completed
generated: 2026-06-15
completed: 2026-06-15
prevc_scale: LARGE
artifacts:
  plano_completo: "./login-module/plano_completo_login-module.md"
  info_aux: "./login-module/info_aux_login-module.md"
phases:
  - id: "phase-p"
    name: "Planning — definição de escopo e diretrizes"
    prevc: "P"
    agent: "architect-specialist"
    status: "completed"
  - id: "phase-r"
    name: "Review — ratificar arquitetura (fachada gRPC-Web, WASM, refresh)"
    prevc: "R"
    agent: "architect-specialist"
    status: "completed"
  - id: "phase-e"
    name: "Execution — Frente A (borda gRPC-Web) → Frente B (login_module)"
    prevc: "E"
    agent: "backend-specialist"
    status: "completed"
  - id: "phase-v"
    name: "Validation — testes, grpcurl, build --wasm ponta-a-ponta"
    prevc: "V"
    agent: "test-writer"
    status: "completed"
  - id: "phase-c"
    name: "Confirmation — final-review, docs e arquivamento"
    prevc: "C"
    agent: "code-reviewer"
    status: "completed"
---

# Módulo de Login (Flutter Web/WASM) × borda gRPC-Web

> Construir o `login_module` no app `smart-core-admin` (Flutter Web/WASM) consumindo o auth da
> `runtime_api` via **gRPC-Web** (decisão **D7**), em duas frentes: **(A)** fachada gRPC-Web no
> servidor (Tonic + tonic-web delegando para `application::auth::*`) e **(B)** o `login_module`
> client seguindo o padrão de feature `return_success_or_error`. Escopo: **Login + sessão + guard
> de rota + Refresh automático**. Refresh em `flutter_secure_storage`; access token só em memória.

## Artefatos detalhados (fonte da verdade)

- **Plano completo (verdade técnica, etapas e código):** [plano_completo_login-module.md](./login-module/plano_completo_login-module.md)
- **Documentação auxiliar (libs, snippets, riscos, observabilidade):** [info_aux_login-module.md](./login-module/info_aux_login-module.md)

## Diretrizes travadas

| # | Diretriz |
|---|---|
| D7 | gRPC-Web nas duas frentes. |
| Escopo | Login + sessão + guard + **Refresh automático**. FORA: registro de conta (`RegisterRequest`) e features de domínio. |
| Storage | Refresh em `flutter_secure_storage`; access só em memória (`SessionService`), nunca persistido. |
| Transporte | `authorization: Bearer <access>` no metadata gRPC-Web; a fachada Tonic converte para `causation_id` do `Envelope`. Client não conhece `Envelope`. |
| Reuso | Reaproveitar 100% de `application::auth::{login,refresh,logout}`; a fachada apenas delega. |
| Ordem | Frente A (borda, validável por `grpcurl`) antes da Frente B (client). |

## Fases PREVC

- **P — Planning** ✅ concluído: escopo, transporte (D7), storage e ordem das frentes definidos (esta sessão).
- **R — Review:** ratificar R1.1–R1.7 do plano completo (porta da fachada, conversão metadata→Envelope, `AppError→Status`, ordem CORS→GrpcWebLayer, **gate WASM B0**, refresh fora do interceptor).
- **E — Execution:** Frente A (A1–A5: `auth.proto`+`service`, deps Tonic, fachada delegadora, servir com tonic-web, Caddy) → Frente B (B0–B9: PoC WASM, stubs, feature `login`, `api_client` gRPC-Web, datasources, `AuthServiceImpl` single-flight, UI, integração/guard, i18n).
- **V — Validation:** `cargo test`, `grpcurl`/`grpcui` (5 cenários do doc 09 §6.4), testes Dart (usecase/controller/datasource/single-flight/guard), build `--wasm` ponta-a-ponta.
- **C — Confirmation:** gate `prevc-final-review`, atualização de docs, arquivamento do plano.

## Riscos-chave

1. **WASM × gRPC-Web** — `GrpcWebClientChannel.xhr()` não roda em `--wasm` (gate B0, transporte sobre `fetch`).
2. **Fachada Tonic é nova** na `runtime_api` (hoje só `transport::Server`); roda em task/porta própria delegando para `application::auth::*`.
3. **Corrida de refresh** — single-flight no `AuthServiceImpl`; retry fora do interceptor síncrono.
4. **XSS/secure storage no Web** — só refresh persiste; CSP forte + HTTPS/HSTS no Caddy.
5. **Dois `AuthService`** (core fino × login rico) — interface única rica no `login_module`.

## Observabilidade & Auditoria

- **Frente A:** span por RPC com `traceparent` propagado; auditoria reaproveitada (`login_success`/`token_reuse_detected`/`logout` server-side); registrar IP do cliente; nunca logar email/senha/tokens (`skip_all`, `secrecy`).
- **Frente B:** client loga só endpoint/status; **sem auditoria no client** (intencional); access só em memória, refresh em secure storage; logout limpa tudo.

---

## Conclusão (2026-06-15)

Ciclo PREVC concluído na branch `feature/login-module`. Ambas as frentes implementadas, testadas e com build `--wasm` verde.

### Resultado da Validação
- **Frente A:** `cargo test -p runtime_api` → 10/10 (6 handlers + 4 da fachada). `cargo build --workspace` e `cargo test --workspace --no-run` ok (bump do `prost` não regrediu nada).
- **Frente B:** `flutter test` do `login_module` → 16/16 (usecases, controller `bloc_test`, refresh single-flight, mapeamento gRPC/JWT) + guard 3/3 no app. `flutter analyze` limpo em todos os pacotes tocados.
- **WASM ponta-a-ponta:** `flutter build web --wasm` do `smart-core-admin` → `✓ Built build\web`.
- **Pendente de infra (manual):** os 5 cenários `grpcurl`/`grpcui` (doc 09 §6.4) exigem `runtime_api` no ar com Postgres/Redis; a lógica está coberta por testes unitários, mas a verificação ao vivo fica para o ambiente com infra.

### Divergências em relação ao plano (registradas)
1. **Gate B0 já resolvido pela versão:** no `grpc ^4.x` o transporte gRPC-Web (`xhr_transport.dart`) usa `package:web`/`dart:js_interop` — **compatível com `--wasm`**. Mantivemos `GrpcWebClientChannel.xhr()` (não há necessidade de transporte alternativo); o risco #1 some ao fixar `grpc ^4.0.1`.
2. **`flutter_secure_storage` exige v10+:** a v9 puxa `flutter_secure_storage_web` baseado em `dart:html` e **quebra o build WASM**. Fixado `^10.0.0` (backend web em `package:web`).
3. **Bump `prost` 0.13 → 0.14** no workspace Rust: o `service AuthService` gera código tonic 0.14 que exige `tonic-prost`/`prost` 0.14. Alinhado todo o stack; `tonic-web 0.14`.
4. **`api_client` com superfície dividida:** barrel neutro (`api_client.dart`, compila em VM+web) + entrypoint web-only `grpc_web_client.dart` (isola `GrpcApiClient`/`package:web`). Sem isso, os testes de VM não compilam.
5. **`ApiClient` migrado para o `LoginModule`:** o `InfraModule` deixou de registrar `ApiClient`/`AuthService`/`LocalStorageService` para manter o `core_module` neutro (VM+web). O `GrpcApiClient` (borda) é registrado pelo `LoginModule.globalBinds`.
6. **Reconciliação dos dois `AuthService`:** adotada a variante (ii) — `AuthServiceImpl` implementa **ambos** os contratos (rico do `login_module` + fino `core.AuthService`) e é registrado para os dois tipos (sem ciclo: `core_module` não depende do `login_module`).
7. **Erros tipados em `domain_models`:** `ErrorAuth/ErrorUnauthorized/ErrorNetwork/ErrorValidation` vivem no pacote compartilhado (consumidos por data e pelo `ErrorMessageMapper` da presentation), evitando ciclos.
8. **Guard como função pura testável:** `authRedirectTarget(...)` isolada em `auth_redirect.dart` (sem DI/UI/transporte), testada na VM; `_authRedirect` só injeta o estado.

### Áreas autenticadas
Adicionada rota placeholder `/home` (com logout) como destino pós-login; features de domínio seguem fora do escopo.
