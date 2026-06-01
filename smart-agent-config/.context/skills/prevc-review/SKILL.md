---
type: skill
name: PREVC Review
description: Fase R (Review) do workflow PREVC - Validar approach e arquitetura. Ativar após conclusão da fase P (Planning), quando PRD e spec técnica estão prontos.
skillSlug: prevc-review
phases: [R]
skills: [code-review, security-audit]
trigger: auto
generated: 2026-05-31
status: filled
scaffoldVersion: "2.0.0"
---

# PREVC - Review (Fase R)

Workflow para a fase de revisão do sistema PREVC.

## Objetivo

Validar o approach técnico, revisar arquitetura e avaliar riscos.

## Quando Ativar

- Após conclusão da fase P (Planning)
- PRD e spec técnica estão prontos
- Antes de iniciar implementação

## Skills Associados

- [code-review](../code-review/SKILL.md) - Revisão de código/design
- [security-audit](../security-audit/SKILL.md) - Auditoria de segurança

## Etapas

### 1. Revisar Especificações

```
1. Leia .context/workflow/docs/prd.md
2. Leia .context/workflow/docs/technical-spec.md
3. Verifique completude e clareza
```

### 2. Validar Arquitetura

Consulte `.context/docs/architecture.md` e verifique:

- Compatibilidade com arquitetura existente
- Padrões sendo seguidos (Result Pattern, modularidade)
- Impacto em módulos existentes
- Fronteira Rust ↔ Python bem definida

### 3. Avaliação de Riscos

Identifique e documente:

```markdown
## Riscos Identificados

| Risco | Probabilidade | Impacto | Mitigação |
|-------|---------------|---------|-----------|
| Risco 1 | Alta | Alto | Ação X |
| Risco 2 | Média | Baixo | Ação Y |
```

### 4. Security Review

Use o skill `security-audit`:

- Verifique OWASP Top 10
- Avalie superfície de ataque
- Identifique dados sensíveis
- Verifique gerenciamento de segredos (.env)

### 5. Criar ADRs (se necessário)

Para decisões arquiteturais significativas:

```markdown
# ADR-XXX: Título da Decisão

## Status
Proposto

## Contexto
Descrição do problema...

## Decisão
O que foi decidido...

## Consequências
Impactos positivos e negativos...
```

## Outputs

| Arquivo | Descrição |
|---------|-----------|
| `architecture.md` | Documento de arquitetura atualizado |
| `adr/*.md` | Architecture Decision Records |
| `risk-assessment.md` | Avaliação de riscos |

## Gate para Próxima Fase

Antes de ir para Execution (E):

- [ ] Arquitetura validada
- [ ] Riscos avaliados e mitigados
- [ ] Security review concluído
- [ ] ADRs criados (se aplicável)
- [ ] Aprovação do Tech Lead

## Atualizar Status

```yaml
# .context/workflow/status.yaml
phases:
  R:
    status: completed
    outputs:
      - path: ".context/workflow/docs/architecture.md"
```

## Próxima Fase

→ [prevc-execution](../prevc-execution/SKILL.md)
