# Padrões por Linguagem e Segurança

Índice dos documentos normativos de desenvolvimento por stack do **Smart Core
Assistant v2**. Cada documento define convenções de Clean Code, TDD, ferramentas
de qualidade e exemplos contextualizados ao projeto. O documento de segurança é
**transversal** e se aplica a todas as stacks.

> **Idioma (regra global):** código e identificadores em **inglês**; comentários,
> docstrings e documentação em **português pt-br** com acentuação correta.

## Documentos

| Documento | Stack / Escopo | Conteúdo principal |
|-----------|----------------|--------------------|
| [rust.md](./rust.md) | Backend (`server/`) | Clean Code em Rust, tratamento de erro sem pânico, async (Tokio/Axum), DDD, `TenantEnvelope`, TDD com banco real + RLS, clippy/rustfmt |
| [python.md](./python.md) | Motor de IA (`ia_engine/`) | Tipagem estrita (pyright), feature-first, Pydantic na fronteira gRPC, async, TDD com mocks de LLM, ruff/pyright/pytest com `uv` |
| [flutter.md](./flutter.md) | Frontend (`clients/`) | Cliente fino, abstração `DataSource` (LocalEngineFFI × RemoteOnly), estado imutável, dois apps (Windows/Web) + packages, TDD de widgets/unit |
| [seguranca.md](./seguranca.md) | **Transversal** | Isolamento multi-tenant (RLS), segredos/cifragem, auth, validação, segurança de IA/mídia, logging com privacidade, deploy, LGPD, checklist por PR |

## Como usar

- **Antes de implementar** em qualquer stack: leia o documento da linguagem
  correspondente **e** o [seguranca.md](./seguranca.md).
- **Em todo PR:** valide o checklist transversal de
  [02-fases-desenvolvimento.md](../planejamento/02-fases-desenvolvimento.md)
  (Apêndice A) **e** o [checklist de segurança](./seguranca.md#15-checklist-de-segurança-por-pr).
- **Fonte de verdade da arquitetura:** o
  [planejamento](../planejamento/00-planejamento-inicial.md) e a
  [estrutura do projeto](../planejamento/01-estrutura-do-projeto.md). Em caso de
  divergência, prevalece o planejamento.

## Convenções-chave compartilhadas

- **Comunicação entre stacks por contrato explícito** — nunca import direto:
  Flutter ↔ Rust por gRPC/HTTP + WebSocket (e FFI no Windows via `local_engine`);
  Rust (`worker`) ↔ Python (`ia_engine`) por **gRPC/HTTP**.
- **FFI existe apenas entre Flutter e Rust** (`local_engine` /
  `flutter_rust_bridge`). O `ia_engine` (Python) **não** usa FFI.
- **Cobertura mínima de testes:** 80% (`domain_*` em Rust e `ia_engine` em
  Python).
- **Nomenclatura de testes:** `test_should_<resultado>_when_<condição>`
  (Rust/Python) / `should <resultado> when <condição>` (Flutter), padrão AAA.
- **Git (gitflow):** branches a partir de `dev`; commits em inglês, sem
  `Co-Authored-By` nem rodapés de IA.
