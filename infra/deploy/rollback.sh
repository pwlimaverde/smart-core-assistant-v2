#!/usr/bin/env bash
# =============================================================================
# Volta um ambiente para um bundle já implantado antes.
#
#   [ACEITO_MIGRACAO=sim] [ENV_FILE_B64=...] rollback.sh <dev|prod> <vX.Y.Z>
#
# Rollback = reimplantar o bundle da versão alvo (compose, scripts e tags de
# imagem daquela versão). Nada de `pull && down && up`: `pull` traria a mesma
# versão e `down` derrubaria tudo sem necessidade.
#
# Portão de migração: as migrações só andam para frente. Se a versão em uso
# aplicou migração que a alvo não conhece, a alvo pode não entender o schema;
# o rollback só segue com ACEITO_MIGRACAO=sim (ver RUNBOOK_DEPLOY.md).
# =============================================================================
set -euo pipefail
# shellcheck source=infra/deploy/lib.sh
source "$(dirname "$0")/lib.sh"

[ $# -eq 2 ] || erro "uso: rollback.sh <dev|prod> <release-id>"
valida_ambiente "$1"; valida_release_id "$2"
caminhos "$1"
ALVO="$2"
ATUAL="$(release_de current)"

if [ ! -d "$DIR_RELEASES/$ALVO" ]; then
  disponiveis=$(find "$DIR_RELEASES" -mindepth 1 -maxdepth 1 -type d -name 'v*' -printf '%f ' 2>/dev/null)
  erro "bundle $ALVO não existe em $DIR_RELEASES (disponíveis: ${disponiveis:-nenhum})"
fi
[ "$ALVO" != "$ATUAL" ] || aviso "$ALVO já é o current — reaplicando (útil após rotação de segredo)"

# As imagens daquela versão ainda existem no GHCR (ou no disco)?
while IFS='=' read -r var tag; do
  for par in "${IMAGENS_APP[@]}"; do
    [ "${par#*=}" = "$var" ] || continue
    img="$REGISTRO/${par%%=*}:$tag"
    docker image inspect "$img" >/dev/null 2>&1 || docker manifest inspect "$img" >/dev/null 2>&1 \
      || erro "imagem $img não encontrada (nem local nem no GHCR)"
  done
done < "$DIR_RELEASES/$ALVO/images.env"

if [ -n "$ATUAL" ] && [ -f "$DIR_RELEASES/$ATUAL/MIGRATIONS" ]; then
  novas=$(comm -23 <(sort "$DIR_RELEASES/$ATUAL/MIGRATIONS") <(sort "$DIR_RELEASES/$ALVO/MIGRATIONS") || true)
  if [ -n "$novas" ]; then
    echo "Migrações aplicadas por $ATUAL que $ALVO não conhece:"
    while read -r m; do echo "  - $m"; done <<< "$novas"
    [ "${ACEITO_MIGRACAO:-nao}" = sim ] \
      || erro "rollback recusado: há migração à frente de $ALVO. Leia RUNBOOK_DEPLOY.md e rode com aceito_migracao=sim"
    aviso "ACEITO_MIGRACAO=sim — seguindo com schema à frente da versão alvo"
  fi
fi

EVENTO=rollback exec "$(dirname "$0")/deploy.sh" "$AMB" "$ALVO"
