# Multi-stage build for releases_server
# Stage 1: Build
FROM rust:1.84 as builder

WORKDIR /app

# Copy workspace
COPY server/ .

# Build release binary (only releases_server app)
RUN cargo build --release --bin releases_server --package releases_server

# Stage 2: Runtime
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/target/release/releases_server /usr/local/bin/releases_server

# Create releases directory
RUN mkdir -p /data/releases

EXPOSE 8086

HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=10s \
    CMD curl -f -s http://localhost:8086/health || exit 1

ENTRYPOINT ["releases_server"]
