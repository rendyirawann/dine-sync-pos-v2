<?php

namespace App\Events;

use Illuminate\Broadcasting\Channel;
use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Contracts\Broadcasting\ShouldBroadcastNow;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class CallQueueEvent implements ShouldBroadcastNow
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    public $text_to_speak;
    public $display_data;
    public $type; // 'queue' atau 'food'
    public $tenantId;

    public function __construct($text_to_speak, $display_data, $type = 'queue', $tenantId = null)
    {
        $this->text_to_speak = $text_to_speak;
        $this->display_data = $display_data;
        $this->type = $type;
        $this->tenantId = $tenantId;
    }

    // Channel public per-tenant agar TV Display tiap UMKM hanya mendengar panggilannya sendiri
    public function broadcastOn()
    {
        return new Channel('public-display.' . $this->tenantId);
    }

    public function broadcastAs()
    {
        return 'call-event';
    }
}
