# Executa o smart-core-admin no Chrome (flavor dev).
# Uso:  .\run-admin.ps1
#       .\run-admin.ps1 -Endpoint "tcp://localhost:50051"
#       .\run-admin.ps1 -Endpoint "https://dev.smartcoreassistant.com.br" (dev remoto)
#       .\run-admin.ps1 -Device web-server -Port 8080
param(
    [string]$Endpoint = "tcp://localhost:50051",
    [ValidateSet("chrome", "web-server")]
    [string]$Device   = "chrome",
    [int]   $Port     = 0
)

$AppDir = "$PSScriptRoot/apps/smart-core-admin"

$args = @(
    "run",
    "-d", $Device,
    "-t", "lib/main_dev.dart",
    "--dart-define=SMARTCORE_API_ENDPOINT=$Endpoint"
)
if ($Port -gt 0) { $args += "--web-port=$Port" }

Write-Host "Iniciando smart-core-admin ($Device) → $Endpoint"
Set-Location $AppDir
flutter @args
