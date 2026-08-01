#!/bin/sh
# Sonda do serviço de backup.
#
# O container do backup passa quase todo o tempo dormindo, então "processo vivo"
# não diz nada sobre ele estar funcionando. O que interessa é se houve um backup
# BEM-SUCEDIDO dentro da janela esperada — um serviço que acorda, falha no
# pg_dump e volta a dormir continua `running` para sempre.
#
# A tolerância é de 1,5x o intervalo: cobre atraso normal de execução sem deixar
# passar um ciclo inteiro perdido.
set -eu

DESTINO="${BACKUP_DIR:-/backups}"
INTERVALO="${BACKUP_INTERVALO_SEGUNDOS:-86400}"
MARCA_SUCESSO="$DESTINO/.ultimo_sucesso"

# Ainda não houve o primeiro backup: o start_period do compose cobre a janela de
# subida; passado ele, ausência de marca é falha de verdade.
[ -f "$MARCA_SUCESSO" ] || exit 1

ultimo="$(cat "$MARCA_SUCESSO")"
agora="$(date -u +%s)"
limite="$((INTERVALO + INTERVALO / 2))"

[ "$((agora - ultimo))" -le "$limite" ]
