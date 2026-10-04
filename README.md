# postgres-docker-backup

PostgreSQL 16 di Docker Compose dengan role hak-minimum, backup harian otomatis (gzip, checksum, rotasi 7 hari), dan **uji pemulihan yang membuktikan data kembali identik**, termasuk skenario kehilangan volume total.

## Arsitektur

```
 systemd timer (02:00, Persistent) / cron
              |
      scripts/backup.sh --- docker compose exec ---> [ postgres:16 ] -- volume pgdata
   (backup_user, -h postgres, lock, sha256)
              |
   backups/*.sql.gz (+ .sha256, rotasi 7 hari)        logs/backup.log
              |
   scripts/restore.sh        (superuser, 1 transaksi, minta konfirmasi)
   scripts/verify_restore.sh / scripts/disaster_test.sh  ->  bukti di docs/evidence/
```

## Struktur

```
docker-compose.yml         service postgres, volume named, healthcheck pg_isready
.env.example               template konfigurasi (.env asli tidak di-commit)
init/01_schema.sql         customers, orders, order_items + data dummy
init/02_roles.sql          app_rw, app_ro, backup_user + default privileges
scripts/lib.sh             fungsi bersama (log, sidik jari data, cek hak akses)
scripts/backup.sh          pg_dump + gzip + sha256 + lock + rotasi + log
scripts/restore.sh         restore (konfirmasi, satu transaksi, cek checksum)
scripts/verify_restore.sh  uji: hapus semua tabel -> restore -> bandingkan data
scripts/disaster_test.sh   uji: hapus volume -> buat ulang -> restore -> bandingkan
systemd/                   timer harian dengan Persistent=true
cron/crontab.example       alternatif jadwal dengan cron
docs/evidence/             keluaran nyata dari setiap pengujian
```

## Menjalankan dari nol

Prasyarat: Docker + Docker Compose plugin, git. Opsional: klien `psql`.

```
git clone https://github.com/Cecarrr/postgres-docker-backup.git
cd postgres-docker-backup
cp .env.example .env
nano .env                  # ganti semua password
docker compose up -d --wait
```

## Role

| Role         | Hak                                          |
| ------------ | -------------------------------------------- |
| app_rw       | SELECT, INSERT, UPDATE, DELETE               |
| app_ro       | SELECT                                       |
| backup_user  | SELECT (cukup untuk pg_dump)                 |

Tabel yang dibuat belakangan otomatis mendapat hak yang sama (`ALTER DEFAULT PRIVILEGES`). Password dibaca dari `.env` lewat `\getenv`; tidak ada password di repo.

## Penggunaan

```
./scripts/backup.sh                              # backup manual
./scripts/restore.sh backups/<file>.sql.gz       # restore (minta konfirmasi bila menimpa database utama)
./scripts/restore.sh backups/<file>.sql.gz uji   # restore ke database lain bernama "uji"
./scripts/verify_restore.sh                      # uji restore lengkap
ASSUME_YES=1 ./scripts/disaster_test.sh          # uji kehilangan volume (MENGHAPUS data lalu memulihkannya)
```

Backup yang gagal tidak meninggalkan file parsial dan dicatat di `logs/backup.log` beserta alasannya. Rotasi baru berjalan setelah backup baru sukses.

## Penjadwalan

Systemd timer (disarankan untuk laptop, karena jadwal yang terlewat dijalankan saat laptop hidup):

```
mkdir -p ~/.config/systemd/user
cp systemd/pg-backup.* ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now pg-backup.timer
```

Alternatif cron: lihat `cron/crontab.example`.

## Autentikasi

Koneksi lewat jaringan wajib password (scram-sha-256): dari host lewat port 5432, dan dari container lewat nama service (`-h postgres`). Koneksi loopback di dalam container memakai `trust` (bawaan image resmi), sehingga `backup.sh` sengaja memakai `-h postgres` agar kredensial `backup_user` benar-benar divalidasi. `restore.sh` dan skrip uji memakai superuser lewat socket untuk operasi administratif. Bukti: `docs/evidence/auth.txt`.

## Bukti pengujian

Semua keluaran di bawah adalah hasil nyata dari menjalankan skrip di repo ini.

| Pengujian | Membuktikan | Berkas |
| --- | --- | --- |
| Uji restore | Semua tabel dihapus lalu dipulihkan; jumlah baris dan md5 isi tiap tabel identik; hak akses role utuh | `docs/evidence/verify_restore.txt` |
| Uji bencana | Volume dihapus, database dibuat ulang dari nol, dipulihkan dari backup; data identik dengan sebelum bencana | `docs/evidence/disaster_test.txt` |
| Rotasi | Backup lebih dari 7 hari (dan checksum-nya) terhapus | `docs/evidence/rotation.txt` |
| Jalur gagal | Backup gagal saat container mati: exit code 1, tidak ada file parsial, alasan tercatat | `docs/evidence/failure.txt` |
| Autentikasi | Password salah ditolak; backup gagal bila password backup_user salah | `docs/evidence/auth.txt` |
| Hak default | Tabel baru langsung bisa dibaca backup_user | `docs/evidence/default_privileges.txt` |

Cara sidik jari data: untuk setiap tabel di schema `public`, dihitung `count(*)` dan `md5` dari seluruh baris (diurutkan). Pada uji bencana ditambahkan tabel penanda acak supaya data berbeda dari data awal hasil `init/`; kecocokan sesudah restore membuktikan data berasal dari backup.

## Troubleshooting

| Gejala | Penyebab / solusi |
| --- | --- |
| `permission denied` pada docker.sock | User belum di grup `docker`; `sudo usermod -aG docker $USER`, lalu login ulang |
| Port 5432 sudah dipakai | Ada PostgreSQL lain di host; ubah mapping port di `docker-compose.yml` |
| Skrip `init/` tidak berjalan lagi | `init/` hanya berjalan pada volume kosong; `docker compose down -v` menghapus data |
| Permission denied saat mount `init/` (Fedora/SELinux) | Pastikan label `:z` pada volume `./init` |
| Log `WARN Backup lain sedang berjalan` | Lock aktif; backup lain sedang berjalan, tunggu atau set `BACKUP_LOCK_WAIT` |
| `up --wait` tidak dikenal | Perbarui Docker Compose plugin |

## Batasan

- Backup ada di mesin yang sama dengan database; jika disk rusak, keduanya hilang.
- Backup tidak dienkripsi dan belum ada backup offsite.
- Format plain SQL: restore selalu untuk seluruh database, bukan per tabel.
- Role tidak ikut dalam backup; role dibuat ulang oleh `init/` pada volume baru.
- Password ada di `.env` dan environment container (terlihat lewat `docker inspect`).
- Belum ada notifikasi saat backup gagal, hanya log.
- Data contoh kecil; durasi backup/restore pada data besar belum diukur.

## Rencana

CI (GitHub Actions: shellcheck + uji restore dari nol), enkripsi backup, lalu penyimpanan offsite.

## Lisensi

MIT. Lihat [LICENSE](LICENSE).
