<?php

namespace App\Providers;

use App\Tenancy\TenantManager;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\ServiceProvider;

class TenancyServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        // Singleton: satu instance per worker. Di Octane ia hidup antar request,
        // makanya kita reset di bawah. Alias 'tenant' supaya bisa app('tenant').
        $this->app->singleton(TenantManager::class, fn () => new TenantManager);
        $this->app->alias(TenantManager::class, 'tenant');
    }

    public function boot(): void
    {
        $this->registerOctaneResetListeners();
    }

    /**
     * JARING PENGAMAN ANTI-BOCOR #1 (Octane state leak).
     *
     * Di PHP-FPM biasa tiap request proses baru, jadi tidak ada kebocoran.
     * Di Octane worker hidup terus -> tenant aktif WAJIB di-reset:
     *  - RequestReceived: bersihkan sebelum request mulai (jaga-jaga sisa request lalu).
     *  - RequestTerminated: bersihkan setelah request selesai.
     * Sama untuk Task/Tick (queue/scheduler yang jalan di worker Octane).
     *
     * Kelas event Octane di-cek via class_exists supaya aman walau Octane tidak terpasang.
     */
    private function registerOctaneResetListeners(): void
    {
        $events = array_filter([
            \Laravel\Octane\Events\RequestReceived::class ?? null,
            \Laravel\Octane\Events\RequestTerminated::class ?? null,
            \Laravel\Octane\Events\TaskReceived::class ?? null,
            \Laravel\Octane\Events\TaskTerminated::class ?? null,
            \Laravel\Octane\Events\TickReceived::class ?? null,
            \Laravel\Octane\Events\TickTerminated::class ?? null,
        ], fn ($class) => $class && class_exists($class));

        foreach ($events as $event) {
            Event::listen($event, function () {
                app(TenantManager::class)->forget();

                // Jika nanti mengaktifkan spatie "teams", reset juga team id di sini:
                // if (app()->bound(\Spatie\Permission\PermissionRegistrar::class)) {
                //     app(\Spatie\Permission\PermissionRegistrar::class)->setPermissionsTeamId(null);
                // }
            });
        }
    }
}
