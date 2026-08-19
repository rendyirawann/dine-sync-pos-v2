<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class IngredientResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        // Atribut "stock" di-set controller (withSum batches). Fallback ke currentStock().
        $stock = (float) ($this->stock ?? $this->currentStock());
        $min = (float) $this->minimum_stock;

        return [
            'id' => $this->id,
            'name' => $this->name,
            'unit' => $this->unit,
            'minimum_stock' => $min,
            'current_stock' => $stock,
            'is_low_stock' => $stock <= $min,
            'stock_label' => number_format($stock, 2, ',', '.') . ' ' . $this->unit,
        ];
    }
}
