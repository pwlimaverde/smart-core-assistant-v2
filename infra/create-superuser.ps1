# ============================================
# Cadastro do superusuario (bootstrap) — modelo FULL-DOCKER
# Smart Core Assistant v2
# ============================================
# A stack roda 100% em Docker no servidor. O CLI do control_plane e um cliente
# fino que fala com o data_postgres via RPC (rede interna do compose). Em vez de
# tunelar o banco e compilar localmente, este script roda o CLI DENTRO do
# container control_plane ja no ar, via SSH:
#
#   ssh <alias> docker exec <container> control_plane create-superuser ...
#
# O container ja tem o env correto (SMARTCORE_DATA_POSTGRES_ENDPOINT,
# ENCRYPTION_KEY, etc.) injetado pelo compose.
#
# Uso (a partir da raiz do repo ou de infra/):
#   .\infra\create-superuser.ps1 -Username admin -Email admin@local -Password "SenhaForte8+"
#   .\infra\create-superuser.ps1 -Env prod -Username admin -Email a@b.com
#
# Requisitos: acesso SSH ao servidor (alias em ~/.ssh/config, padrao hostinger-root).
# ============================================

[CmdletBinding()]
param(
    [string]$Username,
    [string]$Email,
    [string]$Password,
    [ValidateSet("dev", "prod")]
    [string]$Env = "dev",
    [string]$SshAlias = "hostinger-root"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$container = "smart-core-v2-$Env-control_plane-1"

# --- Entrada interativa dos parametros que faltarem ---
while ([string]::IsNullOrWhiteSpace($Username)) { $Username = Read-Host "Username" }
while ([string]::IsNullOrWhiteSpace($Email))    { $Email = Read-Host "Email" }
while ([string]::IsNullOrWhiteSpace($Password)) {
    $sec = Read-Host "Password" -AsSecureString
    if ($sec) {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try { $Password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
}

# Validacao simples de username/email (vao interpolados na linha de comando remota).
if ($Username -notmatch '^[A-Za-z0-9._@+-]+$') { throw "Username com caracteres invalidos." }
if ($Email -and $Email -notmatch '^[A-Za-z0-9._@+-]+$') { throw "Email com caracteres invalidos." }

# A senha vai em base64 (env do docker exec) e e decodificada no servidor: evita
# problemas de escaping com caracteres especiais e nao aparece em texto puro na
# linha de comando (fica base64; ainda assim, use senhas fortes e rotacione).
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Password))

if ($Env -eq "prod") {
    Write-Host "Ambiente: PRODUCAO ($container)" -ForegroundColor Red
} else {
    Write-Host "Ambiente: DESENVOLVIMENTO ($container)" -ForegroundColor Yellow
}

# Confere se o container esta no ar antes de tentar o exec.
$check = ssh $SshAlias "docker ps --format '{{.Names}}' --filter name=^${container}$"
if ($check -notmatch [Regex]::Escape($container)) {
    throw "Container '$container' nao esta rodando no servidor. Suba a stack ($Env) antes."
}

Write-Host "Cadastrando superusuario '$Username'..." -ForegroundColor Cyan

# Comando que roda no /bin/sh do container. Username/Email ja validados (charset
# seguro). A senha chega na env SU_PW_B64 (base64) e e decodificada aqui dentro,
# evitando qualquer problema de escaping com caracteres especiais.
$inner = 'control_plane create-superuser --username "' + $Username + '"'
if ($Email -and $Email.Trim() -ne '') { $inner += ' --email "' + $Email.Trim() + '"' }
$inner += ' --password "$(printf %s "$SU_PW_B64" | base64 -d)"'

# base64 so tem [A-Za-z0-9+/=], seguro sem aspas no shell.
$remote = "docker exec -e SU_PW_B64=$pwB64 $container sh -c '$inner'"

ssh $SshAlias $remote
$cliExit = $LASTEXITCODE

if ($cliExit -ne 0) {
    Write-Host "Falhou ao cadastrar o superusuario (codigo $cliExit)." -ForegroundColor Red
    exit $cliExit
}
Write-Host "Concluido." -ForegroundColor Green
