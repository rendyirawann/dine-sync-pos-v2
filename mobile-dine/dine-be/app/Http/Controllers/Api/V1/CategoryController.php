<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Api\BaseApiController;
use App\Http\Resources\CategoryResource;
use App\Models\Category;
use App\Models\Menu;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use OpenApi\Attributes as OA;

/**
 * Data Master — Kategori Menu.
 *
 * Slug dibuat otomatis dari nama (Str::slug) dan HARUS unik per tenant.
 * Semua query di sini sudah ter-scope tenant otomatis (trait BelongsToTenant),
 * jadi tidak ada filter tenant_id manual.
 */
class CategoryController extends BaseApiController
{
    #[OA\Get(
        path: '/api/v1/categories',
        operationId: 'categoryIndex',
        summary: 'Daftar kategori menu',
        description: <<<'TXT'
Menampilkan daftar kategori menu milik tenant aktif, diurutkan berdasarkan nama (A-Z).

**Query yang didukung:**
- `search` — filter LIKE (tidak peka huruf besar/kecil) pada `name` dan `slug`.
- `per_page` — jumlah data per halaman (default 20, maksimal 100).
- `all=true` — kembalikan SELURUH kategori tanpa paginasi. Dipakai layar kasir
  dan dropdown pada form menu di aplikasi mobile.

Setiap item menyertakan `menus_count`, yaitu jumlah menu yang memakai kategori tersebut.
TXT,
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'search', in: 'query', required: false, description: 'Kata kunci nama / slug kategori.', schema: new OA\Schema(type: 'string'), example: 'minuman'),
            new OA\Parameter(name: 'per_page', in: 'query', required: false, description: 'Jumlah data per halaman (default 20, maks 100).', schema: new OA\Schema(type: 'integer', default: 20)),
            new OA\Parameter(name: 'all', in: 'query', required: false, description: 'Bila true → seluruh data tanpa paginasi (dropdown/kasir).', schema: new OA\Schema(type: 'boolean')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Daftar kategori (berpaginasi, atau seluruh data bila all=true)'),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 403, description: 'Tidak punya izin view_data_master'),
        ]
    )]
    public function index(Request $request): JsonResponse
    {
        $query = Category::query()
            // Jumlah menu per kategori. Model Category belum punya relasi hasMany(Menu),
            // jadi hitungannya dibuat sebagai subquery yang tetap ter-scope tenant
            // (query builder Menu membawa TenantScope-nya sendiri).
            ->addSelect([
                'menus_count' => Menu::query()
                    ->selectRaw('count(*)')
                    ->whereColumn('menus.category_id', 'categories.id'),
            ])
            ->orderBy('name', 'asc');

        $search = trim((string) $request->query('search', ''));

        if ($search !== '') {
            $like = '%' . mb_strtolower($search) . '%';

            $query->where(function ($q) use ($like) {
                $q->whereRaw('LOWER(name) LIKE ?', [$like])
                    ->orWhereRaw('LOWER(slug) LIKE ?', [$like]);
            });
        }

        if ($request->boolean('all')) {
            return $this->ok(CategoryResource::collection($query->get()), 'Daftar kategori.');
        }

        return $this->paginated(
            CategoryResource::collection($query->paginate($this->perPage(20))),
            'Daftar kategori.'
        );
    }

    #[OA\Post(
        path: '/api/v1/categories',
        operationId: 'categoryStore',
        summary: 'Tambah kategori menu',
        description: 'Menambah kategori baru. Slug dibuat otomatis dari nama dan wajib unik di dalam tenant yang sama.',
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['name'],
                properties: [
                    new OA\Property(property: 'name', type: 'string', maxLength: 255, example: 'Minuman Dingin'),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 201, description: 'Kategori berhasil ditambahkan'),
            new OA\Response(response: 422, description: 'Validasi gagal / slug duplikat'),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
        ]
    )]
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
        ], [
            'name.required' => 'Nama Kategori wajib diisi.',
            'name.max' => 'Nama Kategori maksimal 255 karakter.',
        ]);

        $slug = Str::slug($data['name']);

        if (Category::where('slug', $slug)->exists()) {
            return $this->fail('Kategori ini sudah ada (Slug duplikat).', 422, [
                'name' => ['Kategori ini sudah ada (Slug duplikat).'],
            ]);
        }

        $category = Category::create([
            'name' => $data['name'],
            'slug' => $slug,
        ]);

        return $this->created(new CategoryResource($category), 'Kategori berhasil ditambahkan.');
    }

    #[OA\Get(
        path: '/api/v1/categories/{id}',
        operationId: 'categoryShow',
        summary: 'Detail kategori menu',
        description: 'Menampilkan satu kategori beserta jumlah menu yang memakainya.',
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID kategori.', schema: new OA\Schema(type: 'integer'), example: 1),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Detail kategori'),
            new OA\Response(response: 404, description: 'Kategori tidak ditemukan'),
        ]
    )]
    public function show($id): JsonResponse
    {
        $category = Category::query()
            ->addSelect([
                'menus_count' => Menu::query()
                    ->selectRaw('count(*)')
                    ->whereColumn('menus.category_id', 'categories.id'),
            ])
            ->findOrFail($id);

        return $this->ok(new CategoryResource($category), 'Detail kategori.');
    }

    #[OA\Put(
        path: '/api/v1/categories/{id}',
        operationId: 'categoryUpdate',
        summary: 'Ubah kategori menu',
        description: 'Mengubah nama kategori. Slug dibuat ulang dari nama baru dan dicek agar tidak bentrok dengan kategori lain di tenant yang sama.',
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID kategori.', schema: new OA\Schema(type: 'integer'), example: 1),
        ],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['name'],
                properties: [
                    new OA\Property(property: 'name', type: 'string', maxLength: 255, example: 'Minuman Panas'),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 200, description: 'Kategori berhasil diperbarui'),
            new OA\Response(response: 422, description: 'Validasi gagal / slug duplikat'),
            new OA\Response(response: 404, description: 'Kategori tidak ditemukan'),
        ]
    )]
    public function update(Request $request, $id): JsonResponse
    {
        $category = Category::findOrFail($id);

        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
        ], [
            'name.required' => 'Nama Kategori wajib diisi.',
            'name.max' => 'Nama Kategori maksimal 255 karakter.',
        ]);

        $slug = Str::slug($data['name']);

        if (Category::where('slug', $slug)->where('id', '!=', $category->id)->exists()) {
            return $this->fail('Kategori ini sudah ada (Slug duplikat).', 422, [
                'name' => ['Kategori ini sudah ada (Slug duplikat).'],
            ]);
        }

        $category->update([
            'name' => $data['name'],
            'slug' => $slug,
        ]);

        return $this->ok(new CategoryResource($category), 'Kategori berhasil diperbarui.');
    }

    #[OA\Delete(
        path: '/api/v1/categories/{id}',
        operationId: 'categoryDestroy',
        summary: 'Hapus kategori menu',
        description: 'Menghapus kategori. Kategori yang masih dipakai oleh menu tidak boleh dihapus (dibalas 409) agar data menu tidak ikut terhapus.',
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID kategori.', schema: new OA\Schema(type: 'integer'), example: 1),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Kategori berhasil dihapus'),
            new OA\Response(response: 409, description: 'Kategori masih dipakai menu'),
            new OA\Response(response: 404, description: 'Kategori tidak ditemukan'),
        ]
    )]
    public function destroy($id): JsonResponse
    {
        $category = Category::findOrFail($id);

        if (Menu::where('category_id', $category->id)->exists()) {
            return $this->fail('Kategori gagal dihapus karena sedang digunakan oleh menu.', 409);
        }

        $category->delete();

        return $this->ok(null, 'Kategori berhasil dihapus.');
    }
}
