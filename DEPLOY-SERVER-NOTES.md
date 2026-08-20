# dev.mooda.id — catatan server (DineSync POS v2)

Instance ini **berdiri sendiri**: tidak berbagi folder, database, index Redis,
proses, maupun vhost dengan mooda.id / event.mooda.id / laundry.mooda.id / wa-gateway.

> Jangan simpan rahasia di file ini — berada di dalam web root.

## Alokasi sumber daya (jangan bentrok)

| Sumber daya | mooda.id (stakko-pos) | **dev.mooda.id (repo ini)** |
|---|---|---|
| Folder | `/var/www/html/stakko-pos` | `/var/www/html/dine-sync-pos-v2` |
| Octane (RoadRunner) | `127.0.0.1:8044` | **`127.0.0.1:8055`** |
| Reverb (WebSocket) | `127.0.0.1:8080` | **`127.0.0.1:8081`** |
| PostgreSQL | `stakko_pos` | **`dinesync_pos`** (user `dinesync`) |
| Redis session | DB 0 | **DB 2** |
| Redis cache | DB 1 | **DB 3** (prefix `dinesync_`) |
| Cookie sesi | `mooda-session` | **`dinesync_session`** |
| nginx | `sites-available/mooda.id.conf` | **`sites-available/dev.mooda.id.conf`** |
| Sertifikat TLS | `live/mooda.id/` | **`live/dev.mooda.id/`** |

## Service systemd (bukan supervisor)

```bash
systemctl status  octane-dine-sync reverb-dine-sync worker-dine-sync
systemctl restart octane-dine-sync
journalctl -u octane-dine-sync -f
```

| Unit | Perintah |
|---|---|
| `octane-dine-sync.service` | `php artisan octane:start --server=roadrunner --host=127.0.0.1 --port=8055` |
| `reverb-dine-sync.service` | `php artisan reverb:start --host=127.0.0.1 --port=8081` |
| `worker-dine-sync.service` | `php artisan queue:work redis` |

## Alur deploy

```bash
cd /var/www/html/dine-sync-pos-v2
git pull --ff-only origin main
composer install --no-dev --optimize-autoloader
php artisan migrate --force

php artisan optimize:clear
php artisan config:cache && php artisan route:cache && php artisan view:cache
chown -R www-data:www-data storage bootstrap/cache

php artisan octane:reload          # WAJIB — worker menyimpan kode lama di memori
php artisan queue:restart
systemctl restart reverb-dine-sync # hanya bila kode broadcasting berubah
```

## Kredensial

- Password DB & superadmin **tidak** ditulis di sini. Ada di `/root/.dinesync_db_pw`
  dan `/root/.dinesync_admin_pw` (chmod 600, di luar web root).
- Password superadmin default bawaan `SuperAdminSeeder` **sudah diganti** karena
  repo ini publik di GitHub. Jangan jalankan ulang seeder itu di server produksi.

## Jangan lakukan

- `redis-cli FLUSHALL` / `FLUSHDB` tanpa `-n` → menghapus sesi aplikasi LAIN (DB 0/1 milik stakko-pos).
  Untuk instance ini: `redis-cli -n 3 --scan --pattern 'dinesync_*'` lalu hapus yang perlu saja.
- Mengubah `mooda.id.conf` untuk keperluan dev — vhost-nya terpisah.
