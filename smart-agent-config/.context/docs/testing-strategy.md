---
type: doc
name: testing-strategy
description: Test frameworks, patterns, coverage requirements, and quality gates
category: testing
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---

## Testing Strategy

> Projeto greenfield — estratégia a ser refinada durante a implementação. Diretrizes baseadas no design arquitetural e nas lições da v1.

## Test Organization

- **Rust**: unitários em `crates/domain_*/src/` (`#[cfg(test)]`); integração em `crates/*/tests/`; contratos em `crates/contracts/tests/`.
- **Python**: testes em `services/ai_orchestrator/tests/` com pytest.
- **Flutter**: unitários em `clients/flutter_app/test/`; widget e integration tests conforme necessário.

## Testing Priorities

1. **`crates/domain_*`** — regras puras. Alta cobertura obrigatória. Sem I/O; sem mocks.
2. **`crates/application`** — casos de uso com mocks de infraestrutura. Cobrir `TicketPolicy`, `BotRulesEngine`, debounce.
3. **`crates/infrastructure_postgres`** — integração com banco real (não mock). Lição da v1: mocks escondem divergências de schema.
4. **`messaging_gateway`** — validação de webhook, resolução de tenant, idempotência.
5. **`ai_orchestrator`** — cada feature (transcrição, RAG, geração de resposta).

## Domain Rules to Test Explicitly

- Um atendimento ativo por contato (política de ticket).
- Janela de reabertura de 10 min.
- Bot bloqueado permanentemente por mensagem de atendente.
- Idempotência: `wa_message_id` duplicado não reprocessado.
- RLS: query sem `tenant_id` no contexto deve ser rejeitada.
- Debounce: rajada resulta em lote único processado.

## Tooling

| Stack | Framework | Observação |
|-------|-----------|-----------|
| Rust | `cargo test` | Unitários + integração |
| Rust (integração) | `cargo test --test '*'` | Com PostgreSQL real — não usar mocks de banco |
| Python | `pytest` + `pytest-asyncio` | Para ai_orchestrator async |
| Flutter | `flutter test` | Unitário + widget |

## Related Resources

- [Architecture](architecture.md)
- [Development Workflow](development-workflow.md)
