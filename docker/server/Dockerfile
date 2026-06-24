# syntax=docker/dockerfile:1

# Base com toolchain + ferramentas de geração de contratos (flatc/protoc).
# Pin de versão concreta para cache determinístico.
FROM rust:1-bookworm AS chef
RUN cargo install cargo-chef --locked
RUN apt-get update && apt-get install -y --no-install-recommends \
        protobuf-compiler wget unzip ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# flatc — mesma versão e URL do CI
RUN wget -q -O /tmp/flatc.zip \
      https://github.com/google/flatbuffers/releases/download/v25.12.19-2026-02-06-03fffb2/Linux.flatc.binary.g%2B%2B-13.zip \
 && unzip -q -o /tmp/flatc.zip -d /tmp/flatc_extracted \
 && mv /tmp/flatc_extracted/flatc /usr/local/bin/flatc \
 && chmod +x /usr/local/bin/flatc && rm -rf /tmp/flatc.zip /tmp/flatc_extracted
WORKDIR /app

# 1) planner — gera o recipe (grafo de dependências)
FROM chef AS planner
COPY server/ .
RUN cargo chef prepare --recipe-path recipe.json

# 2) builder — cozinha as dependências (cache) e compila os 9 binários
FROM chef AS builder
ENV SQLX_OFFLINE=true
COPY --from=planner /app/recipe.json recipe.json
# build.rs do contracts roda no cook e no build -> flatc/protoc já presentes
RUN cargo chef cook --release --recipe-path recipe.json
COPY server/ .
RUN cargo build --release --workspace

# 3) runtime — imagem final única, sem ENTRYPOINT fixo
FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates libssl3 curl \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -r -s /usr/sbin/nologin smartcore

COPY --from=builder \
     /app/target/release/data_postgres \
     /app/target/release/data_redis \
     /app/target/release/data_storage \
     /app/target/release/control_plane \
     /app/target/release/messaging_gateway \
     /app/target/release/runtime_api \
     /app/target/release/worker \
     /app/target/release/data_whatsapp \
     /app/target/release/webhook_ingress \
     /usr/local/bin/

USER smartcore
# Sem ENTRYPOINT: o command do compose escolhe o binário por serviço.
