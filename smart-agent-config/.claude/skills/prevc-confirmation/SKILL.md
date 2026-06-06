---
name: prevc-confirmation
description: Fase C (Confirmation) do workflow PREVC - Entregar e documentar. Ativar após conclusão da fase V (Validation), com testes passando e PR mergeado. Inclui gate obrigatório de final-review antes do arquivamento.
---

# PREVC - Confirmation (Fase C)

Workflow para a fase de confirmação do sistema PREVC.

## Objetivo

Documentar a entrega, atualizar changelog e fazer handoff.

## Quando Ativar

- Após conclusão da fase V (Validation)
- Testes passando
- PR mergeado

## Skills Associados

- [prevc-final-review](../prevc-final-review/SKILL.md) - **Gate obrigatório**: auditoria final (subagente Opus) antes de arquivar
- [documentation](../documentation/SKILL.md) - Documentação
- [commit-message](../commit-message/SKILL.md) - Mensagens de commit

## Etapas

### 0. Gate de Final Review (OBRIGATÓRIO antes de arquivar)

**Antes de qualquer outra etapa desta fase**, executar o skill
[prevc-final-review](../prevc-final-review/SKILL.md):

1. Lançar subagente com **modelo Opus** que carrega o plano aprovado e audita o
   diff da implementação (`git diff master...HEAD`) contra o planejado.
2. O subagente **corrige automaticamente** todos os desvios/erros e revalida
   (`lint`, `type-check`, testes existentes).
3. O relatório é salvo em `.context/workflow/docs/final-review.md`.

> **Não prosseguir para o arquivamento (etapa 5) enquanto o veredito não for
> CONFORME ou CORRIGIDO.** Se for FALHOU, parar e reportar ao dono do projeto.

### 1. Atualizar Documentação

Se necessário, atualize:

```
.context/docs/
├── architecture.md     # Mudanças arquiteturais
├── data-flow.md        # Novos fluxos de dados
├── glossary.md         # Novos termos
└── tooling.md          # Novas ferramentas

doc_dev/
├── libs/               # Documentação de bibliotecas atualizadas
└── planejamento/       # Planos concluídos
```

### 2. Gerar Changelog

Adicione entrada em `.context/workflow/docs/changelog.md`:

```markdown
## [YYYY-MM-DD] - Nome da Feature

### Adicionado
- Nova feature X
- Endpoint Y

### Modificado
- Refatoração do módulo Z

### Corrigido
- Bug W corrigido
```

### 3. Atualizar README (se necessário)

Se a feature adiciona comandos ou configurações novas, atualize o README relevante.

### 4. Notificar Stakeholders

- Comunicar conclusão
- Documentar onde encontrar a feature
- Fornecer instruções de uso

### 5. Arquivar Plano

Mova o plano para arquivo:

```bash
git mv .context/plans/[nome]/ .context/plans/archive/[data]-[nome]/
```

### 6. Atualizar Status Final

```yaml
# .context/workflow/status.yaml
phases:
  C:
    status: completed
    outputs:
      - path: ".context/workflow/docs/changelog.md"

history:
  - phase: C
    status: completed
    timestamp: "YYYY-MM-DDTHH:MM:SSZ"
    notes: "[Nome da feature] entregue"
```

## Outputs

| Arquivo | Descrição |
|---------|-----------|
| `changelog.md` | Changelog atualizado |
| Documentação | Docs atualizados |
| Plano arquivado | Em `.context/plans/archive/` |

## Checklist Final

- [ ] **Final review executado (subagente Opus) — veredito CONFORME/CORRIGIDO**
- [ ] **Relatório salvo em `.context/workflow/docs/final-review.md`**
- [ ] Documentação atualizada
- [ ] Changelog gerado
- [ ] README atualizado (se aplicável)
- [ ] Stakeholders notificados
- [ ] Plano arquivado
- [ ] Status atualizado

## Conclusão

Após esta fase, o ciclo PREVC está completo:

```
✅ P (Planning) - Completo
✅ R (Review) - Completo
✅ E (Execution) - Completo
✅ V (Validation) - Completo
✅ C (Confirmation) - Completo
```

## Reset para Próximo Ciclo

```yaml
# .context/workflow/status.yaml
current_phase: P
phases:
  P:
    status: pending
  R:
    status: pending
  E:
    status: pending
  V:
    status: pending
  C:
    status: pending
```

## Referências

- [Workflow Status](../../.context/workflow/status.yaml)
- [Plans Archive](../../.context/plans/archive/)
- [Documentation Index](../../.context/docs/README.md)
