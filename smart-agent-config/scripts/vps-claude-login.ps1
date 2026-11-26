<#
.SYNOPSIS
  Faz o login do Claude Code na estação do VPS sem precisar de screen nem de SSH interativo.

.DESCRIPTION
  O login roda `claude auth login --claudeai` no servidor, com a entrada (stdin) vinda de um FIFO.
  Fluxo:
    1. start:  sobe o processo de login no servidor e imprime a URL de autorização.
    2. (você)  abre a URL no navegador, entra na conta Anthropic e copia o código XXX#YYY.
    3. finish: recebe o código, entrega ao login, espera o término e confere `claude auth status`.

  Sem -Phase, executa as três etapas em sequência e pede o código no próprio terminal.
  Use -Phase start e -Phase finish separadamente quando o código só chegar depois
  (o processo de login fica vivo no servidor por até 30 minutos).

.PARAMETER HostAlias
  Alias SSH do servidor. Padrão: hostinger-root.

.PARAMETER Phase
  all (padrão), start ou finish.

.PARAMETER Code
  Código de autorização. Se omitido na fase finish, é pedido no terminal.
  Evite passar pela linha de comando: o código fica no histórico do shell.

.EXAMPLE
  .\scripts\vps-claude-login.ps1

.EXAMPLE
  .\scripts\vps-claude-login.ps1 -Phase start
  .\scripts\vps-claude-login.ps1 -Phase finish
#>
param(
  [string]$HostAlias = 'hostinger-root',
  [ValidateSet('all', 'start', 'finish')]
  [string]$Phase = 'all',
  [string]$Code
)

# Script executado no servidor (bash). Recebe o argumento `start` ou `finish`.
# Na fase finish, o código de autorização é lido do stdin (que vem do ssh).
# Mantido como texto literal para não passar por expansão do PowerShell.
$remoto = @'
#!/usr/bin/env bash
# Login do Claude Code no servidor, em duas fases. Executado como: bash script start|finish
set -u

DIR=/run/claude-login
CLAUDE=/root/.local/bin/claude
REPO=/opt/smartcore/ops/smart-core-assistant-v2/smart-agent-config

limpa_sujeira() {
  for f in "$DIR"/*.pid; do
    [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null
  done
  rm -rf "$DIR"
}

fase_start() {
  limpa_sujeira
  mkdir -p "$DIR" || { echo "ERRO: não criou $DIR"; exit 1; }
  mkfifo "$DIR/in" || { echo "ERRO: não criou o FIFO"; exit 1; }

  # Mantém o FIFO com escritor aberto. Sem isso o login lê EOF antes do código.
  # Os redirecionamentos evitam que o ssh fique preso esperando esse processo.
  sleep 1800 >"$DIR/in" 2>/dev/null </dev/null &
  echo $! > "$DIR/holder.pid"

  (cd "$REPO" && exec "$CLAUDE" auth login --claudeai <"$DIR/in" >"$DIR/out" 2>&1) </dev/null &
  echo $! > "$DIR/login.pid"

  # Espera a URL aparecer na saída do login (até 30 s).
  for _ in $(seq 1 30); do
    url=$(sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "$DIR/out" 2>/dev/null \
          | grep -a -o 'https://[^ ]*oauth/authorize[^ ]*' | head -n 1)
    if [ -n "$url" ]; then
      echo "URL:$url"
      exit 0
    fi
    sleep 1
  done
  echo "ERRO: a URL de login não apareceu. Saída:"
  sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "$DIR/out" 2>/dev/null
  limpa_sujeira
  exit 1
}

fase_finish() {
  if [ ! -f "$DIR/login.pid" ]; then
    echo "ERRO: login não foi iniciado. Rode a fase start antes."
    exit 1
  fi
  pid=$(cat "$DIR/login.pid")

  # Código vem do stdin do ssh (uma linha).
  IFS= read -r -t 120 codigo
  codigo=$(printf '%s' "$codigo" | tr -d '\r' | sed 's/^ *//; s/ *$//')
  if [ -z "$codigo" ]; then
    echo "ERRO: código vazio."
    limpa_sujeira
    exit 1
  fi

  # Entrega o código ao login só se ele ainda estiver vivo.
  # Sem leitor no FIFO, a escrita bloquearia; por isso o timeout.
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "ERRO: o processo de login já tinha encerrado. Rode a fase start de novo."
    limpa_sujeira
    exit 1
  fi
  if ! timeout 10 bash -c 'printf "%s\n" "$1" > "$2"' _ "$codigo" "$DIR/in"; then
    echo "ERRO: não consegui entregar o código ao login."
    limpa_sujeira
    exit 1
  fi

  # Espera o processo de login terminar (até 60 s).
  for _ in $(seq 1 60); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "$pid" 2>/dev/null; then
    echo "ERRO: o login não terminou em 60 s. Saída:"
    sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "$DIR/out" 2>/dev/null | tail -n 15
    limpa_sujeira
    exit 1
  fi

  # O resultado vem da saída do próprio login. O auth status sozinho não serve:
  # uma sessão antiga ainda válida faria um código recusado parecer sucesso.
  saida_login=$(sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "$DIR/out" 2>/dev/null)
  echo "SAIDA_LOGIN:"
  printf '%s\n' "$saida_login" | tail -n 15
  if printf '%s' "$saida_login" | grep -qi -E 'failed|invalid|error|wasn.t accepted'; then
    echo "RESULTADO:falha"
  elif printf '%s' "$saida_login" | grep -qi -E 'successful|logged in'; then
    echo "RESULTADO:ok"
  else
    echo "RESULTADO:indefinido"
  fi
  echo "STATUS:$(cd "$REPO" && "$CLAUDE" auth status --json 2>/dev/null | tr -d '\n')"
  limpa_sujeira
}

case "${1:-}" in
  start)  fase_start ;;
  finish) fase_finish ;;
  *) echo "uso: script start|finish"; exit 2 ;;
esac
'@ -replace "`r", ''

# Envia o script ao servidor como base64 dentro do próprio comando ssh e executa a fase pedida.
# O stdin do ssh segue livre para o código (fase finish). Não depende de quebra de linha no pipe.
function Invoke-Remoto([string]$Fase, [string]$Entrada = '') {
  $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoto))
  $comando = "echo '$b64' | base64 -d > /run/vps-claude-login.sh && bash /run/vps-claude-login.sh $Fase"
  if ($Entrada) {
    return ($Entrada | ssh $HostAlias $comando 2>&1)
  }
  return ($null | ssh $HostAlias $comando 2>&1)
}

if ($Phase -in 'all', 'start') {
  Write-Host "Iniciando o login no servidor ($HostAlias)..." -ForegroundColor Cyan
  $saida = Invoke-Remoto 'start'
  $linhaUrl = $saida | Where-Object { "$_" -like 'URL:*' } | Select-Object -First 1
  if (-not $linhaUrl) {
    $saida | ForEach-Object { Write-Host "$_" }
    throw 'Falha ao iniciar o login no servidor.'
  }
  $url = ("$linhaUrl").Substring(4)
  Write-Host ''
  Write-Host 'Abra este link no navegador, entre na conta Anthropic e copie o código (XXX#YYY):' -ForegroundColor Yellow
  Write-Host $url
  Write-Host ''
}

if ($Phase -in 'all', 'finish') {
  if (-not $Code) {
    $Code = Read-Host 'Cole o código de autorização'
  }
  $Code = $Code.Trim()
  if (-not $Code) { throw 'Código vazio.' }

  Write-Host 'Enviando o código e aguardando o servidor confirmar...' -ForegroundColor Cyan
  $saida = Invoke-Remoto 'finish' $Code
  $saida | ForEach-Object { Write-Host "$_" }

  $resultado = $saida | Where-Object { "$_" -like 'RESULTADO:*' } | Select-Object -First 1
  $linhaStatus = $saida | Where-Object { "$_" -like 'STATUS:*' } | Select-Object -First 1
  $email = if ("$linhaStatus" -match '"email":\s*"([^"]+)"') { $Matches[1] } else { '?' }
  if ("$resultado" -eq 'RESULTADO:ok' -and "$linhaStatus" -match '"loggedIn":\s*true') {
    Write-Host "Login concluído: conta $email." -ForegroundColor Green
  } else {
    throw "Login NÃO confirmado ($resultado). Veja a saída acima."
  }
}
