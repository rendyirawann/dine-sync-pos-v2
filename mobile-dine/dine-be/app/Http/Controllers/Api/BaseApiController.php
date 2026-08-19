<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Controllers\Api\Concerns\ApiResponse;
use OpenApi\Attributes as OA;

#[OA\Info(
    version: '1.0.0',
    title: 'DineSync POS — Mobile API',
    description: <<<'TXT'
REST API untuk aplikasi mobile **DineSync POS** (dine-fe / Flutter).
Menyediakan seluruh modul yang ada di aplikasi web: Kasir, Dapur, Antrian, Shift,
Data Master, Finance (Expense/Stok/Opname), Report, Profil, Setting, dan Tenant.

### Autentikasi
1. `POST /api/v1/auth/login` → dapatkan `token`.
2. Kirim header `Authorization: Bearer {token}` pada endpoint lain.

### Multi-tenant
Data otomatis ter-filter berdasarkan `tenant_id` user yang login.
Superadmin (tanpa tenant) dapat menargetkan satu UMKM lewat header `X-Tenant-ID`.

### Bentuk Response
Semua response memakai struktur:
`{ "success": true, "message": "...", "data": ... }` — dan `meta` bila endpoint berpaginasi.
TXT
)]
#[OA\Server(url: L5_SWAGGER_CONST_HOST, description: 'Server API')]
#[OA\SecurityScheme(
    securityScheme: 'sanctum',
    type: 'http',
    scheme: 'bearer',
    bearerFormat: 'Token',
    description: 'Token dari endpoint login (Laravel Sanctum).'
)]
#[OA\Tag(name: 'Auth', description: 'Login, logout, profil singkat, ganti password')]
#[OA\Tag(name: 'Dashboard', description: 'Ringkasan omzet, HPP, laba, grafik, menu terlaris')]
#[OA\Tag(name: 'Kasir', description: 'Peta meja, buat order, pembayaran, kosongkan meja, struk')]
#[OA\Tag(name: 'Dapur', description: 'Kitchen display: antrian masak, potong stok FEFO, panggil ulang')]
#[OA\Tag(name: 'Antrian', description: 'Antrian pelanggan: ambil nomor, panggil, status, layar TV')]
#[OA\Tag(name: 'Shift', description: 'Buka/tutup shift kasir dan riwayatnya')]
#[OA\Tag(name: 'Data Master', description: 'Kategori, Menu, Meja, Promo, Bahan, Supplier')]
#[OA\Tag(name: 'Finance', description: 'Pengeluaran, target & budget harian, stok masuk, stok opname')]
#[OA\Tag(name: 'Report', description: 'Laporan penjualan dan menu terlaris')]
#[OA\Tag(name: 'Profil', description: 'Profil saya, avatar, aktivitas, sesi login')]
#[OA\Tag(name: 'Setting', description: 'Pengaturan toko & pajak')]
#[OA\Tag(name: 'Manajemen', description: 'User, Role/Permission, Tenant (UMKM)')]
#[OA\Tag(name: 'Publik', description: 'Tanpa login: self-order QR pelanggan, kiosk, display')]
abstract class BaseApiController extends Controller
{
    use ApiResponse;
}
