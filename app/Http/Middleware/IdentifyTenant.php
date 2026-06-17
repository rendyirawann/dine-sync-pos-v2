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
 * Menentukan "tenant aktif" untuk setiap request web.
 *
 * Dua jalur:
 *  A. User sudah login  -> tenant = user->tenant_id (superadmin = null -> lihat semua).
 *  B. Tamu (QR publik)  -> tenant di-resolve dari UUID meja/order di URL,
 *     dibaca TANPA scope (runWithoutTenant) karena belum ada konteks.
 *     Setelah di-set, semua query menu/kategori/setting otomatis ter-filter.
 */
class IdentifyTenant
{
    public function __construct(private TenantManager $tenant) {}

    public function handle(Request $request, Closure $next): Response
    {
        // Selalu mulai bersih (penting di Octane / worker yang dipakai ulang).
        $this->tenant->forget();

        $user = $request->user();

        if ($user) {
            // Jalur A — admin/kasir/kitchen. Superadmin tenant_id NULL = tanpa filter.
            if (! empty($user->tenant_id)) {
                $this->tenant->set($user->tenant_id);
            }
        } elseif ($tenantKey = $request->route('tenant')) {
            // Jalur B1 — halaman publik kiosk/display: {tenant} = slug atau id UMKM.
            $tenantId = $this->tenant->runWithoutTenant(function () use ($tenantKey) {
                return optional(
                    Tenant::where('slug', $tenantKey)->orWhere('id', $tenantKey)->first()
                )->id;
            });

            if ($tenantId) {
                $this->tenant->set($tenantId);
            }
        } elseif ($uuid = $request->route('uuid')) {
            // Jalur B2 — halaman publik berbasis UUID meja/order (scan/menu/checkout/success).
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
