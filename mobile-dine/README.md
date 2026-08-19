# mobile-dine — Aplikasi Mobile DineSync POS

Dua project yang saling melengkapi:

| Folder | Isi | Teknologi |
|--------|-----|-----------|
| **`dine-be`** | Backend **API-only** untuk mobile | Laravel 12 · Sanctum · Swagger (l5-swagger) · Octane · Redis · PostgreSQL |
| **`dine-fe`** | Aplikasi mobile | Flutter 3.44 · Riverpod · Dio · go_router |

`dine-fe` **tidak** menyentuh database — semua data lewat REST API `dine-be`.
`dine-be` memakai **database yang sama** dengan web `dine-sync-pos-v2`, sehingga data mobile & web menyatu.

---

## 0. Jalan cepat — satu klik

Dari root project jalankan **`start-dev.bat`**. Semua service dibuka dalam
**SATU jendela Windows Terminal berisi 4 tab**, lalu Brave terbuka otomatis:

| Tab | Service | Alamat |
|-----|---------|--------|
| `Web-8000` | Aplikasi web (dine-sync-pos-v2) | http://127.0.0.1:8000/admin/login |
| `Reverb-8080` | WebSocket (antrian/dapur/TV) | ws://127.0.0.1:8080 |
| `API-8001` | REST API mobile (dine-be) | http://127.0.0.1:8001/api/documentation |
| `Mobile-8085` | Aplikasi Flutter (debug web di Brave) | http://127.0.0.1:8085 |

- Tab **Mobile** butuh ~30–60 detik saat compile pertama; di tab itu `r` = hot reload, `R` = restart, `q` = keluar.
- Hanya ingin menjalankan aplikasi mobile-nya saja (API sudah hidup)?
  Jalankan **`mobile-dine/dine-fe/debug-web.bat`**.
  Bisa diberi argumen: `debug-web.bat 9000 http://192.168.1.10:8001` (port & alamat API lain).
- Bila Windows Terminal tidak ada, script otomatis membuka jendela CMD terpisah.
- CORS sudah aktif di API (`Access-Control-Allow-Origin: *` untuk `/api/*`), jadi
  Flutter web di port berbeda bisa memanggil API **tanpa proxy**.

---

## 1. Arsitektur singkat

```
   Flutter (dine-fe)                dine-be (Laravel API)              DB & Layanan
 ┌────────────────────┐        ┌──────────────────────────┐      ┌──────────────────────┐
 │ Riverpod + Dio     │  HTTPS │ /api/v1/*                │      │ PostgreSQL (sama     │
 │ Bearer token       ├───────►│ Sanctum token auth       ├─────►│ dengan web v2)       │
 │ Secure storage     │        │ IdentifyTenant (scope)   │      │ Redis (cache/queue)  │
 │ Tema Metronic 8.2  │◄───────┤ Swagger UI /api/document.│      │ Reverb (WebSocket)   │
 └────────────────────┘  JSON  └──────────────────────────┘      └──────────────────────┘
```

- **Multi-tenant otomatis**: tenant diambil dari user pemilik token; seluruh query domain ter-filter `tenant_id` (global scope). Superadmin dapat menargetkan satu UMKM lewat header `X-Tenant-ID`.
- **Bentuk response seragam**: `{ success, message, data }` (+ `meta` untuk paginasi) — sehingga klien tidak pernah menerima HTML.
- **Logika bisnis direplikasi 1:1 dari web**: format invoice, urutan hitung (subtotal → diskon promo → pajak setelah diskon → grand total), pemotongan stok **FEFO** + HPP, roll-up status dapur, perhitungan selisih shift, penomoran antrian A/B/C.

---

## 2. Menjalankan `dine-be` (API)

### 2.1 Langkah WAJIB pertama kali — migrasi
Database `dinesync_pos_v2` belum punya tabel `tenants`, kolom `tenant_id`, dan `personal_access_tokens`.
Tanpa ini, login API **tidak akan bisa** jalan.

```bash
cd mobile-dine/dine-be
php artisan migrate            # menambah: tenants, tenant_id (nullable), personal_access_tokens
```

> Aman & additive: `tenant_id` nullable, tidak ada data terhapus. Baris lama akan ber-`tenant_id` NULL —
> lihat **DEPLOYMENT.md** (bagian backfill) di project web bila ingin memetakan data lama ke satu UMKM.

Bila belum ada UMKM & user sama sekali:
```bash
php artisan db:seed --class=RolePermissionSeeder
php artisan db:seed --class=SuperAdminSeeder
php artisan db:seed --class=TrialTenantsSeeder   # 10 UMKM trial (opsional)
```

### 2.2 Jalankan server
```bash
php artisan serve --port=8001
```
- Swagger UI  : http://localhost:8001/api/documentation
- Health check: http://localhost:8001/health

> Windows tidak punya ekstensi `pcntl`, jadi **Octane tidak bisa jalan lokal** — pakai `artisan serve`.
> Di server Linux gunakan Octane (`config/octane.php` sudah tersedia, lihat DEPLOY-PRODUCTION.md).

### 2.3 Regenerate dokumentasi Swagger
```bash
php artisan l5-swagger:generate
```

### 2.4 `.env` penting
```dotenv
APP_URL=http://localhost:8001
DB_CONNECTION=pgsql            # DB SAMA dengan web v2
DB_DATABASE=dinesync_pos_v2
CACHE_STORE=redis              # Redis (client: predis, tanpa ekstensi php-redis)
SESSION_DRIVER=redis
QUEUE_CONNECTION=redis
REDIS_CLIENT=predis
SANCTUM_TOKEN_EXPIRATION=null  # token mobile tidak kedaluwarsa
L5_SWAGGER_CONST_HOST=http://localhost:8001
OCTANE_SERVER=roadrunner
```

---

## 3. Menjalankan `dine-fe` (Flutter)

```bash
cd mobile-dine/dine-fe
flutter pub get
flutter run
```

### Alamat API
Default otomatis:
- Emulator Android → `http://10.0.2.2:8001`
- Lainnya → `http://127.0.0.1:8001`

Cara mengubah:
1. **Saat run** (paling rapi):
   ```bash
   flutter run --dart-define=API_BASE_URL=http://10.0.22.20/dine-be/public
   ```
2. **Dari dalam aplikasi**: di layar login ada tombol `Server: ...` untuk mengganti alamat tanpa rebuild.

> Alamat yang dimasukkan adalah **root server tanpa `/api/v1`** (aplikasi menambahkannya sendiri).

### Login uji
| Peran | Akun | Password |
|---|---|---|
| Superadmin | `superadmin@gmail.com` | `12qwaszx123!!@@##` |
| Owner UMKM | `owner1@trial.test` … `owner10@trial.test` | `password` |
| Kasir | `kasir1@trial.test` … `kasir10@trial.test` | `password` |

---

## 4. Modul yang tersedia (mengikuti web)

| Modul | Endpoint utama | Layar mobile |
|---|---|---|
| Auth | `POST /auth/login`, `GET /auth/me`, `POST /auth/logout`, `change-password` | Login, Profil |
| Dashboard | `/dashboard/{summary,chart,top-menus,unavailable-menus,hpp-details,daily}` | Beranda (kartu + grafik + widget harian) |
| Kasir | `/kasir/{tables,tables/{id}/detail,order-context,orders,orders/{id}/pay,tables/{id}/clear,orders/{id}/receipt}` | Peta Meja, Buat Pesanan, Struk |
| Shift | `/shifts/{current,open,{id}/close,history}` | Shift Kasir |
| Dapur | `/kitchen/{orders,items/{id}/recipe,items/{id}/status,orders/{id}/status,orders/{id}/recall}` | Kitchen Display (2 tab) |
| Antrian | `/queues`, `/queues/{id}/call`, `/queues/{id}/status` | Antrian (+ cooldown 15 detik) |
| Data Master | `/categories`, `/menus` (+`/recipes`), `/tables`, `/promos`, `/ingredients`, `/suppliers` | 6 layar CRUD |
| Finance | `/expenses`, `/finance/daily-settings`, `/finance/budget-history`, `/stock-batches`, `/stock-opname/*` | Pengeluaran, Stok Masuk, Opname |
| Report | `/reports/sales`, `/reports/items` | Laporan (2 tab) |
| Setting | `/settings` | Pengaturan Toko |
| Manajemen | `/users` (+ban), `/roles`, `/permissions`, `/tenants` (+toggle) | (via API; layar menyusul) |
| Publik (tanpa login) | `/public/scan/{uuid}`, `/public/menu/{uuid}`, `/public/menu/{uuid}/checkout`, `/public/order/{uuid}`, `/public/{tenant}/queue/{display,take}`, `/public/{tenant}/store` | untuk kiosk/QR pelanggan |

Total: **78 path · 110 operasi**, semuanya terdokumentasi di Swagger.

---

## 5. Hak akses (sama seperti web)

Response login/`me` menyertakan `roles`, `permissions`, dan `is_superadmin`. Aplikasi menyembunyikan
menu memakai `user.can('view_kasir')` dst — persis seperti `@can(...)` di Blade.

| Permission | Superadmin | admin | kasir | kitchen |
|---|---|---|---|---|
| `view_kasir` | ✅ | ✅ | ✅ | — |
| `view_kitchen` | ✅ | ✅ | ✅ | ✅ |
| `view_queue` | ✅ | ✅ | ✅ | ✅ |
| `view_data_master` | ✅ | ✅ | — | — |
| `view_finance` | ✅ | ✅ | ✅ | — |
| `view_report` | ✅ | ✅ | ✅ | — |
| `view_resources` | ✅ | — | — | — |

Bottom navigation di aplikasi otomatis menyesuaikan (kitchen hanya melihat Beranda/Dapur/Antrian/Lainnya).

---

## 6. Tema mobile

Warna & font diambil dari web (Metronic 8.2) agar satu keluarga:

| Token | Light | Dark |
|---|---|---|
| primary | `#1B84FF` | `#006AE6` |
| success | `#17C653` | `#00A261` |
| danger | `#F8285A` | `#E42855` |
| warning | `#F6C000` | `#C59A00` |
| latar halaman | `#F6F6F6` | `#0F1014` |
| kartu | `#FFFFFF` | `#15171C` |

Font **Inter**; bobot mengikuti web (`semibold`→w500, `bold`→w600, `bolder`→w700).
Ukuran huruf & komponen disetel ulang untuk layar HP. Dark mode tersedia (System/Terang/Gelap).

---

## 7. Catatan & batasan saat ini

- **Midtrans dinonaktifkan** (trial) — metode pembayaran hanya `cash` & `pay_later`, sama seperti web.
- **Upload gambar dari mobile belum ada** (butuh `image_picker`): ubah foto menu/avatar lewat web dulu.
- **Realtime (Reverb) belum dipasang di Flutter** — layar dapur & antrian memakai auto-refresh (30 detik) dan pull-to-refresh. Endpoint `/meta` sudah mengirim konfigurasi channel (`public-queue.{tenantId}`, `public-display.{tenantId}`) bila nanti ingin menambahkan `pusher_channels_flutter`.
- Layar **Manajemen** (User/Role/Tenant) belum dibuat di mobile; API-nya sudah lengkap.

---

## 8. Perintah yang sering dipakai

```bash
# dine-be
php artisan serve --port=8001
php artisan l5-swagger:generate
php artisan migrate
php artisan optimize:clear

# dine-fe
flutter pub get
flutter analyze
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8001
flutter build apk --release
```
