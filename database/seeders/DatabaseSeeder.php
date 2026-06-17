<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    // CATATAN: TIDAK memakai WithoutModelEvents — kita JUSTRU butuh event "creating"
    // agar tenant_id (BelongsToTenant) dan uuid (HasUuids) terisi otomatis saat seeding.

    public function run(): void
    {
        $this->call([
            // 1. Role & permission GLOBAL (sama untuk semua tenant, teams=false).
            RolePermissionSeeder::class,
            // 2. Superadmin platform (tenant_id NULL -> bisa lihat semua tenant).
            SuperAdminSeeder::class,
            // 3. UMKM trial, masing-masing dengan data terisolasi.
            TrialTenantsSeeder::class,
        ]);
    }
}
