<?php

namespace Database\Seeders;

use App\Models\Category;
use App\Models\Menu;
use App\Models\Setting;
use App\Models\Table;
use App\Models\Tenant;
use App\Models\User;
use App\Tenancy\TenantManager;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

/**
 * Membuat UMKM trial, masing-masing dengan datanya sendiri (terisolasi).
 *
 * Pola penting: semua pembuatan data dibungkus tenant()->runFor($id, ...).
 * Dengan begitu trait BelongsToTenant otomatis mengisi tenant_id yang benar,
 * tanpa kita menulis tenant_id manual di tiap baris.
 */
class TrialTenantsSeeder extends Seeder
{
    public function run(): void
    {
        $manager = app(TenantManager::class);
        $count = (int) (config('tenancy.trial_count') ?? 10);

        for ($i = 1; $i <= $count; $i++) {
            $tenant = Tenant::create([
                'name'          => "UMKM Trial {$i}",
                'slug'          => "umkm-{$i}",
                'is_active'     => true,
                'trial_ends_at' => now()->addDays(30),
            ]);

            $manager->runFor($tenant->id, function () use ($i) {
                // 1. Pengaturan toko (per-tenant)
                Setting::create([
                    'store_name' => "UMKM Trial {$i}",
                    'address'    => "Alamat UMKM {$i}",
                    'phone'      => '0800000000' . $i,
                    'tax_rate'   => 10,
                ]);

                // 2. Meja
                for ($m = 1; $m <= 5; $m++) {
                    Table::create([
                        'table_number' => 'Meja ' . str_pad($m, 2, '0', STR_PAD_LEFT),
                        'capacity'     => 4,
                    ]);
                }

                // 3. Kategori + Menu
                $food = Category::create(['name' => 'Main Course', 'slug' => 'main-course']);
                $drink = Category::create(['name' => 'Beverages', 'slug' => 'beverages']);

                Menu::create([
                    'category_id'  => $food->id,
                    'name'         => "Nasi Goreng UMKM {$i}",
                    'description'  => 'Menu khas UMKM ' . $i,
                    'price'        => 25000,
                    'is_available' => true,
                ]);
                Menu::create([
                    'category_id'  => $drink->id,
                    'name'         => "Es Teh UMKM {$i}",
                    'description'  => 'Minuman segar',
                    'price'        => 8000,
                    'is_available' => true,
                ]);

                // 4. User pemilik + kasir (email/username unik global -> diberi sufiks tenant)
                $admin = User::create([
                    'name'              => "Owner UMKM {$i}",
                    'username'          => "owner_umkm_{$i}",
                    'email'             => "owner{$i}@trial.test",
                    'password'          => Hash::make('password'),
                    'is_active'         => true,
                    'email_verified_at' => now(),
                ]);
                $admin->assignRole('admin');

                $kasir = User::create([
                    'name'              => "Kasir UMKM {$i}",
                    'username'          => "kasir_umkm_{$i}",
                    'email'             => "kasir{$i}@trial.test",
                    'password'          => Hash::make('password'),
                    'is_active'         => true,
                    'email_verified_at' => now(),
                ]);
                $kasir->assignRole('kasir');
            });
        }

        $this->command?->info("Berhasil membuat {$count} UMKM trial (login: owner{1..n}@trial.test / password).");
    }
}
