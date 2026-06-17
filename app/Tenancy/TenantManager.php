<?php

namespace App\Tenancy;

/**
 * Penyimpan "tenant aktif" untuk SATU request.
 *
 * PENTING (anti-bocor di Octane):
 * - Class ini di-bind sebagai singleton, jadi di Octane ia HIDUP TERUS antar request.
 * - Karena itu nilainya WAJIB di-reset (forget) di setiap awal & akhir request.
 *   Lihat App\Providers\TenancyServiceProvider yang memasang listener Octane.
 * - Global scope (TenantScope) membaca id() dari sini SAAT query dijalankan,
 *   bukan menyimpan id di dalam closure. Jadi tidak ada id basi yang "nyangkut".
 */
class TenantManager
{
    protected ?string $tenantId = null;

    /** Set tenant aktif (biasanya dari user yang login). */
    public function set(?string $tenantId): void
    {
        $this->tenantId = $tenantId;
    }

    /** Id tenant yang sedang aktif (null = tidak ada konteks tenant, mis. superadmin/console). */
    public function id(): ?string
    {
        return $this->tenantId;
    }

    /** Apakah sedang ada tenant aktif? Scope hanya memfilter jika true. */
    public function has(): bool
    {
        return ! is_null($this->tenantId);
    }

    /** Bersihkan konteks tenant. WAJIB dipanggil per request di Octane & antar job di queue. */
    public function forget(): void
    {
        $this->tenantId = null;
    }

    /**
     * Jalankan callback sebagai tenant tertentu, lalu kembalikan konteks semula.
     * Berguna untuk: seeder, queue job, webhook Midtrans, dan test.
     */
    public function runFor(?string $tenantId, callable $callback)
    {
        $previous = $this->tenantId;
        $this->tenantId = $tenantId;

        try {
            return $callback();
        } finally {
            $this->tenantId = $previous;
        }
    }

    /**
     * SATU-SATUNYA tempat resmi untuk membaca lintas-tenant (scope dimatikan sementara).
     * Contoh: resolve tenant dari UUID meja pada halaman QR publik yang belum punya konteks.
     */
    public function runWithoutTenant(callable $callback)
    {
        return $this->runFor(null, $callback);
    }

    /**
     * Helper key cache yang sudah ter-prefix tenant -> mencegah cache tenant A
     * terbaca oleh tenant B (titik bocor #5). Gunakan: Cache::get(app('tenant')->cacheKey('menu_list')).
     */
    public function cacheKey(string $key): string
    {
        return ($this->tenantId ?? 'global') . ':' . $key;
    }

    /**
     * Folder penyimpanan file per-tenant (titik bocor #7).
     * Contoh: app('tenant')->mediaDir('menu') -> "tenants/<id>/menu".
     * Dipakai saat MENULIS/hapus file. Untuk URL baca, pakai accessor model
     * (Menu::image_url, User::avatar_url) supaya path tulis & baca tidak pernah beda.
     */
    public function mediaDir(string $sub = ''): string
    {
        $id = $this->tenantId ?? 'global';
        $sub = trim($sub, '/');

        return 'tenants/' . $id . ($sub !== '' ? '/' . $sub : '');
    }
}
