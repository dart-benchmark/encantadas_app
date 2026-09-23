#!/usr/bin/env bash
#
# Cron de retención de backups Encantadas en PocketBase.
# Política grandfather-father-son:
#   - Conservar últimos N_DAILY backups recientes (default 7)
#   - Conservar 1 por semana de las últimas N_WEEKLY semanas (default 4)
#   - Conservar 1 por mes de los últimos N_MONTHLY meses (default 12)
#   - Borrar todo lo demás
#
# Diseñado para correr 1 vez por día via cron.
#
# Configuración via env vars o editar valores abajo.
# Requiere: curl + jq

set -euo pipefail

# ─── Config ──────────────────────────────────────────────────────────────
PB_URL="${PB_URL:-http://localhost:8090}"
SUPERUSER_EMAIL="${SUPERUSER_EMAIL:-retention.bot@encantadas.app}"
SUPERUSER_PASSWORD_FILE="${SUPERUSER_PASSWORD_FILE:-/home/ubuntu/.encantadas-pb-pass}"

N_DAILY=7      # Últimos 7 backups SIEMPRE conservados
N_WEEKLY=4     # 1 por semana últimas 4 semanas
N_MONTHLY=12   # 1 por mes últimos 12 meses

LOG="/var/log/encantadas-retention.log"
DRY_RUN="${DRY_RUN:-0}"   # 1 = solo loguear, no borrar

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}

# ─── Auth ────────────────────────────────────────────────────────────────
if [ ! -f "$SUPERUSER_PASSWORD_FILE" ]; then
  log "ERROR: password file no encontrado en $SUPERUSER_PASSWORD_FILE"
  exit 1
fi
PASS=$(cat "$SUPERUSER_PASSWORD_FILE")

TOKEN=$(curl -sS -X POST "$PB_URL/api/collections/_superusers/auth-with-password" \
  -H 'Content-Type: application/json' \
  -d "{\"identity\":\"$SUPERUSER_EMAIL\",\"password\":\"$PASS\"}" | jq -r '.token // empty')

if [ -z "$TOKEN" ]; then
  log "ERROR: auth fallido para $SUPERUSER_EMAIL"
  exit 1
fi

# ─── Listar todos los backups (ordenados desc por created) ───────────────
ALL=$(curl -sS "$PB_URL/api/collections/encantadas_backups/records?perPage=500&sort=-created&fields=id,created" \
  -H "Authorization: $TOKEN")

TOTAL=$(echo "$ALL" | jq '.totalItems')
log "Backups totales: $TOTAL"

if [ "$TOTAL" -le "$N_DAILY" ]; then
  log "Hay $TOTAL backups, mínimo $N_DAILY → nada que limpiar"
  exit 0
fi

# ─── Calcular qué conservar ──────────────────────────────────────────────
# Algoritmo:
# 1. Conservar los primeros N_DAILY (los más nuevos)
# 2. Para cada semana de las últimas N_WEEKLY semanas, conservar el más nuevo
#    de esa semana (si existe)
# 3. Para cada mes de los últimos N_MONTHLY meses, conservar el más nuevo
# 4. El resto se borra

KEEP_FILE=$(mktemp)
DELETE_FILE=$(mktemp)
trap "rm -f $KEEP_FILE $DELETE_FILE" EXIT

echo "$ALL" | jq -r '.items[] | "\(.id)|\(.created)"' | \
python3 - "$N_DAILY" "$N_WEEKLY" "$N_MONTHLY" "$KEEP_FILE" "$DELETE_FILE" <<'PYEOF'
import sys
from datetime import datetime, timedelta

n_daily = int(sys.argv[1])
n_weekly = int(sys.argv[2])
n_monthly = int(sys.argv[3])
keep_path = sys.argv[4]
delete_path = sys.argv[5]

now = datetime.utcnow()
items = []
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    rid, created = line.split('|', 1)
    # PB created format: "2026-04-25 22:46:26.882Z"
    try:
        dt = datetime.strptime(created.replace('Z', '').split('.')[0], '%Y-%m-%d %H:%M:%S')
    except ValueError:
        continue
    items.append((rid, dt))

# Sort desc por fecha (más nuevo primero)
items.sort(key=lambda x: x[1], reverse=True)

keep = set()

# 1. Daily: primeros N_DAILY
for rid, _ in items[:n_daily]:
    keep.add(rid)

# 2. Weekly: 1 por semana de últimas N_WEEKLY semanas
weekly_buckets = {}  # week_start_date -> (rid, dt)
for rid, dt in items:
    weeks_ago = (now - dt).days // 7
    if weeks_ago >= n_weekly:
        continue
    wk = dt.isocalendar()[:2]  # (year, week)
    if wk not in weekly_buckets or weekly_buckets[wk][1] < dt:
        weekly_buckets[wk] = (rid, dt)
for rid, _ in weekly_buckets.values():
    keep.add(rid)

# 3. Monthly: 1 por mes de últimos N_MONTHLY meses
monthly_buckets = {}
for rid, dt in items:
    months_ago = (now.year - dt.year) * 12 + (now.month - dt.month)
    if months_ago >= n_monthly:
        continue
    mn = (dt.year, dt.month)
    if mn not in monthly_buckets or monthly_buckets[mn][1] < dt:
        monthly_buckets[mn] = (rid, dt)
for rid, _ in monthly_buckets.values():
    keep.add(rid)

# 4. Resto a borrar
delete = [rid for rid, _ in items if rid not in keep]

with open(keep_path, 'w') as f:
    for rid in keep:
        f.write(rid + '\n')
with open(delete_path, 'w') as f:
    for rid in delete:
        f.write(rid + '\n')

print(f"keep={len(keep)} delete={len(delete)}", file=sys.stderr)
PYEOF

KEEP_COUNT=$(wc -l < "$KEEP_FILE" | tr -d ' ')
DELETE_COUNT=$(wc -l < "$DELETE_FILE" | tr -d ' ')

log "Plan: conservar $KEEP_COUNT, borrar $DELETE_COUNT"

if [ "$DELETE_COUNT" -eq 0 ]; then
  log "Nada que borrar"
  exit 0
fi

if [ "$DRY_RUN" = "1" ]; then
  log "DRY_RUN=1 → no se borra realmente. IDs que se borrarían:"
  cat "$DELETE_FILE" | tee -a "$LOG"
  exit 0
fi

# ─── Ejecutar borrado ────────────────────────────────────────────────────
DELETED=0
FAILED=0
while IFS= read -r rid; do
  [ -z "$rid" ] && continue
  CODE=$(curl -sS -o /dev/null -w '%{http_code}' \
    -X DELETE "$PB_URL/api/collections/encantadas_backups/records/$rid" \
    -H "Authorization: $TOKEN")
  if [ "$CODE" = "204" ]; then
    DELETED=$((DELETED + 1))
  else
    FAILED=$((FAILED + 1))
    log "FAIL delete $rid (HTTP $CODE)"
  fi
done < "$DELETE_FILE"

log "Resultado: borrados=$DELETED fallidos=$FAILED conservados=$KEEP_COUNT"
