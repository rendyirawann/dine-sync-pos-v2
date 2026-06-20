# Panduan Deploy / Update di Server

Server: **Linux**, domain `https://beoulve-dev.biz.id`, subpath **`/dine-sync-pos-v2`**, **PostgreSQL**, web server PHP-FPM (Apache/Nginx).
Aplikasi sudah jalan dari pull sebelumnya — dokumen ini untuk **update (git pull)** + setting menyeluruh (multi-tenant, Reverb, storage, migrasi).

> Ganti `<...>` sesuai server. Jalankan semua perintah dari **root project** di server. Untuk produksi, perintah migrate/seed butuh `--force`.

---

## 0. Ringkas: update rutin (kalau DB sudah ber-tenant)
Kalau server sudah pernah dimigrasi ke versi multi-tenant, update berikutnya cukup:

```bash
cd /path/ke/dine-sync-pos-v2
php artisan down                      # maintenance mode (opsional)

git pull --ff-only origin main        # atau: git pull origin lite (versi murah)
composer install --no-dev --optimize-autoloader

php artisan migrate --force           # hanya migration baru yang jalan

php artisan optimize:clear            # WAJIB: buang cache lama dulu
php artisan config:cache
php artisan route:cache
php artisan view:cache
php artisan storage:link              # idempoten (aman diulang)

php artisan queue:restart             # kalau ada worker
# restart Reverb (lihat bagian 6): sudo supervisorctl restart dinesync-reverb

php artisan up
```

> ⚠️ **`npm run build` TIDAK perlu.** UI memakai aset Metronic statis di `public/assets/` (bukan Vite). Tidak butuh Node di server.

Sisanya di bawah ini adalah penjelasan menyeluruh + setup pertama kali (terutama **migrasi DB yang sudah ada datanya** dan **Reverb**).

---

## 1. File `.env` (JANGAN timpa yang sudah ada di server)
`.env` di server sudah berisi APP_KEY/DB/Reverb dari pull sebelumnya. **Jangan overwrite** (kalau APP_KEY berubah, semua sesi & data terenkripsi rusak). Cukup **pastikan/ tambahkan** nilai-nilai penting berikut.

> Catatan: `.env.example` di repo ini masih bawaan Laravel (sqlite) — **JANGAN** dipakai sebagai acuan produksi. Acuan yang benar adalah `.env` server yang sudah jalan.

Nilai wajib untuk produksi:

```dotenv
APP_NAME="DineSync POS"
APP_ENV=production
APP_DEBUG=false
APP_URL=https://beoulve-dev.biz.id/dine-sync-pos-v2   # WAJIB lengkap dengan subpath + https
APP_TIMEZONE=Asia/Jakarta
LOG_LEVEL=error

# Database (PostgreSQL)
DB_CONNECTION=pgsql
DB_HOST=127.0.0.1
DB_PORT=5432                 # cek port Postgres server (lokal pakai 5433, server biasanya 5432)
DB_DATABASE=<nama_db>
DB_USERNAME=<user>
DB_PASSWORD=<password>

# Session/Cache/Queue (semua database-driven, tidak butuh Redis)
SESSION_DRIVER=database
SESSION_SECURE_COOKIE=true   # karena situs HTTPS
CACHE_STORE=database
QUEUE_CONNECTION=database

# Broadcasting / Reverb (WebSocket) — lihat bagian 6
BROADCAST_CONNECTION=reverb
REVERB_APP_ID=<id>
REVERB_APP_KEY=<key>
REVERB_APP_SECRET=<secret>
REVERB_HOST=127.0.0.1        # tempat Laravel mengirim event ke Reverb (lokal di server)
REVERB_PORT=8080
REVERB_SCHEME=http           # internal (server -> reverb). Browser tetap konek via wss:443 (reverse proxy)

# Midtrans — DINONAKTIFKAN untuk trial, biarkan apa adanya
MIDTRANS_IS_PRODUCTION=false

# Versi LITE saja (di branch lite) — opsional menyalakan fitur tertentu:
# FEATURE_INVENTORY=true
# FEATURE_HPP=true
# FEATURE_SELF_ORDER=true
# FEATURE_QUEUE=true
```

> 🔴 **Gotcha paling penting — `APP_URL`.** Di produksi (`APP_ENV=production`), `AppServiceProvider` memanggil `URL::forceRootUrl(APP_URL)` + `forceScheme('https')`. Jadi SEMUA link, redirect, dan `asset()` dibangun ulang dari `APP_URL`. Kalau `APP_URL` salah (tanpa `/dine-sync-pos-v2` atau masih `http`), semua URL/aset/QR akan 404 atau mixed-content. **Harus** `https://beoulve-dev.biz.id/dine-sync-pos-v2`.

> 🔴 **Setelah edit `.env`, WAJIB** `php artisan optimize:clear` lalu `config:cache` lagi — kalau tidak, nilai lama tetap "beku" di cache.

Kalau server **belum** punya `APP_KEY`:
```bash
php artisan key:generate --force
```

---

## 2. (PERTAMA KALI) Migrasi DB multi-tenant — BACA SEBELUM `migrate`
Ini bagian paling kritikal karena server Anda **sudah punya data**.

Apa yang dilakukan migration baru:
- `2026_06_17_000001` → buat tabel `tenants` (daftar UMKM).
- `2026_06_17_000002` → tambah kolom **`tenant_id` (uuid, NULLABLE)** ke semua tabel data, dan ubah UNIQUE global jadi composite per-tenant (`categories.slug`, `tables.table_number`, `orders.invoice_no`, `daily_budgets.date`, `daily_sales_targets.date`, `settings.tenant_id`).

**Backup dulu — wajib:**
```bash
pg_dump -U <user> -d <db> -F c -f ~/backup-dinesync-$(date +%F-%H%M).dump
tar czf ~/backup-storage-$(date +%F-%H%M).tar.gz storage/app/public
php artisan migrate:status   # lihat migration yang belum jalan
```

Lalu pilih **SATU** opsi:

### Opsi A — Mulai bersih (HAPUS SEMUA DATA) — untuk demo/throwaway
```bash
php artisan migrate:fresh --seed --force
```
> ⚠️ **Drop SEMUA tabel** (order, penjualan, user, setting) lalu seed ulang (role, superadmin, 10 UMKM trial). Pakai HANYA jika data server sekarang boleh hilang.

### Opsi B — Pertahankan data + backfill (DISARANKAN kalau ada data penting)
```bash
php artisan migrate --force        # aman: tenant_id nullable, tidak ada baris terhapus
php artisan db:seed --class=RolePermissionSeeder --force   # role & permission global
php artisan db:seed --class=SuperAdminSeeder --force       # akun superadmin platform
```
> ⚠️ **Jebakan diam-diam:** setelah `migrate`, semua baris lama punya `tenant_id = NULL`. Karena global scope memfilter `WHERE tenant_id = <tenant aktif>`, **data lama jadi tidak terlihat** oleh user tenant (tidak ada error, hanya "hilang"). Superadmin (tenant_id NULL) tetap melihat semua.

**Backfill** — tetapkan data lama jadi milik 1 UMKM. Buat UMKM-nya dulu via menu **Tenant Management** (login superadmin) atau tinker, lalu:
```bash
php artisan tinker
```
```php
$t = App\Models\Tenant::firstOrCreate(['slug'=>'umkm-utama'], ['name'=>'UMKM Utama','is_active'=>true]);
foreach (['users','menus','categories','tables','orders','order_details','promos','queues',
          'expenses','shifts','suppliers','ingredients','ingredient_batches','menu_ingredients',
          'stock_movements','stock_opnames','stock_opname_details','settings',
          'daily_budgets','daily_sales_targets'] as $tbl) {
    DB::table($tbl)->whereNull('tenant_id')->update(['tenant_id' => $t->id]);
}
// JANGAN backfill superadmin -> biarkan tenant_id NULL:
App\Models\User::where('email','superadmin@gmail.com')->update(['tenant_id'=>null]);
```
> Pastikan tabel `settings` hanya punya **1 baris per tenant** sebelum/sesudah backfill.

> ⚠️ Kalau `migrate` error di langkah `dropUnique` (mis. nama index berbeda dari bawaan Laravel `<tabel>_<kolom>_unique`), cek `\d <tabel>` di psql dulu. Migration ini aman untuk penambahan kolom (ada guard `hasColumn`), tapi langkah unique mengasumsikan index lama bernama default.

---

## 3. Storage (gambar menu, avatar) — per-tenant
File disimpan di `storage/app/public/tenants/{tenantId}/...` di disk `public`.

```bash
php artisan storage:link                 # buat symlink public/storage -> storage/app/public
# kalau symlink lama rusak: rm public/storage && php artisan storage:link

sudo chown -R www-data:www-data storage bootstrap/cache
sudo chmod -R 775 storage bootstrap/cache
```
> URL gambar dibangun dari `APP_URL/storage/...` (lewat accessor `Menu::image_url`, `User::avatar_url`). Kalau `APP_URL` benar (bagian 1), gambar muncul. File lama (sebelum multi-tenant) ada di path datar (`menus/`, `user/avatar/`) → setelah update path-nya jadi `tenants/{id}/...`, jadi gambar lama bisa 404 sampai di-upload ulang (atau dipindah manual).

---

## 4. Cache & optimize (urutan penting)
```bash
php artisan optimize:clear   # clear config+route+view+event cache (lakukan DULU)
php artisan config:cache
php artisan route:cache
php artisan view:cache
```
> Selalu **clear dulu baru cache**. `config:cache` membekukan `.env` & `config/features.php`; kalau ganti `.env`/branch tanpa clear, nilai lama nyangkut. `view:cache` sekarang sudah lolos (view register Breeze yang rusak sudah dihapus).

---

## 5. Web server (subpath)
Pastikan document root mengarah ke **`public/`** dan subpath `/dine-sync-pos-v2` benar (alias/rewrite). Karena `APP_URL` sudah berisi subpath + `forceRootUrl`, Laravel yang menyusun URL-nya; tugas web server hanya mengarahkan `/dine-sync-pos-v2` → `public/index.php`.

---

## 6. Reverb (WebSocket: antrian, panggilan dapur, TV display)
**Satu** server Reverb melayani **semua** tenant — isolasi lewat nama channel (`public-queue.{tenantId}`, `public-display.{tenantId}`), bukan server terpisah. Jadi tidak ada konfigurasi Reverb per-UMKM; tambah UMKM tidak perlu setting Reverb baru.

### 6a. Jalankan Reverb permanen (supervisor)
```bash
sudo tee /etc/supervisor/conf.d/dinesync-reverb.conf > /dev/null <<'EOF'
[program:dinesync-reverb]
command=php /path/ke/dine-sync-pos-v2/artisan reverb:start --host=0.0.0.0 --port=8080
autostart=true
autorestart=true
user=www-data
redirect_stderr=true
stdout_logfile=/path/ke/dine-sync-pos-v2/storage/logs/reverb.log
stopwaitsecs=10
EOF
sudo supervisorctl reread && sudo supervisorctl update && sudo supervisorctl start dinesync-reverb
```

### 6b. Reverse proxy `wss` (WAJIB untuk HTTPS)
Browser tidak boleh konek langsung ke port 8080 di balik HTTPS. Reverse-proxy WebSocket Reverb (mis. Nginx) — Reverb default mendengarkan path Pusher (`/app/...`):
```nginx
# contoh Nginx (sesuaikan server block beoulve-dev.biz.id)
location /app {
    proxy_pass http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "Upgrade";
    proxy_set_header Host $host;
    proxy_read_timeout 60s;
}
```
> Klien Echo (di blade antrian/display) memakai `wsHost = window.location.hostname`, port `443`, `wss` saat bukan localhost — jadi mereka konek ke `wss://beoulve-dev.biz.id` lalu diproxy ke Reverb 8080. Kunci Reverb di-render dari `config('services.reverb.key')` (aman terhadap `config:cache`).

### 6c. Cek
```bash
sudo supervisorctl status dinesync-reverb
tail -f storage/logs/reverb.log
```
> Catatan: event broadcast pakai `ShouldBroadcastNow` (sinkron), jadi realtime **tidak** butuh queue worker. Kalau WebSocket tidak jalan, masalahnya di proses Reverb atau reverse-proxy/TLS — bukan di queue.

---

## 7. Queue worker (opsional untuk trial)
Driver `database`. Realtime sudah jalan tanpa ini; worker hanya untuk job/email di masa depan.
```bash
sudo tee /etc/supervisor/conf.d/dinesync-worker.conf > /dev/null <<'EOF'
[program:dinesync-worker]
command=php /path/ke/dine-sync-pos-v2/artisan queue:work database --sleep=3 --tries=3 --max-time=3600
autostart=true
autorestart=true
user=www-data
numprocs=1
redirect_stderr=true
stdout_logfile=/path/ke/dine-sync-pos-v2/storage/logs/worker.log
stopwaitsecs=3600
EOF
sudo supervisorctl reread && sudo supervisorctl update && sudo supervisorctl start dinesync-worker
```
Setiap deploy: `php artisan queue:restart`.

---

## 8. Octane (TIDAK dipakai sekarang)
`laravel/octane` terpasang & kode sudah Octane-safe (TenancyServiceProvider me-reset tenant tiap request), **tapi belum dikonfigurasi** (tidak ada `config/octane.php`/service). Server berjalan normal di PHP-FPM. **Jangan** `octane:start` kecuali Anda memang mau pindah ke Octane (perlu `octane:install` + proses manager; lalu tiap deploy `php artisan octane:reload`).

---

## 9. Versi Lite (server murah)
Sama persis, beda **branch** saja (DB & migration identik — tidak perlu `migrate:fresh` saat pindah full↔lite):
```bash
git checkout lite && git pull --ff-only
composer install --no-dev --optimize-autoloader
php artisan migrate --force
php artisan optimize:clear && php artisan config:cache && php artisan route:cache && php artisan view:cache
```
Fitur yang dimatikan di lite (inventory, HPP, self-order QR, antrian) diatur `config/features.php` (default off). Bisa dinyalakan per-fitur lewat `.env` (`FEATURE_*=true`) lalu `optimize:clear`. Detail: lihat **VERSIONS.md**.

---

## 10. Setelah deploy: verifikasi & keamanan
```bash
php artisan about                                  # cek env/url/driver efektif
php artisan tinker --execute="echo config('app.url');"
```
Login default (dari seeder):
- **Superadmin:** `superadmin@gmail.com` / `12qwaszx123!!@@##` (lihat semua UMKM)
- **Trial:** `owner{1..10}@trial.test` & `kasir{1..10}@trial.test` / `password`

> 🔐 **Segera ganti password superadmin** di server beneran. Pertimbangkan **tidak** menjalankan `TrialTenantsSeeder` di produksi (itu bikin 10 UMKM dummy, dan tidak idempoten — jalan 2x error karena slug bentrok).

---

## 11. Troubleshooting cepat
| Gejala | Sebab & solusi |
|--------|----------------|
| Semua link/aset/QR 404 atau mixed-content | `APP_URL` salah (kurang subpath/https). Betulkan → `optimize:clear` → `config:cache`. |
| Data lama "hilang" setelah migrate | Baris lama `tenant_id=NULL`. Lakukan **backfill** (bagian 2B). |
| WebSocket (antrian/TV) tak konek | Proses Reverb mati atau reverse-proxy `wss` belum ada (bagian 6). Cek `storage/logs/reverb.log`. |
| Ganti `.env`/branch tapi tidak berubah | Lupa `php artisan optimize:clear` sebelum `config:cache`. |
| Gambar menu/avatar 404 | `php artisan storage:link` + cek `APP_URL`. File lama (pra-tenant) perlu dipindah ke `tenants/{id}/`. |
| `view:cache` error komponen | Sudah diperbaiki (view register Breeze dihapus). Pastikan branch terbaru. |
| `migrate` error di `dropUnique` | Nama index lama beda dari default; cek `\d <tabel>` di psql. |

---

## 12. Checklist update singkat
- [ ] `pg_dump` + backup `storage/` (kalau migrasi besar)
- [ ] `git pull` (branch yang benar: `main`=full / `lite`=murah)
- [ ] `composer install --no-dev --optimize-autoloader`
- [ ] `php artisan migrate --force` (+ backfill bila perlu)
- [ ] `php artisan storage:link`
- [ ] `php artisan optimize:clear` → `config:cache` → `route:cache` → `view:cache`
- [ ] restart Reverb + `queue:restart`
- [ ] cek `php artisan about`, buka aplikasi, login superadmin
