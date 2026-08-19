<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Api\BaseApiController;
use App\Http\Resources\SupplierResource;
use App\Models\IngredientBatch;
use App\Models\Supplier;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use OpenApi\Attributes as OA;

/**
 * Data Master — Supplier bahan baku.
 *
 * Supplier dipakai saat mencatat stok masuk (ingredient_batches),
 * jadi supplier yang sudah punya batch tidak boleh dihapus.
 */
class SupplierController extends BaseApiController
{
    #[OA\Get(
        path: '/api/v1/suppliers',
        operationId: 'supplierIndex',
        summary: 'Daftar supplier',
        description: <<<'TXT'
Menampilkan daftar supplier milik tenant aktif, diurutkan berdasarkan nama (A-Z).

**Query yang didukung:**
- `search` — filter LIKE (tidak peka huruf besar/kecil) pada `name`, `contact_person`, dan `phone`.
- `per_page` — jumlah data per halaman (default 20, maksimal 100).
- `all=true` — kembalikan SELURUH supplier tanpa paginasi. Dipakai dropdown
  pemilihan supplier pada form stok masuk di aplikasi mobile.
TXT,
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'search', in: 'query', required: false, description: 'Kata kunci nama / PIC / no. telepon supplier.', schema: new OA\Schema(type: 'string'), example: 'sayur'),
            new OA\Parameter(name: 'per_page', in: 'query', required: false, description: 'Jumlah data per halaman (default 20, maks 100).', schema: new OA\Schema(type: 'integer', default: 20)),
            new OA\Parameter(name: 'all', in: 'query', required: false, description: 'Bila true → seluruh data tanpa paginasi (dropdown).', schema: new OA\Schema(type: 'boolean')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Daftar supplier (berpaginasi, atau seluruh data bila all=true)'),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 403, description: 'Tidak punya izin view_data_master'),
        ]
    )]
    public function index(Request $request): JsonResponse
    {
        $query = Supplier::query()->orderBy('name', 'asc');

        $search = trim((string) $request->query('search', ''));

        if ($search !== '') {
            $like = '%' . mb_strtolower($search) . '%';

            $query->where(function ($q) use ($like) {
                $q->whereRaw('LOWER(name) LIKE ?', [$like])
                    ->orWhereRaw('LOWER(contact_person) LIKE ?', [$like])
                    ->orWhereRaw('LOWER(phone) LIKE ?', [$like]);
            });
        }

        if ($request->boolean('all')) {
            return $this->ok(SupplierResource::collection($query->get()), 'Daftar supplier.');
        }

        return $this->paginated(
            SupplierResource::collection($query->paginate($this->perPage(20))),
            'Daftar supplier.'
        );
    }

    #[OA\Post(
        path: '/api/v1/suppliers',
        operationId: 'supplierStore',
        summary: 'Tambah supplier',
        description: 'Menambah supplier baru. Hanya nama yang wajib diisi; PIC, telepon, dan alamat bersifat opsional.',
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['name'],
                properties: [
                    new OA\Property(property: 'name', type: 'string', maxLength: 255, example: 'CV Sayur Segar'),
                    new OA\Property(property: 'contact_person', type: 'string', maxLength: 255, example: 'Pak Budi'),
                    new OA\Property(property: 'phone', type: 'string', maxLength: 30, example: '081234567890'),
                    new OA\Property(property: 'address', type: 'string', example: 'Jl. Pasar Induk No. 12, Bandung'),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 201, description: 'Supplier berhasil ditambahkan'),
            new OA\Response(response: 422, description: 'Validasi gagal'),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
        ]
    )]
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'contact_person' => ['nullable', 'string', 'max:255'],
            'phone' => ['nullable', 'string', 'max:30'],
            'address' => ['nullable', 'string'],
        ], [
            'name.required' => 'Nama Supplier wajib diisi.',
            'name.max' => 'Nama Supplier maksimal 255 karakter.',
            'contact_person.max' => 'Nama PIC maksimal 255 karakter.',
            'phone.max' => 'No. telepon maksimal 30 karakter.',
        ]);

        $supplier = Supplier::create([
            'name' => $data['name'],
            'contact_person' => $data['contact_person'] ?? null,
            'phone' => $data['phone'] ?? null,
            'address' => $data['address'] ?? null,
        ]);

        return $this->created(new SupplierResource($supplier), 'Supplier berhasil ditambahkan!');
    }

    #[OA\Get(
        path: '/api/v1/suppliers/{id}',
        operationId: 'supplierShow',
        summary: 'Detail supplier',
        description: 'Menampilkan satu supplier milik tenant aktif.',
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID supplier.', schema: new OA\Schema(type: 'integer'), example: 1),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Detail supplier'),
            new OA\Response(response: 404, description: 'Supplier tidak ditemukan'),
        ]
    )]
    public function show($id): JsonResponse
    {
        $supplier = Supplier::findOrFail($id);

        return $this->ok(new SupplierResource($supplier), 'Detail supplier.');
    }

    #[OA\Put(
        path: '/api/v1/suppliers/{id}',
        operationId: 'supplierUpdate',
        summary: 'Ubah supplier',
        description: 'Mengubah data supplier milik tenant aktif. Field opsional yang tidak dikirim (`contact_person`, `phone`, `address`) dibiarkan seperti nilai sebelumnya.',
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID supplier.', schema: new OA\Schema(type: 'integer'), example: 1),
        ],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['name'],
                properties: [
                    new OA\Property(property: 'name', type: 'string', maxLength: 255, example: 'CV Sayur Segar Jaya'),
                    new OA\Property(property: 'contact_person', type: 'string', maxLength: 255, example: 'Pak Budi'),
                    new OA\Property(property: 'phone', type: 'string', maxLength: 30, example: '081234567890'),
                    new OA\Property(property: 'address', type: 'string', example: 'Jl. Pasar Induk No. 12, Bandung'),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 200, description: 'Supplier berhasil diperbarui'),
            new OA\Response(response: 422, description: 'Validasi gagal'),
            new OA\Response(response: 404, description: 'Supplier tidak ditemukan'),
        ]
    )]
    public function update(Request $request, $id): JsonResponse
    {
        $supplier = Supplier::findOrFail($id);

        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'contact_person' => ['nullable', 'string', 'max:255'],
            'phone' => ['nullable', 'string', 'max:30'],
            'address' => ['nullable', 'string'],
        ], [
            'name.required' => 'Nama Supplier wajib diisi.',
            'name.max' => 'Nama Supplier maksimal 255 karakter.',
            'contact_person.max' => 'Nama PIC maksimal 255 karakter.',
            'phone.max' => 'No. telepon maksimal 30 karakter.',
        ]);

        // Hanya field yang dikirim yang diperbarui, sisanya memakai nilai lama.
        $supplier->update($data);

        return $this->ok(new SupplierResource($supplier), 'Supplier berhasil diperbarui!');
    }

    #[OA\Delete(
        path: '/api/v1/suppliers/{id}',
        operationId: 'supplierDestroy',
        summary: 'Hapus supplier',
        description: 'Menghapus supplier. Supplier yang sudah pernah dipakai pada data stok masuk (batch bahan) tidak bisa dihapus dan dibalas 409 agar riwayat HPP tetap utuh.',
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID supplier.', schema: new OA\Schema(type: 'integer'), example: 1),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Supplier berhasil dihapus'),
            new OA\Response(response: 409, description: 'Supplier masih dipakai data stok'),
            new OA\Response(response: 404, description: 'Supplier tidak ditemukan'),
        ]
    )]
    public function destroy($id): JsonResponse
    {
        $supplier = Supplier::findOrFail($id);

        if (IngredientBatch::where('supplier_id', $supplier->id)->exists()) {
            return $this->fail('Supplier masih dipakai pada data stok dan tidak bisa dihapus.', 409);
        }

        $supplier->delete();

        return $this->ok(null, 'Supplier berhasil dihapus!');
    }
}
