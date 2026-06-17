<?php

return [
    /*
    |--------------------------------------------------------------------------
    | Jumlah UMKM trial yang dibuat oleh TrialTenantsSeeder
    |--------------------------------------------------------------------------
    */
    'trial_count' => env('TENANCY_TRIAL_COUNT', 10),

    /*
    |--------------------------------------------------------------------------
    | Catatan defense-in-depth (titik bocor yang TIDAK dijaga oleh global scope)
    |--------------------------------------------------------------------------
    | 1. Octane state leak  -> ditangani TenancyServiceProvider (reset per request).
    | 2. Query mentah/DB::   -> hindari; jika terpaksa, filter manual ->where('tenant_id', app('tenant')->id()).
    | 3. Tabel baru          -> WAJIB tambah kolom tenant_id + use BelongsToTenant.
    | 4. withoutGlobalScopes -> jangan dipakai sembarangan; satu-satunya tempat resmi
    |                           membaca lintas-tenant adalah app('tenant')->runWithoutTenant().
    | 5. Cache               -> pakai app('tenant')->cacheKey('xxx') untuk semua key cache per-tenant.
    | 6. Channel Reverb      -> namespace per tenant (lihat routes/channels.php).
    | 7. File/PDF/QR         -> simpan di path tenants/{tenantId}/... (follow-up).
    */
];
