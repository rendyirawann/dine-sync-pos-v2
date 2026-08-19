import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/utils/formatters.dart';
import '../../models/master.dart';

// =====================================================================
// STATE + CONTROLLER GENERIK
// ---------------------------------------------------------------------
// Keenam layar Data Master (Menu, Kategori, Meja, Promo, Bahan, Supplier)
// memakai satu kelas controller yang sama supaya perilaku cari, refresh,
// dan "muat lebih banyak" persis seragam di seluruh modul.
// =====================================================================

/// Isi state daftar data master untuk satu layar.
class MasterListState<T> {
  MasterListState({
    List<T>? items,
    Map<String, dynamic>? filters,
    this.isLoading = true,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.page = 1,
    this.total = 0,
    this.search = '',
    this.error,
  })  : items = items ?? <T>[],
        filters = filters ?? <String, dynamic>{};

  /// Data yang sudah terkumpul (halaman 1..page).
  final List<T> items;

  /// Filter tambahan per layar (mis. `category_id`, `low_stock`).
  final Map<String, dynamic> filters;

  /// Muat awal / ganti kata kunci / ganti filter.
  final bool isLoading;

  /// Sedang mengambil halaman berikutnya.
  final bool isLoadingMore;

  final bool hasMore;
  final int page;
  final int total;
  final String search;

  /// Pesan error dari server/jaringan (sudah Bahasa Indonesia).
  final String? error;

  /// Benar-benar kosong (bukan karena sedang memuat atau gagal).
  bool get isEmpty => items.isEmpty && !isLoading && error == null;

  MasterListState<T> copyWith({
    List<T>? items,
    Map<String, dynamic>? filters,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? page,
    int? total,
    String? search,
    String? error,
    bool clearError = false,
  }) =>
      MasterListState<T>(
        items: items ?? this.items,
        filters: filters ?? this.filters,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        page: page ?? this.page,
        total: total ?? this.total,
        search: search ?? this.search,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Controller daftar + CRUD untuk satu endpoint apiResource.
///
/// Pemakaian di layar:
/// * `load()` / `refresh()` — ambil halaman 1.
/// * `loadMore()` — tambah halaman berikutnya (tombol "Muat lebih banyak").
/// * `setSearch()` / `setFilter()` — ganti kriteria lalu muat ulang dari halaman 1.
/// * `create()` / `update()` / `remove()` / `postAction()` — mutasi data.
///   Keempatnya MELEMPAR [ApiException] agar layar bisa menampilkan pesan
///   server apa adanya (termasuk 409 "data dipakai relasi lain" dan 422).
class MasterListController<T> extends StateNotifier<MasterListState<T>> {
  MasterListController({
    required this.api,
    required this.path,
    required this.parser,
    Map<String, dynamic>? filters,
    this.perPage = 20,
  }) : super(MasterListState<T>(filters: filters)) {
    load();
  }

  final ApiClient api;

  /// Path endpoint apiResource, mis. `/menus`.
  final String path;

  /// Pengubah satu baris JSON menjadi model.
  final T Function(Map<String, dynamic> json) parser;

  final int perPage;

  /// Penanda permintaan terakhir — hasil permintaan lama dibuang supaya
  /// hasil pencarian tidak saling menimpa (race condition saat mengetik).
  int _ticket = 0;

  Map<String, dynamic> _query(int page) {
    final search = state.search.trim();

    return <String, dynamic>{
      if (search.isNotEmpty) 'search': search,
      'per_page': perPage,
      'page': page,
      ...state.filters,
    };
  }

  /// Muat halaman pertama. [silent] dipakai saat pull-to-refresh & setelah
  /// mutasi agar tidak berkedip ke layar loading penuh.
  Future<void> load({bool silent = false}) async {
    final ticket = ++_ticket;

    state = state.copyWith(isLoading: !silent, isLoadingMore: false, clearError: true);

    try {
      final res = await api.get(path, query: _query(1));
      if (!mounted || ticket != _ticket) return;

      state = state.copyWith(
        items: res.asList.map(parser).toList(),
        isLoading: false,
        hasMore: res.hasMore,
        page: 1,
        total: (res.meta?['total'] as num?)?.toInt() ?? res.asList.length,
        clearError: true,
      );
    } on ApiException catch (e) {
      if (!mounted || ticket != _ticket) return;
      state = state.copyWith(isLoading: false, error: e.message);
    }
  }

  /// Dipakai `RefreshIndicator`.
  Future<void> refresh() => load(silent: true);

  /// Ambil halaman berikutnya. Mengembalikan pesan error bila gagal
  /// (null bila berhasil) supaya layar bisa menampilkan snackbar.
  Future<String?> loadMore() async {
    if (state.isLoadingMore || state.isLoading || !state.hasMore) return null;

    final ticket = _ticket;
    final next = state.page + 1;

    state = state.copyWith(isLoadingMore: true, clearError: true);

    try {
      final res = await api.get(path, query: _query(next));
      if (!mounted || ticket != _ticket) return null;

      state = state.copyWith(
        items: [...state.items, ...res.asList.map(parser)],
        isLoadingMore: false,
        hasMore: res.hasMore,
        page: next,
        total: (res.meta?['total'] as num?)?.toInt() ?? state.total,
      );
      return null;
    } on ApiException catch (e) {
      if (!mounted || ticket != _ticket) return e.message;
      state = state.copyWith(isLoadingMore: false);
      return e.message;
    }
  }

  /// Ganti kata kunci pencarian (layar yang mengatur debounce-nya).
  void setSearch(String value) {
    if (value == state.search) return;
    state = state.copyWith(search: value);
    load();
  }

  /// Set/hapus satu filter tambahan lalu muat ulang dari halaman 1.
  void setFilter(String key, dynamic value) {
    final next = Map<String, dynamic>.from(state.filters);
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }

    state = state.copyWith(filters: next);
    load();
  }

  Future<String> create(Map<String, dynamic> data) async {
    final res = await api.post(path, data: data);
    await load(silent: true);
    return res.message;
  }

  Future<String> update(int id, Map<String, dynamic> data) async {
    final res = await api.put('$path/$id', data: data);
    await load(silent: true);
    return res.message;
  }

  Future<String> remove(int id) async {
    final res = await api.delete('$path/$id');
    await load(silent: true);
    return res.message;
  }

  /// Aksi POST khusus pada satu item, mis. `postAction('7/toggle')` untuk promo.
  Future<String> postAction(String subPath, {Object? data}) async {
    final res = await api.post('$path/$subPath', data: data);
    await load(silent: true);
    return res.message;
  }
}

// =====================================================================
// PROVIDER DAFTAR PER LAYAR
// ---------------------------------------------------------------------
// autoDispose: keluar dari layar → state dibuang, masuk lagi → data segar.
// =====================================================================

final menuListProvider = StateNotifierProvider.autoDispose<
    MasterListController<MenuModel>, MasterListState<MenuModel>>(
  (ref) => MasterListController<MenuModel>(
    api: ref.watch(apiClientProvider),
    path: '/menus',
    parser: MenuModel.fromJson,
  ),
);

final categoryListProvider = StateNotifierProvider.autoDispose<
    MasterListController<CategoryModel>, MasterListState<CategoryModel>>(
  (ref) => MasterListController<CategoryModel>(
    api: ref.watch(apiClientProvider),
    path: '/categories',
    parser: CategoryModel.fromJson,
  ),
);

final tableListProvider = StateNotifierProvider.autoDispose<
    MasterListController<TableModel>, MasterListState<TableModel>>(
  (ref) => MasterListController<TableModel>(
    api: ref.watch(apiClientProvider),
    path: '/tables',
    parser: TableModel.fromJson,
  ),
);

final promoListProvider = StateNotifierProvider.autoDispose<
    MasterListController<PromoModel>, MasterListState<PromoModel>>(
  (ref) => MasterListController<PromoModel>(
    api: ref.watch(apiClientProvider),
    path: '/promos',
    parser: PromoModel.fromJson,
  ),
);

final ingredientListProvider = StateNotifierProvider.autoDispose<
    MasterListController<IngredientModel>, MasterListState<IngredientModel>>(
  (ref) => MasterListController<IngredientModel>(
    api: ref.watch(apiClientProvider),
    path: '/ingredients',
    parser: IngredientModel.fromJson,
  ),
);

final supplierListProvider = StateNotifierProvider.autoDispose<
    MasterListController<SupplierModel>, MasterListState<SupplierModel>>(
  (ref) => MasterListController<SupplierModel>(
    api: ref.watch(apiClientProvider),
    path: '/suppliers',
    parser: SupplierModel.fromJson,
  ),
);

// =====================================================================
// DATA PENDUKUNG FORM
// =====================================================================

/// Seluruh kategori tanpa paginasi — dipakai chip filter & dropdown form menu.
final categoryOptionsProvider = FutureProvider.autoDispose<List<CategoryModel>>((ref) async {
  final res = await ref.watch(apiClientProvider).get('/categories', query: {'all': true});
  return res.asList.map(CategoryModel.fromJson).toList();
});

// =====================================================================
// RESEP / BAHAN MENU
// =====================================================================

/// Satu baris resep menu: bahan + jumlah pemakaian per porsi.
class RecipeRow {
  const RecipeRow({
    required this.ingredientId,
    required this.quantity,
    this.ingredientName,
    this.unit,
  });

  final int ingredientId;
  final double quantity;
  final String? ingredientName;
  final String? unit;

  factory RecipeRow.fromJson(Map<String, dynamic> j) => RecipeRow(
        ingredientId: J.toInt(j['ingredient_id']),
        quantity: J.toDouble(j['quantity']),
        ingredientName: J.toStr(j['ingredient_name']),
        unit: J.toStr(j['unit']),
      );
}

/// Balasan `GET /menus/{id}/recipes`.
class MenuRecipeData {
  const MenuRecipeData({
    required this.menuName,
    required this.recipes,
    required this.ingredients,
  });

  final String menuName;
  final List<RecipeRow> recipes;

  /// Semua bahan yang bisa dipilih (sudah membawa satuan & stok).
  final List<IngredientModel> ingredients;

  factory MenuRecipeData.fromJson(Map<String, dynamic> j) {
    final menu = j['menu'];

    return MenuRecipeData(
      menuName: menu is Map<String, dynamic> ? (J.toStr(menu['name']) ?? '-') : '-',
      recipes: _rows(j['recipes']).map(RecipeRow.fromJson).toList(),
      ingredients: _rows(j['available_ingredients']).map(IngredientModel.fromJson).toList(),
    );
  }

  static List<Map<String, dynamic>> _rows(dynamic raw) =>
      raw is List ? raw.whereType<Map<String, dynamic>>().toList() : const [];
}

/// Ambil resep + daftar bahan yang tersedia untuk sebuah menu.
Future<MenuRecipeData> fetchMenuRecipes(ApiClient api, int menuId) async {
  final res = await api.get('/menus/$menuId/recipes');
  return MenuRecipeData.fromJson(res.asMap);
}

/// Simpan ulang seluruh resep sebuah menu (perilaku replace di server).
/// Kirim list kosong untuk mengosongkan resep.
Future<String> saveMenuRecipes(
  ApiClient api,
  int menuId,
  List<Map<String, dynamic>> recipes,
) async {
  final res = await api.post('/menus/$menuId/recipes', data: {'recipes': recipes});
  return res.message;
}
