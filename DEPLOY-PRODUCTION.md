# Deploy Produksi — PostgreSQL + Redis + Octane (RoadRunner)

Panduan menaikkan aplikasi ke stack produktif: **Octane (RoadRunner)** sebagai app server,
**Redis** untuk cache/session/queue, **PostgreSQL** untuk data, **Reverb** untuk WebSocket.

> Untuk alur deploy dasar (pull, migrasi data yang sudah ada, storage, Reverb) lihat **DEPLOYMENT.md**.
> Dokumen ini fokus ke konfigurasi DB, Redis, dan Octane.

---

## 0. Prasyarat di server (Linux)
```bash
# Ekstensi PHP (sesuaikan versi, PHP 8.2+)
sudo apt install -y php8.2-cli php8.2-pgsql php8.2-redis php8.2-mbstring \
     php8.2-xml php8.2-curl php8.2-bcmath php8.2-zip php8.2-gd

# Layanan
sudo apt install -y postgresql redis-server supervisor nginx
sudo systemctl enable --now redis-server postgresql
```
> `php8.2-redis` (ekstensi phpredis) opsional — project sudah punya `predis/predis`. Jika tidak
> mau pasang ekstensi, set `REDIS_CLIENT=predis` (lihat bagian Redis). phpredis lebih cepat.

---

## 1. Konfigurasi DATABASE (PostgreSQL)
`config/database.php` sudah punya blok `pgsql` bawaan — cukup atur `.env`:

```dotenv
DB_CONNECTION=pgsql
DB_HOST=127.0.0.1
DB_PORT=5432
DB_DATABASE=dinesync_pos
DB_USERNAME=dinesync
DB_PASSWORD=__ganti__
# opsional:
DB_SSLMODE=prefer
DB_CHARSET=utf8
```

Buat DB & user di server:
```bash
sudo -u postgres psql -c "CREATE USER dinesync WITH PASSWORD '__ganti__';"
sudo -u postgres psql -c "CREATE DATABASE dinesync_pos OWNER dinesync;"
```
Migrasi (lihat DEPLOYMENT.md untuk opsi fresh vs backfill data yang sudah ada):
```bash
php artisan migrate --force
```

> Multi-tenant tetap **satu database** (row-level `tenant_id`) — tidak ada koneksi DB tambahan.
> Backup rutin: `pg_dump -U dinesync -d dinesync_pos -F c -f backup.dump`.

---

## 2. Konfigurasi REDIS (cache + session + queue)
`config/database.php` sudah punya blok `redis`. Arahkan cache/session/queue ke Redis via `.env`:

```dotenv
# Client: 'phpredis' (butuh ekstensi php-redis) atau 'predis' (murni PHP, sudah ada di composer)
REDIS_CLIENT=phpredis
REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379

# Pisahkan DB index agar cache & queue tidak tabrakan
REDIS_DB=0
REDIS_CACHE_DB=1

# Arahkan layanan ke Redis
CACHE_STORE=redis
SESSION_DRIVER=redis
QUEUE_CONNECTION=redis

# Prefix cache global (penting kalau beberapa app berbagi 1 Redis)
CACHE_PREFIX=dinesync_

# Broadcasting TETAP reverb (WebSocket terpisah, bukan Redis)
BROADCAST_CONNECTION=reverb
```

Catatan multi-tenant: key cache per-tenant sudah otomatis ter-prefix lewat
`app('tenant')->cacheKey('...')`. `CACHE_PREFIX` di atas adalah prefix global aplikasi.

Amankan Redis (opsional tapi disarankan):
```bash
# /etc/redis/redis.conf
# bind 127.0.0.1 -::1
# requirepass <password_kuat>   -> lalu set REDIS_PASSWORD di .env
sudo systemctl restart redis-server
redis-cli ping        # -> PONG
```
> Dengan cache/session di Redis, tabel `cache`/`sessions`/`jobs` di Postgres tidak lagi dipakai
> (tidak masalah dibiarkan). Job sekarang antre di Redis (list `queues:*`).

---

## 3. Konfigurasi OCTANE (RoadRunner)
`config/octane.php` **sudah ada di repo** (server=roadrunner, listener reset per-request,
`flush` memuat `TenantManager` sebagai pengaman anti-bocor tenant).

### 3a. .env
```dotenv
OCTANE_SERVER=roadrunner
OCTANE_HTTPS=true        # karena di belakang reverse-proxy TLS
```

### 3b. Ambil binary RoadRunner (Linux) — JANGAN commit binary
```bash
# Cara resmi (unduh rr + siapkan config):
php artisan octane:install --server=roadrunner
# atau ambil binary saja:
./vendor/bin/rr get-binary
chmod +x rr
```
> Binary `rr` khusus platform (Linux). Jangan commit; masukkan ke `.gitignore` bila perlu.

### 3c. Jalankan Octane permanen (supervisor)
```bash
sudo tee /etc/supervisor/conf.d/dinesync-octane.conf > /dev/null <<'EOF'
[program:dinesync-octane]
command=php /var/www/dine-sync-pos-v2/artisan octane:start --server=roadrunner --host=127.0.0.1 --port=8000 --workers=auto --max-requests=500
directory=/var/www/dine-sync-pos-v2
autostart=true
autorestart=true
user=www-data
stopwaitsecs=15
redirect_stderr=true
stdout_logfile=/var/www/dine-sync-pos-v2/storage/logs/octane.log
EOF
sudo supervisorctl reread && sudo supervisorctl update && sudo supervisorctl start dinesync-octane
```

### 3d. Nginx (reverse proxy ke Octane + WebSocket Reverb)
> ⚠️ Subpath `/dine-sync-pos-v2` + Octane lebih rumit (Octane serve di root). **Paling bersih pakai
> subdomain** (mis. `pos.beoulve-dev.biz.id`) untuk deployment Octane. Contoh subdomain:

```nginx
server {
    listen 443 ssl http2;
    server_name pos.beoulve-dev.biz.id;
    # ssl_certificate ... ; ssl_certificate_key ... ;

    # App -> Octane
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 60s;
    }

    # Aset statis langsung dari disk (lebih cepat, tak lewat Octane)
    location ^~ /storage/ { root /var/www/dine-sync-pos-v2/public; }
    location ^~ /assets/  { root /var/www/dine-sync-pos-v2/public; }
    location ^~ /build/   { root /var/www/dine-sync-pos-v2/public; }

    # WebSocket Reverb
    location /app {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 60s;
    }
}
```
Kalau pakai subdomain, set `APP_URL=https://pos.beoulve-dev.biz.id` (tanpa subpath).
Kalau tetap subpath, `APP_URL=https://beoulve-dev.biz.id/dine-sync-pos-v2` dan nginx harus
me-*rewrite* buang prefix sebelum `proxy_pass` — subdomain jauh lebih sederhana.

### 3e. Multi-tenant di Octane (WAJIB dipahami)
Worker Octane hidup lama, jadi state bisa bocor antar request. Sudah diamankan:
- `App\Providers\TenancyServiceProvider` reset tenant aktif tiap `RequestReceived`/`RequestTerminated`.
- `config/octane.php` `flush` membuat ulang `TenantManager` tiap request.
- `\Midtrans\Config` static di KasirController di-set ulang tiap pembayaran.
> Setelah setiap deploy / ubah `.env` / `config:cache`, **WAJIB** `php artisan octane:reload`
> supaya worker memuat kode & config baru (mereka menyimpan versi lama di memori).

---

## 4. Queue worker (Redis)
```bash
sudo tee /etc/supervisor/conf.d/dinesync-worker.conf > /dev/null <<'EOF'
[program:dinesync-worker]
command=php /var/www/dine-sync-pos-v2/artisan queue:work redis --sleep=3 --tries=3 --max-time=3600
directory=/var/www/dine-sync-pos-v2
autostart=true
autorestart=true
user=www-data
numprocs=1
redirect_stderr=true
stdout_logfile=/var/www/dine-sync-pos-v2/storage/logs/worker.log
stopwaitsecs=3600
EOF
sudo supervisorctl reread && sudo supervisorctl update && sudo supervisorctl start dinesync-worker
```
> Event realtime (antrian/dapur/TV) pakai `ShouldBroadcastNow` (sinkron) — tetap jalan walau worker mati.

---

## 5. Reverb (WebSocket)
Sama seperti DEPLOYMENT.md bagian 6: jalankan `php artisan reverb:start --host=0.0.0.0 --port=8080`
via supervisor, dan proxy `wss` di nginx (sudah ada di contoh 3d). `.env`:
```dotenv
REVERB_APP_ID=__id__
REVERB_APP_KEY=__key__
REVERB_APP_SECRET=__secret__
REVERB_HOST=127.0.0.1
REVERB_PORT=8080
REVERB_SCHEME=http
```

---

## 6. .env produksi (ringkas — gabungan)
```dotenv
APP_NAME="DineSync POS"
APP_ENV=production
APP_DEBUG=false
APP_URL=https://pos.beoulve-dev.biz.id
APP_TIMEZONE=Asia/Jakarta
LOG_LEVEL=error

DB_CONNECTION=pgsql
DB_HOST=127.0.0.1
DB_PORT=5432
DB_DATABASE=dinesync_pos
DB_USERNAME=dinesync
DB_PASSWORD=__ganti__

REDIS_CLIENT=phpredis
REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379
REDIS_DB=0
REDIS_CACHE_DB=1

CACHE_STORE=redis
SESSION_DRIVER=redis
SESSION_SECURE_COOKIE=true
QUEUE_CONNECTION=redis
CACHE_PREFIX=dinesync_

BROADCAST_CONNECTION=reverb
REVERB_APP_ID=__id__
REVERB_APP_KEY=__key__
REVERB_APP_SECRET=__secret__
REVERB_HOST=127.0.0.1
REVERB_PORT=8080
REVERB_SCHEME=http

OCTANE_SERVER=roadrunner
OCTANE_HTTPS=true

MIDTRANS_IS_PRODUCTION=false
```

---

## 7. Alur deploy (stack Octane + Redis)
```bash
cd /var/www/dine-sync-pos-v2
git pull --ff-only origin main            # atau: origin lite
composer install --no-dev --optimize-autoloader

php artisan migrate --force
php artisan storage:link

# Bersihkan lalu cache ulang (WAJIB urut: clear dulu)
php artisan optimize:clear
php artisan config:cache
php artisan route:cache
php artisan view:cache

# Reload worker agar kode/config baru terpakai (Octane simpan di memori!)
php artisan octane:reload
php artisan queue:restart
sudo supervisorctl restart dinesync-reverb
```
> `npm run build` TIDAK perlu (UI pakai aset Metronic statis di `public/assets/`).

---

## 8. Verifikasi & troubleshooting
```bash
php artisan about                 # cek driver: cache=redis, session=redis, queue=redis, db=pgsql
redis-cli ping                    # PONG
redis-cli -n 1 keys 'dinesync_*'  # cek key cache tenant
sudo supervisorctl status         # octane / worker / reverb harus RUNNING
tail -f storage/logs/octane.log
```

| Gejala | Sebab & solusi |
|--------|----------------|
| Perubahan kode/env tidak muncul | Worker Octane pegang versi lama → `php artisan octane:reload` (dan `optimize:clear`+`config:cache`). |
| `Class "Redis" not found` | Ekstensi phpredis belum ada → `apt install php8.2-redis` **atau** set `REDIS_CLIENT=predis`. |
| Data lama "hilang" per tenant | Baris lama `tenant_id=NULL` → backfill (lihat DEPLOYMENT.md bag. 2B). |
| WebSocket tak konek | Reverb mati / proxy `wss` belum ada (lihat 3d & DEPLOYMENT.md). |
| URL/aset 404 / mixed-content | `APP_URL` salah. Betulkan → `optimize:clear` → `config:cache` → `octane:reload`. |
| Sesi ke-reset random di Octane | Pastikan `SESSION_DRIVER=redis` (jangan `array`); `SESSION_SECURE_COOKIE=true` di HTTPS. |
| Tenant "bocor" antar request | Pastikan TenancyServiceProvider aktif + `config/octane.php` `flush` memuat TenantManager; tes di bawah beban. |
