# Documentação Auxiliar — Painel Gerencial do Superusuário

> Gerado em: 2026-06-18
> Plano canônico: `.context/plans/painel-admin-superusuario.md`
> Plano completo: `.context/plans/painel-admin-superusuario/plano_completo_painel-admin-superusuario.md`

---

## Resultado da Triagem de Libs (Etapa 2a)

| Lib | Stack | Versão no Projeto | Status | Ação tomada |
|---|---|---|---|---|
| tonic | Rust | 0.14.6 | ✅ | USAR LOCAL |
| tonic-build | Rust | 0.14.6 | ✅ | USAR LOCAL |
| tonic-web | Rust | 0.14.1 | ⚠️→✅ | ATUALIZAR — doc estava em 0.12 |
| prost | Rust | 0.14.3 | ⚠️→✅ | ATUALIZAR — doc estava em 0.13.5 |
| jsonwebtoken | Rust | 9.3.0 | ✅ | USAR LOCAL |
| secrecy | Rust | 0.10.3 | ✅ | USAR LOCAL |
| reqwest | Rust | 0.12.4 | ✅ | USAR LOCAL |
| sqlx | Rust | 0.9.0 | ✅ | USAR LOCAL |
| redis | Rust | 0.25.0 | ✅ | USAR LOCAL |
| tracing | Rust | 0.1.40 | ✅ | USAR LOCAL |
| axum | Rust | 0.7.5 | ✅ | USAR LOCAL |
| grpc (Dart) | Flutter | ^5.1.0 | ⚠️→✅ | ATUALIZAR — doc estava em ~4.0.0 |
| get_it | Flutter | ^9.2.1 | ✅ | USAR LOCAL |
| return_success_or_error | Flutter | ^2.0.0 | ✅ | USAR LOCAL |
| go_router | Flutter | 17.3.0 | ✅ | USAR LOCAL |

---

## Libs Rust (USAR LOCAL)

### tonic (0.14.6)
> Fonte: `doc_dev/libs/rust/tonic.md` — Última Verificação: 2026-06-04

Propósito no plano: servidor gRPC-Web para o `AdminService`. Registrar `AdminServiceServer` no `serve()` com o mesmo padrão do `AuthService`.

Padrão de registro de serviço:
```rust
Server::builder()
    .accept_http1(true)
    .layer(GrpcWebLayer::new())
    .add_service(AuthServiceServer::new(auth_handler))
    .add_service(AdminServiceServer::new(admin_handler)) // novo
    .serve(addr)
    .await?;
```

Padrão para status de erro gRPC usado no projeto:
- `Status::unauthenticated("Token inválido")` — JWT ausente/inválido
- `Status::permission_denied("Acesso restrito a superusuários")` — claims.is_superuser = false
- `Status::internal("Erro interno")` — falha de infra

### tonic-web (0.14.1) — ATUALIZADO 2026-06-18
> Fonte: `doc_dev/libs/rust/tonic-web.md` — Última Verificação: 2026-06-18
> Docs via Context7: `/hyperium/tonic` (High Reputation)
> **Sem breaking changes vs 0.12** — API de habilitação idêntica.

```rust
use tonic_web::GrpcWebLayer;

Server::builder()
    .accept_http1(true)           // HTTP/1.1 para clientes web
    .layer(GrpcWebLayer::new())   // traduz gRPC-Web → gRPC nativo
    .add_service(...)
    .serve(addr)
    .await?;
```

### tonic-build (0.14.6)
> Fonte: `doc_dev/libs/rust/tonic-build.md` — Última Verificação: 2026-06-05

Propósito no plano: compilar `admin.proto` → stubs Rust no `build.rs` da crate `contracts`.

```rust
// build.rs (padrão existente, só adicionar admin.proto)
tonic_build::configure()
    .build_server(true)
    .build_client(true)
    .compile(&["schemas/queries/admin.proto"], &["schemas"])?;
```

### prost (0.14.3) — ATUALIZADO 2026-06-18
> Fonte: `doc_dev/libs/rust/prost.md` — Última Verificação: 2026-06-18
> Docs via Context7: `/tokio-rs/prost` (High Reputation)
> **Sem breaking changes vs 0.13.5** — APIs de encode/decode estáveis.

```rust
use prost::Message;
// encode: buf.extend_from_slice(&msg.encode_to_vec());
// decode: let msg = MyMessage::decode(&mut bytes)?;
```

⚠️ **Deprecação mantida:** `MyEnum::from_i32(n)` → usar `MyEnum::try_from(n)` ou `is_valid(n)`.

### jsonwebtoken (9.3.0)
> Fonte: `doc_dev/libs/rust/jsonwebtoken.md` — Última Verificação: 2026-06-02

Propósito no plano: implementar `exigir_superuser_do_metadata` — extrair Bearer do metadata gRPC, decodificar claims e verificar `is_superuser = true`.

Padrão de validação (replicar do interceptor `exigir_auth`):
```rust
use jsonwebtoken::{decode, DecodingKey, Validation, Algorithm};

let token_data = decode::<Claims>(
    &token,
    &DecodingKey::from_secret(secret.as_bytes()),
    &Validation::new(Algorithm::HS256),
)?;
let claims = token_data.claims;
if !claims.is_superuser {
    return Err(Status::permission_denied("Requer is_superuser"));
}
```

### secrecy (0.10.3)
> Fonte: `doc_dev/libs/rust/secrecy.md` — Última Verificação: 2026-06-01

Propósito no plano: toda chave decriptada (API keys, token Evolution) deve ser `SecretString`. Nunca logar via `{:?}` ou `{}`.

```rust
use secrecy::{SecretString, ExposeSecret};
let api_key: SecretString = SecretString::new(decrypted_value.into());
// para usar o valor: api_key.expose_secret()
// struct com credenciais implementa: #[allow(dead_code)] — nunca derive Debug
```

### reqwest (0.12.4)
> Fonte: `doc_dev/libs/rust/reqwest.md` — Última Verificação: 2026-05-31

Propósito no plano: cliente HTTP para `control_plane::TestEvolutionConnection` — decripta api_key, faz requisição a `/instance/connectionState/{name}`, retorna resultado sem expor a chave.

```rust
use reqwest::Client;

let client = Client::new();
let response = client
    .get(format!("{}/instance/connectionState/{}", server_url, instance_name))
    .header("apikey", api_key.expose_secret())
    .send()
    .await?;
let status = response.status();
// HTTP 200 + body.state == "open" → conexão ok
```

### sqlx (0.9.0)
> Fonte: `doc_dev/libs/rust/sqlx.md` — Última Verificação: 2026-06-10

Propósito no plano: queries para `ListTenants`, `GetTenant`, `UpdateTenant`, `SetTenantActive`, repos de Plan/Subscription/Payment, queries de `audit_log`.

Padrão de pool admin (cross-tenant, sem RLS de tenant):
```rust
// Pool admin lê de qualquer tenant — usa pool sem SET app.current_tenant_id
let tenants = sqlx::query_as!(TenantRow,
    "SELECT id, name, slug, owner_id, is_active FROM tenants_tenant ORDER BY created_at DESC"
).fetch_all(&pool).await?;
```

Para repos tenant-específicos: `run_in_tenant_transaction(&pool, tenant_id, |tx| ...)`.

### redis (0.25.0)
> Fonte: `doc_dev/libs/rust/redis.md` — Última Verificação: 2026-06-10

Propósito no plano: verificar blocklist de tokens revogados em `exigir_superuser_do_metadata` (JWT pode ter sido revogado via logout).

```rust
// Checar blocklist (padrão do exigir_auth):
let blocklist_key = format!("blocklist:{}", jti);
let revoked: Option<String> = conn.get(&blocklist_key).await?;
if revoked.is_some() {
    return Err(Status::unauthenticated("Token revogado"));
}
```

### tracing (0.1.40)
> Fonte: `doc_dev/libs/rust/tracing.md` — Última Verificação: 2026-05-31

Propósito no plano: instrumentação de todos os handlers do `AdminService`.

Política do projeto (reproduzir do doc de erros e observabilidade):
- `#[tracing::instrument(err)]` — handlers de infra onde todo erro é falha real
- `#[instrument(skip_all)]` — repos de tenant via `run_in_tenant_transaction`
- Campos obrigatórios de correlação: `tenant_id`, `trace_id`, `error_code`, `actor_id`

```rust
#[tracing::instrument(skip(deps, req), fields(actor_id = %claims.sub, tenant_alvo = %tenant_id))]
async fn list_tenants(&self, req: Request<ListTenantsRequest>) -> Result<Response<...>, Status> {
    // ...
}
```

### axum (0.7.5)
> Fonte: `doc_dev/libs/rust/axum.md` — Última Verificação: 2026-05-31

Axum não é o transporte principal do `AdminService` (tonic é), mas pode ser usado para health endpoints. Sem mudanças de padrão para este plano.

---

## Libs Flutter (USAR LOCAL)

### grpc Dart (5.1.0) — ATUALIZADO 2026-06-18
> Fonte: `doc_dev/libs/flutter/grpc.md` — Última Verificação: 2026-06-18
> Docs via Context7: `/grpc/grpc-dart` (High Reputation, 110 snippets)

**Breaking change importante: `protoc_plugin` deve ser ≥16.0.0 para gerar stubs do `AdminService`.**

```bash
# Atualizar protoc_plugin antes de gerar admin.pbgrpc.dart
dart pub global activate protoc_plugin
# depois: protoc --dart_out=grpc:lib/src/generated -I../proto admin.proto
```

Criação do canal gRPC-Web (idêntico para AdminService):
```dart
import 'package:grpc/grpc_web.dart';
import 'src/generated/admin.pbgrpc.dart';

final channel = GrpcWebClientChannel.xhr(
  Uri.parse('https://api.smartcore.com'),
);
final stub = AdminServiceClient(channel);
```

JWT Bearer via provider dinâmico (padrão recomendado para admin_module):
```dart
// Injeta token do SecureStorage sem expor em código fixo
Future<void> injectAuthToken(Map<String, String> metadata, String uri) async {
  final token = await _tokenRepository.getAccessToken();
  if (token != null) metadata['authorization'] = 'Bearer $token';
}

final opts = CallOptions(providers: [injectAuthToken]);
final response = await stub.listTenants(ListTenantsRequest(), options: opts);
```

CORS + cabeçalhos (para WebCallOptions):
```dart
final webOpts = WebCallOptions(
  metadata: {'authorization': 'Bearer $token'},
  bypassCorsPreflight: true, // empacota headers em query param
);
```

Limitações gRPC-Web:
- ✅ Suporte: Unary + Server-Streaming (para exportação CSV)
- ❌ Sem suporte: Client-streaming e Bidirectional-streaming no browser

### get_it (9.2.1)
> Fonte: `doc_dev/libs/flutter/get_it.md` — Última Verificação: 2026-06-14

Propósito no plano: DI do `admin_module`. Registrar `AdminDatasource`, `AdminRepository`, usecases e controllers no `AppModule`.

Padrão do projeto (replicar de `login_module`):
```dart
// Em admin_module/lib/src/di/admin_module.dart
getIt.registerLazySingleton<AdminDatasource>(() => AdminDatasourceImpl(
  adminClient: getIt<AdminServiceClient>(),
));
getIt.registerLazySingleton<ListTenantsUsecase>(() => ListTenantsUsecaseImpl(
  repository: getIt<AdminRepository>(),
));
```

### return_success_or_error (2.0.0)
> Fonte: `doc_dev/libs/flutter/return_success_or_error.md` — Última Verificação: 2026-06-14

Propósito no plano: padrão de resultado para usecases do `admin_module`.

```dart
// Usecase (fetch = datasource, process = CPU-bound se necessário)
class ListTenantsUsecase extends UsecaseBaseCallData<List<TenantModel>, NoParams> {
  @override
  Future<Output<List<TenantModel>>> call(NoParams params) async {
    return fetch(() => repository.listTenants());
  }
}
```

### go_router (17.3.0)
> Fonte: `doc_dev/libs/flutter/go_router.md` — Última Verificação: 2026-06-14

Propósito no plano: navegação do shell admin — rotas protegidas por `SuperuserGuard`, navegação lateral por seção.

```dart
// SuperuserGuard como redirect do GoRouter
GoRoute(
  path: '/admin',
  redirect: (context, state) {
    final auth = context.read<AuthController>();
    if (!auth.isSuperuser) return '/login';
    return null;
  },
  builder: (context, state) => AdminShellPage(),
),
```

---

## Serviços Externos

### Evolution Go API (v2.x — evolution-foundation)
> Fonte: WebSearch/WebFetch — Coletado em 2026-06-18
> Docs oficiais: https://doc.evolution-api.com/v2/api-reference/
> GitHub: https://github.com/evolution-foundation/evolution-api (migrado de EvolutionAPI/)

#### Autenticação

**Dois níveis de autenticação:**
- **Chave API Global** (env `AUTHENTICATION_API_KEY`): acesso a todas as instâncias
  - Header: `apikey: {GLOBAL_API_KEY}`
- **Token de Instância** (campo `hash.apikey` retornado no create): acesso restrito
  - Header: `apikey: {INSTANCE_TOKEN}`

No smart-core-assistant-v2, a `api_key` da instância é armazenada cifrada em `evolution_sync_instance.api_key` (AES-256-GCM via `CipherManager`). Para `TestEvolutionConnection`, o `control_plane` decripta internamente e usa como header.

#### GET /instance/fetchInstances — Listar Instâncias

```bash
curl -X GET https://{server-url}/instance/fetchInstances \
  -H "apikey: {GLOBAL_API_KEY}"
```

Resposta (HTTP 200):
```json
{
  "data": [
    {
      "instanceName": "meu-whatsapp-01",
      "instanceId": "af6c5b7c-ee27-4f94-9ea8-192393746ddd",
      "owner": "+55 (11) 98765-4321",
      "status": "open",
      "serverUrl": "https://evolution-api.example.com",
      "apikey": "instance-token-hash-123456"
    }
  ],
  "count": 1
}
```

Campos de status: `"open"` (conectado), `"close"` (desconectado), `"connecting"` (sincronizando).

#### GET /instance/connectionState/{instanceName} — Status da Conexão

Este é o endpoint principal para `TestEvolutionConnection`:

```bash
curl -X GET https://{server-url}/instance/connectionState/meu-whatsapp-01 \
  -H "apikey: {GLOBAL_API_KEY}"
```

Resposta (HTTP 200):
```json
{
  "instance": {
    "instanceName": "meu-whatsapp-01",
    "state": "open"
  }
}
```

Implementação no `control_plane` (Rust com reqwest):
```rust
#[tracing::instrument(skip(config), fields(instance_name = %req.instance_name))]
pub async fn test_evolution_connection(
    config: &EvolutionConfig, // server_url + api_key (SecretString)
    req: TestConnectionRequest,
) -> Result<ConnectionResult, CoreError> {
    let client = reqwest::Client::new();
    let response = client
        .get(format!(
            "{}/instance/connectionState/{}",
            config.server_url, req.instance_name
        ))
        .header("apikey", config.api_key.expose_secret())
        .timeout(Duration::from_secs(10))
        .send()
        .await
        .map_err(|e| CoreError::external("evolution_api", e.to_string()))?;

    let ok = response.status().is_success();
    if ok {
        let body: serde_json::Value = response.json().await?;
        let state = body["instance"]["state"].as_str().unwrap_or("unknown");
        Ok(ConnectionResult { success: state == "open", state: state.to_string() })
    } else {
        Ok(ConnectionResult { success: false, state: "error".to_string() })
    }
}
```

#### Erros Comuns

| Erro | Causa | Solução |
|---|---|---|
| 404 Not Found | Instância não existe ou nome com espaços | Verificar nome exato |
| 401 Unauthorized | API key inválida | Verificar header `apikey` e se a key não foi revogada |
| QR code vazio | Instância recém-criada sincronizando | Aguardar e tentar novamente |

#### Breaking Changes Recentes

- **Repositório migrado:** URLs GitHub de `EvolutionAPI/` → `evolution-foundation/`
- `mentionsEveryOne: false` agora respeitado (antes sempre aplicava)
- Sem breaking changes nos endpoints de instância (`fetchInstances`, `connectionState`)

#### Limitações

- Sem rate limit documentado — verificar em produção
- QR code válido por ~15 minutos após `GET /instance/connect`
- Instâncias desconectam se sessão WhatsApp principal fechar

---

## Grupo C — Observabilidade & Auditoria (Transversal)

> Referência: `doc_dev/planejamento/05-observabilidade.md` e `doc_dev/modelagem_dados/08_diretrizes_seguranca.md` §4 e §4.2

### Pipeline de Auditoria (existente, reutilizar)

```
[handler admin no data_postgres/control_plane]
   └─ publicar_auditoria(bus, event, level, context{actor, tenant_alvo, diff})
        └─ STREAM_SEGURANCA (Redis)  ── assíncrono, best-effort ──┐
                                                                   ▼
                           [consumidor data_postgres] → INSERT audit_log (lote + PEL)
```

### Matriz de Eventos de Auditoria por RPC

| RPC Admin | event_type | level | Campos no context |
|---|---|---|---|
| `ListTenants` / `GetTenant` | sem evento (leitura) | — | — |
| `CreateTenant` | `tenant_created` | INFO | `tenant_id`, dados do novo tenant |
| `UpdateTenant` | `tenant_updated` | INFO | `tenant_id`, `before`/`after` diff |
| `SetTenantActive` | `tenant_activated` / `tenant_suspended` | INFO | lista `tenant_ids` |
| `BulkExtendSubscription` | `subscription_updated` | INFO | `tenant_ids`, `extension_days` |
| `GenerateAccessCode` | `access_code_generated` | INFO | `tenant_id` (NUNCA o código) |
| `UpsertCoreSetting` | `core_setting_upserted` | INFO | `key`, `encrypted` (nunca o valor) |
| `DeleteCoreSetting` | `core_setting_deleted` | INFO | `key` |
| `UpdateTenantConfig` | `tenant_config_updated` | INFO | `tenant_id`, diff mascarado |
| chave API alterada | `tenant_api_key_changed` | WARN | `tenant_id`, `provider` (nunca o valor) |
| `RegisterPayment` | `payment_registered` | INFO | `tenant_id`, `amount`, `period` |
| `InviteTenantUser` | `tenant_user_invited` | INFO | `tenant_id`, `email`, `role` |
| `RevokeTenantUser` | `tenant_user_revoked` | INFO | `tenant_id`, `email` |
| `SetFeatureFlag` | `feature_flag_set` | INFO | `flag`, `scope`, `before`/`after` |
| `TestEvolutionConnection` | `connection_tested` | INFO/WARN | `target`, `result` (ok/falha), sem credencial |
| `Export*Csv` | `data_exported` | WARN | `tipo`, `intervalo`, `linhas` |
| Acesso negado (não-superuser) | `auth_access_denied` | WARN | `method` |

### Política de Sanitização Obrigatória

Campos que **NUNCA** entram em logs, audit_log.context ou traces:
- Valores de API keys (groq, openai, google, evolution)
- Tokens JWT (acesso ou refresh)
- Senhas / hashes de senha
- PII bruta (números de WhatsApp completos, payloads de mensagens)

Mecanismos de proteção:
- `secrecy::SecretString` para chaves decriptadas em memória
- `••••••••` na leitura de campos cifrados no gRPC response
- `diff before/after` no audit_log: registra chave alterada (`provider`), nunca o valor
- `#[derive(Debug)]` nunca em structs com credenciais

---

## Notas Gerais

1. **Guarda de segurança crítica (Fase 0):** `exigir_superuser_do_metadata` deve ser implementado ANTES de expor qualquer endpoint admin na fachada gRPC-Web. Padrão: extrair Bearer do metadata gRPC → `jsonwebtoken::decode` → verificar blocklist Redis → verificar `claims.is_superuser == true`.

2. **`protoc_plugin` para Dart:** ao gerar stubs do `admin.proto`, garantir `dart pub global activate protoc_plugin` com versão ≥16.0.0 (breaking change gRPC Dart 5.x).

3. **Tenant alvo vs tenant do superuser:** superusuário tem `tenant_id = Uuid::nil()` no JWT. Operações por-tenant levam o UUID alvo no payload (campo `tenant_id` das requests), resolvido via `resolver_tenant_alvo`.

4. **Evolution API — repositório migrado:** URLs GitHub de `EvolutionAPI/` → `evolution-foundation/`. Endpoints de API REST não mudaram.

5. **Sem breaking changes em tonic-web (0.14.1) e prost (0.14.3)** versus versões anteriores — código existente (`AuthService`) não precisa de alteração.
