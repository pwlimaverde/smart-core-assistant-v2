<#
.SYNOPSIS
  Instala a continuidade após limite na máquina Windows (usuário atual).

.DESCRIPTION
  1. Valida o script (py_compile + --status + --verificar --seco).
  2. Registra os ganchos em smart-agent-config/.claude/settings.local.json
     (com backup ao lado do arquivo).
  3. Cria a tarefa "SmartCore\RoteadorContinuidade" no Agendador de Tarefas:
     a cada 15 min e no logon, com pyw (sem janela), sem instâncias
     simultâneas e executando assim que possível se um horário foi perdido.
  Idempotente. -SoValidar para só validar; -Remover para tirar a tarefa.
#>
param(
    [switch]$SoValidar,
    [switch]$Remover
)
$ErrorActionPreference = 'Stop'

$raiz = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path   # smart-agent-config
$script = Join-Path $raiz '.claude\hooks\continuidade.py'
$settings = Join-Path $raiz '.claude\settings.local.json'
$pastaTarefa = '\SmartCore\'
$nomeTarefa = 'RoteadorContinuidade'

if ($Remover) {
    Unregister-ScheduledTask -TaskPath $pastaTarefa -TaskName $nomeTarefa -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host 'tarefa removida (os ganchos continuam; sem o timer eles só registram e avisam).'
    return
}

if (-not (Test-Path $script)) { throw "faltando $script (atualize o checkout)" }

Write-Host '== validação (py_compile + leitura)'
& py -3 -m py_compile $script (Join-Path $raiz '.claude\hooks\roteador.py')
if ($LASTEXITCODE -ne 0) { throw 'py_compile falhou' }
& py -3 $script --status
& py -3 $script --verificar --seco
if ($SoValidar) { return }

Write-Host "== ganchos em $settings"
& py -3 $script --registrar-hooks $settings
if ($LASTEXITCODE -ne 0) { throw 'registro dos ganchos falhou' }
Get-Content $settings -Raw | ConvertFrom-Json | Out-Null   # JSON válido

Write-Host '== tarefa agendada'
$pyw = (Get-Command pyw.exe -ErrorAction Stop).Source
$acao = New-ScheduledTaskAction -Execute $pyw -Argument "-3 `"$script`" --verificar" -WorkingDirectory $env:USERPROFILE
$repetir = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Minutes 15)
$logon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$config = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 5)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskPath $pastaTarefa -TaskName $nomeTarefa -Action $acao `
    -Trigger @($repetir, $logon) -Settings $config -Principal $principal -Force `
    -Description 'Retoma sessões do Claude Code paradas por limite de uso (smart-agent-config).' | Out-Null
Get-ScheduledTask -TaskPath $pastaTarefa -TaskName $nomeTarefa | Get-ScheduledTaskInfo |
    Select-Object LastRunTime, NextRunTime | Format-List
Write-Host "ok. Estado: py -3 `"$script`" --status"
