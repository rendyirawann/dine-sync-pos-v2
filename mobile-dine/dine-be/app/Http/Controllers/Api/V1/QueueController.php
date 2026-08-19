<?php

namespace App\Http\Controllers\Api\V1;

use App\Events\CallQueueEvent;
use App\Events\NewQueueEvent;
use App\Http\Controllers\Api\BaseApiController;
use App\Http\Resources\QueueResource;
use App\Models\Queue;
use App\Models\Setting;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use OpenApi\Attributes as OA;

/**
 * Antrian pelanggan — replika QueueController web:
 * daftar antrian hari ini (resepsionis), panggilan suara ber-cooldown,
 * kiosk ambil nomor, dan layar TV display (keduanya publik/tanpa login).
 *
 * Kategori nomor antrian mengikuti jumlah orang (pax):
 * A = 1-2 orang, B = 3-4 orang, C = 5+ orang.
 */
class QueueController extends BaseApiController
{
    /** Kategori meja per prefix nomor antrian (dipakai layar TV display). */
    private const CATEGORIES = [
        ['code' => 'A', 'title' => 'Meja Kecil', 'subtitle' => '(1 - 2 Orang)'],
        ['code' => 'B', 'title' => 'Meja Sedang', 'subtitle' => '(3 - 4 Orang)'],
        ['code' => 'C', 'title' => 'Meja Besar', 'subtitle' => '(5+ Orang)'],
    ];

    #[OA\Get(
        path: '/api/v1/queues',
        operationId: 'queueIndex',
        summary: 'Daftar antrian hari ini',
        description: <<<'TXT'
Antrian **hari ini** dengan urutan sama seperti web: `waiting` -> `called` -> `seated` ->
`cancelled`, lalu `created_at` ASC di dalam tiap kelompok.

`cooldown_left` = sisa detik sebelum tombol panggil boleh dipakai lagi (0 = siap memanggil),
dihitung dari cache `last_audio_call` dengan jeda 15 detik. `summary` berisi jumlah
antrian per status untuk badge di layar resepsionis.
TXT,
        tags: ['Antrian'],
        security: [['sanctum' => []]],
        responses: [
            new OA\Response(response: 200, description: 'Daftar antrian', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'data', properties: [
                        new OA\Property(property: 'queues', type: 'array', items: new OA\Items(type: 'object')),
                        new OA\Property(property: 'cooldown_left', type: 'integer', example: 0),
                        new OA\Property(property: 'summary', properties: [
                            new OA\Property(property: 'waiting', type: 'integer', example: 3),
                            new OA\Property(property: 'called', type: 'integer', example: 1),
                            new OA\Property(property: 'seated', type: 'integer', example: 8),
                        ], type: 'object'),
                    ], type: 'object'),
                ]
            )),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 403, description: 'Tidak punya izin view_queue'),
        ]
    )]
    public function index(Request $request): JsonResponse
    {
        $queues = Queue::whereDate('created_at', Carbon::today())
            ->orderByRaw("
                CASE status
                    WHEN 'waiting' THEN 1
                    WHEN 'called' THEN 2
                    WHEN 'seated' THEN 3
                    WHEN 'cancelled' THEN 4
                    ELSE 5
                END
            ")
            ->orderBy('created_at', 'asc')
            ->get();

        $lastCall = Cache::get('last_audio_call');
        $cooldownLeft = 0;
        if ($lastCall) {
            $elapsed = time() - $lastCall;
            if ($elapsed < 15) {
                $cooldownLeft = 15 - $elapsed;
            }
        }

        return $this->ok([
            'queues' => QueueResource::collection($queues),
            'cooldown_left' => $cooldownLeft,
            'summary' => [
                'waiting' => $queues->where('status', 'waiting')->count(),
                'called' => $queues->where('status', 'called')->count(),
                'seated' => $queues->where('status', 'seated')->count(),
            ],
        ], 'Data antrian berhasil dimuat.');
    }

    #[OA\Post(
        path: '/api/v1/queues/{id}/call',
        operationId: 'queueCall',
        summary: 'Panggil antrian (suara + TV display)',
        description: <<<'TXT'
Menandai antrian menjadi `called` dan menyiarkan panggilan suara ke TV display.

Dibatasi cooldown **15 detik** di sisi server (cache `last_audio_call`); bila masih
dalam cooldown, response `429` dan status antrian tidak diubah. Kalimat suara dibaca
per digit, mis. `A-0-0-3`, lalu nama pelanggan. Kegagalan broadcast (Reverb mati)
hanya dicatat di log — status `called` tetap tersimpan.
TXT,
        tags: ['Antrian'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID antrian', schema: new OA\Schema(type: 'integer')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Antrian dipanggil', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'message', type: 'string', example: 'Memanggil antrian A003'),
                    new OA\Property(property: 'data', properties: [
                        new OA\Property(property: 'queue', type: 'object'),
                        new OA\Property(property: 'cooldown_left', type: 'integer', example: 15),
                    ], type: 'object'),
                ]
            )),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 404, description: 'Antrian tidak ditemukan'),
            new OA\Response(response: 429, description: 'Masih dalam cooldown panggilan'),
        ]
    )]
    public function call($id): JsonResponse
    {
        $lastCall = Cache::get('last_audio_call');
        if ($lastCall && (time() - $lastCall) < 15) {
            return $this->fail('Harap tunggu! Sedang ada pemanggilan lain yang berlangsung.', 429);
        }

        $queue = Queue::findOrFail($id);
        $queue->update(['status' => 'called']);

        $textToSpeak = 'Nomor antrian, ' . implode('-', str_split($queue->queue_number)) . ', atas nama, ' . $queue->customer_name . '. Silakan menuju meja resepsionis.';

        $displayData = [
            'number' => $queue->queue_number,
            'name' => $queue->customer_name,
        ];

        Cache::put('last_audio_call', time(), 15);

        try {
            broadcast(new CallQueueEvent($textToSpeak, $displayData, 'queue', app('tenant')->id()));
        } catch (\Exception $e) {
            // Reverb mati: abaikan, status antrian HARUS tetap tersimpan.
            Log::error('Gagal Memanggil Antrian (Broadcast): ' . $e->getMessage());
        }

        return $this->ok([
            'queue' => new QueueResource($queue),
            'cooldown_left' => 15,
        ], 'Memanggil antrian ' . $queue->queue_number);
    }

    #[OA\Post(
        path: '/api/v1/queues/{id}/status',
        operationId: 'queueUpdateStatus',
        summary: 'Ubah status antrian',
        description: 'Mengubah status antrian secara manual oleh resepsionis: `waiting` (menunggu), `called` (dipanggil), `seated` (sudah duduk), atau `cancelled` (dibatalkan). Tidak memicu panggilan suara.',
        tags: ['Antrian'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, description: 'ID antrian', schema: new OA\Schema(type: 'integer')),
        ],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['status'],
                properties: [
                    new OA\Property(property: 'status', type: 'string', enum: ['waiting', 'called', 'seated', 'cancelled'], example: 'seated'),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 200, description: 'Status antrian diperbarui'),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 404, description: 'Antrian tidak ditemukan'),
            new OA\Response(response: 422, description: 'Validasi gagal'),
        ]
    )]
    public function updateStatus(Request $request, $id): JsonResponse
    {
        $request->validate([
            'status' => 'required|in:waiting,called,seated,cancelled',
        ], [
            'status.required' => 'Status antrian wajib diisi.',
            'status.in' => 'Status antrian hanya boleh waiting, called, seated, atau cancelled.',
        ]);

        $queue = Queue::findOrFail($id);
        $queue->update(['status' => $request->status]);

        return $this->ok(new QueueResource($queue), 'Status antrian berhasil diperbarui.');
    }

    #[OA\Get(
        path: '/api/v1/public/{tenant}/queue/display',
        operationId: 'publicQueueDisplay',
        summary: 'Data layar TV display antrian (publik)',
        description: <<<'TXT'
Data untuk layar TV display antrian di area tunggu — **tanpa login**.

`{tenant}` berupa slug atau id UMKM; seluruh data otomatis ter-filter untuk UMKM tersebut.
Untuk tiap kategori (A/B/C) dikembalikan nomor yang **terakhir dipanggil** hari ini
(`called`, diurut `updated_at` DESC) dan maksimal **5 antrian berikutnya** yang masih
`waiting` (diurut `created_at` ASC).

`realtime` memberi nama channel broadcast yang perlu di-subscribe:
`channel_display` untuk event panggilan suara (`call-event`) dan `channel_queue`
untuk pemberitahuan antrian baru.
TXT,
        tags: ['Publik'],
        parameters: [
            new OA\Parameter(name: 'tenant', in: 'path', required: true, description: 'Slug atau ID UMKM', schema: new OA\Schema(type: 'string')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Data layar antrian', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'data', properties: [
                        new OA\Property(property: 'store_name', type: 'string', example: 'Warung Bu Ani'),
                        new OA\Property(property: 'called', type: 'object', description: 'Nomor terakhir dipanggil per kategori (A/B/C), null bila belum ada.'),
                        new OA\Property(property: 'waiting', type: 'object', description: 'Maksimal 5 antrian menunggu per kategori (A/B/C).'),
                        new OA\Property(property: 'categories', type: 'array', items: new OA\Items(type: 'object')),
                        new OA\Property(property: 'realtime', properties: [
                            new OA\Property(property: 'channel_display', type: 'string', example: 'public-display.9b1c...'),
                            new OA\Property(property: 'channel_queue', type: 'string', example: 'public-queue.9b1c...'),
                        ], type: 'object'),
                    ], type: 'object'),
                ]
            )),
            new OA\Response(response: 404, description: 'UMKM tidak ditemukan'),
        ]
    )]
    public function display($tenant): JsonResponse
    {
        $tenantId = app('tenant')->id();
        if (! $tenantId) {
            return $this->fail('UMKM tidak ditemukan.', 404);
        }

        $today = Carbon::today();
        $called = [];
        $waiting = [];

        foreach (['A', 'B', 'C'] as $prefix) {
            $last = Queue::whereDate('created_at', $today)
                ->where('status', 'called')
                ->where('queue_number', 'like', $prefix . '%')
                ->orderBy('updated_at', 'desc')
                ->first();

            $called[$prefix] = $last ? new QueueResource($last) : null;

            $waiting[$prefix] = QueueResource::collection(
                Queue::whereDate('created_at', $today)
                    ->where('status', 'waiting')
                    ->where('queue_number', 'like', $prefix . '%')
                    ->orderBy('created_at', 'asc')
                    ->limit(5)
                    ->get()
            );
        }

        $setting = Setting::forCurrentTenant();

        return $this->ok([
            'store_name' => $setting->store_name ?? 'DineSync POS',
            'called' => $called,
            'waiting' => $waiting,
            'categories' => self::CATEGORIES,
            'realtime' => [
                'channel_display' => 'public-display.' . $tenantId,
                'channel_queue' => 'public-queue.' . $tenantId,
            ],
        ], 'Data layar antrian berhasil dimuat.');
    }

    #[OA\Post(
        path: '/api/v1/public/{tenant}/queue/take',
        operationId: 'publicQueueTake',
        summary: 'Ambil nomor antrian dari kiosk (publik)',
        description: <<<'TXT'
Pelanggan mengambil nomor antrian sendiri lewat kiosk — **tanpa login**.

Prefix ditentukan otomatis dari `pax`: 1-2 orang -> `A`, 3-4 orang -> `B`, 5+ orang -> `C`.
Nomor urut di-reset setiap hari per prefix dan diformat 3 digit (mis. `B004`).
Setelah tersimpan, sinyal `NewQueueEvent` disiarkan ke layar kasir/resepsionis;
kegagalan broadcast (Reverb mati) hanya dicatat di log — nomor antrian tetap tersimpan.
TXT,
        tags: ['Publik'],
        parameters: [
            new OA\Parameter(name: 'tenant', in: 'path', required: true, description: 'Slug atau ID UMKM', schema: new OA\Schema(type: 'string')),
        ],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['customer_name', 'pax'],
                properties: [
                    new OA\Property(property: 'customer_name', type: 'string', maxLength: 255, example: 'Budi'),
                    new OA\Property(property: 'pax', type: 'integer', minimum: 1, example: 4, description: 'Jumlah orang — menentukan kategori meja A/B/C.'),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 200, description: 'Antrian berhasil diambil'),
            new OA\Response(response: 404, description: 'UMKM tidak ditemukan'),
            new OA\Response(response: 422, description: 'Validasi gagal'),
        ]
    )]
    public function take(Request $request, $tenant): JsonResponse
    {
        $request->validate([
            'customer_name' => 'required|string|max:255',
            'pax' => 'required|integer|min:1',
        ], [
            'customer_name.required' => 'Nama pelanggan wajib diisi.',
            'customer_name.max' => 'Nama pelanggan maksimal 255 karakter.',
            'pax.required' => 'Jumlah orang wajib diisi.',
            'pax.integer' => 'Jumlah orang harus berupa angka.',
            'pax.min' => 'Jumlah orang minimal 1.',
        ]);

        if (! app('tenant')->id()) {
            return $this->fail('UMKM tidak ditemukan.', 404);
        }

        $prefix = 'A';
        if ($request->pax >= 3 && $request->pax <= 4) {
            $prefix = 'B';
        } elseif ($request->pax >= 5) {
            $prefix = 'C';
        }

        $lastQueue = Queue::whereDate('created_at', Carbon::today())
            ->where('queue_number', 'like', $prefix . '%')
            ->orderBy('id', 'desc')
            ->first();

        $nextNumber = $lastQueue ? intval(substr($lastQueue->queue_number, 1)) + 1 : 1;
        $queue_number = $prefix . str_pad($nextNumber, 3, '0', STR_PAD_LEFT);

        $queue = Queue::create([
            'queue_number' => $queue_number,
            'customer_name' => $request->customer_name,
            'pax' => $request->pax,
            'status' => 'waiting',
        ]);

        try {
            broadcast(new NewQueueEvent(app('tenant')->id()));
        } catch (\Exception $e) {
            // Reverb mati: abaikan, nomor antrian HARUS tetap tersimpan.
            Log::error('Gagal Broadcast Antrian Baru: ' . $e->getMessage());
        }

        return $this->ok(new QueueResource($queue), 'Antrian berhasil diambil!');
    }
}
