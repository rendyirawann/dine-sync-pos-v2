<?php

use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Web Routes — dine-be adalah API-only backend untuk aplikasi mobile.
|--------------------------------------------------------------------------
| Tidak ada halaman web di sini. Root diarahkan ke dokumentasi Swagger.
| Seluruh endpoint ada di routes/api.php (prefix /api/v1).
*/

Route::get('/', fn () => redirect('/api/documentation'));

Route::get('/health', fn () => response()->json([
    'status' => 'ok',
    'app' => config('app.name'),
    'time' => now()->toIso8601String(),
]));
