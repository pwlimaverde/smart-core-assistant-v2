# ============================================
# Testes Flutter Locais (pre-push) - Smart Core Assistant v2
# ============================================
# Roda flutter analyze + flutter test em todos os pacotes do workspace
# Dart pub workspace (clients/pubspec.yaml), iterando pacote a pacote
# para dar visibilidade por modulo (melos nao esta instalado globalmente).
#
# Estrutura do workspace:
#   clients/packages/   -- pacotes base sem dependencia de flutter (domain, DI, etc.)
#   clients/modulos/    -- modulos de feature com widgets e BLoCs
#   clients/apps/       -- aplicativos finais (smart-core-admin, ...)
#
# Uso (a partir da raiz do repo ou da pasta infra/):
#   .\infra\test-flutter.ps1              # analyze + todos os testes
#   .\infra\test-flutter.ps1 -SkipAnalyze # so os testes (mais rapido)
# ============================================

param(
    [switch]$SkipAnalyze
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

$repoRoot  = Split-Path -Parent $PSScriptRoot
$clientDir = Join-Path $repoRoot "clients"

# Ordem espelha o workspace do pubspec.yaml raiz
$pacotes = @(
    "packages\app_config",
    "packages\domain_models",
    "packages\get_it_module",
    "packages\api_client",
    "packages\local_engine_ffi",
    "modulos\presentation_module",
    "modulos\design_system_module",
    "modulos\navigation_module",
    "modulos\core_module",
    "modulos\dependencies_module",
    "modulos\initial_loading_module",
    "modulos\login_module",
    "modulos\admin_module",
    "modulos\operacional_module",
    "modulos\tenant_module",
    "apps\smart-core-admin",
    "apps\smart-core-tenant"
)

function Write-Etapa([string]$msg) {
    Write-Host ""
    Write-Host "== $msg ==" -ForegroundColor Cyan
}

function Write-Ok   { Write-Host "ok" -ForegroundColor Green }
function Write-Fail([string]$msg) { Write-Host "FALHOU: $msg" -ForegroundColor Red }

$falhas      = @()
$totalTestes = 0

# --------------------------------------------
# 0. Codigo-fonte .dart ignorado pelo git
#    Pega o caso "passa local, quebra no CI": um .dart de lib/ que casa o
#    .gitignore existe na sua maquina (o analyze/test local passa) mas nunca
#    foi commitado — o CI nao o tem e a compilacao quebra. Foi exatamente o que
#    aconteceu com a pasta data/ da Clean Architecture (regra data/ generica).
# --------------------------------------------
Write-Etapa "Codigo .dart ignorado pelo git (nao vai pro CI)"
Push-Location $clientDir
try {
    $ignorados = git ls-files --others --ignored --exclude-standard . |
        Where-Object { $_ -match 'lib/.*\.dart$' }
    if ($ignorados) {
        $falhas += "git-ignored"
        Write-Fail "ha .dart de codigo ignorado pelo git:"
        $ignorados | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
    } else {
        Write-Ok
    }
} finally {
    Pop-Location
}

# --------------------------------------------
# 1. flutter analyze POR PACOTE (espelha `melos exec -- flutter analyze .` do CI)
#    NAO usar `flutter analyze` unico no raiz: ele NAO desce em subpacotes
#    aninhados (ex.: local_engine_ffi/cargokit/, tool vendorizada do
#    flutter_rust_bridge) e por isso deixou passar 62 issues que quebraram o CI.
#    O melos roda `flutter analyze .` DENTRO de cada pacote, o que desce nos
#    subdiretorios — replicamos isso aqui, iterando os mesmos pacotes.
#    SEM --no-fatal-infos: o CI trata QUALQUER issue (inclusive info) como falha.
# --------------------------------------------
if (-not $SkipAnalyze) {
    Write-Etapa "flutter analyze (por pacote, espelha o CI)"
    foreach ($rel in $pacotes) {
        $pkgPath = Join-Path $clientDir $rel
        $pkgName = Split-Path -Leaf $rel
        Write-Host "  $pkgName" -NoNewline
        Push-Location $pkgPath
        try {
            $out = flutter analyze . 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                Write-Host " -- FALHOU" -ForegroundColor Red
                $falhas += "analyze:$pkgName"
                $clean = [regex]::Replace($out, '\x1b\[[0-9;]*m', '')
                ($clean -split "`n" | Where-Object { $_ -match ' - |•' } | Select-Object -First 12) |
                    ForEach-Object { Write-Host "      $($_.Trim())" -ForegroundColor Yellow }
            } else {
                Write-Host " -- ok" -ForegroundColor Green
            }
        } finally {
            Pop-Location
        }
    }
}

# --------------------------------------------
# 2. flutter test por pacote
# --------------------------------------------
Write-Etapa "flutter test ($($pacotes.Count) pacotes)"

foreach ($rel in $pacotes) {
    $pkgPath = Join-Path $clientDir $rel
    $pkgName = Split-Path -Leaf $rel

    if (-not (Test-Path (Join-Path $pkgPath "test"))) {
        Write-Host "  [skip]  $pkgName (sem diretorio test/)" -ForegroundColor DarkGray
        continue
    }

    Write-Host "  $pkgName" -NoNewline

    Push-Location $pkgPath
    try {
        $out = flutter test --reporter compact 2>&1 | Out-String

        # Extrai contagem: remove codigos ANSI antes de parsear
        $clean = [regex]::Replace($out, '\x1b\[[0-9;]*m', '')
        $match = [regex]::Match($clean, '\+(\d+):\s*All tests passed')
        if ($match.Success) { $totalTestes += [int]$match.Groups[1].Value }

        if ($LASTEXITCODE -ne 0) {
            Write-Host " -- FALHOU" -ForegroundColor Red
            $falhas += $pkgName
            # Imprime as ultimas linhas do output para facilitar o diagnostico
            ($out -split "`n" | Select-Object -Last 10 | Where-Object { $_ -ne "" }) |
                ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
        } else {
            $resumo = ($out -split "`n" | Where-Object { $_ -match "All tests passed" } | Select-Object -Last 1).Trim()
            Write-Host " -- $resumo" -ForegroundColor Green
        }
    } finally {
        Pop-Location
    }
}

# --------------------------------------------
# Resumo
# --------------------------------------------
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Total de testes executados: $totalTestes"
if ($falhas.Count -eq 0) {
    Write-Host "  TUDO VERDE - pode dar push." -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Cyan
    exit 0
} else {
    Write-Host "  FALHAS: $($falhas -join ', ')" -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Cyan
    exit 1
}
