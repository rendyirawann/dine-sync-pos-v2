<?php

use Illuminate\Support\Facades\Broadcast;

/*
|--------------------------------------------------------------------------
| Broadcast Channels
|--------------------------------------------------------------------------
*/

// 1. Channel untuk Sidebar "Who's Online" (PRESENCE CHANNEL) — per-tenant.
// Hanya user dari tenant yang sama yang boleh join -> daftar "online" tidak campur antar UMKM.
// Langganan di Blade: Echo.join('online-users.' + '{{ app('tenant')->id() }}').
Broadcast::channel('online-users.{tenantId}', function ($user, $tenantId) {
    if (auth()->check() && (string) $user->tenant_id === (string) $tenantId) {
        return [
            'id' => $user->id,
            'name' => $user->name,
            'email' => $user->email,
            'avatar_url' => $user->avatar ? $user->avatar_url : null,
            'initials' => substr($user->name, 0, 1)
        ];
    }
});

// 2. Channel untuk Notifikasi Pribadi / Force Logout (PRIVATE CHANNEL)
// Wajib mengembalikan BOOLEAN (True/False)
// FIX: id user adalah UUID (string), JANGAN di-cast ke (int) -> selalu jadi 0 & cocok ke siapa saja.
// Channel ini sudah aman lintas-tenant karena UUID unik global per user.
Broadcast::channel('App.Models.User.{id}', function ($user, $id) {
    return (string) $user->id === (string) $id;
});

/*
 * CATATAN MULTI-TENANT (follow-up):
 * Channel publik antrian/dapur ('public-queue', 'public-display') dan presence
 * 'online-users' saat ini masih satu nama global -> semua UMKM "mendengar" event
 * yang sama. Untuk isolasi penuh, beri nama per-tenant, mis. 'public-queue.{tenantId}'
 * dan 'online-users.{tenantId}', lalu sesuaikan langganan Echo di Blade/JS serta
 * broadcastOn() pada Event terkait. Lihat titik bocor #6.
 */
