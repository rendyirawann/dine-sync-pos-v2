<?php

namespace App\Tenancy;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Scope;

/**
 * Global scope yang otomatis menambahkan WHERE tenant_id = <tenant aktif>
 * ke SETIAP query Eloquent pada model yang memakai trait BelongsToTenant.
 *
 * Catatan penting:
 * - Class-based (bukan closure) supaya membaca tenant aktif SAAT query jalan,
 *   bukan menangkap id lama -> aman di Octane (titik bocor #1).
 * - Jika tidak ada tenant aktif (console/seeder/superadmin), scope TIDAK memfilter.
 *   Konsekuensinya: lupa set tenant = data tidak terfilter. Itu sebabnya ada
 *   middleware IdentifyTenant + listener Octane + test isolasi sebagai jaring pengaman.
 */
class TenantScope implements Scope
{
    public function apply(Builder $builder, Model $model): void
    {
        $manager = app(TenantManager::class);

        if ($manager->has()) {
            $builder->where($model->getTable() . '.tenant_id', $manager->id());
        }
    }
}
