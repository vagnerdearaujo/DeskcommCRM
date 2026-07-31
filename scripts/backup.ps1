<#
.SYNOPSIS
  Backup diário do DeskcommCRM — Supabase + dados persistentes (WAHA, Redis).
.DESCRIPTION
  Gera dump do Postgres (via docker exec) + zip dos bind mounts em data/backups/.
  Projetado para execução via Agendador de Tarefas do Windows.
.PARAMETER KeepDays
  N° de dias para reter backups (padrão: 7).
.PARAMETER BackupRoot
  Diretório raiz de backup (padrão: .\data\backups).
#>

param(
  [int]$KeepDays = 7,
  [string]$BackupRoot = "data\backups"
)

$ErrorActionPreference = "Stop"
$DateStamp = Get-Date -Format "yyyy-MM-dd"
$Timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$BackupDir = Join-Path $ProjectRoot $BackupRoot

# ── Diretórios ──────────────────────────────────────────────
$DailyDir = Join-Path $BackupDir $DateStamp
$null = New-Item -ItemType Directory -Path $DailyDir -Force

Write-Host "[bkup] Backup diário $DateStamp — destino: $DailyDir"

# ── 1. Supabase: pg_dump ───────────────────────────────────
Write-Host "[bkup] 1/4 — Dump do Supabase (pg_dump)..."
try {
  $dumpFile = "supabase_$Timestamp.dump"
  docker exec supabase_db_deskcomm-crm pg_dump -U postgres -d postgres `
    --format=custom --compress=9 `
    --file="/tmp/$dumpFile" 2>$null
  docker cp "supabase_db_deskcomm-crm:/tmp/$dumpFile" (Join-Path $DailyDir $dumpFile) 2>$null
  docker exec supabase_db_deskcomm-crm rm "/tmp/$dumpFile" 2>$null
  Write-Host "[bkup]   ✓ $dumpFile"
} catch {
  Write-Warning "[bkup]   ✗ Falha no dump Supabase: $_"
}

# ── 2+3. WAHA (docker pause + volumes-from p/ consistência) ─
Write-Host "[bkup] 2/4 — WAHA sessions..."
try {
  $tarName = "waha-sessions_$Timestamp.tar.gz"
  $dst = Join-Path $DailyDir $tarName
  docker pause deskcomm-waha 2>$null
  try {
    # --volumes-from lê os bind mounts do WAHA sem precisar de exec
    docker run --rm --volumes-from deskcomm-waha `
      -v "$($DailyDir):/out" `
      alpine:3.18 tar czf "/out/$tarName" -C /app/.sessions . 2>$null
  } finally {
    docker unpause deskcomm-waha 2>$null
  }
  Write-Host "[bkup]   ✓ $tarName"
} catch {
  Write-Warning "[bkup]   ✗ Falha no backup WAHA sessions: $_"
  docker unpause deskcomm-waha 2>$null
}

Write-Host "[bkup] 3/4 — WAHA media..."
try {
  $tarName = "waha-media_$Timestamp.tar.gz"
  $dst = Join-Path $DailyDir $tarName
  docker run --rm --volumes-from deskcomm-waha `
    -v "$($DailyDir):/out" `
    alpine:3.18 tar czf "/out/$tarName" -C /app/.media . 2>$null
  $size = (Get-Item $dst).Length
  if ($size -gt 50) {
    Write-Host "[bkup]   ✓ $tarName ($([math]::Round($size/1KB))KB)"
  } else {
    Write-Host "[bkup]   - media vazio ($size bytes)"
  }
} catch {
  Write-Warning "[bkup]   ✗ Falha no backup WAHA media: $_"
}

# ── 4. Redis (SAVE + tar via docker exec) ──────────────────
Write-Host "[bkup] 4/4 — Redis..."
try {
  docker exec deskcomm-redis redis-cli SAVE 2>$null
  $tarName = "redis_$Timestamp.tar.gz"
  $dst = Join-Path $DailyDir $tarName
  docker exec deskcomm-redis tar czf "/tmp/$tarName" -C /data . 2>$null
  docker cp "deskcomm-redis:/tmp/$tarName" $dst 2>$null
  docker exec deskcomm-redis rm "/tmp/$tarName" 2>$null
  Write-Host "[bkup]   ✓ $tarName"
} catch {
  Write-Warning "[bkup]   ✗ Falha no backup Redis: $_"
}

# ── 5. Limpeza de backups antigos ──────────────────────────
Write-Host "[bkup] Limpeza — retendo $KeepDays dias..."
try {
  $cutoff = (Get-Date).AddDays(-$KeepDays)
  Get-ChildItem $BackupDir -Directory |
    Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and $_.LastWriteTime -lt $cutoff } |
    ForEach-Object {
      Remove-Item $_.FullName -Recurse -Force
      Write-Host "[bkup]   - removido backup antigo: $($_.Name)"
    }
} catch {
  Write-Warning "[bkup]   ✗ Falha na limpeza: $_"
}

Write-Host "[bkup] ✅ Backup $DateStamp concluído em $DailyDir"
