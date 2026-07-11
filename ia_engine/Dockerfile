# Multi-stage build do ia_engine.
#
# IMPORTANTE: o contexto de build DEVE ser a RAIZ do repositório
# (não `ia_engine/`), porque os stubs gRPC são gerados a partir do `.proto`
# canônico que vive em `server/crates/contracts/schemas/ai/ai_engine.proto`,
# fora da pasta `ia_engine/`. Ver docker/*/compose.yml (build.context: ../..).
#
#   docker build -f ia_engine/Dockerfile -t smartcore-ia-engine .

# ---------- builder: instala deps (com dev) e gera os stubs ----------
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS builder

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never

WORKDIR /app/ia_engine

# Cache de dependências: resolve o ambiente antes de copiar o código.
COPY ia_engine/pyproject.toml ia_engine/uv.lock ./
RUN uv sync --frozen --no-install-project

# Código da app + proto canônico (no mesmo layout relativo do repo).
COPY ia_engine/ ./
COPY server/crates/contracts/schemas/ai/ai_engine.proto \
     /app/server/crates/contracts/schemas/ai/ai_engine.proto

# Gera os stubs e finaliza o venv sem dependências de desenvolvimento.
RUN uv run python scripts/gen_proto.py \
 && uv sync --frozen --no-dev

# ---------- runtime: imagem enxuta só com o venv + app ----------
FROM python:3.12-slim-bookworm AS runtime

ENV PATH="/app/ia_engine/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    GRPC_HOST=0.0.0.0 \
    GRPC_PORT=50060

WORKDIR /app/ia_engine

# Usuário não-root.
RUN useradd --create-home --uid 10001 appuser

COPY --from=builder --chown=appuser:appuser /app/ia_engine/.venv ./.venv
COPY --from=builder --chown=appuser:appuser /app/ia_engine/src ./src

USER appuser
EXPOSE 50060

ENTRYPOINT ["python", "-m", "ia_engine.server"]
