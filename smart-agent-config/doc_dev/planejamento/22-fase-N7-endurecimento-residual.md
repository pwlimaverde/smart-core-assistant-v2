# Fase N7 — Endurecimento residual + operação validada (pré-cutover)

> **Status:** Plano de execução — criado em **2026-07-17**. Segunda fase do
> cronograma de **port final** (N6–N8) — ver
> [02-fases-desenvolvimento.md](./02-fases-desenvolvimento.md).
> **Idioma:** Português (comunicação/documentação). Código e identificadores em inglês.
> **Objetivo:** quitar as pendências técnicas registradas nos ciclos N1/N4/N5 e
> validar a operação com tráfego real — pré-condição do cutover (N8). Sem isto,
> o enforce de produção seria ligado às cegas.

---

## 0. Estado real (aterramento)

| Área | Estado | Origem |
|---|---|---|
| Quota de storage | ⚠️ Medição existe (`usage_metrics`); falta coluna de limite (`max_storage_bytes` em `tenants_plan`) e ponto de enforcement no `data_storage` | pendência N4 (final-review §5) |
| Quota de departamentos | ⚠️ `Departamentos` no enum/RPC do `QuotaGuard` sem nenhum caller | pendência N4 |
| Idempotência do sync offline | ⚠️ `action_id` (uuid v7) chega aos callbacks Dart mas `MoveAtendimentoEtapaRequest`/`SendOutboundMessageRequest` não têm campo no proto | pendência N5 |
| Outbound sem destino | ⚠️ Falha de resolução de destino sem `whatsapp_contact` ativo não tem dead-letter | pendência N1 |
| Rate-limit do webhook | ⚠️ Contadores no `redis-bus` (conexão que o webhook já tinha), separados dos do `runtime_api` em prod | pendência N4 (final-review §5) |
| Sync offline (gatilho) | ⚠️ Só best-effort na abertura da fila; sem trigger por conectividade/timer | pendência N5 |
| `local_engine` (menores) | ⚠️ `next_version`/`MIN(id)` não-atômicos entre conexões do pool; stream FFI encerra silencioso em `Lagged` | revisão pós-N5 |
| Dashboards/alertas | ⚠️ Provisionados como código (N1.4) mas nunca validados com tráfego real | pendência N1 |
| Testes de rajada/carga | ⚠️ Nunca executados (projeto proíbe harness automatizado; validação manual via túnel/`test_support`) | pendência N4 |
| E2E manual das UIs do tenant | ⚠️ Aceito por decisão do dono na N3 com base nos testes; nunca clicado contra runtime real | pendência N3 |

## 1. Escopo

### Dentro do escopo
- **N7.1** Quotas restantes: migration `max_storage_bytes` em `tenants_plan` +
  guard no `data_storage` (mesmo padrão `QuotaGuard` decorator da N4.2, log-only →
  enforce por flag); caller de `Departamentos` no CRUD de departamento.
- **N7.2** Idempotência do sync: campo `action_id` (aditivo) nos RPCs
  `MoveAtendimentoEtapa`/`SendOutboundMessage`, dedupe server-side (tabela ou
  índice único por `action_id`), mapeamento nos callbacks Dart já preparados;
  dead-letter para outbound sem destino resolvível (auditado, reprocessável).
- **N7.3** Centralizar contadores de rate-limit do webhook via RPC
  `RegisterRateLimitAttempt` do `data_redis` (sair do redis-bus; consistência com
  o `runtime_api` e independência da política de eviction do bus).
- **N7.4** Sync offline robusto no desktop: trigger por reconexão (listener de
  conectividade) + timer periódico; atomicidade de `next_version`/id pendente no
  SQLite (single-statement); tratar `Lagged` no stream FFI (log + resubscribe).
- **N7.5** Validação operacional manual (documentada em relatório): rajada no
  webhook/bus via túnel, dashboards/alertas com tráfego real no Grafana dev,
  roteiro E2E clicado das UIs do tenant (convite→aceite→RBAC fino→chat).

### Fora do escopo
- Ligar o enforce em produção (isso é N8.3, após janela de observação).
- Novas features de produto.

## 2. Contrato de observabilidade (DoD transversal)

- Todo enforcement novo nasce **log-only** atrás de flag (padrão N4), com
  contadores Prometheus e auditoria apenas no ponto de enforcement real (lição da
  N4: nunca auditar no caminho quente de leitura).
- Dead-letter audita `mensagem.dead_letter` (sem conteúdo/PII).
- Dedupe por `action_id` audita rejeição de duplicata (INFO, só ids).

## 3. Riscos e mitigações

| Risco | Impacto | Mitigação |
|---|---|---|
| Dedupe server-side mal indexado | Latência no caminho quente de mensagens | Índice único parcial por `action_id NOT NULL`; campo opcional (clientes velhos seguem funcionando) |
| Trigger de conectividade instável no Windows | Sync em loop/bateria | Debounce do trigger + guarda anti-concorrência já existente (`_sincronizando`) |
| Validação de carga derrubar o dev compartilhado | Ambiente fora do ar | Janela combinada, rajada progressiva, observar backlog no Grafana antes de subir carga |

## 4. Frontmatter PREVC

| Fase | P | R | E | V | C |
|---|---|---|---|---|---|
| **N7** | Confirmar formato do dedupe (`action_id`) e da dead-letter | Aprovar migrations + evolução aditiva dos protos | N7.1→N7.4 código; N7.5 roteiro manual | `.\infra\test-local.ps1` + `.\infra\test-flutter.ps1` + relatório da validação manual | changelog + gate `prevc-final-review` |

**DoD da fase:** storage/departamentos com guard log-only funcionando; reenvio de
ação offline não duplica efeito no servidor (provado por `action_id`); contadores
de rate-limit unificados; sync dispara sozinho ao reconectar; relatório de
rajada/dashboards/E2E manual arquivado como evidência de prontidão para o N8.

*Plano consolidado das pendências registradas nos changelogs/final-reviews de
N1, N3, N4 e N5. Pronto para `/plan-restructuring` quando a fase for iniciada.*
