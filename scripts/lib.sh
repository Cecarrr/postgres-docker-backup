#!/usr/bin/env bash
# Fungsi bersama. Di-source oleh skrip lain; jangan dijalankan langsung.

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

[ -f .env ] || { echo "ERROR: .env tidak ditemukan di $PROJECT_DIR" >&2; exit 1; }
set -a; source .env; set +a

BACKUP_DIR="$PROJECT_DIR/backups"
LOG_DIR="$PROJECT_DIR/logs"
LOG_FILE="$LOG_DIR/backup.log"
KEEP_DAYS="${BACKUP_RETENTION_DAYS:-7}"
mkdir -p "$BACKUP_DIR" "$LOG_DIR"

log()  { local lvl="$1"; shift; printf '%s %s %s\n' "$(date '+%F %T')" "$lvl" "$*" | tee -a "$LOG_FILE"; }
die()  { log ERROR "$*"; exit 1; }
fail() { echo "RESULT: FAIL ($*)"; log ERROR "FAIL: $*"; exit 1; }

# Pastikan backup terbaru dibuat SETELAH titik waktu tertentu (bukan backup lama karena backup baru dilewati)
backup_fresh() {   # backup_fresh <file> <epoch_awal>
    [ -n "$1" ] && [ "$(stat -c %Y "$1")" -ge "$2" ] || fail "backup baru tidak terbentuk (yang terbaru sudah lama atau backup dilewati)"
}

latest_backup() { ls -1t "$BACKUP_DIR"/*.sql.gz 2>/dev/null | sed -n 1p; }

# psql sebagai superuser lewat socket di dalam container
psql_admin() { docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -tA "$@"; }

# psql sebagai role tertentu lewat jaringan (-h postgres), jadi passwordnya benar-benar diperiksa
as_role() {   # as_role <user> <password> <argumen psql...>
    local u="$1" p="$2"; shift 2
    docker compose exec -T -e PGPASSWORD="$p" postgres \
        psql -h postgres -U "$u" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -tA "$@"
}

tables() { psql_admin -c "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY 1"; }

# Sidik jari isi data: jumlah baris + md5 dari seluruh baris, untuk SEMUA tabel di schema public
fingerprint() {
    local t out
    for t in $(tables); do
        if out="$(psql_admin -c "SELECT count(*) || ':' || coalesce(md5(string_agg(x::text, ',' ORDER BY x::text)), '-') FROM public.\"$t\" AS x" 2>&1)"; then
            echo "$t=$out"
        else
            echo "$t=ERROR"
        fi
    done
}

require_fingerprint() {
    [ -n "$1" ] || fail "tidak ada tabel di schema public"
    ! grep -q '=ERROR' <<<"$1" || fail "gagal menghitung sidik jari"
}

compare_fingerprint() {
    if [ "$1" = "$2" ]; then
        echo "    sidik jari IDENTIK"
    else
        diff <(echo "$1") <(echo "$2") || true
        fail "sidik jari berbeda"
    fi
}

# Hak akses setiap role harus utuh setelah restore
check_privileges() {
    local t q
    t="$(tables | grep -v '^_' | sed -n 1p || true)"
    [ -n "$t" ] || fail "tidak ada tabel untuk uji hak akses"
    q="public.\"$t\""
    as_role app_rw "$APP_RW_PASSWORD" -c "SELECT 1 FROM $q LIMIT 1" -c "DELETE FROM $q WHERE false" >/dev/null 2>&1 \
        && echo "    app_rw baca/tulis: OK" || fail "app_rw kehilangan hak setelah restore"
    as_role app_ro "$APP_RO_PASSWORD" -c "SELECT 1 FROM $q LIMIT 1" >/dev/null 2>&1 \
        && echo "    app_ro baca: OK" || fail "app_ro tidak bisa SELECT setelah restore"
    if as_role app_ro "$APP_RO_PASSWORD" -c "DELETE FROM $q WHERE false" >/dev/null 2>&1; then
        fail "app_ro BISA menulis (seharusnya ditolak)"
    fi
    echo "    app_ro tulis ditolak: OK"
    as_role backup_user "$BACKUP_PASSWORD" -c "SELECT 1 FROM $q LIMIT 1" >/dev/null 2>&1 \
        && echo "    backup_user baca: OK" || fail "backup_user tidak bisa SELECT setelah restore"
    if as_role backup_user "$BACKUP_PASSWORD" -c "DELETE FROM $q WHERE false" >/dev/null 2>&1; then
        fail "backup_user BISA menulis (seharusnya ditolak)"
    fi
    echo "    backup_user tulis ditolak: OK"
}
