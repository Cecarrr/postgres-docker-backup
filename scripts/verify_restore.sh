#!/usr/bin/env bash
# Bukti restore: sidik jari isi data -> backup -> hapus SEMUA tabel -> restore -> bandingkan -> cek hak akses
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"

echo "[1] Sidik jari SEBELUM"
BEFORE="$(fingerprint)"; echo "$BEFORE" | sed 's/^/    /'
require_fingerprint "$BEFORE"

echo "[2] Backup"
SINCE="$(date +%s)"
BACKUP_LOCK_WAIT=120 ./scripts/backup.sh
LATEST="$(latest_backup)"; echo "    file: $LATEST"
backup_fresh "$LATEST" "$SINCE"

echo "[3] Simulasi bencana: DROP semua tabel di schema public"
psql_admin -c "DROP TABLE $(tables | sed 's/.*/public."&"/' | paste -sd, -) CASCADE" > /dev/null
echo "    tabel tersisa: $(tables | wc -l)"

echo "[4] Restore"
ASSUME_YES=1 ./scripts/restore.sh "$LATEST"

echo "[5] Sidik jari SESUDAH"
AFTER="$(fingerprint)"; echo "$AFTER" | sed 's/^/    /'
require_fingerprint "$AFTER"
compare_fingerprint "$BEFORE" "$AFTER"

echo "[6] Hak akses setelah restore"
check_privileges

echo "RESULT: PASS"
log SUCCESS "verify_restore PASS"
