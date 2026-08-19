<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Api\BaseApiController;
use App\Http\Resources\ShiftResource;
use App\Models\DailyBudget;
use App\Models\DailySalesTarget;
use App\Models\Order;
use App\Models\Shift;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use OpenApi\Attributes as OA;

/**
 * Modul Shift Kasir untuk aplikasi mobile.
 *
 * Logika direplikasi dari ShiftController web: buka shift (dengan modal awal,
 * plus target penjualan & budget harian bila ini shift pertama hari itu),
 * tutup shift (rekonsiliasi uang tunai), dan riwayat shift.
 */
class ShiftController extends BaseApiController
{
    #[OA\Get(
        path: '/api/v1/shifts/current',
        operationId: 'shiftCurrent',
        summary: 'Shift aktif saya + estimasi uang di kasir',
        description: 'Mengembalikan shift yang sedang terbuka milik user login (null bila belum buka shift), '
            . 'total penjualan tunai selama shift, perkiraan uang yang harus ada di laci (modal awal + penjualan tunai), '
            . 'serta penanda apakah ini shift pertama hari ini (kalau ya, target penjualan & budget harian wajib diisi saat buka shift).',
        tags: ['Shift'],
        security: [['sanctum' => []]],
        responses: [
            new OA\Response(response: 200, description: 'Status shift saat ini'),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 403, description: 'Tidak punya izin view_kasir'),
        ]
    )]
    public function current(): JsonResponse
    {
        $userId = auth()->id();
        $currentShift = Shift::where('user_id', $userId)->where('status', 'open')->first();

        $cashSales = 0;
        if ($currentShift) {
            $cashSales = Order::where('payment_method', 'cash')
                ->where('payment_status', 'paid')
                ->where('created_at', '>=', $currentShift->start_time)
                ->sum('grand_total');
        }

        $isFirstShiftOfDay = ! DailySalesTarget::whereDate('date', \Carbon\Carbon::today())->exists();

        return $this->ok([
            'shift' => $currentShift ? new ShiftResource($currentShift) : null,
            'cash_sales' => (float) $cashSales,
            'expected_cash' => $currentShift ? (float) $currentShift->starting_cash + $cashSales : 0,
            'is_first_shift_of_day' => $isFirstShiftOfDay,
        ], 'Status shift berhasil diambil.');
    }

    #[OA\Post(
        path: '/api/v1/shifts/open',
        operationId: 'shiftOpen',
        summary: 'Buka shift kasir',
        description: 'Membuka shift baru dengan mengisi modal awal (uang di laci). '
            . 'Bila ini shift PERTAMA pada hari tersebut, field `target_penjualan` dan `daily_budget` wajib diisi karena '
            . 'keduanya dipakai sebagai acuan global harian (dashboard & finance). '
            . 'Satu user tidak boleh punya dua shift terbuka sekaligus.',
        tags: ['Shift'],
        security: [['sanctum' => []]],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['starting_cash'],
                properties: [
                    new OA\Property(property: 'starting_cash', type: 'number', format: 'float', example: 200000, description: 'Modal awal di laci kasir'),
                    new OA\Property(property: 'target_penjualan', type: 'number', format: 'float', example: 3000000, nullable: true, description: 'Wajib bila shift pertama hari ini'),
                    new OA\Property(property: 'daily_budget', type: 'number', format: 'float', example: 500000, nullable: true, description: 'Wajib bila shift pertama hari ini'),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 201, description: 'Shift berhasil dibuka'),
            new OA\Response(response: 409, description: 'Masih ada shift aktif milik user ini'),
            new OA\Response(response: 422, description: 'Data tidak valid'),
        ]
    )]
    public function open(Request $request): JsonResponse
    {
        $today = \Carbon\Carbon::today();
        $isFirstShiftOfDay = ! DailySalesTarget::whereDate('date', $today)->exists();

        $rules = ['starting_cash' => 'required|numeric|min:0'];
        if ($isFirstShiftOfDay) {
            $rules['target_penjualan'] = 'required|numeric|min:0';
            $rules['daily_budget'] = 'required|numeric|min:0';
        }

        $request->validate($rules, [
            'starting_cash.required' => 'Modal awal kasir wajib diisi.',
            'starting_cash.numeric' => 'Modal awal kasir harus berupa angka.',
            'starting_cash.min' => 'Modal awal kasir tidak boleh minus.',
            'target_penjualan.required' => 'Target penjualan hari ini wajib diisi (Anda shift pertama hari ini).',
            'target_penjualan.numeric' => 'Target penjualan harus berupa angka.',
            'target_penjualan.min' => 'Target penjualan tidak boleh minus.',
            'daily_budget.required' => 'Budget belanja harian wajib diisi (Anda shift pertama hari ini).',
            'daily_budget.numeric' => 'Budget belanja harian harus berupa angka.',
            'daily_budget.min' => 'Budget belanja harian tidak boleh minus.',
        ]);

        // Cegah buka shift ganda.
        $activeShift = Shift::where('user_id', auth()->id())->where('status', 'open')->first();
        if ($activeShift) {
            return $this->fail('Anda masih memiliki shift yang aktif!', 409);
        }

        $shift = DB::transaction(function () use ($request, $today, $isFirstShiftOfDay) {
            if ($isFirstShiftOfDay) {
                DailySalesTarget::create([
                    'date' => $today,
                    'amount' => $request->target_penjualan,
                ]);

                DailyBudget::create([
                    'date' => $today,
                    'amount' => $request->daily_budget,
                ]);
            }

            return Shift::create([
                'user_id' => auth()->id(),
                'start_time' => now(),
                'starting_cash' => $request->starting_cash,
                'status' => 'open',
            ]);
        });

        $shift->load('user');

        return $this->created([
            'shift' => new ShiftResource($shift),
            'is_first_shift_of_day' => $isFirstShiftOfDay,
        ], 'Shift berhasil dibuka! Selamat bekerja.');
    }

    #[OA\Post(
        path: '/api/v1/shifts/{id}/close',
        operationId: 'shiftClose',
        summary: 'Tutup shift kasir',
        description: 'Menutup shift dan menyimpan laporan rekonsiliasi kas (modal awal + penjualan tunai vs uang fisik). '
            . 'Ditolak (409) bila masih ada pesanan yang dibuat selama shift ini yang belum dibayar atau mejanya belum dikosongkan.',
        tags: ['Shift'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', description: 'ID shift yang akan ditutup', in: 'path', required: true, schema: new OA\Schema(type: 'integer', example: 7)),
        ],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['actual_cash'],
                properties: [
                    new OA\Property(property: 'actual_cash', type: 'number', format: 'float', example: 1250000, description: 'Uang fisik hasil hitung manual di laci'),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 200, description: 'Shift berhasil ditutup'),
            new OA\Response(response: 404, description: 'Shift tidak ditemukan / bukan milik Anda / sudah tertutup'),
            new OA\Response(response: 409, description: 'Masih ada pesanan belum selesai pada shift ini'),
            new OA\Response(response: 422, description: 'Data tidak valid'),
        ]
    )]
    public function close(Request $request, $id): JsonResponse
    {
        $request->validate([
            'actual_cash' => 'required|numeric|min:0',
        ], [
            'actual_cash.required' => 'Jumlah uang fisik di laci wajib diisi.',
            'actual_cash.numeric' => 'Jumlah uang fisik harus berupa angka.',
            'actual_cash.min' => 'Jumlah uang fisik tidak boleh minus.',
        ]);

        $shift = Shift::where('user_id', auth()->id())->where('status', 'open')->findOrFail($id);

        // Hanya cek pesanan yang dibuat SELAMA shift ini berlangsung.
        $pendingOrders = Order::where('created_at', '>=', $shift->start_time)
            ->where(function ($query) {
                $query->whereIn('order_status', ['pending', 'cooking', 'served'])
                    ->orWhere('payment_status', 'unpaid');
            })
            ->count();

        if ($pendingOrders > 0) {
            return $this->fail('Akses Ditolak! Masih ada ' . $pendingOrders . ' pesanan yang belum dibayar atau meja yang belum dikosongkan. Harap selesaikan semua meja di menu Kasir terlebih dahulu.', 409);
        }

        DB::transaction(function () use ($shift, $request) {
            $cashSales = Order::where('payment_method', 'cash')
                ->where('payment_status', 'paid')
                ->where('created_at', '>=', $shift->start_time)
                ->sum('grand_total');

            $expectedCash = $shift->starting_cash + $cashSales;
            $difference = $request->actual_cash - $expectedCash;

            $shift->update([
                'end_time' => now(),
                'cash_sales' => $cashSales,
                'expected_cash' => $expectedCash,
                'actual_cash' => $request->actual_cash,
                'difference' => $difference,
                'status' => 'closed',
            ]);
        });

        $shift->load('user');

        return $this->ok([
            'shift' => new ShiftResource($shift),
        ], 'Shift berhasil ditutup. Laporan kasir telah disimpan.');
    }

    #[OA\Get(
        path: '/api/v1/shifts/history',
        operationId: 'shiftHistory',
        summary: 'Riwayat shift saya (berpaginasi)',
        description: 'Daftar shift milik user login yang sudah ditutup, terbaru di atas, lengkap dengan selisih kas dan labelnya.',
        tags: ['Shift'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'per_page', description: 'Jumlah data per halaman (maks 100, default 10)', in: 'query', required: false, schema: new OA\Schema(type: 'integer', example: 10)),
            new OA\Parameter(name: 'page', description: 'Halaman ke-', in: 'query', required: false, schema: new OA\Schema(type: 'integer', example: 1)),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Riwayat shift berpaginasi (data + meta)'),
        ]
    )]
    public function history(Request $request): JsonResponse
    {
        $paginator = Shift::with('user')
            ->where('user_id', auth()->id())
            ->where('status', 'closed')
            ->orderBy('id', 'desc')
            ->paginate($this->perPage(10));

        return $this->paginated(
            $paginator->through(fn ($shift) => new ShiftResource($shift)),
            'Riwayat shift berhasil diambil.'
        );
    }
}
