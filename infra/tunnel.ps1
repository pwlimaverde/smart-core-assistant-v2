# ============================================
# SSH Tunnels para a stack remota — modelo FULL-DOCKER
# Smart Core Assistant v2
# ============================================
# No modelo full-docker, Postgres/Redis/MinIO NAO publicam portas no host (ficam
# so na rede interna do compose). Para inspecionar o banco remoto com ferramentas
# locais (DBeaver, redis-cli, etc.), este script descobre o IP de cada container
# na rede interna do ambiente e faz o forward SSH ate ele.
#
# Para DESENVOLVIMENTO normal, prefira rodar a stack LOCALMENTE:
#   cd docker/dev
#   docker compose --env-file .env up -d
# (no Windows o transport usa TCP; nao precisa de tunel).
#
# Uso (a partir de infra/ ou da raiz):
#   .\infra\tunnel.ps1            # ambiente dev (padrao)
#   .\infra\tunnel.ps1 -Env prod
#
# Mantenha o terminal aberto; Ctrl+C encerra. Requer SSH (alias hostinger-root).
# ============================================

[CmdletBinding()]
param(
    [ValidateSet("dev", "prod")]
    [string]$Env = "dev",
    [string]$SshAlias = "hostinger-root"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$net = "smart-core-v2-${Env}_internal"

# servico-do-compose -> @{ remote = porta no container; local = porta em localhost }
$mapa = [ordered]@{
    "postgres"  = @{ remote = 5432; local = 5434 }
    "redis"     = @{ remote = 6379; local = 6379 }
    "redis-bus" = @{ remote = 6379; local = 6380 }
    "minio"     = @{ remote = 9000; local = 9000 }
}

Write-Host "Descobrindo IPs dos containers na rede '$net'..." -ForegroundColor Cyan
$forwards = @()
foreach ($svc in $mapa.Keys) {
    $container = "smart-core-v2-$Env-$svc-1"
    $fmt = "{{(index .NetworkSettings.Networks `"$net`").IPAddress}}"
    $ip = (ssh $SshAlias "docker inspect -f '$fmt' $container" 2>$null).Trim()
    if ([string]::IsNullOrWhiteSpace($ip)) {
        Write-Host "  ! $container nao encontrado/na rede (pulando)" -ForegroundColor DarkYellow
        continue
    }
    $l = $mapa[$svc].local; $r = $mapa[$svc].remote
    $forwards += "-L"; $forwards += "${l}:${ip}:${r}"
    Write-Host ("  localhost:{0,-5} -> {1}:{2}  ({3})" -f $l, $ip, $r, $svc) -ForegroundColor Green
}

if ($forwards.Count -eq 0) { throw "Nenhum container encontrado para o ambiente '$Env'. A stack esta no ar?" }

Write-Host ""
Write-Host "Conexoes locais (use a senha do env do ambiente):" -ForegroundColor Cyan
Write-Host "  DATABASE_URL = postgresql://smartcore_app:SENHA@localhost:5434/smartcore_v2"
Write-Host "  REDIS_URL    = redis://:SENHA@localhost:6379"
Write-Host "  REDIS_BUS    = redis://:SENHA@localhost:6380"
Write-Host "  MinIO API    = http://localhost:9000"
Write-Host ""
Write-Host "Tunel ativo. Ctrl+C para encerrar." -ForegroundColor Yellow

ssh @forwards -N $SshAlias
