#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

FILE="${1:?Usage: $0 <backup.sql.gz> [target_db]}"
TARGET="${2:-$POSTGRES_DB}"
[ -f "$FILE" ] || { echo "File tidak ditemukan: $FILE" >&2; exit 1; }
gzip -t "$FILE"

PSQL=(docker compose exec -T postgres psql -U "$POSTGRES_USER" -v ON_ERROR_STOP=1)
exists=$("${PSQL[@]}" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$TARGET'")
[ "$exists" = 1 ] || "${PSQL[@]}" -d postgres -c "CREATE DATABASE \"$TARGET\""
gunzip -c "$FILE" | "${PSQL[@]}" -d "$TARGET" -q
echo "Restore $FILE -> $TARGET selesai"
