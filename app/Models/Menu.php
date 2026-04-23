<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class Menu extends Model
{
    use HasUuids;

    protected $fillable = ['uuid', 'category_id', 'name', 'description', 'price', 'discount_percent', 'image', 'is_available'];

    public function uniqueIds(): array
    {
        return ['uuid'];
    }

    public function category()
    {
        return $this->belongsTo(Category::class);
    }
}
