---
type: plan
name: "Fase N5 — Consolidação de Clientes + Offline (desktop, FFI, paridade Web)"
planSlug: n5-consolidacao-clientes-offline
description: "Pós-estabilização (F7/F8/F10): consolidação do app (navegação/estados/empacotamento Windows), local_engine FFI dual-target com índice SQLite, cache de mídia por hash e fila offline com sync (troca RemoteOnly→LocalEngineFFI sem tocar telas), e paridade Web completa com CORS de mídia no R2."
summary: "Última fase do backlog: consolidar os clientes, provar o DataSource abstrato plugando o LocalEngineFFI sem reescrever telas, e fechar a paridade web com mídia servida por presign+CORS."
status: filled
progress: 0
generated: "2026-07-06"
scaffoldVersion: "2.0.0"
agents:
  - type: "mobile-specialist"
    role: "Consolidação do app Flutter (navegação/estados/acessibilidade), empacotamento Windows, DataSource LocalEngineFFI"
  - type: "backend-specialist"
    role: "Crate local_engine dual-target (cdylib/staticlib), índice SQLite, cache de mídia por hash, fila offline + sync"
  - type: "architect-specialist"
    role: "Aprovar dual-target FFI, estratégia de sync (last-write-wins + versionamento) e a prova do port (LSP)"
  - type: "devops-specialist"
    role: "CORS do R2 versionado (cors.json), deploy web do app operacional/tenant (padrão Caddy same-origin)"
phases:
  - id: "phase-p"
    name: "Planning"
    prevc: "P"
    agent: "architect-specialist"
    status: "pending"
  - id: "phase-r"
    name: "Review"
    prevc: "R"
    agent: "architect-specialist"
    status: "pending"
  - id: "phase-2"
    name: "Execution"
    prevc: "E"
    agent: "mobile-specialist"
    status: "pending"
    required_sensors: [tests-passing]
    required_artifacts: [handoff-summary]
  - id: "phase-v"
    name: "Validation"
    prevc: "V"
    agent: "test-writer"
    status: "pending"
  - id: "phase-c"
    name: "Confirmation"
    prevc: "C"
    agent: "devops-specialist"
    status: "pending"
lastUpdated: "2026-07-17T19:03:52.122Z"
---

# Fase N5 — Consolidação de Clientes + Offline (desktop, FFI, paridade Web)

> Quinta e última fase do backlog pós-MVP. **Só entra após N1–N4 estáveis em produção.**
> **Regra inegociável:** o `DataSource` abstrato garante a troca `RemoteOnly` ↔ `LocalEngineFFI`
> **sem reescrever telas** (LSP) — se exigir mudar tela, corrige-se o port.

## Artefatos detalhados
- **Plano completo** (verdade técnica): [plano_completo_n5-consolidacao-clientes-offline.md](./n5-consolidacao-clientes-offline/plano_completo_n5-consolidacao-clientes-offline.md)
- **Documentação auxiliar** (R2 CORS + presign, libs FFI/SQLite): [info_aux_n5-consolidacao-clientes-offline.md](./n5-consolidacao-clientes-offline/info_aux_n5-consolidacao-clientes-offline.md)
- **Origem:** `doc_dev/planejamento/20-fase-N5-consolidacao-clientes-offline.md` (agora histórico)

## Escopo (etapas)
| # | Foco | Estado base |
|---|---|---|
| **N5.1** | Consolidação do app (F7): navegação/estados/acessibilidade + empacotamento Windows | telas já existem — é refino |
| **N5.2** | `local_engine` FFI (F8): dual-target, SQLite, cache de mídia por hash, fila offline + sync | crate ausente — **risco-chave**, entregar em incrementos 8.1→8.5 |
| **N5.3** | Paridade Web (F10): app operacional/tenant na web + CORS de mídia no R2 | admin já roda em `/v2/admin` — incremental |

## Sequenciamento
**N5.1 → N5.2 (incrementos) → N5.3.** Correções da reestruturação (CORS obrigatório mesmo
com presigned URLs; gotchas de `AllowedOrigins`/`range`; `cors.json` versionado; revalidar
`flutter_rust_bridge` na fase P) no [plano completo](./n5-consolidacao-clientes-offline/plano_completo_n5-consolidacao-clientes-offline.md).

## Fases (PREVC)
- **P:** revalidar doc do `flutter_rust_bridge` (janela de ~90 dias vencida quando N5 iniciar); escopo dos incrementos FFI.
- **R:** aprovar dual-target + estratégia de sync + paridade web.
- **E:** F7 consolida; F8 FFI/offline em incrementos; F10 paridade web.
- **V:** `.\infra\test-flutter.ps1` — offline sem perda, troca de DataSource sem tocar telas, mídia web com CORS/range.
- **C:** app empacotado; encerramento do backlog N1–N5; gate `prevc-final-review`.

## Execution History

> Last updated: 2026-07-17T19:03:52.122Z | Progress: 0%
