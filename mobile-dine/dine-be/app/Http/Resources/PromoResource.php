<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class PromoResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            // percentage | nominal (sesuai enum di database)
            'discount_type' => $this->discount_type,
            'discount_value' => (int) $this->discount_value,
            'is_active' => (bool) $this->is_active,
            'label' => $this->discount_type === 'percentage'
                ? $this->name . ' (' . $this->discount_value . '%)'
                : $this->name . ' (Rp ' . number_format($this->discount_value, 0, ',', '.') . ')',
        ];
    }
}
