<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class MenuResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $price = (float) $this->price;
        $discount = (int) ($this->discount_percent ?? 0);
        // Harga final = harga - (harga * diskon%), sama seperti perhitungan di web.
        $finalPrice = $discount > 0 ? $price - ($price * $discount / 100) : $price;

        return [
            'id' => $this->id,
            'uuid' => $this->uuid,
            'name' => $this->name,
            'description' => $this->description,
            'price' => $price,
            'discount_percent' => $discount,
            'final_price' => round($finalPrice, 2),
            'is_available' => (bool) $this->is_available,
            'image' => $this->image,
            'image_url' => $this->image ? $this->image_url : null,
            'category_id' => $this->category_id,
            'category_name' => $this->relationLoaded('category') ? ($this->category->name ?? 'Tanpa Kategori') : null,
            'recipes' => MenuIngredientResource::collection($this->whenLoaded('ingredients')),
        ];
    }
}
