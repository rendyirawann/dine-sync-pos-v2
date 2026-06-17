<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use App\Tenancy\BelongsToTenant;

class DailySalesTarget extends Model
{
    use BelongsToTenant;

    protected $fillable = ['date', 'amount'];
}
