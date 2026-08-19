<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Api\BaseApiController;
use App\Http\Resources\IngredientBatchResource;
use App\Http\Resources\IngredientResource;
use App\Models\Ingredient;
use App\Models\IngredientBatch;
use App\Models\MenuIngredient;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Pagination\LengthAwarePaginator;
use OpenApi\Attributes as OA;

/**
 * Data Master — Bahan makanan (ingredients).
 *
 * Stok bahan TIDAK disimpan sebagai satu kolom, melainkan dihitung dari
 * penjumlahan remaining_quantity seluruh batch (FIFO/FEFO). Karena itu setiap
 * query daftar memakai withSum('batches as stock') supaya tidak N+1.
 */
class IngredientController extends BaseApiController
{
    /** Satuan yang diizinkan (sinkron dengan dropdown pada aplikasi mobile). */
    private const UNITS = ['gram', 'kg', 'ml', 'liter', 'pcs', 'slice', 'bungkus'];

    #[OA\Get(
        path: '/api/v1/ingredients',
        operationId: 'ingredientIndex',
        summary: 'Daftar bahan makanan + stok saat ini',
        description: <<<'TXT'
Menampilkan daftar bahan makanan milik tenant aktif, diurutkan berdasarkan nama (A-Z).
Tiap item sudah membawa `current_stock` (total sisa seluruh batch), `minimum_stock`,
`is_low_stock`, dan `stock_label` siap tampil.

**Query yang didukung:**
- `search` — filter LIKE (tidak peka huruf besar/kecil) pada nama bahan.
- `low_stock=true` — hanya bahan yang stoknya sudah menyentuh/di bawah stok minimum
  (dipakai widget peringatan stok di aplikasi mobile).
- `per_page` — jumlah data per halaman (default 20, maksimal 100).
- `all=true` — kembalikan SELURUH bahan tanpa paginasi. Dipakai dropdown pemilihan
  bahan pada form resep menu dan form stok masuk.
TXT,
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'search', in: 'query', required: false, description: 'Kata kunci nama bahan.', schema: new OA\Schema(type: 'string'), example: 'ayam'),
            new OA\Parameter(name: 'low_stock', in: 'query', required: false, description: 'Bila true → hanya bahan dengan stok <= stok minimum.', schema: new OA\Schema(type: 'boolean')),
            new OA\Parameter(name: 'per_page', in: 'query', required: false, description: 'Jumlah data per halaman (default 20, maks 100).', schema: new OA\Schema(type: 'integer', default: 20)),
            new OA\Parameter(name: 'all', in: 'query', required: false, description: 'Bila true → seluruh data tanpa paginasi (dropdown resep/stok).', schema: new OA\Schema(type: 'boolean')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Daftar bahan (berpaginasi, atau seluruh data bila all=true)'),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 403, description: 'Tidak punya izin view_data_master'),
        ]
    )]
    public function index(Request $request): JsonResponse
    {
        $query = Ingredient::withSum('batches as stock', 'remaining_quantity')
            ->orderBy('name', 'asc');

        $search = trim((string) $request->query('search', ''));

        if ($search !== '') {
            $query->whereRaw('LOWER(name) LIKE ?', ['%' . mb_strtolower($search) . '%']);
        }

        // Stok adalah hasil agregasi batch, jadi perbandingannya terhadap minimum_stock
        // dilakukan di level koleksi — tetap aman dari sisi tenant dan lintas database.
        if ($request->boolean('low_stock')) {
            $items = $query->get()
                ->filter(fn ($ingredient) => (float) ($ingredient->stock ?? 0) <= (float) $ingredient->minimum_stock)
                ->values();

            if ($request->boolean('all')) {
                return $this->ok(IngredientResource::collection($items), 'Daftar bahan dengan stok menipis.');
            }

            $perPage = $this->perPage(20);
            $page = LengthAwarePaginator::resolveCurrentPage();

            $paginator = new LengthAwarePaginator(
                $items->forPage($page, $perPage)->values(),
                $items->count(),
                $perPage,
                $page,
                ['path' => $request->url(), 'query' => $request->query()]
            );

            return $this->paginated(
                IngredientResource::collection($paginator),
                'Daftar bahan dengan stok menipis.'
            );
        }

        if ($request->boolean('all')) {
            return $this->ok(IngredientResource::collection($query->get()), 'Daftar bahan makanan.');
        }

        return $this->paginated(
            IngredientResource::collection($query->paginate($this->perPage(20))),
            'Daftar bahan makanan.'
        );
    }

    #[OA\Post(
        path: '/api/v1/ingredients',
        operationId: 'ingredientStore',
        summary: 'Tambah bahan makanan',
        description: 'Menambah master bahan makanan. Stok awal TIDAK diisi di sini — stok bertambah melalui pencatatan stok masuk (batch) pada modul Finance.',
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['name', 'unit', 'minimum_stock'],
                properties: [
                    new OA\Property(property: 'name', type: 'string', maxLength: 255, example: 'Daging Ayam Fillet'),
                    new OA\Property(property: 'unit', type: 'string', enum: ['gram', 'kg', 'ml', 'liter', 'pcs', 'slice', 'bungkus'], example: 'gram'),
                    new OA\Property(property: 'minimum_stock', type: 'number', format: 'float', minimum: 0, example: 1000, description: 'Batas stok minimum untuk peringatan stok menipis.'),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 201, description: 'Bahan makanan berhasil ditambahkan'),
            new OA\Response(response: 422, description: 'Validasi gagal'),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
        ]
    )]
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'unit' => ['required', 'string', 'in:' . implode(',', self::UNITS)],
            'minimum_stock' => ['required', 'numeric', 'min:0'],
        ], [
            'name.required' => 'Nama Bahan wajib diisi.',
            'name.max' => 'Nama Bahan maksimal 255 karakter.',
            'unit.required' => 'Satuan wajib dipilih.',
            'unit.in' => 'Satuan hanya boleh: gram, kg, ml, liter, pcs, slice, bungkus.',
            'minimum_stock.required' => 'Stok minimum wajib diisi.',
            'minimum_stock.numeric' => 'Stok minimum harus berupa angka.',
            'minimum_stock.min' => 'Stok minimum tidak boleh kurang dari 0.',
        ]);

        $ingredient = Ingredient::create([
            'name' => $data['name'],
            'unit' => $data['unit'],
            'minimum_stock' => $data['minimum_stock'],
        ]);

        return $this->created(
            new IngredientResource($ingredient->loadSum('batches as stock', 'remaining_quantity')),
            'Bahan makanan berhasil ditambahkan!'
        );
    }

    #[OA\Get(
        path: '/api/v1/ingredients/{id}',
        operationId: 'ingredientShow',
        summary: 'Detail bahan makanan + batch aktif',
        description: 'Menampilkan detail bahan (termasuk stok saat ini) beserta daftar batch yang masih punya sisa stok. Batch diurutkan dari tanggal kedaluwarsa terdekat (FEFO); batch tanpa tanggal kedaluwarsa diletakkan paling akhir.',
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID bahan makanan.', schema: new OA\Schema(type: 'integer'), example: 1),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Detail bahan + daftar batch aktif'),
            new OA\Response(response: 404, description: 'Bahan tidak ditemukan'),
        ]
    )]
    public function show($id): JsonResponse
    {
        $ingredient = Ingredient::withSum('batches as stock', 'remaining_quantity')->findOrFail($id);

        $batches = IngredientBatch::with('supplier')
            ->where('ingredient_id', $ingredient->id)
            ->where('remaining_quantity', '>', 0)
            ->orderByRaw('expiry_date ASC NULLS LAST')
            ->get();

        return $this->ok([
            'ingredient' => new IngredientResource($ingredient),
            'batches' => IngredientBatchResource::collection($batches),
        ], 'Detail bahan makanan.');
    }

    #[OA\Put(
        path: '/api/v1/ingredients/{id}',
        operationId: 'ingredientUpdate',
        summary: 'Ubah bahan makanan',
        description: 'Mengubah nama, satuan, dan stok minimum bahan. Perhatikan bahwa mengganti satuan tidak mengonversi angka stok pada batch yang sudah tercatat.',
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID bahan makanan.', schema: new OA\Schema(type: 'integer'), example: 1),
        ],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['name', 'unit', 'minimum_stock'],
                properties: [
                    new OA\Property(property: 'name', type: 'string', maxLength: 255, example: 'Daging Ayam Fillet'),
                    new OA\Property(property: 'unit', type: 'string', enum: ['gram', 'kg', 'ml', 'liter', 'pcs', 'slice', 'bungkus'], example: 'gram'),
                    new OA\Property(property: 'minimum_stock', type: 'number', format: 'float', minimum: 0, example: 1500),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 200, description: 'Bahan makanan berhasil diperbarui'),
            new OA\Response(response: 422, description: 'Validasi gagal'),
            new OA\Response(response: 404, description: 'Bahan tidak ditemukan'),
        ]
    )]
    public function update(Request $request, $id): JsonResponse
    {
        $ingredient = Ingredient::findOrFail($id);

        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'unit' => ['required', 'string', 'in:' . implode(',', self::UNITS)],
            'minimum_stock' => ['required', 'numeric', 'min:0'],
        ], [
            'name.required' => 'Nama Bahan wajib diisi.',
            'name.max' => 'Nama Bahan maksimal 255 karakter.',
            'unit.required' => 'Satuan wajib dipilih.',
            'unit.in' => 'Satuan hanya boleh: gram, kg, ml, liter, pcs, slice, bungkus.',
            'minimum_stock.required' => 'Stok minimum wajib diisi.',
            'minimum_stock.numeric' => 'Stok minimum harus berupa angka.',
            'minimum_stock.min' => 'Stok minimum tidak boleh kurang dari 0.',
        ]);

        $ingredient->update([
            'name' => $data['name'],
            'unit' => $data['unit'],
            'minimum_stock' => $data['minimum_stock'],
        ]);

        return $this->ok(
            new IngredientResource($ingredient->loadSum('batches as stock', 'remaining_quantity')),
            'Bahan makanan berhasil diperbarui!'
        );
    }

    #[OA\Delete(
        path: '/api/v1/ingredients/{id}',
        operationId: 'ingredientDestroy',
        summary: 'Hapus bahan makanan',
        description: 'Menghapus bahan makanan. Bahan yang masih tercantum pada resep menu tidak bisa dihapus dan dibalas 409, karena penghapusannya akan merusak perhitungan HPP dan pemotongan stok otomatis.',
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID bahan makanan.', schema: new OA\Schema(type: 'integer'), example: 1),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Bahan makanan berhasil dihapus'),
            new OA\Response(response: 409, description: 'Bahan masih dipakai resep menu'),
            new OA\Response(response: 404, description: 'Bahan tidak ditemukan'),
        ]
    )]
    public function destroy($id): JsonResponse
    {
        $ingredient = Ingredient::findOrFail($id);

        if (MenuIngredient::where('ingredient_id', $ingredient->id)->exists()) {
            return $this->fail('Bahan masih dipakai pada resep menu dan tidak bisa dihapus.', 409);
        }

        $ingredient->delete();

        return $this->ok(null, 'Bahan makanan berhasil dihapus!');
    }
}
