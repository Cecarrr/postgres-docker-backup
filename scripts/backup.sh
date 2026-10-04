#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

BACKUP_DIR=backups; LOG=logs/backup.log; KEEP_DAYS=7
mkdir -p "$BACKUP_DIR" logs
FILE="$BACKUP_DIR/${POSTGRES_DB}_$(date +%Y%m%d_%H%M%S).sql.gz"
log(){ echo "$(date '+%F %T') $*" >> "$LOG"; }

if docker compose exec -T -e PGPASSWORD="$BACKUP_PASSWORD" postgres \
     pg_dump -h 127.0.0.1 -U backup_user -d "$POSTGRES_DB" --clean --if-exists \
   | gzip > "$FILE.tmp" && gzip -t "$FILE.tmp"; then
  mv "$FILE.tmp" "$FILE"
  log "SUCCESS $FILE size=$(stat -c %s "$FILE")B"
  find "$BACKUP_DIR" -name '*.sql.gz' -mmin +$((KEEP_DAYS*1440)) -delete
else
  rm -f "$FILE.tmp"
  log "FAILED $FILE"
  exit 1
fi
