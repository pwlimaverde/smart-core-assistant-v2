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

## Related Resources

- [Development Workflow](development-workflow.md)
- [Project Overview](project-overview.md)
