<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use App\Tenancy\BelongsToTenant;

class MenuIngredient extends Model
{
    use BelongsToTenant;

    protected $fillable = ['menu_id', 'ingredient_id', 'quantity'];

    public function menu()
    {
        return $this->belongsTo(Menu::class);
    }

    public function ingredient()
    {
        return $this->belongsTo(Ingredient::class);
    }
}
