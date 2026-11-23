---
description: "Liga, desliga ou mostra o roteador de modelo e o seletor de skill (on | skills | off | status)"
disable-model-invocation: true
argument-hint: on | skills | off | status
allowed-tools: Bash(command -v py:*), Bash(py -3:*), Bash(python3:*)
---

!`if command -v py >/dev/null 2>&1; then py -3 "${CLAUDE_PROJECT_DIR:-.}/.claude/hooks/roteador.py" --cli $ARGUMENTS; else python3 "${CLAUDE_PROJECT_DIR:-.}/.claude/hooks/roteador.py" --cli $ARGUMENTS; fi`

Mostre ao usuário a saída acima, sem comentar nem executar mais nada.
