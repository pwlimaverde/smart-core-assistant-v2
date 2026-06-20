# ==============================================================================
# Script de Backup Seguro de Arquivos .env (Smart Core Assistant v2)
# ==============================================================================
# Este script localiza os arquivos .env locais e de deploy e os criptografa
# utilizando AES-256-CBC via OpenSSL com uma senha de sua escolha.
# Os arquivos criptografados gerados (.enc) podem ser salvos com segurança
# em nuvens comerciais (Google Drive, OneDrive) ou repositórios.
# ==============================================================================

$ErrorActionPreference = "Stop"

# Caminhos padrão dos arquivos de ambiente (modelo full-docker). Os .env reais
# (com segredos) ficam fora do git, em docker/compose/env/. Faça uma cópia local
# antes de rodar este backup, se eles vivem só no servidor.
$EnvFiles = @{
    "App-Local"   = "../.env"
    "Compose-Dev"  = "../docker/compose/env/dev.env"
    "Compose-Prod" = "../docker/compose/env/prod.env"
}

# Criar pasta de backup se não existir
$BackupDir = "./backups"
if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir | Out-Null
}

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "    Backup Seguro de Arquivos .env — Smart Core Assistant v2" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

# Verificar se OpenSSL está instalado
try {
    $OpenSslVersion = & openssl version
    Write-Host "✓ OpenSSL detectado: $OpenSslVersion" -ForegroundColor Green
} catch {
    Write-Host "✗ Erro: OpenSSL não foi encontrado no PATH do sistema." -ForegroundColor Red
    Write-Host "Por favor, instale o OpenSSL ou garanta que ele esteja acessível para rodar a criptografia." -ForegroundColor Yellow
    Exit
}

# Solicitar senha forte para criptografia (lida como SecureString para não ficar visível)
$SecurePassword = Read-Host -Prompt "Digite uma senha forte para criptografar os arquivos" -AsSecureString
$Password = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword))
if ([string]::IsNullOrWhiteSpace($Password)) {
    Write-Host "✗ Erro: A senha não pode ser vazia." -ForegroundColor Red
    Exit
}

$SecureConfirm = Read-Host -Prompt "Confirme a senha" -AsSecureString
$ConfirmPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureConfirm))
if ($Password -ne $ConfirmPassword) {
    Write-Host "✗ Erro: As senhas digitadas não coincidem." -ForegroundColor Red
    Exit
}

Write-Host "`nIniciando criptografia dos arquivos..." -ForegroundColor Cyan

$SuccessCount = 0
foreach ($Key in $EnvFiles.Keys) {
    $FilePath = $EnvFiles[$Key]
    if (Test-Path $FilePath) {
        $FileName = [System.IO.Path]::GetFileName($FilePath)
        $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $OutPath = "$BackupDir/${FileName}_${Timestamp}.enc"

        Write-Host "Criptografando $Key ($FileName) -> $OutPath ..." -ForegroundColor Yellow

        # Executar comando OpenSSL para criptografar com PBKDF2 e AES-256.
        # A senha é passada via variável de ambiente (pass:env:) para não ficar
        # visível na linha de comando / lista de processos do sistema.
        $env:BACKUP_ENC_PASS = $Password
        & openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 -pass "env:BACKUP_ENC_PASS" -in $FilePath -out $OutPath
        Remove-Item Env:\BACKUP_ENC_PASS -ErrorAction SilentlyContinue

        if (Test-Path $OutPath) {
            Write-Host "✓ $Key criptografado com sucesso!" -ForegroundColor Green
            $SuccessCount++
        }
    } else {
        Write-Host "- Arquivo de ambiente para '$Key' não encontrado em: $FilePath (Ignorado)" -ForegroundColor Gray
    }
}

Write-Host "`n======================================================================" -ForegroundColor Cyan
if ($SuccessCount -gt 0) {
    Write-Host "✓ Backup concluído! $SuccessCount arquivo(s) salvo(s) de forma criptografada em '$BackupDir'." -ForegroundColor Green
    Write-Host "Para decriptar um arquivo no futuro, execute:" -ForegroundColor Yellow
    Write-Host "  openssl enc -d -aes-256-cbc -salt -pbkdf2 -iter 100000 -in <arquivo.enc> -out .env" -ForegroundColor White
} else {
    Write-Host "ℹ Nenhum arquivo de ambiente .env ativo foi encontrado para backup." -ForegroundColor Yellow
}
Write-Host "======================================================================" -ForegroundColor Cyan
