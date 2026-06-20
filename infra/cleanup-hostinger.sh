#!/usr/bin/env bash
# =============================================================================
# Script de Limpeza de Infraestrutura Legada (systemd + Caddy no host)
# Executar como root: sudo bash cleanup-hostinger.sh
# =============================================================================
set -euo pipefail

echo "============================================================"
echo " Limpando serviços legados do host Hostinger KVM2"
echo "============================================================"

# Listagem de serviços Rust no systemd
SERVICES=(
    "control_plane"
    "data_postgres"
    "data_redis"
    "data_storage"
    "messaging_gateway"
    "runtime_api"
    "worker"
)

echo "1. Parando e desabilitando serviços systemd do SmartCore..."
for env in "dev" "prod"; do
    # Desativa target principal do ambiente
    if systemctl is-active "smartcore-$env.target" &>/dev/null; then
        echo "Parando smartcore-$env.target..."
        systemctl stop "smartcore-$env.target" || true
        systemctl disable "smartcore-$env.target" || true
    fi

    # Desativa cada serviço individualmente
    for svc in "${SERVICES[@]}"; do
        NAME="smartcore-$env-$svc.service"
        if systemctl is-active "$NAME" &>/dev/null || systemctl is-enabled "$NAME" &>/dev/null; then
            echo "Desabilitando $NAME..."
            systemctl stop "$NAME" || true
            systemctl disable "$NAME" || true
        fi
        # Remove arquivo físico do systemd
        rm -f "/etc/systemd/system/$NAME"
    done
    rm -f "/etc/systemd/system/smartcore-$env.target"
done

echo "2. Parando e desabilitando Caddy no host..."
if systemctl is-active caddy &>/dev/null || systemctl is-enabled caddy &>/dev/null; then
    echo "Desabilitando Caddy..."
    systemctl stop caddy || true
    systemctl disable caddy || true
fi
# Opcional: remove arquivo do Caddy no host para evitar conflito
rm -f /etc/caddy/Caddyfile || true

echo "3. Recarregando daemon do systemd..."
systemctl daemon-reload
systemctl reset-failed

echo "4. Removendo pastas de execução temporárias (/run/smartcore)..."
rm -rf /run/smartcore /run/smartcore-dev
rm -f /etc/tmpfiles.d/smartcore.conf || true

echo "============================================================"
echo " Limpeza do legado concluída com sucesso!"
echo " As portas 80, 443 e os binários do host estão liberados."
echo "============================================================"
