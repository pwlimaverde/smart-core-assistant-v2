# Serde

- **Versão Recomendada:** 1.0.229
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-10-01
- **Propósito no Projeto:** Serialização e desserialização de estruturas de dados (DTOs, eventos, payloads do webhook e bancos de dados) para formatos como JSON e Protobuf.
- **Documentação Oficial:** [https://serde.rs/](https://serde.rs/)

---

## 1. Contexto e Uso no Projeto

O Smart Core Assistant v2 interage intensamente com outras tecnologias via rede e FFI. O **Serde** garante que as structs de Rust sejam convertidas de/para representações textuais ou binárias limpas:
- DTOs gRPC/HTTP trocados com o Flutter (Dart).
- Payloads JSON do webhook recebidos do Evolution Go.
- En envelopes serializados e salvos no Redis Streams e PostgreSQL.

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Uniformidade de Case (Nomenclatura)
O backend Rust segue o padrão de nomenclatura `snake_case` para propriedades. No entanto, APIs HTTP externas ou contratos de frontend no Flutter podem exigir `camelCase` ou `PascalCase`. Utilize atributos do Serde para normalizar as chaves sem violar os linters de Rust.

```rust
use serde::{Serialize, Deserialize};

#[derive(Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")] // Renomeia todos os campos no JSON para camelCase
pub struct TicketDto {
    pub ticket_id: uuid::Uuid,
    pub tenant_id: uuid::Uuid,
    pub subject: String,
    pub assigned_agent_id: Option<uuid::Uuid>,
}
```

### 2.2 Tratamento de Tags de Enums (Serialização Internamente Marcada)
Ao expor Enums para serialização JSON, prefira o padrão adjacente ou internamente marcado (`tag` / `content`) para facilitar o parse em TypeScript/Dart e Python.

```rust
#[derive(Serialize, Deserialize, Debug)]
#[serde(tag = "type", content = "payload", rename_all = "snake_case")]
pub enum RealtimeEvent {
    MessageCreated(MessagePayload),
    TicketMoved { ticket_id: uuid::Uuid, target_stage_id: String },
    AgentTyping { agent_id: uuid::Uuid, is_typing: bool },
}
```

*Saída JSON gerada:*
```json
{
  "type": "ticket_moved",
  "payload": {
    "ticket_id": "893c52a0-4ff6-4279-8d1f-827d5fa2ef1a",
    "target_stage_id": "done"
  }
}
```

### 2.3 Evitar Desserialização Silenciosa de Erros
Ao mapear payloads importantes (como webhooks brutos do Evolution Go), garanta que campos obrigatórios de domínio falhem na desserialização se estiverem ausentes, adicionando o atributo `#[serde(deny_unknown_fields)]` apenas em estruturas estritas.

Para propriedades opcionais que devem ter um valor padrão caso omitidas no JSON, use `#[serde(default)]`.

```rust
#[derive(Deserialize, Debug)]
pub struct WebhookPayload {
    pub instance: String,
    pub apikey: String,
    #[serde(default)] // Se omitido, inicializa com None/vazio correspondente ao tipo
    pub data: Option<serde_json::Value>,
}
```

### 2.4 Integração com Tipos do Chrono e UUID
Sempre ative as features `serde` em crates externas como `chrono` e `uuid` no `Cargo.toml` para que esses tipos suportem serialização direta e correta sem necessidade de wrappers manuais:

```toml
# No Cargo.toml
uuid = { version = "1.8", features = ["v4", "v7", "serde"] }
chrono = { version = "0.4", features = ["serde"] }
```

---

## 3. APIs Principais de Serde 1.0.x

### Derive Macros (com feature `derive`)

```rust
#[derive(Serialize, Deserialize)]
pub struct MyStruct {
    field: String,
}
```

### Traits Fundamentais

```rust
// Serialização
pub trait Serialize {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    { ... }
}

// Desserialização
pub trait Deserialize<'de>: Sized {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    { ... }
}
```

### Atributos Comuns de Derive

- `#[serde(rename_all = "camelCase")]` — Rename todos os campos
- `#[serde(skip_serializing_if = "Option::is_none")]` — Omitir campos vazios no JSON
- `#[serde(default)]` — Usar tipo Default se campo omitido na desserialização
- `#[serde(tag = "type", content = "data")]` — Serialização internamente marcada de enums
- `#[serde(deny_unknown_fields)]` — Falhar se JSON contém campos não definidos
- `#[serde(remote = "path")]` — Derivar para tipos de crates externas (bypass orphan rule)

### Suporte a Zero-Copy Deserialization (Lifetime `'de`)

Serde 1.0 habilita desserialização com borrowing — strings podem referenciar substrings do input sem alocação:

```rust
#[derive(Deserialize)]
pub struct Record<'de> {
    pub name: &'de str,  // Referencia a substring do JSON, sem clone
}
```

---

## 4. Histórico de Atualizações

- **2026-10-01:** Atualização de verificação: confirmada versão 1.0.229 (released 2026-09-29). Coletada documentação via docs.rs/serde/1.0 e GitHub release notes. Adicionada seção "APIs Principais de Serde 1.0.x" com assinaturas dos traits Serialize/Deserialize, atributos comuns de derive (rename_all, skip_serializing_if, default, tag/content, deny_unknown_fields, remote), e exemplo de zero-copy deserialization com lifetime `'de`. Nenhuma breaking change em 1.0.x — versão mantém estabilidade API desde 1.0.0 (setembro 2026). Documentação oficial: https://serde.rs/, docs.rs: https://docs.rs/serde/1.0/serde/
- **2026-05-31:** Documentação inicial.
