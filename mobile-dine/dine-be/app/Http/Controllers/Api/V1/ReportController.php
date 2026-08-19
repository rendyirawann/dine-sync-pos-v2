<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Api\BaseApiController;
use App\Http\Resources\OrderResource;
use App\Models\Order;
use App\Models\OrderDetail;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use OpenApi\Attributes as OA;

/**
 * Modul Laporan (Report).
 *
 * Logika bisnis direplikasi dari SalesReportController & ItemSalesReportController web.
 * PENTING untuk klien Flutter: SEMUA angka dikirim sebagai NUMBER mentah
 * (bukan string "Rp 1.000.000"), supaya aplikasi bisa memformatnya sendiri.
 */
class ReportController extends BaseApiController
{
    #[OA\Get(
        path: '/api/v1/reports/sales',
        operationId: 'reportSales',
        summary: 'Laporan penjualan (ringkasan + daftar transaksi)',
        description: 'Laporan transaksi LUNAS (`payment_status = paid`) pada rentang tanggal tertentu. '
            . 'Bagian `summary` dihitung dari query yang sama SEBELUM paginasi, sehingga totalnya '
            . 'mencerminkan seluruh transaksi terfilter (bukan hanya satu halaman): jumlah order, '
            . 'total omzet, total diskon promo, total HPP, dan laba bersih (omzet - HPP). '
            . 'Bila `start_date`/`end_date` tidak dikirim, dipakai tanggal hari ini. '
            . 'Seluruh nilai uang berupa angka mentah agar bisa diformat di aplikasi.',
        tags: ['Report'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'start_date', description: 'Tanggal awal (YYYY-MM-DD). Default: hari ini', in: 'query', required: false, schema: new OA\Schema(type: 'string', format: 'date', example: '2026-08-01')),
            new OA\Parameter(name: 'end_date', description: 'Tanggal akhir (YYYY-MM-DD). Default: hari ini', in: 'query', required: false, schema: new OA\Schema(type: 'string', format: 'date', example: '2026-08-19')),
            new OA\Parameter(name: 'payment_method', description: 'Filter metode pembayaran. Gunakan `all` untuk semua metode', in: 'query', required: false, schema: new OA\Schema(type: 'string', enum: ['all', 'cash', 'midtrans'], example: 'all')),
            new OA\Parameter(name: 'search', description: 'Cari nomor invoice atau nama pelanggan', in: 'query', required: false, schema: new OA\Schema(type: 'string', example: 'DSV2-INV')),
            new OA\Parameter(name: 'per_page', description: 'Jumlah transaksi per halaman (maks 100)', in: 'query', required: false, schema: new OA\Schema(type: 'integer', example: 20)),
            new OA\Parameter(name: 'page', description: 'Halaman ke-', in: 'query', required: false, schema: new OA\Schema(type: 'integer', example: 1)),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Ringkasan + daftar transaksi', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'message', type: 'string', example: 'Laporan penjualan berhasil diambil.'),
                    new OA\Property(property: 'data', properties: [
                        new OA\Property(property: 'summary', properties: [
                            new OA\Property(property: 'total_orders', type: 'integer', example: 42),
                            new OA\Property(property: 'total_revenue', type: 'number', format: 'float', example: 5250000),
                            new OA\Property(property: 'total_discount', type: 'number', format: 'float', example: 175000),
                            new OA\Property(property: 'total_hpp', type: 'number', format: 'float', example: 1980000),
                            new OA\Property(property: 'net_profit', type: 'number', format: 'float', example: 3270000),
                        ], type: 'object'),
                        new OA\Property(property: 'orders', type: 'array', items: new OA\Items(type: 'object')),
                        new OA\Property(property: 'meta', type: 'object'),
                    ], type: 'object'),
                ]
            )),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 403, description: 'Tidak punya izin view_report'),
        ]
    )]
    public function sales(Request $request): JsonResponse
    {
        $start = $request->filled('start_date')
            ? Carbon::parse($request->query('start_date'))->toDateString()
            : now()->toDateString();

        $end = $request->filled('end_date')
            ? Carbon::parse($request->query('end_date'))->toDateString()
            : now()->toDateString();

        $paymentMethod = (string) $request->query('payment_method', 'all');
        $search = $request->query('search');

        $base = Order::with(['table', 'promo', 'details'])
            ->where('payment_status', 'paid')
            ->whereBetween('created_at', [$start . ' 00:00:00', $end . ' 23:59:59']);

        if ($paymentMethod !== '' && $paymentMethod !== 'all') {
            $base->where('payment_method', $paymentMethod);
        }

        if ($search !== null && $search !== '') {
            $keyword = '%' . $search . '%';
            $base->where(function ($q) use ($keyword) {
                $q->where('invoice_no', 'like', $keyword)
                    ->orWhere('customer_name', 'like', $keyword);
            });
        }

        // Ringkasan dihitung dari query yang SAMA, sebelum paginasi (pakai clone).
        $totalRevenue = (clone $base)->sum('grand_total');
        $totalDiscount = (clone $base)->sum('discount_amount');
        $totalOrders = (clone $base)->count();

        $totalHpp = OrderDetail::whereHas('order', function ($q) use ($start, $end, $paymentMethod, $search) {
            $q->where('payment_status', 'paid')
                ->whereBetween('created_at', [$start . ' 00:00:00', $end . ' 23:59:59']);

            if ($paymentMethod !== '' && $paymentMethod !== 'all') {
                $q->where('payment_method', $paymentMethod);
            }

            if ($search !== null && $search !== '') {
                $keyword = '%' . $search . '%';
                $q->where(function ($qq) use ($keyword) {
                    $qq->where('invoice_no', 'like', $keyword)
                        ->orWhere('customer_name', 'like', $keyword);
                });
            }
        })->sum('hpp');

        $paginator = $base->orderBy('created_at', 'desc')->paginate($this->perPage());

        return $this->ok([
            'summary' => [
                'total_orders' => (int) $totalOrders,
                'total_revenue' => (float) $totalRevenue,
                'total_discount' => (float) $totalDiscount,
                'total_hpp' => (float) $totalHpp,
                'net_profit' => (float) ($totalRevenue - $totalHpp),
            ],
            'filters' => [
                'start_date' => $start,
                'end_date' => $end,
                'payment_method' => $paymentMethod !== '' ? $paymentMethod : 'all',
                'search' => $search,
            ],
            'orders' => OrderResource::collection($paginator->items()),
            'meta' => [
                'current_page' => $paginator->currentPage(),
                'last_page' => $paginator->lastPage(),
                'per_page' => $paginator->perPage(),
                'total' => $paginator->total(),
                'has_more' => $paginator->hasMorePages(),
            ],
        ], 'Laporan penjualan berhasil diambil.');
    }

    #[OA\Get(
        path: '/api/v1/reports/items',
        operationId: 'reportItems',
        summary: 'Laporan menu terlaris (agregasi per menu)',
        description: 'Rekap penjualan per menu dari transaksi LUNAS pada rentang tanggal tertentu, '
            . 'diurutkan dari porsi terbanyak. Agregasi memakai gabungan order_details + orders + menus + categories, '
            . 'dimulai dari model OrderDetail yang ber-scope tenant, ditambah filter eksplisit `orders.tenant_id` '
            . 'sebagai lapisan kedua isolasi. Bagian `summary` dihitung dari SELURUH baris hasil agregasi '
            . '(bukan hanya halaman yang diminta). '
            . 'Karena hasil query sudah dikelompokkan per menu (jumlah baris terbatas oleh jumlah menu), '
            . 'paginasinya dilakukan manual di aplikasi: seluruh baris agregasi diambil lalu dipotong per halaman. '
            . 'Kirim `all=true` untuk mendapatkan semua baris sekaligus. Semua angka berupa NUMBER mentah.',
        tags: ['Report'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'start_date', description: 'Tanggal awal (YYYY-MM-DD). Default: hari ini', in: 'query', required: false, schema: new OA\Schema(type: 'string', format: 'date', example: '2026-08-01')),
            new OA\Parameter(name: 'end_date', description: 'Tanggal akhir (YYYY-MM-DD). Default: hari ini', in: 'query', required: false, schema: new OA\Schema(type: 'string', format: 'date', example: '2026-08-19')),
            new OA\Parameter(name: 'category_id', description: 'Filter kategori menu. Gunakan `all` untuk semua kategori', in: 'query', required: false, schema: new OA\Schema(type: 'string', example: 'all')),
            new OA\Parameter(name: 'all', description: 'Bila true, seluruh baris agregasi dikembalikan tanpa paginasi', in: 'query', required: false, schema: new OA\Schema(type: 'boolean', example: false)),
            new OA\Parameter(name: 'per_page', description: 'Jumlah menu per halaman (maks 100)', in: 'query', required: false, schema: new OA\Schema(type: 'integer', example: 20)),
            new OA\Parameter(name: 'page', description: 'Halaman ke-', in: 'query', required: false, schema: new OA\Schema(type: 'integer', example: 1)),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Ringkasan + daftar menu terlaris', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'message', type: 'string', example: 'Laporan menu terlaris berhasil diambil.'),
                    new OA\Property(property: 'data', properties: [
                        new OA\Property(property: 'summary', properties: [
                            new OA\Property(property: 'total_items_sold', type: 'integer', example: 310),
                            new OA\Property(property: 'total_revenue', type: 'number', format: 'float', example: 5250000),
                            new OA\Property(property: 'total_hpp', type: 'number', format: 'float', example: 1980000),
                        ], type: 'object'),
                        new OA\Property(property: 'items', type: 'array', items: new OA\Items(properties: [
                            new OA\Property(property: 'menu_id', type: 'integer', example: 8),
                            new OA\Property(property: 'menu_name', type: 'string', example: 'Ayam Geprek'),
                            new OA\Property(property: 'category_name', type: 'string', example: 'Makanan'),
                            new OA\Property(property: 'discount_percent', type: 'number', format: 'float', example: 0),
                            new OA\Property(property: 'total_qty', type: 'integer', example: 47),
                            new OA\Property(property: 'total_revenue', type: 'number', format: 'float', example: 705000),
                            new OA\Property(property: 'total_hpp', type: 'number', format: 'float', example: 282000),
                        ], type: 'object')),
                        new OA\Property(property: 'meta', type: 'object'),
                    ], type: 'object'),
                ]
            )),
            new OA\Response(response: 403, description: 'Tidak punya izin view_report'),
        ]
    )]
    public function items(Request $request): JsonResponse
    {
        $start = $request->filled('start_date')
            ? Carbon::parse($request->query('start_date'))->toDateString()
            : now()->toDateString();

        $end = $request->filled('end_date')
            ? Carbon::parse($request->query('end_date'))->toDateString()
            : now()->toDateString();

        $categoryId = $request->query('category_id');

        // Query sudah ter-scope tenant karena dimulai dari OrderDetail (BelongsToTenant).
        // Filter orders.tenant_id di bawah adalah lapisan kedua (defense-in-depth) untuk join mentah.
        $tenantId = app('tenant')->id();

        $q = OrderDetail::join('orders', 'order_details.order_id', '=', 'orders.id')
            ->join('menus', 'order_details.menu_id', '=', 'menus.id')
            ->leftJoin('categories', 'menus.category_id', '=', 'categories.id')
            ->where('orders.payment_status', 'paid')
            ->when($tenantId, fn ($qq) => $qq->where('orders.tenant_id', $tenantId))
            ->whereBetween('orders.created_at', [$start . ' 00:00:00', $end . ' 23:59:59'])
            ->when($categoryId && $categoryId !== 'all', fn ($qq) => $qq->where('menus.category_id', $categoryId))
            ->select(
                'menus.id',
                'menus.name as menu_name',
                'menus.discount_percent',
                'categories.name as category_name',
                DB::raw('SUM(order_details.qty) as total_qty'),
                DB::raw('SUM(order_details.subtotal) as total_revenue'),
                DB::raw('SUM(order_details.hpp) as total_hpp')
            )
            ->groupBy('menus.id', 'menus.name', 'menus.discount_percent', 'categories.name')
            ->orderByDesc('total_qty');

        $rows = $q->get()->map(fn ($row) => [
            'menu_id' => $row->id,
            'menu_name' => $row->menu_name,
            'category_name' => $row->category_name ?? 'Tanpa Kategori',
            'discount_percent' => (float) $row->discount_percent,
            'total_qty' => (int) $row->total_qty,
            'total_revenue' => (float) $row->total_revenue,
            'total_hpp' => (float) $row->total_hpp,
        ])->values();

        $summary = [
            'total_items_sold' => (int) $rows->sum('total_qty'),
            'total_revenue' => (float) $rows->sum('total_revenue'),
            'total_hpp' => (float) $rows->sum('total_hpp'),
        ];

        $total = $rows->count();

        // Hasil sudah dikelompokkan per menu, jadi paginasinya dipotong manual dari koleksi.
        if ($request->boolean('all')) {
            $items = $rows;
            $perPage = $total > 0 ? $total : 1;
            $page = 1;
            $lastPage = 1;
        } else {
            $perPage = $this->perPage();
            $lastPage = (int) max(1, (int) ceil($total / $perPage));
            $page = (int) min(max(1, (int) $request->query('page', 1)), $lastPage);
            $items = $rows->slice(($page - 1) * $perPage, $perPage)->values();
        }

        return $this->ok([
            'summary' => $summary,
            'filters' => [
                'start_date' => $start,
                'end_date' => $end,
                'category_id' => ($categoryId === null || $categoryId === '') ? 'all' : $categoryId,
            ],
            'items' => $items,
            'meta' => [
                'current_page' => $page,
                'last_page' => $lastPage,
                'per_page' => $perPage,
                'total' => $total,
                'has_more' => $page < $lastPage,
            ],
        ], 'Laporan menu terlaris berhasil diambil.');
    }
}
