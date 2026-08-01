# Deploy di IP + Subfolder (http://10.0.22.20/dine-sync-pos-v2)

Panduan menaruh aplikasi di **IP tanpa domain, tanpa HTTPS**, di dalam **subfolder**
`/dine-sync-pos-v2`, dan **memastikan subfolder tidak hilang** di semua URL/aset —
berjalan sama di **lokal (XAMPP)** maupun **server**.

> Inti masalah subfolder + IP http sudah **diperbaiki di kode** (commit ini):
> `AppServiceProvider` tidak lagi memaksa HTTPS bila `APP_URL` http, dan Echo/Reverb
> mengikuti skema halaman. Jadi Anda tinggal setel web server + `.env` seperti di bawah.

---

## 0. Cara kerja (kenapa subfolder tetap ada)
- Di **production**, `AppServiceProvider` memanggil `URL::forceRootUrl(APP_URL)` → SEMUA
  `route()`, `url()`, `asset()`, dan `<base href>` dibangun dari `APP_URL`. Jadi kalau
  `APP_URL` = `http://10.0.22.20/dine-sync-pos-v2`, subfolder **selalu** ikut.
- Skema **mengikuti APP_URL** — `http` tetap `http` (tidak dipaksa `https`).
- Di **lokal** (`APP_ENV=local`), tidak ada pemaksaan; Laravel auto-deteksi base path dari
  request, jadi subfolder juga ikut selama web server mengarahkan subfolder ke `public/`.

Sudah **terbukti** (production + `APP_URL=http://10.0.22.20/dine-sync-pos-v2`):
```
url(/)     = http://10.0.22.20/dine-sync-pos-v2
route(...) = http://10.0.22.20/dine-sync-pos-v2/admin/login
asset(...) = http://10.0.22.20/dine-sync-pos-v2/assets/css/style.bundle.css
```

---

## 1. Web server — arahkan subfolder ke `public/`
Titik akses `http://10.0.22.20/dine-sync-pos-v2` HARUS menunjuk ke folder **`public/`**
project (bukan root project). Pilih salah satu:

### A. Apache Alias (paling bersih & aman) — Linux/XAMPP
Tambahkan di config Apache (mis. `/etc/apache2/conf-available/dinesync.conf` atau
`httpd-vhosts.conf` di XAMPP):
```apache
Alias /dine-sync-pos-v2 "/var/www/dine-sync-pos-v2/public"

<Directory "/var/www/dine-sync-pos-v2/public">
    Options -Indexes +FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
```
```bash
sudo a2enmod rewrite
sudo systemctl restart apache2      # XAMPP: restart Apache dari panel
```
> `AllowOverride All` wajib supaya `public/.htaccess` (front controller) jalan.

### B. Project diletakkan langsung di docroot (gaya XAMPP htdocs)
Kalau project ada di `htdocs/dine-sync-pos-v2` dan diakses `.../dine-sync-pos-v2`, buat
`.htaccess` di **root project** untuk melempar ke `public/`:
```apache
# dine-sync-pos-v2/.htaccess
<IfModule mod_rewrite.c>
    RewriteEngine On
    RewriteRule ^(.*)$ public/$1 [L]
</IfModule>
```
> Cara A lebih disarankan (root project tidak ikut terekspos). Cara B praktis untuk XAMPP.

---

## 2. `.env` untuk IP http + subfolder
```dotenv
APP_NAME="DineSync POS"
APP_ENV=production
APP_DEBUG=false
APP_URL=http://10.0.22.20/dine-sync-pos-v2      # WAJIB: http + IP + subfolder, tanpa slash akhir
APP_TIMEZONE=Asia/Jakarta
LOG_LEVEL=error

# Database (PostgreSQL) — lihat DEPLOYMENT.md untuk buat DB & migrasi
DB_CONNECTION=pgsql
DB_HOST=127.0.0.1
DB_PORT=5432
DB_DATABASE=dinesync_pos
DB_USERNAME=dinesync
DB_PASSWORD=__ganti__

# Session/cache/queue: database (sederhana). Bisa Redis (lihat DEPLOY-PRODUCTION.md).
SESSION_DRIVER=database
CACHE_STORE=database
QUEUE_CONNECTION=database

# 🔴 WAJIB false untuk http — kalau true, cookie tidak terkirim di http -> LOGIN GAGAL
SESSION_SECURE_COOKIE=false

# Reverb (opsional; realtime antrian/dapur/TV). Untuk LAN, browser konek langsung ke :8080
BROADCAST_CONNECTION=reverb
REVERB_APP_ID=__id__
REVERB_APP_KEY=__key__
REVERB_APP_SECRET=__secret__
REVERB_HOST=127.0.0.1
REVERB_PORT=8080
REVERB_SCHEME=http

# Midtrans OFF untuk trial
MIDTRANS_IS_PRODUCTION=false
```

> ⚠️ Tiga hal yang paling sering bikin subfolder hilang / login gagal:
> 1. `APP_URL` kurang `/dine-sync-pos-v2` atau pakai `https` → betulkan.
> 2. `SESSION_SECURE_COOKIE=true` di http → login tak bisa (cookie tak terkirim).
> 3. Lupa `optimize:clear` setelah ubah `.env` → nilai lama nyangkut di cache.

---

## 3. Langkah deploy
```bash
cd /var/www/dine-sync-pos-v2            # atau path project Anda

git pull --ff-only origin main          # full  (atau: origin lite = versi murah)
composer install --no-dev --optimize-autoloader

# APP_KEY hanya jika belum ada:
# php artisan key:generate --force

php artisan migrate --force             # lihat DEPLOYMENT.md utk data lama (fresh vs backfill)
php artisan storage:link                # symlink public/storage (disajikan di /dine-sync-pos-v2/storage)

# Bersihkan lalu cache ulang (urut!)
php artisan optimize:clear
php artisan config:cache
php artisan route:cache
php artisan view:cache

# Izin (Linux)
sudo chown -R www-data:www-data storage bootstrap/cache
sudo chmod -R 775 storage bootstrap/cache
```
> `npm run build` TIDAK perlu (aset Metronic statis di `public/assets/`).

---

## 4. VERIFIKASI subfolder (wajib, sebelum dianggap beres)
Jalankan di server, pastikan semua URL mengandung `/dine-sync-pos-v2` dan `http`:
```bash
php artisan tinker --execute="echo url('/').PHP_EOL; echo route('login').PHP_EOL; echo asset('assets/css/style.bundle.css').PHP_EOL;"
```
Output yang BENAR:
```
http://10.0.22.20/dine-sync-pos-v2
http://10.0.22.20/dine-sync-pos-v2/admin/login
http://10.0.22.20/dine-sync-pos-v2/assets/css/style.bundle.css
```
Lalu buka `http://10.0.22.20/dine-sync-pos-v2/admin/login` di browser:
- Klik kanan → View Source → pastikan `<base href="http://10.0.22.20/dine-sync-pos-v2/">`
  dan `<link>/<script>` menunjuk ke `.../dine-sync-pos-v2/assets/...` (bukan langsung ke root IP).
- Coba login (kalau login memantul balik / cookie hilang → cek `SESSION_SECURE_COOKIE=false`).

---

## 5. Lokal (XAMPP) — biar sama-sama jalan
- Biarkan `APP_ENV=local` di `.env` lokal (Laravel auto-deteksi subfolder dari request).
- Akses lewat URL yang mengarah ke `public/`. Dua cara:
  - Alias/vhost lokal ke `.../dine-sync-pos-v2/public` (mirip bagian 1A), akses
    `http://localhost/dine-sync-pos-v2`, **atau**
  - `.htaccess` root (bagian 1B), akses `http://localhost/myProject/dine-sync-pos-v2`.
- Karena `APP_ENV=local` tidak memaksa root URL, subfolder ikut otomatis dari request.
  (Kalau mau menyamakan persis dengan server, set `APP_URL` lokal ke URL subfolder lokal.)

> Jadi: **server** pakai `APP_ENV=production` + `APP_URL` subfolder (dikunci), **lokal**
> pakai `APP_ENV=local` (auto). Dua-duanya menjaga subfolder.

---

## 6. Realtime (Reverb) di IP http — opsional
Echo di halaman antrian/TV kini **otomatis** ikut skema halaman:
- http (lokal/IP) → konek `ws://<host>:8080` langsung ke Reverb.
- https (domain) → `wss://<host>:443` (butuh reverse-proxy, lihat DEPLOY-PRODUCTION.md).

Untuk IP LAN, cukup jalankan Reverb dan buka port 8080 (tanpa proxy):
```bash
php artisan reverb:start --host=0.0.0.0 --port=8080   # jadikan permanen via supervisor
```
Pastikan firewall server mengizinkan port 8080 dari jaringan yang mengakses.

---

## 7. Troubleshooting cepat
| Gejala | Sebab & solusi |
|--------|----------------|
| Aset/CSS 404, tampilan berantakan | Subfolder hilang di URL aset. Cek `APP_URL` benar → `optimize:clear` → `config:cache`. Pastikan web server mengarah ke `public/` (bagian 1). |
| Login memantul / tidak masuk | `SESSION_SECURE_COOKIE=true` di http. Set `false`. |
| Semua link ke `http://10.0.22.20/...` (tanpa subfolder) | `APP_URL` kurang subfolder, atau web server menyajikan root project (bukan `public/`). |
| Muncul `https://...` padahal server http | Pastikan sudah pakai kode terbaru (fix `forceScheme`) dan `APP_URL` diawali `http://`. |
| `403/404` di semua route kecuali beranda | `AllowOverride All` belum aktif / `mod_rewrite` mati → `.htaccess` tidak jalan. |
| Ganti `.env` tak berpengaruh | Lupa `php artisan optimize:clear` sebelum `config:cache`. |
