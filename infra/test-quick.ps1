# ============================================
# Testes Rapidos (desenvolvimento diario) - Smart Core Assistant v2
# ============================================
# Detecta quais pacotes server/ mudaram e testa APENAS esses.
# Nao exige banco nem tunel SSH (so unit + bins, sem integration tests).
# Use durante o desenvolvimento para feedback rapido (<1 min apos cache quente).
#
# Como funciona:
#   - Compara os arquivos alterados com a base indicada (-Vs)
#   - Mapeia cada arquivo ao seu pacote Cargo
#   - Roda clippy + cargo test --lib --bins apenas nesses pacotes
#   - SQLX_OFFLINE=true: compila offline (sem banco), usa cache .sqlx/
#
# ATENCAO: nao substitui test-local.ps1 (pre-push).
#   - Mudancas em crates compartilhados (infrastructure_*) podem quebrar apps
#     que dependem deles sem que este script detecte. Use test-local.ps1
#     antes do push para garantir cobertura completa.
#
# Uso:
#   .\infra\test-quick.ps1                   # mudancas nao commitadas (staged + unstaged)
#   .\infra\test-quick.ps1 -Vs HEAD~1        # ultimo commit
#   .\infra\test-quick.ps1 -Vs origin/dev    # tudo no branch vs remote dev
#   .\infra\test-quick.ps1 -Pkg data_postgres,data_whatsapp  # pacotes explicitos
#   .\infra\test-quick.ps1 -Jobs 2           # limita threads de compilacao (poupa RAM/CPU)
# ============================================

param(
    # Base do git diff. Vazio = mudancas nao commitadas (staged + unstaged).
    # Exemplos: "HEAD~1", "origin/dev", "main"
    [string]$Vs = "",

    # Lista explicita de pacotes (substitui auto-deteccao)
    [string[]]$Pkg = @(),

    # Numero de jobs de compilacao paralelos (padrao: todos os cores do cargo).
    # Reduza para 2-4 se a maquina travar durante a compilacao.
    [int]$Jobs = 0
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$serverDir = Join-Path $repoRoot "server"

function Write-Etapa([string]$msg) {
    Write-Host ""
    Write-Host "== $msg ==" -ForegroundColor Cyan
}

# ----------------------------------------
# Detecta pacotes server/ alterados via git diff
# ----------------------------------------
function Detectar-Pacotes([string]$vs) {
    if ($vs) {
        $arquivos = git -C $repoRoot diff --name-only $vs 2>$null
    } else {
        # Mudancas nao commitadas: staged + unstaged
        $unstaged = git -C $repoRoot diff --name-only 2>$null
        $staged   = git -C $repoRoot diff --name-only --cached 2>$null
        $arquivos  = (@($unstaged) + @($staged)) | Where-Object { $_ } | Sort-Object -Unique
    }

    if (-not $arquivos) { return @() }

    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($f in $arquivos) {
        if      ($f -match '^server/crates/([^/]+)/') { $set.Add($matches[1]) | Out-Null }
        elseif  ($f -match '^server/apps/([^/]+)/')   { $set.Add($matches[1]) | Out-Null }
    }
    return @($set)
}

# ----------------------------------------
# Resolve lista de pacotes
# ----------------------------------------
if ($Pkg.Count -gt 0) {
    $pacotes = $Pkg
    Write-Host "Pacotes (explicitos): $($pacotes -join ', ')" -ForegroundColor Cyan
} else {
    $pacotes = Detectar-Pacotes -vs $Vs
    if ($pacotes.Count -eq 0) {
        $alvo = if ($Vs) { "vs '$Vs'" } else { "(nao commitadas)" }
        Write-Host "Nenhum pacote server/ alterado $alvo." -ForegroundColor Green
        exit 0
    }
    $alvo = if ($Vs) { "vs '$Vs'" } else { "(nao commitadas)" }
    Write-Host "Pacotes alterados $alvo`: $($pacotes -join ', ')" -ForegroundColor Cyan
}

# ----------------------------------------
# Ambiente de compilacao
# ----------------------------------------
$env:SQLX_OFFLINE = "true"   # compila offline; nunca conecta ao banco durante build
if ($Jobs -gt 0) {
    $env:CARGO_BUILD_JOBS = "$Jobs"
    Write-Host "Jobs de compilacao: $Jobs" -ForegroundColor DarkGray
}

$falhas = @()

Push-Location $serverDir
try {
    # --------------------------------------------------
    # fmt: rapido, sem compilacao, verifica workspace todo
    # --------------------------------------------------
    Write-Etapa "cargo fmt --check"
    cargo fmt --all -- --check
    if ($LASTEXITCODE -ne 0) { $falhas += "fmt" } else { Write-Host "ok" -ForegroundColor Green }

    # --------------------------------------------------
    # clippy + testes apenas nos pacotes alterados
    # --------------------------------------------------
    foreach ($pkg in $pacotes) {
        Write-Etapa "clippy: $pkg"
        cargo clippy -p $pkg --all-targets --all-features -- -D warnings
        if ($LASTEXITCODE -ne 0) { $falhas += "clippy:$pkg" } else { Write-Host "ok" -ForegroundColor Green }

        Write-Etapa "test --lib --bins: $pkg"
        # --test-threads=1 evita race entre testes que usam variaveis de ambiente globais
        cargo test -p $pkg --lib --bins -- --test-threads=1
        if ($LASTEXITCODE -ne 0) { $falhas += "test:$pkg" } else { Write-Host "ok" -ForegroundColor Green }
    }
} finally {
    Pop-Location
}

# ----------------------------------------
# Resumo
# ----------------------------------------
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
if ($falhas.Count -eq 0) {
    Write-Host "  TUDO VERDE" -ForegroundColor Green
    if ($pacotes.Count -gt 0) {
        Write-Host "  Testados: $($pacotes -join ', ')" -ForegroundColor DarkGreen
    }
    Write-Host "  (para suite completa com banco: .\infra\test-local.ps1)" -ForegroundColor DarkGray
    Write-Host "============================================" -ForegroundColor Cyan
    exit 0
} else {
    Write-Host "  FALHAS: $($falhas -join ', ')" -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Cyan
    exit 1
}
