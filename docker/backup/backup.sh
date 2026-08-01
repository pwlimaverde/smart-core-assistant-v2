#!/bin/sh
# =============================================================================
# Backup lógico periódico do PostgreSQL
# =============================================================================
# Roda como serviço de longa duração dentro do compose, e não como cron do host,
# por um motivo prático: assim o backup é instalado pelo deploy junto com a
# stack. Cron no host é um passo manual — e passo manual é o passo que ninguém
# executa no servidor novo.
#
# O dump usa o formato custom (-Fc): já vem comprimido, permite restaurar uma
# tabela isolada e, principalmente, permite VERIFICAR o arquivo com
# `pg_restore --list`. Um backup que nunca foi lido não é backup, é esperança.
#
# Saída em JSON por linha porque o promtail recolhe o stdout do container e
# manda para o Loki — assim `backup.falhou` é pesquisável ao lado do resto.
# =============================================================================
set -eu

DESTINO="${BACKUP_DIR:-/backups}"
INTERVALO="${BACKUP_INTERVALO_SEGUNDOS:-86400}"
RETENCAO_DIAS="${BACKUP_RETENCAO_DIAS:-14}"
RETENCAO_MAX="${BACKUP_RETENCAO_MAX_ARQUIVOS:-60}"
MARCA_SUCESSO="$DESTINO/.ultimo_sucesso"

log() {
    nivel="$1"
    evento="$2"
    mensagem="$3"
    extra="${4:-}"
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if [ -n "$extra" ]; then
        printf '{"ts":"%s","level":"%s","service":"pg_backup","event":"%s","message":"%s",%s}\n' \
            "$ts" "$nivel" "$evento" "$mensagem" "$extra"
    else
        printf '{"ts":"%s","level":"%s","service":"pg_backup","event":"%s","message":"%s"}\n' \
            "$ts" "$nivel" "$evento" "$mensagem"
    fi
}

# Remove os dumps que passaram da janela de retenção. Duas regras somadas: por
# idade (a janela que interessa ao negócio) e por quantidade (o teto que protege
# o disco quando o intervalo é curto ou houve muitos deploys no mesmo dia).
aplicar_retencao() {
    find "$DESTINO" -name 'smartcore-*.dump' -type f -mtime "+$RETENCAO_DIAS" -delete 2>/dev/null || true

    total="$(find "$DESTINO" -name 'smartcore-*.dump' -type f | wc -l)"
    if [ "$total" -gt "$RETENCAO_MAX" ]; then
        excedente="$((total - RETENCAO_MAX))"
        # `ls -t` ordena do mais novo para o mais velho; o tail pega a cauda antiga.
        find "$DESTINO" -name 'smartcore-*.dump' -type f -printf '%T@ %p\n' 2>/dev/null \
            | sort -n | head -n "$excedente" | cut -d' ' -f2- \
            | while read -r velho; do rm -f "$velho"; done
        log INFO backup.retencao "Retencao por quantidade aplicada" "\"removidos\":$excedente"
    fi
}

executar_backup() {
    carimbo="$(date -u +%Y%m%d-%H%M%S)"
    arquivo="$DESTINO/smartcore-$carimbo.dump"
    parcial="$arquivo.parcial"
    inicio="$(date +%s)"

    # Grava em .parcial e só renomeia no fim: um dump interrompido no meio (host
    # reiniciado, disco cheio) nunca aparece com nome de backup bom. Sem isso, o
    # arquivo truncado seria escolhido numa restauração de emergência.
    if ! pg_dump -Fc -f "$parcial" 2>/tmp/erro_backup; then
        erro="$(tr -d '\n"' </tmp/erro_backup | head -c 300)"
        rm -f "$parcial"
        log ERROR backup.falhou "Falha ao gerar o dump" "\"erro\":\"$erro\""
        return 1
    fi

    # Verificação de integridade: lê o índice do próprio arquivo. Barato, e é a
    # diferença entre ter um backup e achar que tem.
    if ! pg_restore --list "$parcial" >/dev/null 2>/tmp/erro_verifica; then
        erro="$(tr -d '\n"' </tmp/erro_verifica | head -c 300)"
        rm -f "$parcial"
        log ERROR backup.corrompido "Dump gerado nao passou na verificacao" "\"erro\":\"$erro\""
        return 1
    fi

    mv "$parcial" "$arquivo"
    tamanho="$(stat -c %s "$arquivo" 2>/dev/null || echo 0)"
    duracao="$(($(date +%s) - inicio))"
    date -u +%s >"$MARCA_SUCESSO"

    log INFO backup.concluido "Backup gerado e verificado" \
        "\"arquivo\":\"$(basename "$arquivo")\",\"bytes\":$tamanho,\"duracao_s\":$duracao"
    return 0
}

mkdir -p "$DESTINO"
log INFO backup.iniciado "Servico de backup no ar" \
    "\"intervalo_s\":$INTERVALO,\"retencao_dias\":$RETENCAO_DIAS"

# Um backup logo na subida é intencional: o serviço sobe junto com o deploy,
# então isso deixa um ponto de restauração imediatamente antes/depois de cada
# release — que é exatamente quando algo costuma quebrar.
while true; do
    if executar_backup; then
        aplicar_retencao
    fi
    sleep "$INTERVALO"
done
