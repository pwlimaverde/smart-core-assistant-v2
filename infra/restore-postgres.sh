#!/usr/bin/env bash
# =============================================================================
# Restauração do banco a partir de um dump do serviço pg_backup
# =============================================================================
# Rodar NO SERVIDOR, como root, a partir do checkout de operação. Uso:
#
#   ./infra/restore-postgres.sh dev                      # lista os backups
#   ./infra/restore-postgres.sh dev smartcore-2026....dump --confirmo
#
# Sem `--confirmo` o script só mostra o que faria. A restauração é destrutiva:
# ela recria o schema public, então tudo que existe no banco alvo é perdido.
#
# A stack é a do bundle em uso (`/opt/smartcore/<env>/releases/current`), com o
# mesmo `docker compose` do deploy (`infra/deploy/lib.sh`). Usuário e banco vêm
# do env do ambiente (`/opt/smartcore/<env>/env/<env>.env`), nunca de valor fixo.
#
# Um backup nunca testado não conta. Restaure em dev de tempos em tempos — é o
# único jeito de descobrir que o dump presta ANTES de precisar dele.
# =============================================================================
set -euo pipefail
# shellcheck source=infra/deploy/lib.sh
source "$(dirname "$0")/deploy/lib.sh"

AMBIENTE="${1:-}"
ARQUIVO="${2:-}"
CONFIRMA="${3:-}"

if [ -z "$AMBIENTE" ]; then
    echo "uso: $0 <dev|prod> [arquivo.dump] [--confirmo]" >&2
    exit 1
fi
valida_ambiente "$AMBIENTE"
caminhos "$AMBIENTE"

# O bundle é resolvido uma vez: se um deploy trocar o `current` no meio da
# restauração, o script continua falando com a mesma versão.
[ -L "$DIR_RELEASES/current" ] || erro "$DIR_RELEASES/current não existe — o ambiente $AMB foi implantado por bundle?"
BUNDLE="$(readlink -f "$DIR_RELEASES/current")"
[ -d "$BUNDLE" ] || erro "bundle em uso inexistente: $BUNDLE"
[ -f "$ARQ_ENV" ] || erro "$ARQ_ENV não existe"

# `|| true`: com pipefail, chave ausente faria o script sair calado aqui; o
# teste logo abaixo dá a mensagem certa.
PG_USER="$(le_chave "$ARQ_ENV" POSTGRES_USER || true)"
PG_DB="$(le_chave "$ARQ_ENV" POSTGRES_DB || true)"
[ -n "$PG_USER" ] && [ -n "$PG_DB" ] || erro "POSTGRES_USER/POSTGRES_DB ausentes em $ARQ_ENV"

# O nome do container do backup e do postgres vem do projeto do compose.
container_backup="$(dc "$BUNDLE" ps -q pg_backup 2>/dev/null || true)"
container_pg="$(dc "$BUNDLE" ps -q postgres 2>/dev/null || true)"

if [ -z "$container_backup" ] || [ -z "$container_pg" ]; then
    echo "ERRO: não encontrei os containers pg_backup/postgres do projeto $PROJETO." >&2
    echo "      A stack está no ar? (docker compose -p $PROJETO ps)" >&2
    exit 1
fi

if [ -z "$ARQUIVO" ]; then
    echo "Backups disponíveis em $PROJETO (bundle $(basename "$BUNDLE")):"
    docker exec "$container_backup" sh -c 'ls -lh /backups/*.dump 2>/dev/null || echo "  (nenhum ainda)"'
    echo
    echo "Dumps de pré-deploy (no host): $DIR_BACKUP_DEPLOY"
    echo
    echo "Para restaurar:  $0 $AMB <arquivo.dump> --confirmo"
    exit 0
fi

# O nome do arquivo vai para dentro de um caminho: nada de barra nem `..`.
[[ "$ARQUIVO" =~ ^[A-Za-z0-9._-]+\.dump$ ]] && [[ "$ARQUIVO" != *..* ]] \
    || erro "nome de dump inválido: '$ARQUIVO' (só o nome do arquivo, terminando em .dump)"

if ! docker exec "$container_backup" test -f "/backups/$ARQUIVO"; then
    echo "ERRO: /backups/$ARQUIVO não existe no container de backup." >&2
    exit 1
fi

echo "Verificando a integridade do dump antes de qualquer coisa..."
docker exec "$container_backup" pg_restore --list "/backups/$ARQUIVO" >/dev/null
echo "  ok — o arquivo é legível."

if [ "$CONFIRMA" != "--confirmo" ]; then
    cat <<AVISO

ENSAIO (nada foi alterado).

O que a execução real faria no ambiente $AMB (banco $PG_DB, bundle $(basename "$BUNDLE")):
  1. Derrubar os serviços que escrevem no banco (data_postgres, worker,
     control_plane, runtime_api, data_whatsapp, webhook_ingress);
  2. DROP SCHEMA public CASCADE  <- apaga tudo que está lá hoje;
  3. Restaurar $ARQUIVO;
  4. Subir os serviços de volta.

Para executar de verdade, repita o comando com --confirmo no fim.
AVISO
    exit 0
fi

SERVICOS_ESCRITA="data_postgres worker control_plane runtime_api data_whatsapp webhook_ingress"

# Se algo falhar depois de parar os serviços, eles ficam parados de propósito:
# subir o data_postgres sobre um schema pela metade rodaria as migrações num
# banco inconsistente. O aviso diz como voltar.
falha_apos_parar() {
    echo >&2
    echo "ERRO: a restauração falhou com os serviços de escrita PARADOS." >&2
    echo "      Corrija a causa e rode de novo, ou restaure outro dump. Para só" >&2
    echo "      religar sem restaurar (o banco pode estar vazio ou parcial):" >&2
    echo "      docker compose -p $PROJETO --project-directory $BUNDLE \\" >&2
    echo "        -f $BUNDLE/docker-compose.base.yml -f $BUNDLE/$AMB.override.yml \\" >&2
    echo "        --env-file $BUNDLE/.env --env-file $BUNDLE/$AMB.vars \\" >&2
    echo "        --env-file $BUNDLE/images.env start $SERVICOS_ESCRITA" >&2
}

echo "1/4 Parando os serviços que escrevem no banco..."
# shellcheck disable=SC2086
dc "$BUNDLE" stop $SERVICOS_ESCRITA
trap falha_apos_parar ERR

echo "2/4 Recriando o schema..."
docker exec "$container_pg" psql -v ON_ERROR_STOP=1 -U "$PG_USER" -d "$PG_DB" \
    -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;'

echo "3/4 Restaurando $ARQUIVO..."
# O dump sai do container de backup e entra no do postgres por pipe: evita
# precisar de um volume compartilhado entre os dois só para isso.
docker exec "$container_backup" cat "/backups/$ARQUIVO" \
    | docker exec -i "$container_pg" pg_restore \
        -U "$PG_USER" -d "$PG_DB" --no-owner

trap - ERR
echo "4/4 Subindo os serviços..."
# shellcheck disable=SC2086
dc "$BUNDLE" start $SERVICOS_ESCRITA

echo
echo "Restauração concluída. Confira as migrations e o estado da aplicação antes"
echo "de liberar o acesso — o dump pode ser de um schema anterior ao código no ar."
