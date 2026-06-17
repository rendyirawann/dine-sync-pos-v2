<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use App\Tenancy\BelongsToTenant;

class Promo extends Model
{
    use BelongsToTenant;

    protected $fillable = ['name', 'discount_type', 'discount_value', 'is_active'];
}
