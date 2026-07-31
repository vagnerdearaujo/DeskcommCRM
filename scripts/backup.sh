#!/usr/bin/env bash
# =============================================================================
# backup.sh — Backup diário do DeskcommCRM (Linux/VPS)
# Equivalente shell do backup.ps1 (Windows).
#
# Uso:
#   ./scripts/backup.sh                     # backup único
#   ./scripts/backup.sh --keep-days 14      # retenção 14 dias
#
# Agendamento (cron):
#   # 2x/dia — 06:00 e 19:00
#   0 6 * * * /opt/deskcommcrm/scripts/backup.sh
#   0 19 * * * /opt/deskcommcrm/scripts/backup.sh
# =============================================================================
set -euo pipefail

KEEP_DAYS="${1:-7}"
BACKUP_ROOT="${BACKUP_ROOT:-./data/backups}"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATE_STAMP=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)

cd "$PROJECT_ROOT"

# Resolve BACKUP_ROOT absoluto
case "$BACKUP_ROOT" in
  /*) ;;
  *)  BACKUP_ROOT="$PROJECT_ROOT/$BACKUP_ROOT" ;;
esac

DAILY_DIR="$BACKUP_ROOT/$DATE_STAMP"
mkdir -p "$DAILY_DIR"

log()  { echo "[bkup] $*"; }
warn() { echo "[bkup] ⚠ $*" >&2; }

log "Backup $DATE_STAMP — destino: $DAILY_DIR"

# ── 1. Supabase: pg_dump ───────────────────────────────────
log "1/4 — Dump do Supabase (pg_dump)..."
DUMP_FILE="supabase_${TIMESTAMP}.dump"
if docker exec supabase_db_deskcomm-crm pg_dump -U postgres -d postgres \
  --format=custom --compress=9 --file="/tmp/$DUMP_FILE" 2>/dev/null; then
  docker cp "supabase_db_deskcomm-crm:/tmp/$DUMP_FILE" "$DAILY_DIR/$DUMP_FILE" 2>/dev/null
  docker exec supabase_db_deskcomm-crm rm "/tmp/$DUMP_FILE" 2>/dev/null
  log "  ✓ $DUMP_FILE"
else
  warn "Falha no dump Supabase"
fi

# ── 2. WAHA sessions (docker pause + volumes-from) ─────────
log "2/4 — WAHA sessions..."
TAR_NAME="waha-sessions_${TIMESTAMP}.tar.gz"
docker pause deskcomm-waha 2>/dev/null || true
if docker run --rm --volumes-from deskcomm-waha \
  -v "$DAILY_DIR:/out" \
  alpine:3.18 tar czf "/out/$TAR_NAME" -C /app/.sessions . 2>/dev/null; then
  log "  ✓ $TAR_NAME"
else
  warn "Falha no backup WAHA sessions"
fi
docker unpause deskcomm-waha 2>/dev/null || true

# ── 3. WAHA media ──────────────────────────────────────────
log "3/4 — WAHA media..."
TAR_NAME="waha-media_${TIMESTAMP}.tar.gz"
if docker run --rm --volumes-from deskcomm-waha \
  -v "$DAILY_DIR:/out" \
  alpine:3.18 tar czf "/out/$TAR_NAME" -C /app/.media . 2>/dev/null; then
  SIZE=$(stat -c%s "$DAILY_DIR/$TAR_NAME" 2>/dev/null || echo 0)
  if [ "$SIZE" -gt 50 ]; then
    log "  ✓ $TAR_NAME ($(( SIZE / 1024 ))KB)"
  else
    log "  - media vazio ($SIZE bytes)"
  fi
else
  warn "Falha no backup WAHA media"
fi

# ── 4. Redis (SAVE + tar via docker exec) ──────────────────
log "4/4 — Redis..."
TAR_NAME="redis_${TIMESTAMP}.tar.gz"
if docker exec deskcomm-redis redis-cli SAVE 2>/dev/null; then
  docker exec deskcomm-redis tar czf "/tmp/$TAR_NAME" -C /data . 2>/dev/null
  docker cp "deskcomm-redis:/tmp/$TAR_NAME" "$DAILY_DIR/$TAR_NAME" 2>/dev/null
  docker exec deskcomm-redis rm "/tmp/$TAR_NAME" 2>/dev/null
  log "  ✓ $TAR_NAME"
else
  warn "Falha no backup Redis"
fi

# ── 5. Limpeza ─────────────────────────────────────────────
log "Limpeza — retendo $KEEP_DAYS dias..."
find "$BACKUP_ROOT" -maxdepth 1 -type d -name '????-??-??' | while IFS= read -r dir; do
  dir_date=$(basename "$dir")
  if [[ "$dir_date" < "$(date -d "$KEEP_DAYS days ago" +%Y-%m-%d)" ]]; then
    rm -rf "$dir"
    log "  - removido backup antigo: $dir_date"
  fi
done

log "✅ Backup $DATE_STAMP concluído em $DAILY_DIR"
