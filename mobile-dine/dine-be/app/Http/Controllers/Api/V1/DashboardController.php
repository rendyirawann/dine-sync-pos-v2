<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Api\BaseApiController;
use App\Http\Resources\MenuResource;
use App\Models\DailyBudget;
use App\Models\DailySalesTarget;
use App\Models\Expense;
use App\Models\Menu;
use App\Models\Order;
use App\Models\OrderDetail;
use App\Models\StockMovement;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use OpenApi\Attributes as OA;

/**
 * Dashboard mobile — replikasi dari dashboard web (DashboardAdminController)
 * plus widget harian yang di web dipasang lewat View::composer sidebar.
 *
 * Semua angka default memakai periode BULAN INI (tanggal 1 s/d akhir bulan),
 * dan bisa di-override lewat query ?from=Y-m-d&to=Y-m-d.
 */
class DashboardController extends BaseApiController
{
    #[OA\Get(
        path: '/api/v1/dashboard/summary',
        operationId: 'dashboardSummary',
        summary: 'Ringkasan omzet, HPP, pengeluaran & laba',
        description: <<<'TXT'
Ringkasan angka utama dashboard. Secara default memakai periode **BULAN INI**
(tanggal 1 sampai akhir bulan berjalan), sama seperti dashboard web.

Periode dapat di-override dengan query `from` dan `to` (format `Y-m-d`, opsional).
Bila hanya salah satu dikirim, sisanya tetap memakai batas bulan berjalan.

Perhitungan:
- `revenue` = total `grand_total` order berstatus bayar `paid`.
- `hpp` = total `hpp` item order yang notanya `paid`.
- `expense` = total pengeluaran (tabel expenses) pada rentang tanggal.
- `gross_profit` = revenue - hpp.
- `net_profit` = revenue - hpp - expense.
TXT,
        tags: ['Dashboard'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'from', in: 'query', required: false, description: 'Tanggal awal periode (Y-m-d). Default: tanggal 1 bulan ini.', schema: new OA\Schema(type: 'string', format: 'date', example: '2026-08-01')),
            new OA\Parameter(name: 'to', in: 'query', required: false, description: 'Tanggal akhir periode (Y-m-d). Default: akhir bulan ini.', schema: new OA\Schema(type: 'string', format: 'date', example: '2026-08-31')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Ringkasan periode', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'message', type: 'string', example: 'Ringkasan dashboard berhasil dimuat.'),
                    new OA\Property(property: 'data', properties: [
                        new OA\Property(property: 'period', properties: [
                            new OA\Property(property: 'from', type: 'string', format: 'date', example: '2026-08-01'),
                            new OA\Property(property: 'to', type: 'string', format: 'date', example: '2026-08-31'),
                        ], type: 'object'),
                        new OA\Property(property: 'revenue', type: 'number', format: 'float', example: 12500000),
                        new OA\Property(property: 'hpp', type: 'number', format: 'float', example: 4200000),
                        new OA\Property(property: 'expense', type: 'number', format: 'float', example: 1500000),
                        new OA\Property(property: 'items_sold', type: 'integer', example: 340),
                        new OA\Property(property: 'gross_profit', type: 'number', format: 'float', example: 8300000),
                        new OA\Property(property: 'net_profit', type: 'number', format: 'float', example: 6800000),
                    ], type: 'object'),
                ]
            )),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 422, description: 'Format tanggal tidak valid'),
        ]
    )]
    public function summary(Request $request): JsonResponse
    {
        [$start, $end] = $this->resolvePeriod($request);

        $revenue = Order::whereBetween('created_at', [$start, $end])
            ->where('payment_status', 'paid')
            ->sum('grand_total');

        $totalHpp = OrderDetail::whereHas('order', function ($q) use ($start, $end) {
            $q->whereBetween('created_at', [$start, $end])
                ->where('payment_status', 'paid');
        })->sum('hpp');

        $expense = Expense::whereBetween('date', [$start->format('Y-m-d'), $end->format('Y-m-d')])->sum('amount');

        $itemsSold = OrderDetail::whereHas('order', function ($q) use ($start, $end) {
            $q->whereBetween('created_at', [$start, $end])
                ->where('payment_status', 'paid');
        })->sum('qty');

        return $this->ok([
            'period' => [
                'from' => $start->format('Y-m-d'),
                'to' => $end->format('Y-m-d'),
            ],
            'revenue' => (float) $revenue,
            'hpp' => (float) $totalHpp,
            'expense' => (float) $expense,
            'items_sold' => (int) $itemsSold,
            'gross_profit' => (float) ($revenue - $totalHpp),
            'net_profit' => (float) ($revenue - $totalHpp - $expense),
        ], 'Ringkasan dashboard berhasil dimuat.');
    }

    #[OA\Get(
        path: '/api/v1/dashboard/chart',
        operationId: 'dashboardChart',
        summary: 'Grafik omzet aktual vs target per hari',
        description: <<<'TXT'
Data grafik untuk membandingkan **omzet aktual** dengan **target penjualan harian**.

Default periode: **BULAN INI**, dan perulangan hari berhenti di hari ini
(hari yang belum terjadi tidak ditampilkan) — sama seperti grafik dashboard web.
Periode bisa di-override lewat query `from` & `to` (format `Y-m-d`, opsional);
bila `to` sudah lewat, perulangan berhenti di `to`.

Tiga array yang dikembalikan selalu sama panjang dan sejajar indeksnya:
`categories` (label tanggal "d M"), `sales` (omzet), `targets` (target).
TXT,
        tags: ['Dashboard'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'from', in: 'query', required: false, description: 'Tanggal awal periode (Y-m-d). Default: tanggal 1 bulan ini.', schema: new OA\Schema(type: 'string', format: 'date', example: '2026-08-01')),
            new OA\Parameter(name: 'to', in: 'query', required: false, description: 'Tanggal akhir periode (Y-m-d). Default: akhir bulan ini.', schema: new OA\Schema(type: 'string', format: 'date', example: '2026-08-31')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Data grafik', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'message', type: 'string', example: 'Data grafik berhasil dimuat.'),
                    new OA\Property(property: 'data', properties: [
                        new OA\Property(property: 'categories', type: 'array', items: new OA\Items(type: 'string', example: '01 Agu')),
                        new OA\Property(property: 'sales', type: 'array', items: new OA\Items(type: 'integer', example: 450000)),
                        new OA\Property(property: 'targets', type: 'array', items: new OA\Items(type: 'integer', example: 500000)),
                    ], type: 'object'),
                ]
            )),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 422, description: 'Format tanggal tidak valid'),
        ]
    )]
    public function chart(Request $request): JsonResponse
    {
        [$start, $end] = $this->resolvePeriod($request);

        // Omzet aktual per hari (hasil pluck bisa berformat kunci berbeda di PostgreSQL).
        $actualSales = Order::whereBetween('created_at', [$start, $end])
            ->where('payment_status', 'paid')
            ->select(DB::raw('DATE(created_at) as date'), DB::raw('SUM(grand_total) as total'))
            ->groupBy(DB::raw('DATE(created_at)'))
            ->pluck('total', 'date');

        // Target penjualan per hari.
        $targets = DailySalesTarget::whereBetween('date', [$start->format('Y-m-d'), $end->format('Y-m-d')])
            ->pluck('amount', 'date');

        // Normalisasi kunci ke Y-m-d supaya angka tidak selalu 0 (PostgreSQL bisa
        // mengembalikan "2026-08-02 00:00:00" untuk DATE(created_at)/kolom date).
        $salesByDate = $this->normalizeDateKeys($actualSales);
        $targetsByDate = $this->normalizeDateKeys($targets);

        // Hari terakhir yang ditampilkan: tidak melewati hari ini dan tidak melewati akhir periode.
        $now = Carbon::now();
        $limit = $end->lt($now) ? $end->copy() : $now->copy();

        $dates = [];
        $sales = [];
        $targetSeries = [];

        for ($d = $start->copy(); $d->lte($limit); $d->addDay()) {
            $ds = $d->format('Y-m-d');
            $dates[] = $d->format('d M');
            $sales[] = (int) ($salesByDate[$ds] ?? 0);
            $targetSeries[] = (int) ($targetsByDate[$ds] ?? 0);
        }

        return $this->ok([
            'categories' => $dates,
            'sales' => $sales,
            'targets' => $targetSeries,
        ], 'Data grafik berhasil dimuat.');
    }

    #[OA\Get(
        path: '/api/v1/dashboard/top-menus',
        operationId: 'dashboardTopMenus',
        summary: 'Menu terlaris (Top 5)',
        description: <<<'TXT'
Daftar menu paling banyak terjual pada periode, diurutkan dari qty terbanyak.
Hanya menghitung nota dengan status bayar `paid`.

Default periode **BULAN INI** dan default 5 baris. Jumlah baris dapat diatur
lewat query `limit` (minimal 1, maksimal 20). Periode dapat di-override lewat
query `from` & `to` (format `Y-m-d`).

Bila menu sudah dihapus, `menu_name` berisi "Menu Dihapus" dan `category_name` berisi "-".
TXT,
        tags: ['Dashboard'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'from', in: 'query', required: false, description: 'Tanggal awal periode (Y-m-d). Default: tanggal 1 bulan ini.', schema: new OA\Schema(type: 'string', format: 'date', example: '2026-08-01')),
            new OA\Parameter(name: 'to', in: 'query', required: false, description: 'Tanggal akhir periode (Y-m-d). Default: akhir bulan ini.', schema: new OA\Schema(type: 'string', format: 'date', example: '2026-08-31')),
            new OA\Parameter(name: 'limit', in: 'query', required: false, description: 'Jumlah menu yang diambil (default 5, maksimal 20).', schema: new OA\Schema(type: 'integer', default: 5, maximum: 20, minimum: 1)),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Daftar menu terlaris', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'message', type: 'string', example: 'Menu terlaris berhasil dimuat.'),
                    new OA\Property(property: 'data', type: 'array', items: new OA\Items(properties: [
                        new OA\Property(property: 'menu_id', type: 'integer', example: 12),
                        new OA\Property(property: 'menu_name', type: 'string', example: 'Ayam Geprek'),
                        new OA\Property(property: 'category_name', type: 'string', example: 'Makanan'),
                        new OA\Property(property: 'total_qty', type: 'integer', example: 64),
                        new OA\Property(property: 'total_revenue', type: 'number', format: 'float', example: 1280000),
                    ], type: 'object')),
                ]
            )),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 422, description: 'Parameter tidak valid'),
        ]
    )]
    public function topMenus(Request $request): JsonResponse
    {
        [$start, $end] = $this->resolvePeriod($request);

        $request->validate([
            'limit' => ['nullable', 'integer', 'min:1', 'max:20'],
        ], [
            'limit.integer' => 'Limit harus berupa angka.',
            'limit.min' => 'Limit minimal 1.',
            'limit.max' => 'Limit maksimal 20.',
        ]);

        $limit = (int) $request->query('limit', 5);
        $limit = max(1, min($limit ?: 5, 20));

        $rows = OrderDetail::with(['menu.category'])
            ->whereHas('order', function ($q) use ($start, $end) {
                $q->whereBetween('created_at', [$start, $end])
                    ->where('payment_status', 'paid');
            })
            ->select('menu_id', DB::raw('SUM(qty) as total_qty'), DB::raw('SUM(subtotal) as total_revenue'))
            ->groupBy('menu_id')
            ->orderByDesc('total_qty')
            ->limit($limit)
            ->get();

        $data = $rows->map(function ($row) {
            return [
                'menu_id' => $row->menu_id,
                'menu_name' => $row->menu->name ?? 'Menu Dihapus',
                'category_name' => $row->menu->category->name ?? '-',
                'total_qty' => (int) $row->total_qty,
                'total_revenue' => (float) $row->total_revenue,
            ];
        })->values();

        return $this->ok($data, 'Menu terlaris berhasil dimuat.');
    }

    #[OA\Get(
        path: '/api/v1/dashboard/unavailable-menus',
        operationId: 'dashboardUnavailableMenus',
        summary: 'Menu yang sedang tidak tersedia / habis',
        description: 'Daftar menu dengan status `is_available = false` (stok habis atau sengaja dinonaktifkan), lengkap dengan kategorinya. Dipakai sebagai kartu peringatan di dashboard.',
        tags: ['Dashboard'],
        security: [['sanctum' => []]],
        responses: [
            new OA\Response(response: 200, description: 'Daftar menu tidak tersedia', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'message', type: 'string', example: 'Daftar menu tidak tersedia berhasil dimuat.'),
                    new OA\Property(property: 'data', type: 'array', items: new OA\Items(type: 'object')),
                ]
            )),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
        ]
    )]
    public function unavailableMenus(): JsonResponse
    {
        $menus = Menu::with('category')
            ->where('is_available', false)
            ->get();

        return $this->ok(MenuResource::collection($menus), 'Daftar menu tidak tersedia berhasil dimuat.');
    }

    #[OA\Get(
        path: '/api/v1/dashboard/hpp-details',
        operationId: 'dashboardHppDetails',
        summary: 'Rincian HPP per nota (berpaginasi)',
        description: <<<'TXT'
Rincian Harga Pokok Penjualan untuk setiap nota yang sudah dibayar (`paid`),
diurutkan dari yang terbaru. Tiap nota memuat daftar item, dan tiap item memuat
rincian bahan baku yang dipotong untuk porsi tersebut (dari `stock_movements`,
hanya bahan dengan biaya lebih dari 0).

Default periode **BULAN INI**, bisa di-override lewat query `from` & `to` (format `Y-m-d`).
Ukuran halaman diatur lewat query `per_page` (default 20, maksimal 100).
TXT,
        tags: ['Dashboard'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'from', in: 'query', required: false, description: 'Tanggal awal periode (Y-m-d). Default: tanggal 1 bulan ini.', schema: new OA\Schema(type: 'string', format: 'date', example: '2026-08-01')),
            new OA\Parameter(name: 'to', in: 'query', required: false, description: 'Tanggal akhir periode (Y-m-d). Default: akhir bulan ini.', schema: new OA\Schema(type: 'string', format: 'date', example: '2026-08-31')),
            new OA\Parameter(name: 'per_page', in: 'query', required: false, description: 'Jumlah nota per halaman (default 20, maksimal 100).', schema: new OA\Schema(type: 'integer', default: 20, maximum: 100, minimum: 1)),
            new OA\Parameter(name: 'page', in: 'query', required: false, description: 'Halaman yang diminta.', schema: new OA\Schema(type: 'integer', default: 1, minimum: 1)),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Rincian HPP per nota', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'message', type: 'string', example: 'Rincian HPP berhasil dimuat.'),
                    new OA\Property(property: 'data', type: 'array', items: new OA\Items(properties: [
                        new OA\Property(property: 'invoice_no', type: 'string', example: 'INV-20260819-0007'),
                        new OA\Property(property: 'created_at', type: 'string', format: 'date-time'),
                        new OA\Property(property: 'payment_method', type: 'string', example: 'cash'),
                        new OA\Property(property: 'total_hpp', type: 'number', format: 'float', example: 18500),
                        new OA\Property(property: 'items', type: 'array', items: new OA\Items(properties: [
                            new OA\Property(property: 'menu_name', type: 'string', example: 'Ayam Geprek'),
                            new OA\Property(property: 'qty', type: 'integer', example: 2),
                            new OA\Property(property: 'hpp', type: 'number', format: 'float', example: 12000),
                            new OA\Property(property: 'ingredients', type: 'array', items: new OA\Items(properties: [
                                new OA\Property(property: 'name', type: 'string', example: 'Ayam Potong'),
                                new OA\Property(property: 'cost_total', type: 'number', format: 'float', example: 9000),
                            ], type: 'object')),
                        ], type: 'object')),
                    ], type: 'object')),
                    new OA\Property(property: 'meta', type: 'object'),
                ]
            )),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 422, description: 'Format tanggal tidak valid'),
        ]
    )]
    public function hppDetails(Request $request): JsonResponse
    {
        [$start, $end] = $this->resolvePeriod($request);

        $orders = Order::with(['details.menu'])
            ->where('payment_status', 'paid')
            ->whereBetween('created_at', [$start, $end])
            ->orderBy('created_at', 'desc')
            ->paginate($this->perPage());

        $orders->through(function ($order) {
            $items = $order->details->map(function ($detail) {
                // Rincian bahan baku KHUSUS untuk porsi menu ini di nota ini.
                $breakdown = StockMovement::join('ingredients', 'stock_movements.ingredient_id', '=', 'ingredients.id')
                    ->where('stock_movements.order_detail_id', $detail->id)
                    ->select('ingredients.name as ing_name', 'stock_movements.cost_total')
                    ->get();

                $ingredients = $breakdown
                    ->filter(fn ($row) => (float) $row->cost_total > 0)
                    ->map(fn ($row) => [
                        'name' => $row->ing_name,
                        'cost_total' => (float) $row->cost_total,
                    ])
                    ->values();

                return [
                    'menu_name' => $detail->menu->name ?? 'Menu Dihapus',
                    'qty' => (int) $detail->qty,
                    'hpp' => (float) $detail->hpp,
                    'ingredients' => $ingredients,
                ];
            })->values();

            return [
                'invoice_no' => $order->invoice_no,
                'created_at' => optional($order->created_at)->toIso8601String(),
                'payment_method' => $order->payment_method,
                'total_hpp' => (float) $order->details->sum('hpp'),
                'items' => $items,
            ];
        });

        return $this->paginated($orders, 'Rincian HPP berhasil dimuat.');
    }

    #[OA\Get(
        path: '/api/v1/dashboard/daily',
        operationId: 'dashboardDaily',
        summary: 'Widget harian: target penjualan & budget pengeluaran',
        description: <<<'TXT'
Widget harian **HARI INI** (sama seperti widget di sidebar web):
target penjualan vs omzet masuk, dan budget vs pengeluaran terpakai.

Aturan persentase & warna (siap dipakai langsung di Flutter):
- Target penjualan: `sales_percentage` = omzet / target × 100 (0 bila target belum diatur).
  `sales_bar_width` dibatasi maksimal 100. Warna: >= 100 `success`, >= 50 `primary`, sisanya `warning`.
- Budget: `budget_percentage` = terpakai / budget × 100 dan dibatasi maksimal 100
  (0 bila budget belum diatur). Warna: >= 100 `danger`, >= 75 `warning`, sisanya `primary`.
TXT,
        tags: ['Dashboard'],
        security: [['sanctum' => []]],
        responses: [
            new OA\Response(response: 200, description: 'Widget harian', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'message', type: 'string', example: 'Data harian berhasil dimuat.'),
                    new OA\Property(property: 'data', properties: [
                        new OA\Property(property: 'date', type: 'string', format: 'date', example: '2026-08-19'),
                        new OA\Property(property: 'sales_target', type: 'number', format: 'float', example: 1000000),
                        new OA\Property(property: 'income', type: 'number', format: 'float', example: 750000),
                        new OA\Property(property: 'sales_percentage', type: 'integer', example: 75),
                        new OA\Property(property: 'sales_bar_width', type: 'integer', example: 75),
                        new OA\Property(property: 'sales_color', type: 'string', example: 'primary'),
                        new OA\Property(property: 'sales_message', type: 'string', example: 'Ayo Semangat! 💪'),
                        new OA\Property(property: 'budget', type: 'number', format: 'float', example: 500000),
                        new OA\Property(property: 'spent', type: 'number', format: 'float', example: 200000),
                        new OA\Property(property: 'budget_percentage', type: 'integer', example: 40),
                        new OA\Property(property: 'budget_color', type: 'string', example: 'primary'),
                    ], type: 'object'),
                ]
            )),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
        ]
    )]
    public function daily(): JsonResponse
    {
        $today = date('Y-m-d');

        // 1. Target penjualan harian.
        $salesTargetObj = DailySalesTarget::where('date', $today)->first();
        $salesTarget = $salesTargetObj ? $salesTargetObj->amount : 0;

        // 2. Omzet hari ini (order yang sudah dibayar).
        $income = Order::whereDate('created_at', $today)
            ->where('payment_status', 'paid')
            ->sum('grand_total');

        // 3. Budget & pengeluaran harian.
        $budgetObj = DailyBudget::where('date', $today)->first();
        $budget = $budgetObj ? $budgetObj->amount : 0;

        $spent = Expense::whereDate('date', $today)->sum('amount');

        // Persentase pengeluaran terhadap budget.
        $percentage = 0;
        $budgetColor = 'primary';
        if ($budget > 0) {
            $percentage = (int) round(($spent / $budget) * 100);
            if ($percentage >= 100) {
                $percentage = 100;
                $budgetColor = 'danger';
            } elseif ($percentage >= 75) {
                $budgetColor = 'warning';
            }
        }

        // Persentase penjualan terhadap target.
        $salesPercentage = 0;
        $salesBarWidth = 0;
        $salesColor = 'warning';
        if ($salesTarget > 0) {
            $salesPercentage = (int) round(($income / $salesTarget) * 100);
            $salesBarWidth = min(100, $salesPercentage);
            if ($salesPercentage >= 100) {
                $salesColor = 'success';
            } elseif ($salesPercentage >= 50) {
                $salesColor = 'primary';
            }
        }

        return $this->ok([
            'date' => $today,
            'sales_target' => (float) $salesTarget,
            'income' => (float) $income,
            'sales_percentage' => (int) $salesPercentage,
            'sales_bar_width' => (int) $salesBarWidth,
            'sales_color' => $salesColor,
            'sales_message' => $salesPercentage >= 100 ? 'Target Terlampaui! 🎉' : 'Ayo Semangat! 💪',
            'budget' => (float) $budget,
            'spent' => (float) $spent,
            'budget_percentage' => (int) $percentage,
            'budget_color' => $budgetColor,
        ], 'Data harian berhasil dimuat.');
    }

    /**
     * Periode aktif: default BULAN INI, boleh di-override lewat query from & to (Y-m-d).
     *
     * @return array{0: \Carbon\Carbon, 1: \Carbon\Carbon}
     */
    private function resolvePeriod(Request $request): array
    {
        $request->validate([
            'from' => ['nullable', 'date_format:Y-m-d'],
            'to' => ['nullable', 'date_format:Y-m-d'],
        ], [
            'from.date_format' => 'Tanggal awal harus berformat Y-m-d (contoh: 2026-08-01).',
            'to.date_format' => 'Tanggal akhir harus berformat Y-m-d (contoh: 2026-08-31).',
        ]);

        $from = $request->query('from');
        $to = $request->query('to');

        $start = $from
            ? Carbon::createFromFormat('Y-m-d', $from)->startOfDay()
            : Carbon::now()->startOfMonth();

        $end = $to
            ? Carbon::createFromFormat('Y-m-d', $to)->endOfDay()
            : Carbon::now()->endOfMonth();

        // Bila terbalik, tukar supaya rentang selalu valid.
        if ($end->lt($start)) {
            [$start, $end] = [$end->copy()->startOfDay(), $start->copy()->endOfDay()];
        }

        return [$start, $end];
    }

    /**
     * Ubah kunci hasil pluck() menjadi Y-m-d.
     *
     * PENTING: di PostgreSQL kunci bisa berupa "2026-08-02 00:00:00" (bukan "2026-08-02"),
     * sehingga pencarian per tanggal akan selalu 0 bila kunci tidak dinormalisasi.
     * Nilai dengan tanggal sama dijumlahkan.
     */
    private function normalizeDateKeys(mixed $values): array
    {
        $out = [];

        foreach ($values as $key => $value) {
            $raw = (string) $key;

            if (preg_match('/^\d{4}-\d{2}-\d{2}/', $raw) === 1) {
                $date = substr($raw, 0, 10);
            } else {
                try {
                    $date = Carbon::parse($raw)->format('Y-m-d');
                } catch (\Throwable) {
                    $date = $raw;
                }
            }

            $out[$date] = ($out[$date] ?? 0) + (float) $value;
        }

        return $out;
    }
}
