<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class OrderResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $orderStatusLabel = [
            'pending' => 'Menunggu Dibuat',
            'cooking' => 'Sedang Dimasak',
            'served' => 'Sudah Disajikan',
            'completed' => 'Selesai',
        ];
        $orderTypeLabel = [
            'dine_in' => 'Dine In',
            'take_away' => 'Take Away',
            'reservation' => 'Reservasi',
        ];

        return [
            'id' => $this->id,
            'uuid' => $this->uuid,
            'invoice_no' => $this->invoice_no,
            'table_id' => $this->table_id,
            'table_number' => $this->relationLoaded('table') ? ($this->table->table_number ?? 'Walk-in') : null,
            'customer_name' => $this->customer_name,
            'order_type' => $this->order_type,
            'order_type_label' => $orderTypeLabel[$this->order_type] ?? $this->order_type,
            'subtotal' => (float) $this->subtotal,
            'discount_amount' => (float) $this->discount_amount,
            'tax' => (float) $this->tax,
            'grand_total' => (float) $this->grand_total,
            'promo_id' => $this->promo_id,
            'promo_name' => $this->relationLoaded('promo') ? ($this->promo->name ?? null) : null,
            'payment_method' => $this->payment_method,
            'payment_status' => $this->payment_status,
            'order_status' => $this->order_status,
            'order_status_label' => $orderStatusLabel[$this->order_status] ?? $this->order_status,
            'total_hpp' => $this->relationLoaded('details') ? (float) $this->details->sum('hpp') : null,
            'details' => OrderDetailResource::collection($this->whenLoaded('details')),
            'created_at' => optional($this->created_at)->toIso8601String(),
            'updated_at' => optional($this->updated_at)->toIso8601String(),
        ];
    }
}
