---
type: plan
name: Servidor de Releases Windows — Plano Completo (reestruturado)
planSlug: servidor-releases-windows
parent: .context/plans/servidor-releases-windows.md
auxiliar: .context/plans/servidor-releases-windows/info_aux_servidor-releases-windows.md
prevc_scale: LARGE
generated: 2026-10-03
status: draft-para-aprovacao
---

# Servidor de Releases Windows — Plano Completo (reestruturado)

> Servidor Rust (**Axum 0.8 + Tokio**) que hospeda o feed de atualização do app
> Windows (`smart-core-tenant`, Flutter), CI no GitHub Actions gerando instalador
> e pacotes, cliente com auto-update silencioso, botão de download na landing page
> e observabilidade integrada à stack LGTM. Roda na Hostinger KVM2 atual, num
> projeto compose **novo e isolado** (`smart-core-releases`).

Este documento substitui as seções técnicas do plano canônico
(`servidor-releases-windows.md`), que ainda descreve Actix + Squirrel.Windows +
NSIS. As divergências e o motivo de cada uma estão em **Correções Aplicadas**,
logo abaixo. O frontmatter `phases:` do canônico continua valendo para o
workflow PREVC; só os artefatos técnicos mudam.

---

## Correções Aplicadas

Cada item compara o plano base (e a doc auxiliar) com a documentação atual
(Context7, consultado em 2026-10-03) e com o que existe de fato no repositório.

### C1 — Actix-web → Axum 0.8

| Antes | Depois | Por quê |
|---|---|---|
| `actix-web` + `actix-files` + macros `#[get]` | `axum 0.8` + `tower-http 0.6` | O workspace já usa Axum 0.8 (`webhook_ingress`, `control_plane`) e `tower-http 0.6` / `tower 0.5` (`server/Cargo.toml`). Actix traria um segundo runtime de middleware, outro modelo de extratores e nenhuma reutilização. `architecture.md` define Axum para HTTP e Tonic para gRPC: o servidor de releases é HTTP puro, isolado, sem RPC aos `data_*` — logo Axum, não Tonic. |
| `BearerAuth` (actix-web-httpauth) | Extrator próprio `UploadAuth: FromRequestParts<AppState>` | No Axum 0.8, `FromRequestParts` é `async fn` nativa no trait — **sem `#[async_trait]`** (breaking change 0.7→0.8). |
| `HttpServer::new(...).bind()` | `tokio::net::TcpListener::bind` + `axum::serve(...).with_graceful_shutdown(...)` | Mesmo padrão de `webhook_ingress/src/main.rs`. |

### C2 — Correções na documentação auxiliar de libs

| Item da doc auxiliar | Situação real | Correção |
|---|---|---|
| "tower-http 0.5.x (latest)" | Workspace fixa `tower-http = 0.6`, `tower = 0.5` | Usar `tower-http = { workspace = true, features = [...] }`. O `doc_dev/libs/rust/tower-http.md` precisa ter a versão corrigida para 0.6 e `tower` para 0.5. |
| "Axum 0.8: `Extension` removido → use `State`" | **Falso.** `Extension` continua existindo em 0.8 (docs de `axum::extract` o listam). | Usar `State` é a recomendação (tipado em tempo de compilação), não uma obrigação. O mesmo erro está em `doc_dev/libs/rust/axum.md` §2 — corrigir lá. |
| "`axum::Server::bind` descontinuado em 0.8" | Foi **removido no 0.7** (hyper 1.0). | Irrelevante para código novo; só `axum::serve`. |
| Breaking changes de fato do 0.8 que a doc não cita | (1) rotas `{param}` / `{*resto}` — `:param` dá panic; (2) `FromRequestParts`/`FromRequest` sem `#[async_trait]`; (3) `Option<T>` como extrator exige `OptionalFromRequestParts` — antes engolia qualquer rejeição, agora rejeita se o valor existe e é inválido. | Aplicados nos exemplos abaixo. |
| `use tokio_util::io::AsyncReadExt` | Não existe. `AsyncReadExt`/`AsyncWriteExt` são de `tokio::io`. | `tokio-util` sai do plano: `ServeDir`/`ServeFile` já fazem streaming, e o upload usa `Field::chunk()` do Multipart. `Framed`/codecs e `compat` não têm uso aqui. |
| `CompressionLayer` "gzip + brotli para .nupkg" | `.nupkg`, `.zip` e `.exe` já são comprimidos. Recomprimir só gasta CPU (a VPS tem 2 vCPU) e quebra `Range`/retomada de download. | Compressão **só** no sub-router `/api` (JSON). Para o feed, `releases.win.json` ganha variantes `.gz`/`.br` geradas uma única vez na publicação e servidas por `ServeDir::precompressed_*()`. |
| `ServeDir::new(...).with_buf_chunk_size()` "com precompressed automático" | Precompressão **não** é automática: precisa de `.precompressed_gzip()` / `.precompressed_br()`. | Corrigido no exemplo E1.4. |
| `compress_when(\|headers\| ...)` recebendo headers da requisição | O predicado avalia a **resposta** (`Predicate::should_compress(&Response)`). | Usar `DefaultPredicate` + `NotForContentType` (exemplo E1.4). |
| `tracing::debug!("msg", channel = %x)` | Sintaxe inválida: campos vêm **antes** da mensagem. | `tracing::debug!(channel = %x, "msg")`. |
| `#[tracing::instrument(skip(payload, auth))]` | Instrumentar sem `skip_all` arrisca capturar argumento sensível com `Debug`. | Padrão do plano: `skip_all` + `fields(...)` explícitos. |
| `Multipart` usado sem nota | Exige a feature `multipart` do axum, e o limite padrão de corpo é **2 MB** — um `.nupkg` de 40 MB volta 413. | `features = ["multipart"]` + `DefaultBodyLimit::max(..)` só na rota de upload. |
| CORS para `https://app.smartcoreassistant.com.br` | Esse subdomínio **não existe** (ver `infra/build-windows.ps1`: a produção atende no ápice). O app desktop não passa por CORS (CORS é regra de navegador). | CORS libera só `GET` vindo de `https://smartcoreassistant.com.br` (a landing page em `docker/site`). |

### C3 — Squirrel.Windows → Velopack (sucessor direto)

O plano base assume `Squirrel.Windows` com `UpdateManager` em C#. Dois problemas:

1. **O cliente não é .NET.** É Flutter (`clients/apps/smart-core-tenant`, binário
   `smart_core_tenant.exe`). O `UpdateManager` do Squirrel é uma biblioteca .NET.
2. **Squirrel.Windows está sem manutenção ativa**; o fork Clowd.Squirrel virou o
   **Velopack**, que tem guia oficial de migração "From Squirrel" e SDKs para
   C#, **Rust**, C/C++ e JS — portanto utilizável por app não-.NET.

O que muda com o Velopack (docs: `/velopack/velopack.docs`):

| Aspecto | Squirrel.Windows (plano base) | Velopack (plano novo) |
|---|---|---|
| Empacotador | `Squirrel.exe --releasify` | `vpk pack --packId --packVersion --packDir --mainExe --channel` |
| Índice do feed | arquivo `RELEASES` | `releases.{channel}.json` (ex.: `releases.win.json`); ainda gera `RELEASES` legado no canal padrão |
| Saída do build | `.nupkg` full/delta + `Setup.exe` | `-full.nupkg`, `-delta.nupkg`, `Setup.exe`, `Portable.zip`, `releases.win.json`, `assets.win.json`, `RELEASES` |
| Hospedagem | pasta HTTP estática | pasta HTTP estática (`HttpSource`) — **o servidor só precisa servir arquivos** |
| Deltas | precisam do pacote anterior | idem: o CI baixa o feed atual antes do `vpk pack` |
| Assinatura | `--signWithParams` | `--signParams "/td sha256 /fd sha256 /f cert.pfx /tr <tsa>"` ou Azure Trusted Signing (`--azureTrustedSignFile`) |
| Hooks de instalação | `SquirrelAwareApp.HandleEvents` | `VelopackApp.Build().Run()` — **primeira coisa** do `main` |

**Integração no Flutter** (decisão a fechar na Fase P, spike de 2h):

- **Opção A (preferida):** pacote `velopack_flutter` do pub.dev (comunitário,
  embrulha o SDK Rust do Velopack via `flutter_rust_bridge`). Validar na Fase P:
  data da última versão, compatibilidade com o Flutter 3.x do CI, licença.
- **Opção B (fallback):** expor o crate `velopack` (Rust) por FFI próprio. O
  projeto já planeja `flutter_rust_bridge` para o `local_engine`, mas **não**
  misturar update com o `local_engine` — seria um crate FFI pequeno e dedicado.

### C4 — NSIS: requisitos e decisão

O plano base pede "instalador NSIS" **e** "pacote Squirrel". São instaladores
concorrentes:

- O `Setup.exe` do Velopack instala **por usuário** em `%LocalAppData%\<packId>`,
  sem UAC, e é isso que permite atualizar sem pedir administrador.
- Um NSIS que instale em `Program Files` exige elevação, e o updater passa a
  falhar ao gravar na pasta do app. Atualização silenciosa deixa de funcionar.

**Decisão proposta:** o instalador oficial é o `Setup.exe` gerado pelo `vpk`.
NSIS fica **fora** do escopo, salvo se houver requisito de negócio (ex.: pré-requisito
de runtime, EULA customizada, instalação corporativa por GPO). Se esse requisito
existir, o NSIS vira só um **invólucro** e precisa cumprir:

| Requisito NSIS | Motivo |
|---|---|
| `RequestExecutionLevel user` | Instalação por usuário, sem UAC — compatível com o updater |
| Não instalar arquivos do app; só extrair e executar `Setup.exe --silent` | Quem instala e registra o app no Velopack é o `Setup.exe` |
| Repassar código de saída do `Setup.exe` | O CI/suporte precisa saber se falhou |
| Assinado com o mesmo certificado Authenticode | SmartScreen avalia cada `.exe` baixado |
| `makensis` rodando em `windows-latest` (choco `nsis`) | Mesmo runner do build Flutter |

### C5 — Conflito de tag com o deploy de produção

O plano base dispara o release com `git tag v1.1.0`. Esse padrão (`v[0-9]+.[0-9]+.[0-9]+`)
**já dispara `.github/workflows/deploy-prod.yml`** — cada release do app desktop
faria um deploy de produção do backend. O release do Windows usa tag própria:
**`win-vX.Y.Z`** (não casa com o filtro do deploy-prod).

### C6 — Rollback não é "remover do releases.json"

O plano base diz que, ao remover a v1.2.0 do JSON, "clientes voltam para v1.1.0
em até 1h". Não voltam: o updater não faz downgrade por padrão. Quem já está na
v1.2.0 continua nela. Rollback correto:

- **Roll-forward (padrão):** publicar `v1.2.1` com o código da v1.1.0. Todos os
  clientes sobem para ela no próximo check.
- **Freio de emergência:** restaurar o `releases.win.json` anterior (snapshot
  guardado pelo servidor). Isso só impede **novos** downloads da versão ruim.

### C7 — Demais ajustes de infraestrutura

| Antes | Depois | Por quê |
|---|---|---|
| `ports: "8080:8080"` | `172.17.0.1:${RELEASES_HOST_PORT:-8086}:8080` | Porta 8080 do host é de outro projeto (comentário no Caddyfile). E o padrão da casa é publicar só na ponte do Docker, atrás do Caddy (igual `docker/site`). |
| `releases.smartcore` | `releases.smartcoreassistant.com.br` | Domínio real; precisa de DNS **antes** do deploy, senão o Let's Encrypt entra em laço (mesma nota do MCP no Caddyfile). |
| `version: '3.8'` no compose | Sem `version:`, com `name: smart-core-releases` | Campo obsoleto no Compose v2; projeto nomeado como os demais. |
| Volume nomeado **e** bind no mesmo destino | Só bind `/opt/smartcore/releases:/data/releases` | Os dois no mesmo caminho conflitam. |
| Build na VPS (`image: releases-server:latest`) | Imagem do GHCR montada pelo CI | Não compilar Rust na VPS (2 vCPU / 7,8 GB). |
| Rate limit "via tower middleware" | `tower_governor` por IP, IP vindo do `X-Forwarded-For` do Caddy | `tower::limit::RateLimitLayer` é global, não por IP, e o Caddy da borda é `caddy:2-alpine` sem plugin de rate limit. |
| Métricas `releases_downloads_total` etc. | `smartcore_releases_*` | Convenção `infra/METRICAS_PADRAO.md`; o collector usa `add_metric_suffixes: false`, então o nome nasce completo no código. |

---

## Visão Geral

```
 GitHub Actions (windows-latest)          Hostinger KVM2
 tag win-vX.Y.Z                           ┌──────────────────────────────────────────┐
 ├─ flutter build windows (prod)          │ Caddy (smart-core-v2-edge) :443          │
 ├─ vpk download http (feed atual)        │  releases.smartcoreassistant.com.br      │
 ├─ vpk pack (full+delta, assinado)       │        │ reverse_proxy 172.17.0.1:8086   │
 └─ POST /api/v1/uploads ─── HTTPS ──────►│ releases_server (Axum 0.8)               │
                                          │  GET  /api/v1/releases/latest  (JSON)    │
 Landing (docker/site)                    │  GET  /updates/win/*   (feed Velopack)   │
  botão "Baixar" ─────────────────────────►  GET  /download/latest  (302 → Setup)    │
                                          │  GET  /download/{version}/{filename}     │
 App Windows (Velopack)                   │  POST /api/v1/uploads  (Bearer, CI)      │
  check a cada 1h ────────────────────────►  GET  /health                            │
  baixa delta, aplica ao reiniciar        │  /data/releases ← /opt/smartcore/releases│
                                          │  OTLP → otel-collector → Prom/Tempo      │
                                          │  stdout JSON → promtail → Loki           │
                                          └──────────────────────────────────────────┘
```

**Layout em disco** (`/opt/smartcore/releases/` no host):

```
releases/
├── win/                         ← FEED do Velopack (servido em /updates/win/)
│   ├── releases.win.json        ← gravado por último, por rename atômico
│   ├── releases.win.json.gz/.br ← variantes pré-comprimidas (geradas na publicação)
│   ├── RELEASES                 ← legado (compat. Squirrel)
│   ├── SmartCore-1.1.0-full.nupkg
│   ├── SmartCore-1.2.0-delta.nupkg
│   └── SmartCore-1.2.0-full.nupkg
├── archive/
│   └── 1.2.0/                   ← Setup.exe / Portable.zip de cada versão (retém 10)
│       ├── SmartCore-win-Setup.exe
│       └── SmartCore-win-Portable.zip
├── snapshots/                   ← releases.win.json anteriores (freio de emergência)
└── .staging/{upload_id}/        ← upload em andamento; nunca servido
```

---

# Fase P — Planning (Arquitetura, design, aprovação)

**Objetivo:** fechar decisões e contratos antes de qualquer código.

### P.1 — Decisões a aprovar

| # | Decisão | Proposta |
|---|---|---|
| D1 | Framework | Axum 0.8 + tower-http 0.6 (C1) |
| D2 | Updater | Velopack; integração Flutter A ou B após spike (C3) |
| D3 | Instalador | `Setup.exe` do Velopack; NSIS só como invólucro se houver requisito (C4) |
| D4 | Tag de release | `win-vX.Y.Z` (C5) |
| D5 | Rollback | Roll-forward + freio de emergência por snapshot (C6) |
| D6 | Assinatura | Authenticode (cert OV/EV ou Azure Trusted Signing). **Sem cert, o SmartScreen bloqueia o `Setup.exe`** — pode entrar depois, mas o risco precisa ser aceito por escrito |
| D7 | Código | Novo app `server/apps/releases_server` no workspace, reutilizando a crate `observability`; sem dependência de `contracts`/`transport` de negócio nem de `data_*` |
| D8 | Rede | Container fora das redes `internal` da v2; alcança só o collector por rede dedicada `smart_core_v2_releases_telemetria` (mesmo padrão do `mcp_telemetria`) |

### P.2 — Contrato de API (v1)

| Método e rota | Auth | Resposta |
|---|---|---|
| `GET /api/v1/releases/latest?channel=win` | pública | `200 {version, channel, setup_url, setup_sha256, setup_size, published_at, notes_markdown}` · `404 NO_RELEASE` |
| `GET /updates/win/{arquivo}` | pública | arquivo do feed (com `Range`, `ETag`, `Last-Modified`) |
| `GET /download/latest?channel=win` | pública | `302 Location: /download/{version}/SmartCore-win-Setup.exe` |
| `GET /download/{version}/{filename}` | pública | arquivo de `archive/{version}/` · `404` |
| `POST /api/v1/uploads` | `Bearer` | multipart `version`, `channel`, N × `file` → `201 {upload_id, version, files:[{name, sha256, size}]}` |
| `POST /api/v1/channels/{channel}/rollback` | `Bearer` | restaura snapshot anterior → `200 {restored_version}` |
| `GET /health` | pública | `200 ok` (verifica leitura de `/data/releases`) |

Códigos de erro (`error_code`, iguais em log, métrica e corpo da resposta):
`AUTH_MISSING`, `AUTH_INVALID`, `RATE_LIMITED`, `INVALID_VERSION`,
`INVALID_FILENAME`, `PAYLOAD_TOO_LARGE`, `MANIFEST_INVALID`, `HASH_MISMATCH`,
`VERSION_EXISTS`, `PUBLISH_IO`, `NO_RELEASE`.

### P.3 — Spike obrigatório (antes da aprovação)

1. Rodar `vpk pack` uma vez sobre o build Windows atual e **guardar um
   `releases.win.json` real** como fixture de teste. O tipo `VelopackAsset` do
   E1.2 foi escrito pela documentação; o fixture é a prova.
2. Avaliar `velopack_flutter` (Opção A) ou estimar a Opção B.
3. Confirmar a versão de `tower_governor` compatível com axum 0.8 (Context7 / crates.io).

### P.4 — Artefatos

`arquitetura-releases.md`, `ci-cd-pipeline-design.md`, `client-integration-design.md`,
`frontend-mockup.md`, `security-checklist.md` (lista do frontmatter canônico).

### Observabilidade & Auditoria — Fase P

- **a) Logs/traces:** nada executa nesta fase. O *desenho* fica fixado aqui:
  `service.name = "releases_server"` (resource OTel, via `init_telemetry`),
  campos fixos em todo span HTTP — `service="releases"`, `env`, `request_id`,
  `trace_id` (injetado pela camada OTel), `client_ip`, `status`, `error_code`.
  Tabela de eventos por endpoint em E1.6.
- **b) Auditoria no banco:** **Sem evento de auditoria — servidor não modifica
  state crítico de tenant.** Não toca `TenantUser`, `Subscription`,
  `TenantConfig` nem o Postgres. O estado vive em `/opt/smartcore/releases/`
  (arquivos) e `releases.win.json` (metadados); a trilha de quem publicou o quê
  fica nos logs estruturados (Loki) + histórico de `snapshots/` + run do GitHub
  Actions. Se um dia for exigida auditoria persistente, criar
  `releases_audit_log` (timestamp UTC, token_fp, version, sha256, size, ip),
  fora de RLS de tenant.
- **c) Sanitização:** política aprovada aqui — token só como `SecretString`;
  log do token só `token_len` + `token_fp` (8 hex do SHA-256); hash de arquivo
  completo no manifesto e 8 hex no log; IP do cliente permitido (rate limit e
  investigação de abuso), sem User-Agent completo em métrica.

---

# Fase R — Review (Segurança, performance, compliance)

### R.1 — Checklist de segurança

- [ ] Comparação do token em tempo constante (`subtle::ConstantTimeEq`, já no workspace)
- [ ] Token ≥ 32 bytes aleatórios (`openssl rand -hex 32`), em `secrets.RELEASES_UPLOAD_TOKEN` (GitHub) e no env do container (arquivo `600` em `/opt/smartcore/releases-env/`)
- [ ] Validação de `filename`: regex `^[A-Za-z0-9._-]{1,128}$`, sem `..`, sem separador — impede path traversal no upload e no `/download`
- [ ] Validação de `version`: SemVer (`^\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$`)
- [ ] Upload grava em `.staging/` e só promove após validar manifesto e hashes
- [ ] `releases.win.json` escrito por `rename` atômico — cliente nunca lê feed pela metade
- [ ] Publicação serializada (`tokio::sync::Mutex`) — dois CIs não intercalam arquivos
- [ ] `DefaultBodyLimit` só na rota de upload (300 MB); demais rotas no padrão 2 MB
- [ ] Rate limit por IP: público 120 req/min; upload 10 req/min
- [ ] Container `read_only: true`, usuário `smartcore` (não-root), `cap_drop: [ALL]`, `no-new-privileges`
- [ ] Porta publicada só em `172.17.0.1`
- [ ] Binários assinados (D6); SHA-256 conferido pelo próprio Velopack no cliente
- [ ] Caddy: HSTS, `X-Content-Type-Options`, `-Server`, sem CSP de app (só arquivos)

### R.2 — Performance (estimativa)

| Item | Estimativa | Limite aceito |
|---|---|---|
| `GET /api/v1/releases/latest` | < 5 ms (JSON em memória, recarregado na publicação) | p95 < 50 ms |
| Download 40 MB | limitado pela banda da VPS; `sendfile` não se aplica, `ServeDir` lê em chunks de 64 KB | sem CPU > 20% por download |
| Memória do container | ~15–30 MB | `mem_limit: 128m` |
| Pico de checks | N clientes / 3600 s — 1.000 clientes ≈ 0,3 req/s | trivial |

### R.3 — Compliance

LGPD: o IP é dado pessoal. Base legal = legítimo interesse (segurança e
prevenção de abuso). Retenção = a do Loki (14 dias, commit `078bcbaf`). Sem
identificador de usuário no servidor.

### Observabilidade & Auditoria — Fase R

- **a) Logs/traces:** revisão confirma que nenhum `#[instrument]` deixa de usar
  `skip_all`, que `Authorization` não aparece em `make_span_with` (só método,
  path, request_id) e que `error_code` é preenchido em todo caminho de erro.
- **b) Auditoria no banco:** sem evento — revisão reafirma a justificativa da
  Fase P (nenhum estado de tenant). Registro da própria revisão:
  `security-review.md` + `approval-sign-off.md`.
- **c) Sanitização:** teste de revisão obrigatório — subir o servidor com
  `RUST_LOG=trace`, fazer upload com token válido e inválido, e `grep` do token
  no stdout deve retornar **zero** linhas.

---

# Fase E — Execution (Implementação)

Ordem: E1 servidor → E2 compose/borda → E3 observabilidade → E4 CI → E5 cliente
→ E6 landing page. E1–E3 podem ir para produção antes do cliente existir (o feed
fica vazio e `/latest` devolve 404).

## E1 — Servidor Rust (`server/apps/releases_server`)

### E1.1 — `Cargo.toml`

```toml
[package]
name    = "releases_server"
version = "0.1.0"
edition.workspace = true

[dependencies]
axum        = { version = "0.8", features = ["multipart"] }
tokio       = { workspace = true }
tower       = { workspace = true }
tower-http  = { workspace = true, features = [
    "fs", "trace", "cors", "compression-gzip", "compression-br",
    "request-id", "timeout", "util",
] }
tower_governor = "0.8"          # confirmar versão compatível com axum 0.8 (spike P.3)
serde       = { workspace = true }
serde_json  = { workspace = true }
tracing     = { workspace = true }
uuid        = { workspace = true }   # v7 já habilitada no workspace
secrecy     = { workspace = true }
subtle      = { workspace = true }
sha2        = { workspace = true }
chrono      = { workspace = true }
thiserror   = { workspace = true }
anyhow      = { workspace = true }
observability = { workspace = true } # init_telemetry, hook de panic, sinal de parada, OTel
```

Adicionar `"apps/releases_server"` em `[workspace] members` e o binário na
lista de `COPY --from=builder` do `docker/server/Dockerfile` (a imagem única
`smartcore-server` passa a carregá-lo; o compose escolhe o binário pelo `command`).

### E1.2 — Tipos (Serde)

```rust
use serde::{Deserialize, Serialize};

/// Entrada de `releases.win.json` gerado pelo `vpk`.
/// Conferir contra o fixture real do spike P.3 antes de fechar.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "PascalCase")]
pub struct VelopackAsset {
    pub package_id: String,
    pub version: String,
    #[serde(rename = "Type")]
    pub kind: String,                 // "Full" | "Delta"
    pub file_name: String,
    #[serde(rename = "SHA256")]
    pub sha256: String,
    pub size: u64,
    #[serde(default)]
    pub notes_markdown: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "PascalCase")]
pub struct VelopackFeed {
    pub assets: Vec<VelopackAsset>,
}

/// Resposta de GET /api/v1/releases/latest (consumida pela landing page).
#[derive(Debug, Clone, Serialize)]
pub struct ReleaseInfo {
    pub version: String,
    pub channel: String,
    pub setup_url: String,
    pub setup_sha256: String,
    pub setup_size: u64,
    pub published_at: chrono::DateTime<chrono::Utc>,
    pub notes_markdown: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct UploadResponse {
    pub upload_id: uuid::Uuid,
    pub version: String,
    pub files: Vec<StoredFile>,
}

#[derive(Debug, Serialize)]
pub struct StoredFile {
    pub name: String,
    pub sha256: String,
    pub size: u64,
}
```

### E1.3 — Estado, erros e extratores (Axum 0.8)

```rust
use std::{net::IpAddr, path::PathBuf, sync::Arc};
use axum::{
    extract::FromRequestParts,
    http::{header::AUTHORIZATION, request::Parts, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use secrecy::{ExposeSecret, SecretString};
use sha2::{Digest, Sha256};
use subtle::ConstantTimeEq;
use tokio::sync::{Mutex, RwLock};

#[derive(Clone)]
pub struct AppState {
    pub cfg: Arc<Config>,
    /// Token só existe em memória como SecretString: `Debug` imprime [REDACTED]
    /// e o conteúdo é zerado no Drop.
    pub upload_token: Arc<SecretString>,
    /// Cache do `latest`, recarregado a cada publicação (leitura sem I/O).
    pub latest: Arc<RwLock<Option<ReleaseInfo>>>,
    /// Serializa publicações: dois uploads nunca intercalam arquivos no feed.
    pub publish_lock: Arc<Mutex<()>>,
}

pub struct Config {
    pub env: String,              // "dev" | "production"
    pub data_dir: PathBuf,        // /data/releases
    pub public_base_url: String,  // https://releases.smartcoreassistant.com.br
    pub max_upload_bytes: usize,  // 300 MiB
    pub keep_versions: usize,     // 10
}

#[derive(Debug, thiserror::Error)]
pub enum ApiError {
    #[error("credencial ausente")]           AuthMissing,
    #[error("credencial inválida")]          AuthInvalid,
    #[error("versão inválida")]              InvalidVersion,
    #[error("nome de arquivo inválido")]     InvalidFilename,
    #[error("manifesto inválido: {0}")]      ManifestInvalid(String),
    #[error("hash divergente em {0}")]       HashMismatch(String),
    #[error("versão já publicada")]          VersionExists,
    #[error("sem release publicada")]        NoRelease,
    #[error("erro de multipart: {0}")]       Multipart(String),
    #[error("falha de E/S ao publicar")]     PublishIo(#[from] std::io::Error),
}

impl ApiError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::AuthMissing => "AUTH_MISSING",
            Self::AuthInvalid => "AUTH_INVALID",
            Self::InvalidVersion => "INVALID_VERSION",
            Self::InvalidFilename => "INVALID_FILENAME",
            Self::ManifestInvalid(_) => "MANIFEST_INVALID",
            Self::HashMismatch(_) => "HASH_MISMATCH",
            Self::VersionExists => "VERSION_EXISTS",
            Self::NoRelease => "NO_RELEASE",
            Self::Multipart(_) => "PAYLOAD_INVALID",
            Self::PublishIo(_) => "PUBLISH_IO",
        }
    }
    fn status(&self) -> StatusCode {
        match self {
            Self::AuthMissing | Self::AuthInvalid => StatusCode::UNAUTHORIZED,
            Self::NoRelease => StatusCode::NOT_FOUND,
            Self::VersionExists => StatusCode::CONFLICT,
            Self::PublishIo(_) => StatusCode::INTERNAL_SERVER_ERROR,
            _ => StatusCode::BAD_REQUEST,
        }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        // O span atual (aberto pelo TraceLayer / #[instrument]) recebe o código —
        // é o que liga log, trace e o corpo da resposta pelo mesmo valor.
        tracing::Span::current().record("error_code", self.code());
        let status = self.status();
        // Erro de E/S não vai para o cliente (caminho interno do servidor).
        let msg = if status.is_server_error() { "erro interno".to_string() } else { self.to_string() };
        (status, Json(serde_json::json!({ "error_code": self.code(), "message": msg }))).into_response()
    }
}

/// Impressão digital do token para log: 8 hex do SHA-256. Permite saber QUAL
/// token foi usado (rotação) sem expor nada reversível.
fn token_fp(raw: &str) -> String {
    format!("{:x}", Sha256::digest(raw.as_bytes()))[..8].to_string()
}

/// Extrator de autenticação do upload.
/// Axum 0.8: `async fn` nativa no trait — sem `#[async_trait]`.
pub struct UploadAuth {
    pub token_fp: String,
}

impl FromRequestParts<AppState> for UploadAuth {
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, state: &AppState) -> Result<Self, Self::Rejection> {
        let raw = parts
            .headers
            .get(AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.strip_prefix("Bearer "))
            .ok_or_else(|| {
                tracing::warn!(error_code = "AUTH_MISSING", "upload sem Bearer");
                ApiError::AuthMissing
            })?;

        let fp = token_fp(raw);
        // Tempo constante: o tempo de resposta não revela prefixo correto.
        let ok: bool = raw
            .as_bytes()
            .ct_eq(state.upload_token.expose_secret().as_bytes())
            .into();

        if !ok {
            tracing::warn!(error_code = "AUTH_INVALID", token_len = raw.len(), token_fp = %fp, "upload recusado");
            return Err(ApiError::AuthInvalid);
        }
        tracing::info!(token_len = raw.len(), token_fp = %fp, "upload autorizado");
        Ok(Self { token_fp: fp })
    }
}

/// IP real do cliente. A porta só existe em 172.17.0.1, então o único chamador
/// possível é o Caddy da borda — e ele preenche X-Forwarded-For.
pub struct ClientIp(pub Option<IpAddr>);

impl<S: Send + Sync> FromRequestParts<S> for ClientIp {
    type Rejection = std::convert::Infallible;

    async fn from_request_parts(parts: &mut Parts, _: &S) -> Result<Self, Self::Rejection> {
        let ip = parts
            .headers
            .get("x-forwarded-for")
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.split(',').next())
            .and_then(|v| v.trim().parse().ok());
        Ok(Self(ip))
    }
}
```

### E1.4 — Router com middleware (Axum 0.8 + tower-http 0.6)

```rust
use std::time::Duration;
use axum::{
    body::Body,
    extract::DefaultBodyLimit,
    http::{HeaderValue, Method, Request, Response},
    routing::{get, post},
    Router,
};
use tower::ServiceBuilder;
use tower_http::{
    compression::{
        predicate::{DefaultPredicate, NotForContentType, Predicate},
        CompressionLayer,
    },
    cors::CorsLayer,
    request_id::{MakeRequestUuid, PropagateRequestIdLayer, SetRequestIdLayer},
    services::ServeDir,
    timeout::TimeoutLayer,
    trace::TraceLayer,
};
use tracing::{field::Empty, Span};

pub fn router(state: AppState) -> Router {
    let cfg = state.cfg.clone();

    // --- API JSON: única parte comprimida em tempo de resposta -----------------
    let compression = CompressionLayer::new()
        .gzip(true)
        .br(true)
        // DefaultPredicate já ignora gRPC, imagens, SSE e corpos minúsculos;
        // binários nunca passam por aqui, mas o predicado documenta a intenção.
        .compress_when(DefaultPredicate::new().and(NotForContentType::const_new("application/octet-stream")));

    // CORS só para a landing page buscar a versão; o app desktop não usa CORS.
    let cors = CorsLayer::new()
        .allow_origin(HeaderValue::from_static("https://smartcoreassistant.com.br"))
        .allow_methods([Method::GET]);

    let api_publica = Router::new()
        .route("/releases/latest", get(handlers::latest))
        .layer(cors)
        .layer(compression);

    let api_ci = Router::new()
        .route(
            "/uploads",
            // Limite só aqui: o restante do servidor fica no padrão de 2 MB.
            post(handlers::upload).layer(DefaultBodyLimit::max(cfg.max_upload_bytes)),
        )
        .route("/channels/{channel}/rollback", post(handlers::rollback));

    // --- Feed do Velopack: arquivos estáticos ----------------------------------
    // Sem CompressionLayer (nupkg/zip/exe já são comprimidos). Só o índice JSON
    // tem variantes .gz/.br gravadas na publicação.
    let feed = ServeDir::new(cfg.data_dir.join("win"))
        .precompressed_gzip()
        .precompressed_br()
        .append_index_html_on_directories(false);

    Router::new()
        .nest("/api/v1", api_publica.merge(api_ci))
        .nest_service("/updates/win", feed)
        .route("/download/latest", get(handlers::download_latest))
        .route("/download/{version}/{filename}", get(handlers::download_versao))
        .route("/health", get(handlers::health))
        .layer(
            ServiceBuilder::new()
                // ordem: de cima para baixo = de fora para dentro
                .layer(SetRequestIdLayer::x_request_id(MakeRequestUuid))
                .layer(trace_layer(cfg.env.clone()))
                .layer(PropagateRequestIdLayer::x_request_id())
                // Timeout curto para tudo menos corpo: uploads grandes usam o
                // tempo do Caddy; aqui protege contra handler travado.
                .layer(TimeoutLayer::new(Duration::from_secs(600))),
        )
        .with_state(state)
}
```

> O rate limit (`tower_governor`, chave = IP do `X-Forwarded-For`) entra como
> mais uma camada no `ServiceBuilder`, com duas configurações: pública (120/min)
> e `api_ci` (10/min). Exemplo fechado após o spike P.3, para não fixar aqui uma
> API de versão ainda não confirmada.

### E1.5 — TraceLayer customizado

```rust
use tower_http::trace::{DefaultOnRequest, TraceLayer};
use tower_http::classify::ServerErrorsFailureClass;

fn trace_layer(env: String) -> TraceLayer<
    tower_http::classify::SharedClassifier<tower_http::classify::ServerErrorsAsFailures>,
    impl Fn(&Request<Body>) -> Span + Clone,
    DefaultOnRequest,
    impl Fn(&Response<Body>, Duration, &Span) + Clone,
    tower_http::trace::DefaultOnBodyChunk,
    impl Fn(Option<&axum::http::HeaderMap>, Duration, &Span) + Clone,
    impl Fn(ServerErrorsFailureClass, Duration, &Span) + Clone,
> {
    TraceLayer::new_for_http()
        .make_span_with(move |req: &Request<Body>| {
            let request_id = req
                .headers()
                .get("x-request-id")
                .and_then(|v| v.to_str().ok())
                .unwrap_or("-");
            let client_ip = req
                .headers()
                .get("x-forwarded-for")
                .and_then(|v| v.to_str().ok())
                .and_then(|v| v.split(',').next())
                .unwrap_or("-");
            // NUNCA incluir headers inteiros: Authorization passaria junto.
            tracing::info_span!(
                "http",
                service = "releases",
                env = %env,
                method = %req.method(),
                path = %req.uri().path(),
                request_id,
                client_ip,
                status = Empty,
                bytes = Empty,
                error_code = Empty,
            )
        })
        .on_response(|res: &Response<Body>, latency: Duration, span: &Span| {
            span.record("status", res.status().as_u16());
            if let Some(len) = res.headers().get("content-length").and_then(|v| v.to_str().ok()) {
                span.record("bytes", len);
            }
            // Cabeçalho pronto. Para download, o fim real é no on_eos.
            tracing::debug!(latency_ms = latency.as_millis() as u64, "resposta iniciada");
        })
        .on_eos(|_trailers: Option<&axum::http::HeaderMap>, dur: Duration, _span: &Span| {
            // Corpo inteiro enviado (download concluído). Cliente que aborta
            // não chega aqui — a diferença entre iniciados e concluídos é a
            // taxa de abandono (métrica em E3).
            tracing::info!(stream_ms = dur.as_millis() as u64, "corpo enviado");
        })
        .on_failure(|class: ServerErrorsFailureClass, latency: Duration, _span: &Span| {
            tracing::error!(error_code = "HTTP_5XX", failure = %class, latency_ms = latency.as_millis() as u64, "falha HTTP");
        })
}
```

> Se a assinatura do tipo de retorno ficar ilegível na implementação, montar o
> `TraceLayer` inline dentro de `router()` (é o que o tower-http recomenda); a
> função separada aqui é só para leitura do plano.

### E1.6 — Handlers com `State` e `Multipart`

```rust
use axum::{
    extract::{Multipart, Path, Query, Request, State},
    http::{header::LOCATION, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use tokio::io::AsyncWriteExt; // tokio::io, NÃO tokio_util
use tower::ServiceExt;        // oneshot
use tower_http::services::ServeFile;

#[derive(serde::Deserialize)]
pub struct CanalQuery {
    #[serde(default = "canal_padrao")]
    channel: String,
}
fn canal_padrao() -> String { "win".into() }

// ---------------------------------------------------------------- GET latest
#[tracing::instrument(name = "releases.latest", skip_all,
    fields(service = "releases", channel = %q.channel, version = Empty, error_code = Empty))]
pub async fn latest(
    State(state): State<AppState>,
    Query(q): Query<CanalQuery>,
) -> Result<Json<ReleaseInfo>, ApiError> {
    tracing::debug!("check de versão");
    let guard = state.latest.read().await;
    let info = guard.clone().ok_or(ApiError::NoRelease)?;
    Span::current().record("version", info.version.as_str());
    metrics::check(&q.channel, "ok");
    tracing::info!(version = %info.version, "versão encontrada");
    Ok(Json(info))
}

// ---------------------------------------------------------------- GET download
#[tracing::instrument(name = "releases.download", skip_all,
    fields(service = "releases", version = %version, filename = %filename, error_code = Empty))]
pub async fn download_versao(
    State(state): State<AppState>,
    Path((version, filename)): Path<(String, String)>, // rota 0.8: /{version}/{filename}
    req: Request,                                      // último extrator: consome o corpo
) -> Result<Response, ApiError> {
    validar_versao(&version)?;
    validar_nome(&filename)?;
    tracing::debug!("download iniciado");
    metrics::download_iniciado(&version, tipo_do_arquivo(&filename));

    let caminho = state.cfg.data_dir.join("archive").join(&version).join(&filename);
    // ServeFile trata Range, ETag e Last-Modified; erro é Infallible.
    let res = ServeFile::new(caminho).oneshot(req).await.unwrap_or_else(|e| match e {});
    if res.status() == StatusCode::NOT_FOUND {
        return Err(ApiError::NoRelease);
    }
    // O INFO de "concluído" sai no on_eos do TraceLayer, dentro deste span.
    Ok(res.map(axum::body::Body::new))
}

pub async fn download_latest(
    State(state): State<AppState>,
) -> Result<impl IntoResponse, ApiError> {
    let v = state.latest.read().await.as_ref().map(|i| i.version.clone()).ok_or(ApiError::NoRelease)?;
    Ok((StatusCode::FOUND, [(LOCATION, format!("/download/{v}/SmartCore-win-Setup.exe"))]))
}

// ---------------------------------------------------------------- POST upload
#[tracing::instrument(name = "releases.upload", skip_all, fields(
    service = "releases",
    upload_id = %uuid::Uuid::now_v7(),
    client_ip = ?ip,
    token_fp = %auth.token_fp,
    version = Empty, channel = Empty, files = Empty, total_bytes = Empty, error_code = Empty,
))]
pub async fn upload(
    State(state): State<AppState>,
    ClientIp(ip): ClientIp,
    auth: UploadAuth,          // rejeita antes de ler 1 byte do corpo
    mut multipart: Multipart,  // consome o corpo → último argumento
) -> Result<(StatusCode, Json<UploadResponse>), ApiError> {
    let inicio = std::time::Instant::now();
    let upload_id = uuid::Uuid::now_v7();
    let staging = state.cfg.data_dir.join(".staging").join(upload_id.to_string());
    tokio::fs::create_dir_all(&staging).await?;

    let resultado = async {
        let (mut version, mut channel, mut arquivos) = (None, None, Vec::<StoredFile>::new());

        while let Some(mut field) = multipart
            .next_field()
            .await
            .map_err(|e| ApiError::Multipart(e.body_text()))?
        {
            match field.name().unwrap_or_default() {
                "version" => version = Some(field.text().await.map_err(|e| ApiError::Multipart(e.body_text()))?),
                "channel" => channel = Some(field.text().await.map_err(|e| ApiError::Multipart(e.body_text()))?),
                "file" => {
                    let nome = field.file_name().ok_or(ApiError::InvalidFilename)?.to_owned();
                    validar_nome(&nome)?;
                    let mut out = tokio::fs::File::create(staging.join(&nome)).await?;
                    let mut hasher = Sha256::new();
                    let mut size = 0u64;
                    // Streaming: nada de carregar 40 MB em memória.
                    while let Some(chunk) = field.chunk().await.map_err(|e| ApiError::Multipart(e.body_text()))? {
                        hasher.update(&chunk);
                        size += chunk.len() as u64;
                        out.write_all(&chunk).await?;
                    }
                    out.sync_all().await?;
                    let sha256 = format!("{:x}", hasher.finalize());
                    tracing::debug!(filename = %nome, size_bytes = size, sha256_prefix = &sha256[..8], "arquivo recebido");
                    arquivos.push(StoredFile { name: nome, sha256, size });
                }
                outro => tracing::warn!(campo = outro, "campo multipart ignorado"),
            }
        }

        let version = version.ok_or(ApiError::InvalidVersion)?;
        let channel = channel.unwrap_or_else(canal_padrao);
        validar_versao(&version)?;
        Span::current().record("version", version.as_str());
        Span::current().record("channel", channel.as_str());

        // Valida releases.win.json contra os hashes calculados aqui, promove
        // para o feed e grava o índice por último (rename atômico).
        let _guard = state.publish_lock.lock().await;
        publicar::validar_e_promover(&state, &staging, &version, &channel, &arquivos).await?;
        Ok::<_, ApiError>((version, arquivos))
    }
    .await;

    // Staging sempre removido — sucesso ou falha.
    let _ = tokio::fs::remove_dir_all(&staging).await;

    match resultado {
        Ok((version, files)) => {
            let total: u64 = files.iter().map(|f| f.size).sum();
            Span::current().record("files", files.len());
            Span::current().record("total_bytes", total);
            metrics::upload(&version, "ok", inicio.elapsed());
            tracing::info!(version = %version, files = files.len(), total_bytes = total, "release publicada");
            Ok((StatusCode::CREATED, Json(UploadResponse { upload_id, version, files })))
        }
        Err(e) => {
            metrics::upload("-", e.code(), inicio.elapsed());
            tracing::error!(error_code = e.code(), erro = %e, "falha no upload");
            Err(e)
        }
    }
}
```

`publicar::validar_e_promover` (sem código aqui, comportamento fixado):

1. Exige `releases.win.json` entre os arquivos; desserializa em `VelopackFeed`
   (`MANIFEST_INVALID` se falhar).
2. Todo asset com `Version == version` precisa ter arquivo enviado com o mesmo
   `SHA256` e `Size` (`HASH_MISMATCH`).
3. Se a versão já está no feed atual → `VERSION_EXISTS` (publicação é imutável).
4. Copia o `releases.win.json` atual para `snapshots/{timestamp}-{versao_anterior}.json`.
5. Move `.nupkg` para `win/`, `Setup.exe`/`Portable.zip` para `archive/{version}/`.
6. Grava `releases.win.json.tmp` + `.gz` + `.br`, `fsync`, `rename` — o índice é o
   **último** arquivo a mudar; até esse instante o feed antigo segue íntegro.
7. Recarrega `state.latest`.
8. Retenção: mantém as `keep_versions` mais novas em `archive/` e os `.nupkg` que
   o índice novo ainda referencia; apaga o resto e loga cada remoção em INFO.

### E1.7 — `main.rs`

```rust
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let env = std::env::var("APP_ENV").unwrap_or_else(|_| "production".into());
    observability::init_telemetry("releases_server", &env).map_err(|e| anyhow::anyhow!(e.to_string()))?;
    observability::instalar_hook_de_panic("releases_server");

    // Token lido do ambiente e imediatamente embrulhado; a String original é
    // movida para dentro do SecretString (zerada no Drop).
    let token = std::env::var("RELEASES_UPLOAD_TOKEN")?;
    anyhow::ensure!(token.len() >= 32, "RELEASES_UPLOAD_TOKEN curto demais");
    let state = AppState::carregar(config_do_ambiente(&env)?, SecretString::from(token)).await?;

    let app = router(state);
    let listener = tokio::net::TcpListener::bind("0.0.0.0:8080").await?;
    tracing::info!(addr = "0.0.0.0:8080", "releases_server ouvindo");

    // Downloads em andamento terminam antes do container parar no deploy.
    axum::serve(listener, app.into_make_service_with_connect_info::<std::net::SocketAddr>())
        .with_graceful_shutdown(observability::aguardar_sinal_de_parada())
        .await?;

    observability::shutdown_telemetry();
    Ok(())
}
```

### Observabilidade & Auditoria — E1

**a) Logs/traces estruturados** (todos com `service="releases"`, `env`,
`request_id`, `trace_id` via camada OTel do `init_telemetry`):

| Endpoint | Span | Eventos e níveis | Campos |
|---|---|---|---|
| `GET /api/v1/releases/latest` | `releases.latest` | DEBUG "check de versão" → INFO "versão encontrada" · WARN `NO_RELEASE` (404) | `channel`, `version`, `client_ip`, `error_code` |
| `POST /api/v1/uploads` | `releases.upload` | WARN `AUTH_MISSING`/`AUTH_INVALID` → INFO "upload autorizado" → DEBUG "arquivo recebido" (por arquivo) → INFO "release publicada" ou ERROR "falha no upload" | `upload_id`, `token_len`, `token_fp`, `version`, `channel`, `files`, `total_bytes`, `sha256_prefix`, `client_ip`, `error_code` |
| `GET /download/{version}/{filename}` | `releases.download` | DEBUG "download iniciado" → INFO "corpo enviado" (`on_eos`) · WARN 404 | `version`, `filename`, `bytes`, `stream_ms`, `client_ip` |
| `GET /updates/win/*` | `http` (TraceLayer) | DEBUG "resposta iniciada" → INFO "corpo enviado" | `path`, `status`, `bytes` |
| `POST .../rollback` | `releases.rollback` | INFO "upload autorizado" → WARN "rollback aplicado" (`restored_version`, `from_version`) ou ERROR | idem upload |
| qualquer 5xx | `http` | ERROR `HTTP_5XX` (`on_failure`) | `failure`, `latency_ms` |
| retenção | `releases.retencao` | INFO por arquivo removido | `version`, `filename`, `size_bytes` |

**b) Auditoria no banco:** **Sem evento de auditoria — servidor não modifica
state crítico de tenant.** Não há `AuditLogger` nem RLS: o binário nem recebe
URL de banco. Dados persistidos: arquivos em `/opt/smartcore/releases/` e o
índice `releases.win.json`; o histórico de publicações fica em `snapshots/` e
nos eventos INFO "release publicada" / WARN "rollback aplicado" no Loki.

**c) Sanitização:**

| Dado | Tratamento |
|---|---|
| Bearer token | `SecretString` em `AppState` (`Arc`); comparação `ct_eq`; log só `token_len` + `token_fp` (8 hex SHA-256); `make_span_with` não lê headers além de `x-request-id`/`x-forwarded-for`; `#[instrument(skip_all)]` em todo handler |
| Hash de arquivo | completo no `releases.win.json` e na resposta do upload (é público — o cliente confere); 8 hex no log |
| IP do cliente | permitido em log (`client_ip`) e usado no rate limit; **nunca** como label de métrica (cardinalidade) |
| Erro de E/S | detalhe só no log; cliente recebe `erro interno` + `error_code` |
| Nome de arquivo | validado por regex antes de tocar disco ou log |

## E2 — Compose, borda e DNS

### E2.1 — `docker/releases/compose.yml`

```yaml
# Projeto compose PRÓPRIO, isolado como docker/site: atualizar ou derrubar a v2
# não pode tirar o feed de atualização do ar (e vice-versa).
name: smart-core-releases

networks:
  # Criada pela stack de observabilidade; só o collector e este serviço vivem
  # nela. O servidor de releases é exposto à internet e NÃO deve alcançar
  # postgres/redis/data_* — por isso não entra em `internal` nem `observability`.
  releases_telemetria:
    name: smart_core_v2_releases_telemetria
    external: true

services:
  releases_server:
    image: ${SERVER_IMAGE:-ghcr.io/pwlimaverde/smart-core-assistant-v2/smartcore-server:dev}
    command: ["releases_server"]
    restart: unless-stopped
    environment:
      APP_ENV: ${APP_ENV:-dev}
      RUST_LOG: ${RUST_LOG:-info,releases_server=debug}
      OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector:4317
      RELEASES_DATA_DIR: /data/releases
      RELEASES_PUBLIC_BASE_URL: https://releases.smartcoreassistant.com.br
      RELEASES_MAX_UPLOAD_BYTES: "314572800"
      RELEASES_KEEP_VERSIONS: "10"
    env_file:
      - /opt/smartcore/releases-env/releases.env   # RELEASES_UPLOAD_TOKEN (chmod 600)
    ports:
      - "${HOST_BRIDGE_IP:-172.17.0.1}:${RELEASES_HOST_PORT:-8086}:8080"
    volumes:
      - /opt/smartcore/releases:/data/releases
    networks: [releases_telemetria]
    read_only: true
    tmpfs: [/tmp]
    cap_drop: [ALL]
    security_opt: ["no-new-privileges:true"]
    mem_limit: 128m
    cpus: 0.5
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://localhost:8080/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    logging:
      driver: json-file
      options: { max-size: "10m", max-file: "3" }
```

Preparação no host (uma vez): `mkdir -p /opt/smartcore/releases/{win,archive,snapshots,.staging}`
e `chown` para o UID do usuário `smartcore` da imagem.

### E2.2 — Observabilidade: rede dedicada

Em `docker/observability/compose.yml`, declarar a rede
`smart_core_v2_releases_telemetria` e anexá-la ao `otel-collector`. Como muda a
definição do serviço, aplicar com
`docker compose up -d --force-recreate otel-collector` e **commitar** a mudança
(o próximo deploy do CI sobrescreveria uma edição manual).

### E2.3 — Caddyfile (`docker/edge/Caddyfile`)

```caddyfile
# ----- Servidor de releases do app Windows (feed Velopack + download) -----
# Sem `encode`: nupkg/zip/exe já são comprimidos; o JSON da API é comprimido
# pelo próprio servidor e o índice do feed tem variantes .gz/.br prontas.
releases.smartcoreassistant.com.br {
	header {
		Strict-Transport-Security "max-age=31536000; includeSubDomains"
		X-Content-Type-Options "nosniff"
		Referrer-Policy "strict-origin-when-cross-origin"
		-Server
	}

	reverse_proxy host.docker.internal:{$RELEASES_HOST_PORT:8086} {
		# Upload de ~300 MB vindo do runner do GitHub.
		transport http {
			read_timeout 600s
			write_timeout 600s
		}
	}
}
```

Ordem obrigatória: (1) registro DNS `A releases → 76.13.229.210` propagado;
(2) `docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile`;
(3) commit no repo (a imagem `smartcore-edge` é montada pelo CI com o Caddyfile
embutido). Config inválida derruba o domínio inteiro, inclusive a landing.

### Observabilidade & Auditoria — E2

- **a) Logs/traces:** stdout JSON do container é coletado pelo promtail via
  `docker_sd_configs` e chega ao Loki com `compose_project="smart-core-releases"`
  e `compose_service="releases_server"`. Traces e métricas via OTLP na rede
  dedicada. Caddy registra o acesso na própria borda (correlação por horário e
  `x-request-id`, que o servidor devolve no response).
- **b) Auditoria no banco:** sem evento — mudança de infraestrutura, sem estado
  de tenant. A trilha é o commit (compose, Caddyfile, rede) + o run do CI.
- **c) Sanitização:** token só no `env_file` `600` fora do repo; `docker inspect`
  mostra o valor — acesso ao host já é root. Nunca passar o token em
  `environment:` literal nem em `command:`.

## E3 — Métricas, dashboard e alertas

### E3.1 — Métricas (OTel 0.24, padrão `usage_metrics.rs`)

```rust
// releases_server/src/metrics.rs — instrumentos criados uma vez (OnceLock).
use opentelemetry::{global, metrics::{Counter, Histogram}, KeyValue};
use std::sync::OnceLock;

fn downloads() -> &'static Counter<u64> {
    static C: OnceLock<Counter<u64>> = OnceLock::new();
    C.get_or_init(|| global::meter("smartcore_releases")
        .u64_counter("smartcore_releases_download_total")
        .with_description("Downloads iniciados, por versão e tipo de arquivo")
        .init())
}

pub fn download_iniciado(version: &str, kind: &'static str) {
    // `version` tem cardinalidade baixa (retenção de 10); IP nunca vira label.
    downloads().add(1, &[KeyValue::new("version", version.to_owned()), KeyValue::new("kind", kind)]);
}
```

| Métrica | Tipo | Labels | Uso |
|---|---|---|---|
| `smartcore_releases_check_total` | counter | `channel`, `result` | volume de clientes ativos |
| `smartcore_releases_download_total` | counter | `version`, `kind` (`full`/`delta`/`setup`/`portable`/`index`) | adoção por versão |
| `smartcore_releases_download_completed_total` | counter | `kind` | abandono = iniciados − concluídos |
| `smartcore_releases_upload_total` | counter | `result` (`ok` ou `error_code`) | saúde do CI |
| `smartcore_releases_upload_duration_ms` | histogram | `result` | latência de publicação |
| `smartcore_releases_auth_failure_total` | counter | `error_code` | tentativa de abuso |
| `smartcore_releases_storage_bytes` | gauge | — | disco do feed |
| `smartcore_releases_latest_info` | gauge (=1) | `version` | versão vigente no dashboard |

### E3.2 — Dashboard e alertas (provisionados como código)

Dashboard JSON em `docker/observability/provisioning/dashboards/json/releases.json`:
versão vigente, checks/min, downloads por versão (empilhado), abandono, uploads
e duração, falhas de auth, disco.

Regras novas em `provisioning/alerting/rules.yml` (mesmo formato das existentes):

| Alerta | Condição | Severidade |
|---|---|---|
| Upload de release falhou | `increase(smartcore_releases_upload_total{result!="ok"}[15m]) > 0` | warning |
| Pico de falha de autenticação | `increase(smartcore_releases_auth_failure_total[10m]) > 20` | warning |
| Servidor de releases fora do ar | série `up`/health ausente por 5 min (usar o padrão "série some" da regra existente "Serviço fora do ar") | critical |
| Taxa de 5xx > 5% | logs Loki `{compose_service="releases_server"} \|= "HTTP_5XX"` sobre total | critical |
| Disco do host < 10% | reaproveitar a regra de disco existente, se houver; senão criar | critical |

### Observabilidade & Auditoria — E3

- **a) Logs/traces:** esta etapa é a própria observabilidade; o único evento
  novo é INFO "métricas OTLP inicializadas" do `init_metrics`.
- **b) Auditoria no banco:** sem evento — métricas são agregadas, sem tenant.
- **c) Sanitização:** nenhuma métrica carrega IP, token, `upload_id` ou hash.
  `version` é o único label de valor variável e é limitado pela retenção.

## E4 — CI/CD (`.github/workflows/release-windows.yml`)

```yaml
name: Release Windows

on:
  push:
    tags: ['win-v[0-9]+.[0-9]+.[0-9]+']   # NÃO usar v*: dispararia deploy-prod.yml
  workflow_dispatch:

permissions:
  contents: write   # anexar Setup.exe à GitHub Release (cópia de segurança)

concurrency:
  group: release-windows
  cancel-in-progress: false   # nunca interromper uma publicação no meio

jobs:
  release:
    runs-on: windows-latest
    env:
      FEED_URL: https://releases.smartcoreassistant.com.br/updates/win
    steps:
      - uses: actions/checkout@v5

      - name: Versão a partir da tag
        id: v
        shell: pwsh
        run: |
          $v = "${{ github.ref_name }}" -replace '^win-v', ''
          "version=$v" >> $env:GITHUB_OUTPUT

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with: { flutter-version: '3.x', channel: stable, cache: true }

      - name: Setup .NET (vpk)
        uses: actions/setup-dotnet@v4
        with: { dotnet-version: '8.0.x' }

      - name: Instala vpk
        run: dotnet tool update -g vpk

      # build-windows.ps1 já fixa os --dart-define de prod e confere no binário
      # que os endereços entraram. Precisa ganhar o parâmetro -BuildName para que
      # a versão do app (pubspec) seja a da tag.
      - name: Build Flutter (prod)
        shell: pwsh
        run: .\infra\build-windows.ps1 -Env prod -App tenant -BuildName ${{ steps.v.outputs.version }}

      # Sem os pacotes anteriores o vpk não gera delta — todo cliente baixaria o full.
      - name: Baixa feed atual (para delta)
        run: vpk download http --url $env:FEED_URL --outputDir releases
        continue-on-error: true   # primeiro release: feed vazio

      - name: Empacota (Velopack)
        shell: pwsh
        run: |
          vpk pack `
            --packId SmartCore `
            --packVersion ${{ steps.v.outputs.version }} `
            --packDir clients\apps\smart-core-tenant\build\windows\x64\runner\Release `
            --mainExe smart_core_tenant.exe `
            --channel win `
            --outputDir releases
          # Com certificado (D6), acrescentar:
          #   --signParams "/td sha256 /fd sha256 /f cert.pfx /p $env:CERT_PASS /tr http://timestamp.digicert.com"

      - name: Publica no servidor de releases
        shell: pwsh
        env:
          RELEASES_UPLOAD_TOKEN: ${{ secrets.RELEASES_UPLOAD_TOKEN }}
        run: |
          $v = "${{ steps.v.outputs.version }}"
          $args = @('-sS', '--fail-with-body', '-X', 'POST',
                    "https://releases.smartcoreassistant.com.br/api/v1/uploads",
                    '-H', "Authorization: Bearer $env:RELEASES_UPLOAD_TOKEN",
                    '-F', "version=$v", '-F', 'channel=win')
          # Só os artefatos DESTA versão + o índice novo.
          Get-ChildItem releases | Where-Object {
            $_.Name -like "*$v*" -or $_.Name -in @('releases.win.json','RELEASES','assets.win.json') -or $_.Name -like 'SmartCore-win-*'
          } | ForEach-Object { $args += @('-F', "file=@$($_.FullName)") }
          curl.exe @args

      - name: Smoke test
        shell: pwsh
        run: |
          $r = curl.exe -sS https://releases.smartcoreassistant.com.br/api/v1/releases/latest | ConvertFrom-Json
          if ($r.version -ne "${{ steps.v.outputs.version }}") { throw "latest=$($r.version)" }

      - uses: softprops/action-gh-release@v2
        with:
          files: releases/SmartCore-win-Setup.exe
```

Pré-requisitos no repositório: secret `RELEASES_UPLOAD_TOKEN`; (D6) secrets do
certificado; `build-windows.ps1` com `-BuildName`. O servidor (`releases_server`)
é construído pelo `deploy-dev.yml`/`deploy-prod.yml` existentes junto com a
imagem `smartcore-server` — **nenhum job novo de build Rust**.

### Observabilidade & Auditoria — E4

- **a) Logs/traces:** cada passo do workflow fica no log do Actions; o servidor
  registra o upload com o mesmo `version`. O smoke test falha o job se `latest`
  não refletir a versão. `x-request-id` da resposta do upload aparece no log do
  `curl` (com `-i` em caso de falha) e casa com o Loki.
- **b) Auditoria no banco:** sem evento — publicação de artefato, sem tenant.
  Trilha: run do Actions (quem fez a tag) + INFO "release publicada" + snapshot.
- **c) Sanitização:** token só em `secrets.*` (o Actions mascara no log); nunca
  em `run:` literal; `curl` sem `-v` (verbose imprimiria o header). Senha do
  certificado idem.

## E5 — Cliente Windows (Flutter + Velopack)

Comportamento exigido (independente da Opção A/B do spike):

1. **Primeira linha do `main`**: rodar os hooks do Velopack (equivalente a
   `VelopackApp.Build().Run()`). Em hooks de instalação/desinstalação o processo
   sai sem abrir a UI.
2. Após o app abrir (nunca bloqueando a primeira tela), checar
   `https://releases.smartcoreassistant.com.br/updates/win` — e repetir a cada 1 h
   com `Timer.periodic`.
3. Havendo versão: baixar em segundo plano (delta quando disponível; o Velopack
   cai no full sozinho se o delta falhar).
4. **Aplicar na próxima abertura**, sem reiniciar à força: no SDK Rust isso é
   `wait_exit_then_apply_updates` (o oposto de `apply_updates_and_restart`). Se
   houver atendimento aberto, nada de reinício.
5. Opcional: banner discreto "Atualização pronta — reiniciar agora".
6. Build `dev` aponta para outro canal (`win-dev`) ou não checa — nunca o feed de prod.

Referência do SDK Rust (doc Velopack, base da Opção B):

```rust
use velopack::*;

fn verificar_atualizacao() -> Result<(), velopack::Error> {
    let fonte = sources::HttpSource::new("https://releases.smartcoreassistant.com.br/updates/win");
    let um = UpdateManager::new(fonte, None, None)?;
    if let UpdateCheck::UpdateAvailable(info) = um.check_for_updates()? {
        um.download_updates(&info, None)?;
        // Aplica quando o usuário fechar o app — sem reinício forçado.
        um.wait_exit_then_apply_updates(&info, true, false, Vec::<String>::new())?;
    }
    Ok(())
}
```

> A assinatura exata de `wait_exit_then_apply_updates` e a API Dart do
> `velopack_flutter` são confirmadas no spike P.3; o comportamento (itens 1–6)
> é o que vale.

### Observabilidade & Auditoria — E5

- **a) Logs/traces:** o app registra no log local (o mesmo do app) INFO
  "atualização disponível" (`from`, `to`), INFO "download concluído", WARN em
  falha de check/download com `error_code`. Lado servidor: os checks aparecem
  como `GET /updates/win/releases.win.json` e os downloads como `kind=delta|full`.
  Sem telemetria nova do cliente para o servidor nesta fase.
- **b) Auditoria no banco:** sem evento — o updater não toca dados de tenant nem
  de usuário; atualização é por máquina, não por conta.
- **c) Sanitização:** o cliente não envia token, usuário ou tenant ao servidor
  de releases (requisição anônima); integridade garantida pelo SHA-256 do
  manifesto conferido pelo Velopack + assinatura Authenticode.

## E6 — Landing page (`docker/site/publico/index.html`)

O botão funciona **sem JavaScript** (link direto para o redirect); o JS só
enriquece com versão e tamanho.

```html
<a id="baixar-windows" class="btn-primary"
   href="https://releases.smartcoreassistant.com.br/download/latest?channel=win">
  Baixar para Windows <span id="versao-windows"></span>
</a>
<small id="detalhe-windows">Windows 10 ou superior</small>

<script>
  // Falha silenciosa: sem a versão, o link continua funcionando.
  fetch('https://releases.smartcoreassistant.com.br/api/v1/releases/latest?channel=win')
    .then(r => (r.ok ? r.json() : null))
    .then(info => {
      if (!info) return;
      document.getElementById('versao-windows').textContent = 'v' + info.version;
      const mb = (info.setup_size / 1048576).toFixed(0);
      document.getElementById('detalhe-windows').textContent = `Windows 10 ou superior · ${mb} MB`;
    })
    .catch(() => {});
</script>
```

Se a página tiver CSP, incluir `connect-src https://releases.smartcoreassistant.com.br`.

### Observabilidade & Auditoria — E6

- **a) Logs/traces:** cada visita gera um `GET /api/v1/releases/latest` (DEBUG →
  INFO no servidor) e cada clique um `GET /download/latest` (302) seguido do
  download (DEBUG → INFO `on_eos`). A métrica `download_total{kind="setup"}` é o
  funil de instalação.
- **b) Auditoria no banco:** sem evento — página estática, sem estado.
- **c) Sanitização:** nenhum dado do visitante é enviado além do que o navegador
  manda por padrão; CORS restrito a `GET` do ápice do domínio.

---

# Fase V — Validation (Testes, rollback, documentação)

### V.1 — Testes automatizados (CI, `cargo test -p releases_server`)

| Teste | Verifica |
|---|---|
| `upload_sem_token_401` / `upload_token_errado_401` | rejeição antes de ler o corpo; `error_code` correto |
| `upload_feliz_publica_e_latest_reflete` | fluxo completo com o **fixture real** do spike |
| `upload_hash_divergente_nao_altera_feed` | `releases.win.json` intacto após falha |
| `upload_versao_repetida_409` | imutabilidade |
| `nome_com_traversal_400` | `../`, `..\\`, `%2e%2e`, nomes com `/` |
| `upload_concorrente_serializa` | dois uploads simultâneos → feed consistente |
| `download_range_206` | `Range: bytes=0-99` devolve 206 |
| `json_comprimido_binario_nao` | `/api` com `content-encoding: br`; `.nupkg` sem |
| `logs_nao_contem_token` | captura do subscriber (`tracing-subscriber` em teste) não contém o token |
| `retencao_mantem_10` | publica 12 versões, restam 10 no `archive/` |

Testes usam `tower::ServiceExt::oneshot` sobre o `Router` (sem porta) e
diretório temporário — rodam no `ci.yml` existente (ubuntu-latest), nunca na VPS.

### V.2 — End-to-end (DEV)

1. Tag `win-v0.9.0` → app instalado numa VM Windows limpa via `Setup.exe` da landing.
2. Tag `win-v0.9.1` → em até 1 h o app baixa o **delta** (conferir `kind=delta`
   no dashboard) e aplica na reabertura.
3. Instalar sem certificado (se D6 adiado) e registrar o comportamento do SmartScreen.
4. Derrubar o container durante um download → cliente retoma/repete sem corromper.

### V.3 — Rollback testado

1. Publicar `win-v0.9.2` "ruim".
2. **Freio:** `POST /api/v1/channels/win/rollback` → `latest` volta a `0.9.1`;
   instalação nova recebe 0.9.1; a VM já em 0.9.2 **continua** em 0.9.2 (comportamento esperado).
3. **Roll-forward:** tag `win-v0.9.3` com o código da 0.9.1 → a VM sobe para 0.9.3.
4. Rollback do **servidor**: `SERVER_IMAGE` com a tag anterior + `docker compose up -d` —
   o volume de dados não muda.

### V.4 — Documentação

`test-report.md`, `validation-evidence.md` (prints do dashboard + trechos do Loki),
`rollback-verification.md`; correções nas libs: `doc_dev/libs/rust/axum.md`
(Extension não foi removido), `tower-http.md` (0.6 / tower 0.5) e `tokio-util.md`
(remover `tokio_util::io::AsyncReadExt`).

### Observabilidade & Auditoria — Fase V

- **a) Logs/traces:** a validação **prova** a tabela de E1: para cada endpoint,
  uma consulta Loki (`{compose_service="releases_server"} | json | span_name=...`)
  mostrando DEBUG → INFO, e um trace no Tempo do upload com o span
  `releases.upload` e `error_code` vazio (sucesso) / preenchido (falha).
- **b) Auditoria no banco:** sem evento — confirmado por inspeção: o binário não
  tem `DATABASE_URL` nem dependência de `sqlx`/`infrastructure_postgres`
  (`cargo tree -p releases_server | grep -c sqlx` = 0).
- **c) Sanitização:** teste `logs_nao_contem_token` + `grep` do token em 24 h de
  Loki do DEV = zero ocorrências; IPs presentes só em logs, ausentes em métricas.

---

# Fase C — Complete (Handoff, monitoramento, runbook)

### C.1 — Runbook (`infra/RUNBOOK_RELEASES_WINDOWS.md`)

**Publicar versão**
```bash
git tag win-v1.2.0 && git push origin win-v1.2.0
# Acompanhar: Actions → "Release Windows"; dashboard "Releases" → versão vigente.
```

**Freio de emergência** (bloqueia novos downloads da versão ruim)
```bash
curl -sS -X POST https://releases.smartcoreassistant.com.br/api/v1/channels/win/rollback \
  -H "Authorization: Bearer $(grep RELEASES_UPLOAD_TOKEN /opt/smartcore/releases-env/releases.env | cut -d= -f2)"
```
Em seguida, **roll-forward** obrigatório: nova tag com o código bom.

**Rotacionar o token**
1. Gerar `openssl rand -hex 32`; atualizar `secrets.RELEASES_UPLOAD_TOKEN` e o `releases.env`.
2. `docker compose -p smart-core-releases up -d --force-recreate releases_server`.
3. Conferir no Loki o novo `token_fp` no próximo upload.

**Disco cheio** — a retenção roda a cada publicação; manual:
`du -sh /opt/smartcore/releases/*`; nunca apagar arquivo que o
`releases.win.json` atual referencia.

**Container fora** — `docker compose -p smart-core-releases logs --tail 200 releases_server`;
o app instalado continua funcionando (só não atualiza); a landing mantém o link.

### C.2 — Monitoramento ativo

Dashboard "Releases" + 5 alertas de E3.2 roteados para o contact point existente.
Revisão na primeira semana: taxa de delta vs full, abandono de download, tempo
até 90% dos checks reportarem a versão nova.

### C.3 — Handoff

`handoff-summary.md`, `monitoring-dashboard.md`, `runbook.md`. Atualizar o
frontmatter do plano canônico (`summary` ainda cita Actix) e o README de planos.

### Observabilidade & Auditoria — Fase C

- **a) Logs/traces:** em operação, as consultas salvas no Grafana (Explore) para
  "uploads da semana", "falhas de auth" e "downloads por versão" fazem parte do
  handoff; nível padrão `info,releases_server=info` em produção (DEBUG só sob
  investigação, via `RUST_LOG` + recreate).
- **b) Auditoria no banco:** sem evento — reafirmado no handoff. Revisitar só se
  surgir requisito de auditoria persistente (tabela `releases_audit_log` da Fase P).
- **c) Sanitização:** a rotação de token do runbook é o controle contínuo; a
  retenção de 14 dias do Loki limita a vida do IP em log.

---

## Estimativas

| Fase | Esforço | Calendário |
|---|---|---|
| P (inclui spike) | 6 h | 1–2 dias |
| R | 2 h | 1 dia |
| E1 servidor + testes | 12 h | 2–3 dias |
| E2–E3 infra + observabilidade | 5 h | 1 dia |
| E4 CI | 4 h | 1 dia |
| E5 cliente | 6–10 h (A ou B) | 1–2 dias |
| E6 landing | 1 h | — |
| V | 8 h | 1–2 dias |
| C | 2 h | 1 dia |
| **Total** | **~46–50 h** | **2–3 semanas** |

## Dependências

| Item | Estado |
|---|---|
| Axum 0.8 / tower-http 0.6 / tokio / tracing / serde / uuid / secrecy / subtle / sha2 | ✅ no workspace |
| Crate `observability` (OTLP, hook de panic, shutdown) | ✅ |
| Stack LGTM + promtail com descoberta por compose | ✅ |
| Runner `windows-latest` + Flutter no CI | ✅ (já usado no deploy-dev) |
| DNS `releases.smartcoreassistant.com.br` | ❌ criar |
| `vpk` (Velopack CLI, via `dotnet tool`) | ❌ instalar no workflow |
| Integração Flutter ↔ Velopack | ❌ spike P.3 |
| Certificado Authenticode | ❌ decisão D6 |
| `tower_governor` (versão p/ axum 0.8) | ❌ confirmar |

## Referências

- Plano canônico: `.context/plans/servidor-releases-windows.md`
- Doc auxiliar: `.context/plans/servidor-releases-windows/info_aux_servidor-releases-windows.md`
- Libs: `doc_dev/libs/rust/{axum,tower-http,tokio,tracing,secrecy,serde,uuid,sha2}.md`
- Código de referência: `server/apps/webhook_ingress/src/main.rs` (Axum 0.8 + graceful shutdown),
  `server/crates/observability/src/usage_metrics.rs` (métricas OTel)
- Infra: `docker/site/compose.yml` (padrão de projeto isolado), `docker/edge/Caddyfile`,
  `infra/METRICAS_PADRAO.md`, `infra/PLANO_OBSERVABILIDADE.md`
- Docs externas (Context7): `/tokio-rs/axum`, `/websites/rs_tower-http`, `/velopack/velopack.docs`
