# Prompt final — Roteador de modelo + seletor de skill com o Jev

> Versão consolidada em 2026-10-01 e executada na branch `feature/roteador-modelo`.
> Os valores dos limiares já são os calibrados; as divergências em relação às
> versões anteriores da conversa estão marcadas com **(ajuste)**.

Quero que, a cada mensagem minha, um gancho consulte o Jev uma única vez para decidir:
(a) o nível do pedido e, a partir dele, o modelo e o especialista que vão executar; e
(b) qual skill do projeto serve, se alguma. A sessão principal pode rodar no Haiku como
recepção que delega. As skills ficam num lugar só.

## Regras gerais
- Configuração versionada em `smart-agent-config/`. Caminhos resolvidos a partir do
  script (`Path(__file__)`), nunca do CWD; `${CLAUDE_PROJECT_DIR}` no `settings.json`.
- Gancho em Python ≥3.13 só com biblioteca padrão, sem venv, registrado em *exec form*
  (`"command": "py", "args": ["-3", "${CLAUDE_PROJECT_DIR}/.claude/hooks/roteador.py"]`).
  NUNCA `python3` (nesta máquina é o alias da Microsoft Store). `ssl`/`urllib` só são
  importados quando o Jev é chamado. Comentários em pt-br.
- Limiares, pares concorrentes, mapa skill→especialista e lista de skills manuais em
  `.claude/roteador.config.json` (versionado). Contrato do gancho documentado para
  permitir portar para Rust.
- Chave do Jev: `TYPESAFE_API_KEY`, já definida no bloco `env` do
  `~/.claude/settings.json` global. Só de `os.environ`; nunca no projeto, em `.env`, no
  `settings.json` versionado, em log ou em mensagem de erro. Não usar a CoreSetting.
- No `.claude/settings.json`, só ACRESCENTAR `hooks` e `statusLine`.
- Não rodar export/sync/init do dotcontext. **(ajuste)** O `CLAUDE.md` é cópia literal de
  `.context/docs/README.md`: a mesma alteração é espelhada à mão nos dois, em vez de
  regenerar (regenerar exige o export que corrompe `.context/agents/`).
- Não rodar a suíte de testes do projeto. Validar só os scripts desta tarefa.
- Gitflow: `feature/roteador-modelo` a partir de `dev`. Commits sem auto-referência.

## Etapa 0 — Ler antes de codar
- Skill `typesafe:typesafe-ai`, `doc_dev/libs/python/typesafe_sdk.md`, HTTP API atual
  (`POST https://api.typesafe.ai/v1/systemone`, `Authorization: Bearer`, perguntas com
  `type` choice/noul/score; resposta em `answers`).
- Doc atual do Claude Code (confirmado em 2026-10-01): `UserPromptSubmit` recebe
  `prompt`, `session_id`, `transcript_path`, `cwd`; devolve
  `hookSpecificOutput.additionalContext`; timeout padrão 30 s; ganchos do mesmo evento
  rodam em paralelo; no Windows, Git Bash (ou PowerShell sem Git Bash), *exec form* com
  `args`. `disable-model-invocation: true` tira o comando do contexto do modelo e mantém
  o `/comando`. `statusLine` recebe JSON no stdin, roda por evento (debounce de 300 ms).
  O parâmetro `model` da ferramenta Agent vence o frontmatter do agente.
- Confirmar que o gancho enxerga `TYPESAFE_API_KEY` sem imprimir o valor.

## Etapa 1 — Biblioteca única em `.context/skills/`
O MCP dotcontext tem a pasta fixa em código (`SKILLS_DIR = '.context/skills'`, fallback
`.agents/skills`). Sem mudar o conteúdo de nenhuma SKILL.md:
1. Relatório das diferenças de corpo entre a canônica e `.claude/skills/`,
   `.agents/skills/`, `.agents/workflows/`. **(resultado)** As cópias eram versões mais
   antigas (templates de 05–06/2026, sem as regras do projeto); nada voltou.
2. Mover para `.context/skills/` as `dotcontext-*` (são skills *built-in* do MCP; o
   arquivo na biblioteca vira o conteúdo usado).
3. Apagar `.claude/skills/`, `.agents/skills/`, `.agents/workflows/`.
4. Reescrever `.context/skills/README.md` com o catálogo e a regra "fonte única"; o
   `AGENTS.md` aponta para ele.

## Etapa 2 — Comandos sem duplicar conteúdo
- `gerar_stubs_skills.py` gera `.claude/commands/<slug>.md` para `skills_manuais`
  (plan-restructuring, feature-breakdown, pr-review, commit-message, prevc-*), com
  `disable-model-invocation: true`, marcador `stub-skill:<slug>` e só a instrução de ler
  `.context/skills/<slug>/SKILL.md`. Remove stubs órfãos. Nunca editar à mão.
- **(ajuste)** `/roteador on|skills|off|status` (comando com `!` que chama
  `roteador.py --cli`) troca o modo em `.claude/roteador/modo`.

## Etapa 3 — Gancho único `roteador.py` (timeout 8 s no settings)
**(ajuste) Modos** em vez do arquivo `ATIVO`: `skills` (padrão — só o seletor; sem ele,
remover `.claude/skills/` deixaria a sessão sem skills), `on` (seletor + delegação),
`off`.

### Atalhos (sem Jev)
- `/comando` (ou texto com `stub-skill:`): não roteia; a skill é a do comando.
  (Pela doc, o `UserPromptSubmit` pode nem disparar para comandos; os dois casos são
  tratados.)
- `>>`: passa direto.
- `#rapido|#padrao|#profundo` e/ou `$<slug>`: forçam nível e/ou skill (motivo
  "manual"); removidos do texto; o Jev só é chamado para o resto.

### Estado e perguntas (uma chamada)
State: `mensagem` mascarada (PEM, URLs de banco, URLs com credencial, tokens
conhecidos, `senha=`/`token=`, e-mails/`user@host`, IPs, valores ≥ 40 caracteres) e
truncada em 2000; `projeto` (descrição do Smart Core Assistant v2); `tarefa_anterior`
(última decisão com menos de 2 h).
Perguntas (instruções em inglês, conteúdo em português): `nivel` (Choice com `what` e
`examples`), `especialista` (Choice com as descrições dos agentes de `.context/agents/`
+ `general-purpose`), `skill` (Choice com as descrições das skills elegíveis + "nenhuma";
**(ajuste)** só escolher se o pedido é executar a atividade da skill — explicar ou
responder não precisa de skill), `risco` (Noul), `entregavel_texto` (Noul) e
`continuacao` (Noul, só com tarefa anterior). No modo `skills` vão só `skill` e
`continuacao`. `prevc-*` e `dotcontext-*` ficam fora da escolha: fase PREVC ativa
(`current_phase` com status não concluído em `.context/workflow/status.yaml`) → skill da
fase.

### Decisão (limiares calibrados)
- Base simples→haiku, rotina→sonnet, difícil→opus.
- Risco > 0,7 ou confiança do nível < 0,6: sobe um nível (máximo +1; só registra a
  escalada se mudou). Teto opus.
- Continuação > **0,55** (ajuste; assuntos novos ficam perto de 0,04): herda nível
  (nunca desce), especialista e skill; `retomar=true`.
- Especialista: confiança ≥ 0,5; senão o mapeado pela skill; senão `general-purpose`.
- Skill: chance > 0,5 e confiança ≥ **0,65** (ajuste); senão desempate dos pares
  concorrentes; senão a herdada. **(ajuste)** Skill nova aceita vence a herdada
  ("pode commitar" no meio de uma investigação → commit-message).
- Falha do Jev (timeout de **4 s** (ajuste: a primeira conexão chegou a 3,7 s), HTTP,
  chave ausente): sonnet + general-purpose, sem skill, `falha=<motivo>`.

### Contexto injetado
- Modo `skills`: só o caminho da skill e a instrução de lê-la; nas mensagens seguintes
  da mesma sessão, "já indicada".
- Modo `on`: nível, modelo, especialista, retomar, entregável em texto, skill e a regra
  de delegação (mensagem literal, regras de memória, subagente lê a skill, SendMessage
  na continuação, texto completo × resumo, fallback opus→sonnet após 2 cobranças,
  retomada após limite de sessão).

## Etapa 4 — Registro
`.claude/roteador/decisoes.jsonl` (rotação em 5 MB): horário, session_id, modo,
mensagem mascarada (200), atalho, fase, nível do Jev e confiança, risco, continuação,
entregável em texto, nível final, escalada, especialista e confiança, modelo, skill
candidata/chance/confiança, segunda candidata, skill final e motivo, injetado,
`jev_ms`, `gancho_ms`, falha (sem a chave). `.claude/roteador/` inteiro no `.gitignore`.

## Etapa 5 — Linha de status
Sem Python: o gancho grava `.claude/roteador/status.txt` e o `statusLine` faz
`cat "${CLAUDE_PROJECT_DIR:-.}/.claude/roteador/status.txt"`. Exemplos:
`roteador: difícil 1.00 ↑risco → Database Specialist (Opus) · skill: bug-investigation 0.85 · 416ms`,
`seletor · skill: test-rust 1.00 · 368ms`, `roteador: off`, `roteador: sem chave`,
`roteador: jev indisponível → sonnet`, prefixo `⚠ skills duplicadas`.

## Etapa 6 — Calibração
`avaliar_roteador.py` + `avaliar_casos.json` (40 mensagens no estilo do projeto, com
nível e skill esperados; rótulos revisáveis). Resultado em 2026-10-01: nível 36/40
(4 erros, todos para cima — coerente com "na dúvida, o mais forte"), skill 38/40,
continuação 4/4, Jev média 365 ms / p95 405 ms, partida do processo 80 ms (18% do
total → manter em Python; portar só se passar de 30% ou 400 ms).

## Etapa 7 — Documentação e memória
`.context/docs/tooling.md` (seção do roteador), `.context/docs/README.md` + `CLAUDE.md`
(export com `skipSkills: true`; snapshot com a biblioteca única), `.context/skills/README.md`,
`AGENTS.md`, memórias `dotcontext-export-presets`, `agent-config-folder` e nova memória
do roteador.

## Entrega
Commits: (1) biblioteca + stubs; (2) gancho, registro, status, settings; (3) calibração;
(4) docs, memórias e este prompt. Validação: JSON de exemplo no stdin (cada atalho,
falha sem chave, modos `on`/`skills`), geração dos stubs, calibração.
