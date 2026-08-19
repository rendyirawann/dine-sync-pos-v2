<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Menambah kolom tenant_id ke semua tabel data + mengubah UNIQUE global
 * menjadi COMPOSITE (tenant_id, kolom) supaya tidak bentrok antar UMKM.
 *
 * Catatan: tenant_id dibuat sebagai uuid ber-index TANPA foreign key constraint.
 * Alasannya SQLite (dipakai di test) tidak bisa menambah FK lewat ALTER TABLE.
 * Integritas antar-tenant tetap dijaga di layer aplikasi (TenantScope + auto-fill).
 * Kolom nullable: baris milik superadmin/platform = tenant_id NULL.
 */
return new class extends Migration
{
    /** Tabel yang cukup ditambah tenant_id saja (UNIQUE-nya aman / berbasis UUID). */
    private array $addOnly = [
        'users',
        'menus',
        'order_details',
        'promos',
        'queues',
        'expenses',
        'shifts',
        'suppliers',
        'ingredients',
        'ingredient_batches',
        'menu_ingredients',
        'stock_movements',
        'stock_opnames',
        'stock_opname_details',
        'activity_log',
    ];

    public function up(): void
    {
        // 1. Tabel "add-only"
        foreach ($this->addOnly as $name) {
            if (Schema::hasTable($name) && ! Schema::hasColumn($name, 'tenant_id')) {
                Schema::table($name, function (Blueprint $table) {
                    $table->uuid('tenant_id')->nullable()->after('id')->index();
                });
            }
        }

        // 2. categories: slug unik per-tenant
        $this->addTenantColumn('categories');
        Schema::table('categories', function (Blueprint $table) {
            $table->dropUnique(['slug']);
            $table->unique(['tenant_id', 'slug']);
        });

        // 3. daily_budgets: 1 budget per tanggal per-tenant
        $this->addTenantColumn('daily_budgets');
        Schema::table('daily_budgets', function (Blueprint $table) {
            $table->dropUnique(['date']);
            $table->unique(['tenant_id', 'date']);
        });

        // 4. daily_sales_targets: 1 target per tanggal per-tenant
        $this->addTenantColumn('daily_sales_targets');
        Schema::table('daily_sales_targets', function (Blueprint $table) {
            $table->dropUnique(['date']);
            $table->unique(['tenant_id', 'date']);
        });

        // 5. tables: "Meja 01" boleh ada di tiap UMKM (uuid tetap unik global)
        $this->addTenantColumn('tables');
        Schema::table('tables', function (Blueprint $table) {
            $table->dropUnique(['table_number']);
            $table->unique(['tenant_id', 'table_number']);
        });

        // 6. orders: nomor invoice di-generate per-tenant (uuid tetap unik global)
        $this->addTenantColumn('orders');
        Schema::table('orders', function (Blueprint $table) {
            $table->dropUnique(['invoice_no']);
            $table->unique(['tenant_id', 'invoice_no']);
        });

        // 7. settings: tepat 1 baris pengaturan per-tenant
        $this->addTenantColumn('settings');
        Schema::table('settings', function (Blueprint $table) {
            $table->unique('tenant_id');
        });
    }

    public function down(): void
    {
        Schema::table('settings', function (Blueprint $table) {
            $table->dropUnique(['tenant_id']);
            $table->dropColumn('tenant_id');
        });

        Schema::table('orders', function (Blueprint $table) {
            $table->dropUnique(['tenant_id', 'invoice_no']);
            $table->unique('invoice_no');
            $table->dropColumn('tenant_id');
        });

        Schema::table('tables', function (Blueprint $table) {
            $table->dropUnique(['tenant_id', 'table_number']);
            $table->unique('table_number');
            $table->dropColumn('tenant_id');
        });

        Schema::table('daily_sales_targets', function (Blueprint $table) {
            $table->dropUnique(['tenant_id', 'date']);
            $table->unique('date');
            $table->dropColumn('tenant_id');
        });

        Schema::table('daily_budgets', function (Blueprint $table) {
            $table->dropUnique(['tenant_id', 'date']);
            $table->unique('date');
            $table->dropColumn('tenant_id');
        });

        Schema::table('categories', function (Blueprint $table) {
            $table->dropUnique(['tenant_id', 'slug']);
            $table->unique('slug');
            $table->dropColumn('tenant_id');
        });

        foreach (array_reverse($this->addOnly) as $name) {
            if (Schema::hasTable($name) && Schema::hasColumn($name, 'tenant_id')) {
                Schema::table($name, function (Blueprint $table) {
                    $table->dropColumn('tenant_id');
                });
            }
        }
    }

    private function addTenantColumn(string $name): void
    {
        if (Schema::hasTable($name) && ! Schema::hasColumn($name, 'tenant_id')) {
            Schema::table($name, function (Blueprint $table) {
                $table->uuid('tenant_id')->nullable()->after('id')->index();
            });
        }
    }
};
