# ============================================
# Gerenciador Remoto - Infraestrutura de Dados
# Smart Core Assistant v2
# ============================================
# Execute a partir da pasta infra/:
#   cd infra
#   .\manage.ps1              (menu interativo)
#   .\manage.ps1 -Action logs (acao direta)
#
# Acoes disponiveis: deploy, rebuild, stop, restart, logs, stats
# ============================================

param (
    [string]$Action = ""
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Carregar configuracoes
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

if (-not $HOSTINGER_SSH_PORT) { $HOSTINGER_SSH_PORT = "22" }

function Run-SSH {
    param([string]$Command, [string]$Title)
    if ($Title) {
        Write-Host ""
        Write-Host $Title -ForegroundColor Cyan
        Write-Host "--------------------------------------------" -ForegroundColor DarkGray
    }
    ssh -p $HOSTINGER_SSH_PORT "$HOSTINGER_SSH_USER@$HOSTINGER_SSH_HOST" $Command
}

function Show-Menu {
    Clear-Host
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  GERENCIADOR DATA - SMART CORE V2" -ForegroundColor Cyan
    Write-Host "  Servidor: $HOSTINGER_SSH_HOST" -ForegroundColor DarkGray
    Write-Host "  Deploy:   $DEPLOY_PATH" -ForegroundColor DarkGray
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "1. Deploy    (enviar arquivos + subir containers)"
    Write-Host "2. Rebuild   (recriar containers do zero)"
    Write-Host "3. Stop      (parar e remover containers)"
    Write-Host "4. Restart   (reiniciar containers)"
    Write-Host "5. Logs      (ver logs em tempo real)"
    Write-Host "6. Stats     (uso de CPU/memoria)"
    Write-Host "0. Sair"
    Write-Host "============================================" -ForegroundColor Cyan

    $choice = Read-Host "Escolha uma opcao"
    return $choice
}

if ($Action -eq "") {
    $choice = Show-Menu
} else {
    switch ($Action.ToLower()) {
        "deploy"  { $choice = "1" }
        "rebuild" { $choice = "2" }
        "stop"    { $choice = "3" }
        "restart" { $choice = "4" }
        "logs"    { $choice = "5" }
        "stats"   { $choice = "6" }
        default   { Write-Host "Acao desconhecida: $Action"; exit 1 }
    }
}

switch ($choice) {
    "1" {
        Write-Host "Enviando arquivos e subindo containers..." -ForegroundColor Yellow
        scp -P $HOSTINGER_SSH_PORT ..\docker\compose\data.yml "$HOSTINGER_SSH_USER@$HOSTINGER_SSH_HOST`:$DEPLOY_PATH/docker-compose.yml"
        scp -P $HOSTINGER_SSH_PORT .env.deploy "$HOSTINGER_SSH_USER@$HOSTINGER_SSH_HOST`:$DEPLOY_PATH/.env"
        $cmd = "cd $DEPLOY_PATH && docker compose pull && docker compose up -d --remove-orphans && docker compose ps"
        Run-SSH -Command $cmd -Title "Executando Deploy..."
    }

    "2" {
        Write-Host "Rebuild completo dos containers..." -ForegroundColor Yellow
        if ($Action -eq "") {
            $confirm = Read-Host "Isso vai derrubar os servicos temporariamente. Continuar? (S/N)"
            if ($confirm -ne "S" -and $confirm -ne "s") { exit }
        }
        scp -P $HOSTINGER_SSH_PORT ..\docker\compose\data.yml "$HOSTINGER_SSH_USER@$HOSTINGER_SSH_HOST`:$DEPLOY_PATH/docker-compose.yml"
        scp -P $HOSTINGER_SSH_PORT .env.deploy "$HOSTINGER_SSH_USER@$HOSTINGER_SSH_HOST`:$DEPLOY_PATH/.env"
        $cmd = "cd $DEPLOY_PATH && docker compose down && docker system prune -af && docker compose pull && docker compose up -d --force-recreate && docker compose ps"
        Run-SSH -Command $cmd -Title "Executando Rebuild..."
    }

    "3" {
        Write-Host "Parando containers..." -ForegroundColor Yellow
        Run-SSH -Command "cd $DEPLOY_PATH && docker compose down" -Title "Parando..."
    }

    "4" {
        Write-Host "Reiniciando containers..." -ForegroundColor Yellow
        Run-SSH -Command "cd $DEPLOY_PATH && docker compose restart && docker compose ps" -Title "Reiniciando..."
    }

    "5" {
        Write-Host "Conectando aos logs... (Ctrl+C para sair)" -ForegroundColor Yellow
        ssh -p $HOSTINGER_SSH_PORT -t "$HOSTINGER_SSH_USER@$HOSTINGER_SSH_HOST" "cd $DEPLOY_PATH && docker compose logs -f --tail=100"
    }

    "6" {
        Write-Host "Verificando recursos..." -ForegroundColor Yellow
        ssh -p $HOSTINGER_SSH_PORT -t "$HOSTINGER_SSH_USER@$HOSTINGER_SSH_HOST" "docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'"
    }
}
