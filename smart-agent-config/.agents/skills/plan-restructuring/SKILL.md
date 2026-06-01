---
name: plan-restructuring
description: Etapa final de qualquer planejamento. Normaliza a origem do plano (conversa, doc_dev ou .context/plans) em um diretório próprio dentro de .context/plans/{feature}/, levanta libs internas e serviços externos, coleta documentação atual (context7 + WebSearch/WebFetch) em info_aux_{feature}.md, reestrutura o plano completo, e por fim cria o plano canônico via MCP dotcontext (scaffoldPlan + workflow-init) referenciando esses arquivos e deixando o workflow pronto para implementação. Na conclusão, consolida o canônico dentro da pasta e move tudo para archive/.
---

# Plan Restructuring Skill

## Quando Usar

Use **sempre como etapa FINAL** de qualquer planejamento, depois que o plano
inicial já existe. O objetivo duplo é:

1. Validar e corrigir o plano contra a documentação **atual** das libs e
   serviços externos envolvidos (evitando APIs/sintaxe/endpoints desatualizados).
2. **Normalizar** a origem do plano para um formato único e rastreável,
   independente de onde o plano nasceu.

NÃO é para criar o plano do zero — para isso use `/plan` / `feature-breakdown`.

## Origem do Plano (qualquer uma é tratada igual)

O plano-base pode vir de três lugares; todos seguem o **mesmo** procedimento:

- **(a) Só na conversa** — plano elaborado na sessão atual, ainda não salvo.
- **(b) Em `doc_dev/`** — ex.: `doc_dev/planejamento/.../plano_xyz.md`.
- **(c) Já em `.context/plans/`** — plano avulso a ser canonizado.

Em todos os casos, o conteúdo-base é a **entrada** e o resultado é a estrutura
padronizada descrita abaixo.

## Estrutura de Saída Padronizada

Para cada plano, cria-se um **diretório próprio** dentro de `.context/plans/`:

**Durante a execução** (plano ativo):

```
.context/plans/
├── {feature}.md                          # plano CANÔNICO do MCP (frontmatter PREVC + fases)
└── {feature}/                            # diretório de artefatos detalhados
    ├── info_aux_{feature}.md             # documentação coletada (libs + serviços externos)
    └── plano_completo_{feature}.md       # plano reestruturado detalhado (verdade técnica)
```

**Após a conclusão** (plano arquivado — ver etapa 7):

```
.context/plans/
└── archive/
    └── {feature}/                        # pasta inteira movida para cá
        ├── {feature}.md                  # canônico consolidado dentro da pasta
        ├── info_aux_{feature}.md
        └── plano_completo_{feature}.md
```

- `{feature}` é um slug kebab-case (ex.: `refatoracao-modular-atendimento`).
- O **plano canônico** (`{feature}.md`) é leve: frontmatter de fases PREVC e
  ponteiros para os dois arquivos detalhados. É ele que o MCP linka ao workflow.
- O **plano completo** (`{feature}/plano_completo_{feature}.md`) carrega o
  detalhamento técnico, etapas e exemplos de código.
- O `info_aux_{feature}.md` é a referência permanente de docs externas,
  consultável durante toda a implementação.
- Na execução o canônico fica **fora** da pasta (o MCP resolve por slug em
  `.context/plans/{slug}.md`); só ao concluir ele é consolidado **dentro** da
  pasta, que então migra para `archive/`.

## Estratégia de Modelos (automática via subagentes)

A skill **não** troca o modelo da sua sessão. Delega cada etapa pesada a um
subagente com modelo fixo, via ferramenta `Agent` (parâmetro `model`):

| Etapa | Trabalho | Executor | Modelo |
|-------|----------|----------|--------|
| 1. Normalização + levantamento | Identifica origem, slug, libs, serviços | Sessão principal | (atual) |
| 2a. Docs de libs (packages) | Context7 — coleta/sumarização | Subagente(s) paralelos | `haiku` |
| 2b. Docs de serviços externos | WebSearch + WebFetch — coleta | Subagente(s) paralelos | `haiku` |
| 3. Consolidar info_aux | Gravar `{feature}/info_aux_{feature}.md` | Sessão principal | (atual) |
| 4. Reestruturação | Plano completo detalhado | Subagente | `opus` |
| 5. Canonização MCP | scaffoldPlan + workflow-init + link | Sessão principal | (atual) |
| 7. Arquivamento | Consolidar na pasta + mover p/ archive | Sessão principal | (atual) |

## Etapas

### 1. Normalização da Origem + Levantamento (sessão principal)

1. **Identifique a origem** (a/b/c acima) e obtenha o conteúdo-base.
2. **Defina o slug `{feature}`** (kebab-case, descritivo, estável).
3. **Crie o diretório** de artefatos: `.context/plans/{feature}/`.
4. **Levante as dependências externas** em dois grupos:

#### Grupo A — Pacotes/Libs (gerenciados pelo projeto)

Cruze com os manifests do projeto para capturar versões fixadas:

```bash
# Python
cat pyproject.toml

# Rust
cat Cargo.toml
```

Formato:

```
Python:
- langchain (0.3.x)   -> chains, runnables
- pydantic (2.x)      -> validators, model_config

Rust:
- tokio (1.x)         -> async runtime
- serde (1.x)         -> serialization/deserialization
```

Para cada lib, anote **quais recursos/APIs específicos** o plano usa.

#### Grupo B — Serviços Externos e APIs de Terceiros

Identifique **qualquer coisa fora do código** com que o plano interage:

- **APIs REST/GraphQL externas**: Evolution Go (WhatsApp), Trello, Slack, OpenAI…
- **Serviços de mensageria/webhooks**: SSE, callbacks, filas externas
- **Plataformas SaaS** acessadas via HTTP/SDK
- **Integrações de protocolo**: AMQP, gRPC, WebSocket sobre serviços externos

Para cada serviço anote: nome, URL base, endpoints/recursos citados, tipo de
autenticação e versão/release (cruzando com `.env`/configs do projeto). Formato:

```
- Evolution Go API (v2.3.x, http://host:8080)
    -> POST /message/sendText, GET /instance/fetchInstances
    -> Auth: header apikey (token da instância)
- Trello API (v1, https://api.trello.com/1)
    -> GET /cards/{id}, POST /cards, PUT /cards/{id}
    -> Auth: key + token query params
```

### 2a. Docs de Libs — Context7 (subagentes `haiku` paralelos)

Para cada lib do Grupo A, dispare um subagente barato. Faça as chamadas paralelas
em uma única mensagem com vários blocos `Agent`.

```
Agent({
  description: "Docs atuais de <lib>",
  subagent_type: "general-purpose",
  model: "haiku",
  prompt: `
    Use o MCP context7 para coletar a documentação ATUAL da biblioteca <lib>
    (versão <versão>), focando APENAS nestes recursos: <lista de APIs/recursos>.

    Passos:
    1. resolve-library-id com o nome oficial da lib (formato /org/project; se a
       versão for conhecida, prefira /org/project/versão).
    2. query-docs com esse library ID e uma query específica por recurso.
    3. NÃO despeje a doc inteira. Retorne resumo objetivo:
       - Assinaturas/sintaxe ATUAIS dos recursos pedidos (com mini-exemplo).
       - APIs depreciadas/removidas relevantes ao plano.
       - Breaking changes que afetem a implementação.
       - O library ID usado (rastreabilidade).
    Seja conciso. Relatório em Português.
  `
})
```

### 2b. Docs de Serviços Externos — WebSearch/WebFetch (subagentes `haiku` paralelos)

Para cada serviço do Grupo B, dispare um subagente barato **em paralelo** com os
da 2a. Foco: endpoints, exemplos de código e formas corretas de acesso —
especialmente para serviços que o Context7 não indexa (Evolution Go, APIs
proprietárias, etc.).

```
Agent({
  description: "Docs atuais de <serviço externo>",
  subagent_type: "general-purpose",
  model: "haiku",
  prompt: `
    Colete documentação ATUAL e exemplos práticos do serviço:
    <nome> (URL base: <url>, versão: <versão se conhecida>)

    Endpoints/recursos de interesse: <lista do Grupo B>

    Estratégia:
    1. WebFetch direto na doc oficial se a URL for conhecida (README GitHub,
       docs.servico.com, swagger/openapi).
    2. Senão, WebSearch:
       "<serviço> API <versão> <endpoint> documentation"
       "<serviço> <endpoint> example curl python"
    3. Para cada endpoint/recurso colete:
       - URL completa (método HTTP + path)
       - Headers obrigatórios (auth, Content-Type…)
       - Body da requisição (schema/exemplo)
       - Resposta (campos relevantes)
       - Exemplo funcional (curl OU Python requests/httpx)
       - Erros comuns e tratamento
       - Limitações (rate limit, tamanho máximo…)
    4. Note breaking changes recentes (changelog/release notes) que afetem os
       endpoints do plano.
    5. Priorize fontes oficiais: repo GitHub, doc publicada, OpenAPI/Swagger.

    Relatório estruturado em Português, com seções por endpoint/recurso e snippets
    de código funcionais. Seja detalhado — vira material de implementação.
  `
})
```

Colete os relatórios de todos os subagentes (2a + 2b) antes de seguir.

### 3. Consolidar `info_aux.md` (sessão principal)

Consolide todos os relatórios das etapas 2a/2b em
`.context/plans/{feature}/info_aux_{feature}.md`:

```markdown
# Documentação Auxiliar — {Nome do Plano}

> Gerado em: {data}
> Plano canônico: `.context/plans/{feature}.md`
> Plano completo: `.context/plans/{feature}/plano_completo_{feature}.md`

## Libs Python
### {lib} ({versão})
{relatório da etapa 2a}

## Libs Rust
### {lib} ({versão})
{relatório da etapa 2a}

## Serviços Externos
### {nome do serviço} ({versão/URL base})
#### Autenticação
{como autenticar}
#### Endpoints
##### `METHOD /path/endpoint`
- **Descrição / Headers / Body / Resposta**
- **Exemplo:**
  ```python
  # código funcional
  ```
- **Erros comuns / Limitações**

## Notas Gerais
{breaking changes, gotchas, limitações}
```

### 4. Reestruturação — Plano Completo (subagente `opus`)

Dispare **um** subagente caro, passando o conteúdo-base + o caminho do `info_aux`.
Ele devolve o plano completo reestruturado.

```
Agent({
  description: "Reestruturar plano completo com docs atuais",
  subagent_type: "general-purpose",
  model: "opus",
  prompt: `
    REESTRUTURE um plano de implementação usando docs ATUAIS de libs e serviços
    externos. Comunique-se em Português.

    Plano base (origem: conversa / doc_dev / .context):
    <conteúdo-base>

    Documentação auxiliar (libs + serviços externos):
    <conteúdo de .context/plans/{feature}/info_aux_{feature}.md>

    Tarefas:
    1. Compare cada passo do plano com a documentação atual.
    2. Corrija libs Python: APIs depreciadas/removidas, assinaturas erradas,
       imports obsoletos, padrões que mudaram de versão.
    3. Corrija libs Rust: traits depreciados, APIs instáveis que estabilizaram,
       padrões de erro atualizados.
    4. Corrija integrações externas: endpoints incorretos, headers faltando,
       formatos de body errados, autenticação desatualizada.
    5. Enriqueça as etapas de integração com exemplos de código atualizados
       extraídos do info_aux.
    6. Respeite a arquitetura (ver .context/docs/architecture.md).
       Não invente libs novas sem necessidade.
    7. Estruture o plano em FASES claras (cada uma mapeável a uma fase PREVC e a
       um agente especialista), pois servirão de base ao plano canônico do MCP.
    8. Adicione seção "Correções aplicadas": o que mudou, por quê e a fonte.

    Devolva o PLANO COMPLETO reestruturado em markdown, pronto para salvar.
  `
})
```

Salve o retorno em `.context/plans/{feature}/plano_completo_{feature}.md`.

### 5. Canonização no MCP dotcontext (sessão principal)

Com `info_aux.md` e `plano_completo.md` prontos, crie o plano **canônico** e
prepare o workflow para implementação:

1. **Scaffold do plano canônico** (gera `.context/plans/{feature}.md`):

   ```
   context({ action: "scaffoldPlan", planName: "{feature}",
             title: "<título>", summary: "<resumo do objetivo>", autoFill: false })
   ```

2. **Edite o plano canônico** gerado para:
   - Referenciar os artefatos detalhados:
     `.context/plans/{feature}/plano_completo_{feature}.md` e
     `.context/plans/{feature}/info_aux_{feature}.md`.
   - Transcrever as **fases** definidas na etapa 4 para o frontmatter PREVC
     (id, name, prevc, agent, status) — espelhando o formato dos planos canônicos
     existentes em `.context/plans/`.

3. **Inicialize o workflow PREVC** (escolha a escala pela complexidade):

   ```
   workflow-init({ name: "{feature}", scale: "MEDIUM|LARGE",
                   description: "<descrição p/ detecção de escala>" })
   ```

4. **Linke o plano ao workflow**:

   ```
   plan({ action: "link", planSlug: "{feature}" })
   ```

5. **Avance o workflow para implementação** (fase E), registrando os outputs:

   ```
   workflow-advance({ outputs: [
     ".context/plans/{feature}.md",
     ".context/plans/{feature}/plano_completo_{feature}.md",
     ".context/plans/{feature}/info_aux_{feature}.md"
   ]})
   ```

   Repita `workflow-advance` conforme os gates (P→R→E) até a fase de execução,
   ou use `workflow-manage({ action: "setAutonomous", enabled: true })` se o
   fluxo for autônomo.

6. **Sincronize o tracking com o markdown** do plano canônico:

   ```
   plan({ action: "syncMarkdown", planSlug: "{feature}" })
   ```

### 6. Fechamento da Reestruturação (sessão principal)

1. Mostre ao usuário um resumo das **correções aplicadas** (seção da etapa 4).
2. Confirme a estrutura final criada (plano canônico + diretório de artefatos).
3. Se a origem era `doc_dev/`, deixe claro que a fonte da verdade agora é o
   plano canônico em `.context/plans/` (o arquivo em `doc_dev/` vira histórico).

> A partir daqui o plano fica **ativo** com o canônico FORA da pasta (necessário
> para o MCP resolvê-lo por slug durante a execução). A etapa 7 só é disparada
> quando o plano é **concluído**.

### 7. Arquivamento na Conclusão (sessão principal)

Dispare esta etapa **apenas quando o plano for concluído** (todas as fases PREVC
fechadas / workflow finalizado). O objetivo é manter tudo de um plano junto.

1. **Marque o plano como concluído** no MCP (se ainda não estiver):

   ```
   plan({ action: "updatePhase", planSlug: "{feature}", phaseId: "<última>", status: "completed" })
   plan({ action: "syncMarkdown", planSlug: "{feature}" })
   ```

2. **Consolide o canônico DENTRO da pasta** — mova `{feature}.md` para
   `{feature}/`:

   ```bash
   git mv .context/plans/{feature}.md .context/plans/{feature}/{feature}.md
   ```

3. **Mova a pasta inteira para `archive/`**:

   ```bash
   git mv .context/plans/{feature} .context/plans/archive/{feature}
   ```

   Resultado final:

   ```
   .context/plans/archive/{feature}/
   ├── {feature}.md
   ├── info_aux_{feature}.md
   └── plano_completo_{feature}.md
   ```

4. **Use `git mv`** (não `mv` cru) para preservar histórico. Se algum arquivo não
   estiver versionado, mova com a ferramenta de arquivos normalmente.
5. Confirme ao usuário que o plano foi arquivado com todos os artefatos juntos.

> Observação: como o canônico saiu de `.context/plans/{feature}.md`, o MCP não o
> resolverá mais por slug — o que é o comportamento esperado para um plano
> arquivado/inativo.

## Checklist

- [ ] Origem do plano identificada (conversa / doc_dev / .context) e conteúdo-base obtido.
- [ ] Slug `{feature}` definido e diretório `.context/plans/{feature}/` criado.
- [ ] Grupo A (libs Python/Rust) levantado com versões do `pyproject.toml`/`Cargo.toml`.
- [ ] Grupo B (serviços externos) levantado com endpoints e tipo de auth.
- [ ] Docs de libs coletados via Context7 (subagentes `haiku`).
- [ ] Docs de serviços externos coletados via WebSearch/WebFetch (subagentes `haiku`).
- [ ] `.context/plans/{feature}/info_aux_{feature}.md` consolidado e salvo.
- [ ] Plano completo reestruturado por `opus` salvo em `.context/plans/{feature}/plano_completo_{feature}.md`.
- [ ] Seção "Correções aplicadas" presente no plano completo.
- [ ] Plano canônico `.context/plans/{feature}.md` criado via `scaffoldPlan` e referenciando os artefatos.
- [ ] Fases PREVC transcritas no frontmatter do plano canônico.
- [ ] `workflow-init` + `plan link` executados; workflow avançado para implementação (E).
- [ ] Tracking sincronizado (`plan syncMarkdown`).
- [ ] (Na conclusão) Canônico movido para dentro da pasta e pasta inteira movida para `.context/plans/archive/{feature}/` via `git mv`.
