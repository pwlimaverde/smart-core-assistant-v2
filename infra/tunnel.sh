#!/bin/bash
# ============================================
# SSH Tunnels - Desenvolvimento Local
# Smart Core Assistant v2
# ============================================
# Mapeia as portas do Hostinger para localhost,
# permitindo que o codigo Rust local conecte aos
# bancos remotos como se fossem locais.
#
# Execute a partir da pasta infra/:
#   cd infra && ./tunnel.sh
#
# Mantenha este terminal aberto enquanto desenvolve.
# Pressione Ctrl+C para encerrar os tunnels.
# ============================================

set -e

if [ ! -f ".env.deploy" ]; then
    echo "Erro: .env.deploy nao encontrado!"
    exit 1
fi

source .env.deploy

POSTGRES_PORT="${POSTGRES_PORT:-5432}"
REDIS_PORT="${REDIS_PORT:-6379}"
MINIO_PORT="${MINIO_PORT:-9000}"
MINIO_CONSOLE_PORT="${MINIO_CONSOLE_PORT:-9001}"

echo ""
echo "============================================"
echo "  SSH TUNNELS - SMART CORE V2"
echo "============================================"
echo ""
echo "Servidor remoto: $HOSTINGER_SSH_HOST"
echo ""
echo "Portas mapeadas para localhost:"
echo "  PostgreSQL : localhost:5432  ->  $HOSTINGER_SSH_HOST:$POSTGRES_PORT"
echo "  Redis      : localhost:6379  ->  $HOSTINGER_SSH_HOST:$REDIS_PORT"
echo "  MinIO API  : localhost:9000  ->  $HOSTINGER_SSH_HOST:$MINIO_PORT"
echo "  MinIO UI   : localhost:9001  ->  $HOSTINGER_SSH_HOST:$MINIO_CONSOLE_PORT"
echo ""
echo "Configure o .env local da aplicacao com:"
echo "  DATABASE_URL=postgresql://smartcore_app:SENHA@localhost:5432/smartcore_v2"
echo "  REDIS_URL=redis://:SENHA@localhost:6379"
echo "  MINIO_ENDPOINT=http://localhost:9000"
echo ""
echo "MinIO Console: http://localhost:9001"
echo ""
echo "Pressione Ctrl+C para encerrar os tunnels."
echo ""

ssh -p ${HOSTINGER_SSH_PORT:-22} \
    -L "5432:localhost:$POSTGRES_PORT" \
    -L "6379:localhost:$REDIS_PORT" \
    -L "9000:localhost:$MINIO_PORT" \
    -L "9001:localhost:$MINIO_CONSOLE_PORT" \
    -N \
    "$HOSTINGER_SSH_USER@$HOSTINGER_SSH_HOST"
