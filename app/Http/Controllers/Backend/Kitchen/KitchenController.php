<?php

namespace App\Http\Controllers\Backend\Kitchen;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\Order;
use App\Models\OrderDetail;
use Illuminate\Support\Facades\DB;
use App\Events\CallQueueEvent;
use Illuminate\Support\Facades\Cache;

class KitchenController extends Controller
{
    public function index()
    {
        // Tampilkan SEMUA pesanan yang belum selesai, tanpa filter tanggal.
        // Ini penting agar order dari hari sebelumnya (meja belum dibersihkan) tetap muncul.
        $activeOrders = Order::with(['table', 'details.menu'])
            ->whereIn('order_status', ['pending', 'cooking'])
            ->orderBy('created_at', 'asc')
            ->get();

        // Pesanan Sudah Selesai: tampilkan 3 hari terakhir saja untuk referensi
        $completedOrders = Order::with(['table', 'details.menu'])
            ->whereIn('order_status', ['served', 'completed'])
            ->where('updated_at', '>=', \Carbon\Carbon::now()->subDays(3))
            ->orderBy('updated_at', 'desc')
            ->get();

        return view('backend.kitchen.index', compact('activeOrders', 'completedOrders'));
    }

    public function updateItemStatus(Request $request)
    {
        try {
            DB::beginTransaction();

            $detail = OrderDetail::findOrFail($request->detail_id);
            $detail->update(['status' => $request->status]);

            $order = Order::findOrFail($detail->order_id);

            $totalItems = $order->details()->count();
            $doneItems = $order->details()->where('status', 'done')->count();
            $cookingItems = $order->details()->where('status', 'cooking')->count();

            // 🔥 PERBAIKAN 2: Deteksi apakah ini menu terakhir yang diselesaikan
            $isFinished = false;

            if ($doneItems == $totalItems) {
                $order->update(['order_status' => 'served']);
                $isFinished = true; // Tandai bahwa tiket ini selesai 100%
            } elseif ($cookingItems > 0 || $doneItems > 0) {
                $order->update(['order_status' => 'cooking']);
            } else {
                $order->update(['order_status' => 'pending']);
            }

            DB::commit();
            return response()->json([
                'success' => true,
                'is_finished' => $isFinished,
                'table_name' => $order->table->table_number ?? 'Walk-in'
            ]);
        } catch (\Exception $e) {
            DB::rollback();
            return response()->json(['success' => false, 'error' => $e->getMessage()], 500);
        }
    }

    // FUNGSI BARU: Update semua item di dalam 1 Order sekaligus
    public function updateOrderStatus(Request $request)
    {
        try {
            DB::beginTransaction();

            $order = Order::findOrFail($request->order_id);
            $status = $request->status; // 'cooking' atau 'done'
            $isFinished = false;

            if ($status == 'cooking') {
                // Ubah semua yang 'pending' jadi 'cooking'
                $order->details()->where('status', 'pending')->update(['status' => 'cooking']);
                $order->update(['order_status' => 'cooking']);
            } elseif ($status == 'done') {
                $order->details()->whereIn('status', ['pending', 'cooking'])->update(['status' => 'done']);
                $order->update(['order_status' => 'served']);
                $isFinished = true;

                // Broadcast ke TV display — dibungkus try-catch agar tidak rollback jika Reverb tidak berjalan
                if (!Cache::has('audio_cooldown')) {
                    try {
                        $textToSpeak = "Pesanan atas nama, " . $order->customer_name . ", sudah siap untuk diambil.";
                        $displayData = [
                            'number' => '#' . explode('-', $order->invoice_no)[1],
                            'name'   => $order->customer_name
                        ];
                        Cache::put('audio_cooldown', true, 15);
                        broadcast(new CallQueueEvent($textToSpeak, $displayData, 'food'));
                    } catch (\Exception $broadcastErr) {
                        // Broadcast gagal (Reverb tidak berjalan) — abaikan, status tetap tersimpan
                        \Log::warning('Kitchen broadcast failed: ' . $broadcastErr->getMessage());
                    }
                }
            }

            DB::commit();
            return response()->json([
                'success' => true,
                'is_finished' => $isFinished,
                'table_name' => $order->table->table_number ?? 'Walk-in'
            ]);
        } catch (\Exception $e) {
            DB::rollback();
            return response()->json(['success' => false, 'error' => $e->getMessage()], 500);
        }
    }

    // 🔥 FUNGSI BARU: Panggil Ulang Makanan
    public function recallFood(Request $request)
    {
        // Cek Cooldown 15 Detik
        if (Cache::has('audio_cooldown')) {
            return response()->json([
                'success' => false,
                'message' => 'Harap tunggu! Sedang ada pemanggilan lain yang berlangsung.'
            ], 429);
        }

        $order = Order::findOrFail($request->order_id);

        try {
            $textToSpeak = "Panggilan ulang. Pesanan atas nama, " . $order->customer_name . ", sudah siap untuk diambil.";
            $displayData = [
                'number' => '#' . explode('-', $order->invoice_no)[1],
                'name'   => $order->customer_name
            ];
            Cache::put('audio_cooldown', true, 15);
            broadcast(new CallQueueEvent($textToSpeak, $displayData, 'food'));
            return response()->json(['success' => true, 'message' => 'Memanggil ulang pesanan ' . $order->customer_name]);
        } catch (\Exception $e) {
            \Log::warning('Recall broadcast failed: ' . $e->getMessage());
            return response()->json(['success' => false, 'message' => 'Gagal memanggil ulang: server broadcast tidak aktif.']);
        }
    }
}
