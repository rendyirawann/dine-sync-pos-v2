<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class ShiftResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $diff = $this->difference !== null ? (float) $this->difference : null;

        // Label selisih disamakan dengan badge riwayat shift di web.
        $diffLabel = null;
        $diffColor = null;
        if ($diff !== null) {
            if ($diff == 0) {
                $diffLabel = 'Pas (Rp 0)';
                $diffColor = 'success';
            } elseif ($diff > 0) {
                $diffLabel = 'Lebih +Rp ' . number_format($diff, 0, ',', '.');
                $diffColor = 'info';
            } else {
                $diffLabel = 'Kurang Rp ' . number_format(abs($diff), 0, ',', '.');
                $diffColor = 'danger';
            }
        }

        return [
            'id' => $this->id,
            'uuid' => $this->uuid,
            'user_id' => $this->user_id,
            'user_name' => $this->relationLoaded('user') ? ($this->user->name ?? null) : null,
            'start_time' => optional($this->start_time)->toIso8601String(),
            'end_time' => optional($this->end_time)->toIso8601String(),
            'starting_cash' => (float) $this->starting_cash,
            'cash_sales' => (float) $this->cash_sales,
            'expected_cash' => $this->expected_cash !== null ? (float) $this->expected_cash : null,
            'actual_cash' => $this->actual_cash !== null ? (float) $this->actual_cash : null,
            'difference' => $diff,
            'difference_label' => $diffLabel,
            'difference_color' => $diffColor,
            'status' => $this->status,
        ];
    }
}
