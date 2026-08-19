<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use App\Tenancy\BelongsToTenant;

class Table extends Model
{
    use HasUuids, BelongsToTenant; // Gunakan ini

    protected $fillable = ['uuid', 'table_number', 'capacity', 'status'];

    // Beritahu Laravel bahwa kolom UUID kita bernama 'uuid' (bukan 'id')
    public function uniqueIds(): array
    {
        return ['uuid'];
    }
}
