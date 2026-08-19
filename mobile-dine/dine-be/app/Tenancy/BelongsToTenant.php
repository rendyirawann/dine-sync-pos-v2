<?php

namespace App\Tenancy;

use App\Models\Tenant;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Pasang trait ini di SEMUA model data yang harus terisolasi per UMKM.
 * Konvensi: tabel baru WAJIB punya kolom tenant_id + pakai trait ini.
 *
 * Yang dilakukan trait:
 * 1. Memasang TenantScope (auto-filter WHERE tenant_id saat SELECT/UPDATE/DELETE).
 * 2. Auto-fill tenant_id saat membuat data (ambil dari tenant aktif).
 *
 * ANTI-SPOOF: saat ada tenant aktif, tenant_id DIPAKSA = tenant aktif,
 * meskipun request mengirim tenant_id lain. Jadi user tidak bisa menitipkan
 * data ke tenant lain lewat input (mass assignment). Saat TIDAK ada tenant
 * aktif (mis. seeder), tenant_id dibiarkan apa adanya supaya bisa diisi manual.
 */
trait BelongsToTenant
{
    public static function bootBelongsToTenant(): void
    {
        static::addGlobalScope(new TenantScope);

        static::creating(function ($model) {
            $manager = app(TenantManager::class);

            if ($manager->has()) {
                // Paksa -> mencegah spoofing tenant_id lewat input.
                $model->tenant_id = $manager->id();
            }
            // Jika tidak ada konteks tenant, biarkan nilai yang sudah di-set (seeder/job).
        });
    }

    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }
}
