#!/usr/bin/env bash
# =============================================================================
# Biblioteca comum dos scripts de deploy (bundle, deploy, smoke, rollback).
# Não executar diretamente: `source "$(dirname "$0")/lib.sh"`.
#
# Layout no servidor (Fase R3 do plano servidor-reestruturacao-dev-prod):
#   /opt/smartcore/<env>/env/<env>.env           segredos, materializados do
#                                                secret ENV_FILE_B64 (600)
#   /opt/smartcore/<env>/releases/<id>/          bundle imutável de uma versão
#   /opt/smartcore/<env>/releases/current -> <id>
#   /opt/smartcore/<env>/releases/previous -> <id>
#   /opt/smartcore/<env>/backups-deploy/         pg_dump antes de cada deploy
#   /opt/smartcore/<env>/deploys.log             marcadores event=deploy|rollback
# =============================================================================

# As variáveis abaixo são consumidas pelos scripts que fazem `source` deste.
# shellcheck disable=SC2034

# Raiz configurável só para teste (CI); em produção é sempre /opt/smartcore.
SMARTCORE_RAIZ="${SMARTCORE_RAIZ:-/opt/smartcore}"
REGISTRO="ghcr.io/pwlimaverde/smart-core-assistant-v2"

# Imagens da aplicação: <nome do pacote GHCR>=<variável no images.env>.
IMAGENS_APP=(
  "smartcore-server=SERVER_TAG"
  "smartcore-ia-engine=IA_ENGINE_TAG"
  "smartcore-ia-engine-jev=IA_ENGINE_JEV_TAG"
  "smartcore-mcp-server=MCP_SERVER_TAG"
  "smartcore-web=WEB_TAG"
  "smartcore-web-tenant=WEB_TENANT_TAG"
)

# Serviços one-shot (terminam com sucesso): fora do smoke test.
SERVICOS_ONE_SHOT="minio-setup"

erro() { echo "::error::$*" >&2; exit 1; }
aviso() { echo "::warning::$*" >&2; }
info() { echo "--> $*"; }

valida_ambiente() {
  case "${1:-}" in
    dev|prod) ;;
    *) erro "ambiente inválido: '${1:-}' (use dev ou prod)" ;;
  esac
}

# Id de release: vX.Y.Z, vX.Y.Z-beta.N ou vX.Y.Z-rc.N.
valida_release_id() {
  [[ "${1:-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-(beta|rc)\.[0-9]+)?$ ]] \
    || erro "id de release inválido: '${1:-}' (esperado vX.Y.Z[-beta.N])"
}

# Define as variáveis de caminho de um ambiente.
# shellcheck disable=SC2034
caminhos() {
  AMB="$1"
  BASE_AMB="$SMARTCORE_RAIZ/$AMB"
  DIR_RELEASES="$BASE_AMB/releases"
  ARQ_ENV="$BASE_AMB/env/$AMB.env"
  DIR_BACKUP_DEPLOY="$BASE_AMB/backups-deploy"
  LOG_DEPLOYS="$BASE_AMB/deploys.log"
  PROJETO="smart-core-v2-$AMB"
}

# docker compose de um bundle: base + overlay + env + vars + imagens. A ordem
# dos --env-file importa: o seguinte vence o anterior, então topologia (.vars)
# e imagens (images.env) não podem ser sobrescritas por engano pelo .env.
dc() {
  local bundle="$1"; shift
  docker compose -p "$PROJETO" --project-directory "$bundle" \
    -f "$bundle/docker-compose.base.yml" -f "$bundle/$AMB.override.yml" \
    --env-file "$bundle/.env" --env-file "$bundle/$AMB.vars" \
    --env-file "$bundle/images.env" "$@"
}

# Lê uma chave de um arquivo KEY=VALOR sem passar pelo shell (nada de source:
# o .env tem PEM multilinha e valores com caracteres especiais).
le_chave() {
  local arq="$1" chave="$2"
  grep -E "^${chave}=" "$arq" | head -n1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'
}

# Id do bundle para onde um link (current/previous) aponta, ou vazio.
release_de() {
  local link="$DIR_RELEASES/$1"
  if [ -L "$link" ]; then basename "$(readlink "$link")"; fi
}

# Troca um symlink de forma atômica (ln + mv -T).
aponta() {
  local nome="$1" alvo="$2"
  ln -sfn "$alvo" "$DIR_RELEASES/.$nome.tmp"
  mv -Tf "$DIR_RELEASES/.$nome.tmp" "$DIR_RELEASES/$nome"
}

# Marcador de deploy: uma linha por evento, sem segredo. O promtail pode ler
# este arquivo para anotações no Grafana.
marcador() {
  local evento="$1" versao="$2" status="$3" duracao="$4"
  printf 'ts=%s event=%s env=%s version=%s sha=%s run=%s status=%s duracao_s=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$evento" "$AMB" "$versao" \
    "${GITHUB_SHA:-manual}" "${GITHUB_RUN_ID:-manual}" "$status" "$duracao" \
    >> "$LOG_DEPLOYS"
}

# Redes externas que o compose do ambiente consome. As de telemetria são por
# ambiente; se faltarem, são criadas e o otel-collector é ligado a elas (o
# compose da observabilidade também as declara, para sobreviver a recreate).
garante_redes() {
  local bundle="$1" rede
  for rede in $(le_chave "$bundle/$AMB.vars" OBS_NET) $(le_chave "$bundle/$AMB.vars" MCP_TELEMETRIA_NET); do
    if ! docker network inspect "$rede" >/dev/null 2>&1; then
      info "criando rede de telemetria $rede"
      docker network create "$rede" >/dev/null
    fi
    local coletor
    coletor=$(docker ps -q --filter label=com.docker.compose.project=smart-core-v2-observability \
      --filter label=com.docker.compose.service=otel-collector | head -n1)
    if [ -n "$coletor" ] && ! docker inspect -f '{{json .NetworkSettings.Networks}}' "$coletor" | grep -q "\"$rede\""; then
      info "ligando otel-collector à rede $rede"
      docker network connect --alias otel-collector "$rede" "$coletor"
    fi
  done
  docker network inspect smart_core_v2_evolution_net >/dev/null 2>&1 \
    || erro "rede smart_core_v2_evolution_net ausente — suba a stack evolution (deploy-infra.yml)"
}
