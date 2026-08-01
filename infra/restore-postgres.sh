#!/usr/bin/env bash
# =============================================================================
# Restauração do banco a partir de um dump do serviço pg_backup
# =============================================================================
# Rodar NO SERVIDOR. Uso:
#
#   ./infra/restore-postgres.sh dev                      # lista os backups
#   ./infra/restore-postgres.sh dev smartcore-2026....dump --confirmo
#
# Sem `--confirmo` o script só mostra o que faria. A restauração é destrutiva:
# ela recria o schema public, então tudo que existe no banco alvo é perdido.
#
# Um backup nunca testado não conta. Restaure em dev de tempos em tempos — é o
# único jeito de descobrir que o dump presta ANTES de precisar dele.
# =============================================================================
set -euo pipefail

AMBIENTE="${1:-}"
ARQUIVO="${2:-}"
CONFIRMA="${3:-}"

if [ -z "$AMBIENTE" ]; then
    echo "uso: $0 <dev|prod> [arquivo.dump] [--confirmo]" >&2
    exit 1
fi

PROJETO="smart-core-v2-$AMBIENTE"
COMPOSE_DIR="docker/$AMBIENTE"

# O nome do container do backup e do postgres vem do projeto do compose.
container_backup="$(docker compose -p "$PROJETO" -f "$COMPOSE_DIR/compose.yml" ps -q pg_backup 2>/dev/null || true)"
container_pg="$(docker compose -p "$PROJETO" -f "$COMPOSE_DIR/compose.yml" ps -q postgres 2>/dev/null || true)"

if [ -z "$container_backup" ] || [ -z "$container_pg" ]; then
    echo "ERRO: não encontrei os containers pg_backup/postgres do projeto $PROJETO." >&2
    echo "      A stack está no ar? (docker compose -p $PROJETO ps)" >&2
    exit 1
fi

if [ -z "$ARQUIVO" ]; then
    echo "Backups disponíveis em $PROJETO:"
    docker exec "$container_backup" sh -c 'ls -lh /backups/*.dump 2>/dev/null || echo "  (nenhum ainda)"'
    echo
    echo "Para restaurar:  $0 $AMBIENTE <arquivo.dump> --confirmo"
    exit 0
fi

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

O que a execução real faria no ambiente $AMBIENTE:
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

echo "1/4 Parando os serviços que escrevem no banco..."
# shellcheck disable=SC2086
docker compose -p "$PROJETO" -f "$COMPOSE_DIR/compose.yml" stop $SERVICOS_ESCRITA

echo "2/4 Recriando o schema..."
docker exec "$container_pg" psql -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-smartcore}" \
    -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;'

echo "3/4 Restaurando $ARQUIVO..."
# O dump sai do container de backup e entra no do postgres por pipe: evita
# precisar de um volume compartilhado entre os dois só para isso.
docker exec "$container_backup" cat "/backups/$ARQUIVO" \
    | docker exec -i "$container_pg" pg_restore \
        -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-smartcore}" --no-owner

echo "4/4 Subindo os serviços..."
# shellcheck disable=SC2086
docker compose -p "$PROJETO" -f "$COMPOSE_DIR/compose.yml" start $SERVICOS_ESCRITA

echo
echo "Restauração concluída. Confira as migrations e o estado da aplicação antes"
echo "de liberar o acesso — o dump pode ser de um schema anterior ao código no ar."
