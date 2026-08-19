<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Api\BaseApiController;
use Illuminate\Http\JsonResponse;
use OpenApi\Attributes as OA;

/**
 * Kumpulan konstanta (enum) + konfigurasi realtime untuk aplikasi Flutter.
 * Tujuannya supaya label, warna badge, dan pilihan dropdown TIDAK di-hardcode di klien:
 * cukup panggil endpoint ini sekali saat aplikasi dibuka lalu simpan di cache lokal.
 */
class MetaController extends BaseApiController
{
    #[OA\Get(
        path: '/api/v1/meta',
        operationId: 'metaIndex',
        summary: 'Konstanta aplikasi (enum, label, warna, realtime)',
        description: <<<'TXT'
Mengembalikan seluruh konstanta yang dipakai aplikasi mobile:

- **Pilihan dropdown**: jenis order, metode bayar, satuan bahan, jenis promo, kategori antrian.
- **Label & warna badge**: status bayar, status order, status item dapur, status meja, status antrian, status shift.
- **Format mata uang**: kode, simbol, dan pemisah ribuan/desimal untuk Rupiah.
- **Konfigurasi realtime**: kredensial publik Reverb dan nama channel milik tenant aktif
  (channel antrian dan channel layar display).
- **Info aplikasi**: nama aplikasi dan versi API.

Catatan: metode pembayaran Midtrans dinonaktifkan pada versi trial, jadi hanya
`pay_later` (bayar nanti) dan `cash` (tunai) yang dikembalikan.

Panggil sekali saat aplikasi start; datanya statis kecuali konfigurasi realtime berubah.
TXT,
        tags: ['Setting'],
        security: [['sanctum' => []]],
        responses: [
            new OA\Response(response: 200, description: 'Daftar konstanta', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'message', type: 'string', example: 'Konstanta aplikasi berhasil dimuat.'),
                    new OA\Property(property: 'data', properties: [
                        new OA\Property(property: 'order_types', type: 'array', items: new OA\Items(properties: [
                            new OA\Property(property: 'value', type: 'string', example: 'dine_in'),
                            new OA\Property(property: 'label', type: 'string', example: 'Dine In (Makan di Tempat)'),
                        ], type: 'object')),
                        new OA\Property(property: 'payment_methods', type: 'array', items: new OA\Items(type: 'object')),
                        new OA\Property(property: 'payment_statuses', type: 'array', items: new OA\Items(properties: [
                            new OA\Property(property: 'value', type: 'string', example: 'paid'),
                            new OA\Property(property: 'label', type: 'string', example: 'Lunas'),
                            new OA\Property(property: 'color', type: 'string', example: 'success'),
                        ], type: 'object')),
                        new OA\Property(property: 'order_statuses', type: 'array', items: new OA\Items(type: 'object')),
                        new OA\Property(property: 'item_statuses', type: 'array', items: new OA\Items(type: 'object')),
                        new OA\Property(property: 'table_statuses', type: 'array', items: new OA\Items(type: 'object')),
                        new OA\Property(property: 'queue_statuses', type: 'array', items: new OA\Items(type: 'object')),
                        new OA\Property(property: 'shift_statuses', type: 'array', items: new OA\Items(type: 'object')),
                        new OA\Property(property: 'promo_types', type: 'array', items: new OA\Items(type: 'object')),
                        new OA\Property(property: 'ingredient_units', type: 'array', items: new OA\Items(type: 'object')),
                        new OA\Property(property: 'queue_categories', type: 'array', items: new OA\Items(properties: [
                            new OA\Property(property: 'code', type: 'string', example: 'A'),
                            new OA\Property(property: 'title', type: 'string', example: 'Meja Kecil'),
                            new OA\Property(property: 'subtitle', type: 'string', example: '(1 - 2 Orang)'),
                        ], type: 'object')),
                        new OA\Property(property: 'currency', properties: [
                            new OA\Property(property: 'code', type: 'string', example: 'IDR'),
                            new OA\Property(property: 'symbol', type: 'string', example: 'Rp'),
                            new OA\Property(property: 'decimal_digits', type: 'integer', example: 0),
                            new OA\Property(property: 'thousand_separator', type: 'string', example: '.'),
                            new OA\Property(property: 'decimal_separator', type: 'string', example: ','),
                        ], type: 'object'),
                        new OA\Property(property: 'realtime', properties: [
                            new OA\Property(property: 'driver', type: 'string', example: 'reverb'),
                            new OA\Property(property: 'key', type: 'string', nullable: true),
                            new OA\Property(property: 'host', type: 'string', nullable: true),
                            new OA\Property(property: 'port', type: 'integer', example: 8080),
                            new OA\Property(property: 'scheme', type: 'string', example: 'http'),
                            new OA\Property(property: 'channels', properties: [
                                new OA\Property(property: 'queue', type: 'string', example: 'public-queue.1'),
                                new OA\Property(property: 'display', type: 'string', example: 'public-display.1'),
                            ], type: 'object'),
                        ], type: 'object'),
                        new OA\Property(property: 'app', properties: [
                            new OA\Property(property: 'name', type: 'string', example: 'DineSync POS'),
                            new OA\Property(property: 'api_version', type: 'string', example: 'v1'),
                        ], type: 'object'),
                    ], type: 'object'),
                ]
            )),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
        ]
    )]
    public function index(): JsonResponse
    {
        return $this->ok([
            'order_types' => [
                ['value' => 'dine_in', 'label' => 'Dine In (Makan di Tempat)'],
                ['value' => 'take_away', 'label' => 'Take Away (Bawa Pulang)'],
                ['value' => 'reservation', 'label' => 'Reservasi (Booking)'],
            ],

            // Midtrans dinonaktifkan untuk trial: hanya bayar nanti & tunai.
            'payment_methods' => [
                ['value' => 'pay_later', 'label' => 'Bayar Nanti (Pay Later)'],
                ['value' => 'cash', 'label' => 'Tunai (Cash)'],
            ],

            'payment_statuses' => [
                ['value' => 'unpaid', 'label' => 'Belum Bayar', 'color' => 'warning'],
                ['value' => 'paid', 'label' => 'Lunas', 'color' => 'success'],
                ['value' => 'failed', 'label' => 'Gagal', 'color' => 'danger'],
            ],

            'order_statuses' => [
                ['value' => 'pending', 'label' => 'Menunggu Dibuat', 'color' => 'warning'],
                ['value' => 'cooking', 'label' => 'Sedang Dimasak', 'color' => 'primary'],
                ['value' => 'served', 'label' => 'Sudah Disajikan', 'color' => 'success'],
                ['value' => 'completed', 'label' => 'Selesai', 'color' => 'secondary'],
            ],

            'item_statuses' => [
                ['value' => 'pending', 'label' => 'Antre', 'color' => 'warning'],
                ['value' => 'cooking', 'label' => 'Dimasak', 'color' => 'primary'],
                ['value' => 'done', 'label' => 'Siap', 'color' => 'success'],
            ],

            'table_statuses' => [
                ['value' => 'available', 'label' => 'Tersedia (Kosong)', 'color' => 'success'],
                ['value' => 'occupied', 'label' => 'Terisi (Ada Pelanggan)', 'color' => 'danger'],
            ],

            'queue_statuses' => [
                ['value' => 'waiting', 'label' => 'Menunggu', 'color' => 'warning'],
                ['value' => 'called', 'label' => 'Dipanggil', 'color' => 'primary'],
                ['value' => 'seated', 'label' => 'Sudah Duduk', 'color' => 'success'],
                ['value' => 'cancelled', 'label' => 'Dibatalkan', 'color' => 'secondary'],
            ],

            'shift_statuses' => [
                ['value' => 'open', 'label' => 'Berjalan'],
                ['value' => 'closed', 'label' => 'Ditutup'],
            ],

            'promo_types' => [
                ['value' => 'percentage', 'label' => 'Persentase (%)'],
                ['value' => 'nominal', 'label' => 'Nominal (Rp)'],
            ],

            'ingredient_units' => [
                ['value' => 'gram', 'label' => 'Gram (g)'],
                ['value' => 'kg', 'label' => 'Kilogram (kg)'],
                ['value' => 'ml', 'label' => 'Mililiter (ml)'],
                ['value' => 'liter', 'label' => 'Liter (L)'],
                ['value' => 'pcs', 'label' => 'Pcs / Butir'],
                ['value' => 'slice', 'label' => 'Slice / Lembar'],
                ['value' => 'bungkus', 'label' => 'Bungkus'],
            ],

            'queue_categories' => [
                ['code' => 'A', 'title' => 'Meja Kecil', 'subtitle' => '(1 - 2 Orang)'],
                ['code' => 'B', 'title' => 'Meja Sedang', 'subtitle' => '(3 - 4 Orang)'],
                ['code' => 'C', 'title' => 'Meja Besar', 'subtitle' => '(5+ Orang)'],
            ],

            'currency' => [
                'code' => 'IDR',
                'symbol' => 'Rp',
                'decimal_digits' => 0,
                'thousand_separator' => '.',
                'decimal_separator' => ',',
            ],

            'realtime' => [
                'driver' => 'reverb',
                'key' => config('services.reverb.key'),
                'host' => config('services.reverb.host'),
                'port' => (int) config('services.reverb.port', 8080),
                'scheme' => config('services.reverb.scheme', 'http'),
                'channels' => [
                    'queue' => 'public-queue.' . app('tenant')->id(),
                    'display' => 'public-display.' . app('tenant')->id(),
                ],
            ],

            'app' => [
                'name' => config('app.name'),
                'api_version' => 'v1',
            ],
        ], 'Konstanta aplikasi berhasil dimuat.');
    }
}
