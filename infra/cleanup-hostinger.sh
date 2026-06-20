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

echo "2. Caddy do host: MANTIDO (NAO tocar)."
# ATENCAO: neste servidor o Caddy do host e a BORDA COMPARTILHADA — serve o painel
# v1 (smartcoreassistant.com.br) e roteia o admin v2 (conf.d/admin.caddy ->
# localhost:50051 + /srv/smart-core-admin). Para-lo derrubaria o v1. A stack v2
# full-docker NAO sobe um Caddy proprio em 80/443; o runtime_api publica 50051 no
# host e o Caddy do host faz o reverse_proxy. Portanto, NAO paramos nem removemos
# o Caddy aqui.

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
