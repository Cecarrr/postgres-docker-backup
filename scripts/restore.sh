#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"

FILE="${1:?Pemakaian: $0 <backup.sql.gz> [db_tujuan]}"
TARGET="${2:-$POSTGRES_DB}"
[ -f "$FILE" ] || { echo "File tidak ditemukan: $FILE" >&2; exit 1; }

gzip -t "$FILE" || die "File gzip rusak: $FILE"
if [ -f "$FILE.sha256" ]; then
    ( cd "$(dirname "$FILE")" && sha256sum -c "$(basename "$FILE").sha256" > /dev/null ) \
        || die "Checksum tidak cocok: $FILE"
    log INFO "Checksum OK: $(basename "$FILE")"
else
    log WARN "$(basename "$FILE").sha256 tidak ada; integritas hanya dicek dengan gzip -t"
fi

# Restore ke database utama menimpa isinya (dump dibuat dengan --clean), jadi minta konfirmasi
if [ "$TARGET" = "$POSTGRES_DB" ] && [ "${ASSUME_YES:-0}" != 1 ]; then
    read -r -p "Ini akan MENIMPA database '$TARGET'. Ketik 'ya' untuk lanjut: " ans
    [ "$ans" = ya ] || die "Restore dibatalkan"
fi

PSQL=(docker compose exec -T postgres psql -U "$POSTGRES_USER" -v ON_ERROR_STOP=1)
exists="$("${PSQL[@]}" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$TARGET'")"
if [ "$exists" != 1 ]; then
    "${PSQL[@]}" -d postgres -c "CREATE DATABASE \"$TARGET\""
    log INFO "Database '$TARGET' dibuat"
fi

# -1: satu transaksi. Jika ada error, semua perubahan dibatalkan (tidak ada database setengah pulih)
log INFO "Mulai restore $(basename "$FILE") ke '$TARGET'"
gunzip -c "$FILE" | "${PSQL[@]}" -d "$TARGET" -q -1 -o /dev/null
log SUCCESS "Restore $(basename "$FILE") -> $TARGET selesai"
