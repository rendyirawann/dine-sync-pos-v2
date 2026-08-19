import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/utils/formatters.dart';
import '../../models/ops.dart';

/// Status shift kasir saat ini.
///
/// `cashSales` & `expectedCash` diambil dari nilai hitungan server (bukan kolom
/// shift), karena kolomnya baru terisi saat shift ditutup.
class ShiftStatus {
  const ShiftStatus({
    required this.cashSales,
    required this.expectedCash,
    required this.isFirstShiftOfDay,
    this.shift,
  });

  final ShiftModel? shift;
  final double cashSales;
  final double expectedCash;

  /// True bila belum ada target/budget harian hari ini → wajib diisi saat buka shift.
  final bool isFirstShiftOfDay;

  bool get isOpen => shift != null && shift!.isOpen;

  factory ShiftStatus.fromJson(Map<String, dynamic> j) {
    final raw = j['shift'];

    return ShiftStatus(
      shift: raw is Map<String, dynamic> ? ShiftModel.fromJson(raw) : null,
      cashSales: J.toDouble(j['cash_sales']),
      expectedCash: J.toDouble(j['expected_cash']),
      isFirstShiftOfDay: J.toBool(j['is_first_shift_of_day']),
    );
  }
}

/// GET /shifts/current
final currentShiftProvider = FutureProvider<ShiftStatus>((ref) async {
  final res = await ref.watch(apiClientProvider).get('/shifts/current');
  return ShiftStatus.fromJson(res.asMap);
});

/// GET /shifts/history — halaman pertama saja (cukup untuk ringkasan mobile).
final shiftHistoryProvider = FutureProvider<List<ShiftModel>>((ref) async {
  final res = await ref.watch(apiClientProvider).get('/shifts/history');
  return res.asList.map(ShiftModel.fromJson).toList();
});

/// Aksi tulis buka/tutup shift.
class ShiftRepo {
  const ShiftRepo(this._api);

  final ApiClient _api;

  /// POST /shifts/open — `targetPenjualan` & `dailyBudget` wajib bila shift
  /// pertama hari ini.
  Future<String> open({
    required double startingCash,
    double? targetPenjualan,
    double? dailyBudget,
  }) async {
    final res = await _api.post('/shifts/open', data: {
      'starting_cash': startingCash,
      // Hanya dikirim bila shift pertama hari ini (server memvalidasinya wajib).
      'target_penjualan': ?targetPenjualan,
      'daily_budget': ?dailyBudget,
    });

    return res.message;
  }

  /// POST /shifts/{id}/close — 409 bila masih ada pesanan/meja menggantung.
  Future<String> close({required int id, required double actualCash}) async {
    final res = await _api.post('/shifts/$id/close', data: {'actual_cash': actualCash});
    return res.message;
  }
}

final shiftRepoProvider = Provider<ShiftRepo>(
  (ref) => ShiftRepo(ref.watch(apiClientProvider)),
);
