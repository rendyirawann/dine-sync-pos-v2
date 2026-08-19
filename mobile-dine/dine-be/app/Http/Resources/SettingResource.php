<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class SettingResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'store_name' => $this->store_name,
            'address' => $this->address,
            'phone' => $this->phone,
            'tax_rate' => (int) $this->tax_rate,
        ];
    }
}
