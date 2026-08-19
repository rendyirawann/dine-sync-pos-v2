<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Api\BaseApiController;
use Illuminate\Http\JsonResponse;
use OpenApi\Attributes as OA;

/**
 * Role & Permission (khusus Superadmin — route di-gate 'can:view_resources').
 *
 * Endpoint ini bersifat baca-saja: dipakai aplikasi mobile untuk mengisi dropdown
 * role saat menambah/mengubah user, serta menampilkan daftar hak akses.
 * Role & permission adalah data GLOBAL (bukan milik tenant), jadi tidak ada scope tenant.
 */
class RoleController extends BaseApiController
{
    #[OA\Get(
        path: '/api/v1/roles',
        operationId: 'roleIndex',
        summary: 'Daftar role beserta permission-nya',
        description: 'Menampilkan seluruh role (diurutkan menurut nama) lengkap dengan daftar nama '
            . 'permission yang dimilikinya dan jumlah user yang memakai role tersebut. '
            . 'Dipakai untuk dropdown role pada form user di aplikasi mobile.',
        tags: ['Manajemen'],
        security: [['sanctum' => []]],
        responses: [
            new OA\Response(response: 200, description: 'Daftar role', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'message', type: 'string', example: 'Daftar role berhasil diambil.'),
                    new OA\Property(property: 'data', type: 'array', items: new OA\Items(properties: [
                        new OA\Property(property: 'id', type: 'integer', example: 2),
                        new OA\Property(property: 'name', type: 'string', example: 'admin'),
                        new OA\Property(property: 'guard_name', type: 'string', example: 'web'),
                        new OA\Property(property: 'users_count', type: 'integer', example: 3),
                        new OA\Property(property: 'permissions', type: 'array', items: new OA\Items(type: 'string', example: 'view_kasir')),
                    ], type: 'object')),
                ]
            )),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 403, description: 'Tidak punya izin view_resources'),
        ]
    )]
    public function index(): JsonResponse
    {
        $roles = \Spatie\Permission\Models\Role::with('permissions')
            ->withCount('users')
            ->orderBy('name')
            ->get()
            ->map(fn ($role) => [
                'id' => $role->id,
                'name' => $role->name,
                'guard_name' => $role->guard_name,
                'users_count' => (int) $role->users_count,
                'permissions' => $role->permissions->pluck('name')->values(),
            ])
            ->values();

        return $this->ok($roles, 'Daftar role berhasil diambil.');
    }

    #[OA\Get(
        path: '/api/v1/permissions',
        operationId: 'permissionIndex',
        summary: 'Daftar permission (rata & terkelompok)',
        description: 'Menampilkan seluruh permission yang terdaftar, diurutkan menurut nama. '
            . 'Balasan berisi dua bentuk sekaligus: `permissions` (daftar rata berisi id, nama, dan kategori) '
            . 'dan `grouped` (nama-nama permission dikelompokkan berdasarkan kolom `category`, '
            . 'permission tanpa kategori masuk ke grup "Lainnya"). '
            . 'Bentuk `grouped` memudahkan aplikasi menampilkan hak akses per modul.',
        tags: ['Manajemen'],
        security: [['sanctum' => []]],
        responses: [
            new OA\Response(response: 200, description: 'Daftar permission', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'message', type: 'string', example: 'Daftar permission berhasil diambil.'),
                    new OA\Property(property: 'data', properties: [
                        new OA\Property(property: 'permissions', type: 'array', items: new OA\Items(properties: [
                            new OA\Property(property: 'id', type: 'integer', example: 5),
                            new OA\Property(property: 'name', type: 'string', example: 'view_kasir'),
                            new OA\Property(property: 'category', type: 'string', nullable: true, example: 'Kasir'),
                        ], type: 'object')),
                        new OA\Property(property: 'grouped', type: 'object', example: ['Kasir' => ['view_kasir'], 'Finance' => ['view_finance']]),
                    ], type: 'object'),
                ]
            )),
            new OA\Response(response: 403, description: 'Tidak punya izin view_resources'),
        ]
    )]
    public function permissions(): JsonResponse
    {
        $permissions = \Spatie\Permission\Models\Permission::orderBy('name')->get();

        $flat = $permissions->map(fn ($p) => [
            'id' => $p->id,
            'name' => $p->name,
            'category' => $p->category ?? null,
        ])->values();

        $grouped = $permissions
            ->groupBy(fn ($p) => $p->category ?: 'Lainnya')
            ->map(fn ($group) => $group->pluck('name')->values());

        return $this->ok([
            'permissions' => $flat,
            'grouped' => $grouped,
        ], 'Daftar permission berhasil diambil.');
    }
}
