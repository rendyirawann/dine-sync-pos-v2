import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/utils/formatters.dart';
import '../../models/master.dart';
import '../../models/ops.dart';

// =====================================================================
// KERANGKA DAFTAR BERPAGINASI
// Dipakai bersama oleh modul keuangan, laporan, dan aktivitas profil
// supaya semua daftar berperilaku sama: load / refresh / loadMore.
// =====================================================================

/// State satu daftar berpaginasi.
class PagedState<T> {
  const PagedState({
    this.items = const [],
    this.summary = const {},
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.page = 1,
    this.error,
  });

  final List<T> items;

  /// Ringkasan opsional yang dikirim server bersama daftar (mis. `summary`
  /// pada endpoint laporan).
  final Map<String, dynamic> summary;

  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int page;
  final String? error;

  /// Benar-benar kosong (bukan sedang memuat / bukan error).
  bool get isEmpty => items.isEmpty && !isLoading && error == null;

  /// Nilai ringkasan sebagai angka (aman bila kunci tidak ada).
  double num$(String key) => J.toDouble(summary[key]);

  /// Nilai ringkasan sebagai bilangan bulat.
  int int$(String key) => J.toInt(summary[key]);

  PagedState<T> copyWith({
    List<T>? items,
    Map<String, dynamic>? summary,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? page,
    String? error,
    bool clearError = false,
  }) =>
      PagedState<T>(
        items: items ?? this.items,
        summary: summary ?? this.summary,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        page: page ?? this.page,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Notifier dasar untuk daftar berpaginasi.
///
/// Turunan cukup mengisi [path], [parse], dan (bila perlu) [queryFor],
/// [listKey], serta [summaryKey].
abstract class PagedNotifier<T> extends StateNotifier<PagedState<T>> {
  PagedNotifier(this.api) : super(PagedState<T>(isLoading: true)) {
    load();
  }

  final ApiClient api;

  /// Endpoint daftar, mis. `/expenses`.
  String get path;

  /// Ubah satu baris JSON menjadi model.
  T parse(Map<String, dynamic> json);

  /// Filter tambahan yang dikirim tiap permintaan.
  Map<String, dynamic> queryFor(int page) => const {};

  /// Kunci list bila server membungkusnya (mis. `orders`, `items`).
  String? get listKey => null;

  /// Kunci ringkasan bila ada (mis. `summary`).
  String? get summaryKey => null;

  int get perPage => 20;

  /// Muat ulang dari halaman pertama.
  Future<void> refresh() => load();

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final res = await _fetch(1);
      if (!mounted) return;
      state = PagedState<T>(
        items: _rowsOf(res, keys: [?listKey, 'data'])
            .map(parse)
            .toList(),
        summary: _summaryOf(res),
        hasMore: _hasMoreOf(res),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        error: e.message,
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;

    final next = state.page + 1;
    state = state.copyWith(isLoadingMore: true, clearError: true);

    try {
      final res = await _fetch(next);
      if (!mounted) return;
      state = state.copyWith(
        items: [
          ...state.items,
          ..._rowsOf(res, keys: [?listKey, 'data']).map(parse),
        ],
        summary: _summaryOf(res),
        hasMore: _hasMoreOf(res),
        page: next,
        isLoadingMore: false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoadingMore: false, error: e.message);
    }
  }

  Future<ApiResponse> _fetch(int page) => api.get(path, query: {
        ...queryFor(page),
        'page': page,
        'per_page': perPage,
      });

  Map<String, dynamic> _summaryOf(ApiResponse res) {
    final key = summaryKey;
    if (key == null) return const {};
    final v = res.asMap[key];
    return v is Map<String, dynamic> ? v : const {};
  }
}

/// Ambil list dari response, apa pun bentuk bungkusnya
/// (`data` berupa list, atau map yang memuat list di salah satu [keys]).
List<Map<String, dynamic>> _rowsOf(
  ApiResponse res, {
  List<String> keys = const ['data'],
}) {
  if (res.asList.isNotEmpty) return res.asList;
  for (final k in keys) {
    final rows = res.listAt(k);
    if (rows.isNotEmpty) return rows;
  }
  return const [];
}

/// `meta` bisa berada di akar response atau di dalam `data` — cek keduanya.
Map<String, dynamic> _metaOf(ApiResponse res) {
  if (res.meta != null) return res.meta!;
  final inner = res.asMap['meta'];
  return inner is Map<String, dynamic> ? inner : const {};
}

bool _hasMoreOf(ApiResponse res) => J.toBool(_metaOf(res)['has_more']);

// =====================================================================
// MODEL KHUSUS MODUL KEUANGAN
// =====================================================================

/// Target penjualan & batas pengeluaran untuk satu tanggal.
class DailySetting {
  const DailySetting({
    required this.target,
    required this.budget,
    required this.income,
    required this.spent,
    this.date,
  });

  final String? date;
  final double target;
  final double budget;
  final double income;
  final double spent;

  int get targetPercentage =>
      target <= 0 ? 0 : ((income / target) * 100).round();

  int get budgetPercentage => budget <= 0 ? 0 : ((spent / budget) * 100).round();

  factory DailySetting.fromJson(Map<String, dynamic> j) => DailySetting(
        date: J.toStr(j['date']),
        target: J.toDouble(j['target']),
        budget: J.toDouble(j['budget']),
        income: J.toDouble(j['income']),
        spent: J.toDouble(j['spent']),
      );

  static const empty =
      DailySetting(target: 0, budget: 0, income: 0, spent: 0);
}

/// Satu baris riwayat target & budget harian.
class BudgetHistoryRow {
  const BudgetHistoryRow({
    required this.target,
    required this.income,
    required this.targetPercentage,
    required this.budget,
    required this.spent,
    required this.budgetPercentage,
    this.date,
  });

  final String? date;
  final double target;
  final double income;
  final int targetPercentage;
  final double budget;
  final double spent;
  final int budgetPercentage;

  factory BudgetHistoryRow.fromJson(Map<String, dynamic> j) => BudgetHistoryRow(
        date: J.toStr(j['date']),
        target: J.toDouble(j['target']),
        income: J.toDouble(j['income']),
        targetPercentage: J.toInt(j['target_percentage']),
        budget: J.toDouble(j['budget']),
        spent: J.toDouble(j['spent']),
        budgetPercentage: J.toInt(j['budget_percentage']),
      );
}

/// Satu batch stok masuk (FIFO).
class StockBatch {
  const StockBatch({
    required this.id,
    required this.ingredientId,
    required this.ingredientName,
    required this.unit,
    required this.initialQuantity,
    required this.remainingQuantity,
    required this.buyPrice,
    required this.buyPriceTotal,
    this.supplierId,
    this.supplierName,
    this.entryDate,
    this.expiryDate,
  });

  final int id;
  final int ingredientId;
  final String ingredientName;
  final String unit;
  final int? supplierId;
  final String? supplierName;
  final double initialQuantity;
  final double remainingQuantity;

  /// Harga beli per satuan.
  final double buyPrice;

  /// Total nilai belanja batch ini.
  final double buyPriceTotal;
  final String? entryDate;
  final String? expiryDate;

  bool get isAvailable => remainingQuantity > 0;

  /// Kedaluwarsa kurang dari 7 hari dari sekarang (atau sudah lewat).
  bool get isExpiringSoon {
    final d = Fmt.parse(expiryDate);
    if (d == null) return false;
    return d.difference(DateTime.now()).inDays < 7;
  }

  factory StockBatch.fromJson(Map<String, dynamic> j) => StockBatch(
        id: J.toInt(j['id']),
        ingredientId: J.toInt(j['ingredient_id']),
        ingredientName: J.toStr(j['ingredient_name']) ?? 'Bahan Dihapus',
        unit: J.toStr(j['unit']) ?? '',
        supplierId: j['supplier_id'] == null ? null : J.toInt(j['supplier_id']),
        supplierName: J.toStr(j['supplier_name']),
        initialQuantity: J.toDouble(j['initial_quantity']),
        remainingQuantity: J.toDouble(j['remaining_quantity']),
        buyPrice: J.toDouble(j['buy_price']),
        buyPriceTotal: J.toDouble(j['buy_price_total']),
        entryDate: J.toStr(j['entry_date']),
        expiryDate: J.toStr(j['expiry_date']),
      );
}

/// Satu baris riwayat stock opname.
class OpnameHistoryRow {
  const OpnameHistoryRow({required this.id, this.date, this.notes, this.userName});

  final int id;
  final String? date;
  final String? notes;
  final String? userName;

  factory OpnameHistoryRow.fromJson(Map<String, dynamic> j) => OpnameHistoryRow(
        id: J.toInt(j['id']),
        date: J.toStr(j['date']),
        notes: J.toStr(j['notes']),
        userName: J.toStr(j['user_name']),
      );
}

/// Rincian selisih satu bahan pada sebuah opname.
class OpnameDetailRow {
  const OpnameDetailRow({
    required this.ingredientName,
    required this.unit,
    required this.systemQty,
    required this.physicalQty,
    required this.difference,
  });

  final String ingredientName;
  final String unit;
  final double systemQty;
  final double physicalQty;
  final double difference;

  /// success (lebih), danger (kurang), atau abu-abu (pas).
  String get tone => difference > 0
      ? 'success'
      : difference < 0
          ? 'danger'
          : 'muted';

  factory OpnameDetailRow.fromJson(Map<String, dynamic> j) => OpnameDetailRow(
        ingredientName: J.toStr(j['ingredient_name']) ?? 'Bahan Dihapus',
        unit: J.toStr(j['unit']) ?? '',
        systemQty: J.toDouble(j['system_qty']),
        physicalQty: J.toDouble(j['physical_qty']),
        difference: J.toDouble(j['difference']),
      );
}

/// Detail satu opname beserta rinciannya.
class OpnameDetail {
  const OpnameDetail({
    required this.id,
    required this.details,
    this.date,
    this.notes,
    this.userName,
  });

  final int id;
  final String? date;
  final String? notes;
  final String? userName;
  final List<OpnameDetailRow> details;

  factory OpnameDetail.fromJson(Map<String, dynamic> j) => OpnameDetail(
        id: J.toInt(j['id']),
        date: J.toStr(j['date']),
        notes: J.toStr(j['notes']),
        userName: J.toStr(j['user_name']),
        details: (j['details'] is List)
            ? (j['details'] as List)
                .whereType<Map<String, dynamic>>()
                .map(OpnameDetailRow.fromJson)
                .toList()
            : const [],
      );
}

// =====================================================================
// PROVIDER BACA
// =====================================================================

/// Target & budget untuk satu tanggal (`Y-m-d`).
final dailySettingProvider =
    FutureProvider.family<DailySetting, String>((ref, date) async {
  final res = await ref
      .watch(apiClientProvider)
      .get('/finance/daily-settings', query: {'date': date});
  return DailySetting.fromJson(res.asMap);
});

/// Daftar pengeluaran operasional (berpaginasi + pencarian).
class ExpenseListNotifier extends PagedNotifier<ExpenseModel> {
  ExpenseListNotifier(super.api);

  String _search = '';
  DateTime? _from;
  DateTime? _to;

  String get search => _search;
  DateTime? get dateFrom => _from;
  DateTime? get dateTo => _to;

  @override
  String get path => '/expenses';

  @override
  ExpenseModel parse(Map<String, dynamic> json) => ExpenseModel.fromJson(json);

  @override
  Map<String, dynamic> queryFor(int page) => {
        'search': _search,
        if (_from != null) 'date_from': Fmt.apiDate(_from!),
        if (_to != null) 'date_to': Fmt.apiDate(_to!),
      };

  void setSearch(String value) {
    final v = value.trim();
    if (v == _search) return;
    _search = v;
    load();
  }

  void setRange(DateTime? from, DateTime? to) {
    _from = from;
    _to = to;
    load();
  }
}

final expenseListProvider =
    StateNotifierProvider<ExpenseListNotifier, PagedState<ExpenseModel>>(
  (ref) => ExpenseListNotifier(ref.watch(apiClientProvider)),
);

/// Riwayat target vs pemasukan & budget vs pengeluaran per tanggal.
class BudgetHistoryNotifier extends PagedNotifier<BudgetHistoryRow> {
  BudgetHistoryNotifier(super.api);

  @override
  String get path => '/finance/budget-history';

  @override
  BudgetHistoryRow parse(Map<String, dynamic> json) =>
      BudgetHistoryRow.fromJson(json);
}

final budgetHistoryProvider =
    StateNotifierProvider<BudgetHistoryNotifier, PagedState<BudgetHistoryRow>>(
  (ref) => BudgetHistoryNotifier(ref.watch(apiClientProvider)),
);

/// Daftar batch stok masuk (FIFO) + filter pencarian / hanya yang tersedia.
class StockBatchListNotifier extends PagedNotifier<StockBatch> {
  StockBatchListNotifier(super.api);

  String _search = '';
  bool _onlyAvailable = false;
  int? _ingredientId;

  String get search => _search;
  bool get onlyAvailable => _onlyAvailable;
  int? get ingredientId => _ingredientId;

  @override
  String get path => '/stock-batches';

  @override
  StockBatch parse(Map<String, dynamic> json) => StockBatch.fromJson(json);

  @override
  Map<String, dynamic> queryFor(int page) => {
        'search': _search,
        if (_onlyAvailable) 'only_available': true,
        if (_ingredientId != null) 'ingredient_id': _ingredientId,
      };

  void setSearch(String value) {
    final v = value.trim();
    if (v == _search) return;
    _search = v;
    load();
  }

  void setOnlyAvailable(bool value) {
    if (value == _onlyAvailable) return;
    _onlyAvailable = value;
    load();
  }

  void setIngredient(int? id) {
    if (id == _ingredientId) return;
    _ingredientId = id;
    load();
  }
}

final stockBatchListProvider =
    StateNotifierProvider<StockBatchListNotifier, PagedState<StockBatch>>(
  (ref) => StockBatchListNotifier(ref.watch(apiClientProvider)),
);

/// Bahan + catatan opsional untuk form opname.
class OpnamePrepare {
  const OpnamePrepare({required this.ingredients, this.note});

  final List<IngredientModel> ingredients;
  final String? note;
}

/// Daftar bahan untuk form opname. Bentuk response ditangani defensif:
/// `data` bisa berupa list, atau map yang memuat list (+ `note`).
final opnamePrepareProvider = FutureProvider<OpnamePrepare>((ref) async {
  final res = await ref.watch(apiClientProvider).get('/stock-opname/prepare');

  return OpnamePrepare(
    ingredients: _rowsOf(res, keys: const ['ingredients', 'data', 'items'])
        .map(IngredientModel.fromJson)
        .toList(),
    note: J.toStr(res.asMap['note']),
  );
});

/// Riwayat stock opname (berpaginasi).
class OpnameHistoryNotifier extends PagedNotifier<OpnameHistoryRow> {
  OpnameHistoryNotifier(super.api);

  @override
  String get path => '/stock-opname/history';

  @override
  OpnameHistoryRow parse(Map<String, dynamic> json) =>
      OpnameHistoryRow.fromJson(json);
}

final opnameHistoryProvider =
    StateNotifierProvider<OpnameHistoryNotifier, PagedState<OpnameHistoryRow>>(
  (ref) => OpnameHistoryNotifier(ref.watch(apiClientProvider)),
);

/// Detail satu opname (dipakai bottom sheet rincian).
final opnameDetailProvider =
    FutureProvider.family<OpnameDetail, int>((ref, id) async {
  final res = await ref.watch(apiClientProvider).get('/stock-opname/$id');
  return OpnameDetail.fromJson(res.asMap);
});

/// Pilihan bahan untuk dropdown form.
final ingredientOptionsProvider =
    FutureProvider<List<IngredientModel>>((ref) async {
  final res = await ref
      .watch(apiClientProvider)
      .get('/ingredients', query: {'all': true});
  return _rowsOf(res).map(IngredientModel.fromJson).toList();
});

/// Pilihan supplier untuk dropdown form.
final supplierOptionsProvider =
    FutureProvider<List<SupplierModel>>((ref) async {
  final res = await ref
      .watch(apiClientProvider)
      .get('/suppliers', query: {'all': true});
  return _rowsOf(res).map(SupplierModel.fromJson).toList();
});

// =====================================================================
// AKSI TULIS (create / update / delete)
// Semua mengembalikan `message` dari server agar layar bisa menampilkannya.
// Kegagalan dilempar sebagai ApiException.
// =====================================================================

class FinanceRepo {
  const FinanceRepo(this._api);

  final ApiClient _api;

  Future<String> saveDailySetting({
    required DateTime date,
    required double target,
    required double budget,
  }) async {
    final res = await _api.post('/finance/daily-settings', data: {
      'date': Fmt.apiDate(date),
      'target': target,
      'budget': budget,
    });
    return res.message;
  }

  Future<String> createExpense({
    required DateTime date,
    required String category,
    required double amount,
    String? notes,
  }) async {
    final res = await _api.post('/expenses', data: {
      'date': Fmt.apiDate(date),
      'category': category,
      'amount': amount,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
    return res.message;
  }

  Future<String> updateExpense({
    required int id,
    required DateTime date,
    required String category,
    required double amount,
    String? notes,
  }) async {
    final res = await _api.put('/expenses/$id', data: {
      'date': Fmt.apiDate(date),
      'category': category,
      'amount': amount,
      'notes': notes ?? '',
    });
    return res.message;
  }

  Future<String> deleteExpense(int id) async {
    final res = await _api.delete('/expenses/$id');
    return res.message;
  }

  Future<String> createStockBatch({
    required int ingredientId,
    required double initialQuantity,
    required double buyPriceTotal,
    required DateTime entryDate,
    int? supplierId,
    DateTime? expiryDate,
  }) async {
    final res = await _api.post('/stock-batches', data: {
      'ingredient_id': ingredientId,
      'initial_quantity': initialQuantity,
      'buy_price_total': buyPriceTotal,
      'entry_date': Fmt.apiDate(entryDate),
      'supplier_id': ?supplierId,
      if (expiryDate != null) 'expiry_date': Fmt.apiDate(expiryDate),
    });
    return res.message;
  }

  Future<String> deleteStockBatch(int id) async {
    final res = await _api.delete('/stock-batches/$id');
    return res.message;
  }

  /// [items] hanya berisi baris yang benar-benar diisi kasir.
  Future<String> submitOpname({
    required List<Map<String, dynamic>> items,
    String? notes,
    DateTime? date,
  }) async {
    final res = await _api.post('/stock-opname', data: {
      'items': items,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (date != null) 'date': Fmt.apiDate(date),
    });
    return res.message;
  }
}

final financeRepoProvider =
    Provider<FinanceRepo>((ref) => FinanceRepo(ref.watch(apiClientProvider)));

/// Kunci tanggal hari ini untuk [dailySettingProvider].
String todayKey() => Fmt.apiDate(DateTime.now());
