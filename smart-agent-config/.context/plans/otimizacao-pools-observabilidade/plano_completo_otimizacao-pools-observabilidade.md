# Plano Completo — Otimização de Pools, Concorrência e Observabilidade de Gargalos

> Reestruturado a partir de `smart-agent-config/doc_dev/planejamento/12-plano-otimizacao-pools-observabilidade.md`
> usando a doc auxiliar `info_aux_otimizacao-pools-observabilidade.md` **e validação direta
> do código-fonte vendorizado** das libs nas versões fixadas em `server/Cargo.lock`.
> Comentários de código em pt-br. Sem auto-referência ao modelo em exemplos de commit.

## Versões fixadas (verdade técnica — `server/Cargo.lock`)

| Lib | Versão | Observação para este plano |
|---|---|---|
| sqlx | **0.9.0** | `PgPoolOptions` com `max/min_connections`, `acquire_timeout`, `idle_timeout`, `max_lifetime`; `PgPool::size()/num_idle()` |
| redis | **0.25.5** | **Sem `ConnectionManagerConfig`**; timeouts via `new_with_backoff_and_timeouts`. **Sem `xautoclaim_options`**; usar `xpending_count` + `xclaim` |
| opentelemetry | **0.24.0** | Instrumentos finalizam em **`.init()`**; gauge instantâneo só via `ObservableGauge` (callback) |
| opentelemetry_sdk | **0.24.1** | `runtime::Tokio`; feature `metrics` a habilitar |
| opentelemetry-otlp | **0.17.0** | feature **`metrics`** existe (confirmado no `Cargo.toml` vendorizado); pipeline via `new_pipeline().metrics(rt)` |
| tracing-opentelemetry | **0.25.0** | sem mudança |
| argon2 | **0.5.3** | CPU-bound → `spawn_blocking` |
| tokio | **1.52.3** (req `1.38`) | `spawn_blocking`, `Semaphore::acquire_owned`, `time::interval` |
| tracing | **0.1.40** | `info!`/`warn!` com `target:` dedicado |

> **Importante:** o Context7 só indexa redis ≥1.0 e opentelemetry ≥0.27. A doc auxiliar
> já alertava para isso; a verificação no código vendorizado confirmou e **corrigiu dois
> pontos onde a própria doc auxiliar ainda assumia APIs inexistentes em 0.25.5** (ver
> seção final "Correções aplicadas").

---

## Arquitetura (invariantes que o plano NÃO pode violar)

- **Banco tem porta única:** todo acesso a Postgres passa por `data_postgres`/`infrastructure_postgres`. Apps/CLIs são clientes finos via RPC.
- **`observability` NÃO depende de `infrastructure_postgres`** no build de produção (a aresta só existe sob a feature `postgres-audit`, em dev/testes). **As métricas de pool (M1/M3) recebem o `&PgPool` por parâmetro**; o módulo novo em `observability` não importa `infrastructure_postgres`.
- **IA é gRPC** (fora do escopo deste plano).
- **Transport em Windows usa TCP** (`SMARTCORE_<SVC>_ENDPOINT=tcp://`); UDS só em Unix.
- **Cache × Bus separados:** Redis cache (6379, allkeys-lru) para tokens/cache; Redis bus (6380, noeviction) para Streams/eventos.

---

## Ciclo PREVC (camada de processo sobre as 4 fases de execução)

| Etapa PREVC | O que é | Agente | Entregável / gate |
|---|---|---|---|
| **P — Planning** | Este documento | Backend Specialist | Plano aprovado + `info_aux` |
| **R — Review** | Validar contrato e risco de concorrência; **bater os 3 pontos ⚠️ contra docs.rs/código vendorizado** (já feito aqui) | Backend Specialist + Performance Optimizer | Aprovação de design; checklist ⚠️ resolvido |
| **E — Execution** | Implementar as 4 sub-fases na ordem (1→4) | Backend Specialist (C*/P*), Performance Optimizer (apoio P3/M*), Devops Specialist (envs/systemd/M5) | PRs por sub-fase |
| **V — Validation** | Testes de carga/concorrência + DoD de cada sub-fase | Test Writer | DoD verde, benchmarks |
| **C — Confirmation** | `final-review` (gate obrigatório) + arquivamento | Backend Specialist | Plano canônico arquivado |

### Mapeamento Fase de execução → Agente → DoD (resumo)

| Fase | Itens | Agente principal | DoD (refinado) |
|---|---|---|---|
| **F1 Correções críticas** | C1, C2, C3, C4 | Backend Specialist | 20 logins concorrentes sem degradar `GetThread` (p95<100ms); publicação <10ms sob consumo; auditoria no 6380; evento com erro reentregue (PEL, sem ACK) |
| **F2 Controle de pools** | P1, P2, P3, P4 | Backend Specialist + Performance Optimizer | rajada de 200 req: 100% respondidas (sucesso ou erro retryable <4s), sem espera de 30s, sem OOM no PG |
| **F3 Monitoramento** | M1, M2, M3, M4, M5 | Backend Specialist + Performance Optimizer + Devops | saturação simulada (pool max=2 + carga) aponta gargalo no dashboard antes do erro chegar ao cliente |
| **F4 Eficiência** | E1, E2, E3 | Backend Specialist | benchmarks antes/depois no PR |

---

## Diagnóstico (achados por severidade — inalterado do plano-base, anotado com o estado real do código)

- **C1 (Crítica):** `hash_password`/`verify_password` (argon2) rodam no thread do runtime tokio em `apps/data_postgres/src/main.rs` (`handler_verify_credentials` linha ~876, `handler_create_superuser` linha ~493). Argon2 é CPU-bound: poucos logins simultâneos travam o executor.
- **C2 (Crítica):** `Consumer::run` (`transport/src/bus.rs:334`) clona o `ConnectionManager` multiplexado e roda `XREADGROUP ... BLOCK 1000` nele (`consumir_stream`, `block_ms=1000`). O BLOCK segura a conexão compartilhada; `publicar_evento_seguranca` espera atrás dele. Viola o doc-comment de `connection.rs`.
- **C3 (Alta):** App usa um único `REDIS_URL` (`main.rs:44`). O `data.yml` já tem `redis` (6379, allkeys-lru) e `redis-bus` (6380, noeviction). **Nuance:** o `.env.example` atual já aponta `REDIS_URL` para **6380** — ou seja, hoje tudo (cache + bus) cai no bus noeviction. Falta a chave `REDIS_BUS_URL` e direcionar cache→6379.
- **C4 (Alta):** `Consumer::run` chama `handler(...).await` e em seguida `confirmar_stream` (XACK) **incondicionalmente** (`bus.rs:361-365` e `387-393`). `processar_evento_auditoria` engole o erro internamente e o handler é `Fn(EventoBruto) -> Future<Output=()>`. Evento que falhou é ACKado e perdido.
- **C5 (Alta):** `criar_pool(5)` hardcoded (`main.rs:33`, `connection.rs:9`), sem `acquire_timeout`/`min_connections`/`idle_timeout`/`max_lifetime`. Default de acquire do SQLx = 30s de espera silenciosa.
- **P-adm (Média):** `transport::runtime::handle_connection` (`runtime.rs:484`) faz `tokio::spawn` por frame sem limite.
- **M-0 (Média):** Não há métricas — só traces OTLP + logs JSON (`observability/src/telemetry.rs`).
- **E1 (Baixa):** `revogar_familia` faz N `DEL`s em loop (`auth_tokens.rs:129-131`).
- **E2 (Baixa):** `drenar_outbox` faz `UPDATE ... WHERE id = $1` por linha após publicar (`outbox_relay.rs:123`).
- **E3 (Baixa):** Consolidação de auditoria: 1 transação por evento (`processar_evento_auditoria`).

---

# FASE 1 — Correções Críticas (C1, C2, C3, C4)

Agente: **Backend Specialist** · PREVC: E (execução) + V (validação por DoD)

## C1 — Argon2 fora do runtime async (`spawn_blocking`)

**Onde:** `infrastructure_postgres/src/auth/password.rs` (expor variantes async) + chamadas em `apps/data_postgres/src/main.rs`.

Argon2 é CPU-bound (centenas de ms). Rodar no executor async bloqueia todas as tasks daquele worker thread. Mover para `tokio::task::spawn_blocking`.

```rust
// infrastructure_postgres/src/auth/password.rs  (acrescentar — comentários em pt-br)

/// Variante assíncrona de [`hash_password`]: executa o cálculo CPU-bound do Argon2
/// em uma thread de bloqueio dedicada (`spawn_blocking`), liberando o executor async.
#[tracing::instrument(level = "debug", skip(plaintext), err)]
pub async fn hash_password_async(plaintext: String) -> Result<String, DbError> {
    // `move` transfere a senha para a thread de bloqueio; ela nunca é logada.
    tokio::task::spawn_blocking(move || hash_password(&plaintext))
        .await
        .map_err(|e| DbError::CryptoError(format!("falha ao agendar hash em spawn_blocking: {e}")))?
}

/// Variante assíncrona de [`verify_password`]: roda a verificação Argon2 (CPU-bound)
/// fora do executor async. Retorna `false` em qualquer falha de junção da task.
#[tracing::instrument(level = "debug", skip(plaintext, phc_hash))]
pub async fn verify_password_async(plaintext: String, phc_hash: String) -> bool {
    tokio::task::spawn_blocking(move || verify_password(&plaintext, &phc_hash))
        .await
        .unwrap_or(false)
}
```

Ajuste nos handlers (passar `String` ownership, pois `spawn_blocking` exige `'static`):

```rust
// handler_verify_credentials: troca a chamada síncrona
let login_sucesso = if let Some(user) = &user_opt {
    infrastructure_postgres::verify_password_async(
        password.to_string(),
        user.password_hash.clone(),
    )
    .await
} else {
    false
};

// handler_create_superuser: hash assíncrono
let hash = match infrastructure_postgres::hash_password_async(password.to_string()).await {
    Ok(h) => h,
    Err(err) => { /* mesmo tratamento de erro atual */ }
};
```

> Exportar em `infrastructure_postgres/src/lib.rs`: `pub use auth::password::{hash_password_async, verify_password_async};` (manter as síncronas para os testes existentes em `password.rs`).

**DoD C1:** 20 logins concorrentes (`VerifyCredentials`) não degradam um `GetThread` paralelo; p95 do `GetThread` < 100ms durante a rajada de logins.

---

## C2 — Conexão DEDICADA para o loop de consumo (BLOCK)

**Onde:** `transport/src/bus.rs` (`Consumer`) + `apps/data_postgres/src/main.rs` (construção do consumer).

**Verdade técnica (validada no código vendorizado de redis 0.25.5):**
- `redis::Client::get_async_connection(&self) -> RedisResult<redis::aio::Connection>` **existe** (`client.rs:80`). É uma conexão **single, não-multiplexada** — o `XREADGROUP BLOCK` nela não afeta mais ninguém.
- O `Consumer` passa a guardar `redis::Client` (não o `ConnectionManager` compartilhado) e abre a conexão dedicada dentro de `run`.

```rust
// transport/src/bus.rs  (Consumer reescrito — comentários em pt-br)
use redis::aio::Connection;   // conexão single, dedicada ao loop de consumo
use redis::Client;

pub struct Consumer {
    stream: String,
    grupo: String,
    consumidor: String,
    // ⚠️ Mudança C2: guardamos o Client, não o ConnectionManager multiplexado.
    client: Client,
}

impl Consumer {
    pub fn new(
        stream: impl Into<String>,
        grupo: impl Into<String>,
        consumidor: impl Into<String>,
        client: Client,
    ) -> Self {
        Self {
            stream: stream.into(),
            grupo: grupo.into(),
            consumidor: consumidor.into(),
            client,
        }
    }

    pub async fn run<F, Fut>(&self, handler: F) -> anyhow::Result<()>
    where
        F: Fn(EventoBruto) -> Fut + Send + Sync + 'static,
        // ⚠️ Mudança C4: o handler agora devolve Result; só Ok dá XACK.
        Fut: std::future::Future<Output = anyhow::Result<()>> + Send + 'static,
    {
        // Conexão DEDICADA single para o XREADGROUP BLOCK (não multiplexada).
        // `get_async_connection` existe em redis 0.25.5 (client.rs:80).
        let mut con: Connection = self.client.get_async_connection().await?;
        garantir_consumer_group_stream_con(&mut con, &self.stream, &self.grupo).await?;

        tracing::info!(
            grupo = %self.grupo, stream = %self.stream, consumidor = %self.consumidor,
            "Consumidor iniciado em conexão dedicada."
        );

        // 1. Reprocessa pendências da PEL na inicialização.
        // 2. Loop de consumo ativo com BLOCK; sleep curto entre tentativas em erro.
        // (corpo do loop em C4, com XACK condicional)
        consumir_loop(&mut con, &self.stream, &self.grupo, &self.consumidor, handler).await
    }
}
```

> **Nota de implementação:** as funções livres atuais (`consumir_stream`, `confirmar_stream`,
> `reprocessar_pendentes_stream`, `garantir_consumer_group_stream`) recebem `&mut ConnectionManager`.
> Para C2, criar variantes genéricas sobre `redis::aio::ConnectionLike` (ou `&mut Connection`),
> mantendo as antigas para os usos rápidos (publicação) que continuam no `ConnectionManager`.
> `AsyncCommands`/`query_async` funcionam igualmente sobre `Connection` e `ConnectionManager`.

No `main.rs`, o consumer passa a receber o **Client do bus** (ver C3), não o `ConnectionManager`:

```rust
// apps/data_postgres/src/main.rs
let bus_client = redis::Client::open(redis_bus_url.clone())?;
let audit_consumer = transport::bus::Consumer::new(
    transport::bus::STREAM_SEGURANCA,
    "data_postgres_audit_group",
    "data_postgres_audit_consumer",
    bus_client,                         // ⚠️ C2: Client (conexão dedicada interna)
);
```

**DoD C2:** sob consumo ativo do audit consumer, a latência de `publicar_evento_seguranca` (no `ConnectionManager` do bus) permanece < 10ms (o BLOCK não compete mais com a publicação).

---

## C3 — Separar `REDIS_BUS_URL` (bus noeviction) de `REDIS_URL` (cache)

**Onde:** `apps/data_postgres/src/main.rs`, `.env.example`, `.env` (dev/prod), unit systemd, doc `10-plano-cicd-devops.md`.

**Estado real:** `data.yml` já provê `redis` (6379, `allkeys-lru`) e `redis-bus` (6380, `noeviction`). O `.env.example` atual aponta `REDIS_URL` para **6380**. Corrigir para:
- `REDIS_URL` → **6379** (cache: `RefreshTokenStore`, `TokenBlocklist`, `CachePermissoes`).
- `REDIS_BUS_URL` → **6380** (bus: outbox relay, `publicar_evento*`, consumers de stream).
- **Fallback transitório:** se `REDIS_BUS_URL` ausente, usar `REDIS_URL` (não quebra deploys atuais).

```rust
// apps/data_postgres/src/main.rs  (seção 3, Redis)
let redis_url =
    std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
// Bus separado (noeviction). Fallback transitório para REDIS_URL.
let redis_bus_url = std::env::var("REDIS_BUS_URL").unwrap_or_else(|_| redis_url.clone());

// Cache: ConnectionManager multiplexado (comandos rápidos: tokens, cache, set RLS).
let cache_conn = infrastructure_redis::criar_conexao_com_url(&redis_url).await?;
// Bus: ConnectionManager multiplexado para PUBLICAÇÃO (xadd) — comandos rápidos.
let bus_conn = infrastructure_redis::criar_conexao_com_url(&redis_bus_url).await?;
// Bus consumo (BLOCK): Client → conexão dedicada (ver C2).
let bus_client = infrastructure_redis::criar_cliente(&redis_bus_url)?;
```

> O `AppState.redis_conn` usado nos handlers para **publicar** auditoria deve ser o `bus_conn`
> (eventos vão para o noeviction). O outbox relay também publica no `bus_conn`. Tokens/cache (quando
> introduzidos no `data_postgres` ou em outros apps) usam o `cache_conn`.

**`.env.example` (corrigir + acrescentar):**
```dotenv
# Cache (volátil, allkeys-lru) — tokens, blocklist, permissões
REDIS_URL=redis://:SENHA@localhost:6379/0
# Barramento de eventos (Streams, noeviction) — outbox, auditoria, eventos de domínio
REDIS_BUS_URL=redis://:SENHA@localhost:6380/0
```

**DoD C3:** `XADD` de auditoria aterrissa no Redis 6380 (`noeviction`); cache de tokens no 6379 (`allkeys-lru`). Verificável por `redis-cli -p 6380 XLEN security:stream` após um `login_failed`.

---

## C4 — XACK só em sucesso; reprocessamento periódico da PEL; (Fase 2) DLQ por contagem de entregas

**Onde:** `transport/src/bus.rs` (`Consumer::run`/loop) + `apps/data_postgres/src/main.rs` (handler devolve `Result`; task periódica de pendentes).

Hoje o `handler` é `Fn -> Future<Output=()>` e o XACK é incondicional. Mudar para `Output = anyhow::Result<()>`; XACK **apenas em `Ok`**. Em `Err`, o evento **fica na PEL** (sem ACK) e é reentregue por `reprocessar_pendentes_stream`, agora rodando periodicamente.

```rust
// transport/src/bus.rs  — núcleo do loop (sobre a conexão dedicada de C2)
async fn consumir_loop<F, Fut>(
    con: &mut redis::aio::Connection,
    stream: &str,
    grupo: &str,
    consumidor: &str,
    handler: F,
) -> anyhow::Result<()>
where
    F: Fn(EventoBruto) -> Fut + Send + Sync + 'static,
    Fut: std::future::Future<Output = anyhow::Result<()>> + Send + 'static,
{
    loop {
        let eventos = consumir_stream_con(con, stream, grupo, consumidor, 10, 1000).await?;
        for evento in eventos {
            match handler(evento.clone()).await {
                Ok(()) => {
                    // Sucesso: confirma (XACK) e tira da PEL.
                    let _ = confirmar_stream_con(con, stream, grupo, &evento.stream_id).await;
                }
                Err(e) => {
                    // Falha: NÃO confirma. Fica na PEL para reentrega posterior.
                    tracing::error!(
                        stream_id = %evento.stream_id, erro = ?e,
                        "handler falhou; evento mantido na PEL para reprocessamento"
                    );
                }
            }
        }
    }
}
```

Task periódica de reprocessamento (substitui o reprocessamento só-na-inicialização). Roda a cada 60s:

```rust
// apps/data_postgres/src/main.rs
let bus_client_retry = infrastructure_redis::criar_cliente(&redis_bus_url)?;
tokio::spawn(async move {
    let mut tick = tokio::time::interval(std::time::Duration::from_secs(60));
    loop {
        tick.tick().await;
        if let Err(e) = transport::bus::reprocessar_pendentes_uma_vez(
            &bus_client_retry,
            transport::bus::STREAM_SEGURANCA,
            "data_postgres_audit_group",
            "data_postgres_audit_consumer",
        ).await {
            tracing::warn!("Falha no reprocessamento periódico da PEL: {:?}", e);
        }
    }
});
```

**O handler de auditoria passa a propagar erro** (hoje engole):

```rust
// processar_evento_auditoria devolve anyhow::Result<()> e propaga falhas de consolidação
// com `?` em vez de `tracing::error!` + Ok. O wrapper passado ao Consumer apenas repassa:
let audit_handler = move |evt| {
    let pool = pool_clone.clone();
    async move { processar_evento_auditoria(pool, evt).await }  // Result propagado → C4
};
```

### C4 Fase 2 — DLQ por número de entregas (correção vs. info_aux)

A doc auxiliar sugeria `XAUTOCLAIM`/`xautoclaim_options`. **Esse helper NÃO existe em redis 0.25.5** (validado: só há `xclaim`/`xclaim_options` e `xpending*`). A 0.25.5 oferece algo **melhor** para o nosso caso: `xpending_count` retorna `StreamPendingCountReply { ids: Vec<StreamPendingId> }`, e cada `StreamPendingId` tem o campo **`times_delivered`** — exatamente o contador de tentativas que o plano precisa. Política:

```rust
// transport/src/bus.rs  — varredura de DLQ (Fase 2 do C4)
use redis::streams::{StreamPendingCountReply, StreamClaimOptions};
use redis::AsyncCommands;

const MAX_ENTREGAS: usize = 5;
const DLQ_STREAM: &str = "security:dlq";

/// Move para a DLQ os eventos da PEL entregues mais de `MAX_ENTREGAS` vezes e os confirma.
pub async fn varrer_dlq_pendentes(
    con: &mut redis::aio::Connection,
    stream: &str,
    grupo: &str,
    consumidor: &str,
) -> anyhow::Result<()> {
    // XPENDING <stream> <grupo> - + <count> : detalha cada pendente com times_delivered.
    let pend: StreamPendingCountReply =
        con.xpending_count(stream, grupo, "-", "+", 100).await?;
    for id in pend.ids {
        if id.times_delivered > MAX_ENTREGAS {
            // Reivindica para este consumidor antes de mover (XCLAIM idempotente).
            let opts = StreamClaimOptions::default();
            let _: redis::streams::StreamClaimReply =
                con.xclaim_options(stream, grupo, consumidor, 0, &[id.id.clone()], opts).await?;
            // Copia o evento para a DLQ e confirma o original (sai da PEL).
            // (Republicação simplificada: marca metadados de envenenamento.)
            let _: String = con
                .xadd(DLQ_STREAM, "*", &[("original_id", id.id.as_str()),
                                        ("times_delivered", &id.times_delivered.to_string())])
                .await?;
            let _: i64 = con.xack(stream, grupo, &[id.id.clone()]).await?;
            tracing::warn!(stream_id = %id.id, entregas = id.times_delivered, "evento movido para DLQ");
        }
    }
    Ok(())
}
// ⚠️ validar em docs.rs/redis/0.25.5 — assinatura exata de `xclaim_options`
//    (xclaim_options(key, group, consumer, min_idle_time, ids, options)) e do retorno.
```

**DoD C4:** evento cujo handler retorna `Err` **não é ACKado** e reaparece na próxima passada do reprocessador (PEL); após `MAX_ENTREGAS` tentativas, vai para `security:dlq` e o original é ACKado. Teste: handler que falha N vezes → 1 entrada em `security:dlq`, 0 na PEL.

---

# FASE 2 — Controle Fino dos Pools (P1, P2, P3, P4)

Agente: **Backend Specialist** + **Performance Optimizer** · PREVC: E + V

Quatro alavancas: (1) config externa por ambiente; (2) pool quente (`min_connections`); (3) fail-fast (`acquire_timeout` curto); (4) admission control (semáforo na borda).

## P1 — `PoolConfig` + `criar_pool_config`

**Onde:** `infrastructure_postgres/src/connection.rs`.

```rust
// infrastructure_postgres/src/connection.rs  (comentários em pt-br)
use std::time::Duration;
use sqlx::postgres::PgPoolOptions;

/// Parâmetros do pool, lidos do ambiente com prefixo (ex.: "SMARTCORE_PG").
#[derive(Debug, Clone)]
pub struct PoolConfig {
    pub max_connections: u32,
    pub min_connections: u32,
    pub acquire_timeout: Duration,
    pub idle_timeout: Duration,
    pub max_lifetime: Duration,
}

impl Default for PoolConfig {
    fn default() -> Self {
        Self {
            max_connections: 5,
            min_connections: 1,
            acquire_timeout: Duration::from_millis(3000), // fail-fast (vs. 30s default)
            idle_timeout: Duration::from_secs(300),
            max_lifetime: Duration::from_secs(1800),
        }
    }
}

impl PoolConfig {
    /// Lê a config do ambiente. Variáveis ausentes caem no default.
    pub fn from_env(prefix: &str) -> Self {
        let d = Self::default();
        let u32v = |suf: &str, def: u32| std::env::var(format!("{prefix}_{suf}"))
            .ok().and_then(|s| s.parse().ok()).unwrap_or(def);
        let ms = |suf: &str, def: Duration| std::env::var(format!("{prefix}_{suf}"))
            .ok().and_then(|s| s.parse().ok()).map(Duration::from_millis).unwrap_or(def);
        let s = |suf: &str, def: Duration| std::env::var(format!("{prefix}_{suf}"))
            .ok().and_then(|s| s.parse().ok()).map(Duration::from_secs).unwrap_or(def);
        Self {
            max_connections: u32v("POOL_MAX", d.max_connections),
            min_connections: u32v("POOL_MIN", d.min_connections),
            acquire_timeout: ms("ACQUIRE_TIMEOUT_MS", d.acquire_timeout),
            idle_timeout: s("IDLE_TIMEOUT_S", d.idle_timeout),
            max_lifetime: s("MAX_LIFETIME_S", d.max_lifetime),
        }
    }
}

/// Cria o pool com a config externa. Loga a config efetiva no boot.
#[tracing::instrument(fields(?cfg), err)]
pub async fn criar_pool_config(cfg: PoolConfig) -> Result<PgPool, DbError> {
    let url = std::env::var("DATABASE_URL")
        .map_err(|_| DbError::ConfigError("DATABASE_URL não configurada".into()))?;
    let pool = PgPoolOptions::new()
        .max_connections(cfg.max_connections)
        .min_connections(cfg.min_connections)        // pool quente
        .acquire_timeout(cfg.acquire_timeout)        // fail-fast
        .idle_timeout(cfg.idle_timeout)
        .max_lifetime(cfg.max_lifetime)
        .connect(&url)
        .await?;
    tracing::info!(
        max = cfg.max_connections, min = cfg.min_connections,
        acquire_ms = cfg.acquire_timeout.as_millis() as u64,
        "pool PostgreSQL criado com config efetiva"
    );
    Ok(pool)
}

/// Compatibilidade: a antiga `criar_pool(n)` passa a delegar para a versão configurável.
pub async fn criar_pool(max_connections: u32) -> Result<PgPool, DbError> {
    let mut cfg = PoolConfig::from_env("SMARTCORE_PG");
    cfg.max_connections = max_connections; // respeita o argumento explícito
    criar_pool_config(cfg).await
}
```

> Em `main.rs`, trocar `criar_pool(5)` por `criar_pool_config(PoolConfig::from_env("SMARTCORE_PG"))`.

## P2 — Sizing (1 KVM2, Postgres 512MB, prod+dev compartilhando)

| Pool | Ambiente | max | min | Notas |
|---|---|---|---|---|
| `data_postgres` (app) | **prod** | 12 | 4 | role de aplicação + RLS |
| `data_postgres` (app) | **dev** | 5 | 1 | |
| admin pool (migrations) | ambos | 2 | 0 | efêmero (`close()` após migrations) |
| reserva PG | — | ~5 | — | superuser/manutenção |

**Regra:** `Σ(max) + reserva ≤ max_connections` do Postgres. Com prod(12)+dev(5)+admin(2)+reserva(5)=24 ≤ `max_connections` (ajustar `max_connections` do PG para ≥ 25 se necessário no `10-plano-cicd-devops.md`).

## P3 — Admission control (semáforo na borda do `transport::Server`)

**Onde:** `transport/src/runtime.rs` (`Server`, `handle_connection`).

```rust
// transport/src/runtime.rs  (comentários em pt-br)
use std::sync::Arc;
use tokio::sync::Semaphore;

pub struct Server {
    endpoint: Endpoint,
    handlers: Arc<HashMap<String, Handler>>,
    codec_name: String,
    semaforo: Arc<Semaphore>,   // ⚠️ P3: limite global de requisições in-flight
}

impl Server {
    pub fn new(endpoint: Endpoint, codec_name: &str) -> Self {
        // SMARTCORE_<SVC>_MAX_INFLIGHT é resolvido em from_env; default 64.
        let max_inflight = std::env::var("SMARTCORE_DATA_POSTGRES_MAX_INFLIGHT")
            .ok().and_then(|s| s.parse().ok()).unwrap_or(64usize);
        Self {
            endpoint,
            handlers: Arc::new(HashMap::new()),
            codec_name: codec_name.to_string(),
            semaforo: Arc::new(Semaphore::new(max_inflight)),
        }
    }
}
```

No `handle_connection`, antes do `tokio::spawn` por frame, adquirir o permit (ownership move para a task; `acquire_owned` exige `Arc<Semaphore>`):

```rust
// dentro do loop, após decodificar que NÃO é PING:
let permit = match semaforo.clone().acquire_owned().await {
    Ok(p) => p,                       // mantém o permit vivo durante o handler
    Err(_) => break,                  // semáforo fechado → encerra a conexão
};
let write_tx_clone = write_tx.clone();
tokio::spawn(async move {
    let _permit = permit;             // drop ao fim libera a vaga
    // ... decodifica, despacha handler, responde (M2 instrumenta aqui) ...
});
```

> `max_inflight ≈ 4–6 × pool_max`. Para prod (pool_max=12) → 48–72; default 64 é coerente.
> O `handle_connection` precisa receber `semaforo: Arc<Semaphore>` (clonado do `Server::run`).

## P4 — Redis: timeouts via `new_with_backoff_and_timeouts` (correção vs. info_aux)

**Onde:** `infrastructure_redis/src/connection.rs`.

**Verdade técnica (validada no código vendorizado):** redis 0.25.5 **NÃO tem `ConnectionManagerConfig`** nem `set_response_timeout`/`set_connection_timeout`. O builder citado pela info_aux não existe nesta versão. O caminho correto é o construtor com timeouts:

```rust
pub async fn new_with_backoff_and_timeouts(
    client: Client,
    exponent_base: u64,
    factor: u64,
    number_of_retries: usize,
    response_timeout: std::time::Duration,
    connection_timeout: std::time::Duration,
) -> RedisResult<ConnectionManager>
```

```rust
// infrastructure_redis/src/connection.rs  (acrescentar — comentários em pt-br)
use std::time::Duration;

/// Cria um `ConnectionManager` com timeouts de resposta e conexão (P4).
/// Em redis 0.25.5 a configuração de timeout é feita por este construtor — NÃO existe
/// `ConnectionManagerConfig` (isso só aparece em redis ≥1.0, fora da versão fixada).
#[tracing::instrument(skip(url), err)]
pub async fn criar_conexao_com_timeouts(url: &str) -> Result<ConnectionManager, RedisError> {
    let response_ms = std::env::var("SMARTCORE_REDIS_RESPONSE_TIMEOUT_MS")
        .ok().and_then(|s| s.parse().ok()).unwrap_or(2000u64);
    let client = Client::open(url.to_string())?;
    // Parâmetros de backoff (base/factor/retries) iguais ao default da lib; o que muda
    // é a presença explícita dos timeouts de resposta e conexão.
    let manager = ConnectionManager::new_with_backoff_and_timeouts(
        client,
        2,    // exponent_base (ms) — backoff exponencial
        100,  // factor
        6,    // number_of_retries
        Duration::from_millis(response_ms),  // response_timeout
        Duration::from_millis(response_ms),  // connection_timeout
    )
    .await?;
    tracing::info!(response_ms, "ConnectionManager Redis criado com timeouts");
    Ok(manager)
}
// ⚠️ validar em docs.rs/redis/0.25.5 — ordem/semântica dos 6 parâmetros de
//    `new_with_backoff_and_timeouts` (confirmado no fonte vendorizado: client, exponent_base,
//    factor, number_of_retries, response_timeout, connection_timeout).
```

Papéis fixos (Redis não precisa de pool, é multiplexado): **manager cache** (compartilhado), **manager bus publicação** (compartilhado), **conexão dedicada por loop de consumo** (C2). Trocar `criar_conexao_com_url` por `criar_conexao_com_timeouts` nas conexões de longa vida do `main.rs`.

**DoD F2:** rajada de 200 requisições simultâneas no `data_postgres` responde 100% (sucesso ou erro retryable em < 4s); sem espera de 30s (acquire fail-fast); sem OOM no Postgres (admission control + sizing). Medir antes/depois.

---

# FASE 3 — Monitoramento de Gargalos (M1–M5)

Agente: **Backend Specialist** + **Performance Optimizer** + **Devops Specialist** · PREVC: E + V

## Pré-requisito — Setup de MeterProvider (API otlp 0.17 / opentelemetry 0.24)

**Onde:** `observability/src/telemetry.rs` (mesmo módulo do tracing, reaproveitando `otlp_endpoint` e `resource`) + `observability/Cargo.toml` (feature `metrics`).

**Cargo.toml do `observability` — habilitar feature `metrics` (correção obrigatória):**

```toml
# crates/observability/Cargo.toml
opentelemetry       = { version = "0.24", features = ["metrics"] }
opentelemetry_sdk   = { version = "0.24", features = ["rt-tokio", "metrics"] }
opentelemetry-otlp  = { version = "0.17", features = ["grpc-tonic", "trace", "metrics"] }
```
> Confirmado no `Cargo.toml` vendorizado de `opentelemetry-otlp-0.17.0`: a feature `metrics`
> existe e puxa `opentelemetry/metrics`, `opentelemetry_sdk/metrics`, `opentelemetry-proto/metrics`.

**Setup de métricas (espelha o pipeline de traces — NÃO usar `MetricExporter::builder`):**

```rust
// observability/src/telemetry.rs  (acrescentar — comentários em pt-br)
use opentelemetry_otlp::WithExportConfig;
use opentelemetry_sdk::runtime;
use std::time::Duration;

/// Inicializa o pipeline de MÉTRICAS via OTLP/gRPC, reaproveitando o mesmo endpoint e
/// resource do tracing. API da otlp 0.17: `new_pipeline().metrics(rt)...build()`.
pub fn init_metrics(
    otlp_endpoint: &str,
    resource: opentelemetry_sdk::Resource,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let meter_provider = opentelemetry_otlp::new_pipeline()
        .metrics(runtime::Tokio)
        .with_exporter(
            opentelemetry_otlp::new_exporter().tonic().with_endpoint(otlp_endpoint),
        )
        .with_resource(resource)
        .with_period(Duration::from_secs(10)) // intervalo de export
        .build()?;                            // -> SdkMeterProvider (0.17)
    opentelemetry::global::set_meter_provider(meter_provider);
    tracing::info!("Pipeline de métricas OTLP inicializado.");
    Ok(())
}
// ⚠️ validar em docs.rs/opentelemetry-otlp/0.17.0 — assinatura de `with_exporter` e o tipo
//    de retorno de `.build()` (confirmado no fonte: OtlpMetricPipeline::build -> SdkMeterProvider).
```

> Em `init_telemetry`, após montar `resource` e `otlp_endpoint`, chamar `init_metrics(&otlp_endpoint, resource.clone())`. **`resource` precisa ser clonável** — hoje é consumido por `with_trace_config`; extrair `resource.clone()` antes.

## M1 — Métricas de pool (gauge amostrado via `ObservableGauge` + `.init()`)

**Onde:** novo módulo `observability/src/pool_metrics.rs`. **Recebe `&PgPool` por parâmetro** (não importa `infrastructure_postgres` — preserva a invariante de arquitetura).

```rust
// observability/src/pool_metrics.rs  (comentários em pt-br)
use opentelemetry::{global, KeyValue};
use sqlx::PgPool;
use std::time::Duration;

/// Registra gauges observáveis (callback) do pool e dispara a amostragem periódica.
/// Em opentelemetry 0.24 o gauge instantâneo SÓ existe como ObservableGauge (callback);
/// o builder finaliza em `.init()` (NÃO `.build()`, que é 0.27+).
pub fn monitorar_pool(pool: PgPool, intervalo: Duration) {
    let meter = global::meter("data_postgres");

    let pool_size = pool.clone();
    let _g_size = meter
        .u64_observable_gauge("smartcore_pg_pool_size")
        .with_description("Conexões abertas no pool PG (idle + em uso)")
        .with_callback(move |obs| {
            obs.observe(pool_size.size() as u64, &[KeyValue::new("pool", "postgres")]);
        })
        .init();

    let pool_idle = pool.clone();
    let _g_idle = meter
        .u64_observable_gauge("smartcore_pg_pool_idle")
        .with_description("Conexões ociosas agora")
        .with_callback(move |obs| {
            obs.observe(pool_idle.num_idle() as u64, &[KeyValue::new("pool", "postgres")]);
        })
        .init();

    let pool_use = pool.clone();
    let _g_use = meter
        .u64_observable_gauge("smartcore_pg_pool_in_use")
        .with_description("Conexões em uso (size - idle)")
        .with_callback(move |obs| {
            let em_uso = pool_use.size().saturating_sub(pool_use.num_idle() as u32);
            obs.observe(em_uso as u64, &[KeyValue::new("pool", "postgres")]);
        })
        .init();

    // Os ObservableGauge são coletados pelo PeriodicReader no intervalo do MeterProvider
    // (with_period). O `intervalo` aqui serve para um log de saúde complementar, se desejado.
    tokio::spawn(async move {
        let mut tick = tokio::time::interval(intervalo);
        loop {
            tick.tick().await;
            tracing::debug!(target: "metrics::pool",
                size = _g_size_keep(), "amostra de pool"); // ver nota abaixo
        }
    });
}
```
> **Nota:** os `_g_*` precisam viver enquanto o processo roda — guardá-los num `OnceCell`
> estático ou movê-los para a task de amostragem (evitar que sejam dropados). O `with_callback`
> já garante a coleta no período do reader; a task é só para o log `target: "metrics::pool"`.

## M2 — RED por método no `transport::Server` (histogram + counter, `.init()`)

**Onde:** `transport/src/runtime.rs`, no dispatch único do handler (dentro do `tokio::spawn` de P3).

```rust
// transport/src/runtime.rs  — instrumentação RED no dispatch (comentários em pt-br)
use opentelemetry::{global, KeyValue};
use std::time::Instant;

// (instâncias criadas uma vez e reaproveitadas; ex.: lazy estático)
let meter = global::meter("transport");
let h_dur = meter.f64_histogram("smartcore_rpc_duration_ms").with_unit("ms").init();
let c_total = meter.u64_counter("smartcore_rpc_total").init();

// no dispatch:
let inicio = Instant::now();
let response_env = /* ... handler(env).await ou METHOD_NOT_FOUND ... */;
let dur_ms = inicio.elapsed().as_secs_f64() * 1000.0;
let erro = response_env.kind == contracts::MessageKind::Error as i32;
let attrs = [KeyValue::new("method", method.clone()),
             KeyValue::new("error", erro.to_string())];
h_dur.record(dur_ms, &attrs);
c_total.add(1, &attrs);

// SLOW LOG: liga log→trace no Tempo via traceparent.
let limiar = std::env::var("SMARTCORE_SLOW_REQUEST_MS").ok()
    .and_then(|s| s.parse().ok()).unwrap_or(500.0_f64);
if dur_ms > limiar {
    tracing::warn!(target: "slowlog",
        method = %method, dur_ms,
        tenant_id = %response_env.tenant_id,
        traceparent = %response_env.traceparent,
        "requisição lenta");
}
```

## M3 — Medição do acquire dentro de `run_in_tenant_transaction` (histogram)

**Onde:** `infrastructure_postgres/src/connection.rs`. **Restrição de arquitetura:** `infrastructure_postgres` **não** deve depender de `observability` (evitar aresta nova e ciclo). Solução: emitir a métrica via API global do `opentelemetry` (que `infrastructure_postgres` já pode usar como dependência leve **de métricas**, sem puxar `observability`), ou via `tracing` (`target: "metrics::pg_acquire"`) consumido por um exporter. **Preferir a 2ª** (zero deps novas):

```rust
// infrastructure_postgres/src/connection.rs  — dentro de run_in_tenant_transaction
let inicio = std::time::Instant::now();
let mut tx = pool.begin().await?;                 // a espera do acquire mora aqui
let acquire_ms = inicio.elapsed().as_secs_f64() * 1000.0;
if acquire_ms > 100.0 {
    tracing::warn!(target: "metrics::pg_acquire", acquire_ms, "acquire de pool lento");
}
tracing::trace!(target: "metrics::pg_acquire", acquire_ms, "acquire de pool");
```
> O histograma `smartcore_pg_acquire_ms` é então alimentado por um bridge tracing→OTel
> métricas **na camada `observability`/app** (que pode depender de ambos), OU registrado
> diretamente se optarmos por adicionar `opentelemetry` (só a API de métricas) como dep
> de `infrastructure_postgres`. Decisão fica para a fase R. O log com `target` dedicado é o
> mínimo garantido sem violar a arquitetura.

## M4 — Lag das filas (bus pending + outbox backlog)

**Onde:** task periódica no `apps/data_postgres/src/main.rs` (30s).

**bus pending** — usar o tipo idiomático da 0.25.5 (correção vs. info_aux, que assumia tupla crua):

```rust
// XPENDING <stream> <grupo> (forma resumo) → StreamPendingReply (enum tipado da 0.25.5).
use redis::streams::StreamPendingReply;
use redis::AsyncCommands;

let pend: StreamPendingReply = bus_conn.xpending(STREAM_SEGURANCA, "data_postgres_audit_group").await?;
let total = pend.count();   // método do enum; 0 quando Empty
let meter = opentelemetry::global::meter("data_postgres");
let g_pending = meter.u64_observable_gauge("smartcore_bus_pending").init();
// (preferir ObservableGauge com callback que faz o XPENDING; aqui ilustrativo)
```
> Como `XPENDING` é assíncrono e o `ObservableGauge` usa callback síncrono, a forma robusta é
> uma **task `interval(30s)`** que faz o `xpending`/`SELECT` e grava num `Gauge` observável que
> apenas lê o último valor amostrado (via `AtomicU64` compartilhado). Padrão "amostra → atômico
> → observe".

**outbox backlog:**
```rust
// a cada 30s
let backlog: (i64,) = sqlx::query_as(
    "SELECT count(*) FROM outbox WHERE published_at IS NULL"
).fetch_one(&pool).await?;
// grava em AtomicU64 lido pelo ObservableGauge smartcore_outbox_backlog
```

## M5 — Dashboard Grafana + alertas (infra/provisioning)

**Onde:** provisioning da stack LGTM (PromQL/Grafana). Sem código Rust — o app só exporta via OTLP→Collector→Prometheus.

Dashboard "Saúde de Dados" + alertas:
- `em_uso/max > 0.85` por 5min
- `smartcore_pg_acquire_ms` p95 > 250ms
- `smartcore_outbox_backlog > 500`
- `smartcore_bus_pending > 1000`
- taxa de erro RPC (`smartcore_rpc_total{error="true"}` / total) > 5%

**DoD F3:** saturação simulada (pool max=2 + carga) faz o dashboard apontar o gargalo (`pg_pool_in_use ≈ max`, `pg_acquire_ms` subindo) **antes** de o erro de acquire-timeout chegar ao cliente.

---

# FASE 4 — Eficiência Adicional (E1, E2, E3)

Agente: **Backend Specialist** · PREVC: E + V

## E1 — `revogar_familia` com `DEL` variádico

**Onde:** `infrastructure_redis/src/auth_tokens.rs:126`.

```rust
// revogar_familia — 1 round-trip em vez de N DELs (comentários em pt-br)
pub async fn revogar_familia(&mut self, family_id: &str) -> Result<(), RedisError> {
    let chave_fam = keys::chave_refresh_familia(family_id);
    let membros: Vec<String> = self.con.smembers(&chave_fam).await?;
    if !membros.is_empty() {
        // Constrói o vetor de chaves e deleta tudo num único DEL variádico.
        let chaves: Vec<String> = membros.iter().map(|h| keys::chave_refresh(h)).collect();
        let _: i64 = self.con.del(&chaves).await?;   // DEL k1 k2 k3 ...
    }
    let _: i64 = self.con.del(&chave_fam).await?;
    tracing::info!(tokens_revogados = membros.len(), "família de refresh tokens revogada");
    Ok(())
}
```

## E2 — Outbox relay marca publicados em lote

**Onde:** `apps/data_postgres/src/outbox_relay.rs:89-137`. Acumular IDs publicados e fazer 1 `UPDATE ... WHERE id = ANY($1)`. Trade-off at-least-once (o `event_id`=`row.id` já garante idempotência no consumo).

```rust
let mut publicados: Vec<Uuid> = Vec::with_capacity(rows.len());
for row in rows {
    // ... monta envelope ...
    match transport::bus::publicar_evento(&mut conn, &envelope).await {
        Ok(_) => publicados.push(row.id),
        Err(e) => { tracing::error!("falha ao publicar {} : {:?}", row.id, e); break; }
    }
}
if !publicados.is_empty() {
    sqlx::query("UPDATE outbox SET published_at = NOW() WHERE id = ANY($1)")
        .bind(&publicados)
        .execute(&self.pool)
        .await?;
}
```

## E3 — Consolidação de auditoria em lote

**Onde:** `apps/data_postgres/src/main.rs` (`processar_evento_auditoria`) + loop do consumer. Após C4, agrupar os eventos do **mesmo tenant** lidos numa iteração `count(10)` e fazer 1 `run_in_tenant_transaction` com multi-insert (reduz N transações para ~1 por tenant por iteração). Eventos globais (sem tenant) num insert único separado.

**DoD F4:** benchmarks antes/depois no PR (E1: round-trips Redis; E2: nº de `UPDATE`s por drenagem; E3: nº de transações por iteração).

---

## Variáveis de ambiente novas

| Variável | Default | Onde | Observação |
|---|---|---|---|
| `SMARTCORE_PG_POOL_MAX` | dev 5 / prod 12 | `PoolConfig::from_env` | sizing P2 |
| `SMARTCORE_PG_POOL_MIN` | dev 1 / prod 4 | idem | pool quente |
| `SMARTCORE_PG_ACQUIRE_TIMEOUT_MS` | 3000 | idem | fail-fast |
| `SMARTCORE_PG_IDLE_TIMEOUT_S` | 300 | idem | |
| `SMARTCORE_PG_MAX_LIFETIME_S` | 1800 | idem | |
| `REDIS_URL` | 6379 (cache) | `main.rs` | **corrigir** o `.env.example` (hoje aponta 6380) |
| `REDIS_BUS_URL` | fallback `REDIS_URL` | `main.rs` | bus noeviction 6380 |
| `SMARTCORE_REDIS_RESPONSE_TIMEOUT_MS` | 2000 | `criar_conexao_com_timeouts` | P4 |
| `SMARTCORE_DATA_POSTGRES_MAX_INFLIGHT` | 64 | `Server::new` | admission control P3 |
| `SMARTCORE_SLOW_REQUEST_MS` | 500 | M2 slowlog | |
| `SMARTCORE_POOL_METRICS_INTERVAL_S` | 10 | M1 amostragem | |

Atualizar: `.env.example`, `.env` (dev/prod), unit systemd e o doc `smart-agent-config/doc_dev/planejamento/10-plano-cicd-devops.md`.

---

## Relação com planos existentes

Não conflita com o refator RF0–RF6. `transport::Server`/`bus` são os pontos de instrumentação (M2/P3). C3/C4 completam a decisão RF1 §4.5 (Redis bus noeviction). Orçamento de pools (P2) revisitado no RF3/RF6.

---

## Correções aplicadas (vs. plano base e vs. doc auxiliar)

| ID | Mudança | Por quê | Fonte |
|---|---|---|---|
| **C2** | `Consumer` guarda `redis::Client` e abre conexão **dedicada** via `client.get_async_connection()` no loop — em vez de clonar o `ConnectionManager` multiplexado | `XREADGROUP BLOCK` numa conexão multiplexada trava publicação/comandos rápidos | doc-comment de `connection.rs` + `redis-0.25.5/src/client.rs:80` (vendorizado) |
| **C4** | DLQ por **`xpending_count` + `times_delivered` + `xclaim`** em vez de `xautoclaim`/`xautoclaim_options` | **`xautoclaim` NÃO existe em redis 0.25.5** (só `xclaim`/`xclaim_options` + `xpending*`). `StreamPendingId.times_delivered` dá o contador de entregas nativamente | `redis-0.25.5/src/commands/mod.rs` (sem `xautoclaim`) + `streams.rs` (`StreamPendingId`) — **corrige a doc auxiliar** |
| **P4** | Timeouts via `ConnectionManager::new_with_backoff_and_timeouts(client, exponent_base, factor, retries, response_timeout, connection_timeout)` em vez de `ConnectionManagerConfig::new().set_response_timeout(...)` | **`ConnectionManagerConfig` NÃO existe em redis 0.25.5** (é redis ≥1.0). O único caminho de timeout é esse construtor | `redis-0.25.5/src/aio/connection_manager.rs:147` (vendorizado) — **corrige a doc auxiliar** |
| **M\*** | Setup de métricas via `new_pipeline().metrics(runtime::Tokio)...build()` (→ `SdkMeterProvider`); instrumentos finalizam em **`.init()`**; gauge instantâneo só via `ObservableGauge` (callback) | otlp 0.17 / opentelemetry 0.24 não têm `MetricExporter::builder`, `PeriodicReader::builder`, `.build()` em instrumentos nem `Gauge` síncrono (tudo 0.27+) | `telemetry.rs` (pipeline de traces existente) + `opentelemetry-otlp-0.17.0/src/metric.rs` + `opentelemetry-0.24.0/src/metrics/{meter.rs,instruments/mod.rs}` |
| **M\*** | Feature `metrics` adicionada em `opentelemetry-otlp`, `opentelemetry`, `opentelemetry_sdk` | Sem ela o pipeline de métricas nem compila | `opentelemetry-otlp-0.17.0/Cargo.toml` (feature `metrics` confirmada, linhas 176-179) |
| **M1/M3** | Métricas de pool recebem `&PgPool` por parâmetro; novo `observability::pool_metrics` não importa `infrastructure_postgres`; acquire (M3) emitido por `tracing` com `target` dedicado | Preservar a invariante "observability não depende de infrastructure_postgres" (quebra do ciclo já registrado) | `observability/Cargo.toml` (feature `postgres-audit` opt-in) + memória de arquitetura |
| **M4** | bus pending via `con.xpending(stream, grupo) -> StreamPendingReply` e `.count()`, em vez da tupla crua `(total, menor, maior, [...])` | A 0.25.5 já desserializa para o enum tipado `StreamPendingReply` | `redis-0.25.5/src/streams.rs` (`StreamPendingReply::count`) |
| **C3** | Apontado que o `.env.example` atual já manda `REDIS_URL` para **6380**; correção move cache→6379 e cria `REDIS_BUS_URL`→6380 | Hoje cache e bus colidem no mesmo Redis noeviction | `docker/compose/data.yml` (6379 allkeys-lru / 6380 noeviction) + `.env.example` |
| **C1** | Variantes `*_async` recebem `String` (ownership) para satisfazer o `'static` de `spawn_blocking` | `spawn_blocking` exige `FnOnce + Send + 'static` | `tokio 1.x` `spawn_blocking` + `auth/password.rs` |

### Pontos ⚠️ a revalidar em docs.rs durante a fase R (apesar de já confirmados no fonte vendorizado)
1. `redis 0.25.5` — assinatura de `new_with_backoff_and_timeouts` (6 args) e de `xclaim_options`.
2. `redis 0.25.5` — comportamento de `xpending`/`xpending_count` e campos de `StreamPendingId`.
3. `opentelemetry-otlp 0.17.0` — `with_exporter`/`.build()` do `OtlpMetricPipeline` e nome final da feature `metrics`.
