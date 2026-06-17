<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use App\Tenancy\BelongsToTenant;

class Queue extends Model
{
    use BelongsToTenant;

    // 🔥 WAJIB DITAMBAHKAN: Mengizinkan Laravel mengisi kolom-kolom ini
    protected $fillable = [
        'queue_number',
        'customer_name',
        'pax',
        'status'
    ];
}
