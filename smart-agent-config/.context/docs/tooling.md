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

## Related Resources

- [Development Workflow](development-workflow.md)
- [Project Overview](project-overview.md)
