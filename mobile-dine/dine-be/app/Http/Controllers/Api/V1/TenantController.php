<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Api\BaseApiController;
use App\Http\Resources\TenantResource;
use App\Models\Setting;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Laravel\Sanctum\PersonalAccessToken;
use OpenApi\Attributes as OA;

/**
 * Kelola UMKM / Tenant (khusus Superadmin — route di-gate 'can:view_resources').
 *
 * CATATAN PENTING: model Tenant TIDAK memakai global scope tenant (dia adalah
 * registry tenant-nya, bukan data milik tenant). Karena itu SATU-SATUNYA controller
 * yang boleh menyentuh kolom tenant_id secara manual adalah controller ini.
 * Saat membuat data milik tenant baru (Setting & user owner) prosesnya dibungkus
 * app('tenant')->runFor($tenant->id, ...) agar tenant_id terisi otomatis dan benar.
 *
 * Logika bisnis direplikasi dari TenantController web.
 */
class TenantController extends BaseApiController
{
    /**
     * Urutan tabel penghapusan data tenant: anak lebih dulu, induk terakhir,
     * supaya aman terhadap foreign key.
     */
    private const TENANT_TABLES = [
        'stock_opname_details', 'stock_movements', 'stock_opnames',
        'order_details', 'orders', 'menu_ingredients', 'ingredient_batches',
        'ingredients', 'suppliers', 'menus', 'categories', 'tables',
        'promos', 'queues', 'shifts', 'expenses', 'daily_budgets',
        'daily_sales_targets', 'settings', 'users',
    ];

    #[OA\Get(
        path: '/api/v1/tenants',
        operationId: 'tenantIndex',
        summary: 'Daftar UMKM (berpaginasi)',
        description: 'Menampilkan seluruh UMKM beserta jumlah usernya, terbaru di atas. '
            . 'Mendukung pencarian pada nama maupun slug. Kirim `all=true` untuk mengambil '
            . 'seluruh data tanpa paginasi (mis. untuk mengisi dropdown UMKM pada form user).',
        tags: ['Manajemen'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'search', description: 'Cari nama atau slug UMKM', in: 'query', required: false, schema: new OA\Schema(type: 'string', example: 'warung')),
            new OA\Parameter(name: 'all', description: 'Bila true, seluruh data dikembalikan tanpa paginasi', in: 'query', required: false, schema: new OA\Schema(type: 'boolean', example: false)),
            new OA\Parameter(name: 'per_page', description: 'Jumlah data per halaman (maks 100)', in: 'query', required: false, schema: new OA\Schema(type: 'integer', example: 20)),
            new OA\Parameter(name: 'page', description: 'Halaman ke-', in: 'query', required: false, schema: new OA\Schema(type: 'integer', example: 1)),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Daftar UMKM berpaginasi (data + meta)'),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 403, description: 'Tidak punya izin view_resources'),
        ]
    )]
    public function index(Request $request): JsonResponse
    {
        $query = Tenant::withCount('users');

        if ($request->filled('search')) {
            $keyword = '%' . $request->query('search') . '%';
            $query->where(function ($q) use ($keyword) {
                $q->where('name', 'like', $keyword)
                    ->orWhere('slug', 'like', $keyword);
            });
        }

        $query->orderBy('created_at', 'desc');

        if ($request->boolean('all')) {
            return $this->ok(
                TenantResource::collection($query->get()),
                'Seluruh UMKM berhasil diambil.'
            );
        }

        $paginator = $query->paginate($this->perPage());

        return $this->paginated(
            $paginator->through(fn ($tenant) => new TenantResource($tenant)),
            'Daftar UMKM berhasil diambil.'
        );
    }

    #[OA\Post(
        path: '/api/v1/tenants',
        operationId: 'tenantStore',
        summary: 'Buat UMKM baru beserta akun owner-nya',
        description: 'Membuat satu UMKM baru sekaligus data awalnya, seluruhnya dalam satu transaksi: '
            . '(1) baris Tenant dengan slug unik hasil slugify nama (bila bentrok ditambah sufiks -1, -2, dst) '
            . 'dan `is_active` = true; (2) di dalam konteks tenant baru: baris Setting (nama toko = nama UMKM, '
            . 'pajak 10%) dan satu user owner dengan username unik hasil slugify nama owner, status aktif, '
            . 'email langsung terverifikasi, lalu diberi role `admin`. '
            . 'Bila salah satu langkah gagal, semuanya dibatalkan.',
        tags: ['Manajemen'],
        security: [['sanctum' => []]],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['name', 'owner_name', 'owner_email', 'owner_password'],
                properties: [
                    new OA\Property(property: 'name', type: 'string', maxLength: 255, example: 'Warung Bu Sri', description: 'Nama UMKM'),
                    new OA\Property(property: 'trial_ends_at', type: 'string', format: 'date', nullable: true, example: '2026-09-19', description: 'Tanggal masa uji coba berakhir (opsional)'),
                    new OA\Property(property: 'owner_name', type: 'string', maxLength: 255, example: 'Sri Wahyuni'),
                    new OA\Property(property: 'owner_email', type: 'string', format: 'email', example: 'sri@warungbusri.test'),
                    new OA\Property(property: 'owner_password', type: 'string', format: 'password', minLength: 6, example: 'rahasia123'),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 201, description: 'UMKM & akun owner berhasil dibuat'),
            new OA\Response(response: 422, description: 'Data yang dikirim tidak valid'),
        ]
    )]
    public function store(Request $request): JsonResponse
    {
        $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'trial_ends_at' => ['nullable', 'date'],
            'owner_name' => ['required', 'string', 'max:255'],
            'owner_email' => ['required', 'email', 'max:255', 'unique:users,email'],
            'owner_password' => ['required', 'string', 'min:6'],
        ], [
            'name.required' => 'Nama UMKM wajib diisi.',
            'name.max' => 'Nama UMKM maksimal 255 karakter.',
            'trial_ends_at.date' => 'Format tanggal akhir masa uji coba tidak valid.',
            'owner_name.required' => 'Nama owner wajib diisi.',
            'owner_name.max' => 'Nama owner maksimal 255 karakter.',
            'owner_email.required' => 'Email owner wajib diisi.',
            'owner_email.email' => 'Format email owner tidak valid.',
            'owner_email.unique' => 'Email owner sudah terdaftar.',
            'owner_password.required' => 'Password owner wajib diisi.',
            'owner_password.min' => 'Password owner minimal 6 karakter.',
        ]);

        $tenant = DB::transaction(function () use ($request) {
            $tenant = Tenant::create([
                'name' => $request->name,
                'slug' => $this->uniqueSlug($request->name),
                'is_active' => true,
                'trial_ends_at' => $request->trial_ends_at,
            ]);

            // Data awal milik tenant baru dibuat DI DALAM konteks tenant tersebut,
            // supaya tenant_id terisi otomatis oleh trait BelongsToTenant.
            app('tenant')->runFor($tenant->id, function () use ($request) {
                Setting::create([
                    'store_name' => $request->name,
                    'tax_rate' => 10,
                ]);

                $owner = new User;
                $owner->name = $request->owner_name;
                $owner->username = $this->uniqueUsername($request->owner_name);
                $owner->email = $request->owner_email;
                $owner->password = $request->owner_password; // di-hash otomatis lewat cast 'hashed'
                $owner->is_active = true;
                $owner->email_verified_at = now();
                $owner->save();

                $owner->assignRole('admin');
            });

            return $tenant;
        });

        return $this->created(
            new TenantResource($tenant->loadCount('users')),
            'UMKM baru beserta akun owner-nya berhasil dibuat.'
        );
    }

    #[OA\Put(
        path: '/api/v1/tenants/{id}',
        operationId: 'tenantUpdate',
        summary: 'Perbarui data UMKM',
        description: 'Memperbarui nama, slug, masa uji coba, dan status aktif satu UMKM. '
            . 'Slug wajib unik antar UMKM dan tetap di-slugify ulang agar aman dipakai di URL publik '
            . '(kiosk & layar antrian).',
        tags: ['Manajemen'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', description: 'UUID UMKM', in: 'path', required: true, schema: new OA\Schema(type: 'string', format: 'uuid')),
        ],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['name', 'slug'],
                properties: [
                    new OA\Property(property: 'name', type: 'string', maxLength: 255, example: 'Warung Bu Sri'),
                    new OA\Property(property: 'slug', type: 'string', maxLength: 255, example: 'warung-bu-sri', description: 'Hanya huruf, angka, strip (-) dan underscore (_)'),
                    new OA\Property(property: 'trial_ends_at', type: 'string', format: 'date', nullable: true, example: '2026-09-19'),
                    new OA\Property(property: 'is_active', type: 'boolean', nullable: true, example: true),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 200, description: 'Data UMKM berhasil diperbarui'),
            new OA\Response(response: 404, description: 'UMKM tidak ditemukan'),
            new OA\Response(response: 422, description: 'Data yang dikirim tidak valid'),
        ]
    )]
    public function update(Request $request, $id): JsonResponse
    {
        $tenant = Tenant::findOrFail($id);

        $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'slug' => ['required', 'string', 'max:255', 'alpha_dash', Rule::unique('tenants', 'slug')->ignore($tenant->id)],
            'trial_ends_at' => ['nullable', 'date'],
            'is_active' => ['nullable', 'boolean'],
        ], [
            'name.required' => 'Nama UMKM wajib diisi.',
            'name.max' => 'Nama UMKM maksimal 255 karakter.',
            'slug.required' => 'Slug UMKM wajib diisi.',
            'slug.alpha_dash' => 'Slug hanya boleh huruf, angka, strip (-) dan underscore (_).',
            'slug.unique' => 'Slug sudah dipakai UMKM lain.',
            'trial_ends_at.date' => 'Format tanggal akhir masa uji coba tidak valid.',
            'is_active.boolean' => 'Status aktif harus berupa true atau false.',
        ]);

        $tenant->update([
            'name' => $request->name,
            'slug' => Str::slug($request->slug),
            'trial_ends_at' => $request->trial_ends_at,
            'is_active' => $request->has('is_active') ? $request->boolean('is_active') : $tenant->is_active,
        ]);

        return $this->ok(
            new TenantResource($tenant->fresh()->loadCount('users')),
            'Data UMKM berhasil diperbarui.'
        );
    }

    #[OA\Post(
        path: '/api/v1/tenants/{id}/toggle',
        operationId: 'tenantToggle',
        summary: 'Aktifkan / nonaktifkan UMKM',
        description: 'Membalik status aktif satu UMKM. Bila UMKM menjadi NONAKTIF, seluruh token API '
            . 'milik user UMKM tersebut langsung dihapus sehingga aplikasi mobile mereka tidak bisa '
            . 'lagi mengakses API dan harus login ulang setelah UMKM diaktifkan kembali.',
        tags: ['Manajemen'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', description: 'UUID UMKM', in: 'path', required: true, schema: new OA\Schema(type: 'string', format: 'uuid')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Status UMKM berhasil diubah'),
            new OA\Response(response: 404, description: 'UMKM tidak ditemukan'),
        ]
    )]
    public function toggle($id): JsonResponse
    {
        $tenant = Tenant::findOrFail($id);

        $tenant->update(['is_active' => ! $tenant->is_active]);

        if (! $tenant->is_active) {
            $this->revokeTenantTokens($tenant->id);
        }

        $status = $tenant->is_active ? 'diaktifkan' : 'dinonaktifkan';

        return $this->ok(
            new TenantResource($tenant->fresh()->loadCount('users')),
            "UMKM {$tenant->name} berhasil {$status}."
        );
    }

    #[OA\Delete(
        path: '/api/v1/tenants/{id}',
        operationId: 'tenantDestroy',
        summary: 'Hapus UMKM beserta SELURUH datanya',
        description: 'PERMANEN dan tidak bisa dibatalkan. Menghapus seluruh data milik UMKM dengan urutan '
            . 'anak lebih dulu lalu induk (stock_opname_details, stock_movements, stock_opnames, order_details, '
            . 'orders, menu_ingredients, ingredient_batches, ingredients, suppliers, menus, categories, tables, '
            . 'promos, queues, shifts, expenses, daily_budgets, daily_sales_targets, settings, users) agar aman '
            . 'terhadap foreign key. Sebelum tabel users dihapus, relasi role/permission (model_has_roles & '
            . 'model_has_permissions) dan seluruh token API milik user UMKM tersebut dibersihkan lebih dahulu. '
            . 'Barisan Tenant dihapus paling akhir. Semuanya berjalan dalam satu transaksi database.',
        tags: ['Manajemen'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', description: 'UUID UMKM', in: 'path', required: true, schema: new OA\Schema(type: 'string', format: 'uuid')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'UMKM beserta seluruh datanya telah dihapus'),
            new OA\Response(response: 404, description: 'UMKM tidak ditemukan'),
        ]
    )]
    public function destroy($id): JsonResponse
    {
        $tenant = Tenant::findOrFail($id);

        DB::transaction(function () use ($tenant) {
            // 1. Bersihkan relasi role/permission + token milik user tenant ini.
            $userIds = DB::table('users')->where('tenant_id', $tenant->id)->pluck('id');

            if ($userIds->isNotEmpty()) {
                DB::table('model_has_roles')->whereIn('model_id', $userIds)->delete();
                DB::table('model_has_permissions')->whereIn('model_id', $userIds)->delete();
            }

            $this->revokeTenantTokens($tenant->id);

            // 2. Hapus seluruh data milik tenant (anak -> induk).
            foreach (self::TENANT_TABLES as $table) {
                DB::table($table)->where('tenant_id', $tenant->id)->delete();
            }

            // 3. Terakhir, hapus registry tenant-nya.
            $tenant->delete();
        });

        return $this->ok(null, 'UMKM beserta seluruh datanya telah dihapus.');
    }

    /**
     * Hapus seluruh token Sanctum milik user sebuah tenant.
     * Sengaja memakai withoutGlobalScopes() agar tidak bergantung pada konteks tenant aktif
     * (superadmin memang tidak punya konteks), dan getMorphClass() supaya tetap benar
     * bila suatu saat morph map dipakai.
     */
    private function revokeTenantTokens(string $tenantId): void
    {
        $userIds = User::withoutGlobalScopes()->where('tenant_id', $tenantId)->pluck('id');

        if ($userIds->isEmpty()) {
            return;
        }

        PersonalAccessToken::where('tokenable_type', (new User)->getMorphClass())
            ->whereIn('tokenable_id', $userIds)
            ->delete();
    }

    /**
     * Slug unik untuk tenant baru: slugify nama, tambahkan sufiks -1, -2, ... bila bentrok.
     */
    private function uniqueSlug(string $name): string
    {
        $base = Str::slug($name) ?: 'umkm';
        $slug = $base;
        $i = 1;

        while (Tenant::where('slug', $slug)->exists()) {
            $slug = $base . '-' . $i;
            $i++;
        }

        return $slug;
    }

    /**
     * Username unik untuk owner: slugify nama dengan underscore, tambahkan sufiks _1, _2, ...
     * Dicek lewat DB::table agar tidak terpengaruh scope tenant (username unik global).
     */
    private function uniqueUsername(string $name): string
    {
        $base = Str::slug($name, '_') ?: 'owner';
        $username = $base;
        $i = 1;

        while (DB::table('users')->where('username', $username)->exists()) {
            $username = $base . '_' . $i;
            $i++;
        }

        return $username;
    }
}
