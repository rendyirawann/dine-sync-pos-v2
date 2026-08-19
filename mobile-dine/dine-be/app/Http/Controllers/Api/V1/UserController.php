<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Api\BaseApiController;
use App\Http\Resources\UserResource;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use OpenApi\Attributes as OA;
use Spatie\Permission\Models\Role;

/**
 * Manajemen User (khusus Superadmin — route di-gate 'can:view_resources').
 *
 * Logika bisnis direplikasi dari UserController web, termasuk penentuan tenant target:
 * bila pemanggil punya konteks tenant (admin UMKM) maka user baru selalu masuk ke
 * tenant-nya sendiri; bila tanpa konteks (superadmin) tenant diambil dari input.
 * Pembuatan user dijalankan di dalam app('tenant')->runFor() supaya kolom tenant_id
 * terisi otomatis dan benar (hook creating pada trait BelongsToTenant).
 */
class UserController extends BaseApiController
{
    #[OA\Get(
        path: '/api/v1/users',
        operationId: 'userIndex',
        summary: 'Daftar user (berpaginasi)',
        description: 'Menampilkan daftar user beserta role dan UMKM-nya, terbaru di atas. '
            . 'Mendukung pencarian nama/username/email, filter berdasarkan nama role, dan filter per UMKM. '
            . 'Kirim `all=true` untuk mengambil seluruh data tanpa paginasi.',
        tags: ['Manajemen'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'search', description: 'Cari nama, username, atau email', in: 'query', required: false, schema: new OA\Schema(type: 'string', example: 'owner')),
            new OA\Parameter(name: 'role', description: 'Filter berdasarkan nama role (mis. admin, kasir)', in: 'query', required: false, schema: new OA\Schema(type: 'string', example: 'admin')),
            new OA\Parameter(name: 'tenant_id', description: 'Filter user milik satu UMKM (UUID tenant)', in: 'query', required: false, schema: new OA\Schema(type: 'string', format: 'uuid')),
            new OA\Parameter(name: 'all', description: 'Bila true, seluruh data dikembalikan tanpa paginasi', in: 'query', required: false, schema: new OA\Schema(type: 'boolean', example: false)),
            new OA\Parameter(name: 'per_page', description: 'Jumlah data per halaman (maks 100)', in: 'query', required: false, schema: new OA\Schema(type: 'integer', example: 20)),
            new OA\Parameter(name: 'page', description: 'Halaman ke-', in: 'query', required: false, schema: new OA\Schema(type: 'integer', example: 1)),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Daftar user berpaginasi (data + meta)'),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 403, description: 'Tidak punya izin view_resources'),
        ]
    )]
    public function index(Request $request): JsonResponse
    {
        $query = User::with('roles', 'tenant');

        if ($request->filled('search')) {
            $keyword = '%' . $request->query('search') . '%';
            $query->where(function ($q) use ($keyword) {
                $q->where('name', 'like', $keyword)
                    ->orWhere('username', 'like', $keyword)
                    ->orWhere('email', 'like', $keyword);
            });
        }

        if ($request->filled('role')) {
            $role = $request->query('role');
            $query->whereHas('roles', fn ($q) => $q->where('name', $role));
        }

        if ($request->filled('tenant_id')) {
            $query->where('tenant_id', $request->query('tenant_id'));
        }

        $query->orderBy('created_at', 'desc');

        if ($request->boolean('all')) {
            return $this->ok(
                UserResource::collection($query->get()),
                'Seluruh user berhasil diambil.'
            );
        }

        $paginator = $query->paginate($this->perPage());

        return $this->paginated(
            $paginator->through(fn ($user) => new UserResource($user)),
            'Daftar user berhasil diambil.'
        );
    }

    #[OA\Post(
        path: '/api/v1/users',
        operationId: 'userStore',
        summary: 'Tambah user baru',
        description: 'Membuat user baru pada UMKM tertentu. Field `roles` boleh berupa satu nama role '
            . '(string) maupun array nama role — keduanya didukung dan seluruhnya akan di-assign. '
            . 'User dibuat di dalam konteks tenant target sehingga kolom tenant_id terisi benar. '
            . 'Password otomatis di-hash, `is_active` diisi true, dan email langsung dianggap terverifikasi. '
            . 'Catatan keamanan: bila pemanggil sudah punya konteks tenant, user baru dipaksa masuk '
            . 'ke tenant tersebut (input tenant_id diabaikan) agar tidak bisa menitipkan user ke UMKM lain.',
        tags: ['Manajemen'],
        security: [['sanctum' => []]],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['name', 'username', 'email', 'password', 'roles', 'tenant_id'],
                properties: [
                    new OA\Property(property: 'name', type: 'string', maxLength: 255, example: 'Budi Santoso'),
                    new OA\Property(property: 'username', type: 'string', maxLength: 100, example: 'budi_kasir', description: 'Hanya huruf, angka, strip (-), dan underscore (_)'),
                    new OA\Property(property: 'email', type: 'string', format: 'email', example: 'budi@umkm.test'),
                    new OA\Property(property: 'no_wa', type: 'string', nullable: true, maxLength: 20, example: '081234567890'),
                    new OA\Property(property: 'password', type: 'string', format: 'password', minLength: 8, example: 'password123'),
                    new OA\Property(property: 'roles', example: 'kasir', description: 'Nama role (string) atau array nama role', oneOf: [
                        new OA\Schema(type: 'string'),
                        new OA\Schema(type: 'array', items: new OA\Items(type: 'string')),
                    ]),
                    new OA\Property(property: 'tenant_id', type: 'string', format: 'uuid', description: 'UMKM tempat user ini bernaung'),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 201, description: 'User berhasil ditambahkan'),
            new OA\Response(response: 422, description: 'Data yang dikirim tidak valid / role tidak dikenal'),
        ]
    )]
    public function store(Request $request): JsonResponse
    {
        $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'username' => ['required', 'string', 'max:100', 'alpha_dash', 'unique:users,username'],
            'email' => ['required', 'email', 'max:255', 'unique:users,email'],
            'no_wa' => ['nullable', 'string', 'max:20'],
            'password' => ['required', 'string', 'min:8'],
            'roles' => ['required'],
            'tenant_id' => ['required', 'exists:tenants,id'],
        ], [
            'name.required' => 'Nama lengkap wajib diisi.',
            'name.max' => 'Nama lengkap maksimal 255 karakter.',
            'username.required' => 'Username wajib diisi.',
            'username.max' => 'Username maksimal 100 karakter.',
            'username.alpha_dash' => 'Username hanya boleh huruf, angka, strip (-) dan underscore (_).',
            'username.unique' => 'Username sudah digunakan, pilih username lain.',
            'email.required' => 'Email wajib diisi.',
            'email.email' => 'Format email tidak valid.',
            'email.unique' => 'Email sudah terdaftar.',
            'no_wa.max' => 'Nomor WhatsApp maksimal 20 karakter.',
            'password.required' => 'Password wajib diisi.',
            'password.min' => 'Password minimal 8 karakter.',
            'roles.required' => 'Role wajib diisi.',
            'tenant_id.required' => 'UMKM (tenant) wajib dipilih.',
            'tenant_id.exists' => 'UMKM (tenant) tidak valid.',
        ]);

        $roles = $this->normalizeRoles($request->input('roles'));

        if ($invalid = $this->unknownRoles($roles)) {
            return $this->fail('Role tidak dikenal: ' . implode(', ', $invalid), 422, [
                'roles' => ['Role tidak dikenal: ' . implode(', ', $invalid)],
            ]);
        }

        // Admin UMKM hanya boleh membuat user di tenantnya sendiri; superadmin memakai input.
        $targetTenantId = app('tenant')->has() ? app('tenant')->id() : $request->tenant_id;

        $user = app('tenant')->runFor($targetTenantId, function () use ($request, $roles) {
            $u = new User;
            $u->name = $request->name;
            $u->username = $request->username;
            $u->email = $request->email;
            $u->no_wa = $request->no_wa;
            $u->password = $request->password; // di-hash otomatis lewat cast 'hashed'
            $u->is_active = true;
            $u->email_verified_at = now();
            $u->save();

            $u->assignRole($roles);

            return $u;
        });

        return $this->created(
            new UserResource($user->load('roles', 'tenant')),
            'User berhasil ditambahkan.'
        );
    }

    #[OA\Get(
        path: '/api/v1/users/{id}',
        operationId: 'userShow',
        summary: 'Detail satu user',
        description: 'Menampilkan satu user lengkap dengan role, UMKM, dan daftar permission efektifnya '
            . '(gabungan dari role dan permission langsung).',
        tags: ['Manajemen'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', description: 'UUID user', in: 'path', required: true, schema: new OA\Schema(type: 'string', format: 'uuid')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Detail user'),
            new OA\Response(response: 404, description: 'User tidak ditemukan'),
        ]
    )]
    public function show($id): JsonResponse
    {
        $user = User::with('roles', 'tenant')->findOrFail($id);

        $data = array_merge(
            (new UserResource($user))->resolve(),
            ['permissions' => $user->getAllPermissions()->pluck('name')->values()]
        );

        return $this->ok($data, 'Detail user berhasil diambil.');
    }

    #[OA\Put(
        path: '/api/v1/users/{id}',
        operationId: 'userUpdate',
        summary: 'Perbarui user',
        description: 'Memperbarui data user. Password hanya diubah bila field `password` diisi. '
            . 'Kolom `tenant_id` di-set eksplisit (update tidak melewati hook creating), sehingga '
            . 'superadmin dapat memindahkan user ke UMKM lain. Role lama dihapus lalu diganti dengan '
            . 'role yang dikirim (boleh string maupun array). Username tidak ikut diubah lewat endpoint ini.',
        tags: ['Manajemen'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', description: 'UUID user', in: 'path', required: true, schema: new OA\Schema(type: 'string', format: 'uuid')),
        ],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['name', 'email', 'roles', 'tenant_id'],
                properties: [
                    new OA\Property(property: 'name', type: 'string', maxLength: 255, example: 'Budi Santoso'),
                    new OA\Property(property: 'email', type: 'string', format: 'email', example: 'budi@umkm.test'),
                    new OA\Property(property: 'no_wa', type: 'string', nullable: true, maxLength: 20, example: '081234567890'),
                    new OA\Property(property: 'password', type: 'string', format: 'password', nullable: true, minLength: 8, example: 'passwordbaru', description: 'Kosongkan bila password tidak diubah'),
                    new OA\Property(property: 'roles', example: 'kasir', description: 'Nama role (string) atau array nama role', oneOf: [
                        new OA\Schema(type: 'string'),
                        new OA\Schema(type: 'array', items: new OA\Items(type: 'string')),
                    ]),
                    new OA\Property(property: 'tenant_id', type: 'string', format: 'uuid'),
                    new OA\Property(property: 'is_active', type: 'boolean', nullable: true, example: true),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 200, description: 'User berhasil diperbarui'),
            new OA\Response(response: 404, description: 'User tidak ditemukan'),
            new OA\Response(response: 422, description: 'Data yang dikirim tidak valid / role tidak dikenal'),
        ]
    )]
    public function update(Request $request, $id): JsonResponse
    {
        $user = User::findOrFail($id);

        $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'email' => ['required', 'email', 'max:255', Rule::unique('users', 'email')->ignore($id)],
            'no_wa' => ['nullable', 'string', 'max:20'],
            'password' => ['nullable', 'string', 'min:8'],
            'roles' => ['required'],
            'tenant_id' => ['required', 'exists:tenants,id'],
            'is_active' => ['nullable', 'boolean'],
        ], [
            'name.required' => 'Nama lengkap wajib diisi.',
            'name.max' => 'Nama lengkap maksimal 255 karakter.',
            'email.required' => 'Email wajib diisi.',
            'email.email' => 'Format email tidak valid.',
            'email.unique' => 'Email sudah terdaftar.',
            'no_wa.max' => 'Nomor WhatsApp maksimal 20 karakter.',
            'password.min' => 'Password minimal 8 karakter.',
            'roles.required' => 'Role wajib diisi.',
            'tenant_id.required' => 'UMKM (tenant) wajib dipilih.',
            'tenant_id.exists' => 'UMKM (tenant) tidak valid.',
            'is_active.boolean' => 'Status aktif harus berupa true atau false.',
        ]);

        $roles = $this->normalizeRoles($request->input('roles'));

        if ($invalid = $this->unknownRoles($roles)) {
            return $this->fail('Role tidak dikenal: ' . implode(', ', $invalid), 422, [
                'roles' => ['Role tidak dikenal: ' . implode(', ', $invalid)],
            ]);
        }

        // Admin UMKM tetap di tenantnya sendiri; superadmin boleh memindah user antar UMKM.
        $targetTenantId = app('tenant')->has() ? app('tenant')->id() : $request->tenant_id;

        $user->name = $request->name;
        $user->email = $request->email;
        $user->no_wa = $request->no_wa;
        $user->tenant_id = $targetTenantId; // update tidak punya hook creating, set eksplisit

        if ($request->filled('password')) {
            $user->password = $request->password; // di-hash otomatis lewat cast 'hashed'
        }

        if ($request->has('is_active')) {
            $user->is_active = $request->boolean('is_active');
        }

        $user->save();

        // Ganti seluruh role lama dengan role yang dikirim.
        $user->syncRoles([]);
        $user->assignRole($roles);

        return $this->ok(
            new UserResource($user->fresh()->load('roles', 'tenant')),
            'User berhasil diperbarui.'
        );
    }

    #[OA\Delete(
        path: '/api/v1/users/{id}',
        operationId: 'userDestroy',
        summary: 'Hapus user',
        description: 'Menghapus user secara permanen. Akun yang sedang login TIDAK boleh dihapus. '
            . 'Sebelum user dihapus, seluruh token API dan relasi role-nya dibersihkan '
            . 'agar tidak ada sesi atau relasi menggantung.',
        tags: ['Manajemen'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', description: 'UUID user', in: 'path', required: true, schema: new OA\Schema(type: 'string', format: 'uuid')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'User berhasil dihapus'),
            new OA\Response(response: 404, description: 'User tidak ditemukan'),
            new OA\Response(response: 422, description: 'Tidak dapat menghapus akun sendiri'),
        ]
    )]
    public function destroy($id): JsonResponse
    {
        $user = User::findOrFail($id);

        if ((string) $user->id === (string) auth()->id()) {
            return $this->fail('Tidak dapat menghapus akun Anda sendiri.', 422);
        }

        $user->tokens()->delete();
        $user->syncRoles([]);
        $user->delete();

        return $this->ok(null, 'User berhasil dihapus.');
    }

    #[OA\Post(
        path: '/api/v1/users/{id}/ban',
        operationId: 'userBan',
        summary: 'Bekukan (ban) user',
        description: 'Membekukan akun user dengan mengisi kolom `banned_at`. Seluruh token API user '
            . 'tersebut langsung dihapus sehingga sesi aktifnya di aplikasi mobile ikut berakhir '
            . 'dan tidak bisa login kembali. Akun sendiri tidak boleh dibekukan.',
        tags: ['Manajemen'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', description: 'UUID user', in: 'path', required: true, schema: new OA\Schema(type: 'string', format: 'uuid')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'User berhasil dibekukan'),
            new OA\Response(response: 404, description: 'User tidak ditemukan'),
            new OA\Response(response: 422, description: 'Tidak dapat membekukan akun sendiri'),
        ]
    )]
    public function ban($id): JsonResponse
    {
        $user = User::findOrFail($id);

        if ((string) $user->id === (string) auth()->id()) {
            return $this->fail('Tidak dapat membekukan akun Anda sendiri.', 422);
        }

        $user->update(['banned_at' => now()]);

        // Putus semua sesi mobile user tersebut.
        $user->tokens()->delete();

        return $this->ok(
            new UserResource($user->fresh()->load('roles', 'tenant')),
            'User berhasil dibekukan.'
        );
    }

    #[OA\Post(
        path: '/api/v1/users/{id}/unban',
        operationId: 'userUnban',
        summary: 'Aktifkan kembali user yang dibekukan',
        description: 'Mengosongkan kolom `banned_at` sehingga user dapat login kembali. '
            . 'Token lama tetap terhapus, jadi user harus login ulang untuk mendapatkan token baru.',
        tags: ['Manajemen'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', description: 'UUID user', in: 'path', required: true, schema: new OA\Schema(type: 'string', format: 'uuid')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'User berhasil diaktifkan kembali'),
            new OA\Response(response: 404, description: 'User tidak ditemukan'),
        ]
    )]
    public function unban($id): JsonResponse
    {
        $user = User::findOrFail($id);

        $user->update(['banned_at' => null]);

        return $this->ok(
            new UserResource($user->fresh()->load('roles', 'tenant')),
            'User berhasil diaktifkan kembali.'
        );
    }

    /**
     * Terima `roles` berupa string tunggal maupun array, keluarkan array nama role bersih.
     */
    private function normalizeRoles(mixed $roles): array
    {
        return collect(is_array($roles) ? $roles : [$roles])
            ->map(fn ($role) => is_string($role) ? trim($role) : $role)
            ->filter(fn ($role) => $role !== null && $role !== '')
            ->unique()
            ->values()
            ->all();
    }

    /**
     * Daftar nama role yang tidak ada di database (untuk pesan validasi yang jelas).
     */
    private function unknownRoles(array $roles): array
    {
        if ($roles === []) {
            return [];
        }

        $existing = Role::whereIn('name', $roles)->pluck('name')->all();

        return array_values(array_diff($roles, $existing));
    }
}
