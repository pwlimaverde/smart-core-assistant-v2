# ============================================
# SSH Tunnels - Desenvolvimento Local
# Smart Core Assistant v2
# ============================================
# Mapeia as portas do Hostinger para localhost,
# permitindo que o codigo Rust local conecte aos
# bancos remotos como se fossem locais.
#
# Execute a partir da pasta infra/:
#   cd infra
#   .\tunnel.ps1
#
# Mantenha este terminal aberto enquanto desenvolve.
# Pressione Ctrl+C para encerrar os tunnels.
# ============================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if (-not (Test-Path ".env.deploy")) {
    Write-Host "Erro: .env.deploy nao encontrado!" -ForegroundColor Red
    exit 1
}

Get-Content .env.deploy | ForEach-Object {
    if ($_ -match '^([^#=][^=]*)=(.*)$') {
        $name = $matches[1].Trim()
        $value = $matches[2].Trim().Trim('"')
        Set-Variable -Name $name -Value $value -Scope Script
    }
}

if (-not $POSTGRES_PORT) { $POSTGRES_PORT = "5432" }
if (-not $REDIS_PORT)    { $REDIS_PORT    = "6379" }
if (-not $MINIO_PORT)    { $MINIO_PORT    = "9000" }
if (-not $MINIO_CONSOLE_PORT) { $MINIO_CONSOLE_PORT = "9001" }

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SSH TUNNELS - SMART CORE V2" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Servidor remoto: $HOSTINGER_SSH_HOST" -ForegroundColor Yellow
Write-Host ""
Write-Host "Portas mapeadas para localhost:" -ForegroundColor Green
Write-Host "  PostgreSQL : localhost:5432  ->  $HOSTINGER_SSH_HOST`:$POSTGRES_PORT"
Write-Host "  Redis      : localhost:6379  ->  $HOSTINGER_SSH_HOST`:$REDIS_PORT"
Write-Host "  MinIO API  : localhost:9000  ->  $HOSTINGER_SSH_HOST`:$MINIO_PORT"
Write-Host "  MinIO UI   : localhost:9001  ->  $HOSTINGER_SSH_HOST`:$MINIO_CONSOLE_PORT"
Write-Host ""
Write-Host "Configure o .env local da aplicacao com:" -ForegroundColor Cyan
Write-Host "  DATABASE_URL=postgresql://smartcore_app:SENHA@localhost:5432/smartcore_v2"
Write-Host "  REDIS_URL=redis://:SENHA@localhost:6379"
Write-Host "  MINIO_ENDPOINT=http://localhost:9000"
Write-Host ""
Write-Host "MinIO Console: http://localhost:9001" -ForegroundColor Blue
Write-Host ""
Write-Host "Pressione Ctrl+C para encerrar os tunnels." -ForegroundColor Yellow
Write-Host ""

ssh -p $HOSTINGER_SSH_PORT `
    -L "5432:localhost:$POSTGRES_PORT" `
    -L "6379:localhost:$REDIS_PORT" `
    -L "9000:localhost:$MINIO_PORT" `
    -L "9001:localhost:$MINIO_CONSOLE_PORT" `
    -N `
    "$HOSTINGER_SSH_USER@$HOSTINGER_SSH_HOST"
