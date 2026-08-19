<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class IngredientBatchResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $initial = (float) $this->initial_quantity;
        $unitPrice = (float) $this->buy_price;

        return [
            'id' => $this->id,
            'ingredient_id' => $this->ingredient_id,
            'ingredient_name' => $this->relationLoaded('ingredient') ? ($this->ingredient->name ?? null) : null,
            'unit' => $this->relationLoaded('ingredient') ? ($this->ingredient->unit ?? null) : null,
            'supplier_id' => $this->supplier_id,
            'supplier_name' => $this->relationLoaded('supplier')
                ? ($this->supplier->name ?? 'Manual/Tanpa Supplier')
                : null,
            'initial_quantity' => $initial,
            'remaining_quantity' => (float) $this->remaining_quantity,
            'buy_price' => $unitPrice,
            'buy_price_total' => (float) ($this->buy_price_total ?? ($unitPrice * $initial)),
            'entry_date' => $this->entry_date ? date('Y-m-d', strtotime((string) $this->entry_date)) : null,
            'expiry_date' => $this->expiry_date ? date('Y-m-d', strtotime((string) $this->expiry_date)) : null,
        ];
    }
}
