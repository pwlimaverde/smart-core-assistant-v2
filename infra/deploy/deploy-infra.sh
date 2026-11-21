#!/usr/bin/env bash
# =============================================================================
# Implanta um componente da infraestrutura COMPARTILHADA (dev e prod usam o
# mesmo): edge (Caddy, 80/443), observability (LGTM), evolution (WhatsApp).
#
#   [EDGE_IMAGE=...] [OBS_ENV_FILE_B64=...] [EVOLUTION_ENV_FILE_B64=...] \
#     deploy-infra.sh <edge|observability|evolution> <id>
#
# Mesmo desenho do deploy da aplicação: bundle em
# /opt/smartcore/infra/<componente>/releases/<id>/ (cópia de docker/<componente>),
# link `current`, smoke test e retorno automático ao bundle anterior.
#
# Bônus do bundle: os configs da observabilidade entram por bind mount, e
# `up -d` não recriava o container quando só o CONTEÚDO do arquivo mudava (os
# painéis do Grafana passaram dois meses vazios assim). Com o caminho do bundle
# mudando a cada deploy, o compose enxerga a mudança e recria — sem precisar de
# --force-recreate na stack inteira.
# =============================================================================
set -euo pipefail
# shellcheck source=infra/deploy/lib.sh
source "$(dirname "$0")/lib.sh"

[ $# -eq 2 ] || erro "uso: deploy-infra.sh <edge|observability|evolution> <id>"
COMP="$1"; ID="$2"
case "$COMP" in edge|observability|evolution) ;; *) erro "componente inválido: $COMP" ;; esac
[[ "$ID" =~ ^[A-Za-z0-9._-]+$ ]] || erro "id inválido: $ID"

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BASE_COMP="$SMARTCORE_RAIZ/infra/$COMP"
DIR_REL="$BASE_COMP/releases"
BUNDLE="$DIR_REL/$ID"
PROJ="smart-core-v2-$COMP"
LOG="$SMARTCORE_RAIZ/infra/deploys.log"
INICIO=$(date +%s)

# Arquivo de ambiente de cada componente (fora do bundle: é estado do servidor).
case "$COMP" in
  observability) ARQ_ENV="$SMARTCORE_RAIZ/observability/env/observability.env"; B64="${OBS_ENV_FILE_B64:-}" ;;
  evolution)     ARQ_ENV="$BASE_COMP/env/evolution.env"; B64="${EVOLUTION_ENV_FILE_B64:-}" ;;
  edge)          ARQ_ENV="$BASE_COMP/env/edge.env"; B64="" ;;
esac

dci() {
  local b="$1"; shift
  docker compose -p "$PROJ" --project-directory "$b" -f "$b/compose.yml" --env-file "$b/.env" "$@"
}
anterior() { [ -L "$DIR_REL/current" ] && basename "$(readlink "$DIR_REL/current")" || true; }
marca() {
  printf 'ts=%s event=deploy-infra componente=%s version=%s sha=%s run=%s status=%s duracao_s=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$COMP" "$ID" "${GITHUB_SHA:-manual}" "${GITHUB_RUN_ID:-manual}" \
    "$1" "$(( $(date +%s) - INICIO ))" >> "$LOG"
}

# --- env ---------------------------------------------------------------------
mkdir -p "$(dirname "$ARQ_ENV")"
if [ -n "$B64" ]; then
  ( umask 077; tmp="$(mktemp "$ARQ_ENV.XXXXXX")"
    printf '%s' "$B64" | base64 -d > "$tmp" 2>/dev/null && [ -s "$tmp" ] || { rm -f "$tmp"; erro "secret de env do $COMP inválido"; }
    mv -f "$tmp" "$ARQ_ENV" )
  info "env do $COMP materializado ($(grep -cE '^[A-Z0-9_]+=' "$ARQ_ENV") chaves)"
fi
if [ "$COMP" = edge ]; then
  [ -n "${EDGE_IMAGE:-}" ] || erro "EDGE_IMAGE não informado"
  ( umask 077; printf 'EDGE_IMAGE=%s\n' "$EDGE_IMAGE" > "$ARQ_ENV" )
fi
[ -f "$ARQ_ENV" ] || erro "$ARQ_ENV inexistente e sem secret para materializar"

# --- bundle --------------------------------------------------------------------
[ "$(anterior)" != "$ID" ] || erro "$ID já é o current de $COMP"
mkdir -p "$DIR_REL"
TMP="$(mktemp -d "$DIR_REL/.montando-XXXXXX")"
cp -r "$REPO/docker/$COMP/." "$TMP/"
rm -f "$TMP/.env"
ln -s "$ARQ_ENV" "$TMP/.env"
chmod -R u+rwX,go+rX,go-w "$TMP"; chmod 755 "$TMP"
rm -rf "$BUNDLE"; mv "$TMP" "$BUNDLE"
info "bundle $COMP pronto: $BUNDLE"

# --- pré-condições ---------------------------------------------------------------
if [ "$COMP" = observability ]; then
  # Redes de telemetria da prod: externas para esta stack (ver compose).
  for rede in smart_core_v2_telemetria_prod smart_core_v2_mcp_telemetria_prod; do
    docker network inspect "$rede" >/dev/null 2>&1 || docker network create "$rede" >/dev/null
  done
fi
if [ "$COMP" = edge ]; then
  # A borda roteia o site inteiro: Caddyfile inválido = tudo fora do ar.
  docker pull -q "$EDGE_IMAGE" >/dev/null
  docker run --rm "$EDGE_IMAGE" caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1 \
    || erro "Caddyfile da imagem $EDGE_IMAGE é inválido — borda NÃO foi tocada"
  info "Caddyfile válido"
fi
dci "$BUNDLE" config -q || erro "compose config reprovado para $COMP"

# --- smoke -------------------------------------------------------------------------
smoke() {
  local b="$1" falhas="" svc cid status restarts health espera
  local tpl='{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}'
  sleep 15
  for svc in $(dci "$b" config --services); do
    cid=$(dci "$b" ps -q "$svc" 2>/dev/null || true)
    [ -n "$cid" ] || { echo "::error::$COMP/$svc: container inexistente"; falhas="$falhas $svc"; continue; }
    status=$(docker inspect -f '{{.State.Status}}' "$cid")
    restarts=$(docker inspect -f '{{.RestartCount}}' "$cid")
    health=$(docker inspect -f "$tpl" "$cid"); espera=0
    while [ "$health" = starting ] && [ "$espera" -lt 120 ]; do sleep 5; espera=$((espera + 5)); health=$(docker inspect -f "$tpl" "$cid"); done
    if [ "$status" != running ] || [ "$restarts" -gt 2 ] || [ "$health" = unhealthy ] || [ "$health" = starting ]; then
      echo "::error::$COMP/$svc: status=$status restarts=$restarts health=$health"
      docker logs --tail 30 "$cid" 2>&1 || true
      falhas="$falhas $svc"
    else
      echo "ok  $COMP/$svc (status=$status restarts=$restarts health=$health)"
    fi
  done
  if [ "$COMP" = edge ]; then
    local dominio codigo
    for dominio in smartcoreassistant.com.br dev.smartcoreassistant.com.br; do
      codigo=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://$dominio/" || echo 000)
      if [ "$codigo" = 000 ]; then echo "::error::https://$dominio/ não responde"; falhas="$falhas $dominio"
      else echo "ok  https://$dominio/ HTTP $codigo"; fi
    done
  fi
  [ -z "$falhas" ]
}

ANT="$(anterior)"
if dci "$BUNDLE" up -d --pull missing --quiet-pull --remove-orphans && smoke "$BUNDLE"; then
  ln -sfn "$ID" "$DIR_REL/.current.tmp" && mv -Tf "$DIR_REL/.current.tmp" "$DIR_REL/current"
  marca ok
  # Retenção: 5 bundles por componente (o current nunca sai).
  find "$DIR_REL" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -printf '%T@ %f\n' | sort -rn | tail -n +6 \
    | cut -d' ' -f2- | while read -r velho; do [ "$velho" = "$ID" ] || rm -rf "${DIR_REL:?}/$velho"; done
  echo "infra $COMP implantada: $ID"
  exit 0
fi

marca falha
if [ -n "$ANT" ] && [ -d "$DIR_REL/$ANT" ]; then
  aviso "reaplicando $COMP $ANT"
  dci "$DIR_REL/$ANT" up -d --remove-orphans && smoke "$DIR_REL/$ANT" \
    && erro "$COMP $ID reprovado; voltou para $ANT"
  erro "$COMP $ID reprovado E o retorno para $ANT falhou — intervenção manual"
fi
erro "$COMP $ID reprovado e não há bundle anterior (primeiro deploy por bundle) — conferir à mão"
