# Versi Full vs Lite

Aplikasi ini punya 2 versi yang dibedakan **per branch git**, tapi **DB-nya sama**
(skema/migration identik). Perbedaan hanya fitur yang aktif.

## Branch
| Branch | Versi | Fitur "mahal" |
|--------|-------|----------------|
| `main` / tag `full-version` | **Full** (mahal) | Semua aktif |
| `lite` | **Lite** (murah) | Dimatikan (lihat di bawah) |

## Fitur yang DIMATIKAN di Lite
Dikontrol oleh `config/features.php` (default **off** di branch lite):

| Flag | Mematikan |
|------|-----------|
| `inventory`  | Bahan, Supplier, Stok In, Stok Opname, tab Resep di menu |
| `hpp`        | Kartu "Total HPP" & "Laba Bersih" di dashboard + kolom HPP di Sales/Item Report |
| `self_order` | Pemesanan mandiri pelanggan via QR (scan/menu/checkout) + tombol Cetak QR meja |
| `queue`      | Antrian + Kiosk + TV Display |

## Cara kerja (kenapa aman & DB sama)
- **Route tetap terdaftar**, tapi diberi middleware `feature:<flag>` yang me-**404**-kan akses bila flag off. Jadi `route()` di mana pun tidak pernah error, tapi URL fitur tidak bisa diakses.
- **Navigasi/UI** dibungkus `@if (config('features.<flag>'))` sehingga menu/kartu/kolom hilang.
- **Migration TIDAK diubah** — semua tabel tetap ada (tabel inventory yang kosong tidak mengganggu). Maka pindah `full ↔ lite` **tidak perlu** `migrate:fresh`.
- **Seeder sama** — `TrialTenantsSeeder` memang tidak mengisi data inventory, jadi lite bersih otomatis.

## Mengaktifkan kembali fitur tertentu di Lite (opsional, tanpa ubah kode)
Set di `.env` lalu `php artisan config:clear`:
```
FEATURE_INVENTORY=true
FEATURE_HPP=true
FEATURE_SELF_ORDER=true
FEATURE_QUEUE=true
```

## Deploy
- **Server mahal:** checkout `main` (atau tag `full-version`).
- **Server murah:** checkout `lite`. Jalankan `php artisan config:clear` setelah deploy.
- Migrasi & seeder sama untuk keduanya: `php artisan migrate` (+ `db:seed` bila perlu).

## Catatan teknis
- Logika backend stok/HPP tetap ada tapi jadi no-op di lite (menu tanpa resep → HPP 0, tidak ada pengurangan stok). Tidak ada error.
- Untuk meng-update fitur bersama (mis. perbaikan bug kasir), kerjakan di `main` lalu `git cherry-pick`/merge ke `lite`.
