# Executa o smart-core-admin (Flutter Web) com o arquivo de ambiente desejado (.env.dev ou .env.prod).
# Uso:  .\run-admin.ps1 -Env dev
#       .\run-admin.ps1 -Env prod
#       .\run-admin.ps1 -Env dev -Device web-server -Port 8080
param(
    [ValidateSet("dev", "prod")]
    [string]$Env = "dev",
    [ValidateSet("chrome", "web-server")]
    [string]$Device   = "chrome",
    [int]   $Port     = 0
)

$AppDir = "$PSScriptRoot/apps/smart-core-admin"
$EnvFile = "$PSScriptRoot/.env.$Env"

if (-not (Test-Path $EnvFile)) {
    Write-Host "Erro: Arquivo de ambiente $EnvFile nao encontrado!" -ForegroundColor Red
    exit 1
}

$args = @(
    "run",
    "-d", $Device,
    "-t", "lib/main_$Env.dart",
    "--dart-define-from-file=../../.env.$Env"
)
if ($Port -gt 0) { $args += "--web-port=$Port" }

Write-Host "Iniciando smart-core-admin ($Device) usando o arquivo de ambiente: $EnvFile"
Set-Location $AppDir
flutter @args
