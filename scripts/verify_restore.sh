#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

TABLES=(customers orders order_items)
DROP_TABLE=order_items
q(){ docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "$1"; }
counts(){ for t in "${TABLES[@]}"; do echo "$t=$(q "SELECT count(*) FROM $t" 2>/dev/null || echo MISSING)"; done; }

echo "[1] Backup terbaru"; ./scripts/backup.sh
LATEST=$(ls -1t backups/*.sql.gz | head -n1); echo "    $LATEST"
BEFORE=$(counts); echo "[2] Jumlah baris SEBELUM:"; echo "$BEFORE"
echo "[3] DROP TABLE $DROP_TABLE"; q "DROP TABLE $DROP_TABLE" >/dev/null
echo "[4] Setelah drop:"; counts
echo "[5] Restore"; ./scripts/restore.sh "$LATEST"
AFTER=$(counts); echo "[6] Jumlah baris SESUDAH:"; echo "$AFTER"

if [ "$BEFORE" = "$AFTER" ]; then echo "RESULT: PASS"; else echo "RESULT: FAIL"; exit 1; fi
