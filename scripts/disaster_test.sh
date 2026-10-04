#!/usr/bin/env bash
# Simulasi kehilangan total: volume data dihapus, database dibuat ulang dari nol, lalu dipulihkan dari backup.
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"

if [ "${ASSUME_YES:-0}" != 1 ]; then
    read -r -p "Ini MENGHAPUS volume data database ('docker compose down -v'). Ketik 'hapus' untuk lanjut: " ans
    [ "$ans" = hapus ] || die "Uji bencana dibatalkan"
fi

echo "[1] Tambah tabel penanda (supaya data berbeda dari data awal hasil init)"
psql_admin -c "DROP TABLE IF EXISTS public._restore_marker" \
           -c "CREATE TABLE public._restore_marker AS SELECT now() AS created_at, md5(random()::text) AS token" > /dev/null

echo "[2] Sidik jari SEBELUM"
BEFORE="$(fingerprint)"; echo "$BEFORE" | sed 's/^/    /'
require_fingerprint "$BEFORE"

echo "[3] Backup"
SINCE="$(date +%s)"
BACKUP_LOCK_WAIT=120 ./scripts/backup.sh
LATEST="$(latest_backup)"; echo "    file: $LATEST"
backup_fresh "$LATEST" "$SINCE"

echo "[4] BENCANA: docker compose down -v (volume dihapus)"
docker compose down -v

echo "[5] Membuat ulang dari nol (init/ berjalan lagi)"
docker compose up -d --wait
echo "    sidik jari database baru, sebelum restore:"
fingerprint | sed 's/^/    /'

echo "[6] Restore dari backup"
ASSUME_YES=1 ./scripts/restore.sh "$LATEST"

echo "[7] Sidik jari SESUDAH"
AFTER="$(fingerprint)"; echo "$AFTER" | sed 's/^/    /'
require_fingerprint "$AFTER"
compare_fingerprint "$BEFORE" "$AFTER"

psql_admin -c "DROP TABLE IF EXISTS public._restore_marker" > /dev/null

echo "[8] Hak akses setelah restore"
check_privileges

echo "RESULT: PASS"
log SUCCESS "disaster_test PASS"
