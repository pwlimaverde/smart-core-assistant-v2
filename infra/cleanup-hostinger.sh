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

echo "2. Caddy do host: REMOVIDO (a borda agora e o container edge)."
# A borda 80/443 e o container Caddy (docker/edge), que roteia TUDO: v1
# (smartcoreassistant_app:8000 via shared_network), v2 admin (web + runtime_api) e
# grafana. O Caddy do host fica redundante e e removido para o host ficar limpo.
# Faz backup da config antes (rollback de emergencia).
if command -v caddy &>/dev/null || systemctl list-unit-files 2>/dev/null | grep -q '^caddy'; then
    mkdir -p /opt/smartcore/backups/host-caddy
    cp -a /etc/caddy /opt/smartcore/backups/host-caddy/etc-caddy 2>/dev/null || true
    systemctl disable --now caddy 2>/dev/null || true
    apt-get purge -y caddy >/dev/null 2>&1 || true
    rm -rf /srv/smart-core-admin /var/log/caddy
    echo "  Caddy do host removido; /srv/smart-core-admin limpo."
else
    echo "  (Caddy do host ja ausente)"
fi

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
