# Imagem do releases_server (Axum 0.8). Contexto de build: raiz do repositório.
#
# 1) builder — compila só o pacote releases_server (não depende de contracts,
#    então dispensa protoc/flatc).
FROM rust:1-bookworm AS builder
WORKDIR /app
COPY server/ .
RUN cargo build --release --locked -p releases_server

# 2) runtime — sem shell extra além do necessário para o healthcheck.
FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 10001 --no-create-home releases \
    && mkdir -p /data/releases \
    && chown releases /data/releases
COPY --from=builder /app/target/release/releases_server /usr/local/bin/releases_server
USER releases
ENV RELEASES_DIR=/data/releases
EXPOSE 8086
HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=10s \
    CMD curl -fsS http://127.0.0.1:8086/health || exit 1
ENTRYPOINT ["releases_server"]
