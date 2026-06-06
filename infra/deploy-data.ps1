# ============================================
# Script de Deploy - Infraestrutura de Dados v2
# Smart Core Assistant v2
# ============================================
# Execute a partir da pasta infra/:
#   cd infra
#   .\deploy-data.ps1
# ============================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  DEPLOY DATA - SMART CORE V2 - HOSTINGER" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Verificar se .env.deploy existe
if (-not (Test-Path ".env.deploy")) {
    Write-Host "Erro: .env.deploy nao encontrado!" -ForegroundColor Red
    Write-Host "Copie .env.deploy.example para .env.deploy e preencha as credenciais." -ForegroundColor Yellow
    exit 1
}

# Carregar variaveis de deploy
Get-Content .env.deploy | ForEach-Object {
    if ($_ -match '^([^#=][^=]*)=(.*)$') {
        $name = $matches[1].Trim()
        $value = $matches[2].Trim().Trim('"')
        Set-Variable -Name $name -Value $value -Scope Script
    }
}

# Validar variaveis obrigatorias
$required = @("HOSTINGER_SSH_HOST", "HOSTINGER_SSH_USER", "HOSTINGER_SSH_PORT", "DEPLOY_PATH",
              "POSTGRES_PASSWORD", "REDIS_PASSWORD", "MINIO_ROOT_PASSWORD")
foreach ($var in $required) {
    $val = (Get-Variable -Name $var -ErrorAction SilentlyContinue).Value
    if (-not $val -or $val -like "*DEFINIR*") {
        Write-Host "Erro: $var nao definido ou ainda com valor placeholder em .env.deploy" -ForegroundColor Red
        exit 1
    }
}

Write-Host "Conectando ao servidor: $HOSTINGER_SSH_HOST" -ForegroundColor Yellow

# Criar diretorios no servidor
Write-Host "Criando diretorios remotos..." -ForegroundColor Blue
ssh -p $HOSTINGER_SSH_PORT "$HOSTINGER_SSH_USER@$HOSTINGER_SSH_HOST" "mkdir -p $DEPLOY_PATH/init-scripts"

# Enviar docker-compose.yml
Write-Host "Enviando docker-compose..." -ForegroundColor Blue
scp -P $HOSTINGER_SSH_PORT ..\docker\compose\data.yml "$HOSTINGER_SSH_USER@$HOSTINGER_SSH_HOST`:$DEPLOY_PATH/docker-compose.yml"

# Enviar .env.deploy como .env no servidor (docker compose le .env automaticamente)
Write-Host "Enviando .env..." -ForegroundColor Blue
scp -P $HOSTINGER_SSH_PORT .env.deploy "$HOSTINGER_SSH_USER@$HOSTINGER_SSH_HOST`:$DEPLOY_PATH/.env"

# Enviar init-scripts
Write-Host "Enviando init-scripts..." -ForegroundColor Blue
scp -P $HOSTINGER_SSH_PORT ..\docker\init-scripts\01-extensions.sql "$HOSTINGER_SSH_USER@$HOSTINGER_SSH_HOST`:$DEPLOY_PATH/init-scripts/"

# Executar deploy no servidor
Write-Host "Iniciando containers no servidor..." -ForegroundColor Blue

$deployCommands = @"
cd $DEPLOY_PATH

echo 'Atualizando imagens Docker...'
docker compose pull

echo 'Iniciando containers...'
docker compose up -d --remove-orphans

echo 'Aguardando containers iniciarem...'
sleep 15

echo 'Status dos containers:'
docker compose ps

echo 'Uso de recursos:'
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'

echo 'Limpando imagens antigas...'
docker image prune -af

echo ''
echo '============================================'
echo '  DEPLOY CONCLUIDO COM SUCESSO!'
echo '============================================'
"@

ssh -p $HOSTINGER_SSH_PORT "$HOSTINGER_SSH_USER@$HOSTINGER_SSH_HOST" $deployCommands

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  DEPLOY REALIZADO COM SUCESSO!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Para conectar localmente ao banco, execute:" -ForegroundColor Cyan
Write-Host "  .\tunnel.ps1" -ForegroundColor White
Write-Host ""
Write-Host "Comandos uteis:" -ForegroundColor Yellow
Write-Host "  Gerenciar:  .\manage.ps1"
Write-Host "  Logs:       ssh -p $HOSTINGER_SSH_PORT $HOSTINGER_SSH_USER@$HOSTINGER_SSH_HOST 'cd $DEPLOY_PATH && docker compose logs -f'"
Write-Host "  Status:     ssh -p $HOSTINGER_SSH_PORT $HOSTINGER_SSH_USER@$HOSTINGER_SSH_HOST 'cd $DEPLOY_PATH && docker compose ps'"
Write-Host ""
