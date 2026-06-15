# Documentação Auxiliar — Módulo de Login (login-module)

> Gerado em: 2026-06-14
> Plano canônico: `.context/plans/login-module.md`
> Plano completo: `.context/plans/login-module/plano_completo_login-module.md`
> Origem do plano: conversa (sessão de planejamento jun/2026)

Este documento reúne a documentação atual das libs e a referência de transporte/segurança
para a construção do `login_module` (Flutter Web/WASM, app `smart-core-admin`) consumindo o
auth da `runtime_api` via **gRPC-Web** (decisão **D7**, `doc_dev/planejamento/09-comunicacao-e-autenticacao.md`).

---

## 0. Contexto fixado (diretrizes travadas)

- **Transporte:** gRPC-Web nas duas frentes. (A) borda gRPC-Web no servidor + (B) `login_module` client.
- **Escopo de fluxos:** Login + sessão + guard de rota + **Refresh automático**. Fora: registro de conta (`RegisterRequest`) e features de domínio.
- **Storage:** refresh token em `flutter_secure_storage`; **access token só em memória** (`SessionService`), nunca persistido.
- **Auth no transporte:** cliente envia `authorization: Bearer <access>` no **metadata** gRPC-Web; a fachada Tonic converte para a convenção interna `causation_id` do Envelope. O client **não** conhece Envelope.
- **Ordem:** Frente A (borda, validável por `grpcurl`/`grpcui`) **antes** da Frente B (client).

---

## 1. Libs Rust (Frente A — servidor) — USAR LOCAL (central já curada)

Reaproveitadas da central local; nenhuma chamada ao Context7 necessária.

### tonic (0.14.6) + tonic-web (0.12) + tonic-build — fonte: `doc_dev/libs/rust/tonic-web.md` (✅ verificado 2026-06-04)
- **Servir gRPC-Web no mesmo processo, sem Envoy:** `Server::builder().accept_http1(true).layer(ServiceBuilder::new().layer(cors).layer(GrpcWebLayer::new()).into_inner()).add_service(svc).serve(addr)`.
- `accept_http1(true)` é **obrigatório** (browser usa HTTP/1.1); `GrpcWebLayer` traduz gRPC-Web ↔ gRPC.
- **CORS** (`tower-http` 0.5, feature `cors`): em produção restringir origem; expor headers `grpc-status`, `grpc-message`, `grpc-encoding`, `content-type`. **Ordem dos layers:** CORS **antes** de `GrpcWebLayer`.
- Como o WASM é servido na **mesma origem** que a API (atrás do mesmo reverse proxy), o CORS é trivial/efetivamente dispensável em produção — manter config restritiva mesmo assim.
- **Server streaming** é suportado por gRPC-Web sem mudança de código (relevante para o futuro `StreamAtendimentos`; **client/bidi streaming NÃO**).
- Interceptor JWT no servidor: `tonic::service::Interceptor` lê `authorization` do metadata.
- tonic-build gera os stubs Rust do `service AuthService`.

### prost — fonte: `doc_dev/libs/rust/prost.md`
- Serialização protobuf das mensagens do `auth.proto` (já em uso no codec do `transport`).

### Reuso direto do servidor (já implementado, NÃO reescrever)
- `application::auth::{login, refresh, logout}` — lógica de negócio completa (JWT HS256, refresh opaco SHA-256, rate limiting, rotação de família, blocklist). A fachada Tonic apenas **delega** para essas funções.
- `error_core::AppError` → mapear para `tonic::Status` na borda (sem vazar detalhe sensível).
- Convenção do Envelope: access token viaja no `causation_id` na borda e é removido antes do encaminhamento interno (doc 09, topo).

---

## 2. Libs Flutter/Dart (Frente B — client)

### 2.1 USAR LOCAL (central já curada)
- **return_success_or_error (2.0.0)** — `doc_dev/libs/flutter/return_success_or_error.md` + `doc_dev/modelagem_frontend/construcao-feature-com-return-success-or-error.md`. Padrão de feature: `Datasource<D>` (só I/O, `throw parameters.error.copyWith(...)`) → `UsecaseBaseCallData<T,D>` (getter `process` estático) → resultado selado `ReturnSuccessOrError<T>` recuperado **só por `switch`**. `runInIsolate` só para `process` pesado (não é o caso do login).
- **get_it / go_router / flutter_bloc** — `doc_dev/libs/flutter/{get_it,go_router,flutter_bloc}.md`. Já em uso na base: DI por escopo (`get_it_module`), rotas por `GetItModule`→`GoRoute`, `BaseController extends Cubit<ViewState<T>>`.

### 2.2 CRIADAS nesta reestruturação (Context7)

#### grpc (~4.0.0) — `doc_dev/libs/flutter/grpc.md` (✅ criado 2026-06-14, library id `/grpc/grpc-dart`)
- Canal gRPC-Web + stub gerado; metadata por chamada (`CallOptions(metadata|providers)`), `WebCallOptions(bypassCorsPreflight, withCredentials)`.
- Geração de stubs: `dart pub global activate protoc_plugin` + `protoc --dart_out=grpc:lib/src/generated -Iprotos protos/auth.proto`. Runtime `package:protobuf`.
- `ClientInterceptor.interceptUnary` **retorna `ResponseFuture<R>` síncrono** — injetar token via `CallOptions(providers:[...])`; **não** fazer retry-após-refresh dentro do interceptor.
- Erros: `on GrpcError catch (e)` → `e.code` (`StatusCode.unauthenticated` = 16, `invalidArgument` = 3, `unavailable` = 14, `permissionDenied` = 7), `e.message`.

> ⚠️ **RISCO CRÍTICO — WASM:** `GrpcWebClientChannel.xhr()` usa `dart:html`/XMLHttpRequest,
> **indisponível em `flutter build web --wasm`**. Em WASM é preciso o transporte baseado em
> `package:web`/`dart:js_interop` (gRPC-Web sobre `fetch`). **Validar no início da Frente B**:
> provar a conexão gRPC-Web sob `--wasm` (não só JS) e fixar o construtor/versão corretos do
> `grpc`. Não assumir `.xhr()`.

#### flutter_secure_storage (~9.x/10.x) — `doc_dev/libs/flutter/flutter_secure_storage.md` (✅ criado 2026-06-14)
- API: `write/read/delete/deleteAll/containsKey`. Será a **impl real do `LocalStorageService`** (hoje no-op em `core_module`).
- **Web/WASM:** backend `localStorage` criptografado via Web Cryptography API (SubtleCrypto); v10+ removeu `dart:io` (compatível WASM). **HTTPS obrigatório** (Web Crypto exige contexto seguro).
- **Limitações de segurança no Web (assumidas):** vulnerável a **XSS** (JS malicioso acessa o storage); sem isolamento de memória como em mobile. Mitigação aceita no escopo: só o **refresh token** é persistido (rotaciona + detecção de reuso server-side já existente); access fica em memória. CSP forte recomendada no reverse proxy.
- Boas práticas: namespacing de chave (ex.: `smartcore_admin_auth_refresh_token`); tratar `read` nulo no boot (auto-login silencioso).

---

## 3. Serviços Externos (Grupo B)

**Nenhuma API de terceiros.** O auth é próprio (`runtime_api`). Componentes de infraestrutura interna:
- **Caddy (reverse proxy):** termina TLS e serve, na **mesma origem**, o bundle WASM (`flutter build web --wasm`) e a API gRPC-Web (`/`-routing para o endpoint Tonic). Config é artefato do plano (não há doc externo a coletar). Garante origem única (CORS trivial) e HTTPS (exigência do Web Crypto do secure storage).

---

## 4. Observabilidade & Auditoria (Grupo C — transversal)

> Princípio inviolável: todo comportamento novo emite log estruturado + erro rastreável + trace, e não vaza segredo/PII.

### Frente A — borda gRPC-Web (`runtime_api`)
- **Logs/trace (`tracing`):** span por RPC na fachada (`Login`/`Refresh`/`Logout`) com `service=runtime_api`, `env`, e **`traceparent`** propagado do metadata para o Envelope (`#[tracing::instrument(skip_all, fields(traceparent))]`, como o `login.rs` atual). Mapear `AppError → Status` registrando `error_code` sem detalhe sensível.
- **Auditoria (`audit_log`):** **reaproveitada** — já ocorre server-side a jusante: `login_failed`/`login_success` (`data_postgres`), `token_reuse_detected` no `security:stream` (`data_redis`/`application::auth::refresh`), publicada assíncrona via `transport::bus`. A fachada **não** duplica auditoria; apenas garante propagar `traceparent`/contexto. Eventos críticos sensíveis (login, refresh, logout) já cobertos pelo plano `user-auth-module`.
- **Sanitização:** **nunca** logar `email`/`password`/tokens (o `login.rs` já usa `skip_all` e correlaciona por `traceparent`/hash). Rate limiting por e-mail **hasheado**. Segredos em `secrecy::SecretString`. Registrar IP do cliente agora que a borda gRPC-Web existe (item pendente do doc 09 §6.4).

### Frente B — client `login_module`
- **Logs:** client loga **apenas** endpoint/status/estado de fluxo (o `ApiClientStub` atual só loga `endpoint=... status=...`). **Proibido** logar token/credenciais/refresh (regra do `SessionService`). Erros viram `AppError` tipado (`ErrorAuth`/`ErrorUnauthorized`/`ErrorNetwork`/`ErrorValidation`) → `ErrorMessageMapper` (i18n).
- **Auditoria:** **sem evento de auditoria no client** (intencional — a auditoria é server-side, na borda/`data_postgres`).
- **Sanitização:** access token só em memória; refresh em `flutter_secure_storage`; nada de `print` de valores sensíveis; limpar storage + memória no logout.

---

## 5. Notas gerais / riscos a tratar no plano completo

1. **WASM × gRPC-Web (`.xhr` indisponível)** — risco técnico #1; prova de conceito da conexão sob `--wasm` é o primeiro passo da Frente B.
2. **Fachada Tonic é nova na `runtime_api`** — hoje só existe o `transport::Server` (framing custom sobre TCP/UDS). A fachada gRPC-Web roda **em paralelo** (porta HTTP própria) delegando para `application::auth::*`; decidir se convive com o `transport::Server` ou se há um novo binário/porta.
3. **`auth.proto` precisa do `service AuthService`** — hoje só tem as mensagens (`LoginRequest`/`AuthResponse`); faltam `service` + `RefreshRequest`/`LogoutRequest`/`LogoutResponse`. Regeneração Rust (tonic-build) e Dart (protoc_plugin).
4. **Mapeamento `AppError → tonic::Status`** — `Auth`→`unauthenticated`, `RateLimit`→`resource_exhausted`/`unavailable`, `Validation`→`invalid_argument`, demais→`internal`; mensagens amigáveis sem vazar interno.
5. **Refresh automático** — orquestrar no `AuthGrpcDatasource`/`AuthService` (capturar `unauthenticated` → `RefreshTokenUsecase` → refazer), **não** no interceptor. Tratar corrida (múltiplas chamadas expirando juntas) com lock/single-flight do refresh.
6. **Substituições na base** — `core_module/InfraModule` hoje registra `AuthServiceNoOp` e `LocalStorageServiceNoOp`; o `login_module` passa a registrar `AuthService` real (globalBind) e a impl real de `LocalStorageService` (secure storage). Guard de auth substitui o placeholder `_readyRoute`/`_bootRedirect` em `app.dart`.
7. **CSP/HTTPS** — Caddy deve servir sob HTTPS (Web Crypto) e com CSP forte (mitiga XSS do secure storage no Web).
