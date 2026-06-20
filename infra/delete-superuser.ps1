# ============================================
# Exclusao interativa de superusuario — modelo FULL-DOCKER
# Smart Core Assistant v2
# ============================================
# A stack roda 100% em Docker no servidor. Este script roda o CLI interativo
# (lista -> seleciona -> confirma) DENTRO do container control_plane ja no ar,
# via SSH com TTY:
#
#   ssh -t <alias> docker exec -it <container> control_plane delete-superuser
#
# Uso (a partir da raiz do repo ou de infra/):
#   .\infra\delete-superuser.ps1
#   .\infra\delete-superuser.ps1 -Env prod
#
# Requisitos: acesso SSH ao servidor (alias em ~/.ssh/config, padrao hostinger-root).
# ============================================

[CmdletBinding()]
param(
    [ValidateSet("dev", "prod")]
    [string]$Env = "dev",
    [string]$SshAlias = "hostinger-root"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$container = "smart-core-v2-$Env-control_plane-1"

if ($Env -eq "prod") {
    Write-Host "Ambiente: PRODUCAO ($container)" -ForegroundColor Red
} else {
    Write-Host "Ambiente: DESENVOLVIMENTO ($container)" -ForegroundColor Yellow
}

# Confere se o container esta no ar antes do exec interativo.
$check = ssh $SshAlias "docker ps --format '{{.Names}}' --filter name=^${container}$"
if ($check -notmatch [Regex]::Escape($container)) {
    throw "Container '$container' nao esta rodando no servidor. Suba a stack ($Env) antes."
}

# -t (ssh) + -it (docker exec): aloca TTY para o fluxo interativo do CLI.
ssh -t $SshAlias "docker exec -it $container control_plane delete-superuser"
$cliExit = $LASTEXITCODE

if ($cliExit -ne 0) {
    Write-Host "A exclusao falhou ou foi cancelada (codigo $cliExit)." -ForegroundColor Red
    exit $cliExit
}
Write-Host "Concluido." -ForegroundColor Green
