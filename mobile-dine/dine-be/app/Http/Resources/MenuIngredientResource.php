<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class MenuIngredientResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'menu_id' => $this->menu_id,
            'ingredient_id' => $this->ingredient_id,
            'quantity' => (float) $this->quantity,
            'ingredient_name' => $this->relationLoaded('ingredient') ? ($this->ingredient->name ?? null) : null,
            'unit' => $this->relationLoaded('ingredient') ? ($this->ingredient->unit ?? null) : null,
        ];
    }
}
