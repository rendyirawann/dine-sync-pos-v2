<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Api\BaseApiController;
use App\Http\Resources\TableResource;
use App\Models\Order;
use App\Models\Table;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use OpenApi\Attributes as OA;

/**
 * Data Master — Meja.
 *
 * Nomor/nama meja unik PER TENANT (composite unique tenant_id + table_number),
 * sedangkan kolom uuid tetap unik global karena dipakai sebagai payload QR
 * self-order pelanggan (url /scan/{uuid}).
 */
class TableController extends BaseApiController
{
    /** Status order yang dianggap "masih berjalan" di sebuah meja. */
    private const ACTIVE_ORDER_STATUSES = ['pending', 'cooking', 'served'];

    #[OA\Get(
        path: '/api/v1/tables',
        operationId: 'tableIndex',
        summary: 'Daftar meja',
        description: <<<'TXT'
Menampilkan daftar meja milik tenant aktif, diurutkan berdasarkan nomor/nama meja (A-Z).

**Query yang didukung:**
- `search` — filter LIKE (tidak peka huruf besar/kecil) pada `table_number`.
- `status` — `available` atau `occupied`.
- `per_page` — jumlah data per halaman (default 20, maksimal 100).
- `all=true` — kembalikan SELURUH meja tanpa paginasi. Dipakai layar kasir
  (peta meja) dan dropdown pemilihan meja di aplikasi mobile.

Tiap item menyertakan `status_label`, `status_color`, dan `qr_payload`
(URL yang perlu di-render menjadi QR code untuk dicetak/ditempel di meja).
TXT,
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'search', in: 'query', required: false, description: 'Kata kunci nomor/nama meja.', schema: new OA\Schema(type: 'string'), example: 'Meja 0'),
            new OA\Parameter(name: 'status', in: 'query', required: false, description: 'Filter status meja.', schema: new OA\Schema(type: 'string', enum: ['available', 'occupied'])),
            new OA\Parameter(name: 'per_page', in: 'query', required: false, description: 'Jumlah data per halaman (default 20, maks 100).', schema: new OA\Schema(type: 'integer', default: 20)),
            new OA\Parameter(name: 'all', in: 'query', required: false, description: 'Bila true → seluruh data tanpa paginasi (kasir/dropdown).', schema: new OA\Schema(type: 'boolean')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Daftar meja (berpaginasi, atau seluruh data bila all=true)'),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 403, description: 'Tidak punya izin view_data_master'),
        ]
    )]
    public function index(Request $request): JsonResponse
    {
        $query = Table::query()->orderBy('table_number', 'asc');

        $search = trim((string) $request->query('search', ''));

        if ($search !== '') {
            $query->whereRaw('LOWER(table_number) LIKE ?', ['%' . mb_strtolower($search) . '%']);
        }

        if ($request->filled('status')) {
            $query->where('status', $request->query('status'));
        }

        if ($request->boolean('all')) {
            return $this->ok(TableResource::collection($query->get()), 'Daftar meja.');
        }

        return $this->paginated(
            TableResource::collection($query->paginate($this->perPage(20))),
            'Daftar meja.'
        );
    }

    #[OA\Post(
        path: '/api/v1/tables',
        operationId: 'tableStore',
        summary: 'Tambah meja',
        description: 'Menambah meja baru dengan status awal `available`. Nomor/nama meja tidak boleh sama dengan meja lain pada tenant yang sama. UUID untuk QR code dibuat otomatis.',
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['table_number', 'capacity'],
                properties: [
                    new OA\Property(property: 'table_number', type: 'string', maxLength: 100, example: 'Meja 01'),
                    new OA\Property(property: 'capacity', type: 'integer', minimum: 1, example: 4),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 201, description: 'Meja berhasil ditambahkan'),
            new OA\Response(response: 422, description: 'Validasi gagal / nomor meja duplikat'),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
        ]
    )]
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'table_number' => ['required', 'string', 'max:100'],
            'capacity' => ['required', 'integer', 'min:1'],
        ], [
            'table_number.required' => 'Nomor/nama meja wajib diisi.',
            'table_number.max' => 'Nomor/nama meja maksimal 100 karakter.',
            'capacity.required' => 'Kapasitas meja wajib diisi.',
            'capacity.integer' => 'Kapasitas meja harus berupa angka bulat.',
            'capacity.min' => 'Kapasitas meja minimal 1 orang.',
        ]);

        if (Table::where('table_number', $data['table_number'])->exists()) {
            return $this->fail('Nomor/nama meja ini sudah ada.', 422, [
                'table_number' => ['Nomor/nama meja ini sudah ada.'],
            ]);
        }

        $table = Table::create([
            'table_number' => $data['table_number'],
            'capacity' => $data['capacity'],
            'status' => 'available',
        ]);

        return $this->created(new TableResource($table), 'Meja berhasil ditambahkan!');
    }

    #[OA\Get(
        path: '/api/v1/tables/{id}',
        operationId: 'tableShow',
        summary: 'Detail meja',
        description: 'Menampilkan detail meja (termasuk `qr_payload`) plus jumlah order yang masih berjalan di meja tersebut (status pending / cooking / served) pada field `active_orders`.',
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID meja.', schema: new OA\Schema(type: 'integer'), example: 1),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Detail meja + jumlah order aktif'),
            new OA\Response(response: 404, description: 'Meja tidak ditemukan'),
        ]
    )]
    public function show($id): JsonResponse
    {
        $table = Table::findOrFail($id);

        $activeOrders = Order::where('table_id', $table->id)
            ->whereIn('order_status', self::ACTIVE_ORDER_STATUSES)
            ->count();

        return $this->ok([
            'table' => new TableResource($table),
            'active_orders' => $activeOrders,
        ], 'Detail meja.');
    }

    #[OA\Put(
        path: '/api/v1/tables/{id}',
        operationId: 'tableUpdate',
        summary: 'Ubah meja',
        description: 'Mengubah nomor/nama, kapasitas, dan status meja. Nomor/nama meja dicek agar tidak bentrok dengan meja lain pada tenant yang sama. Bila `status` tidak dikirim, status meja dibiarkan seperti sebelumnya.',
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID meja.', schema: new OA\Schema(type: 'integer'), example: 1),
        ],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['table_number', 'capacity'],
                properties: [
                    new OA\Property(property: 'table_number', type: 'string', maxLength: 100, example: 'Meja 01'),
                    new OA\Property(property: 'capacity', type: 'integer', minimum: 1, example: 6),
                    new OA\Property(property: 'status', type: 'string', enum: ['available', 'occupied'], example: 'available'),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 200, description: 'Meja berhasil diupdate'),
            new OA\Response(response: 422, description: 'Validasi gagal / nomor meja duplikat'),
            new OA\Response(response: 404, description: 'Meja tidak ditemukan'),
        ]
    )]
    public function update(Request $request, $id): JsonResponse
    {
        $table = Table::findOrFail($id);

        $data = $request->validate([
            'table_number' => ['required', 'string', 'max:100'],
            'capacity' => ['required', 'integer', 'min:1'],
            'status' => ['nullable', 'in:available,occupied'],
        ], [
            'table_number.required' => 'Nomor/nama meja wajib diisi.',
            'table_number.max' => 'Nomor/nama meja maksimal 100 karakter.',
            'capacity.required' => 'Kapasitas meja wajib diisi.',
            'capacity.integer' => 'Kapasitas meja harus berupa angka bulat.',
            'capacity.min' => 'Kapasitas meja minimal 1 orang.',
            'status.in' => 'Status meja hanya boleh available atau occupied.',
        ]);

        $duplicate = Table::where('table_number', $data['table_number'])
            ->where('id', '!=', $table->id)
            ->exists();

        if ($duplicate) {
            return $this->fail('Nomor/nama meja ini sudah ada.', 422, [
                'table_number' => ['Nomor/nama meja ini sudah ada.'],
            ]);
        }

        $table->update([
            'table_number' => $data['table_number'],
            'capacity' => $data['capacity'],
            'status' => $data['status'] ?? $table->status,
        ]);

        return $this->ok(new TableResource($table), 'Meja berhasil diupdate!');
    }

    #[OA\Delete(
        path: '/api/v1/tables/{id}',
        operationId: 'tableDestroy',
        summary: 'Hapus meja',
        description: 'Menghapus meja. Meja yang masih punya order berjalan (pending / cooking / served) tidak bisa dihapus dan dibalas 409.',
        tags: ['Data Master'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID meja.', schema: new OA\Schema(type: 'integer'), example: 1),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Meja berhasil dihapus'),
            new OA\Response(response: 409, description: 'Meja sedang dipakai order aktif'),
            new OA\Response(response: 404, description: 'Meja tidak ditemukan'),
        ]
    )]
    public function destroy($id): JsonResponse
    {
        $table = Table::findOrFail($id);

        $hasActiveOrder = Order::where('table_id', $table->id)
            ->whereIn('order_status', self::ACTIVE_ORDER_STATUSES)
            ->exists();

        if ($hasActiveOrder) {
            return $this->fail('Meja sedang digunakan dan tidak bisa dihapus.', 409);
        }

        $table->delete();

        return $this->ok(null, 'Meja berhasil dihapus!');
    }
}
