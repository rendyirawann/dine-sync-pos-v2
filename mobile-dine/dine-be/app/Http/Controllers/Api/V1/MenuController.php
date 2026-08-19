<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Api\BaseApiController;
use App\Http\Resources\IngredientResource;
use App\Http\Resources\MenuIngredientResource;
use App\Http\Resources\MenuResource;
use App\Models\Ingredient;
use App\Models\Menu;
use App\Models\MenuIngredient;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Arr;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use OpenApi\Attributes as OA;

/**
 * Data Master — Menu (produk yang dijual) + Resep/Bahan per menu.
 *
 * Gambar menu disimpan di folder per-tenant: tenants/{tenant_id}/menu/{file}.
 * Path tulis SELALU memakai app('tenant')->mediaDir('menu') agar tidak pernah
 * berbeda dengan accessor pembaca (Menu::image_url).
 */
class MenuController extends BaseApiController
{
    #[OA\Get(
        path: '/api/v1/menus',
        operationId: 'menuIndex',
        summary: 'Daftar menu',
        description: <<<'TXT'
Menampilkan daftar menu milik tenant aktif beserta kategorinya, diurutkan dari yang terbaru.

**Query yang didukung:**
- `search` — filter LIKE (tidak peka huruf besar/kecil) pada nama menu.
- `category_id` — hanya menu pada kategori tertentu.
- `is_available` — `1` hanya menu tersedia, `0` hanya menu habis.
- `per_page` — jumlah data per halaman (default 20, maksimal 100).
- `all=true` — kembalikan SELURUH menu tanpa paginasi. Dipakai layar kasir
  (grid menu) dan dropdown di aplikasi mobile, biasanya `?all=true&is_available=1`.

Setiap item sudah menyertakan `final_price` (harga setelah diskon per menu) dan `image_url`.
TXT,
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'search', in: 'query', required: false, description: 'Kata kunci nama menu.', schema: new OA\Schema(type: 'string'), example: 'ayam'),
            new OA\Parameter(name: 'category_id', in: 'query', required: false, description: 'Filter berdasarkan ID kategori.', schema: new OA\Schema(type: 'integer')),
            new OA\Parameter(name: 'is_available', in: 'query', required: false, description: 'Filter ketersediaan menu (1 = tersedia, 0 = habis).', schema: new OA\Schema(type: 'boolean')),
            new OA\Parameter(name: 'per_page', in: 'query', required: false, description: 'Jumlah data per halaman (default 20, maks 100).', schema: new OA\Schema(type: 'integer', default: 20)),
            new OA\Parameter(name: 'all', in: 'query', required: false, description: 'Bila true → seluruh data tanpa paginasi (kasir/dropdown).', schema: new OA\Schema(type: 'boolean')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Daftar menu (berpaginasi, atau seluruh data bila all=true)'),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 403, description: 'Tidak punya izin view_data_master'),
        ]
    )]
    public function index(Request $request): JsonResponse
    {
        $query = Menu::with('category')->orderBy('created_at', 'desc');

        $search = trim((string) $request->query('search', ''));

        if ($search !== '') {
            $query->whereRaw('LOWER(name) LIKE ?', ['%' . mb_strtolower($search) . '%']);
        }

        if ($request->filled('category_id')) {
            $query->where('category_id', $request->query('category_id'));
        }

        if ($request->filled('is_available')) {
            $query->where('is_available', $request->boolean('is_available'));
        }

        if ($request->boolean('all')) {
            return $this->ok(MenuResource::collection($query->get()), 'Daftar menu.');
        }

        return $this->paginated(
            MenuResource::collection($query->paginate($this->perPage(20))),
            'Daftar menu.'
        );
    }

    #[OA\Post(
        path: '/api/v1/menus',
        operationId: 'menuStore',
        summary: 'Tambah menu',
        description: <<<'TXT'
Menambah menu baru. Kirim sebagai `multipart/form-data` bila menyertakan gambar
(jpeg/png/jpg, maksimal 2 MB). Gambar disimpan pada folder per-tenant
`tenants/{tenant_id}/menu/` dan kolom `image` hanya menyimpan nama file-nya.

Bila `is_available` tidak dikirim, menu dianggap tersedia (`true`).
TXT,
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\MediaType(
                mediaType: 'multipart/form-data',
                schema: new OA\Schema(
                    required: ['category_id', 'name', 'price'],
                    properties: [
                        new OA\Property(property: 'category_id', type: 'integer', example: 1),
                        new OA\Property(property: 'name', type: 'string', maxLength: 255, example: 'Ayam Geprek'),
                        new OA\Property(property: 'price', type: 'number', format: 'float', example: 18000),
                        new OA\Property(property: 'discount_percent', type: 'integer', minimum: 0, maximum: 100, example: 10),
                        new OA\Property(property: 'description', type: 'string', example: 'Ayam goreng sambal bawang, pedas level 3.'),
                        new OA\Property(property: 'is_available', type: 'boolean', example: true),
                        new OA\Property(property: 'image', type: 'string', format: 'binary', description: 'File gambar menu (jpeg/png/jpg, maks 2 MB).'),
                    ]
                )
            )
        ),
        responses: [
            new OA\Response(response: 201, description: 'Menu berhasil ditambahkan'),
            new OA\Response(response: 422, description: 'Validasi gagal'),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
        ]
    )]
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'category_id' => ['required', 'exists:categories,id'],
            'name' => ['required', 'string', 'max:255'],
            'price' => ['required', 'numeric', 'min:0'],
            'discount_percent' => ['nullable', 'integer', 'min:0', 'max:100'],
            'description' => ['nullable', 'string'],
            'is_available' => ['nullable', 'boolean'],
            'image' => ['nullable', 'image', 'mimes:jpeg,png,jpg', 'max:2048'],
        ], [
            'category_id.required' => 'Kategori wajib dipilih.',
            'category_id.exists' => 'Kategori yang dipilih tidak ditemukan.',
            'name.required' => 'Nama Menu wajib diisi.',
            'name.max' => 'Nama Menu maksimal 255 karakter.',
            'price.required' => 'Harga wajib diisi.',
            'price.numeric' => 'Harga harus berupa angka.',
            'price.min' => 'Harga tidak boleh kurang dari 0.',
            'discount_percent.integer' => 'Diskon harus berupa angka bulat.',
            'discount_percent.min' => 'Diskon minimal 0%.',
            'discount_percent.max' => 'Diskon maksimal 100%.',
            'image.image' => 'File yang diunggah harus berupa gambar.',
            'image.mimes' => 'Format gambar harus jpeg, png, atau jpg.',
            'image.max' => 'Ukuran gambar maksimal 2 MB.',
        ]);

        $payload = [
            'category_id' => $data['category_id'],
            'name' => $data['name'],
            'description' => $data['description'] ?? null,
            'price' => $data['price'],
            'discount_percent' => $data['discount_percent'] ?? 0,
            // Default menu langsung tersedia bila field tidak dikirim aplikasi.
            'is_available' => $request->has('is_available') ? $request->boolean('is_available') : true,
        ];

        if ($request->hasFile('image')) {
            $file = $request->file('image');
            $filename = 'menu-' . time() . '.' . $file->getClientOriginalExtension();
            Storage::disk('public')->putFileAs(app('tenant')->mediaDir('menu'), $file, $filename);
            $payload['image'] = $filename;
        }

        $menu = Menu::create($payload);

        return $this->created(
            new MenuResource($menu->load('category')),
            'Menu berhasil ditambahkan!'
        );
    }

    #[OA\Get(
        path: '/api/v1/menus/{id}',
        operationId: 'menuShow',
        summary: 'Detail menu',
        description: 'Menampilkan satu menu lengkap dengan kategori dan daftar resep/bahan yang dipakai.',
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID menu.', schema: new OA\Schema(type: 'integer'), example: 1),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Detail menu'),
            new OA\Response(response: 404, description: 'Menu tidak ditemukan'),
        ]
    )]
    public function show($id): JsonResponse
    {
        $menu = Menu::with('category', 'ingredients.ingredient')->findOrFail($id);

        return $this->ok(new MenuResource($menu), 'Detail menu.');
    }

    #[OA\Put(
        path: '/api/v1/menus/{id}',
        operationId: 'menuUpdate',
        summary: 'Ubah menu',
        description: <<<'TXT'
Mengubah data menu. Field `image` bersifat opsional — bila gambar baru dikirim,
gambar lama pada folder tenant akan dihapus lebih dulu lalu diganti yang baru.

Karena PHP tidak mem-parsing `multipart/form-data` pada request PUT, aplikasi mobile
sebaiknya mengirim `POST /api/v1/menus/{id}` dengan field tambahan `_method=PUT`
saat mengunggah gambar. Tanpa gambar, PUT biasa (JSON) tetap bisa dipakai.

Field opsional yang TIDAK dikirim (`description`, `discount_percent`, `is_available`)
dibiarkan seperti nilai sebelumnya, jadi aman dipakai untuk update sebagian
(mis. hanya mengubah status tersedia/habis).
TXT,
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID menu.', schema: new OA\Schema(type: 'integer'), example: 1),
        ],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\MediaType(
                mediaType: 'multipart/form-data',
                schema: new OA\Schema(
                    required: ['category_id', 'name', 'price'],
                    properties: [
                        new OA\Property(property: 'category_id', type: 'integer', example: 1),
                        new OA\Property(property: 'name', type: 'string', maxLength: 255, example: 'Ayam Geprek Keju'),
                        new OA\Property(property: 'price', type: 'number', format: 'float', example: 21000),
                        new OA\Property(property: 'discount_percent', type: 'integer', minimum: 0, maximum: 100, example: 0),
                        new OA\Property(property: 'description', type: 'string', example: 'Dengan tambahan keju mozzarella.'),
                        new OA\Property(property: 'is_available', type: 'boolean', example: true),
                        new OA\Property(property: 'image', type: 'string', format: 'binary', description: 'Gambar baru (opsional).'),
                        new OA\Property(property: '_method', type: 'string', example: 'PUT', description: 'Wajib bila dikirim lewat POST multipart.'),
                    ]
                )
            )
        ),
        responses: [
            new OA\Response(response: 200, description: 'Menu berhasil diupdate'),
            new OA\Response(response: 422, description: 'Validasi gagal'),
            new OA\Response(response: 404, description: 'Menu tidak ditemukan'),
        ]
    )]
    public function update(Request $request, $id): JsonResponse
    {
        $menu = Menu::findOrFail($id);

        $data = $request->validate([
            'category_id' => ['required', 'exists:categories,id'],
            'name' => ['required', 'string', 'max:255'],
            'price' => ['required', 'numeric', 'min:0'],
            'discount_percent' => ['nullable', 'integer', 'min:0', 'max:100'],
            'description' => ['nullable', 'string'],
            'is_available' => ['nullable', 'boolean'],
            'image' => ['nullable', 'image', 'mimes:jpeg,png,jpg', 'max:2048'],
        ], [
            'category_id.required' => 'Kategori wajib dipilih.',
            'category_id.exists' => 'Kategori yang dipilih tidak ditemukan.',
            'name.required' => 'Nama Menu wajib diisi.',
            'name.max' => 'Nama Menu maksimal 255 karakter.',
            'price.required' => 'Harga wajib diisi.',
            'price.numeric' => 'Harga harus berupa angka.',
            'price.min' => 'Harga tidak boleh kurang dari 0.',
            'discount_percent.integer' => 'Diskon harus berupa angka bulat.',
            'discount_percent.min' => 'Diskon minimal 0%.',
            'discount_percent.max' => 'Diskon maksimal 100%.',
            'image.image' => 'File yang diunggah harus berupa gambar.',
            'image.mimes' => 'Format gambar harus jpeg, png, atau jpg.',
            'image.max' => 'Ukuran gambar maksimal 2 MB.',
        ]);

        // Hanya field yang benar-benar dikirim yang ikut diperbarui — field opsional
        // yang tidak dikirim tetap memakai nilai lamanya (aman untuk update sebagian).
        $payload = Arr::except($data, ['image']);

        // multipart/form-data selalu mengirim nilai sebagai string, jadi tipenya dinormalkan.
        if (array_key_exists('is_available', $payload)) {
            $payload['is_available'] = $request->boolean('is_available');
        }

        if (array_key_exists('discount_percent', $payload)) {
            $payload['discount_percent'] = (int) $payload['discount_percent'];
        }

        if ($request->hasFile('image')) {
            $dir = app('tenant')->mediaDir('menu');

            // Hapus gambar lama milik tenant ini agar storage tidak menumpuk.
            if ($menu->image && Storage::disk('public')->exists($dir . '/' . $menu->image)) {
                Storage::disk('public')->delete($dir . '/' . $menu->image);
            }

            $file = $request->file('image');
            $filename = 'menu-' . time() . '.' . $file->getClientOriginalExtension();
            Storage::disk('public')->putFileAs($dir, $file, $filename);
            $payload['image'] = $filename;
        }

        $menu->update($payload);

        return $this->ok(
            new MenuResource($menu->load('category')),
            'Menu berhasil diupdate!'
        );
    }

    #[OA\Delete(
        path: '/api/v1/menus/{id}',
        operationId: 'menuDestroy',
        summary: 'Hapus menu',
        description: 'Menghapus menu beserta file gambarnya pada folder tenant (bila ada).',
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID menu.', schema: new OA\Schema(type: 'integer'), example: 1),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Menu berhasil dihapus'),
            new OA\Response(response: 404, description: 'Menu tidak ditemukan'),
        ]
    )]
    public function destroy($id): JsonResponse
    {
        $menu = Menu::findOrFail($id);

        $dir = app('tenant')->mediaDir('menu');

        if ($menu->image && Storage::disk('public')->exists($dir . '/' . $menu->image)) {
            Storage::disk('public')->delete($dir . '/' . $menu->image);
        }

        $menu->delete();

        return $this->ok(null, 'Menu berhasil dihapus!');
    }

    #[OA\Get(
        path: '/api/v1/menus/{id}/recipes',
        operationId: 'menuRecipes',
        summary: 'Resep/bahan sebuah menu',
        description: <<<'TXT'
Menampilkan resep (komposisi bahan) sebuah menu, plus daftar seluruh bahan yang
tersedia di tenant — dipakai layar "Resep/Bahan" pada aplikasi mobile untuk
mengisi dropdown pemilihan bahan.

Balasan berisi tiga bagian: `menu`, `recipes`, dan `available_ingredients`.
TXT,
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID menu.', schema: new OA\Schema(type: 'integer'), example: 1),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Resep menu + daftar bahan tersedia'),
            new OA\Response(response: 404, description: 'Menu tidak ditemukan'),
        ]
    )]
    public function recipes($id): JsonResponse
    {
        $menu = Menu::with('category', 'ingredients.ingredient')->findOrFail($id);

        // withSum dipakai supaya kolom stok bahan tidak menghitung ulang per baris (hindari N+1).
        $ingredients = Ingredient::withSum('batches as stock', 'remaining_quantity')
            ->orderBy('name', 'asc')
            ->get();

        return $this->ok([
            'menu' => new MenuResource($menu),
            'recipes' => MenuIngredientResource::collection($menu->ingredients),
            'available_ingredients' => IngredientResource::collection($ingredients),
        ], 'Resep/bahan menu.');
    }

    #[OA\Post(
        path: '/api/v1/menus/{id}/recipes',
        operationId: 'menuUpdateRecipes',
        summary: 'Simpan resep/bahan sebuah menu',
        description: <<<'TXT'
Menyimpan ulang seluruh resep sebuah menu (perilaku *replace*): seluruh baris resep
lama dihapus lalu dibuat ulang dari payload, semuanya di dalam satu transaksi.

Kirim `recipes` sebagai array kosong (`[]`) untuk mengosongkan resep menu.
TXT,
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID menu.', schema: new OA\Schema(type: 'integer'), example: 1),
        ],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['recipes'],
                properties: [
                    new OA\Property(
                        property: 'recipes',
                        type: 'array',
                        items: new OA\Items(
                            required: ['ingredient_id', 'quantity'],
                            properties: [
                                new OA\Property(property: 'ingredient_id', type: 'integer', example: 3),
                                new OA\Property(property: 'quantity', type: 'number', format: 'float', example: 150.5),
                            ],
                            type: 'object'
                        ),
                        description: 'Daftar bahan + jumlah pemakaian per porsi.'
                    ),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 200, description: 'Resep/Bahan menu berhasil diperbarui'),
            new OA\Response(response: 422, description: 'Validasi gagal'),
            new OA\Response(response: 404, description: 'Menu tidak ditemukan'),
        ]
    )]
    public function updateRecipes(Request $request, $id): JsonResponse
    {
        $menu = Menu::findOrFail($id);

        $data = $request->validate([
            'recipes' => ['present', 'array'],
            'recipes.*.ingredient_id' => ['required', 'exists:ingredients,id'],
            'recipes.*.quantity' => ['required', 'numeric', 'min:0.01'],
        ], [
            'recipes.present' => 'Data resep wajib dikirim (boleh array kosong).',
            'recipes.array' => 'Format data resep tidak valid.',
            'recipes.*.ingredient_id.required' => 'Bahan wajib dipilih.',
            'recipes.*.ingredient_id.exists' => 'Bahan yang dipilih tidak ditemukan.',
            'recipes.*.quantity.required' => 'Jumlah pemakaian bahan wajib diisi.',
            'recipes.*.quantity.numeric' => 'Jumlah pemakaian bahan harus berupa angka.',
            'recipes.*.quantity.min' => 'Jumlah pemakaian bahan minimal 0.01.',
        ]);

        DB::transaction(function () use ($menu, $data) {
            MenuIngredient::where('menu_id', $menu->id)->delete();

            foreach ($data['recipes'] as $row) {
                MenuIngredient::create([
                    'menu_id' => $menu->id,
                    'ingredient_id' => $row['ingredient_id'],
                    'quantity' => $row['quantity'],
                ]);
            }
        });

        $menu->load('category', 'ingredients.ingredient');

        return $this->ok([
            'menu' => new MenuResource($menu),
            'recipes' => MenuIngredientResource::collection($menu->ingredients),
        ], 'Resep/Bahan menu berhasil diperbarui!');
    }
}
