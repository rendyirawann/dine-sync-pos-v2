<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Api\BaseApiController;
use App\Http\Resources\CategoryResource;
use App\Http\Resources\MenuResource;
use App\Http\Resources\OrderResource;
use App\Http\Resources\PromoResource;
use App\Http\Resources\SettingResource;
use App\Http\Resources\TableResource;
use App\Models\Category;
use App\Models\Menu;
use App\Models\Order;
use App\Models\Promo;
use App\Models\Setting;
use App\Models\Table;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use OpenApi\Attributes as OA;

/**
 * Self-order pelanggan (replika CustomerOrderController web) — SEMUA endpoint publik.
 *
 * Tenant aktif ditentukan middleware IdentifyTenant:
 * - dari `{tenant}` (slug/id) untuk halaman kiosk/toko, atau
 * - dari `{uuid}` meja/order untuk alur scan QR -> menu -> checkout -> lacak status.
 */
class CustomerController extends BaseApiController
{
    #[OA\Get(
        path: '/api/v1/public/{tenant}/store',
        operationId: 'publicStoreInfo',
        summary: 'Info toko UMKM (publik)',
        description: 'Identitas toko untuk header halaman kiosk / landing scan QR: nama toko, alamat, telepon, dan persentase pajak yang berlaku. `{tenant}` berupa slug atau id UMKM.',
        tags: ['Publik'],
        parameters: [
            new OA\Parameter(name: 'tenant', in: 'path', required: true, description: 'Slug atau ID UMKM', schema: new OA\Schema(type: 'string')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Info toko', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'data', properties: [
                        new OA\Property(property: 'store_name', type: 'string', example: 'Warung Bu Ani'),
                        new OA\Property(property: 'address', type: 'string', nullable: true, example: 'Jl. Merdeka No. 10'),
                        new OA\Property(property: 'phone', type: 'string', nullable: true, example: '08123456789'),
                        new OA\Property(property: 'tax_rate', type: 'integer', example: 10),
                    ], type: 'object'),
                ]
            )),
            new OA\Response(response: 404, description: 'UMKM tidak ditemukan'),
        ]
    )]
    public function store($tenant): JsonResponse
    {
        if (! app('tenant')->id()) {
            return $this->fail('UMKM tidak ditemukan.', 404);
        }

        $setting = Setting::forCurrentTenant();

        return $this->ok([
            'store_name' => $setting->store_name ?? 'DineSync POS',
            'address' => $setting->address,
            'phone' => $setting->phone,
            'tax_rate' => (int) $setting->tax_rate,
        ], 'Info toko berhasil dimuat.');
    }

    #[OA\Get(
        path: '/api/v1/public/scan/{uuid}',
        operationId: 'publicScanTable',
        summary: 'Landing scan QR meja (publik)',
        description: <<<'TXT'
Dipakai saat pelanggan **memindai QR code di meja**. Mengembalikan data meja dan
identitas toko untuk halaman "masukkan nama" sebelum masuk ke daftar menu.

`is_occupied` = `true` bila meja sedang terisi (masih ada pesanan aktif yang belum
dibereskan kasir); klien bisa menampilkan peringatan atau melanjutkan sebagai
tamu yang sama, meniru perilaku halaman scan di web.
TXT,
        tags: ['Publik'],
        parameters: [
            new OA\Parameter(name: 'uuid', in: 'path', required: true, description: 'UUID meja dari QR code', schema: new OA\Schema(type: 'string')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Data meja & toko', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'data', properties: [
                        new OA\Property(property: 'table', type: 'object'),
                        new OA\Property(property: 'setting', type: 'object'),
                        new OA\Property(property: 'is_occupied', type: 'boolean', example: false),
                    ], type: 'object'),
                ]
            )),
            new OA\Response(response: 404, description: 'Meja tidak ditemukan'),
        ]
    )]
    public function scan($uuid): JsonResponse
    {
        $table = Table::where('uuid', $uuid)->firstOrFail();

        return $this->ok([
            'table' => new TableResource($table),
            'setting' => new SettingResource(Setting::forCurrentTenant()),
            'is_occupied' => $table->status == 'occupied',
        ], 'Data meja berhasil dimuat.');
    }

    #[OA\Get(
        path: '/api/v1/public/menu/{uuid}',
        operationId: 'publicMenuList',
        summary: 'Katalog menu untuk self-order (publik)',
        description: <<<'TXT'
Seluruh data yang dibutuhkan halaman self-order pelanggan:

- `categories`: kategori diurut nama A-Z (untuk tab filter).
- `menus`: hanya menu yang `is_available = true`, lengkap dengan `final_price`
  (harga setelah diskon per menu) yang WAJIB dipakai sebagai harga tampilan.
- `promos`: promo yang masih aktif (informatif — checkout self-order belum memakai promo).
- `setting`: nama toko & `tax_rate` untuk pratinjau total.
- `active_orders`: pesanan meja ini yang masih berjalan (`pending`, `cooking`, `served`),
  terbaru di atas — dipakai untuk menampilkan riwayat pesanan berjalan & status dapur.
TXT,
        tags: ['Publik'],
        parameters: [
            new OA\Parameter(name: 'uuid', in: 'path', required: true, description: 'UUID meja dari QR code', schema: new OA\Schema(type: 'string')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Katalog menu', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'data', properties: [
                        new OA\Property(property: 'table', type: 'object'),
                        new OA\Property(property: 'setting', type: 'object'),
                        new OA\Property(property: 'categories', type: 'array', items: new OA\Items(type: 'object')),
                        new OA\Property(property: 'menus', type: 'array', items: new OA\Items(type: 'object')),
                        new OA\Property(property: 'promos', type: 'array', items: new OA\Items(type: 'object')),
                        new OA\Property(property: 'active_orders', type: 'array', items: new OA\Items(type: 'object')),
                    ], type: 'object'),
                ]
            )),
            new OA\Response(response: 404, description: 'Meja tidak ditemukan'),
        ]
    )]
    public function menu($uuid): JsonResponse
    {
        $table = Table::where('uuid', $uuid)->firstOrFail();

        $categories = Category::orderBy('name', 'asc')->get();
        $menus = Menu::with('category')->where('is_available', true)->get();
        $promos = Promo::where('is_active', true)->get();
        $setting = Setting::forCurrentTenant();

        $activeOrders = Order::with('details.menu')
            ->where('table_id', $table->id)
            ->whereIn('order_status', ['pending', 'cooking', 'served'])
            ->orderBy('created_at', 'desc')
            ->get();

        return $this->ok([
            'table' => new TableResource($table),
            'setting' => new SettingResource($setting),
            'categories' => CategoryResource::collection($categories),
            'menus' => MenuResource::collection($menus),
            'promos' => PromoResource::collection($promos),
            'active_orders' => OrderResource::collection($activeOrders),
        ], 'Katalog menu berhasil dimuat.');
    }

    #[OA\Post(
        path: '/api/v1/public/menu/{uuid}/checkout',
        operationId: 'publicMenuCheckout',
        summary: 'Kirim pesanan self-order ke dapur (publik)',
        description: <<<'TXT'
Pelanggan mengirim keranjang belanjanya langsung ke dapur — **tanpa login**.

Harga **dihitung ulang di server** (anti-manipulasi): harga tiap item diambil dari
database beserta diskon per menu (`discount_percent`), pajak memakai `tax_rate` dari
setting toko dan dibulatkan dengan `round()`. Promo belum dipakai pada alur self-order
sehingga `discount_amount` selalu 0 — harga yang dikirim klien diabaikan.

Pesanan dibuat dengan `payment_method = null` (bayar di kasir), `payment_status = unpaid`,
`order_status = pending` (langsung tampil di layar dapur), `order_type = dine_in`,
dan meja otomatis ditandai `occupied`.
TXT,
        tags: ['Publik'],
        parameters: [
            new OA\Parameter(name: 'uuid', in: 'path', required: true, description: 'UUID meja dari QR code', schema: new OA\Schema(type: 'string')),
        ],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['customer_name', 'cart'],
                properties: [
                    new OA\Property(property: 'customer_name', type: 'string', maxLength: 255, example: 'Budi'),
                    new OA\Property(property: 'cart', type: 'array', minItems: 1, items: new OA\Items(
                        required: ['id', 'qty'],
                        properties: [
                            new OA\Property(property: 'id', type: 'integer', example: 12, description: 'ID menu'),
                            new OA\Property(property: 'qty', type: 'integer', minimum: 1, example: 2),
                            new OA\Property(property: 'note', type: 'string', nullable: true, maxLength: 255, example: 'Tidak pakai sambal'),
                        ],
                        type: 'object'
                    )),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 201, description: 'Pesanan berhasil dibuat', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'message', type: 'string', example: 'Pesanan berhasil dikirim ke dapur. Silakan bayar di kasir.'),
                    new OA\Property(property: 'data', properties: [
                        new OA\Property(property: 'order', type: 'object'),
                    ], type: 'object'),
                ]
            )),
            new OA\Response(response: 404, description: 'Meja tidak ditemukan'),
            new OA\Response(response: 422, description: 'Validasi gagal / menu tidak tersedia'),
        ]
    )]
    public function checkout(Request $request, $uuid): JsonResponse
    {
        $data = $request->validate([
            'customer_name' => 'required|string|max:255',
            'cart' => 'required|array|min:1',
            'cart.*.id' => 'required|exists:menus,id',
            'cart.*.qty' => 'required|integer|min:1',
            'cart.*.note' => 'nullable|string|max:255',
        ], [
            'customer_name.required' => 'Nama pelanggan wajib diisi.',
            'customer_name.max' => 'Nama pelanggan maksimal 255 karakter.',
            'cart.required' => 'Keranjang kosong! Pilih menu terlebih dahulu.',
            'cart.min' => 'Keranjang kosong! Pilih menu terlebih dahulu.',
            'cart.*.id.required' => 'Menu pada keranjang tidak valid.',
            'cart.*.id.exists' => 'Ada menu di keranjang yang sudah tidak tersedia.',
            'cart.*.qty.required' => 'Jumlah pesanan wajib diisi.',
            'cart.*.qty.integer' => 'Jumlah pesanan harus berupa angka.',
            'cart.*.qty.min' => 'Jumlah pesanan minimal 1.',
            'cart.*.note.max' => 'Catatan maksimal 255 karakter.',
        ]);

        $table = Table::where('uuid', $uuid)->firstOrFail();

        // Harga diambil ulang dari database (anti-manipulasi harga dari sisi klien).
        $menus = Menu::whereIn('id', collect($data['cart'])->pluck('id')->all())->get()->keyBy('id');

        $subtotal = 0;
        $lines = [];

        foreach ($data['cart'] as $item) {
            $menu = $menus->get($item['id']);

            if (! $menu) {
                return $this->fail('Ada menu di keranjang yang sudah tidak tersedia.', 422);
            }

            $price = (float) $menu->price;
            $discountPercent = (int) ($menu->discount_percent ?? 0);
            // Diskon per menu, sama seperti perhitungan harga di kasir & halaman menu web.
            $finalPrice = $discountPercent > 0 ? $price - ($price * ($discountPercent / 100)) : $price;

            $qty = (int) $item['qty'];
            $lineSubtotal = $finalPrice * $qty;
            $subtotal += $lineSubtotal;

            $lines[] = [
                'menu_id' => $menu->id,
                'qty' => $qty,
                'price' => $finalPrice,
                'subtotal' => $lineSubtotal,
                'notes' => $item['note'] ?? null,
                'status' => 'pending',
            ];
        }

        // Self-order belum memakai promo: diskon order selalu 0.
        $discountAmount = 0;
        $netSubtotal = $subtotal - $discountAmount;
        if ($netSubtotal < 0) {
            $netSubtotal = 0;
        }

        $setting = Setting::forCurrentTenant();
        $taxRate = $setting->tax_rate ?? 0;
        $tax = round($netSubtotal * ($taxRate / 100));
        $grandTotal = $netSubtotal + $tax;

        $order = DB::transaction(function () use ($data, $table, $lines, $subtotal, $discountAmount, $tax, $grandTotal) {
            $order = Order::create([
                'invoice_no' => 'DSV2-INV-' . date('YmdHis') . rand(10, 99),
                'table_id' => $table->id,
                'promo_id' => null,
                'customer_name' => $data['customer_name'],
                'order_type' => 'dine_in',
                'subtotal' => $subtotal,
                'discount_amount' => $discountAmount,
                'tax' => $tax,
                'grand_total' => $grandTotal,
                'payment_method' => null,   // bayar di kasir (pay_later)
                'payment_status' => 'unpaid',
                'order_status' => 'pending', // langsung masuk layar dapur
            ]);

            foreach ($lines as $line) {
                $order->details()->create($line);
            }

            // Meja jadi terisi di peta kasir.
            $table->update(['status' => 'occupied']);

            return $order;
        });

        return $this->created([
            'order' => new OrderResource($order->load('details.menu', 'table')),
        ], 'Pesanan berhasil dikirim ke dapur. Silakan bayar di kasir.');
    }

    #[OA\Get(
        path: '/api/v1/public/order/{uuid}',
        operationId: 'publicOrderStatus',
        summary: 'Lacak status pesanan pelanggan (publik)',
        description: <<<'TXT'
Halaman "pesanan diterima" sekaligus pelacak status dapur untuk pelanggan.

`{uuid}` adalah `uuid` order yang dikembalikan endpoint checkout. Response memuat
rincian pesanan beserta status per item (`pending` = Antre, `cooking` = Dimasak,
`done` = Siap) dan status order (`pending`, `cooking`, `served`, `completed`),
sehingga klien dapat melakukan polling untuk memperbarui progres masakan.
TXT,
        tags: ['Publik'],
        parameters: [
            new OA\Parameter(name: 'uuid', in: 'path', required: true, description: 'UUID order (dari response checkout)', schema: new OA\Schema(type: 'string')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Detail & status pesanan'),
            new OA\Response(response: 404, description: 'Pesanan tidak ditemukan'),
        ]
    )]
    public function orderStatus($uuid): JsonResponse
    {
        $order = Order::with('details.menu', 'table')->where('uuid', $uuid)->firstOrFail();

        return $this->ok(new OrderResource($order), 'Status pesanan berhasil dimuat.');
    }
}
