---
name: prevc-planning
description: Fase P (Planning) do workflow PREVC - Definir o que construir. Ativar quando uma nova feature é solicitada, um bug complexo precisa ser investigado, ou uma refatoração planejada.
---

# PREVC - Planning (Fase P)

Workflow para a fase de planejamento do sistema PREVC.

## Objetivo

Definir o que construir, levantar requisitos e criar especificações.

## Quando Ativar

- Nova feature solicitada
- Bug complexo a investigar
- Refatoração planejada

## Skills Associados

- [feature-breakdown](../feature-breakdown/SKILL.md) - Decomposição de features
- [api-design](../api-design/SKILL.md) - Design de APIs
- [bug-investigation](../bug-investigation/SKILL.md) - Investigação de bugs

## Etapas

### 1. Entender o Contexto

```
1. Leia a solicitação/issue
2. Consulte .context/docs/project-overview.md
3. Identifique stakeholders e requisitos
4. Verifique doc_dev/ para documentação existente do projeto
```

### 2. Levantar Requisitos

Documente em `.context/workflow/docs/prd.md`:

- Requisitos funcionais
- Requisitos não-funcionais
- Restrições
- Dependências (Rust / Python / ambas)

### 3. Decompor em Tarefas

Use o skill `feature-breakdown`:

```
1. Identifique componentes principais (core Rust vs módulos Python)
2. Quebre em tarefas atômicas
3. Estime complexidade (T-shirt sizing)
4. Identifique dependências entre tarefas
5. Separe tarefas por camada (Rust core, Python agent, integração)
```

### 4. Especificação Técnica

Documente em `.context/workflow/docs/technical-spec.md`:

- Arquitetura proposta
- Interfaces/APIs (gRPC, REST, CLI)
- Modelos de dados
- Fluxos de dados
- Fronteira Rust ↔ Python (FFI / subprocess / gRPC)

### 5. Definir Critérios de Aceite

Para cada requisito:

```markdown
- [ ] Critério específico e mensurável
- [ ] Pode ser verificado objetivamente
- [ ] Tem escopo claro
```

## Outputs

| Arquivo | Descrição |
|---------|-----------|
| `prd.md` | Requisitos do produto |
| `technical-spec.md` | Especificação técnica |
| `tasks.md` | Lista de tarefas decompostas |

## Gate para Próxima Fase

Antes de ir para Review (R):

- [ ] PRD completo e revisado
- [ ] Spec técnica completa
- [ ] Tarefas decompostas
- [ ] Critérios de aceite definidos
- [ ] Stakeholders alinhados

## Atualizar Status

```yaml
# .context/workflow/status.yaml
phases:
  P:
    status: completed
    outputs:
      - path: ".context/workflow/docs/prd.md"
      - path: ".context/workflow/docs/technical-spec.md"
```

## Próxima Fase

→ [prevc-review](../prevc-review/SKILL.md)
