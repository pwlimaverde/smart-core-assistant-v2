# ============================================
# Cadastro do superusuario padrao (bootstrap)
# Smart Core Assistant v2
# ============================================
# O CLI do control_plane e um cliente fino: fala com o data_postgres via RPC
# (o banco tem uma unica porta de acesso, a infra do Postgres). Em Windows o
# transport usa TCP. Este script orquestra tudo em um comando:
#   1) carrega server/.env (DATABASE_URL, REDIS_URL, ...)
#   2) garante o tunel SSH (Postgres + Redis remotos), se necessario
#   3) sobe o data_postgres em TCP (se nao estiver no ar)
#   4) roda o CLI create-superuser
#   5) encerra o que ESTE script subiu (tunel/servico)
#
# Uso (a partir da raiz do repo ou de infra/):
#   .\infra\create-superuser.ps1 -Username admin -Email admin@local -Password "SenhaForte8+"
# ============================================

[CmdletBinding()]
param(
    [string]$Username,
    [string]$Email,
    [string]$Password,
    [int]$RpcPort = 7001
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$infraDir = $PSScriptRoot
$rootDir = Split-Path -Parent $infraDir
$serverDir = Join-Path $rootDir "server"

# --- Validacao e Entrada de Parametros Interativa ---
while ([string]::IsNullOrWhiteSpace($Username)) {
    $Username = Read-Host "Username"
}
while ([string]::IsNullOrWhiteSpace($Email)) {
    $Email = Read-Host "Email"
}
while ([string]::IsNullOrWhiteSpace($Password)) {
    # Solicita a senha ocultando a digitacao
    $PasswordSecure = Read-Host "Password" -AsSecureString
    if ($PasswordSecure) {
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PasswordSecure)
        try {
            $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
        } finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        }
    }
}

function Test-Port([int]$porta) {
    $cliente = New-Object Net.Sockets.TcpClient
    try { $cliente.Connect("127.0.0.1", $porta); return $true }
    catch { return $false }
    finally { $cliente.Close() }
}

function Wait-Port([int]$porta, [int]$timeoutSeg = 40) {
    $fim = (Get-Date).AddSeconds($timeoutSeg)
    while ((Get-Date) -lt $fim) {
        if (Test-Port $porta) { return $true }
        Start-Sleep -Milliseconds 400
    }
    return $false
}

function Get-PortaDaUrl([string]$url, [int]$padrao) {
    # extrai a porta de "...@host:porta/..." ou "...//host:porta"
    if ($url -match '@[^:/]+:(\d+)') { return [int]$matches[1] }
    if ($url -match '//[^:/]+:(\d+)') { return [int]$matches[1] }
    return $padrao
}

# --- 1) Carrega server/.env no ambiente do processo (herdado pelos filhos) ---
$envFile = Join-Path $serverDir ".env"
if (-not (Test-Path $envFile)) { throw "server/.env nao encontrado em $envFile" }
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([^#=][^=]*)=(.*)$') {
        $nome = $matches[1].Trim()
        $valor = $matches[2].Trim().Trim('"').Trim("'")
        [Environment]::SetEnvironmentVariable($nome, $valor, "Process")
    }
}
$databaseUrl = [Environment]::GetEnvironmentVariable("DATABASE_URL", "Process")
$redisUrl = [Environment]::GetEnvironmentVariable("REDIS_URL", "Process")
$redisBusUrl = [Environment]::GetEnvironmentVariable("REDIS_BUS_URL", "Process")

# Silencia logs de depuracao e telemetria OTLP para manter o terminal interativo limpo
$env:RUST_LOG = "warn"
$env:OTEL_SDK_DISABLED = "true"

if (-not $databaseUrl) { throw "DATABASE_URL ausente no server/.env" }

$pgLocal = Get-PortaDaUrl $databaseUrl 5434
$redisLocal = if ($redisUrl) { Get-PortaDaUrl $redisUrl 6379 } else { 6379 }
$redisBusLocal = if ($redisBusUrl) { Get-PortaDaUrl $redisBusUrl 6380 } else { 6380 }

# Endpoint TCP do data_postgres (servidor e cliente leem a MESMA variavel).
$env:SMARTCORE_DATA_POSTGRES_ENDPOINT = "tcp://127.0.0.1:$RpcPort"

$sshProc = $null
$dpProc = $null
$cliExit = 0
try {
    # --- 2) Tunel SSH (Postgres + Redis), se a porta do Postgres estiver fechada ---
    if (-not (Test-Port $pgLocal)) {
        $deployFile = Join-Path $infraDir ".env.deploy"
        if (-not (Test-Path $deployFile)) { throw "infra/.env.deploy nao encontrado (necessario para o tunel SSH)" }
        $deploy = @{}
        Get-Content $deployFile | ForEach-Object {
            if ($_ -match '^\s*([^#=][^=]*)=(.*)$') { $deploy[$matches[1].Trim()] = $matches[2].Trim().Trim('"').Trim("'") }
        }
        $sshHost = $deploy["HOSTINGER_SSH_HOST"]; $sshUser = $deploy["HOSTINGER_SSH_USER"]
        $sshPort = if ($deploy["HOSTINGER_SSH_PORT"]) { $deploy["HOSTINGER_SSH_PORT"] } else { "22" }
        $pgRemote = if ($deploy["POSTGRES_PORT"]) { $deploy["POSTGRES_PORT"] } else { "5432" }
        $redisRemote = if ($deploy["REDIS_PORT"]) { $deploy["REDIS_PORT"] } else { "6379" }
        $redisBusRemote = if ($deploy["REDIS_BUS_PORT"]) { $deploy["REDIS_BUS_PORT"] } else { "6381" }
        if (-not $sshHost -or -not $sshUser) { throw "HOSTINGER_SSH_HOST/USER ausentes em infra/.env.deploy" }

        Write-Host "Abrindo tunel SSH (Postgres $pgLocal, Redis Cache $redisLocal, Redis Bus $redisBusLocal)..." -ForegroundColor Cyan
        $sshArgs = @("-p", $sshPort, "-N",
            "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new", "-o", "ExitOnForwardFailure=yes",
            "-L", "${pgLocal}:localhost:$pgRemote",
            "-L", "${redisLocal}:localhost:$redisRemote",
            "-L", "${redisBusLocal}:localhost:$redisBusRemote",
            "$sshUser@$sshHost")
        if ($deploy["HOSTINGER_SSH_IDENTITY_FILE"]) { $sshArgs += @("-i", $deploy["HOSTINGER_SSH_IDENTITY_FILE"]) }
        $sshProc = Start-Process -FilePath "ssh" -ArgumentList $sshArgs -PassThru -WindowStyle Hidden
        if (-not (Wait-Port $pgLocal 25)) { throw "tunel SSH iniciado mas a porta $pgLocal nao respondeu" }
    }
    else {
        Write-Host "Postgres ja acessivel em localhost:$pgLocal (tunel reaproveitado)." -ForegroundColor DarkGray
    }

    # --- 3) Compila e sobe o data_postgres em TCP, se necessario ---
    Push-Location $serverDir
    try {
        Write-Host "Compilando data_postgres e control_plane..." -ForegroundColor Cyan
        $env:SQLX_OFFLINE = "true"
        cargo build -p data_postgres -p control_plane | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "falha ao compilar (cargo build)" }

        $dpExe = Join-Path $serverDir "target\debug\data_postgres.exe"
        $cpExe = Join-Path $serverDir "target\debug\control_plane.exe"

        if (-not (Test-Port $RpcPort)) {
            Write-Host "Subindo data_postgres em $($env:SMARTCORE_DATA_POSTGRES_ENDPOINT)..." -ForegroundColor Cyan
            $logOut = Join-Path $env:TEMP "smartcore_data_postgres.out.log"
            $logErr = Join-Path $env:TEMP "smartcore_data_postgres.err.log"
            $dpProc = Start-Process -FilePath $dpExe -PassThru -WindowStyle Hidden `
                -RedirectStandardOutput $logOut -RedirectStandardError $logErr
            if (-not (Wait-Port $RpcPort 40)) {
                throw "data_postgres nao respondeu em $RpcPort. Veja o log: $logErr"
            }
        }
        else {
            Write-Host "data_postgres ja acessivel em $RpcPort (reaproveitado)." -ForegroundColor DarkGray
        }

        # --- 4) Roda o CLI create-superuser ---
        Write-Host "Cadastrando superusuario '$Username'..." -ForegroundColor Cyan
        
        $argsList = @("create-superuser", "--username", $Username)
        if ($Email -and $Email.Trim() -ne "") {
            $argsList += @("--email", $Email.Trim())
        }
        $argsList += @("--password", $Password)

        & $cpExe $argsList
        $cliExit = $LASTEXITCODE
    }
    finally { Pop-Location }
}
finally {
    # --- 5) Encerra apenas o que ESTE script subiu ---
    if ($dpProc -and -not $dpProc.HasExited) {
        Write-Host "Encerrando data_postgres..." -ForegroundColor DarkGray
        Stop-Process -Id $dpProc.Id -Force -ErrorAction SilentlyContinue
    }
    if ($sshProc -and -not $sshProc.HasExited) {
        Write-Host "Encerrando tunel SSH..." -ForegroundColor DarkGray
        Stop-Process -Id $sshProc.Id -Force -ErrorAction SilentlyContinue
    }
}

# --- 6) Resultado final (sem stack trace): o CLI ja imprimiu a mensagem ---
if ($cliExit -ne 0) {
    Write-Host "Falhou ao cadastrar o superusuario (codigo $cliExit)." -ForegroundColor Red
    exit $cliExit
}
Write-Host "Concluido." -ForegroundColor Green
