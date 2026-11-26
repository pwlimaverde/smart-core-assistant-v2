---
type: doc
name: tooling
description: Scripts, IDE settings, automation, and developer productivity tips
category: tooling
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---

## Tooling

## Build System

| Stack | Ferramenta | Comando principal |
|-------|-----------|------------------|
| Rust | Cargo workspace | `cargo build` / `cargo test` |
| Flutter | Flutter SDK + Dart | `flutter build windows` / `flutter run` |
| Python (IA) | uv | `uv run pytest` / `uv run python` |
| Ambientes | Docker Compose na VPS | `docker/stack/` (base + overlay) implantado por `infra/deploy/deploy.sh` — ver `doc_dev/runbooks/RUNBOOK_DEPLOY.md` |
| Contratos | `protoc` (gRPC) + `flatc` (FlatBuffers) | gerados no build (`tonic-build` no Rust; `grpcio` no Python) |
| FFI | flutter_rust_bridge | `flutter_rust_bridge_codegen` |

## Rust Toolchain

- `rustup` para gerenciar versões (`rust-toolchain.toml` na raiz quando criado).
- `cargo clippy -- -D warnings` e `cargo fmt --check` obrigatórios antes de commit.
- `sqlx` modo offline (`.sqlx/` versionado); `cargo sqlx prepare` após cada migration.
- Testes: unitários com `cargo test` em qualquer máquina; integração (Postgres/Redis) só na CI — não há túnel nem ambiente local. Portão: `node infra/ci-verde.mjs --esperar`.

## Flutter

- `flutter_rust_bridge` para FFI com `local_engine`.
- Código gerado (`*.g.dart`, `*.freezed.dart`) não é versionado; regenerar com `dart run build_runner build`.
- Build Windows: `flutter build windows --release`. Análise: `flutter analyze`.

## Python (ia_engine)

- Python 3.13+. Gerenciador: `uv`; `uv.lock` versionado.
- Stubs gRPC (`*_pb2.py`) não são versionados; gerados no build/CI.
- Linting: `ruff` + `pyright` (strict). Testes: `uv run pytest`.

## Ambientes (sem infraestrutura local)

Não há infraestrutura local: `docker/compose/data.yml` e o túnel SSH deixaram de existir.
Os dois ambientes rodam na VPS `srv1321059`, a partir de bundles por versão:

| Ambiente | Onde | Como chega |
|---|---|---|
| dev | `/opt/smartcore/dev/releases/current` | push na `dev` → `deploy-dev.yml` → `vX.Y.Z-beta.N` |
| prod | `/opt/smartcore/prod/releases/current` | tag `vX.Y.Z` → `deploy-prod.yml` (aprovação) |

Scripts: `infra/deploy/{bundle,deploy,smoke,rollback,promove-imagens,deploy-infra}.sh`
(um só script de deploy para os dois ambientes). Passo a passo:
`doc_dev/runbooks/RUNBOOK_DEPLOY.md`. Logs e métricas: Grafana (`grafana.smartcoreassistant.com.br`).

## Environment Variables

O arquivo de ambiente de cada ambiente é o secret `ENV_FILE_B64` do GitHub
Environment (`dev` / `prod`), materializado pelo deploy em
`/opt/smartcore/<env>/env/<env>.env`. `.env.example` (raiz) é a referência das
chaves; as obrigatórias estão em `infra/deploy/required-keys.{dev,prod}`.
Nunca commitar `.env`, `infra/.env.deploy` nem o conteúdo decodificado do secret.

## Roteador de modelo e seletor de skill (Claude Code)

Um gancho `UserPromptSubmit` (`.claude/hooks/roteador.py`, Python só com biblioteca
padrão) faz **uma** chamada ao Jev por mensagem e decide em código:

- **nível** (simples/rotina/difícil) → modelo do subagente (haiku/sonnet/opus);
- **especialista** entre os agentes de `.context/agents/` (ou `general-purpose`);
- **skill** da biblioteca única `.context/skills/` (ou nenhuma);
- **risco**, **continuação** da tarefa anterior e se o **entregável é texto**.

| Modo (`/roteador <modo>`) | O que faz |
|---|---|
| `skills` (padrão) | Só o seletor: injeta o caminho da skill escolhida; o Claude a lê. Não repete a instrução na mesma sessão. |
| `on` | Seletor + delegação: a sessão principal (no Haiku, `/model haiku`) delega ao especialista com `model:` do nível, passando o caminho da skill ao subagente. |
| `off` | Nada. |

`/roteador status` mostra o modo, se a chave chega ao gancho e a última decisão.

**Regra do dono** (`REGRA_AUTONOMIA` em `roteador.py`): nos modos `skills` e `on`,
toda mensagem do usuário que passa pelo roteador (todas, menos as que começam com
`>>` ou `/`) recebe também a regra de autonomia e conclusão: nada de
pergunta de decisão (dúvida técnica vai a um subagente de pesquisa, que escolhe a
opção mais robusta, com o motivo registrado em uma linha) e conclusão só depois de
executar tudo, conferir e revisar. As proibições de produção e de gasto continuam
valendo. A regra não muda a decisão do roteador. Vale para a sessão local e para a do
servidor (o gancho é o mesmo arquivo versionado).

**Atalhos** (no início da mensagem): `>>` passa direto; `#rapido`, `#padrao`,
`#profundo` forçam o nível; `$<slug>` força a skill; `/slug` (stub de comando) usa a
skill do comando e não roteia.

**Política** (`.claude/roteador.config.json`, versionado — ajuste aqui, não no código):
risco > 0,7 ou confiança do nível < 0,6 sobe um nível (máximo +1, teto opus);
continuação > 0,55 herda nível, especialista e skill (nunca desce); skill aceita com
chance > 0,5 e confiança ≥ 0,65, com desempate para pares parecidos
(test-generation×test-rust, code-review×pr-review, code-review×refactoring); skill nova
aceita vence a herdada. Fase PREVC ativa em `.context/workflow/status.yaml` → skill da
fase. Falha do Jev (timeout de 4 s, HTTP, chave ausente) → sonnet + general-purpose,
sem skill.

**Chave**: `TYPESAFE_API_KEY`, do bloco `env` do `~/.claude/settings.json` global (o
Claude Code a repassa ao gancho). Nunca no repositório nem no log.

**Estado local** (git-ignorado) em `.claude/roteador/`: `modo`, `decisoes.jsonl`
(rotação em 5 MB; mensagem mascarada e truncada), `status.txt` (texto pronto da linha de
status — o `statusLine` só faz `cat`, sem Python) e `catalogo.json` (cache por mtime).

**Contrato do gancho** (para portar sem mudar o resto): stdin = JSON do Claude Code
(`prompt`, `session_id`); stdout = `hookSpecificOutput.additionalContext` ou nada;
efeitos = uma linha no JSONL e o `status.txt`. Registrado no `settings.json` em
*exec form*, no `~/.claude/settings.json` global de cada máquina: no Windows
`py -3 ${CLAUDE_PROJECT_DIR}/.claude/hooks/roteador.py` — nunca `python3`, que lá é o
alias da Microsoft Store; no VPS (Linux, sem `py`) `python3` com o mesmo argumento. O
comando `/roteador` escolhe sozinho: `py -3` se existir, senão `python3`.

**Calibração**: `py -3 .claude/hooks/avaliar_roteador.py` roda os casos de
`avaliar_casos.json` em modo seco e imprime a matriz de nível, o acerto de skill, a
continuação e as latências. Em 2026-10-01: nível 36/40 (os 4 erros para cima, nenhum
abaixo), skill 38/40, continuação 4/4, Jev ~365 ms (p95 ~405 ms), partida do processo
~80 ms (18% do total → manter em Python; portar para Rust só se passar de 30% ou 400 ms).

**Comandos de skill**: `.claude/commands/<slug>.md` são gerados por
`py -3 .claude/hooks/gerar_stubs_skills.py` a partir de `skills_manuais` na
configuração. Não editar à mão.

**Plugins e skills globais** (typesafe, anthropic-skills etc.) não passam pelo seletor e
continuam listados; desative os que não usa com `/plugin`.

### Continuidade após limite de uso

`.claude/hooks/continuidade.py` (biblioteca padrão; reaproveita o `mascarar` do roteador)
faz a sessão que parou por limite voltar sozinha, sem o coordenador intervir.

- **Detecção** — gancho `StopFailure` (o Claude Code o dispara no lugar do `Stop` quando o
  turno acaba em erro de API; `error` = `rate_limit`, `server_error`, ...; a saída é
  ignorada). Erros em `erros_retomaveis` (padrão `rate_limit` e `server_error`) marcam a
  sessão como `limite`. O horário de reset vem do transcript (`resetsAt` do último erro
  de API, formato interno, best-effort) ou do texto `resets 3:45pm (Fuso)`. Sem horário,
  a retomada segue com backoff a partir de 15 min. `UserPromptSubmit` guarda o último
  pedido (mascarado, 400 caracteres), e `Stop` marca a tarefa como concluída.
- **Agendador do sistema** (sobrevive ao fim da sessão, ao contrário de
  `CronCreate`/`ScheduleWakeup`/`/loop`, que só disparam com a sessão aberta): systemd
  timer `roteador-continuidade.timer` no VPS e a tarefa `\SmartCore\RoteadorContinuidade`
  no Windows, **a cada 15 min**. A verificação é local, lê um JSON e não chama a API.
  Vencido o horário, roda `claude -p --resume <sessão> --output-format json "<[continuidade] …>"`:
  - **no lugar**, se nenhum processo segura a sessão;
  - com **`--fork-session`**, se a sessão está viva. É o caso do Remote Control, que
    roda `--print --sdk-url`. Duas escritas no mesmo transcript perdem mensagens.
  - **Sessão interativa viva** (`entrypoint` `cli`): primeiro uma carência de 20 min
    para o auto-continue nativo. A notificação `quota_auto_resume_fired` ou o
    transcript andando cancelam a nossa retomada.
- **Sem loop**: até `max_tentativas` (6), teto de `teto_horas` (30 h) desde a primeira
  detecção (um reset além do teto desiste na hora) e timeout de 4 h por retomada. Só
  limite de novo (ou timeout) volta para a fila; outra falha (binário ausente, sessão não
  encontrada) vira `falha` com o motivo no aviso. Uma só verificação por vez (trava do SO,
  `flock`/`msvcrt`, solta sozinha se o processo morre, + `oneshot`/`IgnoreNew`). A
  retomada roda na pasta em que a sessão nasceu (`cwd_projeto`). No Windows, só com o
  `claude.exe` nativo: um `claude.cmd` passaria o pedido pelo `cmd.exe`.
- **Sinal de vida**: avisos injetados na próxima mensagem ou `SessionStart` de qualquer
  sessão do mesmo diretório (limite detectado, retomada iniciada ou terminada,
  desistência, e agendador sem rodar há mais de 45 min com sessão esperando). Também
  vão para `log.jsonl`, para o journal (`journalctl -u roteador-continuidade`) e para a
  segunda linha da statusline. `notificar_cmd` (opcional) recebe cada aviso no stdin.
- **Estado** em `~/.claude/roteador-continuidade/`: `estado.json`, `log.jsonl` (rotação
  em 1 MB), `status.txt` e `config.json` opcional, que sobrepõe os padrões de `PADRAO`
  no script. Não guarda segredo nem token.
- **Comandos**: `continuidade.py --status`, `--verificar --seco` (diz o que faria) e
  `--registrar-hooks <settings.json>` (idempotente, com backup).

**Instalação** (valida com `py_compile` + `--status` + `--verificar --seco` antes de ativar):

- VPS: `git -C /opt/smartcore/ops/smart-core-assistant-v2 pull --ff-only origin dev` e
  `bash smart-agent-config/scripts/continuidade/instalar-vps.sh`. O script registra os
  ganchos no `/root/.claude/settings.json` (onde está o roteador) e instala as unidades.
  A retomada roda como root em `bypassPermissions` com `IS_SANDBOX=1`, a mesma decisão do
  `claude-rc`. Backup em `/root/.claude/backups/continuidade-<data>/`.
- Windows: `pwsh smart-agent-config/scripts/continuidade/instalar-windows.ps1`. O script
  registra os ganchos no `.claude/settings.local.json` do projeto (onde está o roteador
  local) e cria a tarefa com `pyw`, sem janela. A permissão segue o `defaultMode` do
  `~/.claude/settings.json`. `-SoValidar` só valida e `-Remover` tira a tarefa.

**Limites conhecidos**: depende de o host estar ligado (o PC dormindo não retoma, e o
`StartWhenAvailable` roda no despertar). No fork, a conversa do Remote Control não mostra a
continuação ao vivo, mas o aviso chega na próxima mensagem com o id da sessão nova. A
retomada consome o limite renovado.

## Related Resources

- [Development Workflow](development-workflow.md)
- [Project Overview](project-overview.md)
