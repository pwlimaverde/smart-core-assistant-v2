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
| gRPC | tonic-build (Rust) + grpcio (Python) | gerado em build |
| FFI | flutter_rust_bridge | `flutter_rust_bridge_codegen` |

## Rust Toolchain

- `rustup` para gerenciar versões (`rust-toolchain.toml` na raiz quando criado).
- `cargo clippy -- -D warnings` e `cargo fmt --check` obrigatórios antes de commit.
- `sqlx` modo offline (`.sqlx/` versionado); `cargo sqlx prepare` após cada migration.

## Flutter

- `flutter_rust_bridge` para FFI com `local_engine`.
- Arquivos gerados (`*.g.dart`, `*.freezed.dart`) git-ignored; regenerar com `flutter pub run build_runner build`.
- Build Windows: `flutter build windows --release`.

## Python (ia_engine)

- Python 3.13+. Gerenciador: `uv`; `uv.lock` versionado.
- `.venv/` git-ignored.
- Arquivos gRPC gerados (`*_pb2.py`) git-ignored; gerados em build.
- Linting: `ruff` + `pyright` (strict).

## Local Infrastructure

```bash
docker compose -f docker/compose/data.yml up -d
```

Volumes de dados git-ignored: `pgdata/`, `redis-data/`, `minio-data/`, `evolution-data/`.

## Environment Variables

Copie `.env.example` para `.env` na raiz do monorepo:

```
DATABASE_URL=postgres://...
REDIS_URL=redis://...
MINIO_URL=http://...
EVOLUTION_API_URL=http://...
EVOLUTION_API_KEY=...
OPENAI_API_KEY=...
```

## Related Resources

- [Development Workflow](development-workflow.md)
- [Project Overview](project-overview.md)
