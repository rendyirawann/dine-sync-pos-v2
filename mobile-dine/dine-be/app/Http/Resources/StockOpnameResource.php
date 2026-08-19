<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class StockOpnameResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'date' => $this->date ? date('Y-m-d', strtotime((string) $this->date)) : null,
            'notes' => $this->notes,
            'user_id' => $this->user_id,
            'user_name' => $this->relationLoaded('user') ? ($this->user->name ?? null) : null,
            'details' => $this->whenLoaded('details', fn () => $this->details->map(fn ($d) => [
                'id' => $d->id,
                'ingredient_id' => $d->ingredient_id,
                'ingredient_name' => $d->relationLoaded('ingredient') ? ($d->ingredient->name ?? null) : null,
                'unit' => $d->relationLoaded('ingredient') ? ($d->ingredient->unit ?? null) : null,
                'system_qty' => (float) $d->system_qty,
                'physical_qty' => (float) $d->physical_qty,
                'difference' => (float) $d->difference,
            ])->values()),
            'created_at' => optional($this->created_at)->toIso8601String(),
        ];
    }
}
