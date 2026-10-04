#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"

# Cegah dua backup berjalan bersamaan (mis. cron + manual). BACKUP_LOCK_WAIT = detik menunggu giliran (default: tidak menunggu)
exec 9>"$LOG_DIR/.backup.lock"
flock -w "${BACKUP_LOCK_WAIT:-0}" 9 || { log WARN "Backup lain sedang berjalan; dilewati"; exit 0; }

FILE="$BACKUP_DIR/${POSTGRES_DB}_$(date +%Y%m%d_%H%M%S).sql.gz"
TMP="$FILE.tmp"
ERR="$(mktemp)"
trap 'rm -f "$TMP" "$ERR"' EXIT

# -h postgres: koneksi lewat jaringan, sehingga password backup_user benar-benar diperiksa
if docker compose exec -T -e PGPASSWORD="$BACKUP_PASSWORD" postgres \
       pg_dump -h postgres -U backup_user -d "$POSTGRES_DB" --clean --if-exists 2>"$ERR" \
   | gzip > "$TMP" \
   && gzip -t "$TMP"; then
    mv "$TMP" "$FILE"
    ( cd "$BACKUP_DIR" && sha256sum "$(basename "$FILE")" > "$(basename "$FILE").sha256" )
    log SUCCESS "${FILE#"$PROJECT_DIR"/} size=$(stat -c %s "$FILE")B"

    # Rotasi hanya berjalan setelah backup baru sukses, supaya backup lama tidak hilang saat yang baru gagal
    deleted=0
    while IFS= read -r old; do
        rm -f "$old" "$old.sha256"
        deleted=$((deleted + 1))
    done < <(find "$BACKUP_DIR" -name '*.sql.gz' -mmin +$((KEEP_DAYS * 1440)))
    log INFO "Rotasi: $deleted backup lebih dari $KEEP_DAYS hari dihapus"
else
    reason="$(tr '\n' ' ' < "$ERR" | cut -c1-200)"
    log FAILED "${FILE#"$PROJECT_DIR"/} reason=${reason:-tidak diketahui}"
    exit 1
fi
