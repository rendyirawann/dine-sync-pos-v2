<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use App\Tenancy\BelongsToTenant;

class Menu extends Model
{
    use HasUuids, BelongsToTenant;

    protected $fillable = ['uuid', 'category_id', 'name', 'description', 'price', 'discount_percent', 'image', 'is_available'];

    public function uniqueIds(): array
    {
        return ['uuid'];
    }

    public function promo()
    {
        return $this->belongsTo(Promo::class);
    }

    public function ingredients()
    {
        return $this->hasMany(MenuIngredient::class);
    }

    /**
     * Calculate HPP (COGS) based on current FIFO batch prices
     */
    public function calculateHPP()
    {
        $totalHPP = 0;
        foreach ($this->ingredients as $recipe) {
            // Logic to find average price from active batches or latest batch
            $latestBatch = $recipe->ingredient->batches()
                ->where('remaining_quantity', '>', 0)
                ->orderBy('entry_date', 'asc')
                ->first();
            
            if ($latestBatch) {
                $totalHPP += ($recipe->quantity * $latestBatch->buy_price);
            }
        }
        return $totalHPP;
    }

    public function category()
    {
        return $this->belongsTo(Category::class);
    }

    /**
     * URL gambar menu, sudah ter-namespace per-tenant (tenants/{id}/menu/...).
     * Pakai app('tenant')->id() kalau ada konteks, jika tidak (superadmin/console)
     * pakai tenant_id milik record itu sendiri. Tidak ada fallback blank di sini —
     * biarkan ternary di view yang menangani kasus gambar kosong.
     */
    public function getImageUrlAttribute(): string
    {
        $tid = app('tenant')->id() ?? $this->tenant_id;

        return asset('storage/tenants/' . $tid . '/menu/' . $this->image);
    }
}
