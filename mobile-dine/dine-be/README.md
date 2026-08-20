# dine-be — DineSync POS Mobile API

REST API untuk aplikasi mobile **DineSync POS** (dipakai oleh [dine-fe](https://github.com/rendyirawann/dine-fe)).
Menyediakan seluruh modul yang ada di aplikasi web POS: Kasir, Dapur, Antrian, Shift,
Data Master, Finance, Report, Profil, Setting, dan Tenant.

- **Stack:** Laravel 12 · Sanctum (token) · l5-swagger (OpenAPI) · PostgreSQL
- **Opsional produksi:** Octane (RoadRunner) · Redis · Reverb (WebSocket)
- **Dokumentasi API:** `/api/documentation` (Swagger UI)

> **Penting:** dine-be memakai **database yang sama** dengan aplikasi web
> `dine-sync-pos-v2`, sehingga data mobile dan web menyatu. API ini **tidak**
> membuat migration baru — skema tetap dimiliki project web.

---

## 1. Instalasi

```bash
composer install
cp .env.example .env
php artisan key:generate
```

Arahkan `.env` ke database yang sama dengan web POS:

```dotenv
APP_URL=http://127.0.0.1:8001

DB_CONNECTION=pgsql
DB_HOST=127.0.0.1
DB_PORT=5432
DB_DATABASE=dinesync_pos      # sama dengan web
DB_USERNAME=...
DB_PASSWORD=...

# Swagger
L5_SWAGGER_CONST_HOST=http://127.0.0.1:8001
```

Jalankan:

```bash
php artisan serve --host=127.0.0.1 --port=8001
php artisan l5-swagger:generate      # bila dokumentasi perlu di-refresh
```

Buka **http://127.0.0.1:8001/api/documentation**

---

## 2. Autentikasi

1. `POST /api/v1/auth/login` — body `{ "login": "...", "password": "..." }`
   (`login` menerima email / no_wa / nama, sama seperti web).
2. Kirim `Authorization: Bearer {token}` pada endpoint lain.

Multi-tenant: data otomatis ter-filter per `tenant_id` milik user yang login.
Superadmin (tanpa tenant) bisa menargetkan satu UMKM lewat header `X-Tenant-ID`.

Bentuk response seragam:

```json
{ "success": true, "message": "...", "data": ... }
```

Endpoint berpaginasi menambahkan `meta` (`current_page`, `last_page`, `total`, `has_more`).

---

## 3. Cakupan modul

| Modul | Contoh endpoint |
|---|---|
| Auth & Profil | `auth/login`, `auth/me`, `profile`, `profile/avatar` |
| Dashboard | `dashboard/summary`, `dashboard/chart`, `dashboard/top-menus` |
| Kasir | `tables` (peta meja), `orders` (buat), `orders/{id}/pay`, `tables/{id}/clear` |
| Dapur | `kitchen/orders`, `kitchen/items/{id}/status`, `kitchen/recipe/{id}` |
| Antrian | `queues`, `queues/take`, `queues/{id}/call`, `queues/display` |
| Shift | `shifts/current`, `shifts/open`, `shifts/close` |
| Data Master | `categories`, `menus`, `tables`, `promos`, `ingredients`, `suppliers` |
| Finance | `expenses`, `budget`, `stocks` (batch FIFO), `stock-opname` |
| Report | `reports/sales`, `reports/items` |
| Setting & Manajemen | `settings`, `users`, `roles`, `tenants` |

Logika bisnis disamakan dengan web: pemotongan stok **FEFO**, perhitungan **HPP**
dari harga batch, urutan kalkulasi `subtotal → diskon → pajak → grand total`,
serta penomoran antrian `A/B/C` berdasarkan jumlah pax.

---

## 4. Catatan

- Pembayaran **Midtrans dinonaktifkan** (mode trial) — pembayaran memakai tunai / bayar di kasir.
- Realtime (Reverb) sudah tersedia di sisi server; klien mobile belum berlangganan channel.
- Upload gambar dari mobile belum diaktifkan (endpoint baca gambar sudah ada).
