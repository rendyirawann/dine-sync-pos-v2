<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Api\BaseApiController;
use App\Http\Resources\IngredientResource;
use App\Http\Resources\StockOpnameResource;
use App\Models\Ingredient;
use App\Models\StockOpname;
use App\Models\StockOpnameDetail;
use App\Services\StockService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use OpenApi\Attributes as OA;

/**
 * Modul Stock Opname (hitung stok fisik).
 *
 * Logika bisnis direplikasi dari StockOpnameController web:
 * - Ambil stok sistem tiap bahan, bandingkan dengan stok fisik hasil hitung.
 * - Simpan header (StockOpname) + rincian per bahan (StockOpnameDetail),
 *   termasuk bahan yang selisihnya 0 supaya laporan tetap lengkap.
 * - Penyesuaian batch diserahkan ke StockService::adjustStock (FEFO untuk
 *   kekurangan, batch terbaru untuk kelebihan).
 */
class StockOpnameController extends BaseApiController
{
    public function __construct(protected StockService $stockService) {}

    #[OA\Get(
        path: '/api/v1/stock-opname/prepare',
        operationId: 'stockOpnamePrepare',
        summary: 'Data awal form stock opname',
        description: 'Menyiapkan daftar seluruh bahan beserta stok sistemnya (jumlah sisa semua batch) '
            . 'untuk diisi stok fisiknya oleh petugas. Nilai `current_stock` pada setiap bahan adalah '
            . 'stok menurut sistem; aplikasi cukup mengirim stok fisik lalu selisih dihitung server.',
        tags: ['Finance'],
        security: [['sanctum' => []]],
        responses: [
            new OA\Response(response: 200, description: 'Daftar bahan + stok sistem', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'message', type: 'string', example: 'Data awal stock opname berhasil diambil.'),
                    new OA\Property(property: 'data', properties: [
                        new OA\Property(property: 'ingredients', type: 'array', items: new OA\Items(type: 'object')),
                        new OA\Property(property: 'note', type: 'string', example: 'Selisih dihitung otomatis: fisik - sistem. Penyesuaian batch memakai FEFO.'),
                    ], type: 'object'),
                ]
            )),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 403, description: 'Tidak punya izin view_finance'),
        ]
    )]
    public function prepare(): JsonResponse
    {
        $ingredients = Ingredient::withSum('batches as stock', 'remaining_quantity')
            ->orderBy('name')
            ->get();

        return $this->ok([
            'ingredients' => IngredientResource::collection($ingredients),
            'note' => 'Selisih dihitung otomatis: fisik - sistem. Penyesuaian batch memakai FEFO.',
        ], 'Data awal stock opname berhasil diambil.');
    }

    #[OA\Post(
        path: '/api/v1/stock-opname',
        operationId: 'stockOpnameStore',
        summary: 'Simpan hasil stock opname',
        description: 'Menyimpan satu sesi stock opname. Untuk setiap item dikirim `ingredient_id` dan '
            . '`physical_qty` (hasil hitung fisik). Server mengambil stok sistem tiap bahan, menghitung '
            . 'selisih (fisik - sistem), menyimpan rinciannya, lalu memanggil StockService::adjustStock '
            . 'sehingga batch ikut disesuaikan: kekurangan dipotong dengan urutan FEFO, kelebihan '
            . 'ditambahkan ke batch terbaru. Seluruh proses berada di dalam satu transaksi database. '
            . 'Bahan yang tidak dikirim TIDAK ikut dicatat pada sesi ini.',
        tags: ['Finance'],
        security: [['sanctum' => []]],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['items'],
                properties: [
                    new OA\Property(
                        property: 'items',
                        type: 'array',
                        items: new OA\Items(
                            required: ['ingredient_id', 'physical_qty'],
                            properties: [
                                new OA\Property(property: 'ingredient_id', type: 'integer', example: 3),
                                new OA\Property(property: 'physical_qty', type: 'number', format: 'float', example: 4.5),
                            ],
                            type: 'object'
                        ),
                        description: 'Daftar bahan beserta stok fisiknya (minimal 1 item)'
                    ),
                    new OA\Property(property: 'notes', type: 'string', nullable: true, maxLength: 255, example: 'Opname akhir bulan', description: 'Catatan sesi opname. Default: "Stock Opname Berkala"'),
                    new OA\Property(property: 'date', type: 'string', format: 'date', nullable: true, example: '2026-08-19', description: 'Tanggal opname. Default: hari ini'),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 201, description: 'Stock opname berhasil disimpan beserta rinciannya'),
            new OA\Response(response: 422, description: 'Data yang dikirim tidak valid'),
        ]
    )]
    public function store(Request $request): JsonResponse
    {
        $request->validate([
            'items' => ['required', 'array', 'min:1'],
            'items.*.ingredient_id' => ['required', 'exists:ingredients,id'],
            'items.*.physical_qty' => ['required', 'numeric', 'min:0'],
            'notes' => ['nullable', 'string', 'max:255'],
            'date' => ['nullable', 'date'],
        ], [
            'items.required' => 'Data bahan wajib dikirim.',
            'items.array' => 'Format data bahan tidak valid.',
            'items.min' => 'Minimal satu bahan harus dihitung.',
            'items.*.ingredient_id.required' => 'ID bahan wajib diisi.',
            'items.*.ingredient_id.exists' => 'Salah satu bahan yang dikirim tidak valid.',
            'items.*.physical_qty.required' => 'Stok fisik wajib diisi.',
            'items.*.physical_qty.numeric' => 'Stok fisik harus berupa angka.',
            'items.*.physical_qty.min' => 'Stok fisik tidak boleh minus.',
            'notes.max' => 'Catatan maksimal 255 karakter.',
            'date.date' => 'Format tanggal opname tidak valid.',
        ]);

        $opname = DB::transaction(function () use ($request) {
            $opname = StockOpname::create([
                'user_id' => auth()->id(),
                'date' => $request->date ?? now()->toDateString(),
                'notes' => $request->notes ?? 'Stock Opname Berkala',
            ]);

            foreach ($request->items as $row) {
                $ing = Ingredient::findOrFail($row['ingredient_id']);

                $systemQty = (float) $ing->currentStock();
                $physical = (float) $row['physical_qty'];
                $diff = $physical - $systemQty;

                StockOpnameDetail::create([
                    'stock_opname_id' => $opname->id,
                    'ingredient_id' => $ing->id,
                    'system_qty' => $systemQty,
                    'physical_qty' => $physical,
                    'difference' => $diff,
                ]);

                // Menyesuaikan batch: FEFO untuk kekurangan, batch terbaru untuk kelebihan.
                $this->stockService->adjustStock($ing->id, $physical, 'stock_opname');
            }

            return $opname;
        });

        return $this->created(
            new StockOpnameResource($opname->load('details.ingredient', 'user')),
            'Stock Opname berhasil disimpan! Seluruh bahan telah tercatat di laporan.'
        );
    }

    #[OA\Get(
        path: '/api/v1/stock-opname/history',
        operationId: 'stockOpnameHistory',
        summary: 'Riwayat stock opname (berpaginasi)',
        description: 'Menampilkan riwayat sesi stock opname milik UMKM aktif beserta petugasnya, '
            . 'terbaru di atas. Rincian per bahan tidak disertakan di sini — ambil lewat '
            . '`GET /api/v1/stock-opname/{id}`. Kirim `all=true` untuk mengambil seluruh riwayat tanpa paginasi.',
        tags: ['Finance'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'all', description: 'Bila true, seluruh riwayat dikembalikan tanpa paginasi', in: 'query', required: false, schema: new OA\Schema(type: 'boolean', example: false)),
            new OA\Parameter(name: 'per_page', description: 'Jumlah data per halaman (maks 100)', in: 'query', required: false, schema: new OA\Schema(type: 'integer', example: 20)),
            new OA\Parameter(name: 'page', description: 'Halaman ke-', in: 'query', required: false, schema: new OA\Schema(type: 'integer', example: 1)),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Riwayat stock opname berpaginasi (data + meta)'),
            new OA\Response(response: 403, description: 'Tidak punya izin view_finance'),
        ]
    )]
    public function history(Request $request): JsonResponse
    {
        $query = StockOpname::with('user')
            ->orderBy('date', 'desc')
            ->orderBy('id', 'desc');

        if ($request->boolean('all')) {
            return $this->ok(
                StockOpnameResource::collection($query->get()),
                'Seluruh riwayat stock opname berhasil diambil.'
            );
        }

        $paginator = $query->paginate($this->perPage());

        return $this->paginated(
            $paginator->through(fn ($opname) => new StockOpnameResource($opname)),
            'Riwayat stock opname berhasil diambil.'
        );
    }

    #[OA\Get(
        path: '/api/v1/stock-opname/{id}',
        operationId: 'stockOpnameShow',
        summary: 'Detail satu sesi stock opname',
        description: 'Menampilkan satu sesi stock opname lengkap dengan petugas dan rincian per bahan '
            . '(stok sistem, stok fisik, dan selisihnya).',
        tags: ['Finance'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', description: 'ID sesi stock opname', in: 'path', required: true, schema: new OA\Schema(type: 'integer', example: 4)),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Detail sesi stock opname'),
            new OA\Response(response: 404, description: 'Sesi stock opname tidak ditemukan'),
        ]
    )]
    public function show($id): JsonResponse
    {
        $opname = StockOpname::with('user', 'details.ingredient')->findOrFail($id);

        return $this->ok(
            new StockOpnameResource($opname),
            'Detail stock opname berhasil diambil.'
        );
    }
}
