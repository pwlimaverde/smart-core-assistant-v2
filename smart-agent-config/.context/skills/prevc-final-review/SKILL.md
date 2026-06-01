---
type: skill
name: PREVC Final Review
description: Auditoria final pós-implementação (subagente Opus) que compara o que foi implementado contra o plano aprovado, corrige desvios e libera o arquivamento. Gate obrigatório no início da fase C (Confirmation).
skillSlug: prevc-final-review
phases: [C]
skills: [code-review, security-audit]
trigger: auto
generated: 2026-05-31
status: filled
scaffoldVersion: "2.0.0"
---

# PREVC - Final Review (Gate da Fase C)

Auditoria final da implementação **antes do arquivamento do plano**. Confronta o
**código implementado** contra o **plano aprovado** usando um subagente rodando o
modelo **Opus mais capaz**, corrige automaticamente os desvios encontrados,
revalida e só então libera a fase C para arquivar o plano.

> **Idioma:** comunicação e relatório em Português; código e identificadores em Inglês.

## Quando Ativar

- Logo no início da fase **C (Confirmation)**, **antes** da etapa de arquivamento
  do plano descrita em [prevc-confirmation](../prevc-confirmation/SKILL.md).
- Sob demanda, via comando `/final-review`.

## Política de Execução (decidida pelo dono do projeto)

| Aspecto | Decisão |
|---------|---------|
| Correção | **Corrigir automaticamente** todos os desvios/erros encontrados. |
| Arquivamento | Após corrigir e **revalidar com sucesso**, **arquivar** o plano normalmente. |
| Disparo | Gate automático na fase C **e** comando manual `/final-review`. |

## Etapa 0 — Reunir Contexto (agente principal)

Antes de lançar o subagente, o agente principal coleta os insumos:

1. **Plano ativo:** ler `plans/plans.json` → campo `primary` (ou o `slug` em
   `active[]`). Carregar:
   - `.context/plans/<slug>.md` (plano principal)
   - `.context/plans/<slug>/` (info auxiliar e plano completo, se existir)
2. **Estado do workflow:** `.context/workflow/status.yaml` **e o status das fases
   internas do plano** (`status:` de cada fase no front-matter de `<slug>.md`).
   - **Pré-condição de completude:** o final-review só pode levar a arquivamento se
     **todas as fases de execução do plano estiverem concluídas** (nenhuma `pending`
     /`in_progress`). Se houver fases pendentes, o ciclo **não terminou** — o veredito
     será **INCOMPLETO** (ver Etapa 3) e o plano **não** é arquivado, mesmo que a
     auditoria do que já existe passe limpa.
   - Se `status.yaml` e o status das fases do plano se contradizerem (ex.: workflow
     diz `E=completed` mas o plano tem fases `pending`), **reportar a contradição** e
     tratar como INCOMPLETO.
3. **Critérios de aceite:** `.context/workflow/docs/prd.md` e
   `.context/workflow/docs/technical-spec.md`.
4. **Diff da implementação:** capturar tudo que mudou no ciclo. O trabalho pode
   estar **commitado** (na branch) e/ou **no working tree** (ainda não commitado);
   incluir os dois:
   ```bash
   git status --short            # mudanças não commitadas (working tree)
   git diff                      # diff working tree (unstaged)
   git diff --stat master...HEAD # commits do ciclo vs main branch (master)
   ```
   **Escopo:** se a branch acumula trabalho heterogêneo (assuntos fora do plano),
   **não auditar o diff inteiro** — restringir aos caminhos que o plano declara
   tocar (ex.: os apps/módulos citados no plano). Passar ao subagente apenas o
   diff desses caminhos:
   ```bash
   git diff -- <path1> <path2> ...
   git diff master...HEAD -- <path1> <path2> ...
   ```
   Itens fora do escopo do plano vão para a seção "Pendências" do relatório, não
   são corrigidos.

## Etapa 1 — Lançar Subagente de Auditoria (Opus)

O agente principal lança **um subagente** com a ferramenta `Agent`:

- `subagent_type: general-purpose`
- **`model: opus`** (obrigatório — usar o Opus mais capaz disponível)
- `description: "Auditoria final do plano <slug>"`

**Prompt do subagente** (preencher os `<...>`):

```
Você é um revisor sênior. Audite a implementação do ciclo PREVC contra o plano
aprovado e CORRIJA os desvios encontrados. Idioma: Português; código em Inglês.

CONTEXTO (já anexado abaixo / leia os arquivos indicados):
- Plano aprovado: .context/plans/<slug>.md  (+ pasta .context/plans/<slug>/)
- PRD e spec: .context/workflow/docs/prd.md, .context/workflow/docs/technical-spec.md
- Diff do ciclo: git diff master...HEAD
- Padrões do projeto: AGENTS.md, .context/docs/architecture.md
- Checklist de qualidade: .context/skills/code-review/SKILL.md
- Segurança: .context/skills/security-audit/SKILL.md
- Documentação de libs: doc_dev/libs/

TAREFA:
1. Para CADA item/objetivo do plano, verifique se foi implementado de fato no
   diff. Marque: ✅ feito conforme | ⚠️ feito com desvio | ❌ não feito | ➕ feito
   além do plano (escopo extra não planejado).
2. Audite o código alterado contra os padrões: Result Pattern, type hints
   (pyright strict para Python, tipos explícitos para Rust), docstrings Google,
   sem secrets hardcoded, sem N+1, sem código morto/TODO esquecido.
3. CORRIJA automaticamente todos os desvios e erros encontrados (edite os arquivos).
   Para cada correção, registre arquivo:linha e o motivo.
4. Revalide após corrigir:
     uv run task lint
     uv run task type-check
     cargo clippy -- -D warnings  (se houver código Rust)
   Repita correção+revalidação até lint e type-check passarem limpos.
5. Produza um relatório em Markdown (estrutura na seção "Relatório" abaixo).

REGRAS:
- NÃO crie testes automatizados (diretriz do projeto).
- NÃO faça commit nem arquive o plano — isso é responsabilidade do agente principal.
- Se algum desvio for arquiteturalmente grande e arriscado de corrigir sozinho,
  CORRIJA mesmo assim (política do projeto é auto-correção) mas destaque-o como
  ⚠️ "decisão tomada autonomamente" no relatório para revisão posterior.
- Retorne no final: o relatório completo + veredito (CONFORME / CORRIGIDO / FALHOU).
```

> Se o diff for muito grande, o agente principal pode fatiar a auditoria por módulo
> e lançar o subagente por área — mas o relatório final deve ser consolidado.

## Etapa 2 — Consolidar e Persistir o Relatório

Salvar o relatório retornado pelo subagente em:

```
.context/workflow/docs/final-review.md
```

### Estrutura do Relatório

```markdown
# Final Review — <slug>
Data: <YYYY-MM-DD> · Modelo: Opus · Diff: master...HEAD

## Veredito: CONFORME | CORRIGIDO | FALHOU

## 1. Plano vs. Implementado
| Item do plano | Status | Observação |
|---------------|--------|------------|
| ... | ✅/⚠️/❌/➕ | ... |

## 2. Correções Aplicadas
| Arquivo:linha | Problema | Correção |
|---------------|----------|----------|
| ... | ... | ... |

## 3. Decisões Autônomas (revisar depois)
- ...

## 4. Revalidação
- lint: ✅/❌
- type-check: ✅/❌
- clippy (Rust): ✅/❌/N/A
- testes: ✅/❌/N/A

## 5. Pendências (escopo extra ou fora do plano)
- ...
```

## Etapa 3 — Liberar (ou bloquear) o Arquivamento

Vereditos possíveis:

- **CONFORME** — plano completo, implementação bate, lint + type-check limpos.
- **CORRIGIDO** — plano completo, havia desvios; foram corrigidos e revalidados.
- **INCOMPLETO** — há fases do plano ainda `pending`/`in_progress` (a auditoria do
  que já existe pode até estar limpa, mas o ciclo não terminou).
- **FALHOU** — não foi possível deixar lint/type-check limpos no escopo.

Ações:

- **CONFORME** / **CORRIGIDO** → seguir a fase C (changelog, docs, **arquivar plano**,
  atualizar status).
- **INCOMPLETO** → **não arquivar**. O relatório vira um checkpoint de qualidade do
  trabalho parcial; reportar ao dono do projeto as fases que faltam para fechar o ciclo.
- **FALHOU** → **não arquivar**; reportar o que travou, com o relatório.

## Saída para a Fase C

Ao terminar, o agente principal retoma [prevc-confirmation](../prevc-confirmation/SKILL.md)
a partir da etapa de changelog/arquivamento, anexando o caminho do relatório como output:

```yaml
phases:
  C:
    outputs:
      - path: ".context/workflow/docs/final-review.md"
```
