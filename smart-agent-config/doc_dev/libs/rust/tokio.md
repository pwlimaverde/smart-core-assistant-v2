# Tokio

- **Versão Recomendada:** 1.38.0
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
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
