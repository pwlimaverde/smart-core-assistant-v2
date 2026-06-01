# SQLite3 (Persistência Local)

- **Versão Recomendada:** 2.1.0 (via `rusqlite` / `sqlx-sqlite` no Rust FFI)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
- **Propósito no Projeto:** Persistência relacional local e rápida para indexação de mídias offline, fila de envios pendentes e cache de mensagens no Windows Desktop.
- **Documentação Oficial:** [https://pub.dev/packages/sqlite3](https://pub.dev/packages/sqlite3) (para wrappers Dart direct) e [https://crates.io/crates/rusqlite](https://crates.io/crates/rusqlite) (para FFI)

---

## 1. Contexto e Uso no Projeto

Conforme a decisão arquitetural **D1 (FFI Híbrido)**, o aplicativo Windows Desktop funciona com armazenamento permanente local para garantir que:
1. Visualizações repetidas de mídias (fotos, áudios) não consumam processamento e banda do servidor principal.
2. O histórico recente de conversas carregue instantaneamente na UI sem latência de rede.
3. Mensagens enviadas offline fiquem retidas em fila de reprocessamento em disco.

> [!IMPORTANT]
> **Acesso Exclusivo via FFI:** O aplicativo Dart/Flutter **não executa queries SQL locais diretamente**. Quem gerencia e abre o arquivo SQLite local (`.db` local no diretório do usuário no Windows) é o crate Rust **`local_engine`**. A camada Dart consome esses dados apenas como objetos DTO estruturados expostos pela FFI (`local_engine_ffi`).

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Estrutura do Banco de Dados Local (Schema)
O schema do SQLite é gerenciado pelo módulo `local_engine` no Rust e sincronizado via migrações automáticas no bootstrap do FFI local.
Tabelas principais em cache:
- `cached_message`: id, conversation_id, content, type, status_envio, media_path, media_hash, created_at.
- `cached_conversation`: id, contact_id, last_message_at, subject, unread_count.
- `outbox_queue`: id, endpoint, payload_json, retries, created_at.

### 2.2 Reconciliação e Estratégia de Sincronização (Sync)
O SQLite local atua estritamente como um **cache otimista de leitura e gravação offline**, e a verdade absoluta reside no PostgreSQL do servidor principal.
*   **Atualização Unilateral:** Ao receber atualizações via WebSocket (`runtime_api`), a camada FFI insere ou atualiza o registro correspondente no SQLite local.
*   **Envio Otimista:** Quando o atendente envia uma mensagem, ela é inserida no SQLite local com status `Pending`, mostrada na tela imediatamente, e adicionada na tabela `outbox_queue`. O motor Rust local tenta fazer a transmissão HTTP para o servidor e, após confirmação, altera o status para `Sent`.

```rust
// Exemplo conceitual de query SQL do lado Rust (local_engine) usando rusqlite:
pub fn save_message_to_local_cache(
    conn: &rusqlite::Connection,
    message: &LocalMessageDto,
) -> Result<(), rusqlite::Error> {
    conn.execute(
        "INSERT OR REPLACE INTO cached_message (id, conversation_id, content, status_envio) 
         VALUES (?1, ?2, ?3, ?4)",
        (
            &message.id.to_string(),
            &message.conversation_id.to_string(),
            &message.content,
            "Sent"
        ),
    )?;
    Ok(())
}
```

### 2.3 Gestão de Arquivo e Diretório de Cache no Windows
O arquivo do SQLite no Windows Desktop deve ser salvo sob o diretório padrão de dados locais do aplicativo (App Data Local), isolado por usuário do sistema.

```dart
// Exemplo de como a camada FFI do Dart inicializa passando o caminho correto do diretório de dados
import 'package:path_provider/path_provider.dart';

Future<void> initializeLocalEngine() async {
  final appDir = await getApplicationSupportDirectory();
  final dbPath = "${appDir.path}/local_cache.db";
  
  // Inicializa o motor Rust passando o caminho do SQLite local
  await LocalEngineFFI.init(dbPath: dbPath);
}
```
