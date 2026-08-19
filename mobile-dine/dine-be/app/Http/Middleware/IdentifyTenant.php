<?php

namespace App\Http\Middleware;

use App\Models\Order;
use App\Models\Table;
use App\Models\Tenant;
use App\Tenancy\TenantManager;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Menentukan "tenant aktif" untuk setiap request API.
 *
 * Urutan resolusi:
 *  A. User terautentikasi (token Sanctum) -> tenant = user->tenant_id.
 *     Superadmin (tenant_id NULL) tidak men-set tenant sehingga bisa lihat semua,
 *     KECUALI ia mengirim header X-Tenant-ID untuk "masuk" ke tenant tertentu.
 *  B. Route publik dengan {tenant} (slug/id) -> mis. kiosk/display.
 *  C. Route publik dengan {uuid} meja/order -> self-order pelanggan (tanpa login).
 *
 * Dibaca TANPA scope (runWithoutTenant) saat resolusi, karena konteks belum ada.
 */
class IdentifyTenant
{
    public function __construct(private TenantManager $tenant) {}

    public function handle(Request $request, Closure $next): Response
    {
        // Selalu mulai bersih (penting di Octane: worker dipakai ulang antar request).
        $this->tenant->forget();

        // Sanctum: resolve dari Bearer token. Middleware ini berjalan sebelum
        // 'auth:sanctum', jadi guard dipanggil eksplisit (bukan $request->user()).
        $user = $request->user() ?: auth('sanctum')->user();

        if ($user) {
            if (! empty($user->tenant_id)) {
                $this->tenant->set($user->tenant_id);
            } elseif ($header = $request->header('X-Tenant-ID')) {
                // Superadmin boleh menargetkan satu tenant lewat header.
                $tenantId = $this->tenant->runWithoutTenant(fn () => optional(
                    Tenant::where('id', $header)->orWhere('slug', $header)->first()
                )->id);

                if ($tenantId) {
                    $this->tenant->set($tenantId);
                }
            }

            return $next($request);
        }

        if ($tenantKey = $request->route('tenant')) {
            $tenantId = $this->tenant->runWithoutTenant(fn () => optional(
                Tenant::where('slug', $tenantKey)->orWhere('id', $tenantKey)->first()
            )->id);

            if ($tenantId) {
                $this->tenant->set($tenantId);
            }

            return $next($request);
        }

        if ($uuid = $request->route('uuid')) {
            $tenantId = $this->tenant->runWithoutTenant(function () use ($uuid) {
                return optional(Table::where('uuid', $uuid)->first())->tenant_id
                    ?? optional(Order::where('uuid', $uuid)->first())->tenant_id;
            });

            if ($tenantId) {
                $this->tenant->set($tenantId);
            }
        }

        return $next($request);
    }
}
