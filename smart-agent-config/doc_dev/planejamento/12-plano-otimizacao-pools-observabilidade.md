# 12 — Plano de Otimização: Pools, Concorrência e Observabilidade de Gargalos

> **Status:** Planejamento (proposta para fase P do PREVC).
> **Escopo:** `infrastructure_postgres`, `infrastructure_redis`, `transport`, `apps/data_postgres` (e, por extensão, os futuros `data_redis`/`worker`).
> **Origem:** análise técnica do código real em `dev` (handlers, pools, bus, outbox relay, consumer de auditoria).
> **Objetivo:** (a) corrigir gargalos e bugs de concorrência já presentes; (b) dar **controle fino dos pools** dirigido por configuração e por medição — nem conexões ociosas demais, nem fila por escassez; (c) instalar um **sistema de monitoramento de gargalos por requisição** (latência por método, saturação de pool, lag de filas).

---

## Sumário

1. [Diagnóstico — achados por severidade](#1-diagnóstico)
2. [Correções críticas de concorrência (C1–C5)](#2-correções-críticas)
3. [Controle fino dos pools (P1–P4)](#3-controle-fino-dos-pools)
4. [Sistema de monitoramento de gargalos (M1–M5)](#4-monitoramento-de-gargalos)
5. [Eficiência adicional (E1–E3)](#5-eficiência-adicional)
6. [Variáveis de ambiente novas](#6-variáveis-de-ambiente)
7. [Fases de implementação e DoD](#7-fases-e-dod)

---

## 1. Diagnóstico

Achados da análise do código em `dev`, ordenados por impacto:

| # | Achado | Onde | Severidade | Efeito |
|---|--------|------|-----------|--------|
| C1 | Argon2 (`verify_password`/`hash_password`) roda **no thread do runtime tokio** | `apps/data_postgres/main.rs` (`handler_verify_credentials`, `handler_create_superuser`) | **Crítica** | Cada login segura um worker thread por ~100ms–1s. Poucos logins simultâneos **param o processo inteiro** (handlers, keepalive, consumers) |
| C2 | Consumer de auditoria usa o **ConnectionManager multiplexado** com `XREADGROUP BLOCK 1000` | `main.rs` (passa `redis_conn.clone()` ao `Consumer`) | **Crítica** | O `BLOCK` segura a conexão compartilhada por até 1s por iteração; **toda publicação** (`publicar_evento_seguranca`, outbox relay) espera atrás dele. Viola a regra documentada em `infrastructure_redis::connection` |
| C3 | Separação cache×bus do docker **não refletida no app**: um único `REDIS_URL` para tudo | `main.rs` | **Alta** | `data.yml` tem `redis` (6379, `allkeys-lru`) e `redis-bus` (6380, `noeviction`). Se `REDIS_URL` apontar para o cache, **eventos de auditoria/outbox podem ser evictados** (perda silenciosa) |
| C4 | Consumer **ACKa evento que falhou**: handler engole o erro e o `Consumer::run` confirma sempre | `transport::bus::Consumer::run` + `processar_evento_auditoria` | **Alta** | Falha na consolidação de auditoria → `XACK` mesmo assim → evento perdido para sempre (sem retry, sem DLQ) |
| C5 | Pool criado com **`criar_pool(5)` hardcoded**, sem `acquire_timeout`/`min_connections`/`idle_timeout`/`max_lifetime` | `main.rs` + `connection.rs` | **Alta** | Sem fail-fast (default de acquire do SQLx = 30s de espera silenciosa); sem pool quente; impossível tunar por ambiente sem recompilar |
| P-adm | `Server` spawna **uma task por frame sem limite** | `transport::runtime::handle_connection` | Média | Rajada de N frames → N tasks disputando 5 conexões; a fila se forma invisível dentro do pool, com 30s de timeout default |
| M-0 | **Não existem métricas** — telemetria atual = traces OTLP + logs JSON apenas | `observability::telemetry` | Média | Sem gauges de pool, sem histograma de latência por método, sem lag de consumer — gargalos só aparecem quando já viraram incidente |
| E1 | `revogar_familia` faz **N+1 DELs** (um round-trip por token) | `infrastructure_redis::auth_tokens` | Baixa | Latência desnecessária em logout global/reuso |
| E2 | Outbox relay faz **UPDATE por linha** após publicar | `outbox_relay::drenar_outbox` | Baixa | N round-trips ao Postgres por lote drenado |
| E3 | Consolidação de auditoria: **1 transação por evento** | `processar_evento_auditoria` | Baixa | Lotes de 10 eventos = 10 transações; poderia ser 1 |

---

## 2. Correções críticas

### C1 — Argon2 em `spawn_blocking` (a correção mais importante)

Argon2id é **deliberadamente caro** (é a defesa contra brute-force). Hoje ele roda inline
num handler async — o que bloqueia um worker thread do tokio (tipicamente `nproc` threads,
2–4 no KVM2). Com 4 logins simultâneos, **todos** os worker threads ficam presos e o
processo inteiro congela: nenhum outro handler responde, o keepalive não responde PING,
o consumer para.

```rust
// ANTES (handler_verify_credentials)
let login_sucesso = infrastructure_postgres::verify_password(password, &user.password_hash);

// DEPOIS — CPU-bound vai para o threadpool de bloqueio do tokio
let hash = user.password_hash.clone();
let password = password.to_string();
let login_sucesso = tokio::task::spawn_blocking(move || {
    infrastructure_postgres::verify_password(&password, &hash)
})
.await
.unwrap_or(false);
```

Mesmo tratamento em `hash_password` no `handler_create_superuser` (e em todo handler
futuro de Register/ChangePassword na `application`).

**Recomendação estrutural:** expor na `infrastructure_postgres` as variantes async que
encapsulam o `spawn_blocking` (`hash_password_async`, `verify_password_async`), para o
padrão correto ser o caminho fácil.

### C2 — Conexão dedicada para o loop do consumer

O `Consumer::run` deve **deixar de receber o `ConnectionManager` compartilhado** e criar
sua própria conexão a partir da URL (ou receber um `redis::Client` e abrir a conexão
dentro do `run`). Regra final:

- `ConnectionManager` compartilhado → **só comandos rápidos** (XADD, GET/SET, XACK).
- `XREADGROUP BLOCK`, pub/sub, qualquer comando bloqueante → **conexão exclusiva do loop**.

```rust
// transport::bus::Consumer — passa a receber o Client, não o manager compartilhado
pub struct Consumer {
    stream: String,
    grupo: String,
    consumidor: String,
    client: redis::Client, // cria conexão própria no run()
}

pub async fn run<F, Fut>(&self, handler: F) -> anyhow::Result<()> {
    // conexão EXCLUSIVA deste loop: o BLOCK não afeta mais ninguém
    let mut con = redis::aio::ConnectionManager::new(self.client.clone()).await?;
    // ... resto do loop igual
}
```

O mesmo vale para o futuro consumer do `worker` (RF6) — vale registrar como regra de
arquitetura no doc 04.

### C3 — `REDIS_BUS_URL` separada da `REDIS_URL`

O compose já provisiona dois Redis com políticas corretas. O app precisa refletir isso:

```rust
// main.rs do data_postgres (e de todo app que publica/consome bus)
let redis_cache_url = std::env::var("REDIS_URL")?;       // 6379 — allkeys-lru (cache/tokens)
let redis_bus_url   = std::env::var("REDIS_BUS_URL")     // 6380 — noeviction + AOF (bus/auditoria)
    .unwrap_or_else(|_| redis_cache_url.clone());        // fallback transitório
```

- Outbox relay e `publicar_evento*` → conexão do **bus**.
- `RefreshTokenStore`/`TokenBlocklist`/`CachePermissoes` → conexão do **cache**.
- Adicionar `REDIS_BUS_URL` ao `.env.example`, aos `.env` de dev/prod do servidor e aos
  systemd units (já carregam via `EnvironmentFile`).

> Sem isso, a separação `noeviction` feita no docker é inócua — o app pode estar
> publicando auditoria no Redis errado.

### C4 — ACK condicionado ao sucesso + política de retry

O handler do consumer passa a devolver `Result`, e o `Consumer::run` só confirma quando
`Ok`. Em `Err`, o evento **permanece na PEL** e será reentregue pelo
`reprocessar_pendentes` (que já existe e hoje roda só na inicialização — passar a
executá-lo também periodicamente, ex.: a cada 60s).

```rust
pub async fn run<F, Fut>(&self, handler: F) -> anyhow::Result<()>
where
    F: Fn(EventoBruto) -> Fut + Send + Sync + 'static,
    Fut: Future<Output = Result<(), anyhow::Error>> + Send + 'static,
{
    // ...
    for evento in eventos {
        match handler(evento.clone()).await {
            Ok(()) => { confirmar_stream(&mut con, ..., &evento.stream_id).await?; }
            Err(e) => {
                tracing::warn!(stream_id = %evento.stream_id, erro = ?e,
                    "evento não confirmado — permanecerá na PEL para reentrega");
                // NÃO faz XACK: a PEL é o mecanismo de retry
            }
        }
    }
}
```

Complemento (fase 2): contador de entregas via `XPENDING`/`XAUTOCLAIM`; acima de N
tentativas, mover para um stream de **DLQ** (`security:dlq`) e ACKar o original — evita
veneno girando para sempre.

### C5 — Pool dirigido por configuração (ver §3)

---

## 3. Controle fino dos pools

### Princípio honesto

O `max_connections` do SQLx **não é redimensionável em runtime**. "Controle fino com
base nas requisições" se obtém com quatro alavancas combinadas:

1. **Configuração externa por ambiente** (env), com min/max e timeouts corretos;
2. **Pool quente** (`min_connections`) — elimina o custo de abrir conexão no pico;
3. **Fail-fast** (`acquire_timeout` curto) — fila explícita e visível em vez de espera
   silenciosa de 30s;
4. **Admission control** (semáforo na borda) — limita a concorrência **antes** do pool e
   torna a fila mensurável (é aqui que nasce a métrica de gargalo).

A medição (§4) fecha o ciclo: os números dizem se o `max` está baixo (fila no semáforo,
`acquire` lento) ou alto (muitas `idle` permanentes).

### P1 — `PoolConfig` por ambiente

```rust
// infrastructure_postgres::connection — nova API (a antiga delega para esta)
pub struct PoolConfig {
    pub max_connections: u32,      // SMARTCORE_PG_POOL_MAX        (dev: 5, prod: 12)
    pub min_connections: u32,      // SMARTCORE_PG_POOL_MIN        (dev: 1, prod: 4)
    pub acquire_timeout: Duration, // SMARTCORE_PG_ACQUIRE_TIMEOUT_MS (default 3000)
    pub idle_timeout: Duration,    // SMARTCORE_PG_IDLE_TIMEOUT_S  (default 300)
    pub max_lifetime: Duration,    // SMARTCORE_PG_MAX_LIFETIME_S  (default 1800)
}

impl PoolConfig {
    /// Lê da env com defaults seguros; loga a configuração efetiva no boot.
    pub fn from_env(prefix: &str) -> Self { /* ... */ }
}

pub async fn criar_pool_config(cfg: &PoolConfig) -> Result<PgPool, DbError> {
    let pool = PgPoolOptions::new()
        .max_connections(cfg.max_connections)
        .min_connections(cfg.min_connections)   // pool quente
        .acquire_timeout(cfg.acquire_timeout)   // fail-fast: erro visível em vez de fila oculta
        .idle_timeout(cfg.idle_timeout)         // devolve conexões ociosas ao Postgres
        .max_lifetime(cfg.max_lifetime)         // recicla conexões (evita estado acumulado)
        .connect(&url).await?;
    tracing::info!(max = cfg.max_connections, min = cfg.min_connections,
        acquire_ms = cfg.acquire_timeout.as_millis() as u64,
        "pool PostgreSQL criado");
    Ok(pool)
}
```

**Racional dos timeouts:**
- `acquire_timeout = 3s`: se uma requisição não consegue conexão em 3s, o sistema está
  saturado — melhor responder erro `retryable` rápido (o `ErrorEnvelope` já tem o campo)
  do que enfileirar 30s e estourar o prazo do `MuxClient` de qualquer jeito.
- `idle_timeout = 5min` + `min_connections`: fora de pico, o pool encolhe até o piso;
  no pico, cresce até o teto sem pagar o custo de conexão fria nas primeiras.
- `max_lifetime = 30min`: higiene padrão (renegocia conexões, evita sessões eternas).

### P2 — Sizing inicial (servidor atual: 1 KVM2, Postgres com 512MB)

O Postgres do compose serve **prod e dev simultaneamente** (`smartcore_v2` e
`smartcore_v2_dev`) com limite de 512MB. Cada conexão custa ~5–10MB no servidor.
Orçamento proposto:

| Consumidor | Pool | Justificativa |
|---|---|---|
| `data_postgres` **prod** | max **12** / min 4 | único dono do acesso a dados em prod |
| `data_postgres` **dev** | max **5** / min 1 | tráfego de teste |
| admin pool (migrations, cada boot) | 2 (efêmero, `close()` após migrar) | já é assim |
| Reserva (psql manual, `sqlx-cli`, pg_dump do deploy) | ~5 | emergência/operação |
| **Total no pico** | **~24** | folga ampla sob `max_connections=100` do PG; ~240MB no pior caso teórico, na prática bem menos |

> Regra de revisão: `Σ(max de todos os pools) + reserva ≤ max_connections do Postgres`.
> Quando o `worker` e o `control_plane` ganharem acesso próprio (se ganharem — o desenho
> por contrato concentra tudo no `data_postgres`), o orçamento é revisto **antes** do deploy.

### P3 — Admission control no `transport::Server`

Hoje cada frame vira uma task sem limite. Um semáforo global (e opcionalmente por método)
limita a concorrência **antes** do pool e dá a métrica de fila:

```rust
// transport::runtime — Server ganha limite de concorrência
pub struct Server {
    // ...
    max_em_voo: usize, // SMARTCORE_<SVC>_MAX_INFLIGHT (default 64)
}

// em handle_connection, antes do spawn do handler:
let permit = semaforo.clone().acquire_owned().await; // fila explícita e mensurável
tokio::spawn(async move {
    let _permit = permit;        // devolve a vaga ao terminar
    let inicio = Instant::now(); // instrumentação (§4 M2)
    // ... decode + handler + resposta
});
```

Dimensionamento: `max_em_voo ≈ 4–6 × pool_max` (requisições passam parte do tempo fora
do banco). Com `pool_max=12` → `MAX_INFLIGHT=64` é um bom início; o monitoramento ajusta.

**Efeito:** sob rajada, o excedente espera no semáforo (barato, mensurável, com
backpressure natural até o socket) em vez de explodir em tasks que disputam o pool às
cegas.

### P4 — Redis: timeouts e papéis

- `ConnectionManagerConfig` com `response_timeout` (ex.: 2s) e `connection_timeout` na
  criação dos managers — hoje um Redis travado pendura o comando indefinidamente.
- Papéis fixos (decorrência de C2/C3): manager do **cache** (compartilhado), manager do
  **bus para publicação** (compartilhado), conexão **exclusiva por loop de consumo**.
- Redis não precisa de pool: a multiplexação cobre os comandos rápidos; loops bloqueantes
  têm conexão própria. (Se um dia aparecer comando pesado tipo `SMEMBERS` gigante, a
  resposta é redesenhar o dado — `SSCAN` — não criar pool.)

---

## 4. Monitoramento de gargalos

Hoje há traces (OTLP) e logs JSON, mas **nenhuma métrica**. Gargalo de pool não aparece
em trace nenhum: ele aparece como "tudo ficou lento ao mesmo tempo". As peças abaixo
tornam o gargalo visível **antes** do incidente, na stack LGTM que já existe
(Prometheus + Grafana + Loki + Tempo).

### M1 — Métricas de pool (a peça central do pedido)

Task de amostragem no boot de cada app com pool (10s de intervalo):

```rust
// observability::pool_metrics (novo módulo)
pub fn monitorar_pool(pool: PgPool, intervalo: Duration) {
    tokio::spawn(async move {
        let mut tick = tokio::time::interval(intervalo);
        loop {
            tick.tick().await;
            let size = pool.size();           // conexões abertas (ativas + ociosas)
            let idle = pool.num_idle() as u32; // ociosas agora
            let em_uso = size - idle;
            // gauges OTLP: smartcore_pg_pool_size / _idle / _in_use
            tracing::info!(target: "metrics::pool",
                size, idle, em_uso, "amostra do pool PostgreSQL");
        }
    });
}
```

**Leitura do gargalo:**
- `em_uso` colado no `max` por minutos + latência subindo → **pool pequeno** (ou query lenta segurando conexão — cruzar com M2).
- `idle == size` o tempo todo → **pool grande demais**, reduzir `max`.
- Erros de `acquire_timeout` (M2 captura como categoria) → saturação aguda: subir `max` **ou** baixar `MAX_INFLIGHT` para proteger o banco.

### M2 — RED por método no `transport::Server` (Rate, Errors, Duration)

Instrumentar o ponto único por onde **toda requisição** passa (o dispatch do handler):

```rust
// no handle_connection, envolvendo a chamada do handler:
let inicio = std::time::Instant::now();
let response_env = handler(env).await;
let dur_ms = inicio.elapsed().as_millis() as u64;
let erro = response_env.kind == MessageKind::Error as i32;

// histograma OTLP smartcore_rpc_duration_ms{method, error} + contador
tracing::info!(target: "metrics::rpc",
    method = %method, dur_ms, erro, em_voo = inflight_atual,
    "requisição concluída");

// SLOW LOG: o log de gargalo pedido — threshold por env
if dur_ms > slow_threshold_ms { // SMARTCORE_SLOW_REQUEST_MS (default 500)
    tracing::warn!(target: "slowlog",
        method = %method, dur_ms,
        tenant_id = %response_env.tenant_id,
        traceparent = %response_env.traceparent,
        "requisição LENTA — investigar via trace");
}
```

O `traceparent` no slow log liga o registro direto ao **trace no Tempo** — do log do
gargalo você abre a requisição exata e vê em qual span (acquire? query? argon2? redis?)
o tempo foi gasto.

### M3 — Span de `acquire` dentro de `run_in_tenant_transaction`

O tempo de espera por conexão é o sintoma nº 1 de pool subdimensionado, e hoje é
invisível (está embutido no `begin`):

```rust
pub async fn run_in_tenant_transaction<F, T, Fut>(...) -> Result<T, DbError> {
    let inicio = std::time::Instant::now();
    let mut tx = pool.begin().await?;            // espera de acquire acontece aqui
    let espera_ms = inicio.elapsed().as_millis() as u64;
    if espera_ms > 100 {
        tracing::warn!(target: "slowlog", espera_ms,
            "espera por conexão do pool acima do esperado — pool saturando");
    }
    // histograma smartcore_pg_acquire_ms
    // ... resto igual
}
```

### M4 — Lag das filas (bus e outbox)

Os dois buffers assíncronos do sistema precisam de gauge de profundidade:

| Fila | Métrica | Como medir |
|---|---|---|
| Redis Streams (por grupo) | `smartcore_bus_pending{stream,grupo}` | `XPENDING <stream> <grupo>` na task de amostragem |
| Outbox | `smartcore_outbox_backlog` | `SELECT count(*) FROM outbox WHERE published_at IS NULL` (a cada 30s) |

Backlog do outbox crescendo = relay caído ou Redis do bus indisponível. Pending do grupo
crescendo = consumer lento ou eventos venenosos (cruzar com C4/DLQ).

### M5 — Dashboard e alertas (Grafana, stack já provisionada)

Painel "SmartCore — Saúde de Dados" com:

1. **Pool PG:** `size`/`idle`/`em_uso` + histograma de `acquire_ms` (p50/p95/p99);
2. **RPC:** taxa por método, taxa de erro, duração p95/p99 por método; top-N do slowlog (Loki, `target="slowlog"`);
3. **Filas:** pending por grupo, backlog do outbox, idade do evento mais antigo não publicado;
4. **Redis:** latência de comando (timer nos stores), erros de timeout.

Alertas mínimos: `em_uso/max > 0.85 por 5min`, `acquire p95 > 250ms`,
`outbox_backlog > 500`, `bus pending > 1000`, `taxa de erro RPC > 5%`.

---

## 5. Eficiência adicional

### E1 — `revogar_familia` com DEL variádico

```rust
// infrastructure_redis::auth_tokens — 1 round-trip em vez de N+1
let membros: Vec<String> = self.con.smembers(&chave_fam).await?;
if !membros.is_empty() {
    let chaves: Vec<String> = membros.iter().map(|h| keys::chave_refresh(h)).collect();
    let _: i64 = self.con.del(&chaves).await?; // DEL k1 k2 k3...
}
let _: i64 = self.con.del(&chave_fam).await?;
```

### E2 — Outbox relay: marcar publicados em lote

```rust
// acumula os ids publicados e marca de uma vez ao fim do lote
let mut publicados: Vec<Uuid> = Vec::with_capacity(rows.len());
for row in rows { /* publica; em sucesso: publicados.push(row.id) */ }
if !publicados.is_empty() {
    sqlx::query("UPDATE outbox SET published_at = NOW() WHERE id = ANY($1)")
        .bind(&publicados)
        .execute(&self.pool).await?;
}
```

> Trade-off consciente: na janela entre publicar e marcar, um crash gera **republicação**
> do lote — aceitável porque o `event_id` (= id da linha) garante idempotência no
> consumidor, que é a semântica at-least-once do barramento de qualquer forma.

### E3 — Consolidação de auditoria em lote

Com C4 aplicado, o consumer pode agrupar os eventos do mesmo tenant lidos numa iteração
(`count(10)`) e consolidá-los numa única `run_in_tenant_transaction` com multi-insert —
10× menos transações no caminho de auditoria sob carga.

---

## 6. Variáveis de ambiente

| Variável | Default | Consumidor | Item |
|---|---|---|---|
| `SMARTCORE_PG_POOL_MAX` | dev 5 / prod 12 | `data_postgres` | P1/P2 |
| `SMARTCORE_PG_POOL_MIN` | dev 1 / prod 4 | `data_postgres` | P1/P2 |
| `SMARTCORE_PG_ACQUIRE_TIMEOUT_MS` | 3000 | `data_postgres` | P1 |
| `SMARTCORE_PG_IDLE_TIMEOUT_S` | 300 | `data_postgres` | P1 |
| `SMARTCORE_PG_MAX_LIFETIME_S` | 1800 | `data_postgres` | P1 |
| `REDIS_BUS_URL` | (fallback: `REDIS_URL`) | todos que publicam/consomem bus | C3 |
| `SMARTCORE_REDIS_RESPONSE_TIMEOUT_MS` | 2000 | managers Redis | P4 |
| `SMARTCORE_DATA_POSTGRES_MAX_INFLIGHT` | 64 | `transport::Server` | P3 |
| `SMARTCORE_SLOW_REQUEST_MS` | 500 | `transport::Server` | M2 |
| `SMARTCORE_POOL_METRICS_INTERVAL_S` | 10 | task de amostragem | M1 |

Atualizar `.env.example`, os `.env` do servidor (dev/prod) e a seção 7 do doc
`10-plano-cicd-devops.md`.

---

## 7. Fases e DoD

### Fase 1 — Correções críticas (antes de qualquer carga real)

- [ ] C1: Argon2 via `spawn_blocking` (+ helpers `*_async` na `infrastructure_postgres`); teste: 20 logins concorrentes não degradam um `GetThread` paralelo (p95 < 100ms).
- [ ] C2: `Consumer` com conexão exclusiva; teste: latência de `publicar_evento_seguranca` sob consumo ativo permanece < 10ms (hoje pode esperar o `BLOCK` de 1s).
- [ ] C3: `REDIS_BUS_URL` em código, envs e systemd; verificação: `XADD` de auditoria aterrissa no Redis 6380 (`noeviction`).
- [ ] C4: ACK condicionado + `reprocessar_pendentes` periódico; teste: evento com erro de consolidação é reentregue, não perdido.

### Fase 2 — Controle fino de pools

- [ ] P1: `PoolConfig::from_env` + `criar_pool_config`; `criar_pool(n)` antiga marcada como caminho legado.
- [ ] P2: orçamento de conexões aplicado nos `.env` dev/prod e documentado.
- [ ] P3: semáforo `MAX_INFLIGHT` no `Server` + gauge de em-voo.
- [ ] P4: timeouts nos managers Redis.
- [ ] DoD: teste de rajada (200 requisições simultâneas) responde 100% (sucesso ou erro `retryable` em < 4s) — sem espera silenciosa de 30s, sem OOM no Postgres.

### Fase 3 — Monitoramento de gargalos

- [ ] M1: gauges de pool amostrados e visíveis no Prometheus.
- [ ] M2: RED por método + slowlog com `traceparent` (link log→trace funcionando no Grafana).
- [ ] M3: espera de `acquire` medida e com warn acima de 100ms.
- [ ] M4: gauges de pending do bus e backlog do outbox.
- [ ] M5: dashboard "Saúde de Dados" + 5 alertas mínimos provisionados.
- [ ] DoD: simular saturação (pool max=2 + carga) e comprovar que o dashboard aponta o gargalo correto **antes** do erro chegar ao cliente.

### Fase 4 — Eficiência

- [ ] E1 (DEL variádico), E2 (outbox em lote), E3 (auditoria em lote).
- [ ] DoD: benchmarks antes/depois registrados no PR (mesmo que informais, via `slowlog`).

---

## Relação com os planos existentes

- **Não conflita** com o refator RF0–RF6: o `transport::Server`/`bus` são exatamente os
  pontos de instrumentação previstos; este plano antecipa o "OTLP cedo" do RF1 com a
  camada de métricas que faltava.
- C3/C4 **completam** a decisão do RF1 §4.5 (Redis do bus `noeviction`) — o docker foi
  feito, faltava o lado do app.
- O orçamento de pools (P2) deve ser revisitado no RF3 (`data_redis`/`data_storage`) e
  RF6 (`worker`), somando os novos consumidores.
