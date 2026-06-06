---
type: skill
name: PREVC Execution
description: Fase E (Execution) do workflow PREVC - Construir o que foi planejado. Ativar após conclusão da fase R (Review), quando design e arquitetura estão aprovados.
skillSlug: prevc-execution
phases: [E]
skills: [commit-message, refactoring, documentation]
trigger: auto
generated: 2026-05-31
status: filled
scaffoldVersion: "2.0.0"
---

# PREVC - Execution (Fase E)

Workflow para a fase de execução do sistema PREVC.

## Objetivo

Implementar o código seguindo as especificações aprovadas.

## Quando Ativar

- Após conclusão da fase R (Review)
- Design e arquitetura aprovados
- Pronto para implementar

## Skills Associados

- [commit-message](../commit-message/SKILL.md) - Mensagens de commit
- [refactoring](../refactoring/SKILL.md) - Refatoração segura
- [documentation](../documentation/SKILL.md) - Documentação

## Etapas

### 1. Preparar Ambiente

```bash
# Verificar branch
git checkout -b feature/[nome-da-feature]

# Atualizar dependências Python
uv sync --dev

# Atualizar dependências Rust (se aplicável)
cargo build
```

### 2. Implementar Tarefa

Para cada tarefa em `tasks.md`:

```
1. Leia a spec da tarefa
2. Implemente seguindo padrões:
   - Rust: clippy, rustfmt, tipos explícitos
   - Python: PEP8, type hints (pyright strict), docstrings Google style
3. Mantenha código em Inglês
4. Comentários em Português
5. Consulte doc_dev/ para padrões de libs específicas
```

### 3. Verificar Qualidade

```bash
# Python - Formatar
uv run task format

# Python - Lint
uv run task lint

# Python - Type check
uv run task type-check

# Rust - Verificar
cargo clippy -- -D warnings
cargo fmt --check
```

### 4. Commit

Use o skill `commit-message`:

```bash
git add [arquivos]
git commit -m "feat(modulo): descrição

Detalhes da implementação.

Refs: #issue"
```

### 5. Atualizar Progresso

Marque tarefas concluídas em `tasks.md`:

```markdown
- [x] Tarefa 1 - Concluída
- [ ] Tarefa 2 - Em progresso
- [ ] Tarefa 3 - Pendente
```

## Padrões de Código

### Python - Estrutura de Arquivos

```python
"""
Docstring do módulo em Português.
"""
from typing import Any


# Constantes
MAX_LENGTH = 100


# Classes e funções
class MyClass:
    """Docstring da classe."""

    def my_method(self, param: str) -> None:
        """Docstring do método."""
        pass
```

### Rust - Estrutura de Arquivos

```rust
//! Documentação do módulo em Português.

use std::error::Error;

/// Documentação da struct.
pub struct MyStruct {
    /// Campo documentado.
    pub field: String,
}

impl MyStruct {
    /// Documentação do método.
    pub fn new(field: String) -> Self {
        Self { field }
    }
}
```

### Imports em `__init__.py`

```python
"""Descrição do módulo."""
from .feature import FeatureClass

__all__ = ["FeatureClass"]
```

## Outputs

- Código implementado
- Commits seguindo Conventional Commits
- `tasks.md` atualizado

## Gate para Próxima Fase

Antes de ir para Validation (V):

- [ ] Todas as tarefas implementadas
- [ ] Código formatado e linted
- [ ] Type check passando (Python + Rust)
- [ ] Commits organizados

## Atualizar Status

```yaml
# .context/workflow/status.yaml
phases:
  E:
    status: completed
```

## Próxima Fase

→ [prevc-validation](../prevc-validation/SKILL.md)
