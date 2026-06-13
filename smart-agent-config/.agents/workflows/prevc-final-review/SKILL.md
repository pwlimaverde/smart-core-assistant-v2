---
name: prevc-final-review
description: Auditoria final pós-implementação (subagente Opus) que compara o que foi implementado contra o plano aprovado, corrige automaticamente os desvios (sem bloquear) e fecha o ciclo arquivando e commitando, deixando no relatório um resumo das correções. Gate obrigatório no início da fase C (Confirmation).
---

# PREVC - Final Review (Gate da Fase C)

Auditoria final da implementação **antes do arquivamento do plano**. Confronta o
**código implementado** contra o **plano aprovado** usando um subagente rodando o
modelo **Opus mais capaz**, **corrige** automaticamente os desvios encontrados,
revalida e então **arquiva e commita** — fechando o ciclo. O gate **não bloqueia**:
o procedimento é conferir → ajustar/corrigir o que precisar → arquivar → commitar,
sempre deixando no relatório um **resumo do que precisou ser corrigido**.

> **Idioma:** comunicação e relatório em Português; código e identificadores em Inglês.

## Quando Ativar

- Logo no início da fase **C (Confirmation)**, **antes** da etapa de arquivamento
  do plano descrita em [prevc-confirmation](../prevc-confirmation/SKILL.md).
- Sob demanda, via comando `/final-review`.

## Política de Execução (decidida pelo dono do projeto)

| Aspecto | Decisão |
|---------|---------|
| Correção | **Corrigir automaticamente** todos os desvios/erros encontrados — **nunca bloquear** o ciclo por desvio corrigível. |
| Conclusão | Após corrigir e revalidar, **arquivar o plano E commitar** as mudanças. O gate sempre fecha o ciclo. |
| Relatório | Mostrar um **resumo do que precisou ser corrigido** (não trava nada; é registro). |
| Disparo | Gate automático na fase C **e** comando manual `/final-review`. |

## Etapa 0 — Reunir Contexto (agente principal)

Antes de lançar o subagente, o agente principal coleta os insumos:

1. **Plano ativo:** ler `plans/plans.json` → campo `primary` (ou o `slug` em
   `active[]`). Carregar:
   - `.context/plans/<slug>.md` (plano principal)
   - `.context/plans/<slug>/` (info auxiliar e plano completo, se existir)
2. **Estado do workflow:** `.context/workflow/status.yaml` **e o status das fases
   internas do plano** (`status:` de cada fase no front-matter de `<slug>.md`).
   - **Fases pendentes → corrigir, não bloquear:** se alguma fase de execução do
     plano estiver `pending`/`in_progress`, o procedimento é **implementar/corrigir
     o que falta dentro do escopo do plano** (política de auto-correção) e então
     seguir para arquivar + commitar. Só registre como **pendência residual** no
     relatório aquilo que estiver genuinamente fora do escopo do plano ou que
     dependa de decisão externa — isso **não** trava o fechamento do ciclo.
   - Se `status.yaml` e o status das fases do plano se contradizerem (ex.: workflow
     diz `E=completed` mas o plano tem fases `pending`), **registrar a contradição
     no relatório**, alinhar o status real e seguir.
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
- Observabilidade: doc_dev/planejamento/05-observabilidade.md
- Auditoria/sanitização: doc_dev/modelagem_dados/08_diretrizes_seguranca.md (§4 e §4.2)
- Documentação de libs: doc_dev/libs/

TAREFA:
1. Para CADA item/objetivo do plano, verifique se foi implementado de fato no
   diff. Marque: ✅ feito conforme | ⚠️ feito com desvio | ❌ não feito | ➕ feito
   além do plano (escopo extra não planejado).
2. Audite o código alterado contra os padrões: Result Pattern, type hints
   (pyright strict para Python, tipos explícitos para Rust), docstrings Google,
   sem secrets hardcoded, sem N+1, sem código morto/TODO esquecido.
2b. OBSERVABILIDADE E AUDITORIA (requisito inviolável — ver
   doc_dev/planejamento/05-observabilidade.md e
   doc_dev/modelagem_dados/08_diretrizes_seguranca.md §4 e §4.2). Para cada
   comportamento novo/alterado no diff, verifique de fato no código:
     a) Logs/traces estruturados: emite spans/eventos via tracing (não println!),
        com correlação (tenant_id, trace_id) e error_code nos erros; política de
        instrumentação da infra respeitada (#[tracing::instrument(err)] só em
        falha real de infra; repositórios de tenant via run_in_tenant_transaction
        + #[instrument(skip_all)]).
     b) Auditoria no banco: toda mutação de estado sensível/crítico (Tenant/
        owner_id, TenantInvite, TenantUser/permissões, Subscription/PaymentRecord,
        chaves de API do TenantConfig, acesso a dados protegidos) gera registro
        de audit_log com metadados mínimos (timestamp UTC, user_id, ip_address,
        user_agent, event_type, descrição SEM o segredo), publicado pelo
        transport::bus. Falta de auditoria onde o plano/diretriz exige é DESVIO.
     c) Sanitização/não-vazamento: nenhum log expõe segredos, PII bruta (telefone
        completo, payloads do WhatsApp) ou tokens; structs com credenciais usam
        secrecy::SecretString/SecretVec. Logar segredo/PII é DESVIO crítico.
   Confronte com o que o plano declarou (seção "Observabilidade & Auditoria" das
   fases). Marque cada eixo: ✅ conforme | ⚠️ parcial | ❌ ausente.
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
- NÃO faça commit nem arquive o plano — o commit e o arquivamento são do agente
  principal (Etapa 3). Seu papel é deixar o código corrigido e revalidado.
- Política é AUTO-CORREÇÃO: corrija TUDO que encontrar, inclusive desvios grandes
  ou arriscados — nunca devolva um desvio sem corrigir. Se um desvio for grande/
  arriscado, corrija mesmo assim e destaque-o como ⚠️ "decisão tomada
  autonomamente" no relatório para revisão posterior.
- Produza sempre um RESUMO do que precisou ser corrigido (entra no relatório).
- Retorne no final: o relatório completo + rótulo (CONFORME = nada a corrigir |
  CORRIGIDO = havia desvios e foram corrigidos+revalidados). O rótulo é
  informativo — não bloqueia o arquivamento.
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

## Rótulo: CONFORME | CORRIGIDO  (informativo — não bloqueia o ciclo)

## Resumo das correções
- <1-3 linhas: o que precisou ser ajustado/corrigido neste ciclo, ou "nada a corrigir">

## 1. Plano vs. Implementado
| Item do plano | Status | Observação |
|---------------|--------|------------|
| ... | ✅/⚠️/❌/➕ | ... |

## 2. Correções Aplicadas
| Arquivo:linha | Problema | Correção |
|---------------|----------|----------|
| ... | ... | ... |

## 2b. Observabilidade & Auditoria
| Comportamento | Logs/Trace | Audit log | Sanitização | Observação |
|---------------|-----------|-----------|-------------|------------|
| ... | ✅/⚠️/❌ | ✅/⚠️/❌/N/A | ✅/⚠️/❌ | ... |

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

## Etapa 3 — Corrigir, Revalidar, Arquivar e Commitar

O gate **sempre fecha o ciclo** — não há veredito que bloqueie. Com o relatório do
subagente em mãos, o agente principal executa, em ordem:

1. **Garantir que as correções foram aplicadas e revalidadas** (lint + type-check
   limpos; clippy se houver Rust). Se algo ainda não estiver verde, **corrija
   aqui** — só não se commita código que não compila/builda (essa é a única
   exceção, e é rara: trate como bug a resolver, não como motivo para abandonar o
   ciclo). Pendências genuinamente fora do escopo do plano vão para a seção
   "Pendências" do relatório.
2. **Seguir a fase C** ([prevc-confirmation](../prevc-confirmation/SKILL.md)):
   changelog, docs e **arquivamento do plano** (mover a pasta para
   `.context/plans/archive/<slug>/`, atualizar status do workflow).
3. **Commitar** as mudanças do ciclo (código corrigido + plano arquivado +
   relatório), seguindo o GitFlow e o padrão de mensagens do projeto
   ([commit-message](../commit-message/SKILL.md)). **Sem** auto-referência ao
   agente na mensagem.

O **rótulo** (CONFORME / CORRIGIDO) é só registro do relatório:

- **CONFORME** — nada a corrigir; implementação batia com o plano.
- **CORRIGIDO** — havia desvios; foram corrigidos e revalidados antes de arquivar.

Em ambos os casos o fluxo é o mesmo: arquivar + commitar. O que precisou de
correção fica documentado no "Resumo das correções" e na tabela "Correções
Aplicadas" do relatório.

## Saída para a Fase C

Ao terminar (plano arquivado e commitado), o relatório fica registrado como output
da fase C:

```yaml
phases:
  C:
    outputs:
      - path: ".context/workflow/docs/final-review.md"
```
