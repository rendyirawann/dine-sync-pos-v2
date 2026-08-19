<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Api\BaseApiController;
use App\Http\Resources\CategoryResource;
use App\Http\Resources\MenuResource;
use App\Http\Resources\OrderResource;
use App\Http\Resources\PromoResource;
use App\Http\Resources\SettingResource;
use App\Http\Resources\ShiftResource;
use App\Http\Resources\TableResource;
use App\Models\Category;
use App\Models\Menu;
use App\Models\Order;
use App\Models\Promo;
use App\Models\Setting;
use App\Models\Shift;
use App\Models\Table;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use OpenApi\Attributes as OA;

/**
 * Modul Kasir untuk aplikasi mobile.
 *
 * Logika bisnis direplikasi dari KasirController web (peta meja, buat order,
 * pembayaran tunai / pay later, kosongkan meja, dan data struk).
 */
class KasirController extends BaseApiController
{
    #[OA\Get(
        path: '/api/v1/kasir/tables',
        operationId: 'kasirTables',
        summary: 'Peta meja + ringkasan status',
        description: 'Menampilkan seluruh meja beserta status pembayaran runtime (unpaid/paid) seperti peta meja di web. '
            . 'Meja yang berstatus occupied namun tidak punya order aktif otomatis dikembalikan menjadi available (failsafe data kotor). '
            . 'Berbeda dengan web, endpoint ini TIDAK menolak akses saat kasir belum membuka shift — status shift aktif dikirim di field '
            . '`active_shift` supaya aplikasi mobile bisa menampilkan peringatannya sendiri.',
        tags: ['Kasir'],
        security: [['sanctum' => []]],
        responses: [
            new OA\Response(response: 200, description: 'Daftar meja, ringkasan jumlah, dan shift aktif kasir'),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 403, description: 'Tidak punya izin view_kasir'),
        ]
    )]
    public function tables(Request $request): JsonResponse
    {
        $tables = Table::orderBy('table_number', 'asc')->get();

        $emptyCount = 0;
        $unpaidCount = 0;
        $paidCount = 0;

        foreach ($tables as $table) {
            if ($table->status == 'available') {
                $emptyCount++;
            } elseif ($table->status == 'occupied') {
                // Ambil SEMUA order aktif di meja ini (satu meja bisa punya beberapa invoice).
                $activeOrders = Order::where('table_id', $table->id)
                    ->whereIn('order_status', ['pending', 'cooking', 'served'])
                    ->get();

                if ($activeOrders->isNotEmpty()) {
                    // Bila ada 1 saja invoice belum lunas, meja dianggap "BELUM BAYAR".
                    $hasUnpaid = $activeOrders->contains('payment_status', 'unpaid');

                    // Atribut runtime (bukan kolom DB), dibaca oleh TableResource.
                    $table->payment_status = $hasUnpaid ? 'unpaid' : 'paid';

                    if ($hasUnpaid) {
                        $unpaidCount++;
                    } else {
                        $paidCount++;
                    }
                } else {
                    // Failsafe: meja terisi tapi ordernya sudah selesai semua.
                    $table->update(['status' => 'available']);
                    $emptyCount++;
                }
            }
        }

        $activeShift = Shift::where('user_id', auth()->id())->where('status', 'open')->first();

        return $this->ok([
            'tables' => TableResource::collection($tables),
            'summary' => [
                'empty' => $emptyCount,
                'unpaid' => $unpaidCount,
                'paid' => $paidCount,
                'total' => $tables->count(),
            ],
            'active_shift' => $activeShift ? new ShiftResource($activeShift) : null,
        ], 'Peta meja berhasil diambil.');
    }

    #[OA\Get(
        path: '/api/v1/kasir/tables/{id}/detail',
        operationId: 'kasirTableDetail',
        summary: 'Detail meja beserta semua invoice aktif',
        description: 'Menampilkan detail satu meja. Bila meja kosong hanya data meja yang dikembalikan. '
            . 'Bila terisi, seluruh invoice aktif (pending/cooking/served) dikembalikan lengkap dengan itemnya, terbaru di atas.',
        tags: ['Kasir'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', description: 'ID meja', in: 'path', required: true, schema: new OA\Schema(type: 'integer', example: 1)),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Detail meja (status available atau occupied)'),
            new OA\Response(response: 404, description: 'Meja tidak ditemukan'),
        ]
    )]
    public function tableDetail($id): JsonResponse
    {
        $table = Table::findOrFail($id);

        if ($table->status == 'available') {
            return $this->ok([
                'status' => 'available',
                'table' => new TableResource($table),
            ], 'Meja ini kosong dan siap digunakan.');
        }

        $orders = Order::with('details.menu', 'promo', 'table')
            ->where('table_id', $id)
            ->whereIn('order_status', ['pending', 'cooking', 'served'])
            ->orderBy('created_at', 'desc')
            ->get();

        if ($orders->isEmpty()) {
            // Failsafe sama seperti web: data kotor dibersihkan.
            $table->update(['status' => 'available']);

            return $this->ok([
                'status' => 'available',
                'table' => new TableResource($table),
            ], 'Meja ini kosong dan siap digunakan.');
        }

        return $this->ok([
            'status' => 'occupied',
            'table' => new TableResource($table),
            'orders' => OrderResource::collection($orders),
        ], 'Detail meja berhasil diambil.');
    }

    #[OA\Get(
        path: '/api/v1/kasir/order-context/{table_id}',
        operationId: 'kasirOrderContext',
        summary: 'Data pendukung layar buat pesanan',
        description: 'Sekali panggil untuk mendapatkan semua data yang dibutuhkan layar kasir saat membuat pesanan: '
            . 'meja, kategori, menu tersedia, promo aktif, pengaturan toko (pajak), dan pilihan tipe pesanan. '
            . 'Bila meja sudah terisi maka permintaan ditolak (409).',
        tags: ['Kasir'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'table_id', description: 'ID meja yang akan dipakai', in: 'path', required: true, schema: new OA\Schema(type: 'integer', example: 1)),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Data konteks pesanan'),
            new OA\Response(response: 404, description: 'Meja tidak ditemukan'),
            new OA\Response(response: 409, description: 'Meja sudah terisi'),
        ]
    )]
    public function orderContext($table_id): JsonResponse
    {
        $table = Table::findOrFail($table_id);

        if ($table->status == 'occupied') {
            return $this->fail('Meja sudah terisi! Tidak bisa membuat pesanan baru.', 409);
        }

        return $this->ok([
            'table' => new TableResource($table),
            'categories' => CategoryResource::collection(Category::orderBy('name', 'asc')->get()),
            'menus' => MenuResource::collection(Menu::with('category')->where('is_available', true)->get()),
            'promos' => PromoResource::collection(Promo::where('is_active', true)->get()),
            'setting' => new SettingResource(Setting::forCurrentTenant()),
            'order_types' => [
                ['value' => 'dine_in', 'label' => 'Dine In (Makan di Tempat)'],
                ['value' => 'take_away', 'label' => 'Take Away (Bawa Pulang)'],
                ['value' => 'reservation', 'label' => 'Reservasi (Booking)'],
            ],
        ], 'Data pesanan berhasil diambil.');
    }

    #[OA\Post(
        path: '/api/v1/kasir/orders',
        operationId: 'kasirStoreOrder',
        summary: 'Buat pesanan baru (tunai atau bayar nanti)',
        description: 'Menyimpan pesanan baru. Harga dihitung ULANG di server (harga menu + diskon menu), '
            . 'lalu promo dipotong dari subtotal dan pajak dihitung SETELAH diskon. '
            . 'Meja otomatis menjadi occupied. Bila `payment_method` = cash maka pesanan langsung dilunasi dan kembalian dihitung; '
            . 'bila `pay_later` maka pesanan dikirim ke dapur dengan status belum bayar.',
        tags: ['Kasir'],
        security: [['sanctum' => []]],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['table_id', 'customer_name', 'payment_method', 'cart'],
                properties: [
                    new OA\Property(property: 'table_id', type: 'integer', example: 1, description: 'ID meja'),
                    new OA\Property(property: 'customer_name', type: 'string', example: 'Budi', description: 'Nama pelanggan'),
                    new OA\Property(property: 'order_type', type: 'string', enum: ['dine_in', 'take_away', 'reservation'], example: 'dine_in'),
                    new OA\Property(property: 'payment_method', type: 'string', enum: ['pay_later', 'cash'], example: 'cash'),
                    new OA\Property(property: 'promo_id', type: 'integer', example: 2, nullable: true, description: 'ID promo (opsional)'),
                    new OA\Property(property: 'cash_received', type: 'number', format: 'float', example: 100000, nullable: true, description: 'Uang diterima (khusus tunai)'),
                    new OA\Property(
                        property: 'cart',
                        type: 'array',
                        description: 'Isi keranjang, minimal 1 item',
                        items: new OA\Items(
                            required: ['id', 'qty'],
                            properties: [
                                new OA\Property(property: 'id', type: 'integer', example: 5, description: 'ID menu'),
                                new OA\Property(property: 'qty', type: 'integer', example: 2, description: 'Jumlah porsi'),
                                new OA\Property(property: 'note', type: 'string', example: 'Tidak pakai sambal', nullable: true),
                            ],
                            type: 'object'
                        )
                    ),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 201, description: 'Pesanan berhasil dibuat'),
            new OA\Response(response: 422, description: 'Data tidak valid / nominal uang tidak cukup'),
        ]
    )]
    public function storeOrder(Request $request): JsonResponse
    {
        $request->validate([
            'table_id' => 'required|exists:tables,id',
            'customer_name' => 'required|string|max:255',
            'order_type' => 'nullable|in:dine_in,take_away,reservation',
            'payment_method' => 'required|in:pay_later,cash',
            'promo_id' => 'nullable|exists:promos,id',
            'cart' => 'required|array|min:1',
            'cart.*.id' => 'required|exists:menus,id',
            'cart.*.qty' => 'required|integer|min:1',
            'cart.*.note' => 'nullable|string|max:255',
            'cash_received' => 'nullable|numeric|min:0',
        ], [
            'table_id.required' => 'Meja wajib dipilih.',
            'table_id.exists' => 'Meja tidak ditemukan.',
            'customer_name.required' => 'Nama pelanggan wajib diisi.',
            'customer_name.max' => 'Nama pelanggan maksimal 255 karakter.',
            'order_type.in' => 'Tipe pesanan tidak valid.',
            'payment_method.required' => 'Metode pembayaran wajib dipilih.',
            'payment_method.in' => 'Metode pembayaran hanya boleh pay_later atau cash.',
            'promo_id.exists' => 'Promo tidak ditemukan.',
            'cart.required' => 'Keranjang pesanan masih kosong.',
            'cart.array' => 'Format keranjang pesanan tidak valid.',
            'cart.min' => 'Minimal 1 menu harus dipesan.',
            'cart.*.id.required' => 'ID menu wajib diisi.',
            'cart.*.id.exists' => 'Salah satu menu tidak ditemukan.',
            'cart.*.qty.required' => 'Jumlah porsi wajib diisi.',
            'cart.*.qty.integer' => 'Jumlah porsi harus berupa angka.',
            'cart.*.qty.min' => 'Jumlah porsi minimal 1.',
            'cart.*.note.max' => 'Catatan menu maksimal 255 karakter.',
            'cash_received.numeric' => 'Nominal uang harus berupa angka.',
            'cash_received.min' => 'Nominal uang tidak boleh minus.',
        ]);

        // ---- Hitung harga di SERVER (jangan percaya harga dari klien) ----
        $subtotal = 0;
        $items = [];

        foreach ($request->cart as $row) {
            $menu = Menu::findOrFail($row['id']);

            $price = (float) $menu->price;
            if ($menu->discount_percent > 0) {
                // Harga per item setelah diskon menu.
                $price = $price - ($price * ($menu->discount_percent / 100));
            }

            $lineSub = $price * (int) $row['qty'];
            $subtotal += $lineSub;

            $items[] = [
                'menu_id' => $menu->id,
                'qty' => (int) $row['qty'],
                'price' => $price,
                'subtotal' => $lineSub,
                'notes' => $row['note'] ?? null,
                'status' => 'pending',
            ];
        }

        // ---- Diskon promo ----
        $discount_amount = 0;
        if ($request->promo_id) {
            $promo = Promo::find($request->promo_id);
            if ($promo && $promo->is_active) {
                $discount_amount = $promo->discount_type == 'percentage'
                    ? round($subtotal * ($promo->discount_value / 100))
                    : $promo->discount_value;
            }
        }

        $net_subtotal = max(0, $subtotal - $discount_amount);

        // ---- Pajak dihitung SETELAH diskon ----
        $setting = Setting::forCurrentTenant();
        $tax_rate = $setting ? $setting->tax_rate : 0;
        $tax = round($net_subtotal * ($tax_rate / 100));
        $grand_total = $net_subtotal + $tax;

        $isCash = $request->payment_method == 'cash';
        $cashSent = $request->filled('cash_received');

        if ($isCash && $cashSent && (float) $request->cash_received < $grand_total) {
            return $this->fail('Nominal uang tidak cukup.', 422);
        }

        $invoice_no = 'DSV2-INV-' . date('YmdHis') . rand(10, 99);

        $order = DB::transaction(function () use ($request, $items, $subtotal, $discount_amount, $tax, $grand_total, $invoice_no, $isCash) {
            $order = Order::create([
                'invoice_no' => $invoice_no,
                'table_id' => $request->table_id,
                'promo_id' => $request->promo_id,
                'customer_name' => $request->customer_name,
                'order_type' => $request->order_type ?? 'dine_in',
                'subtotal' => $subtotal,
                'discount_amount' => $discount_amount,
                'tax' => $tax,
                'grand_total' => $grand_total,
                'payment_method' => $request->payment_method == 'pay_later' ? null : $request->payment_method,
                'payment_status' => 'unpaid',
                'order_status' => 'pending',
            ]);

            foreach ($items as $item) {
                $order->details()->create($item);
            }

            Table::where('id', $request->table_id)->update(['status' => 'occupied']);

            if ($isCash) {
                $order->update(['payment_status' => 'paid']);
            }

            return $order;
        });

        $change = ($isCash && $cashSent) ? max(0, (float) $request->cash_received - $grand_total) : 0;

        $order->load('details.menu', 'table', 'promo');

        return $this->created([
            'order' => new OrderResource($order),
            'type' => $isCash ? 'cash' : 'pay_later',
            'change' => (float) $change,
        ], $isCash
            ? 'Pembayaran tunai berhasil!'
            : 'Pesanan dikirim ke dapur. Pembayaran ditangguhkan (Pay Later).');
    }

    #[OA\Post(
        path: '/api/v1/kasir/orders/{id}/pay',
        operationId: 'kasirPayOrder',
        summary: 'Bayar pesanan yang belum lunas',
        description: 'Melunasi pesanan berstatus belum bayar (hasil Pay Later) secara tunai. '
            . 'Bila pesanan sudah lunas maka ditolak (409); bila uang yang diterima kurang dari total maka ditolak (422).',
        tags: ['Kasir'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', description: 'ID pesanan', in: 'path', required: true, schema: new OA\Schema(type: 'integer', example: 12)),
        ],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['payment_method'],
                properties: [
                    new OA\Property(property: 'payment_method', type: 'string', enum: ['cash'], example: 'cash'),
                    new OA\Property(property: 'cash_received', type: 'number', format: 'float', example: 50000, nullable: true, description: 'Uang diterima dari pelanggan'),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 200, description: 'Pembayaran berhasil'),
            new OA\Response(response: 404, description: 'Pesanan tidak ditemukan'),
            new OA\Response(response: 409, description: 'Pesanan sudah lunas'),
            new OA\Response(response: 422, description: 'Data tidak valid / nominal uang tidak cukup'),
        ]
    )]
    public function payOrder(Request $request, $id): JsonResponse
    {
        $request->validate([
            'payment_method' => 'required|in:cash',
            'cash_received' => 'nullable|numeric|min:0',
        ], [
            'payment_method.required' => 'Metode pembayaran wajib dipilih.',
            'payment_method.in' => 'Saat ini pembayaran hanya melayani tunai (cash).',
            'cash_received.numeric' => 'Nominal uang harus berupa angka.',
            'cash_received.min' => 'Nominal uang tidak boleh minus.',
        ]);

        $order = Order::findOrFail($id);

        if ($order->payment_status == 'paid') {
            return $this->fail('Pesanan ini sudah lunas.', 409);
        }

        $grandTotal = (float) $order->grand_total;
        $cashSent = $request->filled('cash_received');

        if ($cashSent && (float) $request->cash_received < $grandTotal) {
            return $this->fail('Nominal uang tidak cukup.', 422);
        }

        DB::transaction(function () use ($order, $request) {
            $order->update([
                'payment_method' => $request->payment_method,
                'payment_status' => 'paid',
            ]);
        });

        $change = $cashSent ? max(0, (float) $request->cash_received - $grandTotal) : 0;

        $order->load('details.menu', 'table', 'promo');

        return $this->ok([
            'order' => new OrderResource($order),
            'type' => 'cash',
            'change' => (float) $change,
        ], 'Pembayaran tunai lunas!');
    }

    #[OA\Post(
        path: '/api/v1/kasir/tables/{id}/clear',
        operationId: 'kasirClearTable',
        summary: 'Kosongkan meja',
        description: 'Menutup semua invoice aktif di meja (menjadi completed) lalu mengembalikan meja ke status available. '
            . 'Gagal (400) bila masih ada item pesanan yang belum diselesaikan oleh koki.',
        tags: ['Kasir'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', description: 'ID meja', in: 'path', required: true, schema: new OA\Schema(type: 'integer', example: 1)),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Meja berhasil dikosongkan'),
            new OA\Response(response: 400, description: 'Masih ada pesanan yang belum diselesaikan koki'),
            new OA\Response(response: 404, description: 'Meja tidak ditemukan'),
        ]
    )]
    public function clearTable($id): JsonResponse
    {
        return DB::transaction(function () use ($id) {
            $table = Table::findOrFail($id);

            $activeOrders = Order::where('table_id', $id)
                ->whereIn('order_status', ['pending', 'cooking', 'served'])
                ->get();

            if ($activeOrders->isNotEmpty()) {
                $unfinished = 0;
                foreach ($activeOrders as $order) {
                    $unfinished += $order->details()->whereIn('status', ['pending', 'cooking'])->count();
                }

                if ($unfinished > 0) {
                    return $this->fail('Tidak bisa mengosongkan meja! Masih ada ' . $unfinished . ' pesanan yang belum diselesaikan oleh Koki.', 400);
                }

                foreach ($activeOrders as $order) {
                    $order->update(['order_status' => 'completed']);
                }
            }

            $table->update(['status' => 'available']);

            return $this->ok([
                'table' => new TableResource($table),
            ], 'Meja berhasil dikosongkan dan siap digunakan kembali!');
        });
    }

    #[OA\Get(
        path: '/api/v1/kasir/orders',
        operationId: 'kasirOrders',
        summary: 'Riwayat pesanan (berpaginasi)',
        description: 'Daftar pesanan terbaru untuk layar riwayat di mobile. Mendukung filter tanggal, status bayar, status pesanan, '
            . 'dan pencarian berdasarkan nomor invoice atau nama pelanggan.',
        tags: ['Kasir'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'date_from', description: 'Tanggal awal (YYYY-MM-DD)', in: 'query', required: false, schema: new OA\Schema(type: 'string', format: 'date', example: '2026-08-01')),
            new OA\Parameter(name: 'date_to', description: 'Tanggal akhir (YYYY-MM-DD)', in: 'query', required: false, schema: new OA\Schema(type: 'string', format: 'date', example: '2026-08-19')),
            new OA\Parameter(name: 'payment_status', description: 'Filter status pembayaran', in: 'query', required: false, schema: new OA\Schema(type: 'string', enum: ['unpaid', 'paid', 'failed'])),
            new OA\Parameter(name: 'order_status', description: 'Filter status pesanan', in: 'query', required: false, schema: new OA\Schema(type: 'string', enum: ['pending', 'cooking', 'served', 'completed'])),
            new OA\Parameter(name: 'search', description: 'Cari nomor invoice atau nama pelanggan', in: 'query', required: false, schema: new OA\Schema(type: 'string', example: 'DSV2-INV')),
            new OA\Parameter(name: 'per_page', description: 'Jumlah data per halaman (maks 100)', in: 'query', required: false, schema: new OA\Schema(type: 'integer', example: 20)),
            new OA\Parameter(name: 'page', description: 'Halaman ke-', in: 'query', required: false, schema: new OA\Schema(type: 'integer', example: 1)),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Daftar pesanan berpaginasi (data + meta)'),
        ]
    )]
    public function orders(Request $request): JsonResponse
    {
        $query = Order::with('table', 'promo', 'details.menu');

        if ($request->filled('date_from') && $request->filled('date_to')) {
            $query->whereBetween('created_at', [
                Carbon::parse($request->date_from)->startOfDay(),
                Carbon::parse($request->date_to)->endOfDay(),
            ]);
        } elseif ($request->filled('date_from')) {
            $query->where('created_at', '>=', Carbon::parse($request->date_from)->startOfDay());
        } elseif ($request->filled('date_to')) {
            $query->where('created_at', '<=', Carbon::parse($request->date_to)->endOfDay());
        }

        if ($request->filled('payment_status')) {
            $query->where('payment_status', $request->payment_status);
        }

        if ($request->filled('order_status')) {
            $query->where('order_status', $request->order_status);
        }

        if ($request->filled('search')) {
            $keyword = '%' . $request->search . '%';
            $query->where(function ($q) use ($keyword) {
                $q->where('invoice_no', 'like', $keyword)
                    ->orWhere('customer_name', 'like', $keyword);
            });
        }

        $paginator = $query->latest()->paginate($this->perPage());

        return $this->paginated(
            $paginator->through(fn ($order) => new OrderResource($order)),
            'Riwayat pesanan berhasil diambil.'
        );
    }

    #[OA\Get(
        path: '/api/v1/kasir/orders/{id}',
        operationId: 'kasirShowOrder',
        summary: 'Detail satu pesanan',
        description: 'Menampilkan satu pesanan lengkap dengan item, meja, dan promo yang dipakai.',
        tags: ['Kasir'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', description: 'ID pesanan', in: 'path', required: true, schema: new OA\Schema(type: 'integer', example: 12)),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Detail pesanan'),
            new OA\Response(response: 404, description: 'Pesanan tidak ditemukan'),
        ]
    )]
    public function showOrder($id): JsonResponse
    {
        $order = Order::with('details.menu', 'table', 'promo')->findOrFail($id);

        return $this->ok(new OrderResource($order), 'Detail pesanan berhasil diambil.');
    }

    #[OA\Get(
        path: '/api/v1/kasir/orders/{id}/receipt',
        operationId: 'kasirReceipt',
        summary: 'Data struk untuk dicetak',
        description: 'Mengembalikan data yang dibutuhkan aplikasi mobile untuk mencetak struk ke printer bluetooth: '
            . 'pesanan + itemnya, identitas toko, waktu cetak, dan nama kasir yang mencetak.',
        tags: ['Kasir'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', description: 'ID pesanan', in: 'path', required: true, schema: new OA\Schema(type: 'integer', example: 12)),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Data struk'),
            new OA\Response(response: 404, description: 'Pesanan tidak ditemukan'),
        ]
    )]
    public function receipt($id): JsonResponse
    {
        $order = Order::with('details.menu', 'table')->findOrFail($id);
        $setting = Setting::forCurrentTenant();

        return $this->ok([
            'order' => new OrderResource($order),
            'setting' => new SettingResource($setting),
            'printed_at' => now()->toIso8601String(),
            'cashier_name' => auth()->user()->name,
        ], 'Data struk berhasil diambil.');
    }
}
