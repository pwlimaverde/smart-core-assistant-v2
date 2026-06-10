---
type: skill
name: Api Design
description: Design contract-first APIs (.proto canônico → FlatBuffers/gRPC) for services and the Flutter client. Use when Designing new RPC methods or services, Defining events for the bus, or Planning contract versioning strategy
skillSlug: api-design
phases: [P, R]
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---
## Workflow

1. Defina o contrato no schema `.proto` canônico em `crates/contracts` (fonte única; `.fbs` é transpilado no build)
2. Modele requisição/resposta como mensagens explícitas (`XxxRequest` / `XxxResponse`) — nunca tipos soltos
3. Todo método que toca dados de tenant viaja em `Envelope` (RPC) ou `TenantEnvelope<T>` (evento do bus) com `tenant_id`
4. Erros sempre via `ErrorEnvelope` (`error_core::AppError` no Rust) — nunca strings ad-hoc
5. Para acesso a dados, crie o handler no serviço `data_*` dono do recurso (rota por `method` no `transport::Server`); apps de negócio só consomem via cliente RPC
6. Para o Flutter, exponha pelo `runtime_api` seguindo o contrato unificado D7 (req/reply + Server Streaming p/ realtime)
7. Planeje evolução compatível: campos novos opcionais, nunca reusar número de campo, `reserved` para removidos

## Examples

**Novo método de dados (contrato + handler):**
```proto
// crates/contracts/proto/ticket.proto — comentários em pt-br
message GetTicketRequest {
  string tenant_id = 1;
  string ticket_id = 2;
}
message GetTicketResponse {
  Ticket ticket = 1;
}
```

```rust
// apps/data_postgres/src/main.rs — rota registrada no Server::from_env
// handler recebe Envelope, usa repositórios de infrastructure_postgres
// e publica auditoria via transport::bus quando a operação é sensível
servidor.rota("ticket.get", handler_get_ticket);
```

**Evento do bus:**
```rust
// TenantEnvelope<MessageReceived> publicado pelo gateway no Redis Streams
publicar_evento(&bus, "message.received", TenantEnvelope::new(tenant_id, evento)).await?;
```

## Quality Bar

- Schema `.proto` é a fonte única; nada de structs paralelas divergindo do contrato
- `tenant_id` obrigatório em qualquer mensagem que toque dados de domínio
- Nomes de métodos no padrão `recurso.acao` (ex.: `ticket.get`, `auth.verify_credentials`)
- Mudanças de contrato são compatíveis para frente (campos opcionais, números nunca reaproveitados)
- Webhook HTTP (Evolution Go → `messaging_gateway`) é a única superfície REST; valida assinatura e nunca executa regra pesada
- Idempotência explícita onde há retry (ex.: `wa_message_id`)

## Resource Strategy

- Add `scripts/` only when the task is fragile, repetitive, or benefits from deterministic execution.
- Add `references/` only when details are too large or too variant-specific to keep in `SKILL.md`.
- Add `assets/` only for files that will be consumed in the final output.
- Keep extra docs out of the skill folder; prefer `SKILL.md` plus only the resources that materially help.
