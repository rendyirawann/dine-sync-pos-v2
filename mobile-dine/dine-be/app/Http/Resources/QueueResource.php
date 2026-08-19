<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class QueueResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $labels = [
            'waiting' => 'Menunggu',
            'called' => 'Dipanggil',
            'seated' => 'Sudah Duduk',
            'cancelled' => 'Dibatalkan',
        ];
        $colors = [
            'waiting' => 'warning',
            'called' => 'primary',
            'seated' => 'success',
            'cancelled' => 'secondary',
        ];

        return [
            'id' => $this->id,
            'queue_number' => $this->queue_number,
            'customer_name' => $this->customer_name,
            'pax' => (int) $this->pax,
            'status' => $this->status,
            'status_label' => $labels[$this->status] ?? $this->status,
            'status_color' => $colors[$this->status] ?? 'secondary',
            // Kategori meja mengikuti prefix nomor antrian: A (1-2), B (3-4), C (5+).
            'category' => substr((string) $this->queue_number, 0, 1),
            'time' => optional($this->created_at)->format('H:i'),
            'created_at' => optional($this->created_at)->toIso8601String(),
        ];
    }
}
