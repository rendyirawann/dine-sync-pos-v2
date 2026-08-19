<?php

namespace App\Http\Controllers\Api\V1;

use App\Events\CallQueueEvent;
use App\Http\Controllers\Api\BaseApiController;
use App\Http\Resources\OrderResource;
use App\Models\IngredientBatch;
use App\Models\Order;
use App\Models\OrderDetail;
use App\Services\StockService;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use OpenApi\Attributes as OA;

/**
 * Kitchen Display System (KDS) — replika perilaku KitchenController web:
 * papan pesanan, resep + pilihan batch bahan, potong stok FEFO, dan panggilan suara.
 */
class KitchenController extends BaseApiController
{
    public function __construct(protected StockService $stockService) {}

    #[OA\Get(
        path: '/api/v1/kitchen/orders',
        operationId: 'kitchenOrders',
        summary: 'Papan pesanan dapur (aktif & selesai)',
        description: <<<'TXT'
Mengembalikan dua kelompok pesanan, sama seperti layar dapur di web:

- **active**: `order_status` = `pending` atau `cooking`, **tanpa filter tanggal** (disengaja)
  agar pesanan hari sebelumnya yang belum selesai tetap tampil, diurut `created_at` ASC.
- **completed**: `order_status` = `served` atau `completed`, hanya 3 hari terakhir
  (`updated_at >= now() - 3 hari`), diurut `updated_at` DESC.

Setiap order sudah memuat `details[]` beserta `status` per item
(`pending` = Antre, `cooking` = Dimasak, `done` = Siap), sehingga klien dapat
menghitung sendiri `has_pending` = ada minimal satu `details[].status == 'pending'`
tanpa perlu field tambahan (bentuk `active` & `completed` dibuat identik agar mudah dipakai).
TXT,
        tags: ['Dapur'],
        security: [['sanctum' => []]],
        responses: [
            new OA\Response(response: 200, description: 'Daftar pesanan dapur', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'message', type: 'string', example: 'Data dapur berhasil dimuat.'),
                    new OA\Property(property: 'data', properties: [
                        new OA\Property(property: 'active', type: 'array', items: new OA\Items(type: 'object')),
                        new OA\Property(property: 'completed', type: 'array', items: new OA\Items(type: 'object')),
                        new OA\Property(property: 'counts', properties: [
                            new OA\Property(property: 'active', type: 'integer', example: 4),
                            new OA\Property(property: 'completed', type: 'integer', example: 12),
                        ], type: 'object'),
                    ], type: 'object'),
                ]
            )),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 403, description: 'Tidak punya izin view_kitchen'),
        ]
    )]
    public function orders(Request $request): JsonResponse
    {
        // Tanpa filter tanggal: order kemarin yang belum selesai HARUS tetap muncul di dapur.
        $activeOrders = Order::with(['table', 'details.menu'])
            ->whereIn('order_status', ['pending', 'cooking'])
            ->orderBy('created_at', 'asc')
            ->get();

        $completedOrders = Order::with(['table', 'details.menu'])
            ->whereIn('order_status', ['served', 'completed'])
            ->where('updated_at', '>=', Carbon::now()->subDays(3))
            ->orderBy('updated_at', 'desc')
            ->get();

        return $this->ok([
            'active' => OrderResource::collection($activeOrders),
            'completed' => OrderResource::collection($completedOrders),
            'counts' => [
                'active' => $activeOrders->count(),
                'completed' => $completedOrders->count(),
            ],
        ], 'Data dapur berhasil dimuat.');
    }

    #[OA\Get(
        path: '/api/v1/kitchen/items/{id}/recipe',
        operationId: 'kitchenItemRecipe',
        summary: 'Resep item pesanan + pilihan batch bahan',
        description: <<<'TXT'
Detail resep satu item pesanan (`order_details.id`) untuk modal "Pilih Batch" di dapur.

Setiap bahan menyertakan daftar batch yang masih bersisa, diurut **FEFO**
(kedaluwarsa terdekat lebih dulu, batch tanpa tanggal kedaluwarsa di akhir).
`suggested_batch` = batch teratas (saran otomatis), `label` siap dipakai sebagai teks dropdown.
Bila `is_stock_deducted` sudah `true`, stok item ini sudah pernah dipotong sehingga
tidak akan dipotong ulang saat status diubah.
TXT,
        tags: ['Dapur'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID order detail (item pesanan)', schema: new OA\Schema(type: 'integer')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Detail resep', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'data', properties: [
                        new OA\Property(property: 'menu_name', type: 'string', example: 'Nasi Goreng Spesial'),
                        new OA\Property(property: 'qty', type: 'integer', example: 2),
                        new OA\Property(property: 'is_stock_deducted', type: 'boolean', example: false),
                        new OA\Property(property: 'recipes', type: 'array', items: new OA\Items(
                            properties: [
                                new OA\Property(property: 'ingredient_id', type: 'integer', example: 7),
                                new OA\Property(property: 'name', type: 'string', example: 'Beras'),
                                new OA\Property(property: 'needed', type: 'number', format: 'float', example: 0.4),
                                new OA\Property(property: 'unit', type: 'string', example: 'kg'),
                                new OA\Property(property: 'batches', type: 'array', items: new OA\Items(type: 'object')),
                                new OA\Property(property: 'suggested_batch', type: 'integer', nullable: true, example: 12),
                            ],
                            type: 'object'
                        )),
                    ], type: 'object'),
                ]
            )),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 404, description: 'Item pesanan tidak ditemukan'),
        ]
    )]
    public function recipe($id): JsonResponse
    {
        $detail = OrderDetail::with(['menu.ingredients.ingredient'])->findOrFail($id);
        $recipes = [];

        foreach ($detail->menu->ingredients as $recipe) {
            $ingredient = $recipe->ingredient;

            // NULLS LAST = sintaks PostgreSQL (DB project ini pgsql) — urutan FEFO seperti web.
            $batches = IngredientBatch::where('ingredient_id', $ingredient->id)
                ->where('remaining_quantity', '>', 0)
                ->orderByRaw('expiry_date ASC NULLS LAST')
                ->get()
                ->map(function ($b) {
                    $arrival = date('d/m/y', strtotime($b->created_at));
                    $expiry = $b->expiry_date ? date('d/m/y', strtotime($b->expiry_date)) : 'N/A';

                    return [
                        'id' => $b->id,
                        'supplier' => $b->supplier->name ?? 'Manual',
                        'remaining' => (float) $b->remaining_quantity,
                        'expiry' => $expiry,
                        'arrival' => $arrival,
                        'label' => ($b->supplier->name ?? 'Manual') . " (Masuk: $arrival | Exp: $expiry) - Sisa: " . number_format($b->remaining_quantity, 2),
                    ];
                });

            $recipes[] = [
                'ingredient_id' => $ingredient->id,
                'name' => $ingredient->name,
                'needed' => (float) ($recipe->quantity * $detail->qty),
                'unit' => $ingredient->unit,
                'batches' => $batches,
                'suggested_batch' => $batches->first()['id'] ?? null,
            ];
        }

        return $this->ok([
            'menu_name' => $detail->menu->name,
            'qty' => $detail->qty,
            'is_stock_deducted' => (bool) $detail->is_stock_deducted,
            'recipes' => $recipes,
        ], 'Detail resep berhasil dimuat.');
    }

    #[OA\Post(
        path: '/api/v1/kitchen/items/{id}/status',
        operationId: 'kitchenUpdateItemStatus',
        summary: 'Ubah status satu item pesanan',
        description: <<<'TXT'
Mengubah status satu item (`pending` / `cooking` / `done`).

Stok bahan dipotong **sekali saja**: saat status menjadi `cooking` atau `done`
dan item belum pernah dipotong (`is_stock_deducted = false`). Kirim `selections`
(map `ingredient_id` => `batch_id`, dari endpoint resep) bila juru masak memilih
batch secara manual; bila tidak dikirim, sistem memakai FEFO otomatis.

Status order induk ikut menyesuaikan otomatis: semua item `done` -> order `served`
(`is_finished = true`), ada item `cooking`/`done` -> order `cooking`, sisanya `pending`.
TXT,
        tags: ['Dapur'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID order detail (item pesanan)', schema: new OA\Schema(type: 'integer')),
        ],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['status'],
                properties: [
                    new OA\Property(property: 'status', type: 'string', enum: ['pending', 'cooking', 'done'], example: 'cooking'),
                    new OA\Property(
                        property: 'selections',
                        type: 'object',
                        description: 'Opsional. Map ingredient_id => batch_id untuk pemilihan batch manual, mis. {"7": 12, "9": 15}.',
                        example: ['7' => 12, '9' => 15]
                    ),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 200, description: 'Status item diperbarui', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'data', properties: [
                        new OA\Property(property: 'is_finished', type: 'boolean', example: false),
                        new OA\Property(property: 'table_name', type: 'string', example: 'Meja 4'),
                        new OA\Property(property: 'order', type: 'object'),
                    ], type: 'object'),
                ]
            )),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 404, description: 'Item pesanan tidak ditemukan'),
            new OA\Response(response: 422, description: 'Validasi gagal'),
        ]
    )]
    public function updateItemStatus(Request $request, $id): JsonResponse
    {
        $request->validate([
            'status' => 'required|in:pending,cooking,done',
            'selections' => 'nullable|array',
        ], [
            'status.required' => 'Status item wajib diisi.',
            'status.in' => 'Status item hanya boleh pending, cooking, atau done.',
            'selections.array' => 'Format pilihan batch tidak valid (harus objek ingredient_id => batch_id).',
        ]);

        $payload = DB::transaction(function () use ($request, $id) {
            $detail = OrderDetail::findOrFail($id);
            $detail->update(['status' => $request->status]);

            // Pilihan batch manual dari juru masak: [ingredient_id => batch_id]
            $selections = $request->selections ?? [];

            if (! $detail->is_stock_deducted && in_array($request->status, ['cooking', 'done'])) {
                $this->stockService->deductMenuStock($detail, $selections);
            }

            $order = Order::findOrFail($detail->order_id);

            $totalItems = $order->details()->count();
            $doneItems = $order->details()->where('status', 'done')->count();
            $cookingItems = $order->details()->where('status', 'cooking')->count();

            $isFinished = false;
            if ($doneItems == $totalItems) {
                $order->update(['order_status' => 'served']);
                $isFinished = true;
            } elseif ($cookingItems > 0 || $doneItems > 0) {
                $order->update(['order_status' => 'cooking']);
            } else {
                $order->update(['order_status' => 'pending']);
            }

            return [
                'is_finished' => $isFinished,
                'table_name' => $order->table->table_number ?? 'Walk-in',
                'order' => new OrderResource($order->load('details.menu', 'table')),
            ];
        });

        return $this->ok($payload, 'Status item berhasil diperbarui.');
    }

    #[OA\Post(
        path: '/api/v1/kitchen/orders/{id}/status',
        operationId: 'kitchenUpdateOrderStatus',
        summary: 'Ubah status seluruh item dalam satu pesanan',
        description: <<<'TXT'
Aksi massal untuk satu pesanan (tombol "Masak Semua" / "Semua Siap" di web).

- `status = cooking`: semua item `pending` menjadi `cooking`, stok dipotong bila belum,
  order menjadi `cooking`.
- `status = done`: semua item `pending`/`cooking` menjadi `done`, stok dipotong bila belum,
  order menjadi `served` (`is_finished = true`), lalu **panggilan suara "pesanan siap"**
  disiarkan ke TV display dengan cooldown 15 detik (key cache `audio_cooldown`).

Kegagalan broadcast (Reverb mati) hanya dicatat di log — perubahan status tetap tersimpan.
TXT,
        tags: ['Dapur'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID order', schema: new OA\Schema(type: 'integer')),
        ],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['status'],
                properties: [
                    new OA\Property(property: 'status', type: 'string', enum: ['cooking', 'done'], example: 'done'),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 200, description: 'Status pesanan diperbarui', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'data', properties: [
                        new OA\Property(property: 'is_finished', type: 'boolean', example: true),
                        new OA\Property(property: 'table_name', type: 'string', example: 'Meja 4'),
                        new OA\Property(property: 'order', type: 'object'),
                    ], type: 'object'),
                ]
            )),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 404, description: 'Pesanan tidak ditemukan'),
            new OA\Response(response: 422, description: 'Validasi gagal'),
        ]
    )]
    public function updateOrderStatus(Request $request, $id): JsonResponse
    {
        $request->validate([
            'status' => 'required|in:cooking,done',
        ], [
            'status.required' => 'Status pesanan wajib diisi.',
            'status.in' => 'Status pesanan hanya boleh cooking atau done.',
        ]);

        $order = Order::with('details')->findOrFail($id);

        $payload = DB::transaction(function () use ($request, $order) {
            $isFinished = false;

            if ($request->status == 'cooking') {
                $pendingDetails = $order->details()->where('status', 'pending')->get();
                foreach ($pendingDetails as $detail) {
                    if (! $detail->is_stock_deducted) {
                        $this->stockService->deductMenuStock($detail);
                    }
                    $detail->update(['status' => 'cooking']);
                }
                $order->update(['order_status' => 'cooking']);
            } elseif ($request->status == 'done') {
                $undoneDetails = $order->details()->whereIn('status', ['pending', 'cooking'])->get();
                foreach ($undoneDetails as $detail) {
                    if (! $detail->is_stock_deducted) {
                        $this->stockService->deductMenuStock($detail);
                    }
                    $detail->update(['status' => 'done']);
                }
                $order->update(['order_status' => 'served']);
                $isFinished = true;

                // Panggilan suara "pesanan siap" — cooldown 15 detik agar tidak tumpang tindih.
                if (! Cache::has('audio_cooldown')) {
                    try {
                        $textToSpeak = 'Pesanan atas nama, ' . $order->customer_name . ', sudah siap untuk diambil.';
                        $displayData = [
                            'number' => '#' . (explode('-', $order->invoice_no)[1] ?? $order->invoice_no),
                            'name' => $order->customer_name,
                        ];
                        Cache::put('audio_cooldown', true, 15);
                        broadcast(new CallQueueEvent($textToSpeak, $displayData, 'food', app('tenant')->id()));
                    } catch (\Exception $e) {
                        // Reverb mati: abaikan, status pesanan HARUS tetap tersimpan.
                        Log::warning('Kitchen broadcast failed: ' . $e->getMessage());
                    }
                }
            }

            return [
                'is_finished' => $isFinished,
                'table_name' => $order->table->table_number ?? 'Walk-in',
                'order' => new OrderResource($order->load('details.menu', 'table')),
            ];
        });

        $message = $request->status == 'done'
            ? 'Semua item ditandai siap. Pesanan siap disajikan.'
            : 'Semua item ditandai sedang dimasak.';

        return $this->ok($payload, $message);
    }

    #[OA\Post(
        path: '/api/v1/kitchen/orders/{id}/recall',
        operationId: 'kitchenRecallOrder',
        summary: 'Panggil ulang pesanan yang sudah siap',
        description: <<<'TXT'
Menyiarkan ulang panggilan suara "pesanan siap" ke TV display (tanpa mengubah status apa pun).

Dibatasi cooldown 15 detik (key cache `audio_cooldown`) agar tidak bertabrakan dengan
panggilan lain; bila masih dalam cooldown, response `429`.
Kegagalan broadcast (Reverb mati) hanya dicatat di log.
TXT,
        tags: ['Dapur'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID order', schema: new OA\Schema(type: 'integer')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Panggilan ulang dikirim'),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 404, description: 'Pesanan tidak ditemukan'),
            new OA\Response(response: 429, description: 'Masih dalam cooldown panggilan'),
        ]
    )]
    public function recall(Request $request, $id): JsonResponse
    {
        if (Cache::has('audio_cooldown')) {
            return $this->fail('Harap tunggu! Sedang ada pemanggilan lain yang berlangsung.', 429);
        }

        $order = Order::findOrFail($id);

        $textToSpeak = 'Panggilan ulang. Pesanan atas nama, ' . $order->customer_name . ', sudah siap untuk diambil.';
        $displayData = [
            'number' => '#' . (explode('-', $order->invoice_no)[1] ?? $order->invoice_no),
            'name' => $order->customer_name,
        ];

        Cache::put('audio_cooldown', true, 15);

        try {
            broadcast(new CallQueueEvent($textToSpeak, $displayData, 'food', app('tenant')->id()));
        } catch (\Exception $e) {
            Log::warning('Recall broadcast failed: ' . $e->getMessage());
        }

        return $this->ok([
            'order_id' => $order->id,
            'customer_name' => $order->customer_name,
            'cooldown_left' => 15,
        ], 'Memanggil ulang pesanan ' . $order->customer_name);
    }
}
