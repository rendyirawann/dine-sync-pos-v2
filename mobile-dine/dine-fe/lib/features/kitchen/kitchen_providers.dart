import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/utils/formatters.dart';
import '../../models/order.dart';

/// Papan pesanan dapur — padanan Kitchen Display di web.
///
/// `active`  : order_status `pending` / `cooking` (server sengaja TIDAK memfilter
///             tanggal supaya pesanan kemarin yang belum selesai tetap muncul).
/// `completed`: order_status `served` / `completed` (3 hari terakhir).
class KitchenBoard {
  const KitchenBoard({
    required this.active,
    required this.completed,
    required this.activeCount,
    required this.completedCount,
  });

  final List<OrderModel> active;
  final List<OrderModel> completed;
  final int activeCount;
  final int completedCount;

  factory KitchenBoard.fromResponse(ApiResponse res) {
    final raw = res.asMap['counts'];
    final counts = raw is Map<String, dynamic> ? raw : const <String, dynamic>{};

    final active = res.listAt('active').map(OrderModel.fromJson).toList();
    final completed = res.listAt('completed').map(OrderModel.fromJson).toList();

    return KitchenBoard(
      active: active,
      completed: completed,
      activeCount: counts['active'] == null ? active.length : J.toInt(counts['active']),
      completedCount:
          counts['completed'] == null ? completed.length : J.toInt(counts['completed']),
    );
  }
}

/// Satu batch bahan yang masih bersisa (urut FEFO dari server).
class RecipeBatch {
  const RecipeBatch({
    required this.id,
    required this.label,
    required this.supplier,
    required this.remaining,
    this.expiry,
    this.arrival,
  });

  final int id;

  /// Teks siap pakai untuk dropdown, mis. `Toko Jaya (Masuk: 10/08/26 | Exp: 20/08/26) - Sisa: 4,00`
  final String label;
  final String supplier;
  final double remaining;
  final String? expiry;
  final String? arrival;

  factory RecipeBatch.fromJson(Map<String, dynamic> j) => RecipeBatch(
        id: J.toInt(j['id']),
        label: J.toStr(j['label']) ?? 'Batch #${J.toInt(j['id'])}',
        supplier: J.toStr(j['supplier']) ?? 'Manual',
        remaining: J.toDouble(j['remaining']),
        expiry: J.toStr(j['expiry']),
        arrival: J.toStr(j['arrival']),
      );
}

/// Satu bahan pada resep menu + daftar batch yang bisa dipilih juru masak.
class RecipeIngredient {
  const RecipeIngredient({
    required this.ingredientId,
    required this.name,
    required this.needed,
    required this.unit,
    required this.batches,
    this.suggestedBatch,
  });

  final int ingredientId;
  final String name;
  final double needed;
  final String unit;
  final List<RecipeBatch> batches;
  final int? suggestedBatch;

  bool get isOutOfStock => batches.isEmpty;

  /// Batch saran (FEFO) yang benar-benar ada di daftar — dipakai sebagai nilai awal dropdown.
  int? get defaultBatchId {
    if (batches.isEmpty) return null;
    final has = batches.any((b) => b.id == suggestedBatch);
    return has ? suggestedBatch : batches.first.id;
  }

  factory RecipeIngredient.fromJson(Map<String, dynamic> j) => RecipeIngredient(
        ingredientId: J.toInt(j['ingredient_id']),
        name: J.toStr(j['name']) ?? '-',
        needed: J.toDouble(j['needed']),
        unit: J.toStr(j['unit']) ?? '',
        batches: (j['batches'] is List)
            ? (j['batches'] as List)
                .whereType<Map<String, dynamic>>()
                .map(RecipeBatch.fromJson)
                .toList()
            : const [],
        suggestedBatch: j['suggested_batch'] == null ? null : J.toInt(j['suggested_batch']),
      );
}

/// Resep satu item pesanan (order_details.id) untuk sheet "Konfirmasi Bahan & Batch".
class ItemRecipe {
  const ItemRecipe({
    required this.menuName,
    required this.qty,
    required this.isStockDeducted,
    required this.recipes,
  });

  final String menuName;
  final int qty;

  /// True bila stok item ini sudah pernah dipotong (tidak akan dipotong dua kali).
  final bool isStockDeducted;
  final List<RecipeIngredient> recipes;

  factory ItemRecipe.fromJson(Map<String, dynamic> j) => ItemRecipe(
        menuName: J.toStr(j['menu_name']) ?? '-',
        qty: J.toInt(j['qty']),
        isStockDeducted: J.toBool(j['is_stock_deducted']),
        recipes: (j['recipes'] is List)
            ? (j['recipes'] as List)
                .whereType<Map<String, dynamic>>()
                .map(RecipeIngredient.fromJson)
                .toList()
            : const [],
      );
}

/// Hasil aksi dapur (ubah status item / pesanan).
class KitchenActionResult {
  const KitchenActionResult({
    required this.isFinished,
    required this.tableName,
    required this.message,
  });

  /// True bila SEMUA item pesanan sudah `done` (order menjadi `served`).
  final bool isFinished;
  final String tableName;
  final String message;
}

/// GET /kitchen/orders
final kitchenBoardProvider = FutureProvider<KitchenBoard>((ref) async {
  final res = await ref.watch(apiClientProvider).get('/kitchen/orders');
  return KitchenBoard.fromResponse(res);
});

/// GET /kitchen/items/{id}/recipe — autoDispose supaya sisa stok selalu segar
/// setiap kali sheet resep dibuka.
final itemRecipeProvider = FutureProvider.autoDispose.family<ItemRecipe, int>((ref, itemId) async {
  final res = await ref.watch(apiClientProvider).get('/kitchen/items/$itemId/recipe');
  return ItemRecipe.fromJson(res.asMap);
});

/// Kumpulan aksi tulis untuk layar dapur.
class KitchenRepo {
  const KitchenRepo(this._api);

  final ApiClient _api;

  /// POST /kitchen/items/{id}/status — `selections` = {ingredient_id: batch_id}.
  Future<KitchenActionResult> setItemStatus(
    int itemId,
    String status, {
    Map<int, int>? selections,
  }) async {
    final res = await _api.post('/kitchen/items/$itemId/status', data: {
      'status': status,
      if (selections != null && selections.isNotEmpty)
        // Kunci JSON wajib String.
        'selections': {for (final e in selections.entries) '${e.key}': e.value},
    });

    return _toResult(res);
  }

  /// POST /kitchen/orders/{id}/status — aksi massal "Masak Semua" / "Selesai Semua".
  Future<KitchenActionResult> setOrderStatus(int orderId, String status) async {
    final res = await _api.post('/kitchen/orders/$orderId/status', data: {'status': status});
    return _toResult(res);
  }

  /// POST /kitchen/orders/{id}/recall — 429 bila masih dalam cooldown 15 detik.
  Future<String> recall(int orderId) async {
    final res = await _api.post('/kitchen/orders/$orderId/recall');
    return res.message;
  }

  KitchenActionResult _toResult(ApiResponse res) {
    final map = res.asMap;

    return KitchenActionResult(
      isFinished: J.toBool(map['is_finished']),
      tableName: J.toStr(map['table_name']) ?? 'Walk-in',
      message: res.message,
    );
  }
}

final kitchenRepoProvider = Provider<KitchenRepo>(
  (ref) => KitchenRepo(ref.watch(apiClientProvider)),
);
