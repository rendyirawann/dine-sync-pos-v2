<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use App\Models\Product;
use App\Tenancy\BelongsToTenant;

class Category extends Model
{
    use BelongsToTenant;

    protected $fillable = ['name', 'slug'];

    // Relasi ke Produk: Satu kategori punya banyak produk
    public function products()
    {
        return $this->hasMany(Product::class);
    }
}
