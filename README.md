# postgres-docker-backup

PostgreSQL 16 di Docker Compose dengan role hak-minimum, backup harian otomatis,
dan **uji restore yang terverifikasi** (drop tabel, restore, bandingkan jumlah baris).

## Arsitektur

```
 cron (02:00) --> scripts/backup.sh --> docker compose exec pg_dump (backup_user)
                       |                          |
                       |                 [ container postgres:16 ] -- [ volume pgdata ]
                       v                          ^
        backups/*.sql.gz (rotasi 7 hari)          |
        logs/backup.log                           |
 restore.sh / verify_restore.sh ---- psql (superuser di dalam container)
```

## Struktur

```
docker-compose.yml         service postgres, volume named, healthcheck pg_isready
.env.example               template konfigurasi (.env asli tidak di-commit)
init/01_schema.sql         customers, orders, order_items + data dummy
init/02_roles.sql          app_rw, app_ro, backup_user (hak minimum)
scripts/backup.sh          pg_dump + gzip + rotasi 7 hari + log
scripts/restore.sh         restore file backup ke database tujuan
scripts/verify_restore.sh  uji restore otomatis
cron/crontab.example       jadwal backup harian
```

## Menjalankan dari nol

Prasyarat: Docker + Docker Compose plugin, cronie, git (opsional: klien `psql`).

```bash
git clone https://github.com/Cecarrr/postgres-docker-backup.git
cd postgres-docker-backup
cp .env.example .env
nano .env                  # ganti semua password
docker compose up -d
docker compose ps          # tunggu status healthy
```

## Role

| Role | Hak |
|---|---|
| app_rw | SELECT, INSERT, UPDATE, DELETE |
| app_ro | SELECT |
| backup_user | SELECT (cukup untuk pg_dump) |

Password diatur lewat `.env` dan dibaca oleh `init/02_roles.sql`, tidak ada password di repo.

## Penggunaan

```bash
./scripts/backup.sh                                       # backup manual
./scripts/restore.sh backups/<file>.sql.gz [target_db]    # restore
./scripts/verify_restore.sh                               # uji restore otomatis
```

Hasil backup ada di `backups/`, log di `logs/backup.log`. Backup yang lebih tua dari 7 hari dihapus otomatis.

## Jadwal cron

Pasang dengan `crontab -e` (ganti `/path/to` dengan lokasi repo di mesin kamu):

```
0 2 * * * /path/to/postgres-docker-backup/scripts/backup.sh >> /path/to/postgres-docker-backup/logs/cron.out 2>&1
```

## Bukti uji restore

Output `./scripts/verify_restore.sh` (tabel `order_items` di-drop, lalu dipulihkan dari backup):

```
[1] Backup terbaru
    backups/shopdb_20261004_221308.sql.gz
[2] Jumlah baris SEBELUM:
customers=100
orders=300
order_items=800
[3] DROP TABLE order_items
[4] Setelah drop:
customers=100
orders=300
order_items=MISSING
[5] Restore
 set_config 
------------
 
(1 row)

 setval 
--------
    100
(1 row)

 setval 
--------
    800
(1 row)

 setval 
--------
    300
(1 row)

Restore backups/shopdb_20261004_221308.sql.gz -> shopdb selesai
[6] Jumlah baris SESUDAH:
customers=100
orders=300
order_items=800
RESULT: PASS
```

## Batasan

- Backup masih di satu mesin yang sama dengan database (jika disk rusak, keduanya hilang).
- Belum ada enkripsi pada file backup.
- Belum ada backup offsite.
- Cron tidak berjalan jika mesin mati pada jam jadwal.
