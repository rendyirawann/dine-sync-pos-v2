<?php

use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\CategoryController;
use App\Http\Controllers\Api\V1\CustomerController;
use App\Http\Controllers\Api\V1\DashboardController;
use App\Http\Controllers\Api\V1\ExpenseController;
use App\Http\Controllers\Api\V1\IngredientController;
use App\Http\Controllers\Api\V1\KasirController;
use App\Http\Controllers\Api\V1\KitchenController;
use App\Http\Controllers\Api\V1\MenuController;
use App\Http\Controllers\Api\V1\MetaController;
use App\Http\Controllers\Api\V1\ProfileController;
use App\Http\Controllers\Api\V1\PromoController;
use App\Http\Controllers\Api\V1\QueueController;
use App\Http\Controllers\Api\V1\ReportController;
use App\Http\Controllers\Api\V1\RoleController;
use App\Http\Controllers\Api\V1\SettingController;
use App\Http\Controllers\Api\V1\ShiftController;
use App\Http\Controllers\Api\V1\StockController;
use App\Http\Controllers\Api\V1\StockOpnameController;
use App\Http\Controllers\Api\V1\SupplierController;
use App\Http\Controllers\Api\V1\TableController;
use App\Http\Controllers\Api\V1\TenantController;
use App\Http\Controllers\Api\V1\UserController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| API v1 — dipakai aplikasi mobile (dine-fe / Flutter)
|--------------------------------------------------------------------------
| Semua endpoint diawali /api/v1. Autentikasi memakai token Sanctum
| (header: Authorization: Bearer {token}).
| Tenant aktif otomatis di-set middleware IdentifyTenant dari user token.
*/

Route::prefix('v1')->name('api.')->group(function () {

    /* ================= PUBLIK (tanpa login) ================= */
    Route::post('auth/login', [AuthController::class, 'login'])->name('auth.login')
        ->middleware('throttle:10,1');

    Route::prefix('public')->name('public.')->group(function () {
        // Self-order pelanggan via QR meja
        Route::get('scan/{uuid}', [CustomerController::class, 'scan'])->name('scan');
        Route::get('menu/{uuid}', [CustomerController::class, 'menu'])->name('menu');
        Route::post('menu/{uuid}/checkout', [CustomerController::class, 'checkout'])->name('checkout');
        Route::get('order/{uuid}', [CustomerController::class, 'orderStatus'])->name('order');

        // Kiosk & TV display antrian (per tenant: slug atau id)
        Route::get('{tenant}/queue/display', [QueueController::class, 'display'])->name('queue.display');
        Route::post('{tenant}/queue/take', [QueueController::class, 'take'])->name('queue.take');
        Route::get('{tenant}/store', [CustomerController::class, 'store'])->name('store');
    });

    /* ================= BUTUH LOGIN ================= */
    Route::middleware(['auth:sanctum', 'forbid-banned-user'])->group(function () {

        /* ---- Auth & Profil ---- */
        Route::get('auth/me', [AuthController::class, 'me'])->name('auth.me');
        Route::post('auth/logout', [AuthController::class, 'logout'])->name('auth.logout');
        Route::post('auth/logout-all', [AuthController::class, 'logoutAll'])->name('auth.logout-all');
        Route::post('auth/change-password', [AuthController::class, 'changePassword'])->name('auth.change-password');

        Route::get('profile', [ProfileController::class, 'show'])->name('profile.show');
        Route::put('profile', [ProfileController::class, 'update'])->name('profile.update');
        Route::post('profile/avatar', [ProfileController::class, 'updateAvatar'])->name('profile.avatar');
        Route::get('profile/activities', [ProfileController::class, 'activities'])->name('profile.activities');

        /* ---- Meta (enum & konstanta untuk dropdown Flutter) ---- */
        Route::get('meta', [MetaController::class, 'index'])->name('meta');

        /* ---- Dashboard (semua role) ---- */
        Route::prefix('dashboard')->name('dashboard.')->group(function () {
            Route::get('summary', [DashboardController::class, 'summary'])->name('summary');
            Route::get('chart', [DashboardController::class, 'chart'])->name('chart');
            Route::get('top-menus', [DashboardController::class, 'topMenus'])->name('top-menus');
            Route::get('unavailable-menus', [DashboardController::class, 'unavailableMenus'])->name('unavailable-menus');
            Route::get('hpp-details', [DashboardController::class, 'hppDetails'])->name('hpp-details');
            // Widget harian (target, omzet hari ini, budget, terpakai) seperti sidebar web
            Route::get('daily', [DashboardController::class, 'daily'])->name('daily');
        });

        /* ---- Setting toko (semua role bisa lihat; ubah butuh admin) ---- */
        Route::get('settings', [SettingController::class, 'show'])->name('settings.show');
        Route::put('settings', [SettingController::class, 'update'])->name('settings.update');

        /* ---- KASIR (view_kasir) ---- */
        Route::middleware('can:view_kasir')->prefix('kasir')->name('kasir.')->group(function () {
            Route::get('tables', [KasirController::class, 'tables'])->name('tables');
            Route::get('tables/{id}/detail', [KasirController::class, 'tableDetail'])->name('table-detail');
            Route::get('order-context/{table_id}', [KasirController::class, 'orderContext'])->name('order-context');
            Route::post('orders', [KasirController::class, 'storeOrder'])->name('orders.store');
            Route::post('orders/{id}/pay', [KasirController::class, 'payOrder'])->name('orders.pay');
            Route::post('tables/{id}/clear', [KasirController::class, 'clearTable'])->name('tables.clear');
            Route::get('orders', [KasirController::class, 'orders'])->name('orders.index');
            Route::get('orders/{id}', [KasirController::class, 'showOrder'])->name('orders.show');
            Route::get('orders/{id}/receipt', [KasirController::class, 'receipt'])->name('orders.receipt');
        });

        /* ---- SHIFT (view_kasir) ---- */
        Route::middleware('can:view_kasir')->prefix('shifts')->name('shifts.')->group(function () {
            Route::get('current', [ShiftController::class, 'current'])->name('current');
            Route::post('open', [ShiftController::class, 'open'])->name('open');
            Route::post('{id}/close', [ShiftController::class, 'close'])->name('close');
            Route::get('history', [ShiftController::class, 'history'])->name('history');
        });

        /* ---- DAPUR (view_kitchen) ---- */
        Route::middleware('can:view_kitchen')->prefix('kitchen')->name('kitchen.')->group(function () {
            Route::get('orders', [KitchenController::class, 'orders'])->name('orders');
            Route::get('items/{id}/recipe', [KitchenController::class, 'recipe'])->name('items.recipe');
            Route::post('items/{id}/status', [KitchenController::class, 'updateItemStatus'])->name('items.status');
            Route::post('orders/{id}/status', [KitchenController::class, 'updateOrderStatus'])->name('orders.status');
            Route::post('orders/{id}/recall', [KitchenController::class, 'recall'])->name('orders.recall');
        });

        /* ---- ANTRIAN (view_queue) ---- */
        Route::middleware('can:view_queue')->prefix('queues')->name('queues.')->group(function () {
            Route::get('/', [QueueController::class, 'index'])->name('index');
            Route::post('{id}/call', [QueueController::class, 'call'])->name('call');
            Route::post('{id}/status', [QueueController::class, 'updateStatus'])->name('status');
        });

        /* ---- DATA MASTER (view_data_master) ---- */
        Route::middleware('can:view_data_master')->group(function () {
            Route::apiResource('categories', CategoryController::class);

            Route::apiResource('menus', MenuController::class);
            Route::get('menus/{id}/recipes', [MenuController::class, 'recipes'])->name('menus.recipes');
            Route::post('menus/{id}/recipes', [MenuController::class, 'updateRecipes'])->name('menus.recipes.update');

            Route::apiResource('tables', TableController::class);

            Route::apiResource('promos', PromoController::class);
            Route::post('promos/{id}/toggle', [PromoController::class, 'toggle'])->name('promos.toggle');

            Route::apiResource('suppliers', SupplierController::class);
            Route::apiResource('ingredients', IngredientController::class);
        });

        /* ---- FINANCE (view_finance) ---- */
        Route::middleware('can:view_finance')->group(function () {
            Route::apiResource('expenses', ExpenseController::class);

            // Target penjualan & budget harian
            Route::get('finance/daily-settings', [ExpenseController::class, 'dailySettings'])->name('finance.daily-settings');
            Route::post('finance/daily-settings', [ExpenseController::class, 'saveDailySettings'])->name('finance.daily-settings.save');
            Route::get('finance/budget-history', [ExpenseController::class, 'budgetHistory'])->name('finance.budget-history');

            // Stok masuk (batch FIFO/FEFO)
            Route::apiResource('stock-batches', StockController::class)->only(['index', 'store', 'destroy']);

            // Stok opname
            Route::get('stock-opname/prepare', [StockOpnameController::class, 'prepare'])->name('stock-opname.prepare');
            Route::post('stock-opname', [StockOpnameController::class, 'store'])->name('stock-opname.store');
            Route::get('stock-opname/history', [StockOpnameController::class, 'history'])->name('stock-opname.history');
            Route::get('stock-opname/{id}', [StockOpnameController::class, 'show'])->name('stock-opname.show');
        });

        /* ---- REPORT (view_report) ---- */
        Route::middleware('can:view_report')->prefix('reports')->name('reports.')->group(function () {
            Route::get('sales', [ReportController::class, 'sales'])->name('sales');
            Route::get('items', [ReportController::class, 'items'])->name('items');
        });

        /* ---- MANAJEMEN (view_resources — Superadmin) ---- */
        Route::middleware('can:view_resources')->group(function () {
            Route::apiResource('users', UserController::class);
            Route::post('users/{id}/ban', [UserController::class, 'ban'])->name('users.ban');
            Route::post('users/{id}/unban', [UserController::class, 'unban'])->name('users.unban');

            Route::get('roles', [RoleController::class, 'index'])->name('roles.index');
            Route::get('permissions', [RoleController::class, 'permissions'])->name('permissions.index');

            Route::apiResource('tenants', TenantController::class)->except(['show']);
            Route::post('tenants/{id}/toggle', [TenantController::class, 'toggle'])->name('tenants.toggle');
        });
    });
});

/* Webhook Midtrans (dinonaktifkan untuk trial — pembayaran memakai tunai).
   Route dibiarkan agar mudah diaktifkan kembali:
Route::post('midtrans-webhook', [KasirController::class, 'handleWebhook'])->name('midtrans.webhook');
*/
