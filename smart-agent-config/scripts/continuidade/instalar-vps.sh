#!/usr/bin/env bash
# Instala a continuidade após limite no VPS (root). Idempotente; faz backup de
# tudo que altera em /root/.claude/backups/continuidade-<data>/.
#
#   bash smart-agent-config/scripts/continuidade/instalar-vps.sh            # instala e ativa
#   bash smart-agent-config/scripts/continuidade/instalar-vps.sh --so-validar
#
# Pré-requisito: checkout espelho em /opt/smartcore/ops/smart-core-assistant-v2
# atualizado com `git pull --ff-only origin dev`.
set -euo pipefail

RAIZ=/opt/smartcore/ops/smart-core-assistant-v2/smart-agent-config
SCRIPT="$RAIZ/.claude/hooks/continuidade.py"
DIR_UNIDADES="$RAIZ/scripts/continuidade"
SETTINGS=/root/.claude/settings.json
BACKUP="/root/.claude/backups/continuidade-$(date +%Y%m%d%H%M%S)"

test -f "$SCRIPT" || { echo "faltando $SCRIPT (atualize o checkout)"; exit 1; }

echo "== validação (py_compile + leitura)"
python3 -m py_compile "$SCRIPT" "$RAIZ/.claude/hooks/roteador.py"
python3 "$SCRIPT" --status
python3 "$SCRIPT" --verificar --seco
if [ "${1:-}" = "--so-validar" ]; then exit 0; fi

echo "== backup em $BACKUP"
mkdir -p "$BACKUP"
cp -a "$SETTINGS" "$BACKUP/" 2>/dev/null || true
for u in roteador-continuidade.service roteador-continuidade.timer; do
  cp -a "/etc/systemd/system/$u" "$BACKUP/" 2>/dev/null || true
done

echo "== ganchos em $SETTINGS"
python3 "$SCRIPT" --registrar-hooks "$SETTINGS"
python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$SETTINGS"

echo "== unidades systemd"
install -m 644 "$DIR_UNIDADES/roteador-continuidade.service" /etc/systemd/system/
install -m 644 "$DIR_UNIDADES/roteador-continuidade.timer" /etc/systemd/system/
systemd-analyze verify /etc/systemd/system/roteador-continuidade.service /etc/systemd/system/roteador-continuidade.timer
systemctl daemon-reload
systemctl enable --now roteador-continuidade.timer
systemctl list-timers roteador-continuidade.timer --no-pager
echo "ok. Log: journalctl -u roteador-continuidade -n 50 · estado: python3 $SCRIPT --status"
