# ============================================
# Testes Locais (pre-push) - Smart Core Assistant v2
# ============================================
# Roda a MESMA esteira do CI localmente, mas com a suite COMPLETA
# (unit + integracao), conectando aos bancos remotos da Hostinger
# atraves do tunel SSH (aberto automaticamente pelo test_support).
#
# Topologia do tunel (local -> Hostinger):
#   localhost:5434 -> Postgres   (porta host remota: POSTGRES_PORT)
#   localhost:6379 -> Redis Cache (porta host remota: REDIS_PORT,     allkeys-lru)
#   localhost:6380 -> Redis Bus   (porta host remota: REDIS_BUS_PORT, noeviction)
#
# Uso (a partir da pasta infra/ ou da raiz):
#   .\infra\test-local.ps1                 # esteira completa
#   .\infra\test-local.ps1 -Fast           # so fmt + clippy + testes unitarios (sem banco)
#   .\infra\test-local.ps1 -ResetTunnel    # derruba tuneis ssh antigos antes (use apos
#                                          # mudancas de mapeamento de portas)
#
# Pre-requisitos:
#   - infra/.env.deploy com as credenciais SSH (chave id_hostinger_root)
#   - server/.env com DATABASE_URL/REDIS_URL/REDIS_BUS_URL apontando para as
#     portas locais do tunel (5434/6379/6380)
# ============================================

param(
    [switch]$Fast,
    [switch]$ResetTunnel
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

# Resolve a raiz do repo a partir da localizacao do script (infra/..)
$repoRoot = Split-Path -Parent $PSScriptRoot
$serverDir = Join-Path $repoRoot "server"

function Write-Etapa([string]$msg) {
    Write-Host ""
    Write-Host "== $msg ==" -ForegroundColor Cyan
}

# --------------------------------------------
# 0. Tunel: reset opcional (mapeamentos antigos de porta enganam os testes,
#    pois o test_support so verifica se a porta 5434 esta aberta)
# --------------------------------------------
if ($ResetTunnel) {
    Write-Etapa "Derrubando tuneis SSH antigos"
    Get-Process ssh -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $cmdline = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine
            # So mata processos ssh que carregam port-forwards dos nossos servicos
            if ($cmdline -match "5434:localhost|6379:localhost|6380:localhost") {
                Write-Host "  matando ssh PID $($_.Id)" -ForegroundColor Yellow
                Stop-Process -Id $_.Id -Force -Confirm:$false
            }
        } catch {}
    }
    Start-Sleep -Seconds 1
}

# --------------------------------------------
# 1. Validacao de pre-requisitos
# --------------------------------------------
Write-Etapa "Validando pre-requisitos"
if (-not (Test-Path (Join-Path $PSScriptRoot ".env.deploy"))) {
    Write-Host "Erro: infra/.env.deploy nao encontrado (necessario para o tunel SSH)." -ForegroundColor Red
    exit 1
}
if (-not $Fast -and -not (Test-Path (Join-Path $serverDir ".env"))) {
    Write-Host "Erro: server/.env nao encontrado (DATABASE_URL/REDIS_URL/REDIS_BUS_URL dos testes)." -ForegroundColor Red
    exit 1
}
Write-Host "ok" -ForegroundColor Green

# --- Carrega server/.env no ambiente do processo para os testes e sqlx herdarem as configuracoes ---
if (Test-Path (Join-Path $serverDir ".env")) {
    Get-Content (Join-Path $serverDir ".env") | ForEach-Object {
        if ($_ -match '^\s*([^#=][^=]*)=(.*)$') {
            $nome = $matches[1].Trim()
            $valor = $matches[2].Trim().Trim('"').Trim("'")
            [Environment]::SetEnvironmentVariable($nome, $valor, "Process")
        }
    }
}

$databaseUrl = [Environment]::GetEnvironmentVariable("DATABASE_URL", "Process")
$databaseAdminUrl = [Environment]::GetEnvironmentVariable("DATABASE_ADMIN_URL", "Process")
$smartcoreEnv = [Environment]::GetEnvironmentVariable("SMARTCORE_ENV", "Process")

if ($smartcoreEnv -eq "dev") {
    # Roteia o banco de dados na URL para smartcore_v2_dev
    if ($databaseUrl -and $databaseUrl -match '/smartcore_v2(?:\?|$)') {
        $databaseUrl = $databaseUrl -replace '/smartcore_v2(?:\?|$)', '/smartcore_v2_dev'
        [Environment]::SetEnvironmentVariable("DATABASE_URL", $databaseUrl, "Process")
    }
    if ($databaseAdminUrl -and $databaseAdminUrl -match '/smartcore_v2(?:\?|$)') {
        $databaseAdminUrl = $databaseAdminUrl -replace '/smartcore_v2(?:\?|$)', '/smartcore_v2_dev'
        [Environment]::SetEnvironmentVariable("DATABASE_ADMIN_URL", $databaseAdminUrl, "Process")
    }
    Write-Host "Roteando testes para o ambiente de DESENVOLVIMENTO remoto (banco: smartcore_v2_dev)" -ForegroundColor Yellow
} elseif ($smartcoreEnv -eq "prod") {
    Write-Host "Roteando testes para o ambiente de PRODUCAO remoto (banco: smartcore_v2)" -ForegroundColor Red
} else {
    Write-Host "Roteando testes para o ambiente LOCAL/TESTE" -ForegroundColor Green
}

$falhas = @()

# --------------------------------------------
# 2. cargo fmt --check (mesmo gate do CI)
# --------------------------------------------
Write-Etapa "cargo fmt --check"
Push-Location $serverDir
try {
    cargo fmt --all -- --check
    if ($LASTEXITCODE -ne 0) { $falhas += "fmt" } else { Write-Host "ok" -ForegroundColor Green }

    # --------------------------------------------
    # 3. cargo clippy (mesmo gate do CI)
    # --------------------------------------------
    Write-Etapa "cargo clippy --all-targets --all-features -- -D warnings"
    $env:SQLX_OFFLINE = "true"
    cargo clippy --all-targets --all-features -- -D warnings
    if ($LASTEXITCODE -ne 0) { $falhas += "clippy" } else { Write-Host "ok" -ForegroundColor Green }

    # --------------------------------------------
    # 4. Testes
    #    -Fast : so unit/lib (sem banco, igual ao CI)
    #    padrao: suite COMPLETA (unit + integracao) - o test_support abre o
    #            tunel SSH sozinho na primeira suite que precisar do banco
    # --------------------------------------------
    if ($Fast) {
        Write-Etapa "cargo test --workspace --lib --bins (modo rapido, sem banco)"
        # Serializa threads para evitar exaustao de conexoes ao banco (ver ci.yml)
        $env:RUST_TEST_THREADS = "1"
        cargo test --workspace --lib --bins -- --test-threads=1
    } else {
        Write-Etapa "cargo test --workspace (suite completa: unit + integracao via tunel)"
        # RUST_TEST_THREADS=1 serializa testes dentro de cada binario; --test-threads=1
        # serializa entre binarios. Obrigatorio: testes de banco compartilham o mesmo
        # Postgres e cada setup_teste() abre pool proprio — paralelo esgota max_connections.
        # Alem disso, o teste test_audit_log_rls_isolation_enforced exige que DATABASE_URL
        # aponte para a role smartcore_app (NOBYPASSRLS), nao para o superuser postgres.
        # Se DATABASE_URL usar superuser, o teste falha com "VULNERABILIDADE: Tenant B...".
        # Ver .github/workflows/ci.yml step "Bootstrap do banco de teste" para criar o role.
        $env:RUST_TEST_THREADS = "1"
        cargo test --workspace -- --test-threads=1
    }
    if ($LASTEXITCODE -ne 0) { $falhas += "test" } else { Write-Host "ok" -ForegroundColor Green }

    # --------------------------------------------
    # 5. cargo sqlx prepare --check (drift do cache .sqlx/, mesmo gate do CI)
    #    Requer o tunel aberto (a suite completa ja o abriu). Pulado no -Fast.
    # --------------------------------------------
    if (-not $Fast) {
        Write-Etapa "cargo sqlx prepare --workspace --check"
        if (Get-Command cargo-sqlx -ErrorAction SilentlyContinue) {
            # Conecta no banco remoto via tunel para revalidar as queries
            $dbAdmin = [Environment]::GetEnvironmentVariable("DATABASE_ADMIN_URL", "Process")
            if ($dbAdmin) {
                $env:DATABASE_URL = $dbAdmin
            }
            cargo sqlx prepare --workspace --check
            if ($LASTEXITCODE -ne 0) { $falhas += "sqlx-prepare" } else { Write-Host "ok" -ForegroundColor Green }
        } else {
            Write-Host "sqlx-cli nao instalado - pulando (instale com: cargo install sqlx-cli --no-default-features --features postgres)" -ForegroundColor Yellow
        }
    }
} finally {
    Pop-Location
}

# --------------------------------------------
# Resumo
# --------------------------------------------
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
if ($falhas.Count -eq 0) {
    Write-Host "  TUDO VERDE - pode dar push." -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Cyan
    exit 0
} else {
    Write-Host "  FALHAS: $($falhas -join ', ')" -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Cyan
    exit 1
}
