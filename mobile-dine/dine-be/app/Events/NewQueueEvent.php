<?php

namespace App\Events;

use Illuminate\Broadcasting\Channel;
use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Contracts\Broadcasting\ShouldBroadcastNow;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class NewQueueEvent implements ShouldBroadcastNow
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    public $timestamp;
    public $tenantId;

    public function __construct($tenantId = null)
    {
        $this->tenantId = $tenantId;
        $this->timestamp = now()->toDateTimeString();
    }

    public function broadcastOn()
    {
        // Per-tenant: tiap UMKM punya channel sendiri -> kiosk/kasir tenant lain tidak ikut menerima.
        return new Channel('public-queue.' . $this->tenantId);
    }

    public function broadcastAs()
    {
        return 'new-queue';
    }
}
