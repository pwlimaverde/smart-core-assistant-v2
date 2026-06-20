#!/bin/bash
# ============================================
# SSH Tunnels para a stack remota — modelo FULL-DOCKER
# Smart Core Assistant v2
# ============================================
# Postgres/Redis/MinIO NAO publicam portas no host (ficam so na rede interna do
# compose). Este script descobre o IP de cada container no ambiente e faz o
# forward SSH ate ele, para inspecao com ferramentas locais.
#
# Para DESENVOLVIMENTO normal, prefira rodar a stack LOCALMENTE:
#   cd docker/compose && docker compose --env-file env/dev.env up -d
#
# Uso:  ./infra/tunnel.sh [dev|prod]   (padrao: dev)
# Requer SSH (alias hostinger-root em ~/.ssh/config). Ctrl+C encerra.
# ============================================
set -euo pipefail

ENVNAME="${1:-dev}"
SSH_ALIAS="${SSH_ALIAS:-hostinger-root}"
NET="smart-core-v2-${ENVNAME}_internal"

# servico:remoto:local
SVCS=("postgres:5432:5434" "redis:6379:6379" "redis-bus:6379:6380" "minio:9000:9000")

echo "Descobrindo IPs dos containers na rede '$NET'..."
FW=()
for entry in "${SVCS[@]}"; do
    IFS=':' read -r svc remote local <<< "$entry"
    container="smart-core-v2-${ENVNAME}-${svc}-1"
    ip=$(ssh "$SSH_ALIAS" "docker inspect -f '{{(index .NetworkSettings.Networks \"$NET\").IPAddress}}' $container" 2>/dev/null | tr -d '[:space:]')
    if [ -z "$ip" ]; then
        echo "  ! $container nao encontrado/na rede (pulando)"
        continue
    fi
    FW+=("-L" "${local}:${ip}:${remote}")
    printf "  localhost:%-5s -> %s:%s  (%s)\n" "$local" "$ip" "$remote" "$svc"
done

if [ ${#FW[@]} -eq 0 ]; then
    echo "Nenhum container encontrado para o ambiente '$ENVNAME'. A stack esta no ar?"
    exit 1
fi

echo ""
echo "Conexoes locais (use a senha do env do ambiente):"
echo "  DATABASE_URL = postgresql://smartcore_app:SENHA@localhost:5434/smartcore_v2"
echo "  REDIS_URL    = redis://:SENHA@localhost:6379"
echo "  REDIS_BUS    = redis://:SENHA@localhost:6380"
echo "  MinIO API    = http://localhost:9000"
echo ""
echo "Tunel ativo. Ctrl+C para encerrar."

ssh "${FW[@]}" -N "$SSH_ALIAS"
