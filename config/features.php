<?php

/*
|--------------------------------------------------------------------------
| Feature Flags — VERSI LITE (murah)
|--------------------------------------------------------------------------
| Di branch "lite" semua fitur "mahal" default MATI. Bisa dinyalakan lewat
| .env per-deploy tanpa ubah kode. Di branch "full" file ini tidak ada
| (semua fitur selalu aktif).
|
|  inventory  : Bahan, Supplier, Stok In, Stok Opname, Resep di menu
|  hpp        : Kartu HPP/Laba di dashboard + kolom HPP di report
|  self_order : Pemesanan mandiri pelanggan via QR (scan/menu/checkout)
|  queue      : Antrian + Kiosk + TV Display
*/

return [
    'inventory'  => env('FEATURE_INVENTORY', false),
    'hpp'        => env('FEATURE_HPP', false),
    'self_order' => env('FEATURE_SELF_ORDER', false),
    'queue'      => env('FEATURE_QUEUE', false),
];
