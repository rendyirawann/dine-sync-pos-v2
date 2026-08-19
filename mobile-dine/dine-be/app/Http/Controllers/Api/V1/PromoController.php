<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Api\BaseApiController;
use App\Http\Resources\PromoResource;
use App\Models\Promo;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use OpenApi\Attributes as OA;

/**
 * Data Master — Promo / Diskon nota.
 *
 * discount_type:
 *  - percentage → discount_value = persen (1-100)
 *  - nominal    → discount_value = potongan rupiah
 */
class PromoController extends BaseApiController
{
    #[OA\Get(
        path: '/api/v1/promos',
        operationId: 'promoIndex',
        summary: 'Daftar promo',
        description: <<<'TXT'
Menampilkan daftar promo milik tenant aktif, diurutkan dari yang terbaru.

**Query yang didukung:**
- `search` — filter LIKE (tidak peka huruf besar/kecil) pada nama promo.
- `is_active` — `1` hanya promo aktif, `0` hanya promo non-aktif.
- `per_page` — jumlah data per halaman (default 20, maksimal 100).
- `all=true` — kembalikan SELURUH promo tanpa paginasi. Dipakai dropdown promo
  di layar kasir, umumnya dipanggil dengan `?all=true&is_active=1`.

Tiap item menyertakan `label` siap tampil, contoh: `Diskon Karyawan (10%)`.
TXT,
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'search', in: 'query', required: false, description: 'Kata kunci nama promo.', schema: new OA\Schema(type: 'string'), example: 'karyawan'),
            new OA\Parameter(name: 'is_active', in: 'query', required: false, description: 'Filter status promo (1 = aktif, 0 = non-aktif).', schema: new OA\Schema(type: 'boolean')),
            new OA\Parameter(name: 'per_page', in: 'query', required: false, description: 'Jumlah data per halaman (default 20, maks 100).', schema: new OA\Schema(type: 'integer', default: 20)),
            new OA\Parameter(name: 'all', in: 'query', required: false, description: 'Bila true → seluruh data tanpa paginasi (dropdown kasir).', schema: new OA\Schema(type: 'boolean')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Daftar promo (berpaginasi, atau seluruh data bila all=true)'),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 403, description: 'Tidak punya izin view_data_master'),
        ]
    )]
    public function index(Request $request): JsonResponse
    {
        $query = Promo::query()->orderBy('created_at', 'desc');

        $search = trim((string) $request->query('search', ''));

        if ($search !== '') {
            $query->whereRaw('LOWER(name) LIKE ?', ['%' . mb_strtolower($search) . '%']);
        }

        if ($request->filled('is_active')) {
            $query->where('is_active', $request->boolean('is_active'));
        }

        if ($request->boolean('all')) {
            return $this->ok(PromoResource::collection($query->get()), 'Daftar promo.');
        }

        return $this->paginated(
            PromoResource::collection($query->paginate($this->perPage(20))),
            'Daftar promo.'
        );
    }

    #[OA\Post(
        path: '/api/v1/promos',
        operationId: 'promoStore',
        summary: 'Tambah promo',
        description: 'Menambah promo baru. Bila `discount_type` = `percentage`, `discount_value` dibatasi maksimal 100. Bila `is_active` tidak dikirim, promo langsung aktif.',
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['name', 'discount_type', 'discount_value'],
                properties: [
                    new OA\Property(property: 'name', type: 'string', maxLength: 255, example: 'Diskon Karyawan'),
                    new OA\Property(property: 'discount_type', type: 'string', enum: ['percentage', 'nominal'], example: 'percentage'),
                    new OA\Property(property: 'discount_value', type: 'integer', minimum: 1, example: 10, description: 'Persen (1-100) bila percentage, rupiah bila nominal.'),
                    new OA\Property(property: 'is_active', type: 'boolean', example: true),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 201, description: 'Promo berhasil ditambahkan'),
            new OA\Response(response: 422, description: 'Validasi gagal'),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
        ]
    )]
    public function store(Request $request): JsonResponse
    {
        // Diskon persentase dibatasi 100; diskon nominal (rupiah) tidak dibatasi.
        $valueRules = ['required', 'integer', 'min:1'];

        if ($request->input('discount_type') === 'percentage') {
            $valueRules[] = 'max:100';
        }

        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'discount_type' => ['required', 'in:percentage,nominal'],
            'discount_value' => $valueRules,
            'is_active' => ['nullable', 'boolean'],
        ], [
            'name.required' => 'Nama Promo wajib diisi.',
            'name.max' => 'Nama Promo maksimal 255 karakter.',
            'discount_type.required' => 'Tipe diskon wajib dipilih.',
            'discount_type.in' => 'Tipe diskon hanya boleh percentage atau nominal.',
            'discount_value.required' => 'Nilai diskon wajib diisi.',
            'discount_value.integer' => 'Nilai diskon harus berupa angka bulat.',
            'discount_value.min' => 'Nilai diskon minimal 1.',
            'discount_value.max' => 'Diskon persentase maksimal 100%.',
        ]);

        $promo = Promo::create([
            'name' => $data['name'],
            'discount_type' => $data['discount_type'],
            'discount_value' => $data['discount_value'],
            // Default promo langsung aktif bila field tidak dikirim aplikasi.
            'is_active' => $request->has('is_active') ? $request->boolean('is_active') : true,
        ]);

        return $this->created(new PromoResource($promo), 'Promo berhasil ditambahkan!');
    }

    #[OA\Get(
        path: '/api/v1/promos/{id}',
        operationId: 'promoShow',
        summary: 'Detail promo',
        description: 'Menampilkan satu promo milik tenant aktif.',
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID promo.', schema: new OA\Schema(type: 'integer'), example: 1),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Detail promo'),
            new OA\Response(response: 404, description: 'Promo tidak ditemukan'),
        ]
    )]
    public function show($id): JsonResponse
    {
        $promo = Promo::findOrFail($id);

        return $this->ok(new PromoResource($promo), 'Detail promo.');
    }

    #[OA\Put(
        path: '/api/v1/promos/{id}',
        operationId: 'promoUpdate',
        summary: 'Ubah promo',
        description: 'Mengubah data promo. Aturan `discount_value` mengikuti `discount_type` yang dikirim. Bila `is_active` tidak dikirim, statusnya dibiarkan seperti sebelumnya.',
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID promo.', schema: new OA\Schema(type: 'integer'), example: 1),
        ],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['name', 'discount_type', 'discount_value'],
                properties: [
                    new OA\Property(property: 'name', type: 'string', maxLength: 255, example: 'Promo Kemerdekaan'),
                    new OA\Property(property: 'discount_type', type: 'string', enum: ['percentage', 'nominal'], example: 'nominal'),
                    new OA\Property(property: 'discount_value', type: 'integer', minimum: 1, example: 15000),
                    new OA\Property(property: 'is_active', type: 'boolean', example: true),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 200, description: 'Promo berhasil diperbarui'),
            new OA\Response(response: 422, description: 'Validasi gagal'),
            new OA\Response(response: 404, description: 'Promo tidak ditemukan'),
        ]
    )]
    public function update(Request $request, $id): JsonResponse
    {
        $promo = Promo::findOrFail($id);

        // Diskon persentase dibatasi 100; diskon nominal (rupiah) tidak dibatasi.
        $valueRules = ['required', 'integer', 'min:1'];

        if ($request->input('discount_type') === 'percentage') {
            $valueRules[] = 'max:100';
        }

        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'discount_type' => ['required', 'in:percentage,nominal'],
            'discount_value' => $valueRules,
            'is_active' => ['nullable', 'boolean'],
        ], [
            'name.required' => 'Nama Promo wajib diisi.',
            'name.max' => 'Nama Promo maksimal 255 karakter.',
            'discount_type.required' => 'Tipe diskon wajib dipilih.',
            'discount_type.in' => 'Tipe diskon hanya boleh percentage atau nominal.',
            'discount_value.required' => 'Nilai diskon wajib diisi.',
            'discount_value.integer' => 'Nilai diskon harus berupa angka bulat.',
            'discount_value.min' => 'Nilai diskon minimal 1.',
            'discount_value.max' => 'Diskon persentase maksimal 100%.',
        ]);

        $promo->update([
            'name' => $data['name'],
            'discount_type' => $data['discount_type'],
            'discount_value' => $data['discount_value'],
            'is_active' => $request->has('is_active')
                ? $request->boolean('is_active')
                : (bool) $promo->is_active,
        ]);

        return $this->ok(new PromoResource($promo), 'Promo berhasil diperbarui!');
    }

    #[OA\Delete(
        path: '/api/v1/promos/{id}',
        operationId: 'promoDestroy',
        summary: 'Hapus promo',
        description: 'Menghapus promo. Order lama yang pernah memakai promo ini tetap aman (kolom promo_id pada order menjadi NULL).',
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID promo.', schema: new OA\Schema(type: 'integer'), example: 1),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Promo berhasil dihapus'),
            new OA\Response(response: 404, description: 'Promo tidak ditemukan'),
        ]
    )]
    public function destroy($id): JsonResponse
    {
        $promo = Promo::findOrFail($id);

        $promo->delete();

        return $this->ok(null, 'Promo berhasil dihapus!');
    }

    #[OA\Post(
        path: '/api/v1/promos/{id}/toggle',
        operationId: 'promoToggle',
        summary: 'Aktif/non-aktifkan promo',
        description: 'Membalik nilai `is_active` sebuah promo (switch on/off pada daftar promo di aplikasi mobile). Tidak perlu mengirim body.',
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID promo.', schema: new OA\Schema(type: 'integer'), example: 1),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Status promo berhasil diubah'),
            new OA\Response(response: 404, description: 'Promo tidak ditemukan'),
        ]
    )]
    public function toggle($id): JsonResponse
    {
        $promo = Promo::findOrFail($id);

        $promo->update(['is_active' => ! (bool) $promo->is_active]);

        return $this->ok(new PromoResource($promo), 'Status promo berhasil diubah!');
    }
}
