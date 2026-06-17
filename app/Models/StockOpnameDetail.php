<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use App\Tenancy\BelongsToTenant;

class StockOpnameDetail extends Model
{
    use BelongsToTenant;

    protected $fillable = ['stock_opname_id', 'ingredient_id', 'system_qty', 'physical_qty', 'difference'];

    public function stockOpname()
    {
        return $this->belongsTo(StockOpname::class);
    }

    public function ingredient()
    {
        return $this->belongsTo(Ingredient::class);
    }
}
