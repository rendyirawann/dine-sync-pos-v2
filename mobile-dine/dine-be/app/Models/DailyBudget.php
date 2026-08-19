<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use App\Tenancy\BelongsToTenant;

class DailyBudget extends Model
{
    use BelongsToTenant;

    protected $fillable = ['date', 'amount'];
}
