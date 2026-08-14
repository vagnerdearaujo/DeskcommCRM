# =============================================================================
# DeskcommStack.ps1 — exclusão mútua dos ambientes (regra: 1 stack por vez)
#
# USO:
#   powershell -ExecutionPolicy Bypass -File DeskcommStack.ps1 start-dev
#   powershell -ExecutionPolicy Bypass -File DeskcommStack.ps1 start-main
#   powershell -ExecutionPolicy Bypass -File DeskcommStack.ps1 stop
#   powershell -ExecutionPolicy Bypass -File DeskcommStack.ps1 status
#
# - start-dev : para MAIN (supabase + auxiliares) e sobe a stack DEV (portas 5442x)
# - start-main: para DEV e delega ao DeskcommStart.bat (canônico do main, porta 5432x)
# - stop      : deixa ambas dormentes (containers preservados, volumes intactos)
# - status    : o que está no ar + memória
# =============================================================================

param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('start-dev', 'start-main', 'stop', 'status')]
  [string]$Command
)

$ErrorActionPreference = 'Stop'
$repoDir = 'D:\qwenProjects\DeskcommCRM'
$devDir  = 'C:\Users\vagne\.qwen\supabase-dev\deskcommcrm'

function Get-StackUp([string]$exactName) {
  return docker ps --filter "name=^/$exactName$" --format "{{.Names}}"
}

function Stop-MainStack {
  if (Get-StackUp 'supabase_db_deskcomm-crm') {
    Write-Host "[main] parando Supabase (dormente)..."
    Push-Location $repoDir
    supabase stop
    Pop-Location
  }
  if (docker ps --filter "name=deskcomm-" --format "{{.Names}}") {
    Write-Host "[main] parando servicos auxiliares (WAHA/Redis/SRH/Worker)..."
    Push-Location $repoDir
    docker compose --env-file .env.local stop
    Pop-Location
  }
}

function Stop-DevStack {
  if (Get-StackUp 'supabase_db_deskcomm-crm-dev') {
    Write-Host "[dev] parando Supabase (dormente)..."
    Push-Location $devDir
    supabase stop
    Pop-Location
  }
}

function Start-Dev {
  Stop-MainStack
  Write-Host "[dev] subindo stack DEV (API :54421, Studio :54423)..."
  Push-Location $devDir
  supabase start
  Pop-Location
  Write-Host "DEV no ar. App de testes: pnpm dev com .env apontando p/ 54421."
}

function Start-Main {
  Stop-DevStack
  Write-Host "[main] subindo ambiente MAIN via DeskcommStart.bat..."
  Push-Location $repoDir
  cmd /c DeskcommStart.bat
  Pop-Location
}

function Show-Status {
  $all = docker ps --filter "name=supabase_db_" --filter "name=deskcomm-" --format "{{.Names}}"
  if ($all) {
    Write-Host "=== Containers ativos ==="
    docker stats --no-stream --format "{{.Name}}  {{.MemUsage}}"
  } else {
    Write-Host "Nenhum container do projeto ativo (tudo dormente)."
  }
  if (Get-StackUp 'supabase_db_deskcomm-crm') { Write-Host "-> Stack MAIN: ATIVA" } else { Write-Host "-> Stack MAIN: dormente" }
  if (Get-StackUp 'supabase_db_deskcomm-crm-dev') { Write-Host "-> Stack DEV:  ATIVA" } else { Write-Host "-> Stack DEV:  dormente" }
}

switch ($Command) {
  'start-dev'  { Start-Dev }
  'start-main' { Start-Main }
  'stop'       { Stop-MainStack; Stop-DevStack; Write-Host "Ambas dormentes." }
  'status'     { Show-Status }
}
