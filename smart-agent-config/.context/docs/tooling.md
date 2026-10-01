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
| Infra local | Docker Compose | `docker compose -f docker/compose/data.yml up -d` |
| Contratos | `protoc` (gRPC) + `flatc` (FlatBuffers) | gerados no build (`tonic-build` no Rust; `grpcio` no Python) |
| FFI | flutter_rust_bridge | `flutter_rust_bridge_codegen` |

## Rust Toolchain

- `rustup` para gerenciar versões (`rust-toolchain.toml` na raiz quando criado).
- `cargo clippy -- -D warnings` e `cargo fmt --check` obrigatórios antes de commit.
- `sqlx` modo offline (`.sqlx/` versionado); `cargo sqlx prepare` após cada migration.
- Testes: `cargo test` sobe o túnel SSH do banco sozinho (`test_support::ensure_tunnel()`); `cargo nextest run` recomendado.

## Flutter

- `flutter_rust_bridge` para FFI com `local_engine`.
- Código gerado (`*.g.dart`, `*.freezed.dart`) não é versionado; regenerar com `dart run build_runner build`.
- Build Windows: `flutter build windows --release`. Análise: `flutter analyze`.

## Python (ia_engine)

- Python 3.13+. Gerenciador: `uv`; `uv.lock` versionado.
- Stubs gRPC (`*_pb2.py`) não são versionados; gerados no build/CI.
- Linting: `ruff` + `pyright` (strict). Testes: `uv run pytest`.

## Local Infrastructure

```bash
docker compose -f docker/compose/data.yml up -d
```

> **Windows (dev):** UDS não funciona — configure os endpoints dos serviços com
> `SMARTCORE_<SVC>_ENDPOINT=tcp://...` (ex.: `SMARTCORE_DATA_POSTGRES_ENDPOINT`).
> Storage não usa infra local: Cloudflare R2 é acessado por HTTPS direto.

## Environment Variables

Copie `.env.example` para `.env` na raiz do monorepo:

```
DATABASE_URL=postgres://...
REDIS_URL=redis://...
S3_ENDPOINT=https://<account>.r2.cloudflarestorage.com
S3_REGION=auto
S3_ACCESS_KEY_ID=...
S3_SECRET_ACCESS_KEY=...
S3_BUCKET=...
EVOLUTION_API_URL=http://...
EVOLUTION_API_KEY=...
OPENAI_API_KEY=...
```

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
*exec form* (`py -3 ${CLAUDE_PROJECT_DIR}/.claude/hooks/roteador.py`) — nunca
`python3`, que nesta máquina é o alias da Microsoft Store.

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
