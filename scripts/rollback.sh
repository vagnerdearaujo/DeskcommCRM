#!/usr/bin/env bash
# =============================================================================
# rollback.sh — Rollback de dados e/ou aplicação DeskcommCRM
#
# Uso:
#   ./scripts/rollback.sh --help                     Mostra ajuda
#   ./scripts/rollback.sh --db [--date YYYY-MM-DD]   Restaura DB do backup
#   ./scripts/rollback.sh --app                      Reverte docker-compose ao git anterior
#   ./scripts/rollback.sh --full [--date YYYY-MM-DD] DB + app
#
# Requer: docker, pg_restore, git
# =============================================================================
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_ROOT="${BACKUP_ROOT:-./data/backups}"
COMPOSE_FILES=("docker-compose.yml" "docker-compose.override.yml" "docker-compose.prod.yml")

cd "$PROJECT_ROOT"

# Resolve BACKUP_ROOT absoluto
case "$BACKUP_ROOT" in
  /*) ;;
  *)  BACKUP_ROOT="$PROJECT_ROOT/$BACKUP_ROOT" ;;
esac

help() {
  sed -n 's/^# \?//p' "$0" | sed '1,2d'  # extrai cabeçalho de uso
  exit 0
}

find_latest_backup() {
  local latest
  latest=$(find "$BACKUP_ROOT" -maxdepth 2 -name "supabase_*.dump" -type f 2>/dev/null | sort | tail -1)
  if [ -z "$latest" ]; then
    echo "Nenhum backup encontrado em $BACKUP_ROOT" >&2
    exit 1
  fi
  echo "$latest"
}

# ── DB Rollback ─────────────────────────────────────────────
rollback_db() {
  local date_filter="$1"
  local dump_file

  if [ -n "$date_filter" ]; then
    dump_file=$(find "$BACKUP_ROOT/$date_filter" -name "supabase_*.dump" -type f 2>/dev/null | sort | tail -1 || true)
    if [ -z "$dump_file" ]; then
      echo "Nenhum backup para a data $date_filter" >&2
      exit 1
    fi
  else
    dump_file=$(find_latest_backup)
  fi

  echo "=== Rollback DB a partir de: $dump_file ==="

  # 1. Validar integridade do dump
  echo "[1/3] Validando dump..."
  if ! pg_restore --list "$dump_file" >/dev/null 2>&1; then
    echo "ERRO: Dump corrompido ou inválido" >&2
    exit 1
  fi

  # 2. Parar app (evita escritas concorrentes)
  echo "[2/3] Parando serviços que acessam o DB..."
  docker compose --env-file .env.prod down --timeout 30 2>/dev/null || true
  docker compose --env-file .env.local down --timeout 30 2>/dev/null || true
  docker stop deskcomm-srh deskcomm-worker 2>/dev/null || true

  # 3. Restaurar
  echo "[3/3] Restaurando DB..."
  local container="supabase_db_deskcomm-crm"
  local tmp_dump="/tmp/rollback_$$.dump"

  docker cp "$dump_file" "$container:$tmp_dump"

  # Drop & recreate + restore
  docker exec "$container" psql -U postgres -d postgres \
    -c "DROP OWNED BY current_user CASCADE;" 2>/dev/null || true
  docker exec "$container" pg_restore -U postgres -d postgres --clean --if-exists "$tmp_dump"
  docker exec "$container" rm "$tmp_dump"

  echo "✅ DB rollback concluído. Reinicie os serviços:"
  echo "   docker compose --env-file .env.prod up -d"
  echo "   # ou: docker compose --env-file .env.local up -d"
}

# ── App Rollback ────────────────────────────────────────────
rollback_app() {
  echo "=== Rollback App — revertendo compose ao commit anterior ==="

  # 1. Verificar se há commit anterior
  local parent
  parent=$(git log --oneline -2 -- "${COMPOSE_FILES[@]}" 2>/dev/null | tail -1 | awk '{print $1}' || true)
  if [ -z "$parent" ]; then
    echo "Nenhum commit anterior dos composes encontrado para reverter" >&2
    echo "Dica: o rollback app só funciona se os composes foram commitados" >&2
    exit 1
  fi

  # 2. Restaurar composes do commit anterior
  echo "[1/3] Revertendo arquivos docker-compose ao commit $parent..."
  for f in "${COMPOSE_FILES[@]}"; do
    if git show "$parent:$f" >/dev/null 2>&1; then
      git show "$parent:$f" > "$PROJECT_ROOT/$f"
      echo "  - $f restaurado"
    fi
  done

  # 3. Verificar diff (warning)
  echo "[2/3] Diferenças entre versão anterior e atual:"
  git diff --stat -- "${COMPOSE_FILES[@]}" 2>/dev/null || true

  # 4. Restart
  echo "[3/3] Re-subindo containers com composes revertidos..."
  if [ -f "$PROJECT_ROOT/.env.prod" ]; then
    docker compose -f docker-compose.yml -f docker-compose.prod.yml --env-file .env.prod up -d
  else
    docker compose --env-file .env.local up -d
  fi

  echo "✅ App rollback concluído. Containers reiniciados com composes do commit $parent."
  echo ""
  echo "⚠ Importante:"

  for f in "${COMPOSE_FILES[@]}"; do
    echo "  git add $f && git commit -m \"rollback: $f ao estado do commit $parent\""
  done
}

# ── Main ────────────────────────────────────────────────────
MODE="${1:-}"
DATE_ARG=""

case "$MODE" in
  --help|-h)
    help
    ;;
  --db)
    if [ "${2:-}" = "--date" ]; then
      DATE_ARG="${3:-}"
    fi
    rollback_db "$DATE_ARG"
    ;;
  --app)
    rollback_app
    ;;
  --full)
    if [ "${2:-}" = "--date" ]; then
      DATE_ARG="${3:-}"
    fi
    rollback_db "$DATE_ARG"
    rollback_app
    ;;
  *)
    echo "Uso: $0 --help | --db [--date YYYY-MM-DD] | --app | --full [--date YYYY-MM-DD]" >&2
    exit 1
    ;;
esac
