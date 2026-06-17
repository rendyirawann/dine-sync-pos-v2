<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Tenant = 1 UMKM / bisnis.
 *
 * Ini SATU-SATUNYA tabel "global" yang baru. Semua tabel data lain
 * menyimpan tenant_id yang menunjuk ke sini. Tenant TIDAK memakai
 * trait BelongsToTenant (dia bukan data milik tenant, dia adalah tenant-nya).
 */
class Tenant extends Model
{
    use HasUuids;

    protected $fillable = [
        'name',
        'slug',
        'is_active',
        'trial_ends_at',
    ];

    protected function casts(): array
    {
        return [
            'is_active'     => 'boolean',
            'trial_ends_at' => 'datetime',
        ];
    }

    public function users()
    {
        return $this->hasMany(User::class);
    }
}
