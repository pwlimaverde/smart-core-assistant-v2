# Plano de Implementação — `login_module` (Flutter Web/WASM × borda gRPC-Web)

> **Feature:** `login-module`
> **Ciclo:** PREVC — **P**lanning concluído; este documento detalha **R**eview, **E**xecution, **V**alidation, **C**onfirmation.
> **Fonte da verdade técnica:** `.context/plans/login-module/info_aux_login-module.md` (libs, snippets, riscos, eixos de Observabilidade & Auditoria).
> **Idioma:** documentação e comentários em **pt-br**; identificadores em **inglês**.
> **Ordem inviolável:** **Frente A** (borda gRPC-Web no servidor, validável por `grpcurl`/`grpcui`) **antes** de **Frente B** (client).

---

## 0. Diretrizes Travadas (não reabrir)

| # | Diretriz |
|---|---|
| D7 | **gRPC-Web** nas duas frentes. |
| Escopo | Login + sessão + guard de rota + **Refresh automático**. **FORA:** `RegisterRequest` (registro) e features de domínio. |
| Storage | **Refresh** em `flutter_secure_storage`; **access** só em memória (`SessionService`), **nunca** persistido. |
| Transporte/auth | Client envia `authorization: Bearer <access>` no **metadata** gRPC-Web. A fachada Tonic converte para `causation_id` do `Envelope`. **O client não conhece o `Envelope`.** |
| Reuso | Reaproveitar **100%** de `application::auth::{login,refresh,logout}`. A fachada Tonic **apenas delega** — não reescreve regra de negócio. |

---

## 1. Mapa Arquitetural Confirmado (inspeção do código real)

Pontos validados nos arquivos reais que **condicionam** o plano:

1. **`runtime_api` hoje NÃO usa Tonic.** O `server/apps/runtime_api/src/main.rs` sobe um `transport::Server` (framing custom UDS/TCP), com rotas `Login`/`Refresh`/`Logout`/admin e o interceptor `exigir_auth`. **Não há `tonic`/`tower-http` no `Cargo.toml`.** → A fachada gRPC-Web é um **componente novo**, rodando **em paralelo** numa **porta HTTP própria**, que **delega** para `application::auth::*` (mesmas funções que o `transport::Server` já chama).
2. **A convenção de borda já existe e é reusável:** `extrair_bearer(&env)` lê o token de `causation_id` (com/sem `Bearer `), `validar_access_token`, mapeamento `AppError → ErrorEnvelope`, e `publicar_auditoria_borda` (eventos `login_success`/`login_rate_limited`/`token_reuse_detected`/`logout`). A fachada Tonic **reusa essas funções** montando um `Envelope` interno a partir da request gRPC.
3. **`auth.proto` só tem mensagens** (`RegisterRequest`, `LoginRequest`, `AuthResponse`) — **falta** `service AuthService` + `RefreshRequest`/`LogoutRequest`/`LogoutResponse`.
4. **`core_module` já define contratos finos** que serão substituídos:
   - `AuthService` (core) expõe **apenas** `checkCurrentUser()` — é o gancho de boot. **NÃO confundir** com o `AuthService` rico do `login_module` (`login/refresh/logout/isAuthenticated/currentSession`). **Decisão:** o `login_module` introduz seu **próprio** `AuthService` (rico, anatomia-modulo §3) e fornece a impl que **também satisfaz** o gancho `checkCurrentUser` consumido pelo `InfraModule.bootTasks()`. Ver Etapa B7.
   - `SessionService` (core) hoje guarda só `token`/`tenantId`. **Será estendido** para o que o `Session` exige (access em memória, expiração) — sem persistir.
   - `LocalStorageService` (core) é `init/write/read/delete`; `LocalStorageServiceNoOp` é um `Map`. O `login_module` fornece a impl real sobre `flutter_secure_storage`.
   - `InfraModule.globalBinds` registra hoje `AuthServiceNoOp`, `LocalStorageServiceNoOp`, `ApiClientStub`. O app passará a compor o `LoginModule` (que registra as impls reais via `globalBinds`).
5. **`app.dart`** tem `_readyRoute`/`_bootRedirect` placeholders (boot-only). O guard de auth real os substitui.
6. **`api_client`** é hoje `ApiClient { connect() }` + `ApiClientStub`. Vira `GrpcApiClient` com canal gRPC-Web e o stub gerado.

---

## 2. FASE R — Review (validar approach e arquitetura)

**Objetivo:** travar as decisões de design antes de codar. Saídas desta fase são *go/no-go*; nenhuma escreve código de produção além de provas de conceito descartáveis.

### R1. Decisões de arquitetura a ratificar
- **R1.1 — Binário/porta da fachada.** A fachada gRPC-Web roda **no mesmo processo** da `runtime_api` (uma `tokio::task` adicional ao lado do `server.run()`) **ou** num binário separado. **Decisão recomendada:** mesma `runtime_api`, **task paralela** em porta HTTP própria (`RUNTIME_API_GRPC_WEB_ADDR`, ex. `0.0.0.0:50051`), reusando o `AuthDeps` já montado no boot (clientes `pg`/`redis`/`bus` compartilhados). Mantém um único deploy e reusa `application::auth::*` sem duplicar conexões.
- **R1.2 — Tonic convive com `transport::Server`.** Sim: `transport::Server` continua servindo IPC interno (worker, control_plane); a fachada Tonic serve **só a borda do browser**. Sem sobreposição de responsabilidade.
- **R1.3 — Conversão request gRPC → `Envelope`.** A fachada monta um `Envelope` com `causation_id = "Bearer <access do metadata>"`, `traceparent` extraído do metadata (`traceparent` do W3C TraceContext, se vier; senão gera) e `payload` JSON (`{email,password}` / `{refresh_token}`), e chama **exatamente** as funções `application::auth::login/refresh/logout` (não o `handler_*` do `main.rs`, para não arrastar a montagem de `Envelope` específica — extrair um helper compartilhado se necessário).
- **R1.4 — `AppError → tonic::Status`** (risco info_aux #4): `Auth → unauthenticated`; `RateLimit → resource_exhausted`; `Validation → invalid_argument`; `NotFound → not_found`; demais → `internal`. Mensagens amigáveis; **nunca** vazar detalhe interno.
- **R1.5 — Ordem dos layers** (info_aux §1): `Server::builder().accept_http1(true).layer(ServiceBuilder::new().layer(CorsLayer).layer(GrpcWebLayer::new()))` — **CORS antes de GrpcWebLayer**.
- **R1.6 — WASM × transporte gRPC-Web (risco #1).** Antes de qualquer código de feature no client, **provar a conexão gRPC-Web sob `flutter build web --wasm`**. `GrpcWebClientChannel.xhr()` usa `dart:html`/XHR e **não existe em WASM** (info_aux §2.2). Fixar o construtor/versão correto do `grpc` (transporte sobre `fetch` via `package:web`/`dart:js_interop`). **Gate de R:** PoC compila e conecta em `--wasm`.
- **R1.7 — Refresh automático fora do interceptor** (risco #5 + info_aux §2.4): `interceptUnary` é **síncrono** (retorna `ResponseFuture<R>`); injeção de token via `CallOptions(providers:[...])`. O **retry-após-refresh** é orquestrado no `AuthServiceImpl`/`AuthGrpcDatasource`, com **single-flight** para a corrida de refresh.

### R2. DoD da Fase R
- [ ] R1.1–R1.7 ratificadas e registradas.
- [ ] PoC WASM (R1.6) conecta a um endpoint gRPC-Web real (pode ser a fachada da Frente A já no ar).
- [ ] Contrato `auth.proto` revisado (nomes de RPC/mensagens) e aprovado antes de gerar stubs.

### Observabilidade & Auditoria (Fase R)
- **(a) Logs/traces:** nenhuma — fase de design. A PoC WASM **não** loga token (usa credencial fake).
- **(b) Auditoria:** nenhuma alteração de auditoria; apenas **confirmar** que os eventos server-side existentes (`login_success`, etc.) continuam cobrindo a borda nova (já cobertos por `publicar_auditoria_borda`).
- **(c) Sanitização:** a PoC usa endpoint/credencial fictícios; proibido commitar segredos no código de prova.

---

## 3. FASE E — Execution (construir; cada etapa compila/testa isolada)

> Ordem: **Frente A (A1→A5) → Frente B (B0→B9).** Cada etapa lista **objetivo**, **arquivos tocados** (caminhos reais) e **critério de pronto**.

### FRENTE A — Borda gRPC-Web no servidor

#### Etapa A1 — Contrato `auth.proto`: `service AuthService` + mensagens faltantes
- **Objetivo:** adicionar o serviço e as mensagens de Refresh/Logout, mantendo as existentes.
- **Arquivos:** `server/crates/contracts/schemas/queries/auth.proto`; build do `contracts` (tonic-build/prost).
- **Conteúdo:**
```proto
syntax = "proto3";
package smartcore.contracts.queries;

// (mensagens existentes LoginRequest/AuthResponse mantidas)

message RefreshRequest {
  string refresh_token = 1;
}

message LogoutRequest {
  // refresh opcional: se presente, revoga a família inteira (logout global).
  string refresh_token = 1;
}

message LogoutResponse {
  bool revoked = 1;
}

// Fachada de borda gRPC-Web. Login/Refresh são públicas; Logout exige access token
// no metadata `authorization: Bearer <access>`.
service AuthService {
  rpc Login   (LoginRequest)   returns (AuthResponse);
  rpc Refresh (RefreshRequest) returns (AuthResponse);
  rpc Logout  (LogoutRequest)  returns (LogoutResponse);
}
```
- **Pronto quando:** `contracts` compila com os stubs Rust gerados (tonic-build) para `AuthService`.

#### Etapa A2 — Dependências Rust da fachada
- **Objetivo:** introduzir `tonic`, `tonic-web`, `tower-http` (feature `cors`) na `runtime_api`.
- **Arquivos:** `server/apps/runtime_api/Cargo.toml`; (se a geração for centralizada) `server/crates/contracts/build.rs` / `Cargo.toml`.
- **Versões (info_aux §1):** `tonic 0.14.x` + `tonic-web 0.12` + `tower-http 0.5` (cors). Conferir compatibilidade de versão tonic↔tonic-web no lockfile.
- **Pronto quando:** `cargo build -p runtime_api` resolve sem código novo de servidor ainda.

#### Etapa A3 — Implementação da fachada `AuthService` (delegação pura)
- **Objetivo:** implementar o trait gerado, delegando para `application::auth::*`; converter metadata→`Envelope`; mapear `AppError→Status`.
- **Arquivos:** novo `server/apps/runtime_api/src/grpc_web.rs` (módulo); `server/apps/runtime_api/src/main.rs` (declarar `mod grpc_web;`).
- **Esqueleto (Rust, comentários pt-br):**
```rust
//! Fachada gRPC-Web da runtime_api: traduz chamadas do browser para a lógica
//! de negócio já existente em `application::auth::*`. NÃO reimplementa regra.

use std::{sync::Arc, time::Duration};
use tonic::{Request, Response, Status};
use contracts::queries::auth_service_server::{AuthService, AuthServiceServer};
use contracts::queries::{LoginRequest, RefreshRequest, LogoutRequest, AuthResponse, LogoutResponse};
use application::auth::login::AuthDeps;

pub struct AuthFacade {
    deps: Arc<AuthDeps>,
    bus: redis::aio::ConnectionManager,
}

/// Converte o `AppError` interno num `tonic::Status` sem vazar detalhe sensível.
fn app_err_para_status(err: &error_core::AppError) -> Status {
    use error_core::AppError::*;
    match err {
        Auth(_)      => Status::unauthenticated("errors.auth"),
        RateLimit(_) => Status::resource_exhausted("errors.auth.rate_limited"),
        Validation(_) => Status::invalid_argument("errors.validation"),
        _            => Status::internal("errors.internal"),
    }
}

/// Extrai o token Bearer do metadata `authorization` (convenção da borda gRPC-Web).
fn bearer_do_metadata<T>(req: &Request<T>) -> String {
    req.metadata()
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string())
        .unwrap_or_default()
}

/// Extrai o `traceparent` (W3C TraceContext) do metadata, para correlação distribuída.
fn traceparent_do_metadata<T>(req: &Request<T>) -> String {
    req.metadata()
        .get("traceparent")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string())
        .unwrap_or_else(|| observability::novo_traceparent()) // gera se ausente
}

#[tonic::async_trait]
impl AuthService for AuthFacade {
    /// Login: delega para `application::auth::login::login`. Sem token no metadata.
    #[tracing::instrument(skip_all, fields(service = "runtime_api", rpc = "Login", traceparent))]
    async fn login(&self, req: Request<LoginRequest>) -> Result<Response<AuthResponse>, Status> {
        let traceparent = traceparent_do_metadata(&req);
        tracing::Span::current().record("traceparent", tracing::field::display(&traceparent));
        let LoginRequest { email, password } = req.into_inner();
        // NUNCA logar email/password.
        match application::auth::login::login(&self.deps, &traceparent, &email, &password).await {
            Ok(tokens) => Ok(Response::new(AuthResponse {
                access_token: tokens["access_token"].as_str().unwrap_or_default().to_string(),
                refresh_token: tokens["refresh_token"].as_str().unwrap_or_default().to_string(),
            })),
            Err(err) => {
                error_core::registrar(&err, &error_core::ErrorContext {
                    trace_id: traceparent.clone(), tenant_id: String::new(),
                });
                Err(app_err_para_status(&err)) // mensagem amigável, sem detalhe interno
            }
        }
    }

    /// Refresh: delega para `application::auth::refresh::refresh` (rotação + reuso).
    #[tracing::instrument(skip_all, fields(service = "runtime_api", rpc = "Refresh", traceparent))]
    async fn refresh(&self, req: Request<RefreshRequest>) -> Result<Response<AuthResponse>, Status> {
        let traceparent = traceparent_do_metadata(&req);
        let refresh_token = req.into_inner().refresh_token;
        match application::auth::refresh::refresh(&self.deps, &traceparent, &refresh_token).await {
            Ok(tokens) => Ok(Response::new(AuthResponse {
                access_token: tokens["access_token"].as_str().unwrap_or_default().to_string(),
                refresh_token: tokens["refresh_token"].as_str().unwrap_or_default().to_string(),
            })),
            Err(err) => {
                // Reuso detectado: a família já foi revogada a jusante; auditoria
                // `token_reuse_detected` é publicada server-side (mesma função do main.rs).
                Err(app_err_para_status(&err))
            }
        }
    }

    /// Logout: exige access token no metadata; delega para `application::auth::logout::logout`.
    #[tracing::instrument(skip_all, fields(service = "runtime_api", rpc = "Logout", traceparent))]
    async fn logout(&self, req: Request<LogoutRequest>) -> Result<Response<LogoutResponse>, Status> {
        let traceparent = traceparent_do_metadata(&req);
        let bearer = bearer_do_metadata(&req);
        let token = bearer.strip_prefix("Bearer ").unwrap_or(&bearer).trim();
        let claims = application::jwt::validar_access_token(token)
            .map_err(|_| Status::unauthenticated("errors.auth"))?;
        let refresh = req.into_inner().refresh_token;
        let refresh_opt = (!refresh.is_empty()).then_some(refresh.as_str());
        match application::auth::logout::logout(&self.deps, &traceparent, &claims, refresh_opt).await {
            Ok(_) => Ok(Response::new(LogoutResponse { revoked: true })),
            Err(err) => Err(app_err_para_status(&err)),
        }
    }
}
```
> **Nota de reuso:** se a auditoria (`login_success`, `logout`, `token_reuse_detected`) hoje vive nos `handler_*` do `main.rs` e não dentro de `application::auth::*`, **extrair** esses publishes para uma função compartilhada (ex. `application::auth::audit::*` ou um wrapper) invocada tanto pelos `handler_*` quanto pela fachada — para a borda gRPC-Web emitir os **mesmos** eventos sem duplicar lógica. Decidido em A3 ao inspecionar `login.rs`/`refresh.rs`/`logout.rs`.
- **Pronto quando:** `cargo build -p runtime_api` compila com a fachada (ainda sem servir).

#### Etapa A4 — Servir a fachada (task paralela, accept_http1 + CORS + GrpcWebLayer)
- **Objetivo:** subir o servidor HTTP gRPC-Web ao lado do `transport::Server`.
- **Arquivos:** `server/apps/runtime_api/src/main.rs` (spawnar a task); `server/apps/runtime_api/src/grpc_web.rs` (função `serve`).
```rust
/// Sobe a fachada gRPC-Web numa porta HTTP própria (browser usa HTTP/1.1).
pub async fn serve(deps: Arc<AuthDeps>, bus: redis::aio::ConnectionManager) -> anyhow::Result<()> {
    let addr = std::env::var("RUNTIME_API_GRPC_WEB_ADDR")
        .unwrap_or_else(|_| "0.0.0.0:50051".to_string())
        .parse()?;
    let facade = AuthServiceServer::new(AuthFacade { deps, bus });

    // CORS restritivo mesmo com mesma origem (defesa em profundidade).
    let cors = tower_http::cors::CorsLayer::new()
        .allow_origin(tower_http::cors::AllowOrigin::mirror_request())
        .allow_headers([http::header::CONTENT_TYPE, "x-grpc-web".parse().unwrap(), "authorization".parse().unwrap()])
        .expose_headers(["grpc-status".parse().unwrap(), "grpc-message".parse().unwrap(),
                         "grpc-encoding".parse().unwrap(), "grpc-accept-encoding".parse().unwrap()]);

    tracing::info!(%addr, "Subindo fachada gRPC-Web da runtime_api");
    tonic::transport::Server::builder()
        .accept_http1(true) // OBRIGATÓRIO p/ browser
        .layer(
            tower::ServiceBuilder::new()
                .layer(cors)                       // CORS ANTES
                .layer(tonic_web::GrpcWebLayer::new()) // GrpcWebLayer DEPOIS
                .into_inner(),
        )
        .add_service(facade)
        .serve(addr)
        .await?;
    Ok(())
}
```
No `main.rs`, após montar `deps`/`bus` e antes/junto de `server.run()`:
```rust
let facade_deps = deps.clone();
let facade_bus = bus.clone();
tokio::spawn(async move {
    if let Err(e) = grpc_web::serve(facade_deps, facade_bus).await {
        tracing::error!("Fachada gRPC-Web parou: {:?}", e);
    }
});
```
- **Pronto quando:** `runtime_api` sobe e a porta gRPC-Web responde; `transport::Server` continua intacto.

#### Etapa A5 — Caddy (TLS, mesma origem WASM+API) e validação grpcurl/grpcui
- **Objetivo:** servir o bundle WASM e a API gRPC-Web na **mesma origem** sob HTTPS; validar o DoD do doc 09 §6.4.
- **Arquivos:** `Caddyfile` (artefato do plano, ex. `server/deploy/Caddyfile` ou `infra/Caddyfile`).
- **Caddyfile (esqueleto):**
```caddyfile
admin.smartcore.example {
  encode gzip
  # API gRPC-Web (HTTP/1.1) — roteia o tráfego gRPC-Web para a fachada Tonic.
  @grpcweb {
    header Content-Type application/grpc-web*
  }
  reverse_proxy @grpcweb localhost:50051
  # Bundle Flutter Web/WASM (mesma origem → CORS trivial).
  root * /srv/smart-core-admin/build/web
  file_server
  # CSP forte (mitiga XSS do secure storage no Web).
  header Content-Security-Policy "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; connect-src 'self'; object-src 'none'"
  header Strict-Transport-Security "max-age=31536000; includeSubDomains"
}
```
- **Validação (espelha doc 09 §6.4):** com `grpcurl`/`grpcui` contra a fachada:
  1. Login feliz → `access_token`+`refresh_token`.
  2. Senha errada → `unauthenticated`.
  3. Refresh expirado/inexistente → `unauthenticated`.
  4. **Reuso** de refresh rotacionado → `unauthenticated` + evento `token_reuse_detected` no `security:stream`.
  5. Logout → `revoked=true`; reuso do access bloqueado (rota protegida → `unauthenticated`).
- **Pronto quando:** os 5 cenários passam por `grpcurl`/`grpcui` e a auditoria correspondente aparece.

#### Observabilidade & Auditoria (Frente A)
- **(a) Logs/traces (`tracing`):** span por RPC (`#[tracing::instrument(skip_all, fields(... traceparent))]`) com `service=runtime_api`, `rpc`, e `traceparent` propagado do metadata para o `Envelope` interno. `AppError→Status` registra `error_code` via `error_core::registrar`, **sem** detalhe sensível. **Registrar IP do cliente** agora que a borda existe (item pendente do doc 09 §6.4 — `ip_address` no `AuditLogPayload` deixa de ser `None` quando o proxy repassa `X-Forwarded-For`).
- **(b) Auditoria (`audit_log`):** **reaproveitada** — `login_success`/`login_failed` (`data_postgres`), `login_rate_limited`/`token_reuse_detected`/`logout` (`security:stream` via `publicar_auditoria_borda`). A fachada **não duplica** auditoria: invoca o mesmo caminho (`application::auth::*` + publishes compartilhados). Garante propagar `traceparent`/contexto.
- **(c) Sanitização:** **nunca** logar `email`/`password`/tokens (spans usam `skip_all`); rate limiting por e-mail **hasheado**; segredos em `secrecy::SecretString`; access token removido do `Envelope` antes do encaminhamento interno (já é o caso — `causation_id = message_id` nos forwards).

---

### FRENTE B — `login_module` (client)

#### Etapa B0 — PoC de transporte gRPC-Web sob `--wasm` (gate do risco #1)
- **Objetivo:** **provar** a conexão gRPC-Web em `flutter build web --wasm` antes de construir a feature. Fixar construtor/versão do `grpc`.
- **Arquivos:** PoC descartável em `clients/apps/smart-core-admin` (ou scratch); ao validar, fixar versão em `clients/packages/api_client/pubspec.yaml`.
- **Ação:** **não** usar `GrpcWebClientChannel.xhr()` (depende de `dart:html`, indisponível em WASM). Usar o transporte gRPC-Web sobre `fetch` (`package:web`/`dart:js_interop`) exposto pela versão fixada do `grpc (~4.0.0)`. Conectar à fachada da Frente A (já no ar) e fazer um `Login` real.
- **Pronto quando:** app compilado com `--wasm` conecta e recebe resposta do `Login` da fachada.

#### Etapa B1 — Geração de stubs Dart + scaffolding do módulo
- **Objetivo:** gerar `auth.pbgrpc.dart`/`auth.pb.dart` e criar o esqueleto do módulo (anatomia-modulo §2).
- **Arquivos:**
  - Stubs: `clients/packages/api_client/lib/src/generated/auth.pbgrpc.dart` (+ `.pb.dart`) via `protoc --dart_out=grpc:... -I... auth.proto` (`dart pub global activate protoc_plugin`).
  - Módulo: `clients/modulos/login_module/` (pubspec + `lib/login_module.dart` + `lib/src/login_module.dart` + `lib/src/features/login/{domain,data,presentation}/...`).
- **Pronto quando:** `dart analyze` limpo no esqueleto; stubs compilam.

#### Etapa B2 — `domain` da feature `login`
- **Objetivo:** contrato público + parâmetros + model + usecases (return_success_or_error v2.0.0).
- **Arquivos:**
  - `.../domain/services/auth_service.dart`
  - `.../domain/parameters/login_parameters.dart`, `.../refresh_parameters.dart`
  - `.../domain/model/session.dart`
  - `.../domain/usecases/login_usecase.dart`, `.../refresh_token_usecase.dart`, `.../logout_usecase.dart`
- **`Session` (imutável/sendable):**
```dart
// domain/model/session.dart
@immutable
final class Session {
  final String accessToken;   // só em memória
  final String refreshToken;  // persistido em secure storage
  final DateTime expiresAt;
  final String tenantId;
  final List<String> scopes;
  final bool isSuperuser;
  const Session({
    required this.accessToken, required this.refreshToken,
    required this.expiresAt, required this.tenantId,
    required this.scopes, required this.isSuperuser,
  });
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
```
- **`AuthService` (interface pública):**
```dart
// domain/services/auth_service.dart
abstract interface class AuthService {
  Future<ReturnSuccessOrError<Session>> login({required String email, required String password});
  Future<ReturnSuccessOrError<Session>> refresh();
  Future<ReturnSuccessOrError<Unit>> logout();
  bool get isAuthenticated;
  Session? get currentSession;
}
```
- **Usecase (passthrough D==T, process estático síncrono):**
```dart
// domain/usecases/login_usecase.dart
final class LoginUsecase extends UsecaseBaseCallData<Session, Session> {
  LoginUsecase({required super.datasource});
  @override
  ProcessData<Session, Session> get process => _process;
  static ReturnSuccessOrError<Session> _process(Session s, ParametersReturnResult p)
      => SuccessReturn(success: s);
}
```
(`RefreshTokenUsecase` análogo; `LogoutUsecase` com `D=Unit`/`T=Unit` → `SuccessReturn(success: unit)`.)
- **`LoginParameters`:**
```dart
// domain/parameters/login_parameters.dart
final class LoginParameters implements ParametersReturnResult {
  final String email;
  final String password;
  const LoginParameters({required this.email, required this.password});
  @override
  AppError get error => const ErrorAuth(message: 'Falha ao autenticar');
}
```
- **Pronto quando:** testes de usecase passam (fake datasource + `switch`; short-circuit de erro).

#### Etapa B3 — `api_client`: `GrpcApiClient` + `AuthTokenInterceptor`
- **Objetivo:** trocar `ApiClientStub` por `GrpcApiClient` real (canal gRPC-Web WASM-compatível) com interceptor de token.
- **Arquivos:** `clients/packages/api_client/lib/src/api_client.dart` (estender contrato), novo `.../grpc_api_client.dart`, `.../interceptors/auth_token_interceptor.dart`; `pubspec.yaml` (deps `grpc ~4.0.0`, `protobuf ~3.0.0`).
- **Interceptor (assinatura síncrona correta — info_aux §2.4):**
```dart
// interceptors/auth_token_interceptor.dart
final class AuthTokenInterceptor implements ClientInterceptor {
  final Future<String?> Function() _readAccessToken;
  AuthTokenInterceptor(this._readAccessToken);

  @override
  ResponseFuture<R> interceptUnary<Q, R>(
    ClientMethod<Q, R> method, Q request, CallOptions options,
    ClientUnaryInvoker<Q, R> invoker,
  ) {
    // Token resolvido por provider assíncrono (pega o valor atual, inclusive pós-refresh).
    final withAuth = options.mergedWith(CallOptions(providers: [
      (metadata, _) async {
        final token = await _readAccessToken();
        if (token != null) metadata['authorization'] = 'Bearer $token';
      },
    ]));
    return invoker(method, request, withAuth); // síncrono: NÃO fazer retry-após-refresh aqui
  }

  @override
  ResponseStream<R> interceptStreaming<Q, R>(
    ClientMethod<Q, R> m, Stream<Q> r, CallOptions o, ClientStreamingInvoker<Q, R> inv,
  ) => inv(m, r, o);
}
```
- **`GrpcApiClient`:** cria o canal gRPC-Web (transporte WASM-compatível fixado em B0), expõe `AuthServiceClient` com o interceptor; `connect()` valida o canal. **Não loga token** (só endpoint/status).
- **Pronto quando:** `GrpcApiClient` conecta sob `--wasm`; testes do interceptor (token injetado no metadata) passam.

#### Etapa B4 — `data`: datasources gRPC e local
- **Objetivo:** `AuthGrpcDatasource` (I/O gRPC-Web → `Session`) e `TokenLocalDatasource` (secure storage).
- **Arquivos:** `.../data/datasources/auth_grpc_datasource.dart`, `.../data/datasources/token_local_datasource.dart`.
- **`AuthGrpcDatasource` (só I/O; mapeia `GrpcError`→`AppError` tipado):**
```dart
// data/datasources/auth_grpc_datasource.dart
final class AuthGrpcDatasource implements Datasource<Session> {
  final GrpcApiClient _api;
  const AuthGrpcDatasource({required GrpcApiClient api}) : _api = api;

  @override
  Future<Session> call(covariant LoginParameters parameters) async {
    try {
      final resp = await _api.auth.login(
        LoginRequest()..email = parameters.email..password = parameters.password,
      );
      return _toSession(resp); // decodifica claims do access p/ tenant/scopes/exp/isSuperuser
    } on GrpcError catch (e) {
      throw _mapGrpcError(e, parameters.error); // unauthenticated→ErrorAuth, etc.
    } catch (e) {
      throw parameters.error.copyWith(message: '$e'); // sem vazar segredo
    }
  }
}

AppError _mapGrpcError(GrpcError e, AppError fallback) => switch (e.code) {
  StatusCode.unauthenticated => const ErrorUnauthorized(message: 'Credenciais inválidas'),
  StatusCode.invalidArgument => const ErrorValidation(message: 'Dados inválidos'),
  StatusCode.unavailable     => const ErrorNetwork(message: 'Servidor indisponível'),
  _ => fallback,
};
```
> O `RefreshTokenUsecase` precisa de um datasource de refresh; reusar `AuthGrpcDatasource` com `covariant RefreshParameters` **ou** criar `RefreshGrpcDatasource`. **Decisão:** datasource único por RPC (`...GrpcDatasource` por método mantém o `Datasource<Session>` limpo), seguindo o sufixo de transporte.
- **`TokenLocalDatasource`:** `flutter_secure_storage` com chave `smartcore_admin_auth_refresh_token`; só **refresh** persiste.
- **Pronto quando:** testes de datasource (mock do stub gRPC + mock do storage) passam.

#### Etapa B5 — `AuthServiceImpl` (orquestra sessão, persistência, refresh single-flight)
- **Objetivo:** guardar `Session`, popular `SessionService`, persistir refresh, orquestrar **refresh automático + retry single-flight** (risco #5).
- **Arquivos:** `.../data/services/auth_service_impl.dart`.
```dart
// data/services/auth_service_impl.dart
final class AuthServiceImpl implements AuthService {
  final Datasource<Session> _loginDs;
  final Datasource<Session> _refreshDs;
  final TokenLocalDatasource _tokenStore;
  final SessionService _session; // core_module: access em memória

  Session? _current;
  Future<ReturnSuccessOrError<Session>>? _refreshInFlight; // single-flight

  AuthServiceImpl({
    required Datasource<Session> loginDatasource,
    required Datasource<Session> refreshDatasource,
    required TokenLocalDatasource tokenStore,
    required SessionService session,
  })  : _loginDs = loginDatasource, _refreshDs = refreshDatasource,
        _tokenStore = tokenStore, _session = session;

  @override
  bool get isAuthenticated => _current != null && !_current!.isExpired;
  @override
  Session? get currentSession => _current;

  @override
  Future<ReturnSuccessOrError<Session>> login({required String email, required String password}) async {
    final result = await LoginUsecase(datasource: _loginDs)
        .call(LoginParameters(email: email, password: password));
    switch (result) {
      case SuccessReturn<Session>():
        await _aplicarSessao(result.result);
      case ErrorReturn<Session>():
        break;
    }
    return result;
  }

  /// Refresh com single-flight: chamadas concorrentes compartilham a MESMA Future.
  @override
  Future<ReturnSuccessOrError<Session>> refresh() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() => _refreshInFlight = null);
  }

  Future<ReturnSuccessOrError<Session>> _doRefresh() async {
    final stored = await _tokenStore.readRefresh();
    if (stored == null) {
      return const ErrorReturn(error: ErrorUnauthorized(message: 'Sem sessão persistida'));
    }
    final result = await RefreshTokenUsecase(datasource: _refreshDs)
        .call(RefreshParameters(refreshToken: stored));
    switch (result) {
      case SuccessReturn<Session>(): await _aplicarSessao(result.result);
      case ErrorReturn<Session>(): await _limparSessao(); // refresh inválido → logout local
    }
    return result;
  }

  /// Gancho de boot (auto-login silencioso): tenta refresh com o token persistido.
  Future<void> checkCurrentUser() async {
    final r = await refresh();
    // ErrorReturn é esperado quando não há sessão — não propaga, só fica deslogado.
    if (r is ErrorReturn) await _limparSessao();
  }

  Future<void> _aplicarSessao(Session s) async {
    _current = s;
    _session.setSession(token: s.accessToken, tenantId: s.tenantId); // access em memória
    await _tokenStore.writeRefresh(s.refreshToken);                  // refresh persistido
  }

  Future<void> _limparSessao() async {
    _current = null;
    _session.clearSession();
    await _tokenStore.deleteRefresh();
  }

  @override
  Future<ReturnSuccessOrError<Unit>> logout() async {
    final result = await LogoutUsecase(datasource: /* logout ds */).call(const NoParams(error: ErrorAuth(message: 'Falha no logout')));
    await _limparSessao(); // falha aberta: limpa local mesmo se o server falhar
    return result is SuccessReturn ? const SuccessReturn(success: unit) : result as ReturnSuccessOrError<Unit>;
  }
}
```
> **Refresh automático na captura de `unauthenticated`:** ao consumir uma RPC de domínio que retorne `StatusCode.unauthenticated`, o `AuthServiceImpl` (ou o datasource de domínio) chama `refresh()` (single-flight) e **refaz** a chamada **uma vez**. Como o escopo desta entrega não inclui features de domínio, o retry vive como gancho reusável; o ciclo login/refresh já o exercita.
- **Pronto quando:** testes do single-flight (N chamadas concorrentes → 1 RPC de refresh) e do auto-login passam.

#### Etapa B6 — `presentation`: rota, controller, página, form
- **Objetivo:** UI que fala **só** com o controller.
- **Arquivos:** `.../presentation/routes/login_route.dart`, `.../controllers/login_controller.dart`, `.../pages/login_page.dart`, `.../widgets/login_form.dart`.
```dart
// presentation/controllers/login_controller.dart
final class LoginController extends BaseController<Session> {
  final AuthService _auth;
  LoginController({required AuthService auth}) : _auth = auth;
  Future<void> signIn(String email, String password) =>
      execute(() => _auth.login(email: email, password: password));
}
```
```dart
// presentation/routes/login_route.dart
final class LoginRoute extends GetItModule {
  @override String get path => '/login';
  @override Widget get page => const LoginPage();
  @override
  void binds(Injector i) =>
      i.controller<LoginController>(() => LoginController(auth: inject<AuthService>()));
}
```
- **Pronto quando:** `bloc_test` do controller (loading→success / loading→error) passa.

#### Etapa B7 — `LoginModule` + integração com a base (substituir NoOps)
- **Objetivo:** registrar impls reais no escopo global e plugar no boot.
- **Arquivos:**
  - `clients/modulos/login_module/lib/src/login_module.dart` (`LoginModule extends AppModule`: `globalBinds` registra `AuthService→AuthServiceImpl`, `LocalStorageService` real e os datasources; `routes()→[LoginRoute]`).
  - `clients/modulos/core_module/lib/src/infra_module.dart`: **remover** `AuthServiceNoOp`/`LocalStorageServiceNoOp` dos binds (ou deixar o `LoginModule` sobrescrever); manter `SessionService` (agora populado pelo `login_module`).
  - `clients/apps/smart-core-admin/lib/bootstrap` (lista de `AppModule`): **adicionar** `LoginModule`.
  - `clients/modulos/core_module/.../services/session_service.dart` + `session_service_impl.dart`: **estender** `SessionService` se o `Session` exigir mais que `token`/`tenantId` (ex. expiração) — sem persistir.
- **Reconciliação dos dois `AuthService`:** o `InfraModule.bootTasks()` chama `inject<AuthService>().checkCurrentUser()`. Resolver por **uma** das opções (decidir em B7): (i) o `AuthService` do `login_module` **inclui** `checkCurrentUser()` e o core passa a referenciar essa interface; **ou** (ii) manter o `AuthService` fino do core como gancho de boot e registrar a impl do `login_module` para **ambas** as interfaces. **Recomendado:** (i) — interface única rica no `login_module`, `core_module` consome via API público (sem ciclo, pois `login_module` é camada de domínio base acima da infra).
- **Pronto quando:** app compõe `LoginModule`; boot executa `checkCurrentUser` (auto-login silencioso) sem NoOps.

#### Etapa B8 — Guard de auth no GoRouter (substitui placeholders)
- **Objetivo:** trocar `_readyRoute`/`_bootRedirect` por guard real.
- **Arquivos:** `clients/apps/smart-core-admin/lib/app.dart`.
```dart
// substitui _bootRedirect
static String? _authRedirect(BuildContext context, GoRouterState state) {
  final booted = inject<BootState>().value;
  if (!booted) return state.matchedLocation == '/' ? null : '/';
  final auth = inject<AuthService>();
  final indoParaLogin = state.matchedLocation == '/login';
  if (!auth.isAuthenticated) return indoParaLogin ? null : '/login';
  if (indoParaLogin) return '/'; // já logado → sai do login
  return null;
}
```
`refreshListenable` deve reagir a mudanças de auth (ex. um `ValueNotifier`/`Listenable` exposto pelo `AuthService` além do `BootState`).
- **Pronto quando:** rotas protegidas redirecionam para `/login` quando deslogado; pós-login vai ao destino.

#### Etapa B9 — i18n dos erros
- **Objetivo:** mapear `ErrorAuth`/`ErrorUnauthorized`/`ErrorNetwork`/`ErrorValidation` no `ErrorMessageMapper`.
- **Arquivos:** `clients/modulos/presentation_module/.../error_message_mapper.dart` (+ `.arb` do app: `clients/apps/smart-core-admin/lib/l10n/app_pt.arb`).
- **Pronto quando:** cada categoria de erro resolve uma mensagem amigável pt-br; default cobre `ErrorGeneric`.

#### Observabilidade & Auditoria (Frente B — todas as etapas B)
- **(a) Logs:** o client loga **apenas** endpoint/status/estado de fluxo (como o `ApiClientStub` faz hoje: `endpoint=... status=...`). **Proibido** `print` de token/credenciais/refresh. Erros viram `AppError` tipado → `ErrorMessageMapper`.
- **(b) Auditoria:** **sem evento de auditoria no client** (intencional — auditoria é server-side, na borda/`data_postgres`). Documentar essa ausência como decisão.
- **(c) Sanitização:** access token **só em memória** (`SessionService`); refresh em `flutter_secure_storage` (chave namespaced); **logout** limpa storage **e** memória; `Session`/`Parameters` imutáveis/sendable; nenhum log de valores sensíveis. HTTPS obrigatório (Web Crypto do secure storage) — garantido pelo Caddy (A5).

---

## 4. FASE V — Validation (verificar que funciona)

- **V1 — Servidor (Frente A):** `cargo test -p runtime_api` (handlers + fachada); validação manual `grpcurl`/`grpcui` dos 5 cenários do doc 09 §6.4 (A5).
- **V2 — Client (Frente B):**
  - **Usecases:** fake datasource + `switch`; short-circuit de erro do fetch (`Cod. 02-1`); erro de negócio do `process`.
  - **Controller:** `bloc_test` (loading→success / loading→error).
  - **Datasource:** mock do stub gRPC (mapeamento `GrpcError`→`AppError`) e do secure storage.
  - **Single-flight de refresh:** N chamadas concorrentes → 1 RPC.
  - **Guard:** deslogado→`/login`; logado→destino; pós-logout→`/login`.
- **V3 — Integração WASM:** `flutter build web --wasm`; login feliz ponta-a-ponta contra a fachada via Caddy (HTTPS).
- **DoD da Fase V:** todos os testes passam; build `--wasm` conecta; nenhum segredo em log.

---

## 5. FASE C — Confirmation (entregar e documentar)

- **Gate obrigatório:** `prevc-final-review` (auditoria pós-implementação compara implementado × plano, corrige desvios, arquiva e commita).
- **Entregáveis:** PR(s) por frente (A e B podem ser PRs separados, A primeiro); atualização dos docs `09`, `tonic-web.md`, `grpc.md`, `flutter_secure_storage.md` se a implementação divergir; mover plano para `archive/`.
- **DoD da Fase C:** PR mergeado, testes verdes, docs atualizados, plano arquivado.

---

## 6. Riscos e Mitigações

| # | Risco | Mitigação |
|---|---|---|
| 1 | **WASM × gRPC-Web** — `GrpcWebClientChannel.xhr()` usa `dart:html`/XHR, **indisponível** em `--wasm`. | **Gate B0:** provar conexão sob `--wasm` com transporte sobre `fetch` (`package:web`/`dart:js_interop`); fixar construtor/versão do `grpc`. **Não assumir `.xhr()`.** |
| 2 | **Fachada Tonic nova** na `runtime_api` (hoje só `transport::Server`). | Task paralela em porta própria (`RUNTIME_API_GRPC_WEB_ADDR`), reusando `AuthDeps`; delega para `application::auth::*`; sem mexer no `transport::Server`. |
| 3 | **Corrida de refresh** (múltiplas chamadas expirando juntas). | **Single-flight** no `AuthServiceImpl` (`_refreshInFlight` compartilhado); retry **fora** do interceptor síncrono. |
| 4 | **XSS / secure storage no Web** — `localStorage` criptografado é acessível a JS malicioso. | Só o **refresh** persiste (rotação + detecção de reuso server-side); access em memória; **CSP forte** + **HTTPS/HSTS** no Caddy. |
| 5 | **CSP/HTTPS** — Web Crypto do secure storage exige contexto seguro. | Caddy termina TLS, serve WASM+API na **mesma origem**, aplica CSP e HSTS (A5). |
| 6 | **`interceptUnary` síncrono** (info_aux §2.4) — retry-após-refresh frágil dentro dele. | Token via `CallOptions(providers:[...])` (assíncrono, por chamada); orquestração refresh+retry no `AuthServiceImpl`. |
| 7 | **Ordem dos layers** CORS/GrpcWeb. | CORS **antes** de `GrpcWebLayer`; `accept_http1(true)` obrigatório. |
| 8 | **Dois `AuthService`** (core fino × login rico). | Interface única rica no `login_module`; `core_module` consome via API público (sem ciclo). |

---

## 7. Critérios de Aceite (DoD) por Frente

### Frente A — Borda gRPC-Web
- [ ] `auth.proto` com `service AuthService { Login, Refresh, Logout }` + `RefreshRequest`/`LogoutRequest`/`LogoutResponse`; stubs Rust e Dart gerados.
- [ ] Fachada Tonic delega para `application::auth::*` (sem reescrever regra); `accept_http1(true)` + CORS→GrpcWebLayer.
- [ ] Token extraído do metadata `authorization` → `causation_id` do `Envelope`; `AppError→Status` sem vazar detalhe.
- [ ] Fachada roda em paralelo ao `transport::Server` (porta própria), sem regressão.
- [ ] Caddy: TLS + WASM e API na mesma origem; CSP/HSTS.
- [ ] `grpcurl`/`grpcui`: login feliz, senha errada, refresh expirado, **reuso de refresh** (+ auditoria), logout + token bloqueado.
- [ ] Observabilidade: span/`traceparent` por RPC; auditoria reaproveitada; IP registrado; sem segredo em log.

### Frente B — `login_module`
- [ ] Estrutura exata da anatomia-modulo (lib público + `src/features/login/{domain,data,presentation}`).
- [ ] `domain` com `AuthService`, `Session`, `LoginParameters`/`RefreshParameters`, usecases (process estático síncrono).
- [ ] `data` com `AuthGrpcDatasource` (gRPC-Web), `TokenLocalDatasource` (secure storage), `AuthServiceImpl` (sessão + persistência + refresh single-flight).
- [ ] `api_client`: `GrpcApiClient` real (WASM) + `AuthTokenInterceptor` (provider assíncrono).
- [ ] Integração: NoOps substituídos; `SessionService` populado/limpo; `checkCurrentUser` = auto-login silencioso; guard de auth no GoRouter; refresh automático via captura de `unauthenticated`.
- [ ] i18n: `ErrorAuth`/`ErrorUnauthorized`/`ErrorNetwork`/`ErrorValidation` mapeados.
- [ ] Build `--wasm` conecta e faz login ponta-a-ponta.
- [ ] Testes: usecases, controller (`bloc_test`), datasource (mock), single-flight, guard.
- [ ] Observabilidade: client loga só endpoint/status; **sem** auditoria no client (intencional); access só em memória, refresh em secure storage; logout limpa tudo.

---

## 8. Correções Aplicadas (em relação ao plano-base da conversa)

| # | Ajuste | Por quê | Fonte |
|---|---|---|---|
| 1 | **`GrpcWebClientChannel.xhr()` não é usado** em WASM; transporte sobre `fetch` (`package:web`/`dart:js_interop`), provado no **gate B0**. | `.xhr()` depende de `dart:html`/XHR, indisponível em `flutter build web --wasm`. | `grpc.md` §2.2 (⚠️ WASM); info_aux §2.2/§5.1. |
| 2 | **`interceptUnary` permanece síncrono**; injeção de token via `CallOptions(providers:[...])`; **retry-após-refresh tirado do interceptor** e movido para o `AuthServiceImpl`. | A assinatura síncrona (`ResponseFuture<R>`, sem `await`) torna retry no interceptor frágil. | `grpc.md` §2.4 (⚠️ assinatura); info_aux §2.1/§5.5. |
| 3 | **Ordem dos layers fixada:** `CorsLayer` **antes** de `GrpcWebLayer`; `accept_http1(true)` obrigatório. | Tradução gRPC-Web e CORS exigem essa ordem/flag. | `tonic-web.md`; info_aux §1. |
| 4 | **Fachada é componente novo em task paralela** (não reaproveita o `transport::Server`, que é framing custom — **não** Tonic). | Inspeção real de `runtime_api/src/main.rs` e `Cargo.toml` (sem `tonic`). | Código real; info_aux §5.2. |
| 5 | **Fachada delega para `application::auth::*`** (não para os `handler_*` do `main.rs`); auditoria/publishes extraídos para caminho compartilhado se hoje vivem no `main.rs`. | Evita duplicar montagem de `Envelope`/auditoria; mantém reuso 100%. | Código real (`main.rs` handlers); info_aux §1/§4. |
| 6 | **Reconciliação dos dois `AuthService`** (core fino `checkCurrentUser` × login rico). Interface única rica no `login_module`. | Inspeção real: `core_module` já define um `AuthService` mínimo distinto do da anatomia. | Código real (`core_module/.../auth_service.dart`); anatomia-modulo §3. |
| 7 | **`SessionService` do core será estendido** (não recriado) para suportar o que `Session` exige, sem persistir access. | `SessionService` atual só tem `token`/`tenantId`. | Código real (`session_service.dart`). |
| 8 | **Auditoria de IP** passa a ser registrada na borda (era pendência). | A borda gRPC-Web/proxy agora existe (Caddy repassa `X-Forwarded-For`). | doc 09 §6.4 (item pendente); info_aux §4. |
| 9 | **CSP/HTTPS/HSTS no Caddy** explicitados como mitigação de XSS do secure storage. | Web Crypto exige contexto seguro; localStorage é exposto a XSS. | `flutter_secure_storage.md` (limitações Web); info_aux §5.7. |
