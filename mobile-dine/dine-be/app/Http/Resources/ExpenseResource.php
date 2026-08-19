<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class ExpenseResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'uuid' => $this->uuid,
            'date' => $this->date ? date('Y-m-d', strtotime((string) $this->date)) : null,
            'category' => $this->category,
            'notes' => $this->notes,
            'amount' => (float) $this->amount,
            'user_id' => $this->user_id,
            'user_name' => $this->relationLoaded('user') ? ($this->user->name ?? 'Sistem') : null,
            'created_at' => optional($this->created_at)->toIso8601String(),
        ];
    }
}
