<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use App\Tenancy\BelongsToTenant;

class Supplier extends Model
{
    use BelongsToTenant;

    protected $fillable = ['name', 'contact_person', 'phone', 'address'];

    public function batches()
    {
        return $this->hasMany(IngredientBatch::class);
    }
}
