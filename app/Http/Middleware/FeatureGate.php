<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Memblokir akses URL ke fitur yang dimatikan di versi lite.
 * Route tetap TERDAFTAR (supaya route() tidak pernah error di mana pun),
 * tapi diakses akan 404 jika feature flag-nya off.
 *
 * Pakai: ->middleware('feature:inventory')
 */
class FeatureGate
{
    public function handle(Request $request, Closure $next, string $feature): Response
    {
        abort_unless((bool) config("features.$feature", false), 404);

        return $next($request);
    }
}
