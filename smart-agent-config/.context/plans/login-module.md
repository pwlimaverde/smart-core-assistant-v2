---
status: active
generated: 2026-06-15
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
    status: "pending"
  - id: "phase-e"
    name: "Execution — Frente A (borda gRPC-Web) → Frente B (login_module)"
    prevc: "E"
    agent: "backend-specialist"
    status: "pending"
  - id: "phase-v"
    name: "Validation — testes, grpcurl, build --wasm ponta-a-ponta"
    prevc: "V"
    agent: "test-writer"
    status: "pending"
  - id: "phase-c"
    name: "Confirmation — final-review, docs e arquivamento"
    prevc: "C"
    agent: "code-reviewer"
    status: "pending"
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
