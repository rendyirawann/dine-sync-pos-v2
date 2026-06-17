<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use App\Tenancy\BelongsToTenant;

class OrderDetail extends Model
{
    use BelongsToTenant;

    protected $fillable = [
        'order_id',
        'menu_id',
        'qty',
        'price',
        'subtotal',
        'notes',
        'status',
        'is_stock_deducted',
        'hpp'
    ];

    public function order()
    {
        return $this->belongsTo(Order::class);
    }

    public function menu()
    {
        return $this->belongsTo(Menu::class);
    }
}
