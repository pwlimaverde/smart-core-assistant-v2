#!/bin/bash
# ============================================================
# N8.3 — roda a analise de enforce de quota (read-only) e salva CSV.
# Smart Core Assistant v2
# ============================================================
# Pre-requisitos:
#   - psql no PATH
#   - tunel aberto para o Postgres alvo (ver infra/tunnel.sh)
#   - $DATABASE_ADMIN_URL apontando para o role BOOTSTRAP
#     (smartcore_app, NAO smartcore_app_rt — ver README.md desta pasta)
#
# Uso:
#   ./infra/tunnel.sh prod                       # terminal 1, deixar aberto
#   export DATABASE_ADMIN_URL="postgresql://smartcore_app:SENHA@localhost:5434/smartcore_v2"
#   ./infra/migracao-v1/analise-enforce/run_analysis.sh
#
# Este script NUNCA escreve no banco e NUNCA altera nenhuma flag/config — so
# executa os SELECTs de 01_estado_atual_quotas.sql e
# 02_janela_log_only_audit.sql e salva a saida em infra/migracao-v1/analise-enforce/out/.
# ============================================================

set -e

if [ -z "$DATABASE_ADMIN_URL" ]; then
    echo "Erro: DATABASE_ADMIN_URL nao definido (role bootstrap smartcore_app)." >&2
    exit 1
fi

if ! command -v psql >/dev/null 2>&1; then
    echo "Erro: psql nao encontrado no PATH." >&2
    exit 1
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$HERE/out"
mkdir -p "$OUT_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"

for script in 01_estado_atual_quotas.sql 02_janela_log_only_audit.sql; do
    out_file="$OUT_DIR/${script%.sql}-$STAMP.csv"
    echo "Rodando $script -> $out_file"
    # --csv concatena os blocos de resultado (o arquivo tem >1 SELECT); revisar
    # visualmente se os blocos vierem colados sem cabecalho repetido.
    psql "$DATABASE_ADMIN_URL" --csv -f "$HERE/$script" -o "$out_file"
    echo "  OK"
done

echo ""
echo "Analise concluida. Resultados em: $OUT_DIR"
echo "Nenhuma escrita foi feita no banco; nenhuma flag foi alterada."
