#!/usr/bin/env bash
# =============================================================================
# Implanta um bundle num ambiente. Script ÚNICO para dev e prod (e para o
# rollback, que é só implantar um bundle anterior).
#
#   [ENV_FILE_B64=...] deploy.sh <dev|prod> <release-id>
#
# Passos:
#   1. materializa o .env a partir de ENV_FILE_B64 (secret do environment),
#      escrita atômica com umask 077 — o conteúdo decodificado nunca vai ao log
#   2. valida chaves obrigatórias/proibidas (required-keys.<env>)
#   3. `compose config` (pega variável faltando antes de tocar container)
#   4. pg_dump validado do banco no ar (aborta se falhar)
#   5. pull + up -d --remove-orphans
#   6. smoke.sh
#   7. sucesso: current -> <id>, previous -> anterior, marcador, poda
#      falha:   reaplica o bundle anterior (se houver), marcador, exit 1
#
# NUNCA rodar com `set -x`: o passo 1 manipula o arquivo de segredos.
# =============================================================================
set -euo pipefail
# shellcheck source=infra/deploy/lib.sh
source "$(dirname "$0")/lib.sh"
DIR_SCRIPTS="$(cd "$(dirname "$0")" && pwd)"

[ $# -eq 2 ] || erro "uso: deploy.sh <dev|prod> <release-id>"
valida_ambiente "$1"; valida_release_id "$2"
caminhos "$1"
ID="$2"
BUNDLE="$DIR_RELEASES/$ID"
INICIO=$(date +%s)
[ -d "$BUNDLE" ] || erro "bundle inexistente: $BUNDLE (rode bundle.sh antes)"

# --- 1. materialização do .env ------------------------------------------------
mkdir -p "$(dirname "$ARQ_ENV")"
if [ -n "${ENV_FILE_B64:-}" ]; then
  ( umask 077
    tmp="$(mktemp "$ARQ_ENV.XXXXXX")"
    if ! printf '%s' "$ENV_FILE_B64" | base64 -d > "$tmp" 2>/dev/null || [ ! -s "$tmp" ]; then
      rm -f "$tmp"; erro "ENV_FILE_B64 inválido (base64 malformado ou vazio)"
    fi
    mv -f "$tmp" "$ARQ_ENV" )
  info "env materializado: $AMB ($(grep -cE '^[A-Z0-9_]+=' "$ARQ_ENV") chaves)"
else
  aviso "ENV_FILE_B64 ausente — usando o $ARQ_ENV que já está no servidor"
fi
[ -f "$ARQ_ENV" ] || erro "$ARQ_ENV não existe e ENV_FILE_B64 não foi fornecido"

# --- 2. chaves obrigatórias e proibidas (só nomes vão ao log) ------------------
faltando=""
while read -r chave; do
  [ -z "$chave" ] || [[ "$chave" == \#* ]] && continue
  grep -qE "^${chave}=.+" "$ARQ_ENV" || faltando="$faltando $chave"
done < "$DIR_SCRIPTS/required-keys.$AMB"
[ -z "$faltando" ] || erro "$ARQ_ENV sem chaves obrigatórias:$faltando"
# COMPOSE_PROJECT_NAME sobreporia o -p e jogaria a stack em outro projeto.
proibidas='^COMPOSE_PROJECT_NAME='
[ "$AMB" = prod ] && proibidas="$proibidas|^MINIO_"
if grep -qE "$proibidas" "$ARQ_ENV"; then
  erro "$ARQ_ENV contém chave proibida: $(grep -oE "$proibidas" "$ARQ_ENV" | tr '\n' ' ')"
fi

# --- 3. config ------------------------------------------------------------------
garante_redes "$BUNDLE"
dc "$BUNDLE" config -q || erro "compose config reprovado para $BUNDLE"

# --- 3b. gate do cutover para o provider_edge -----------------------------------
# Com a URL do webhook apontando para o provider_edge (ADR
# adr-intermediario-webhooks-provedores.md, §5), o Evolution passa a entregar
# TODAS as mensagens do ambiente por ele. Se ele não estiver no ar, o ambiente
# para de receber mensagens sem nenhum erro visível. Por isso o deploy só segue
# se o caminho inteiro responde: Evolution-net -> provider_edge -> ingress deste
# ambiente. Roda antes do backup e de qualquer container ser tocado: reprovado,
# nada muda no servidor.
#
# Prova ponta a ponta: POST com corpo que não é JSON no caminho do webhook. O
# ingress responde 400 antes de autenticar ou auditar (nada é gravado). O
# provider_edge só produz 404 (ambiente desconhecido), 502 (destino fora) e 504
# (destino lento); qualquer outro código veio do ingress do ambiente.
# Bloqueia: edge fora de healthy, 000 (nome/porta da URL inalcançável na
# evolution_net) e 404 (ambiente ausente em PROVIDER_EDGE_DESTINOS). 502/503/504
# só avisam: o ingress do ambiente pode estar fora justamente porque este deploy
# é o conserto, e travar o deploy deixaria o ambiente sem saída.
#
# Rollback (EVENTO=rollback) só avisa: travar o retorno a um bundle bom deixaria
# a release ruim no ar.
#
# A URL sai do `compose config` em JSON, sem jq (o host não precisa dele). A
# chave só existe no data_whatsapp.
url_webhook=$(dc "$BUNDLE" config --format json \
  | grep -oE '"WEBHOOK_INGRESS_URL": *"[^"]*"' | head -n1 | sed -E 's/.*: *"([^"]*)"/\1/' || true)
bloqueia_cutover() {
  if [ "${EVENTO:-deploy}" = rollback ]; then aviso "rollback segue apesar do gate: $*"; else erro "$*"; fi
}
if [[ "$url_webhook" == *provider_edge* || "$url_webhook" == *provider-edge* ]]; then
  saude=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}sem-healthcheck{{end}}' \
    smartcore-provider-edge 2>/dev/null || echo inexistente)
  [ "$saude" = healthy ] \
    || bloqueia_cutover "cutover bloqueado: WEBHOOK_INGRESS_URL=$url_webhook, mas o provider_edge está '$saude'. Suba-o pelo deploy-infra (evolution) ou volte a URL no $AMB.vars/override."
  codigo=$(docker exec smartcore-provider-edge curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
    -X POST -H 'content-type: application/json' --data 'gate-de-cutover' \
    "${url_webhook%/}/webhook/evolution/00000000-0000-0000-0000-000000000000/0" 2>/dev/null || true)
  case "${codigo:-000}" in
    000|404)
      bloqueia_cutover "cutover bloqueado: $url_webhook não é atendido pelo provider_edge para o $AMB (HTTP ${codigo:-000}). Conferir a URL e PROVIDER_EDGE_DESTINOS no evolution.env." ;;
    502|503|504)
      aviso "cutover: provider_edge healthy, mas o ingress do $AMB não respondeu (HTTP $codigo); segue, este deploy sobe o ingress" ;;
    *)
      info "cutover: provider_edge healthy e repassando ao ingress do $AMB (HTTP $codigo)" ;;
  esac
fi

ANTERIOR="$(release_de current)"
info "ambiente=$AMB versão=$ID anterior=${ANTERIOR:-nenhuma}"

# --- 4. backup pré-deploy --------------------------------------------------------
# Único ponto de retorno se a release corromper dados. Com o banco no ar, backup
# que falha ABORTA o deploy; banco ausente é o primeiro deploy (legítimo).
if [ -n "$(docker ps -q --filter "label=com.docker.compose.project=$PROJETO" --filter label=com.docker.compose.service=postgres)" ]; then
  mkdir -p "$DIR_BACKUP_DEPLOY"
  arq="$DIR_BACKUP_DEPLOY/pre-deploy-$ID-$(date -u +%Y%m%d%H%M%S).dump"
  pg_user=$(le_chave "$ARQ_ENV" POSTGRES_USER); pg_db=$(le_chave "$ARQ_ENV" POSTGRES_DB)
  if ! dc "$BUNDLE" exec -T postgres pg_dump -U "$pg_user" -F c "$pg_db" > "$arq"; then
    rm -f "$arq"; erro "pg_dump falhou — deploy abortado (sem ponto de retorno)"
  fi
  tamanho=$(stat -c%s "$arq")
  if [ "$tamanho" -lt 1024 ] || [ "$(head -c 5 "$arq")" != "PGDMP" ]; then
    erro "backup suspeito ($arq, $tamanho bytes) — deploy abortado"
  fi
  chmod 600 "$arq"
  info "backup pré-deploy: $arq ($tamanho bytes)"
  # Retenção: 10 dumps de pré-deploy por ambiente.
  find "$DIR_BACKUP_DEPLOY" -maxdepth 1 -name 'pre-deploy-*.dump' -printf '%T@ %p\n' \
    | sort -rn | tail -n +11 | cut -d' ' -f2- | xargs -r rm -f
else
  info "postgres do $PROJETO não está no ar — primeiro deploy, sem backup"
fi

# --- 5/6. sobe e verifica ---------------------------------------------------------
# `--pull missing`: baixa só o que não está em disco. Tag de versão é imutável,
# então imagem presente é a imagem certa — e o rollback funciona mesmo sem acesso
# ao GHCR (pacotes privados; fora do workflow o runner não tem login). Também
# evita que `pgvector:pg16`/`redis:7-alpine` mudem de versão em silêncio a cada
# deploy: atualizar imagem base passa a ser decisão explícita.
sobe() {
  local bundle="$1"
  dc "$bundle" up -d --pull missing --quiet-pull --remove-orphans
}

if sobe "$BUNDLE" && "$DIR_SCRIPTS/smoke.sh" "$AMB" "$ID"; then
  if [ -n "$ANTERIOR" ] && [ "$ANTERIOR" != "$ID" ]; then aponta previous "$ANTERIOR"; fi
  aponta current "$ID"
  marcador "${EVENTO:-deploy}" "$ID" ok $(( $(date +%s) - INICIO ))
  # Retenção de bundles (texto puro; as imagens ficam no GHCR): 5 na dev, 10
  # na prod. current e previous nunca são podados.
  manter=$([ "$AMB" = prod ] && echo 10 || echo 5)
  find "$DIR_RELEASES" -mindepth 1 -maxdepth 1 -type d -name 'v*' -printf '%T@ %f\n' \
    | sort -rn | tail -n +$((manter + 1)) | cut -d' ' -f2- \
    | while read -r velho; do
        [ "$velho" = "$(release_de current)" ] || [ "$velho" = "$(release_de previous)" ] \
          || rm -rf "${DIR_RELEASES:?}/$velho"
      done
  echo "deploy concluído: $AMB $ID ($(( $(date +%s) - INICIO ))s)"
  exit 0
fi

# --- falha: volta ao bundle anterior ---------------------------------------------
marcador "${EVENTO:-deploy}" "$ID" falha $(( $(date +%s) - INICIO ))
if [ -n "$ANTERIOR" ] && [ "$ANTERIOR" != "$ID" ] && [ -d "$DIR_RELEASES/$ANTERIOR" ]; then
  aviso "reaplicando o bundle anterior $ANTERIOR"
  if sobe "$DIR_RELEASES/$ANTERIOR" && "$DIR_SCRIPTS/smoke.sh" "$AMB" "$ANTERIOR"; then
    marcador rollback-automatico "$ANTERIOR" ok $(( $(date +%s) - INICIO ))
    erro "$ID reprovado no smoke test; $AMB voltou para $ANTERIOR"
  fi
  marcador rollback-automatico "$ANTERIOR" falha $(( $(date +%s) - INICIO ))
  erro "$ID reprovado E o retorno para $ANTERIOR também falhou — intervenção manual"
fi
erro "$ID reprovado no smoke test e não há bundle anterior para voltar"
