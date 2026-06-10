---
name: documentation
description: Generate and update technical documentation. Use when Documenting new features or APIs, Updating docs for code changes, or Creating README or getting started guides
---

## Workflow

1. Identifique o público e o lugar certo: doc comment no código, `doc_dev/` (planejamento) ou `.context/docs/` (snapshot p/ agentes)
2. Escreva em **pt-br com acentuação correta**; identificadores e nomes de arquivos em inglês
3. Documente o *porquê* e as invariantes — não repita o que o código já mostra
4. Inclua exemplos funcionais na linguagem certa (Rust `///`, Python docstring, Dart `///`)
5. Atualize a doc no mesmo PR da mudança de código
6. Mudança arquitetural → refletir em `.context/docs/architecture.md` e no plano em `doc_dev/`

## Examples

**Rust (doc comment em pt-br):**
```rust
/// Decide a política de ticket para uma mensagem recebida.
///
/// Reaproveita ticket ativo (`FILA`/`EM_ATENDIMENTO`/`PENDENCIA`);
/// dentro da janela de reabertura trata como feedback; fora dela,
/// cria um novo atendimento.
pub fn decidir_politica_ticket(ctx: &TicketContext) -> TicketDecision { ... }
```

**Python (docstring em pt-br):**
```python
def transcrever_audio(pointer: MediaPointer) -> str:
    """Transcreve o áudio apontado pelo MediaPointer.

    O binário é lido do storage transitório (R2); o resultado vira
    `analise_midia` na mensagem. Lança AudioFormatError para mimetype
    não suportado.
    """
```

## Quality Bar

- Comentários/docstrings em pt-br; código e identificadores em inglês
- Exemplos compiláveis/copiáveis e coerentes com o código atual
- Regras de domínio críticas documentadas com exemplo concreto (política de ticket, janela de reabertura, bot bloqueado)
- Sem duplicação: `doc_dev/` é o planejamento canônico; `.context/docs/` resume e aponta para ele
- Sem referências a artefatos de build ou arquivos temporários

## Resource Strategy

- Add `scripts/` only when the task is fragile, repetitive, or benefits from deterministic execution.
- Add `references/` only when details are too large or too variant-specific to keep in `SKILL.md`.
- Add `assets/` only for files that will be consumed in the final output.
- Keep extra docs out of the skill folder; prefer `SKILL.md` plus only the resources that materially help.
