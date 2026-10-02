# Tokio

- **Versão Recomendada:** 1.38.0
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-10-01
- **Propósito no Projeto:** Runtime assíncrono para execução concorrente do backend Rust e do local_engine.
- **Documentação Oficial:** [https://tokio.rs/](https://tokio.rs/)

---

## 1. Contexto e Uso no Projeto

O backend do Smart Core Assistant v2 é totalmente assíncrono, rodando no topo do runtime **Tokio**. Ele gerencia múltiplos canais de comunicação, WebSocket, Webhooks de entrada do Evolution Go, consultas de banco de dados e mensageria no Redis Streams.

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Nunca Bloquear o Runtime
A regra mais crítica ao usar o Tokio é **nunca bloquear uma thread assíncrona com chamadas síncronas/bloqueantes**. Operações de CPU intensas ou I/O síncrono impedem que o executor processe outras tasks.

*   **Incorreto (Não Faça):**
    ```rust
    // std::thread::sleep bloqueia a thread do runtime inteira!
    std::thread::sleep(std::time::Duration::from_secs(1)); 
    ```
*   **Correto (Faça):**
    ```rust
    // tokio::time::sleep libera a thread para outras tasks rodarem
    tokio::time::sleep(std::time::Duration::from_secs(1)).await;
    ```

### 2.2 Usando `spawn_blocking` para CPU-bound
Quando for inevitável executar código síncrono ou pesado (ex: hashing de senhas, parsing de JSONs gigantescos ou descriptografia local), delegue a operação para o pool de threads síncronas do Tokio:

```rust
let hash_result = tokio::task::spawn_blocking(move || {
    // Código síncrono/CPU-bound roda aqui com segurança
    hash_password_sync(password)
})
.await
.expect("Task blocking em pânico");
```

### 2.3 Cancelamento Seguro e Encerramento Gracioso
O `worker` e o `messaging_gateway` devem encerrar suas tarefas de forma limpa quando o servidor for desligado. Use `CancellationToken` da crate `tokio_util` para sinalizar cancelamentos.

```rust
use tokio_util::sync::CancellationToken;

async fn process_redis_stream(token: CancellationToken) {
    loop {
        tokio::select! {
            _ = token.cancelled() => {
                log::info!("Sinal de cancelamento recebido. Encerrando consumidor do Redis...");
                break;
            }
            event = read_next_stream_event() => {
                if let Some(ev) = event {
                    process_event(ev).await;
                }
            }
        }
    }
}
```

### 2.4 Timeouts em Operações de Rede
Toda chamada de rede externa (HTTP para a API do Evolution Go ou gRPC para o `ia_engine`) deve ter um timeout explícito definido para evitar que a task fique pendente indefinidamente.

```rust
use tokio::time::timeout;
use std::time::Duration;

let response = timeout(Duration::from_secs(5), call_external_api()).await;

match response {
    Ok(Ok(data)) => process_data(data),
    Ok(Err(e)) => log::error!("Erro na chamada: {:?}", e),
    Err(_) => log::warn!("Operação expirou (timeout de 5s excedido)."),
}
```

---

## 3. Features Principais de Tokio 1.38 (com feature `full`)

Quando ativada a feature `full`, o Tokio expõe:

- **tokio::time**: `sleep()`, `interval()`, `timeout()`, `Instant`, `Sleep`
- **tokio::sync**: `mpsc` (canal multi-produtor, single-consumidor), `broadcast` (pub/sub com tracking de lag), `watch` (broadcast de um único valor), `oneshot` (canal de resposta)
- **tokio::task**: `spawn()`, `spawn_blocking()`, `JoinSet` (gerenciador de múltiplas tasks com Builder)
- **tokio::select!**: Macro para multiplexação de operações assíncronas (semelhante a `select` Unix)
- **I/O assíncrono**: TCP, UDP, pipes nomeados, file system ops (novo em 1.38: `File::create_new`)
- **Notificações**: `Notify::notify_last()` (novo em 1.38) para notificar apenas a última task aguardando
- **Semáforo**: Suporte a `split()` de permits (novo em 1.38)
- **Metricas de runtime**: `RuntimeMetrics::worker_count` estabilizado em 1.38

### Features adicionadas em 1.38.0 (sem breaking changes)

- `mpsc::Receiver::{capacity,max_capacity}()` para introspecção de canais
- `JoinSet::Builder::spawn_blocking()` para integração com operações síncronas
- Suporte a plataformas: Apple visionOS, QNX, wasm32-wasi-preview1-threads
- `Copy` trait para `NamedPipeInfo`
- `copy_bidirectional_with_sizes()` para controlar buffer de cópia bidirecional

Nenhuma API foi depreciada ou removida em 1.38.0 — versão é totalmente retrocompatível com 1.37.

---

## Histórico de Atualizações

- **2026-10-01:** Atualização de verificação: confirmadas features de 1.38.0 via docs.rs e GitHub releases. Adicionada seção "Features Principais de Tokio 1.38 (com feature `full`)" com novas APIs (capacity/max_capacity, notify_last, split de semáforo, Builder::spawn_blocking, RuntimeMetrics::worker_count). Nenhuma breaking change identificada — 1.38 é retrocompatível com 1.37. Documentação oficial: https://tokio.rs/, docs.rs: https://docs.rs/tokio/1.38/tokio/
- **2026-05-31:** Documentação inicial.
