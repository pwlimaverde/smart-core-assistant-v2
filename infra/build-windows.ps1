# ============================================
# Build do cliente Windows (Flutter desktop)
# Smart Core Assistant v2
# ============================================
# Existe porque este artefato NÃO é construído por nenhum workflow de deploy —
# o `deploy-dev.yml` produz as imagens Docker das versões WEB. O `.zip` do
# desktop sempre foi feito à mão, e em 12/09/2026 isso custou uma sessão inteira
# de confusão: o zip marcava a data de um build antigo e ninguém notou que
# "refiz o build" tinha refeito só a web.
#
# O que este script resolve, além de digitar menos:
#
#   1. Fixa o entrypoint e os `--dart-define` por ambiente. Esquecer um define
#      NÃO dá erro: `main_dev.dart` cai no default `tcp://localhost:50051` e
#      gera um app que abre, não conecta, e não diz por quê.
#   2. **Confere no binário** que os endereços entraram. É a única prova real —
#      os defines viram constantes dentro do snapshot AOT (`data/app.so`), e sem
#      olhar lá dentro o build "bem-sucedido" pode estar apontando para o lugar
#      errado.
#   3. Empacota com o nome que o time já usa.
#
# Uso (a partir da raiz ou de infra/):
#   .\infra\build-windows.ps1                 # tenant, dev
#   .\infra\build-windows.ps1 -Env prod
#   .\infra\build-windows.ps1 -App admin
#   .\infra\build-windows.ps1 -LimparCache    # apaga build/windows antes
#
# ⚠️ `-LimparCache` é necessário depois de trocar/reinstalar o Visual Studio: o
# CMake guarda o caminho da instalação em `CMAKE_GENERATOR_INSTANCE` e falha com
# "could not find specified instance of Visual Studio" quando aquele caminho
# deixa de existir (foi o que aconteceu ao migrar de `18/Community` para
# `18/Insiders`).
# ============================================

[CmdletBinding()]
param(
    [ValidateSet("dev", "prod")]
    [string]$Env = "dev",

    [ValidateSet("tenant", "admin")]
    [string]$App = "tenant",

    [switch]$LimparCache
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Etapa($msg) { Write-Host "`n== $msg ==" -ForegroundColor Cyan }

$repoRoot = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $repoRoot "clients\apps\smart-core-$App"
$saidaDir = Join-Path $repoRoot "clients\build"

if (-not (Test-Path $appDir)) {
    Write-Host "Erro: $appDir nao encontrado." -ForegroundColor Red
    exit 1
}

# --------------------------------------------
# Endereços por ambiente.
#
# O MCP precisa casar com o ambiente: a descoberta OAuth de cada um declara o
# `resource` com o próprio domínio, e um cliente que valide o casamento recusa a
# conexão quando o endereço colado não é o mesmo. Os dois domínios respondem —
# por isso a divergência não aparece num teste superficial.
# --------------------------------------------
$config = @{
    dev  = @{
        api = "https://dev.smartcoreassistant.com.br"
        mcp = "https://mcp.dev.smartcoreassistant.com.br/mcp"
        # COM o caminho base: o app e servido sob /v2/tenant/, e o dominio
        # sozinho devolve HTTP 400. E a base dos links que saem do app (hoje o
        # convite) — nao confundir com `api`, que atende na raiz.
        app = "https://dev.smartcoreassistant.com.br/v2/tenant"
    }
    # Produção atende no ápice do domínio (`docker/edge/Caddyfile`), não num
    # subdomínio `app.` — que não existe.
    prod = @{
        api = "https://smartcoreassistant.com.br"
        mcp = "https://mcp.smartcoreassistant.com.br/mcp"
        app = "https://smartcoreassistant.com.br/v2/tenant"
    }
}
$api = $config[$Env].api
$mcp = $config[$Env].mcp
$app = $config[$Env].app
$zip = Join-Path $saidaDir "smart-core-$App-windows-$Env.zip"

Write-Host "app=$App  ambiente=$Env" -ForegroundColor Green
Write-Host "  API = $api"
Write-Host "  MCP = $mcp"
Write-Host "  APP = $app"

Push-Location $appDir
try {
    if ($LimparCache) {
        Write-Etapa "Limpando build\windows (cache do CMake)"
        $bw = Join-Path $appDir "build\windows"
        if (Test-Path $bw) { Remove-Item $bw -Recurse -Force }
        Write-Host "ok"
    }

    Write-Etapa "flutter build windows --release"
    & flutter build windows --release `
        --target "lib/main_$Env.dart" `
        --dart-define=SMARTCORE_API_ENDPOINT=$api `
        --dart-define=SMARTCORE_MCP_ENDPOINT=$mcp `
        --dart-define=SMARTCORE_APP_PUBLIC_URL=$app
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`nBuild falhou." -ForegroundColor Red
        Write-Host "Se o erro citar 'could not find specified instance of Visual Studio', rode de novo com -LimparCache." -ForegroundColor Yellow
        exit 1
    }

    $release = Join-Path $appDir "build\windows\x64\runner\Release"

    # --------------------------------------------
    # A verificação que dá sentido ao script.
    #
    # Um `--dart-define` esquecido não falha o build: gera um app que aponta para
    # outro lugar. A prova é procurar a string dentro do snapshot AOT.
    # --------------------------------------------
    Write-Etapa "Conferindo os endereços dentro do binário"
    $snap = Join-Path $release "data\app.so"
    if (-not (Test-Path $snap)) {
        Write-Host "Erro: snapshot $snap nao encontrado — build incompleto." -ForegroundColor Red
        exit 1
    }
    $texto = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($snap))

    $falhas = @()
    foreach ($esperado in @($api, $mcp, $app)) {
        if ($texto.Contains($esperado)) {
            Write-Host "  ok      $esperado" -ForegroundColor Green
        } else {
            Write-Host "  AUSENTE $esperado" -ForegroundColor Red
            $falhas += $esperado
        }
    }

    # E o inverso: o endereço do OUTRO ambiente não pode ter vazado para dentro.
    # Pega o caso em que o define foi ignorado e o default do `main_` assumiu.
    $outro = if ($Env -eq "dev") { "prod" } else { "dev" }
    foreach ($indevido in @($config[$outro].api, $config[$outro].mcp, $config[$outro].app)) {
        if ($texto.Contains($indevido)) {
            Write-Host "  VAZOU   $indevido (endereço de $outro)" -ForegroundColor Red
            $falhas += $indevido
        }
    }

    if ($falhas.Count -gt 0) {
        Write-Host "`nOs endereços do binário nao conferem — NAO publique este zip." -ForegroundColor Red
        exit 1
    }

    Write-Etapa "Empacotando"
    if (-not (Test-Path $saidaDir)) { New-Item -ItemType Directory -Force $saidaDir | Out-Null }
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path (Join-Path $release "*") -DestinationPath $zip -CompressionLevel Optimal

    $i = Get-Item $zip
    Write-Host ("`n{0}" -f $i.FullName) -ForegroundColor Green
    Write-Host ("{0} MB · {1}" -f [math]::Round($i.Length / 1MB, 1), $i.LastWriteTime)
}
finally {
    Pop-Location
}
