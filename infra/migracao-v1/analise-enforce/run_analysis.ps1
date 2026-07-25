# ============================================================
# N8.3 — roda a análise de enforce de quota (read-only) e salva CSV.
# Smart Core Assistant v2
# ============================================================
# Pré-requisitos:
#   - psql no PATH
#   - túnel aberto para o Postgres alvo (ver infra/tunnel.ps1)
#   - $env:DATABASE_ADMIN_URL apontando para o role BOOTSTRAP
#     (smartcore_app, NAO smartcore_app_rt — ver README.md desta pasta)
#
# Uso:
#   .\infra\tunnel.ps1 -Env prod                 # terminal 1, deixar aberto
#   $env:DATABASE_ADMIN_URL = "postgresql://smartcore_app:SENHA@localhost:5434/smartcore_v2"
#   .\infra\migracao-v1\analise-enforce\run_analysis.ps1
#
# Este script NUNCA escreve no banco e NUNCA altera nenhuma flag/config —
# só executa os SELECTs de 01_estado_atual_quotas.sql e
# 02_janela_log_only_audit.sql e salva a saida em infra/migracao-v1/analise-enforce/out/.
# ============================================================

[CmdletBinding()]
param(
    [string]$DatabaseUrl = $env:DATABASE_ADMIN_URL
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if ([string]::IsNullOrWhiteSpace($DatabaseUrl)) {
    throw "DATABASE_ADMIN_URL nao definido. Exporte a variavel ou passe -DatabaseUrl (role bootstrap smartcore_app)."
}

$psql = Get-Command psql -ErrorAction SilentlyContinue
if (-not $psql) {
    throw "psql nao encontrado no PATH. Instale o cliente Postgres (ex.: winget install PostgreSQL.PostgreSQL) ou rode os .sql manualmente."
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$outDir = Join-Path $here "out"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"

$scripts = @(
    "01_estado_atual_quotas.sql",
    "02_janela_log_only_audit.sql"
)

foreach ($script in $scripts) {
    $scriptPath = Join-Path $here $script
    $outFile = Join-Path $outDir ("{0}-{1}.csv" -f ($script -replace "\.sql$", ""), $stamp)
    Write-Host "Rodando $script -> $outFile" -ForegroundColor Cyan
    # --csv concatena os blocos de resultado (o arquivo tem >1 SELECT); revisar
    # visualmente se os blocos vierem colados sem cabecalho repetido.
    & psql $DatabaseUrl --csv -f $scriptPath -o $outFile
    Write-Host "  OK" -ForegroundColor Green
}

Write-Host ""
Write-Host "Analise concluida. Resultados em: $outDir" -ForegroundColor Yellow
Write-Host "Nenhuma escrita foi feita no banco; nenhuma flag foi alterada." -ForegroundColor Yellow
