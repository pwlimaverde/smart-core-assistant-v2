# Tracing (tracing)

- **Versão Recomendada:** 0.1.40
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-10-01
- **Propósito no Projeto:** Framework de instrumentação assíncrona e logs estruturados de alto desempenho para todo o backend Rust.
- **Documentação Oficial:** [https://tokio.rs/blog/2019-08-tracing](https://tokio.rs/blog/2019-08-tracing)

---

## 1. Contexto e Uso no Projeto

O monitoramento de fluxos concorrentes no `worker`, `runtime_api` e `messaging_gateway` exige logs rastreáveis e ricos. O **Tracing** substitui o tradicional sistema de logs por um modelo baseado em Spans (intervalos de tempo com metadados) e Events (ocorrências individuais).

Em produção, os logs são exportados em formato **JSON estruturado** para facilitar a consolidação de métricas e auditoria. Em desenvolvimento local, são exibidos de forma amigável e colorida no console.

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Instrumentação de Funções Assíncronas (#[instrument])
Utilize o macro `#[instrument]` em funções complexas ou Use Cases de negócio. Ele cria automaticamente um Span com o nome da função e insere os argumentos da chamada como metadados do log.

```rust
use tracing::{instrument, info, error, debug};
use uuid::Uuid;

#[instrument(skip(db_pool))] // skip evita gravar bytes ou estruturas grandes no log
pub async fn process_ticket_transition(
    ticket_id: Uuid,
    target_stage_id: &str,
    db_pool: &sqlx::PgPool,
) -> Result<(), anyhow::Error> {
    info!("Iniciando transição de etapa do ticket.");

    // Eventos disparados dentro desta função carregarão implicitamente o ticket_id
    let res = db::update_ticket_stage(ticket_id, target_stage_id, db_pool).await;

    if let Err(ref e) = res {
        error!(error = ?e, "Falha ao gravar transição de etapa no banco.");
    } else {
        debug!("Etapa atualizada com sucesso no banco.");
    }

    res
}
```

### 2.2 Configuração de Logs Rotativos (tracing-appender)
Para evitar que os logs consumam todo o espaço de disco da VM Hostinger, configure a gravação com rotação diária de arquivos usando `tracing-appender`:

```rust
use tracing_subscriber::{fmt, layer::SubscriberExt, util::SubscriberInitExt, Registry};

pub fn init_observability() {
    // Configura rotação diária de logs gravando na pasta ./logs
    let file_appender = tracing_appender::rolling::daily("./logs", "smart-core.log");
    let (non_blocking_writer, _guard) = tracing_appender::non_blocking(file_appender);

    // Layer para console local (colorido e humanizado)
    let stdout_layer = fmt::layer()
        .with_ansi(true);

    // Layer para arquivo (formato JSON estruturado para análise posterior)
    let file_layer = fmt::layer()
        .json() // Habilita output em formato JSON
        .with_writer(non_blocking_writer);

    Registry::default()
        .with(stdout_layer)
        .with(file_layer)
        .init();
}
```

### 2.3 Proibição de Prints no Código
Nunca utilize as macros `println!` ou `print!` em crates de domínio e binários do backend. Prints burlam a infraestrutura do Tracing, não possuem metadados de span (como `tenant_id`) e não são gravados nos logs rotativos. Utilize sempre `info!`, `debug!`, `warn!` ou `error!`.

---

## 3. APIs Principais de Tracing 0.1.40

### Macros Centrais

```rust
// Logging por nível (no contexto do span atual)
pub macro info!($($tt:tt)*) { /* ... */ }
pub macro debug!($($tt:tt)*) { /* ... */ }
pub macro warn!($($tt:tt)*) { /* ... */ }
pub macro error!($($tt:tt)*) { /* ... */ }
pub macro trace!($($tt:tt)*) { /* ... */ }

// Macro genérica com nível dinâmico
pub macro event!($level:expr, $($tt:tt)*) { /* ... */ }
```

### Instrumentação de Funções

```rust
#[instrument(skip(large_param), fields(tenant_id = %tenant_id.to_string()))]
pub async fn process_async(
    tenant_id: Uuid,
    large_param: &[u8],
) -> Result<()> { ... }
```

**Atributos de `#[instrument]`:**
- `skip(param1, param2)` — Não logar esses parâmetros (evita dados grandes/sensitivos)
- `skip_all` — Não logar nenhum parâmetro
- `fields(key = value, key2 = %display_value)` — Adicionar campos custom
- `err` — Logar erros automaticamente se função retorna `Err`

### Spans (Período de Tempo com Metadados)

```rust
use tracing::{span, Level};

let span = span!(Level::INFO, "processing", event_id = %uuid);
let _guard = span.enter();
// Código aqui está dentro do span
```

### Obtenção do Span Atual (para adicionar campos em runtime)

```rust
use tracing::Span;

let current = Span::current();
current.record("field_name", &value);
```

### Traits e Tipos-Chave

- `Subscriber` — Implementador que processa spans e events
- `Span` — Referência a um span ativo
- `Event` — Uma ocorrência singular dentro de um span
- `Metadata` — Nome, nível, arquivo/linha de um span/event

### Compatibilidade com `log` crate

Com feature `"log"` habilitada, logs do `log` crate são convertidos para Tracing. Com feature `"log-always"`, Tracing também emite para `log` simultaneamente.

```toml
tracing = { version = "0.1.40", features = ["attributes", "log"] }
```

### MSRV (Minimum Supported Rust Version)

Tracing 0.1.40 requer Rust **1.65+**. Segue política de Tokio: suporta compilador estável atual + 3 versões anteriores.

---

## 4. Histórico de Atualizações

- **2026-10-01:** Atualização de verificação: confirmada versão 0.1.40 (stable, sem breaking changes em 0.1.x). Coletada documentação via docs.rs/tracing/0.1 e GitHub release notes (0.1.40 é maintenance release que corrigiu segurança: stack use-after-free em `Instrument::into_inner` via `mem::ManuallyDrop`). Adicionada seção "APIs Principais de Tracing 0.1.40" com macros (info/debug/warn/error/trace/event), atributos de `#[instrument]`, Spans, métodos `Span::current().record()`, traits (Subscriber, Metadata), e MSRV (1.65+). Nenhuma breaking change em 0.1.40. Documentação oficial: https://tokio.rs/blog/2019-08-tracing, docs.rs: https://docs.rs/tracing/0.1/tracing/
- **2026-05-31:** Documentação inicial.
