---
type: skill
name: Bug Investigation
description: Investigate bugs systematically and perform root cause analysis. Use when Investigating reported bugs, Diagnosing unexpected behavior, or Finding the root cause of issues
skillSlug: bug-investigation
phases: [E, V]
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---
## Workflow

1. Reproduza o bug de forma consistente (teste que falha > reprodução manual)
2. Identifique o processo afetado: app de negócio, serviço `data_*`, `ia_engine` ou client Flutter
3. Colete evidências: logs estruturados (`observability`/OTLP), `traceparent`, payloads de `Envelope`/`ErrorEnvelope`
4. Verifique as suspeitas clássicas do projeto: idempotência (`wa_message_id`), isolamento de tenant (RLS/`tenant_id`), debounce (rajadas), retry/backoff de mídia
5. Identifique quando o bug foi introduzido (`git bisect` se necessário)
6. Formule hipótese, confirme com debug/teste e documente a causa raiz
7. Escreva o teste de regressão junto com o fix

## Examples

**Notas de investigação:**
```
## Bug: mensagem duplicada no ticket após rajada

### Reprodução:
1. Enviar 3 mensagens em < 2s para a mesma instância
2. Worker processa 2 lotes em vez de 1

### Investigação:
- Trace mostra dois consumers pegando eventos do mesmo contato
- Lock de debounce expira antes do fim da janela de acumulação
- Introduzido no commit abc123 (ajuste do TTL do lock)

### Causa raiz:
TTL do lock menor que a janela de debounce → segundo consumer
adquire o lock e processa a rajada parcial.

### Fix:
TTL = janela + margem; teste de regressão
`debounce_burst_results_in_single_batch` em tests/event_bus/.
```

## Quality Bar

- Sempre reproduzir antes de investigar; preferir reprodução por teste
- Para bugs de dados, validar contra banco real (transação+rollback), nunca mock
- Checar se o bug existe em outros pontos (mesmo padrão em outro handler/feature)
- Causa raiz documentada em pt-br; teste de regressão obrigatório no fix
- Bug de tenant isolation é severidade máxima: validar policies RLS + filtro `tenant_id`

## Resource Strategy

- Add `scripts/` only when the task is fragile, repetitive, or benefits from deterministic execution.
- Add `references/` only when details are too large or too variant-specific to keep in `SKILL.md`.
- Add `assets/` only for files that will be consumed in the final output.
- Keep extra docs out of the skill folder; prefer `SKILL.md` plus only the resources that materially help.
