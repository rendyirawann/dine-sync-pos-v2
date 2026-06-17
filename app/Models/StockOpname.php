<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use App\Tenancy\BelongsToTenant;

class StockOpname extends Model
{
    use BelongsToTenant;

    protected $fillable = ['user_id', 'date', 'notes'];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function details()
    {
        return $this->hasMany(StockOpnameDetail::class);
    }
}
