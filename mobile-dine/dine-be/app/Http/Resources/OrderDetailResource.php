<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class OrderDetailResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        // Label & warna disamakan dengan badge di web (Antre/Dimasak/Siap).
        $labels = ['pending' => 'Antre', 'cooking' => 'Dimasak', 'done' => 'Siap'];
        $colors = ['pending' => 'warning', 'cooking' => 'primary', 'done' => 'success'];

        return [
            'id' => $this->id,
            'order_id' => $this->order_id,
            'menu_id' => $this->menu_id,
            'menu_name' => $this->relationLoaded('menu') ? ($this->menu->name ?? 'Menu Dihapus') : null,
            'menu_image_url' => $this->relationLoaded('menu') && $this->menu && $this->menu->image ? $this->menu->image_url : null,
            'qty' => (int) $this->qty,
            'price' => (float) $this->price,
            'subtotal' => (float) $this->subtotal,
            'hpp' => (float) $this->hpp,
            'notes' => $this->notes,
            'status' => $this->status,
            'status_label' => $labels[$this->status] ?? $this->status,
            'status_color' => $colors[$this->status] ?? 'secondary',
            'is_stock_deducted' => (bool) $this->is_stock_deducted,
        ];
    }
}
