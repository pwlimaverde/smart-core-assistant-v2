# Limpeza de artefatos antigos do target/ Rust via cargo-sweep
# Remove arquivos não acessados há mais de 30 dias
# Executado semanalmente pela tarefa agendada "SmartCore-CargoSweep"

param(
    [int]$DiasRetencao = 30,
    [switch]$DryRun
)

$serverPath = Join-Path $PSScriptRoot "..\server"
$serverPath = Resolve-Path $serverPath

Write-Host "SmartCore — limpeza do target/ em: $serverPath"
Write-Host "Retencao: $DiasRetencao dias | DryRun: $DryRun"
Write-Host ""

if (-not (Get-Command cargo-sweep -ErrorAction SilentlyContinue)) {
    Write-Error "cargo-sweep nao encontrado. Instale com: cargo install cargo-sweep"
    exit 1
}

$args = @("--time", $DiasRetencao)
if ($DryRun) { $args += "--dry-run" }

Push-Location $serverPath
try {
    cargo sweep @args
    Write-Host ""
    $tamanho = (Get-ChildItem "target" -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    Write-Host ("Target apos limpeza: {0:N1} GB" -f ($tamanho / 1GB))
} finally {
    Pop-Location
}
