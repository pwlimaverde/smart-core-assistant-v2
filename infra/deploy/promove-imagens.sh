#!/usr/bin/env bash
# =============================================================================
# Dá a TODAS as imagens da aplicação uma mesma tag de versão, sem rebuild, e
# escreve o images.env do bundle.
#
#   promove-imagens.sh <tag-destino> <saida images.env> <tag-origem-padrão> \
#                      [<pacote>=<tag-origem> ...]
#
# Ex.: promove-imagens.sh 0.2.0-beta.3 /tmp/images.env 0.2.0-beta.2 \
#        smartcore-server=sha-1a2b3c4
#   -> o server (reconstruído agora) e as demais imagens (herdadas da beta.2)
#      passam a existir também como :0.2.0-beta.3.
#
# `imagetools create` só cria um novo nome para o mesmo digest: segundos, sem
# build. É o que permite a prod usar exatamente o binário testado na dev.
# =============================================================================
set -euo pipefail
# shellcheck source=infra/deploy/lib.sh
source "$(dirname "$0")/lib.sh"

[ $# -ge 3 ] || erro "uso: promove-imagens.sh <tag-destino> <saida> <origem-padrão> [pacote=origem ...]"
DESTINO="$1"; SAIDA="$2"; PADRAO="$3"; shift 3
[[ "$DESTINO" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(beta|rc)\.[0-9]+)?$ ]] || erro "tag-destino inválida: $DESTINO"

declare -A ORIGEM=()
for arg in "$@"; do ORIGEM["${arg%%=*}"]="${arg#*=}"; done

: > "$SAIDA"
for par in "${IMAGENS_APP[@]}"; do
  pacote="${par%%=*}"; var="${par#*=}"
  origem="${ORIGEM[$pacote]:-$PADRAO}"
  if [ "$origem" != "$DESTINO" ]; then
    docker buildx imagetools create --tag "$REGISTRO/$pacote:$DESTINO" "$REGISTRO/$pacote:$origem" >/dev/null \
      || erro "falha ao promover $pacote:$origem -> $DESTINO"
  fi
  echo "ok  $pacote:$origem -> $DESTINO"
  echo "$var=$DESTINO" >> "$SAIDA"
done
