#!/usr/bin/env bash
# =============================================================================
# Monta o bundle de uma release a partir do checkout do repositório.
#
#   bundle.sh <dev|prod> <vX.Y.Z[-beta.N]> <images.env>
#
# Resultado: /opt/smartcore/<env>/releases/<id>/ com compose base + overlay,
# <env>.vars, backup/, init-scripts/, images.env, MIGRATIONS, RELEASE e o link
# .env -> ../../env/<env>.env. O compose passa a montar `backup/` e
# `init-scripts/` DAQUI — nunca da workspace do runner, que o próximo checkout
# (de outro ambiente) troca.
#
# Um bundle que é o `current` não é sobrescrito: versão publicada é imutável.
# =============================================================================
set -euo pipefail
# shellcheck source=infra/deploy/lib.sh
source "$(dirname "$0")/lib.sh"

[ $# -eq 3 ] || erro "uso: bundle.sh <dev|prod> <release-id> <images.env>"
valida_ambiente "$1"; valida_release_id "$2"
caminhos "$1"
ID="$2"; IMAGENS="$3"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
DESTINO="$DIR_RELEASES/$ID"

[ -f "$IMAGENS" ] || erro "images.env não encontrado: $IMAGENS"
for par in "${IMAGENS_APP[@]}"; do
  var="${par#*=}"
  grep -qE "^${var}=[A-Za-z0-9._-]+$" "$IMAGENS" || erro "images.env sem $var válido"
done
if grep -qE '=(latest|dev)$' "$IMAGENS" && [ "$AMB" = prod ]; then
  erro "prod não aceita tag móvel (latest/dev) no images.env"
fi

if [ "$(release_de current)" = "$ID" ]; then
  erro "$ID é o bundle em uso (current) — versão publicada não se sobrescreve"
fi

mkdir -p "$DIR_RELEASES"
TMP="$(mktemp -d "$DIR_RELEASES/.montando-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

cp "$REPO/docker/stack/docker-compose.base.yml" "$TMP/"
cp "$REPO/docker/stack/$AMB.override.yml" "$TMP/"
cp "$REPO/docker/stack/$AMB.vars" "$TMP/"
cp -r "$REPO/docker/backup" "$REPO/docker/init-scripts" "$TMP/"
cp "$IMAGENS" "$TMP/images.env"
# Lista de migrações desta versão: o rollback compara com a do bundle em uso
# para recusar voltar para uma versão que não conhece o schema atual.
ls -1 "$REPO/server/crates/infrastructure_postgres/migrations" > "$TMP/MIGRATIONS"
{
  echo "id=$ID"
  echo "ambiente=$AMB"
  echo "sha=${GITHUB_SHA:-$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo desconhecido)}"
  echo "run=${GITHUB_RUN_ID:-manual}"
  echo "montado_em=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$TMP/RELEASE"
ln -s "../../env/$AMB.env" "$TMP/.env"
chmod -R u+rwX,go+rX,go-w "$TMP"
chmod 755 "$TMP"

rm -rf "$DESTINO"
mv "$TMP" "$DESTINO"
trap - EXIT
info "bundle pronto: $DESTINO"
