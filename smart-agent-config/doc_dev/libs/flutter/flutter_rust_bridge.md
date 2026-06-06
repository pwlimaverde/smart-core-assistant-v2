# Flutter Rust Bridge (flutter_rust_bridge)

- **Versão Recomendada:** 2.0.0
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
- **Propósito no Projeto:** Gerador de código para FFI (Foreign Function Interface) de alta performance entre Dart (Flutter) e Rust (`local_engine`), permitindo compartilhar a lógica de cache local e criptografia.
- **Documentação Oficial:** [https://github.com/fzyzcjy/flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge)

---

## 1. Contexto e Uso no Projeto

Para atingir excelente desempenho de interface, leitura instantânea offline de histórico e gerenciamento de arquivos de mídia sem engasgar o thread de UI do Flutter, criamos a crate Rust `local_engine` que compila como uma biblioteca nativa (`.dll` no Windows).

O **`flutter_rust_bridge` (FRB)** elimina a necessidade de escrever código FFI C manual repetitivo:
- Ele analisa o código das structs e funções em Rust em `server/crates/local_engine/`.
- Gera automaticamente os adapters Dart correspondentes e o código de cola C/C++ em `clients/packages/local_engine_ffi/`.

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Separação Rígida de Dependência (Abstração DataSource)
Para evitar que o aplicativo dependa exclusivamente do binário FFI (o que impediria o port Web do Flutter na Fase 2), todo o código de interface deve se comunicar apenas com a classe abstrata `DataSource`. 
O `local_engine_ffi` é injetado como implementação concreta **somente** no build de Windows Desktop.

```dart
// lib/core/data_source.dart
abstract class DataSource {
  Future<List<Ticket>> fetchTickets(String tenantId);
  Stream<RealtimeEvent> watchEvents();
}

// clients/packages/local_engine_ffi/lib/src/ffi_data_source.dart
class LocalEngineFFIDataSource implements DataSource {
  // Chamada nativa gerada pelo flutter_rust_bridge
  @override
  Future<List<Ticket>> fetchTickets(String tenantId) async {
    final rustTickets = await api.fetchLocalTickets(tenantId: tenantId);
    return rustTickets.map((t) => t.toDartEntity()).toList();
  }

  @override
  Stream<RealtimeEvent> watchEvents() {
    // Escuta stream nativa enviada do Rust
    return api.subscribeToLocalEvents();
  }
}
```

### 2.2 Codegen e Geração de Código
Sempre que structs ou assinaturas de funções expostas em `local_engine` sofrerem alterações no lado Rust, recompile a ponte rodando a ferramenta de codegen da raiz do pacote:

```bash
flutter_rust_bridge_codegen generate
```

### 2.3 Utilização de Fluxos de Dados Assíncronos (Stream)
Para eventos em tempo real capturados no lado nativo (como download concluído de mídia ou reconexão de rede local), utilize o tipo `StreamSink` do Rust. O FRB converterá isso automaticamente em um `Stream<T>` nativo do Dart.

*Rust (`server/crates/local_engine/src/api.rs`):*
```rust
use flutter_rust_bridge::StreamSink;

pub fn subscribe_to_local_events(sink: StreamSink<LocalEvent>) {
    // Guarda o sink em uma thread ou canal estático para postar eventos concorrentemente
    GLOBAL_EVENT_SINK.set(sink);
}
```

*Dart (`clients/packages/local_engine_ffi/lib/...`):*
```dart
Stream<LocalEvent> get localEvents => api.subscribeToLocalEvents();
```

### 2.4 Cuidado com Mutabilidade e Linckagem Estática
*   Toda transferência de tipos entre Dart e Rust via FRB envolve serialização binária interna (através do formato de serialização do FRB). Evite passar payloads gigantescos de uma só vez (ex: bytes brutos de mídia inteira no retorno de funções normais). Utilize ponteiros para arquivos temporários no disco sempre que possível.
*   Trate o ciclo de vida do Rust de forma assíncrona. Funções de FFI pesadas devem usar `async fn` no Rust, o que faz o FRB despachá-las na thread-pool interna do Tokio do lado nativo, liberando a thread principal de UI do Flutter de micro-travamentos.
