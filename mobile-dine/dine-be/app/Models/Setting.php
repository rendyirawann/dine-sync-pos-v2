<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use App\Tenancy\BelongsToTenant;

class Setting extends Model
{
    use BelongsToTenant;

    protected $table = 'settings';
    protected $fillable = ['store_name', 'address', 'phone', 'tax_rate'];

    /**
     * Ambil baris setting milik tenant aktif (buat default jika belum ada).
     * Gantikan pemakaian Setting::first() yang lama (yang mengambil baris pertama global).
     */
    public static function forCurrentTenant(): self
    {
        return static::firstOrCreate([], [
            'store_name' => 'DineSync POS',
            'tax_rate'   => 10,
        ]);
    }
}
