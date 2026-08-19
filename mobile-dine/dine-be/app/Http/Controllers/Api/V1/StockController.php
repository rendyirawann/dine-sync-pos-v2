<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Api\BaseApiController;
use App\Http\Resources\IngredientBatchResource;
use App\Models\IngredientBatch;
use App\Models\StockMovement;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use OpenApi\Attributes as OA;

/**
 * Modul Stok Masuk (batch bahan) — dasar sistem FIFO/FEFO.
 *
 * Logika bisnis direplikasi dari StockController web:
 * - Input stok memakai TOTAL harga belanja; harga satuan dihitung otomatis
 *   (total / jumlah) lalu disimpan di kolom `buy_price` untuk perhitungan HPP.
 * - Setiap batch baru mencatat StockMovement bertipe `in` dengan alasan `purchase`.
 *
 * Model IngredientBatch & StockMovement ber-scope tenant, jadi tidak ada
 * filter tenant_id manual di controller ini.
 */
class StockController extends BaseApiController
{
    #[OA\Get(
        path: '/api/v1/stock-batches',
        operationId: 'stockBatchIndex',
        summary: 'Daftar batch stok masuk (berpaginasi)',
        description: 'Menampilkan seluruh batch stok bahan beserta bahan dan suppliernya, '
            . 'diurutkan dari tanggal masuk terbaru. Mendukung pencarian nama bahan, filter per bahan, '
            . 'serta filter hanya batch yang stoknya masih tersisa. Kirim `all=true` untuk tanpa paginasi.',
        tags: ['Finance'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'search', description: 'Cari berdasarkan nama bahan', in: 'query', required: false, schema: new OA\Schema(type: 'string', example: 'Ayam')),
            new OA\Parameter(name: 'ingredient_id', description: 'Filter batch milik satu bahan', in: 'query', required: false, schema: new OA\Schema(type: 'integer', example: 3)),
            new OA\Parameter(name: 'only_available', description: 'Bila true, hanya batch dengan sisa stok > 0', in: 'query', required: false, schema: new OA\Schema(type: 'boolean', example: true)),
            new OA\Parameter(name: 'all', description: 'Bila true, seluruh data dikembalikan tanpa paginasi', in: 'query', required: false, schema: new OA\Schema(type: 'boolean', example: false)),
            new OA\Parameter(name: 'per_page', description: 'Jumlah data per halaman (maks 100)', in: 'query', required: false, schema: new OA\Schema(type: 'integer', example: 20)),
            new OA\Parameter(name: 'page', description: 'Halaman ke-', in: 'query', required: false, schema: new OA\Schema(type: 'integer', example: 1)),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Daftar batch stok berpaginasi (data + meta)'),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 403, description: 'Tidak punya izin view_finance'),
        ]
    )]
    public function index(Request $request): JsonResponse
    {
        $query = IngredientBatch::with('ingredient', 'supplier');

        if ($request->filled('search')) {
            $keyword = '%' . $request->query('search') . '%';
            $query->whereHas('ingredient', fn ($q) => $q->where('name', 'like', $keyword));
        }

        if ($request->filled('ingredient_id')) {
            $query->where('ingredient_id', $request->query('ingredient_id'));
        }

        if ($request->boolean('only_available')) {
            $query->where('remaining_quantity', '>', 0);
        }

        $query->orderBy('entry_date', 'desc')->orderBy('id', 'desc');

        if ($request->boolean('all')) {
            return $this->ok(
                IngredientBatchResource::collection($query->get()),
                'Seluruh batch stok berhasil diambil.'
            );
        }

        $paginator = $query->paginate($this->perPage());

        return $this->paginated(
            $paginator->through(fn ($batch) => new IngredientBatchResource($batch)),
            'Daftar batch stok berhasil diambil.'
        );
    }

    #[OA\Post(
        path: '/api/v1/stock-batches',
        operationId: 'stockBatchStore',
        summary: 'Tambah stok masuk (batch baru)',
        description: 'Mencatat pembelian bahan sebagai batch baru pada sistem FIFO/FEFO. '
            . 'PENTING: `buy_price_total` adalah TOTAL harga belanja, bukan harga satuan. '
            . 'Harga satuan dihitung otomatis = buy_price_total / initial_quantity dan disimpan di `buy_price` '
            . '(dipakai untuk menghitung HPP saat penjualan). Sisa stok batch (`remaining_quantity`) '
            . 'diisi sama dengan jumlah awal, lalu satu StockMovement bertipe `in` dicatat. '
            . 'Seluruh proses berjalan dalam satu transaksi database.',
        tags: ['Finance'],
        security: [['sanctum' => []]],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['ingredient_id', 'initial_quantity', 'buy_price_total', 'entry_date'],
                properties: [
                    new OA\Property(property: 'ingredient_id', type: 'integer', example: 3, description: 'ID bahan yang dibeli'),
                    new OA\Property(property: 'initial_quantity', type: 'number', format: 'float', example: 5, description: 'Jumlah bahan yang masuk (sesuai satuan bahan)'),
                    new OA\Property(property: 'buy_price_total', type: 'number', format: 'float', example: 175000, description: 'TOTAL harga belanja untuk seluruh jumlah di atas'),
                    new OA\Property(property: 'supplier_id', type: 'integer', nullable: true, example: 1, description: 'ID supplier (opsional, kosongkan bila belanja manual)'),
                    new OA\Property(property: 'entry_date', type: 'string', format: 'date', example: '2026-08-19', description: 'Tanggal bahan masuk'),
                    new OA\Property(property: 'expiry_date', type: 'string', format: 'date', nullable: true, example: '2026-09-19', description: 'Tanggal kedaluwarsa (dipakai urutan FEFO)'),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 201, description: 'Batch stok berhasil dibuat'),
            new OA\Response(response: 422, description: 'Data yang dikirim tidak valid'),
        ]
    )]
    public function store(Request $request): JsonResponse
    {
        $request->validate([
            'ingredient_id' => ['required', 'exists:ingredients,id'],
            'initial_quantity' => ['required', 'numeric', 'min:0.01'],
            'buy_price_total' => ['required', 'numeric', 'min:0'],
            'supplier_id' => ['nullable', 'exists:suppliers,id'],
            'entry_date' => ['required', 'date'],
            'expiry_date' => ['nullable', 'date', 'after_or_equal:entry_date'],
        ], [
            'ingredient_id.required' => 'Bahan wajib dipilih.',
            'ingredient_id.exists' => 'Bahan yang dipilih tidak valid.',
            'initial_quantity.required' => 'Jumlah bahan wajib diisi.',
            'initial_quantity.numeric' => 'Jumlah bahan harus berupa angka.',
            'initial_quantity.min' => 'Jumlah bahan minimal 0.01.',
            'buy_price_total.required' => 'Total harga belanja wajib diisi.',
            'buy_price_total.numeric' => 'Total harga belanja harus berupa angka.',
            'buy_price_total.min' => 'Total harga belanja tidak boleh minus.',
            'supplier_id.exists' => 'Supplier yang dipilih tidak valid.',
            'entry_date.required' => 'Tanggal masuk wajib diisi.',
            'entry_date.date' => 'Format tanggal masuk tidak valid.',
            'expiry_date.date' => 'Format tanggal kedaluwarsa tidak valid.',
            'expiry_date.after_or_equal' => 'Tanggal kedaluwarsa tidak boleh lebih awal dari tanggal masuk.',
        ]);

        // Harga satuan = total belanja / jumlah masuk (persis seperti perhitungan di web).
        $unitPrice = $request->buy_price_total / $request->initial_quantity;

        $batch = DB::transaction(function () use ($request, $unitPrice) {
            $batch = IngredientBatch::create([
                'ingredient_id' => $request->ingredient_id,
                'supplier_id' => $request->supplier_id ?: null,
                'initial_quantity' => $request->initial_quantity,
                'remaining_quantity' => $request->initial_quantity,
                'buy_price' => $unitPrice,
                'buy_price_total' => $request->buy_price_total,
                'entry_date' => $request->entry_date,
                'expiry_date' => $request->expiry_date ?: null,
            ]);

            StockMovement::create([
                'ingredient_id' => $request->ingredient_id,
                'ingredient_batch_id' => $batch->id,
                'type' => 'in',
                'quantity' => $request->initial_quantity,
                'cost_total' => $request->buy_price_total,
                'reason' => 'purchase',
                'reference' => 'Stok Masuk Manual',
            ]);

            return $batch;
        });

        return $this->created(
            new IngredientBatchResource($batch->load('ingredient', 'supplier')),
            'Stok bahan berhasil ditambahkan ke sistem FIFO!'
        );
    }

    #[OA\Delete(
        path: '/api/v1/stock-batches/{id}',
        operationId: 'stockBatchDestroy',
        summary: 'Hapus batch stok',
        description: 'Menghapus satu batch stok. Bila batch sudah terpakai sebagian '
            . '(`remaining_quantity` < `initial_quantity`), batch tetap dihapus namun pesan balasan '
            . 'memuat peringatan agar kasir/admin tahu bahwa riwayat pemakaian batch tersebut sudah ada. '
            . 'Status tetap 200.',
        tags: ['Finance'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', description: 'ID batch stok', in: 'path', required: true, schema: new OA\Schema(type: 'integer', example: 7)),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Batch stok berhasil dihapus (dengan/tanpa peringatan)'),
            new OA\Response(response: 404, description: 'Batch stok tidak ditemukan'),
        ]
    )]
    public function destroy($id): JsonResponse
    {
        $batch = IngredientBatch::findOrFail($id);

        $isPartiallyUsed = (float) $batch->remaining_quantity < (float) $batch->initial_quantity;

        DB::transaction(fn () => $batch->delete());

        $message = $isPartiallyUsed
            ? 'Batch stok dihapus. Perhatian: batch ini sudah terpakai sebagian.'
            : 'Batch stok berhasil dihapus!';

        return $this->ok(['was_partially_used' => $isPartiallyUsed], $message);
    }
}
