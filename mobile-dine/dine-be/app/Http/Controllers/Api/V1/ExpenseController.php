<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Api\BaseApiController;
use App\Http\Resources\ExpenseResource;
use App\Models\DailyBudget;
use App\Models\DailySalesTarget;
use App\Models\Expense;
use App\Models\Order;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use OpenApi\Attributes as OA;

/**
 * Modul Pengeluaran (Expense) + Target & Budget harian.
 *
 * Logika bisnis direplikasi dari ExpenseController web:
 * - CRUD pengeluaran (kolom `date`, `category`, `notes`, `amount`).
 * - Pengaturan harian: 1 target penjualan + 1 budget belanja per tanggal per tenant.
 * - Riwayat budget: pencapaian omzet vs target dan realisasi belanja vs budget.
 *
 * Semua model di sini ber-scope tenant (trait BelongsToTenant), jadi TIDAK ada
 * filter tenant_id manual — global scope yang mengerjakannya.
 */
class ExpenseController extends BaseApiController
{
    #[OA\Get(
        path: '/api/v1/expenses',
        operationId: 'expenseIndex',
        summary: 'Daftar pengeluaran (berpaginasi)',
        description: 'Menampilkan riwayat pengeluaran milik UMKM aktif, terbaru di atas '
            . '(urut tanggal turun lalu waktu input turun). Mendukung filter rentang tanggal dan '
            . 'pencarian pada kategori maupun catatan. Kirim `all=true` untuk mengambil seluruh data tanpa paginasi.',
        tags: ['Finance'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'date_from', description: 'Tanggal awal (YYYY-MM-DD), difilter pada kolom `date`', in: 'query', required: false, schema: new OA\Schema(type: 'string', format: 'date', example: '2026-08-01')),
            new OA\Parameter(name: 'date_to', description: 'Tanggal akhir (YYYY-MM-DD), difilter pada kolom `date`', in: 'query', required: false, schema: new OA\Schema(type: 'string', format: 'date', example: '2026-08-19')),
            new OA\Parameter(name: 'search', description: 'Cari pada kategori atau catatan pengeluaran', in: 'query', required: false, schema: new OA\Schema(type: 'string', example: 'Gas')),
            new OA\Parameter(name: 'all', description: 'Bila true, seluruh data dikembalikan tanpa paginasi', in: 'query', required: false, schema: new OA\Schema(type: 'boolean', example: false)),
            new OA\Parameter(name: 'per_page', description: 'Jumlah data per halaman (maks 100)', in: 'query', required: false, schema: new OA\Schema(type: 'integer', example: 20)),
            new OA\Parameter(name: 'page', description: 'Halaman ke-', in: 'query', required: false, schema: new OA\Schema(type: 'integer', example: 1)),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Daftar pengeluaran berpaginasi (data + meta)'),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 403, description: 'Tidak punya izin view_finance'),
        ]
    )]
    public function index(Request $request): JsonResponse
    {
        $query = Expense::with('user');

        if ($request->filled('date_from')) {
            $query->where('date', '>=', Carbon::parse($request->query('date_from'))->toDateString());
        }

        if ($request->filled('date_to')) {
            $query->where('date', '<=', Carbon::parse($request->query('date_to'))->toDateString());
        }

        if ($request->filled('search')) {
            $keyword = '%' . $request->query('search') . '%';
            $query->where(function ($q) use ($keyword) {
                $q->where('category', 'like', $keyword)
                    ->orWhere('notes', 'like', $keyword);
            });
        }

        $query->orderBy('date', 'desc')->orderBy('created_at', 'desc');

        if ($request->boolean('all')) {
            return $this->ok(
                ExpenseResource::collection($query->get()),
                'Seluruh pengeluaran berhasil diambil.'
            );
        }

        $paginator = $query->paginate($this->perPage());

        return $this->paginated(
            $paginator->through(fn ($expense) => new ExpenseResource($expense)),
            'Daftar pengeluaran berhasil diambil.'
        );
    }

    #[OA\Post(
        path: '/api/v1/expenses',
        operationId: 'expenseStore',
        summary: 'Catat pengeluaran baru',
        description: 'Menyimpan satu pengeluaran baru. Kolom `user_id` otomatis diisi user yang login, '
            . '`uuid` otomatis dibuat oleh model, dan `tenant_id` otomatis diisi tenant aktif.',
        tags: ['Finance'],
        security: [['sanctum' => []]],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['date', 'category', 'amount'],
                properties: [
                    new OA\Property(property: 'date', type: 'string', format: 'date', example: '2026-08-19', description: 'Tanggal pengeluaran'),
                    new OA\Property(property: 'category', type: 'string', maxLength: 255, example: 'Bahan Baku', description: 'Kategori pengeluaran (Bahan Baku, Gaji, Listrik, dll)'),
                    new OA\Property(property: 'amount', type: 'number', format: 'float', example: 150000, description: 'Nominal pengeluaran (Rupiah)'),
                    new OA\Property(property: 'notes', type: 'string', nullable: true, example: 'Beli gas 3 kg 2 tabung'),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 201, description: 'Pengeluaran berhasil dicatat'),
            new OA\Response(response: 422, description: 'Data yang dikirim tidak valid'),
        ]
    )]
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'date' => ['required', 'date'],
            'category' => ['required', 'string', 'max:255'],
            'amount' => ['required', 'numeric', 'min:0'],
            'notes' => ['nullable', 'string'],
        ], [
            'date.required' => 'Tanggal pengeluaran wajib diisi.',
            'date.date' => 'Format tanggal pengeluaran tidak valid.',
            'category.required' => 'Kategori pengeluaran wajib diisi.',
            'category.max' => 'Kategori pengeluaran maksimal 255 karakter.',
            'amount.required' => 'Nominal pengeluaran wajib diisi.',
            'amount.numeric' => 'Nominal pengeluaran harus berupa angka.',
            'amount.min' => 'Nominal pengeluaran tidak boleh minus.',
        ]);

        $expense = Expense::create([
            'date' => $data['date'],
            'category' => $data['category'],
            'amount' => $data['amount'],
            'notes' => $data['notes'] ?? null,
            'user_id' => auth()->id(),
        ]);

        return $this->created(
            new ExpenseResource($expense->load('user')),
            'Pengeluaran berhasil dicatat!'
        );
    }

    #[OA\Get(
        path: '/api/v1/expenses/{id}',
        operationId: 'expenseShow',
        summary: 'Detail satu pengeluaran',
        description: 'Menampilkan satu pengeluaran beserta nama pencatatnya.',
        tags: ['Finance'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', description: 'ID pengeluaran', in: 'path', required: true, schema: new OA\Schema(type: 'integer', example: 12)),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Detail pengeluaran'),
            new OA\Response(response: 404, description: 'Pengeluaran tidak ditemukan'),
        ]
    )]
    public function show($id): JsonResponse
    {
        $expense = Expense::with('user')->findOrFail($id);

        return $this->ok(new ExpenseResource($expense), 'Detail pengeluaran berhasil diambil.');
    }

    #[OA\Put(
        path: '/api/v1/expenses/{id}',
        operationId: 'expenseUpdate',
        summary: 'Ubah pengeluaran',
        description: 'Memperbarui data pengeluaran. Kolom `user_id` diperbarui menjadi user yang melakukan perubahan (sama seperti web).',
        tags: ['Finance'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', description: 'ID pengeluaran', in: 'path', required: true, schema: new OA\Schema(type: 'integer', example: 12)),
        ],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['date', 'category', 'amount'],
                properties: [
                    new OA\Property(property: 'date', type: 'string', format: 'date', example: '2026-08-19'),
                    new OA\Property(property: 'category', type: 'string', maxLength: 255, example: 'Listrik'),
                    new OA\Property(property: 'amount', type: 'number', format: 'float', example: 250000),
                    new OA\Property(property: 'notes', type: 'string', nullable: true, example: 'Token listrik bulan Agustus'),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 200, description: 'Pengeluaran berhasil diubah'),
            new OA\Response(response: 404, description: 'Pengeluaran tidak ditemukan'),
            new OA\Response(response: 422, description: 'Data yang dikirim tidak valid'),
        ]
    )]
    public function update(Request $request, $id): JsonResponse
    {
        $data = $request->validate([
            'date' => ['required', 'date'],
            'category' => ['required', 'string', 'max:255'],
            'amount' => ['required', 'numeric', 'min:0'],
            'notes' => ['nullable', 'string'],
        ], [
            'date.required' => 'Tanggal pengeluaran wajib diisi.',
            'date.date' => 'Format tanggal pengeluaran tidak valid.',
            'category.required' => 'Kategori pengeluaran wajib diisi.',
            'category.max' => 'Kategori pengeluaran maksimal 255 karakter.',
            'amount.required' => 'Nominal pengeluaran wajib diisi.',
            'amount.numeric' => 'Nominal pengeluaran harus berupa angka.',
            'amount.min' => 'Nominal pengeluaran tidak boleh minus.',
        ]);

        $expense = Expense::findOrFail($id);

        $expense->update([
            'date' => $data['date'],
            'category' => $data['category'],
            'amount' => $data['amount'],
            'notes' => $data['notes'] ?? null,
            'user_id' => auth()->id(),
        ]);

        return $this->ok(
            new ExpenseResource($expense->fresh()->load('user')),
            'Pengeluaran berhasil diubah!'
        );
    }

    #[OA\Delete(
        path: '/api/v1/expenses/{id}',
        operationId: 'expenseDestroy',
        summary: 'Hapus pengeluaran',
        description: 'Menghapus satu catatan pengeluaran secara permanen.',
        tags: ['Finance'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'id', description: 'ID pengeluaran', in: 'path', required: true, schema: new OA\Schema(type: 'integer', example: 12)),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Pengeluaran berhasil dihapus'),
            new OA\Response(response: 404, description: 'Pengeluaran tidak ditemukan'),
        ]
    )]
    public function destroy($id): JsonResponse
    {
        $expense = Expense::findOrFail($id);
        $expense->delete();

        return $this->ok(null, 'Pengeluaran berhasil dihapus.');
    }

    #[OA\Get(
        path: '/api/v1/finance/daily-settings',
        operationId: 'financeDailySettings',
        summary: 'Target & budget harian beserta realisasinya',
        description: 'Mengembalikan target penjualan dan budget belanja untuk satu tanggal, '
            . 'plus realisasinya: `income` (total grand_total order LUNAS pada tanggal itu) dan '
            . '`spent` (total pengeluaran pada tanggal itu). Dipakai untuk kartu ringkasan harian di mobile. '
            . 'Bila parameter `date` tidak dikirim, dipakai tanggal hari ini.',
        tags: ['Finance'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'date', description: 'Tanggal yang ingin dilihat (YYYY-MM-DD). Default: hari ini', in: 'query', required: false, schema: new OA\Schema(type: 'string', format: 'date', example: '2026-08-19')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Pengaturan & realisasi harian', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'message', type: 'string', example: 'Pengaturan harian berhasil diambil.'),
                    new OA\Property(property: 'data', properties: [
                        new OA\Property(property: 'date', type: 'string', format: 'date', example: '2026-08-19'),
                        new OA\Property(property: 'target', type: 'number', format: 'float', example: 2000000),
                        new OA\Property(property: 'budget', type: 'number', format: 'float', example: 750000),
                        new OA\Property(property: 'income', type: 'number', format: 'float', example: 1250000),
                        new OA\Property(property: 'spent', type: 'number', format: 'float', example: 320000),
                    ], type: 'object'),
                ]
            )),
            new OA\Response(response: 422, description: 'Format tanggal tidak valid'),
        ]
    )]
    public function dailySettings(Request $request): JsonResponse
    {
        $request->validate([
            'date' => ['nullable', 'date'],
        ], [
            'date.date' => 'Format tanggal tidak valid.',
        ]);

        $date = $request->filled('date')
            ? Carbon::parse($request->query('date'))->toDateString()
            : now()->toDateString();

        return $this->ok([
            'date' => $date,
            'target' => (float) (DailySalesTarget::where('date', $date)->value('amount') ?? 0),
            'budget' => (float) (DailyBudget::where('date', $date)->value('amount') ?? 0),
            'income' => (float) Order::whereDate('created_at', $date)
                ->where('payment_status', 'paid')
                ->sum('grand_total'),
            'spent' => (float) Expense::whereDate('date', $date)->sum('amount'),
        ], 'Pengaturan harian berhasil diambil.');
    }

    #[OA\Post(
        path: '/api/v1/finance/daily-settings',
        operationId: 'financeSaveDailySettings',
        summary: 'Simpan target & budget harian',
        description: 'Menyimpan (atau memperbarui) target penjualan dan budget belanja untuk satu tanggal. '
            . 'Satu tanggal hanya boleh punya satu target dan satu budget per UMKM, sehingga dipakai '
            . '`updateOrCreate` di dalam satu transaksi database.',
        tags: ['Finance'],
        security: [['sanctum' => []]],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['date', 'target', 'budget'],
                properties: [
                    new OA\Property(property: 'date', type: 'string', format: 'date', example: '2026-08-19'),
                    new OA\Property(property: 'target', type: 'number', format: 'float', example: 2000000, description: 'Target omzet harian (Rupiah)'),
                    new OA\Property(property: 'budget', type: 'number', format: 'float', example: 750000, description: 'Budget belanja harian (Rupiah)'),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 200, description: 'Pengaturan harian berhasil disimpan'),
            new OA\Response(response: 422, description: 'Data yang dikirim tidak valid'),
        ]
    )]
    public function saveDailySettings(Request $request): JsonResponse
    {
        $data = $request->validate([
            'date' => ['required', 'date'],
            'target' => ['required', 'numeric', 'min:0'],
            'budget' => ['required', 'numeric', 'min:0'],
        ], [
            'date.required' => 'Tanggal wajib diisi.',
            'date.date' => 'Format tanggal tidak valid.',
            'target.required' => 'Target penjualan wajib diisi.',
            'target.numeric' => 'Target penjualan harus berupa angka.',
            'target.min' => 'Target penjualan tidak boleh minus.',
            'budget.required' => 'Budget harian wajib diisi.',
            'budget.numeric' => 'Budget harian harus berupa angka.',
            'budget.min' => 'Budget harian tidak boleh minus.',
        ]);

        $date = Carbon::parse($data['date'])->toDateString();

        DB::transaction(function () use ($date, $data) {
            DailySalesTarget::updateOrCreate(
                ['date' => $date],
                ['amount' => $data['target']]
            );

            DailyBudget::updateOrCreate(
                ['date' => $date],
                ['amount' => $data['budget']]
            );
        });

        return $this->ok([
            'date' => $date,
            'target' => (float) $data['target'],
            'budget' => (float) $data['budget'],
        ], 'Pengaturan Harian berhasil disimpan!');
    }

    #[OA\Get(
        path: '/api/v1/finance/budget-history',
        operationId: 'financeBudgetHistory',
        summary: 'Riwayat target & budget harian (berpaginasi)',
        description: 'Riwayat pencapaian per tanggal, terbaru di atas. Untuk setiap tanggal dihitung ulang '
            . 'secara real-time: `income` (omzet order LUNAS), `spent` (total pengeluaran), '
            . '`target_percentage` = round(income / target * 100) bila target > 0, dan '
            . '`budget_percentage` = round(spent / budget * 100) bila budget > 0. '
            . 'Daftar tanggal diambil dari tabel target penjualan harian — endpoint penyimpanan '
            . '(`POST /api/v1/finance/daily-settings`) selalu menulis target dan budget bersamaan, '
            . 'sehingga tanggalnya identik dengan tabel budget.',
        tags: ['Finance'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'per_page', description: 'Jumlah data per halaman (maks 100)', in: 'query', required: false, schema: new OA\Schema(type: 'integer', example: 20)),
            new OA\Parameter(name: 'page', description: 'Halaman ke-', in: 'query', required: false, schema: new OA\Schema(type: 'integer', example: 1)),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Riwayat target & budget berpaginasi', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'message', type: 'string', example: 'Riwayat target & budget berhasil diambil.'),
                    new OA\Property(property: 'data', type: 'array', items: new OA\Items(properties: [
                        new OA\Property(property: 'date', type: 'string', format: 'date', example: '2026-08-19'),
                        new OA\Property(property: 'target', type: 'number', format: 'float', example: 2000000),
                        new OA\Property(property: 'income', type: 'number', format: 'float', example: 1250000),
                        new OA\Property(property: 'target_percentage', type: 'integer', example: 63),
                        new OA\Property(property: 'budget', type: 'number', format: 'float', example: 750000),
                        new OA\Property(property: 'spent', type: 'number', format: 'float', example: 320000),
                        new OA\Property(property: 'budget_percentage', type: 'integer', example: 43),
                    ], type: 'object')),
                    new OA\Property(property: 'meta', type: 'object'),
                ]
            )),
        ]
    )]
    public function budgetHistory(Request $request): JsonResponse
    {
        $paginator = DailySalesTarget::orderBy('date', 'desc')
            ->orderBy('id', 'desc')
            ->paginate($this->perPage());

        return $this->paginated(
            $paginator->through(function ($row) {
                $date = date('Y-m-d', strtotime((string) $row->date));

                $target = (float) $row->amount;
                $budget = (float) (DailyBudget::where('date', $date)->value('amount') ?? 0);

                $income = (float) Order::whereDate('created_at', $date)
                    ->where('payment_status', 'paid')
                    ->sum('grand_total');

                $spent = (float) Expense::whereDate('date', $date)->sum('amount');

                return [
                    'date' => $date,
                    'target' => $target,
                    'income' => $income,
                    'target_percentage' => $target > 0 ? (int) round($income / $target * 100) : 0,
                    'budget' => $budget,
                    'spent' => $spent,
                    'budget_percentage' => $budget > 0 ? (int) round($spent / $budget * 100) : 0,
                ];
            }),
            'Riwayat target & budget berhasil diambil.'
        );
    }
}
