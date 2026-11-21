#!/usr/bin/env bash
# =============================================================================
# Smoke test de um ambiente, a partir de um bundle.
#
#   smoke.sh <dev|prod> <release-id>
#
# Unifica os smoke tests que viviam duplicados no deploy-dev.yml e no
# deploy-prod.yml, e passa a cobrir TODOS os serviços do compose (antes
# mcp_server, web e web-tenant ficavam de fora — L7 do go-live).
#
# `compose up -d` devolve sucesso assim que os containers são CRIADOS. O gate
# aqui é "o serviço responde": sonda saudável, sem laço de restart, e o bundle
# web servindo a index. Containers sem healthcheck são julgados pelo estado.
# =============================================================================
set -uo pipefail
# shellcheck source=infra/deploy/lib.sh
source "$(dirname "$0")/lib.sh"

[ $# -eq 2 ] || erro "uso: smoke.sh <dev|prod> <release-id>"
valida_ambiente "$1"; caminhos "$1"
BUNDLE="$DIR_RELEASES/$2"
[ -d "$BUNDLE" ] || erro "bundle inexistente: $BUNDLE"

# Janela para um crash-loop se manifestar (restart: unless-stopped é imediato).
sleep "${SMOKE_ESPERA_INICIAL:-25}"

falhas=""
tpl='{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}'
for svc in $(dc "$BUNDLE" config --services); do
  case " $SERVICOS_ONE_SHOT " in *" $svc "*) continue ;; esac
  cid=$(dc "$BUNDLE" ps -q "$svc" 2>/dev/null || true)
  if [ -z "$cid" ]; then
    echo "::error::$svc: container inexistente"
    falhas="$falhas $svc"; continue
  fi
  status=$(docker inspect -f '{{.State.Status}}' "$cid")
  restarts=$(docker inspect -f '{{.RestartCount}}' "$cid")
  health=$(docker inspect -f "$tpl" "$cid")
  # `starting` não é veredito: espera a sonda concluir. 240s cobre o
  # start_period do pg_backup (primeiro dump) e o de data_postgres em prod.
  espera=0
  while [ "$health" = "starting" ] && [ "$espera" -lt 240 ]; do
    sleep 5; espera=$((espera + 5))
    health=$(docker inspect -f "$tpl" "$cid")
  done
  if [ "$status" != "running" ] || [ "$restarts" -gt 2 ] \
     || [ "$health" = "unhealthy" ] || [ "$health" = "starting" ]; then
    echo "::error::$svc: status=$status restarts=$restarts health=$health"
    # 50 linhas, como antes: o log pode trazer payload de cliente.
    docker logs --tail 50 "$cid" 2>&1 || true
    falhas="$falhas $svc"
  else
    echo "ok  $svc (status=$status restarts=$restarts health=$health)"
  fi
done

# Bundles web: o container de pé com /srv vazio devolveria 404.
ip=$(le_chave "$BUNDLE/.env" HOST_BRIDGE_IP); ip="${ip:-172.17.0.1}"
for var in WEB_HOST_PORT WEB_TENANT_HOST_PORT; do
  porta=$(le_chave "$BUNDLE/$AMB.vars" "$var")
  codigo=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$ip:$porta/" || echo 000)
  if [ "$codigo" = "200" ]; then
    echo "ok  http://$ip:$porta/ ($var) HTTP 200"
  else
    echo "::error::http://$ip:$porta/ ($var) respondeu HTTP $codigo"
    falhas="$falhas $var"
  fi
done

# Config de tenant: publicada pelo data_postgres e lida pelo ia_engine em
# instâncias Redis diferentes se o wiring estiver errado (cache x bus). Ela fica
# íntegra e invisível — só a primeira mensagem de WhatsApp revelaria. Nenhum
# teste unitário pega wiring.
pg_user=$(le_chave "$BUNDLE/.env" POSTGRES_USER)
pg_db=$(le_chave "$BUNDLE/.env" POSTGRES_DB)
ativos=$(dc "$BUNDLE" exec -T postgres psql -U "$pg_user" -d "$pg_db" -t -A \
  -c "SELECT count(*) FROM tenants_tenant WHERE active = TRUE" 2>/dev/null | tr -d '[:space:]')
if [ -z "${ativos:-}" ] || [ "$ativos" = "0" ]; then
  echo "ok  sem tenants ativos — nada a conferir no Redis"
else
  # REDISCLI_AUTH herdado do ambiente (`-e NOME` sem valor): a senha não
  # aparece na linha de comando do host nem na do container.
  cid_redis=$(dc "$BUNDLE" ps -q redis)
  publicadas=$(REDISCLI_AUTH="$(le_chave "$BUNDLE/.env" REDIS_PASSWORD)" docker exec -e REDISCLI_AUTH "$cid_redis" \
    redis-cli --scan --pattern 'tenant:config:*' 2>/dev/null | grep -c 'tenant:config:' || true)
  if [ "${publicadas:-0}" = "0" ]; then
    echo "::error::$ativos tenant(s) ativo(s) e nenhuma config em tenant:config:* no Redis de cache"
    falhas="$falhas redis-config"
  else
    echo "ok  config no Redis ($publicadas de $ativos tenant(s) ativo(s))"
  fi
fi

if [ -n "$falhas" ]; then
  echo "::error::smoke test reprovado:$falhas"
  exit 1
fi
echo "smoke test aprovado ($AMB, $2)"
