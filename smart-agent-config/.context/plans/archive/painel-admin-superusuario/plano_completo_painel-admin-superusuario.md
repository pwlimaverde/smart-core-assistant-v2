# Plano Completo — Painel Gerencial do Superusuário (Plano de Controle Total)

> **Status:** ⬜ Planejado — primeira feature de negócio pós-fundação (login já funciona).
> **Idioma:** pt-br na documentação/comentários; identificadores em inglês.
> **Origem:** `doc_dev/planejamento/11-painel-admin-superusuario.md`, reestruturado contra a documentação ATUAL de libs/serviços externos (junho/2026) e validado contra o código real do repositório.
> **Referência v1:** `old/smart-core-assistant-painel/` — Django admin (global + por-tenant) e o "Service Hub" como especificação funcional.

---

## 0. Caminhos reais validados no repositório (corrige paths do plano base)

O plano base usava paths abreviados. Os caminhos reais confirmados no código são:

| Conceito | Path real validado |
|---|---|
| Fachada gRPC-Web | `server/apps/runtime_api/src/grpc_web.rs` |
| Interceptor IPC `exigir_auth` | `server/apps/runtime_api/src/main.rs` (linhas ~281-391) |
| Forward admin IPC | `server/apps/runtime_api/src/main.rs` → `handler_admin_forward` (linha ~612) |
| Protos (canônicos) | `server/crates/contracts/schemas/queries/` (ex.: `auth.proto`) |
| Claims JWT | `server/crates/application/src/jwt.rs` (`Claims` tem `is_superuser: bool`, `jti`, `tenant_id`, `scopes`) |
| Handlers RPC | `server/apps/data_postgres/src/main.rs` |
| `control_plane` RPC/CLI | `server/apps/control_plane/src/` |
| Cliente Dart gerado | `clients/packages/api_client/lib/src/generated/queries/` (`auth.pb.dart`, `auth.pbgrpc.dart`, `auth.pbenum.dart`) |
| Client gRPC-Web | `clients/packages/api_client/lib/grpc_web_client.dart`, `clients/packages/api_client/lib/src/grpc_api_client.dart` |
| Módulo de login (molde) | `clients/modulos/login_module/` |

> **Ação:** o `admin.proto` vai em `server/crates/contracts/schemas/queries/admin.proto` (não em `contracts/schemas/...`), e o Dart gerado em `clients/packages/api_client/lib/src/generated/queries/admin.*`.

---

## 1. Objetivo

Construir o **plano de controle total** da aplicação para o **superusuário**: o ponto único onde toda a plataforma é parametrizada — system prompts, API keys das LLMs, configuração por tenant, integrações, planos/billing, feature flags, auditoria e dashboards — sem acesso direto ao banco.

**Escopo (decisão):** este app (`smart-core-admin`) é **superadmin/configuração**. A operação diária do tenant (chat/kanban/CRM) será outro app cliente. O superusuário pode, porém, editar a configuração de qualquer tenant alvo (contexto por `tenant_id` no payload).

**Princípio arquitetural:** o Flutter admin fala **exclusivamente com `runtime_api`** via **gRPC-Web** (app Web/WASM). O `runtime_api` valida o JWT (superusuário) e repassa ao `data_postgres` (CRUD) e ao `control_plane` (lógica de negócio) por RPC interno (`Envelope`). Nenhuma tela acessa a infraestrutura diretamente.

---

## 2. Decisões desta consolidação

- **Transporte admin:** um `AdminService` gRPC **tipado** (proto) exposto na fachada gRPC-Web, espelhando o padrão do `AuthService` em `grpc_web.rs`.
- **Entrega:** roadmap faseado completo, com um **molde repetível** (§5) aplicado por fatias verticais.
- **Auditoria & observabilidade (§12):** toda ação registra o que foi feito e por quem; reaproveita a infra de borda existente (`publicar_auditoria_borda`).
- **Melhorias de mercado incorporadas (§13):** teste de conexão/health, versionamento de config, feature flags dinâmicas, dashboards & cost tracking.
- **State Flutter:** padrão existente — Clean Arch + `return_success_or_error` + get_it (`AppModule`/`GetItModule`) + `BaseController`/`ViewStateBuilder` + `design_system_module`.

---

## 3. Realidade do código atual (correções factuais)

### 3.1 O que JÁ existe (não recriar)

- **Banco modelado quase por completo** (migrations 0001–0011, ~35 tabelas com RLS): tenants/config, **billing** (`tenants_plan`/`tenants_subscription`/`tenants_paymentrecord` na 0003), clientes/contatos, operacional, atendimentos, treinamento/RAG, evolution_sync (0008), audit_log (0010), outbox (0011).
- **Handlers RPC no `data_postgres`** (JSON sobre `Envelope`): `ListCoreSettings`, `UpsertCoreSetting`, `DeleteCoreSetting`, `GetTenantConfig`, `UpdateTenantConfig` (com cifragem AES-GCM e masking `••••••••` prontos), `CreateTenant`, `CreateSuperuser`/`ListSuperusers`/`DeleteSuperuser`, `GetUserIdentity`, `ListAtendimentos`, `GetThread`, `PersistMessage`, `UpsertContact`, `VerifyCredentials`.
- **Rotas admin no `transport::Server` do `runtime_api`** (IPC interno) com `exigir_auth(..., exigir_superuser=true)`: CoreSettings CRUD, TenantConfig get/update, GetUserIdentity, StreamAtendimentos. Padrão de forward: `handler_admin_forward(deps, env, target_method, reply_method)` → `deps.pg.call(...)`.
- **`control_plane` é serviço RPC** (não só CLI): rota `RegisterTenant` + subcomando `create-superuser`.
- **Cifragem:** `infrastructure_postgres::crypto::CipherManager` (AES-256-GCM) + `TenantConfigCache` (invalidação via Redis pub/sub).
- **JWT:** `Claims { sub, tenant_id, scopes, is_superuser, jti, iat, exp }` em `application/src/jwt.rs`; `validar_access_token(token) -> Result<Claims, AppError>` (HS256, `jsonwebtoken` 9.3.0).
- **Flutter:** `login_module` (Clean Arch completo), `api_client` (gRPC-Web + protobuf gerado), `design_system_module` (tema gold/stone), `presentation_module` (`BaseController`), `navigation_module`, DI via `get_it_module`.

### 3.2 O GARGALO (peça crítica que falta)

O Flutter é **Web/WASM** e só alcança a **fachada gRPC-Web** (`server/apps/runtime_api/src/grpc_web.rs`), que **hoje só expõe `AuthService`** (Login/Refresh/Logout). **Nenhum endpoint admin chega ao browser.** As rotas admin existem só no `transport::Server` (IPC interno), inacessível ao navegador. → Todo endpoint admin precisa ser **exposto na fachada gRPC-Web**.

**[Segurança — crítico]** A fachada gRPC-Web **não tem guarda de superuser** (só `logout` valida token via `validar_access_token`, e mesmo assim sem checar `is_superuser` nem blocklist). É preciso um helper `exigir_superuser_do_metadata` (JWT + blocklist Redis + `claims.is_superuser`) replicando o que o interceptor `exigir_auth` (main.rs) já faz para a borda IPC. Sem isso, expor admin via gRPC-Web abriria acesso indevido.

### 3.3 O que NÃO existe (a criar)

- **Handlers RPC** de listagem/edição da maioria dos domínios: `ListTenants`/`GetTenant`/`UpdateTenant`/`SetTenantActive`; planos/assinaturas/pagamentos CRUD; tenant users/invites; operacional; query de `audit_log`; agregações de dashboard.
- **Repos faltantes:** `TenantRepository::listar`/`atualizar`/`set_active` (hoje só `criar`/`buscar_por_id`); repos de plan/subscription/payment.
- **`AdminService` proto** + fachadas gRPC-Web + Dart gerado + `admin_module` Flutter.
- **Feature flags:** não há tabela (migration nova).
- **Cliente HTTP Evolution em Rust** (para "testar conexão"): `messaging_gateway` só bootstrapado; não há cliente Evolution real ainda.
- **Cost tracking de LLM:** depende do `ia_engine` (Python/gRPC) que ainda não existe.

### 3.4 Conceitos do old que NÃO se aplicam (não portar)

- **`TenantDatabase` (DB-per-tenant):** obsoleto — a v2 é single-DB + RLS (decisão D4).
- **Flags hardcoded em `settings.py`:** viram feature flags dinâmicas no banco (§13).
- **`TenantEvolution`/`TenantTrello` como tabelas próprias:** consolidados em `tenants_tenantconfig` + `evolution_sync_instance` (0008).

---

## 4. Stack e versões ATUAIS (validação de libs/serviços)

### 4.1 Rust — sem breaking changes relevantes (usar local)

| Lib | Versão | Uso no painel / nota de atualização |
|---|---|---|
| `tonic` | 0.14.6 | `Server::builder().add_service(AdminServiceServer::new(...))`; `Status::permission_denied("errors.auth.forbidden")` |
| `tonic-web` | 0.14.1 | `GrpcWebLayer::new()` + `accept_http1(true)` — sem breaking vs 0.12; **CORS ANTES do GrpcWebLayer** (já é assim em `grpc_web.rs`) |
| `prost` | 0.14.3 | `encode()`/`decode()` idênticos vs 0.13.5. **Deprecação: `from_i32()` → usar `TryFrom<i32>`** em enums protobuf |
| `jsonwebtoken` | 9.3.0 | `decode::<Claims>(&token, &DecodingKey::from_secret(...), &Validation::new(Algorithm::HS256))` — já encapsulado em `application::jwt::validar_access_token` |
| `secrecy` | 0.10.3 | `SecretString::new(decrypted.into())`; expor só via `.expose_secret()`; **nunca** `derive(Debug)` em struct com credencial |
| `reqwest` | 0.12.4 | cliente Evolution: `.header("apikey", key.expose_secret())` |
| `sqlx` | 0.9.0 | pool admin cross-tenant; `run_in_tenant_transaction` para repos tenant-específicos |
| `redis` | 0.25.0 | blocklist: `IsTokenBlocked` via `deps.redis.call(...)` (padrão já usado no `exigir_auth`) |

### 4.2 Flutter/Dart — padrões atuais

| Lib | Versão | Nota de atualização |
|---|---|---|
| `grpc` (Dart) | 5.1.0 (de ~4.0.0) | **BREAKING: requer `protoc_plugin` ≥ 16.0.0 para gerar stubs.** `GrpcWebClientChannel.xhr(Uri.parse(...))` igual ao 4.x. JWT dinâmico via `CallOptions(providers: [injectAuthToken])`. `WebCallOptions(metadata: {...}, bypassCorsPreflight: true)` para CORS. **Limitação:** sem client-streaming/bidi em browser → exportações CSV usam **server-streaming** (suportado) ou unário paginado |
| `get_it` | 9.2.1 | `getIt.registerLazySingleton<AdminDatasource>(...)` — igual ao `login_module` |
| `return_success_or_error` | 2.0.0 | `fetch(() => repository.listTenants())` em usecases |
| `go_router` | 17.3.0 | `GoRoute` com `redirect` para `SuperuserGuard` |

### 4.3 Evolution API (Go, v2.x)

- **Autenticação:** header `apikey: {API_KEY}` — global (`AUTHENTICATION_API_KEY`) ou por instância (`hash.apikey` do create).
- **`GET /instance/connectionState/{instanceName}`** → usado por `TestEvolutionConnection`. Resposta: `{"instance": {"instanceName": "...", "state": "open"}}`; estados: `"open"`, `"close"`, `"connecting"`.
- **`GET /instance/fetchInstances`** → lista todas as instâncias com status.
- Repo GitHub migrou `EvolutionAPI/` → `evolution-foundation/` (endpoints sem breaking).

---

## 5. Molde repetível ("fábrica" de um recurso admin)

1. **Repo Rust** (`infrastructure_postgres/src/...`): `listar`/`buscar`/`criar`/`atualizar`/`remover` (anote `#[instrument(skip_all)]` em repos tenant via `run_in_tenant_transaction`).
2. **Handler RPC** no `data_postgres`: JSON sobre `Envelope`, `resolver_tenant_alvo`, `ok_reply`/`erro`, `publicar_auditoria`. `#[tracing::instrument(err)]`.
3. **Proto** no `AdminService` (`server/crates/contracts/schemas/queries/admin.proto`) + registro no `build.rs`. Enums: consumir via `TryFrom<i32>`.
4. **Fachada gRPC-Web** (`runtime_api/src/grpc_web.rs`): `exigir_superuser_do_metadata` → delega ao `data_postgres`/`control_plane` via `deps.pg.call`/`deps.cp.call` (padrão `handler_admin_forward`) → converte JSON↔proto → registra `add_service` no `serve()`.
5. **Dart gerado** no `api_client` (pipeline com `protoc_plugin` ≥16.0.0) + expor stub em `grpc_api_client.dart`.
6. **Feature Flutter** no `admin_module` (Clean Arch): datasource gRPC → usecase (`UsecaseBaseCallData`) → controller (`BaseController`) + page (`ViewStateBuilder`).

> **Roteamento:** CRUD simples → `data_postgres`; ações complexas (provisionar tenant, gerar código + e-mail, testar conexão Evolution, agregações) → `control_plane`.

---

## 6. Pré-requisitos (dependências de fase)

| Pré-requisito | Status | Nota |
|---|---|---|
| `runtime_api` + fachada gRPC-Web | ✅ parcial | só `AuthService`; estender com `AdminService` |
| `AuthService` (Login/Refresh/Logout) | ✅ | login do superusuário funciona |
| Guarda `is_superuser` na fachada gRPC-Web | 🔴 | **criar `exigir_superuser_do_metadata`** |
| `control_plane` serviço RPC | ✅ | só `RegisterTenant`; estender com ações complexas |
| `data_postgres` repos/handlers | 🟡 | CoreSettings/TenantConfig ok; resto a criar |
| Pipeline de geração Dart de proto | ✅ | precedente `auth.pb.dart`; **exige `protoc_plugin` ≥16.0.0** |
| `admin_module` Flutter | 🔴 | criar do zero, espelhando `login_module` |

**Ordem macro:** Fundação (Fase 0) → Fases 1→6, cada uma aplicando o molde (§5).

---

## ETAPA 0 — Fundação

**Branch:** `feature/admin-foundation`.

### 0.1 `admin_module` novo
- `clients/modulos/admin_module/`, registrado no workspace `pubspec.yaml`, espelhando `login_module` (mesma árvore `lib/src/features/<feature>/{data,domain,presentation}`).

### 0.2 Shell admin
- Substituir placeholder `/home` em `app.dart` por `AppScaffold` com navegação lateral; `/admin` como destino pós-login em `auth_redirect.dart` (go_router 17.3.0, `redirect`).

### 0.3 Guarda de segurança — `exigir_superuser_do_metadata` (CRÍTICO)

Helper na fachada gRPC-Web replicando o que o `exigir_auth` (IPC) já faz: extrai bearer do metadata, valida JWT, **checa blocklist no Redis** e **exige `claims.is_superuser`**. Em falha de privilégio, audita `auth_access_denied` (WARN) e retorna `PERMISSION_DENIED`.

```rust
// runtime_api/src/grpc_web.rs (pt-br)
// Guarda de borda: valida JWT + blocklist + is_superuser. Reaproveita o padrão do
// interceptor `exigir_auth` (main.rs) e a auditoria de borda existente.
async fn exigir_superuser_do_metadata<T>(
    facade: &AdminFacade,
    req: &Request<T>,
) -> Result<application::jwt::Claims, Status> {
    let traceparent = traceparent_do_metadata(req);

    // 1. Extrair access token do metadata authorization (com/sem "Bearer ")
    let bearer = bearer_do_metadata(req);
    let token = bearer.strip_prefix("Bearer ").unwrap_or(&bearer).trim();
    if token.is_empty() {
        return Err(Status::unauthenticated("errors.auth"));
    }

    // 2. Validar assinatura/expiração (jsonwebtoken 9.3.0 via helper de application)
    let claims = application::jwt::validar_access_token(token)
        .map_err(|_| Status::unauthenticated("errors.auth"))?;

    // 3. Blocklist no Redis (mesmo RPC interno IsTokenBlocked do exigir_auth)
    let blocked_payload = serde_json::json!({ "jti": claims.jti });
    let block_req = application::auth::login::montar_envelope_request(
        uuid::Uuid::nil(), &traceparent, "IsTokenBlocked", &blocked_payload,
    );
    match facade.deps.redis.call(block_req, std::time::Duration::from_secs(3)).await {
        Ok(resp) => {
            let v: serde_json::Value =
                serde_json::from_slice(&resp.payload).unwrap_or_default();
            if v.get("blocked").and_then(|b| b.as_bool()).unwrap_or(false) {
                return Err(Status::unauthenticated("errors.auth"));
            }
        }
        Err(_) => return Err(Status::internal("errors.internal")),
    }

    // 4. Exigir superusuário; tentativa indevida = evento de segurança auditável
    if !claims.is_superuser {
        let mut bus = facade.bus.clone();
        publicar_auditoria_borda(
            &mut bus,
            None, // tenant_alvo desconhecido nessa borda
            "WARN",
            "auth_access_denied",
            "Acesso admin via gRPC-Web negado (sem is_superuser).".to_string(),
            serde_json::json!({}), // NUNCA o token/credencial
            claims.sub.parse::<i32>().ok(),
            &traceparent,
            ip_do_metadata(req),
        )
        .await;
        return Err(Status::permission_denied("errors.auth.forbidden"));
    }

    Ok(claims)
}
```

> Reuso direto das funções já existentes em `grpc_web.rs`: `bearer_do_metadata`, `traceparent_do_metadata`, `ip_do_metadata`, `publicar_auditoria_borda`.

### 0.4 `AdminService` proto inicial + pipeline Dart validado
- `server/crates/contracts/schemas/queries/admin.proto` com o subconjunto da Fase 1 (CoreSettings) + registro no `build.rs`.
- Pipeline Dart (ver Etapa B.0) validada gerando `admin.pb.dart`/`admin.pbgrpc.dart`.

### 0.5 Fatia vertical de validação: **CoreSettings ponta a ponta**
- Handler já existe no `data_postgres` (`ListCoreSettings`/`UpsertCoreSetting`/`DeleteCoreSetting`). Provar o caminho proto→fachada→dart→tela antes de escalar.

### Observabilidade & Auditoria — Etapa 0

**a) Logs/traces:** `exigir_superuser_do_metadata` roda dentro de spans `#[tracing::instrument(skip_all, fields(service="runtime_api", rpc, traceparent))]` em cada RPC da fachada (igual ao `AuthService`). Campos de correlação: `traceparent`, `actor_id` (`claims.sub`). **`skip_all`** garante que nenhum argumento (que poderia conter token) entre nos campos do span.

**b) Auditoria no banco:** acesso negado → `publicar_auditoria_borda(... "WARN", "auth_access_denied" ...)` → bus Redis (STREAM_SEGURANCA) → consumidor `data_postgres` → `INSERT audit_log` (assíncrono). Sucesso de borda admin não gera evento próprio na Fase 0 (a ação concreta — CoreSettings — é auditada pelo handler do `data_postgres`).

**c) Sanitização:** o `context` do evento é `{}` — **nunca** carrega token, `jti`, senha ou PII. O JWT trafega só no metadata e nunca é logado (mapeador de erro retorna chaves i18n estáveis, não o detalhe interno).

**DoD Etapa 0:** `flutter analyze` limpo; `cargo clippy -D warnings` limpo; grpcurl em `AdminService/ListCoreSettings` retorna dados com JWT superuser e `PERMISSION_DENIED` sem JWT / com JWT comum; tela CoreSettings renderiza com masking `••••••••` para `encrypted=true`.

---

## ETAPA A — Backend por fase (aplicação do molde §5)

- **A.1** Repos faltantes (`infrastructure_postgres`).
- **A.2** Handlers `data_postgres` + auditoria via `publicar_auditoria`.
- **A.3** `control_plane` ações complexas.
- **A.4** `admin.proto` + `build.rs`.
- **A.5** Fachada gRPC-Web (`AdminServiceServer`) + server-streaming para CSV.

**DoD A:** grpcurl chama todos os RPCs com JWT superuser; sem JWT ou com JWT comum → `PERMISSION_DENIED`; mapeamento proto↔JSON coberto por teste em Rust.

---

## ETAPA B — Frontend por fase

### B.0 Geração de stubs Dart (pipeline atualizado)

**IMPORTANTE — `protoc_plugin` ≥ 16.0.0** é obrigatório para o `grpc` Dart 5.1.0. Antes de rodar `protoc`:

```bash
# 1. Instalar/atualizar o plugin Dart (>= 16.0.0 para grpc 5.1.0)
dart pub global activate protoc_plugin 16.0.0

# 2. Garantir que ~/.pub-cache/bin está no PATH (protoc-gen-dart)
export PATH="$PATH:$HOME/.pub-cache/bin"

# 3. Gerar stubs do AdminService (mesmo padrão do auth.pb.dart)
protoc \
  --dart_out=grpc:clients/packages/api_client/lib/src/generated \
  -Iserver/crates/contracts/schemas \
  server/crates/contracts/schemas/queries/admin.proto
```

Saída esperada em `clients/packages/api_client/lib/src/generated/queries/`: `admin.pb.dart`, `admin.pbenum.dart`, `admin.pbgrpc.dart`, `admin.pbjson.dart`. Expor `AdminServiceClient` em `grpc_api_client.dart`, com `CallOptions(providers: [injectAuthToken])` injetando `authorization: Bearer <JWT>` (mesmo `auth_token_interceptor.dart`).

### B.1 Shell + navegação + `SuperuserGuard`
- `SuperuserGuard` no `go_router` (`redirect`): se a sessão não for de superusuário, redireciona para `/login`.

### B.2 → B.n Telas por fase
- Datasource gRPC (`on GrpcError catch` → `mapGrpcError`) → usecase (`fetch(...)`) → controller (`BaseController`) → page (`ViewStateBuilder`), igual ao `login_grpc_datasource.dart`.

**DoD B:** telas operacionais contra `runtime_api` real; cifrados nunca exibem valor real; máscara `••••••••` enviada no update **preserva** o valor.

---

## 7. Roadmap de domínios (Fases)

### Fase 1 — Configuração global & IA

- **CoreSettings** ✅ (handler pronto) — globais: API keys, modelos padrão, prompts de sistema, thresholds, embeddings. Tela: tabela (key/description/encrypted/updated_at) + CRUD; `encrypted=true` exibe `••••••••`.
- **TenantConfig** ✅ (Get/Update prontos, cifragem + masking) — por tenant alvo: LLM (llm_class/model/temperature), Bot/Prompts, Mensagens automáticas, Entidades (JSON), API Keys (mascaradas), Branding/RAG.

**Observabilidade & Auditoria — Fase 1**
- **a) Logs/traces:** handlers `UpsertCoreSetting`/`UpdateTenantConfig` com `#[tracing::instrument(err)]`; correlação `actor_id`, `tenant_alvo`, `trace_id`, `error_code`.
- **b) Auditoria:** `core_setting_upserted` e `tenant_api_key_changed` (WARN para mudança de chave) → bus → `audit_log`. `context` registra **quais** chaves mudaram (nomes), nunca os valores.
- **c) Sanitização:** valores `encrypted` cifrados com `CipherManager`; em `secrecy::SecretString` no caminho de decifragem; auditoria e logs **nunca** contêm o valor.

### Fase 2 — Tenants & Billing

- **Dashboard de Tenants** 🟡: lista com `subscription_status` colorido, filtros, bulk actions (estender assinatura/ativar/suspender/gerar código `[A-Z0-9]{3}-[A-Z0-9]{3}`). Faltam: `ListTenants`/`GetTenant`/`UpdateTenant`/`SetTenantActive` + repos.
- **Detalhe do Tenant** 🟡: abas Identificação, Credenciais (api_key mascarada), Config IA, Assinatura, Pagamentos.
- **Planos/Assinaturas/Pagamentos** 🟡 (tabelas 0003 existem; faltam repos/handlers). Registro manual → cria PaymentRecord + estende `current_period_end`.
- **TenantUser/TenantInvite** 🟡 (tabelas 0002): RBAC por módulo.

**Observabilidade & Auditoria — Fase 2**
- **a) Logs/traces:** repos `TenantRepository::listar/atualizar/set_active` com `#[instrument(skip_all)]` via `run_in_tenant_transaction`; handlers de billing com `#[tracing::instrument(err)]`. Bulk actions registram contagem e lista de `tenant_id` afetados no span.
- **b) Auditoria:** `tenant_updated`, `subscription_updated`, `payment_registered`, `tenant_user_invited`, `tenant_user_revoked` → bus → `audit_log`, cada um com `diff before/after` sanitizado, `actor_id`, `tenant_alvo`, `trace_id`.
- **c) Sanitização:** `api_key` do tenant nunca no log/auditoria; geração do código de acesso registra apenas o evento, não o código por si só onde for sensível.

### Fase 3 — Integrações + teste de conexão/health

- **Evolution** 🟡: server_url, api_key (cifrada), instance_name, connection_state. Botão "Testar Conexão" → `control_plane::TestEvolutionConnection`. **Requer cliente HTTP Evolution em Rust (🔴 a criar).**
- **Painel de saúde:** status dos serviços/instâncias + validação de keys LLM.

#### TestEvolutionConnection — implementação detalhada (reqwest + secrecy)

A ação roda no **`control_plane`** (lógica complexa + acesso a credencial cifrada). Decifra a `api_key` internamente em `SecretString`, chama `GET /instance/connectionState/{instanceName}` com header `apikey` e devolve apenas o estado (`open`/`close`/`connecting`).

```rust
// control_plane: cliente Evolution mínimo para teste de conexão (pt-br)
use secrecy::{ExposeSecret, SecretString};
use serde::Deserialize;

#[derive(Deserialize)]
struct ConnStateResp {
    instance: ConnStateInner,
}
#[derive(Deserialize)]
struct ConnStateInner {
    state: String, // "open" | "close" | "connecting"
}

// `api_key` chega decifrada do CipherManager, encapsulada em SecretString.
// A struct nunca deriva Debug; o valor só sai via expose_secret() no header.
#[tracing::instrument(skip_all, fields(service = "control_plane", rpc = "TestEvolutionConnection", traceparent))]
pub async fn testar_conexao_evolution(
    http: &reqwest::Client,        // reqwest 0.12.4
    server_url: &str,
    instance_name: &str,
    api_key: &SecretString,
    traceparent: &str,
) -> Result<String, error_core::AppError> {
    let url = format!("{}/instance/connectionState/{}", server_url.trim_end_matches('/'), instance_name);

    let resp = http
        .get(&url)
        .header("apikey", api_key.expose_secret()) // único ponto que expõe o segredo
        .send()
        .await
        .map_err(|e| error_core::AppError::Internal(format!("Evolution indisponível: {e}")))?;

    if !resp.status().is_success() {
        // NUNCA logar a key; só status HTTP
        return Err(error_core::AppError::Validation(format!(
            "connectionState retornou HTTP {}", resp.status()
        )));
    }

    let body: ConnStateResp = resp
        .json()
        .await
        .map_err(|e| error_core::AppError::Internal(format!("resposta inválida: {e}")))?;

    Ok(body.instance.state) // "open" / "close" / "connecting"
}
```

**Observabilidade & Auditoria — Fase 3**
- **a) Logs/traces:** `#[tracing::instrument(skip_all, ...)]` no handler `control_plane`; em caso de falha de rede, `error_code` e status HTTP no span (nunca a credencial). O cliente `reqwest` registra latência da chamada.
- **b) Auditoria:** `connection_tested` → bus → `audit_log`, `context` com `{ instance_name, state, http_status }` — **nunca** a `api_key`.
- **c) Sanitização:** `api_key` vive em `SecretString`; só `expose_secret()` no header `apikey`; struct sem `derive(Debug)`. O `control_plane` decifra internamente e nunca devolve a credencial ao browser.

### Fase 4 — Feature flags + versionamento de config

- **Feature flags** 🔴: migration nova (`feature_flags`: flag global + override por tenant) + CRUD (`ListFeatureFlags`/`SetFeatureFlag`).
- **Viewer de histórico** baseado em `audit_log`; rollback = etapa avançada.

**Observabilidade & Auditoria — Fase 4**
- **a) Logs/traces:** `SetFeatureFlag` com `#[tracing::instrument(err)]`; span registra `flag_key`, escopo (global/tenant), valor anterior→novo.
- **b) Auditoria:** `feature_flag_set` → bus → `audit_log` com `diff before/after` (booleano/escopo). O viewer de histórico **lê** `audit_log` (filtros por `event_type`/período/tenant).
- **c) Sanitização:** flags não são segredos, mas o viewer aplica o mesmo masking de qualquer campo cifrado caso apareça; nenhum token/PII no `context`.

### Fase 5 — Auditoria & Dashboards

- **Audit viewer** 🟡: filtros (nível/serviço/evento/trace_id/período/tenant/user) via `QueryAuditLog`. Deep-link `trace_id` → Grafana/Tempo.
- **Dashboard principal** 🔴: `GetDashboardSummary` — cards KPIs + gráficos.
- **Exportações CSV**: `ExportTenantsCsv` / `ExportPaymentsCsv` como **server-streaming** (suportado em browser; client/bidi-streaming **não** é). Alternativa: unário paginado.

**Observabilidade & Auditoria — Fase 5**
- **a) Logs/traces:** `QueryAuditLog`/`GetDashboardSummary` com `#[tracing::instrument(err)]`; agregações registram janelas temporais e contagens no span. Exportações registram nº de linhas emitidas.
- **b) Auditoria:** exportações de dados sensíveis geram `data_exported` (CSV) → `audit_log` com `{ scope, row_count }`. Acessos ao viewer não geram ruído, mas filtros por tenant herdam `tenant_alvo`.
- **c) Sanitização:** o CSV exportado **mascara** colunas cifradas (api_key etc.); o `context` do evento nunca traz linhas de dados, só metadados de volume.

### Fase 6 — Operacional por tenant

- Atendentes, Departamentos, AppInstances, campos dinâmicos, etiquetas, treinamento/RAG. Tabelas/repos existem; faltam handlers.

**Observabilidade & Auditoria — Fase 6**
- **a) Logs/traces:** handlers operacionais com `#[tracing::instrument(err)]`; repos tenant via `run_in_tenant_transaction` (`#[instrument(skip_all)]`), correlação por `tenant_alvo`.
- **b) Auditoria:** eventos `*_created`/`*_updated`/`*_deleted` por entidade operacional → `audit_log` com `diff before/after`.
- **c) Sanitização:** dados de treinamento/RAG podem conter PII → o `context` registra só identificadores e contagens, nunca o conteúdo bruto.

---

## 8. Modelo de dados — tabelas envolvidas

| Tabela (nome real) | Entidade | Migration |
|---|---|---|
| `tenants_tenant` | Tenant | 0002 |
| `tenants_tenantconfig` | TenantConfig | 0002 |
| `tenants_tenantuser` | TenantUser | 0002 |
| `tenants_tenantinvite` | TenantInvite | 0002 |
| `tenants_plan` | Plan | 0003 |
| `tenants_subscription` | Subscription | 0003 |
| `tenants_paymentrecord` | PaymentRecord | 0003 |
| `oraculo_app_instance` | AppInstance | 0005 |
| `evolution_sync_instance` | EvolutionInstance | 0008 |
| `settings_manager_coresettings` | CoreSettings (global) | 0009 |
| `audit_log` | AuditLog | 0010 |
| `auth_user` | AuthUser | 0001 |
| *(nova)* `feature_flags` | FeatureFlag | Fase 4 |

---

## 9. Arquitetura de implementação

```
[Flutter Admin Web/WASM]
    │  gRPC-Web (HTTP/1.1, metadata: authorization: Bearer <JWT superuser>)
    │  GrpcWebClientChannel.xhr(...) + CallOptions(providers: [injectAuthToken])
    ▼
[runtime_api] ── exigir_superuser_do_metadata (JWT + blocklist Redis + is_superuser)
    │                                    │
    ▼                                    ▼
[data_postgres] (CRUD via Envelope)  [control_plane] (lógica: provisionar tenant,
   handler_admin_forward(deps.pg)      gerar código, TestEvolutionConnection, agregações)
                                       deps.cp.call(...)
```

---

## 10. Contratos gRPC — `AdminService`

`server/crates/contracts/schemas/queries/admin.proto`. Grupos de RPCs:

- **Tenants:** ListTenants, GetTenant, CreateTenant, UpdateTenant, SetTenantActive, BulkExtendSubscription, BulkSetTenantActive, GenerateAccessCode
- **Billing:** ListPlans, CreatePlan, UpdatePlan, SetPlanActive, ListSubscriptions, RegisterPayment, ListPayments
- **Config:** ListCoreSettings, UpsertCoreSetting, DeleteCoreSetting, GetTenantConfig, UpdateTenantConfig, TestEvolutionConnection, TestLlmKey
- **TenantUsers:** ListTenantUsers, InviteTenantUser, UpdateTenantUser, RevokeTenantUser
- **Feature flags:** ListFeatureFlags, SetFeatureFlag
- **Audit/Dashboard:** QueryAuditLog, GetConfigHistory, GetServiceHealth, GetDashboardSummary, ExportTenantsCsv (server-stream), ExportPaymentsCsv (server-stream)

> **Enums protobuf:** consumir em Rust via `TryFrom<i32>` (`prost` 0.14.3 deprecou `from_i32()`). Ex.: `SubscriptionStatus::try_from(v).unwrap_or_default()`.

---

## 11. Campos encriptados — política de segurança

- `api_keys` (JSON) em `tenants_tenantconfig` → mascarado por chave (`••••••••`).
- `value` (quando `encrypted`) em `settings_manager_coresettings` → mascarado na leitura.
- `api_key` da instância em `evolution_sync_instance` → mascarado; edição substitui.
- Enviar máscara `••••••••` no update **preserva** o valor existente.
- Para `TestEvolutionConnection`, o `control_plane` decifra internamente (em `SecretString`), nunca expõe.

---

## 12. Auditoria e observabilidade do painel (pipeline canônico)

Toda ação do `AdminService` emite evento de auditoria **assíncrono**:

```
publicar_auditoria(_borda)(bus, tenant_alvo, level, event_type, msg, context, actor_id, traceparent, ip)
  → Redis STREAM_SEGURANCA → consumidor data_postgres → INSERT audit_log
```

**Política de instrumentação:**
- `#[tracing::instrument(err)]` em handlers de infra onde todo erro é falha real.
- `#[instrument(skip_all)]` em repos de tenant via `run_in_tenant_transaction`.
- `skip_all` em qualquer span que receba token/credencial como argumento.
- Campos de correlação obrigatórios: `actor_id` (superuser do JWT), `tenant_alvo`, `trace_id`/`traceparent`, `error_code`.

**Catálogo de eventos por domínio:**

| Domínio/RPC | event_type | Nível | context mínimo (sanitizado) |
|---|---|---|---|
| Acesso negado | `auth_access_denied` | WARN | `{ method }` |
| Tenant update/owner | `tenant_updated` | INFO | `diff before/after` (sem segredos) |
| Convite | `tenant_user_invited` | INFO | `{ email_destino, role }` |
| Revogação | `tenant_user_revoked` | INFO | `{ tenant_user_id }` |
| Assinatura | `subscription_updated` | INFO | `{ plan_id, period_end }` |
| Pagamento | `payment_registered` | INFO | `{ amount, period_end }` |
| API key tenant | `tenant_api_key_changed` | WARN | `{ chaves_alteradas: [...] }` (nunca valores) |
| CoreSetting cifrado | `core_setting_upserted` | INFO | `{ key }` (nunca o valor) |
| Teste Evolution | `connection_tested` | INFO | `{ instance_name, state, http_status }` |
| Feature flag | `feature_flag_set` | INFO | `{ flag_key, escopo, before, after }` |
| Exportação | `data_exported` | INFO | `{ scope, row_count }` |

**Regra de ouro:** o `context` do evento **NUNCA** contém segredo, token, senha ou PII bruta.

---

## 13. Melhorias de mercado incorporadas

1. Teste de conexão / health (Fase 3/5).
2. Versionamento de config via `audit_log` (Fase 4).
3. Feature flags dinâmicas (Fase 4).
4. Dashboards & cost tracking (Fase 5, depende de `ia_engine`).

---

## 14. Critérios de aceite globais (DoD)

- Login JWT; refresh automático; **guarda `is_superuser` na fachada gRPC-Web** (`exigir_superuser_do_metadata`).
- CRUD completo tenants; Config global + por tenant ponta a ponta.
- CRUD planos; pagamento manual estende `current_period_end`.
- Campos cifrados nunca exibem valor real; máscara `••••••••` preserva valor no update.
- Feature flags dinâmicas em runtime.
- Toda ação gera evento de auditoria (actor, tenant_alvo, trace_id, diff before/after).
- Audit viewer com filtros; deep-link `trace_id` ao Grafana/Tempo.
- `GetServiceHealth`; dashboard KPIs; teste conexão integrações.
- `flutter analyze` limpo; `cargo clippy -D warnings` limpo.
- Testes: mapeamento proto↔JSON (Rust) + datasource/usecase/controller (Flutter).

---

## 15. Checklist transversal por PR

- [ ] Comentários e docstrings em pt-br; identificadores em inglês.
- [ ] Branch gitflow (`feature/admin-*`); commit sem auto-referência à IA.
- [ ] Proto novo registrado no `build.rs`; enums consumidos via `TryFrom<i32>` (não `from_i32()`).
- [ ] Dart gerado com `protoc_plugin` ≥ 16.0.0; stub exposto em `grpc_api_client.dart`.
- [ ] RPC protegido por `exigir_superuser_do_metadata` na fachada (verificado por grpcurl: `PERMISSION_DENIED` sem JWT/JWT comum).
- [ ] Span com `#[tracing::instrument]` (`skip_all`/`err` conforme o caso) e campos `actor_id`/`tenant_alvo`/`trace_id`/`error_code`.
- [ ] Evento de auditoria emitido (event_type do catálogo §12) com `context` sanitizado.
- [ ] Segredos só em `secrecy::SecretString`; sem `derive(Debug)` em struct com credencial; `expose_secret()` no único ponto de uso.
- [ ] Campos cifrados mascarados na leitura; máscara preserva valor no update.
- [ ] Testes: Rust (mapeamento proto↔JSON, guarda PERMISSION_DENIED) + Flutter (datasource/usecase/controller) via scripts canônicos (`.\infra\test-local.ps1`, `.\infra\test-flutter.ps1`).
- [ ] `cargo clippy -D warnings` e `flutter analyze` limpos.

---

## 16. Correções aplicadas (o que mudou, por quê, fonte)

| # | Correção | Por quê | Fonte |
|---|---|---|---|
| 1 | Paths corrigidos: protos em `server/crates/contracts/schemas/queries/`; Dart gerado em `clients/packages/api_client/lib/src/generated/queries/`; clients Flutter em `clients/modulos/` e `clients/packages/` | O plano base usava paths abreviados que não existem no repo | Inspeção do código (`grpc_web.rs`, `auth.proto`, árvore `clients/`) |
| 2 | `from_i32()` → `TryFrom<i32>` em enums protobuf | `prost` 0.14.3 deprecou `from_i32()` | doc aux (libs Rust) |
| 3 | Etapa B.0 ganhou passo explícito `dart pub global activate protoc_plugin 16.0.0` antes do `protoc` | `grpc` Dart 5.1.0 exige `protoc_plugin` ≥ 16.0.0 (breaking) | doc aux (libs Flutter) |
| 4 | `TestEvolutionConnection` detalhado com `GET /instance/connectionState/{instanceName}`, header `apikey`, `reqwest` 0.12.4 e `secrecy::SecretString` | Implementação concreta da Fase 3, sem vazar credencial | doc aux (Evolution v2.x + secrecy/reqwest) |
| 5 | `exigir_superuser_do_metadata` escrito reaproveitando funções reais de `grpc_web.rs` (`bearer_do_metadata`, `traceparent_do_metadata`, `ip_do_metadata`, `publicar_auditoria_borda`) e o fluxo do `exigir_auth` (validar JWT → blocklist `IsTokenBlocked` via `deps.redis.call` → `is_superuser`) | O plano base descrevia a guarda em alto nível; agora ela espelha o código existente fielmente | `runtime_api/src/main.rs` (linhas ~281-391) + `grpc_web.rs` |
| 6 | Exportações CSV fixadas como **server-streaming** (ou unário paginado), não client/bidi | `grpc` Dart em browser não suporta client/bidi-streaming | doc aux (grpc Dart 5.1.0) |
| 7 | Cada fase ganhou sub-seção "Observabilidade & Auditoria" com os 3 eixos (logs/traces, auditoria no banco, sanitização) | Requisito inviolável do escopo de reestruturação | TAREFAS §7/§9 + doc aux (observabilidade) |
| 8 | Catálogo de eventos de auditoria por domínio consolidado em tabela (§12) com `context` mínimo sanitizado | Tornar a auditoria verificável por PR | doc aux (eventos críticos §08 §4.2) |
| 9 | Claims JWT alinhadas ao struct real (`is_superuser`, `jti`, `tenant_id` vazio/nil = global) | O plano base não detalhava o shape real das claims | `application/src/jwt.rs` |
| 10 | Versões de libs fixadas (tonic 0.14.6, tonic-web 0.14.1, prost 0.14.3, jsonwebtoken 9.3.0, secrecy 0.10.3, reqwest 0.12.4, sqlx 0.9.0, redis 0.25.0; grpc 5.1.0, get_it 9.2.1, return_success_or_error 2.0.0, go_router 17.3.0) | Referência única e atual para implementação | doc aux (libs) |
