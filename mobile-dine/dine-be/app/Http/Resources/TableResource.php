<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class TableResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        // payment_status di-inject runtime oleh controller peta meja (bukan kolom DB),
        // meniru perilaku KasirController@index di web.
        $payment = $this->payment_status ?? null;

        $statusLabel = 'KOSONG';
        $statusColor = 'success';
        if ($this->status === 'occupied') {
            $statusLabel = $payment === 'unpaid' ? 'BELUM BAYAR' : 'TERISI (LUNAS)';
            $statusColor = $payment === 'unpaid' ? 'warning' : 'danger';
        }

        return [
            'id' => $this->id,
            'uuid' => $this->uuid,
            'table_number' => $this->table_number,
            'capacity' => (int) $this->capacity,
            'status' => $this->status,
            'payment_status' => $payment,
            'status_label' => $statusLabel,
            'status_color' => $statusColor,
            // Payload QR yang dicetak di web (dipakai Flutter untuk render/scan QR).
            'qr_payload' => $this->uuid ? url('/scan/' . $this->uuid) : null,
        ];
    }
}
