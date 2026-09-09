# Multi-stage build do mcp_server.
#
# IMPORTANTE: o contexto de build DEVE ser a RAIZ do repositório (não
# `mcp_server/`), porque os stubs gRPC são gerados a partir dos `.proto`
# canônicos que vivem em `server/crates/contracts/schemas/queries/`, fora da
# pasta `mcp_server/`. Ver docker/*/compose.yml (build.context: ../..).
#
#   docker build -f mcp_server/Dockerfile -t smartcore-mcp-server .

# ---------- builder: instala deps (com dev) e gera os stubs ----------
FROM ghcr.io/astral-sh/uv:python3.13-bookworm-slim AS builder

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never

WORKDIR /app/mcp_server

# Cache de dependências: resolve o ambiente antes de copiar o código.
COPY mcp_server/pyproject.toml mcp_server/uv.lock mcp_server/README.md ./
RUN uv sync --frozen --no-install-project

# Código da app + protos canônicos (no mesmo layout relativo do repo).
COPY mcp_server/ ./
COPY server/crates/contracts/schemas/queries/admin.proto \
     /app/server/crates/contracts/schemas/queries/admin.proto
COPY server/crates/contracts/schemas/queries/auth.proto \
     /app/server/crates/contracts/schemas/queries/auth.proto

# Gera os stubs e finaliza o venv sem dependências de desenvolvimento.
RUN uv run python scripts/gen_proto.py \
 && uv sync --frozen --no-dev

# ---------- runtime: imagem enxuta só com o venv + app ----------
FROM python:3.13-slim-bookworm AS runtime

ENV PATH="/app/mcp_server/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    MCP_HOST=0.0.0.0 \
    MCP_PORT=8099

WORKDIR /app/mcp_server

# Usuário não-root.
RUN useradd --create-home --uid 10001 appuser

COPY --from=builder --chown=appuser:appuser /app/mcp_server/.venv ./.venv
COPY --from=builder --chown=appuser:appuser /app/mcp_server/src ./src

USER appuser
EXPOSE 8099

ENTRYPOINT ["python", "-m", "mcp_server.server"]
