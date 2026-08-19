import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import '../../models/master.dart';
import '../../models/order.dart';
import '../finance/finance_providers.dart';

// ====================================================================
// MODEL & PROVIDER LOKAL LAPORAN
// ====================================================================

/// Satu baris laporan menu terlaris.
class ReportItemRow {
  const ReportItemRow({
    required this.menuId,
    required this.menuName,
    required this.discountPercent,
    required this.totalQty,
    required this.totalRevenue,
    required this.totalHpp,
    this.categoryName,
  });

  final int menuId;
  final String menuName;
  final String? categoryName;
  final int discountPercent;
  final int totalQty;
  final double totalRevenue;
  final double totalHpp;

  factory ReportItemRow.fromJson(Map<String, dynamic> j) => ReportItemRow(
        menuId: J.toInt(j['menu_id']),
        menuName: J.toStr(j['menu_name']) ?? 'Menu Dihapus',
        categoryName: J.toStr(j['category_name']),
        discountPercent: J.toInt(j['discount_percent']),
        totalQty: J.toInt(j['total_qty']),
        totalRevenue: J.toDouble(j['total_revenue']),
        totalHpp: J.toDouble(j['total_hpp']),
      );
}

/// Laporan penjualan (nota per nota) + ringkasan omzet & laba.
class SalesReportNotifier extends PagedNotifier<OrderModel> {
  SalesReportNotifier(super.api);

  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now();
  String _method = 'all';
  String _search = '';

  String get method => _method;

  @override
  String get path => '/reports/sales';

  @override
  String? get listKey => 'orders';

  @override
  String? get summaryKey => 'summary';

  @override
  OrderModel parse(Map<String, dynamic> json) => OrderModel.fromJson(json);

  @override
  Map<String, dynamic> queryFor(int page) => {
        'start_date': Fmt.apiDate(_start),
        'end_date': Fmt.apiDate(_end),
        'payment_method': _method,
        'search': _search,
      };

  void setRange(DateTime start, DateTime end) {
    _start = start;
    _end = end;
    load();
  }

  void setMethod(String value) {
    if (value == _method) return;
    _method = value;
    load();
  }

  void setSearch(String value) {
    final v = value.trim();
    if (v == _search) return;
    _search = v;
    load();
  }
}

final salesReportProvider =
    StateNotifierProvider<SalesReportNotifier, PagedState<OrderModel>>(
  (ref) => SalesReportNotifier(ref.watch(apiClientProvider)),
);

/// Laporan menu terlaris + ringkasan porsi & omzet.
class ItemReportNotifier extends PagedNotifier<ReportItemRow> {
  ItemReportNotifier(super.api);

  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now();
  String _categoryId = 'all';

  String get categoryId => _categoryId;

  @override
  String get path => '/reports/items';

  @override
  String? get listKey => 'items';

  @override
  String? get summaryKey => 'summary';

  @override
  int get perPage => 30;

  @override
  ReportItemRow parse(Map<String, dynamic> json) => ReportItemRow.fromJson(json);

  @override
  Map<String, dynamic> queryFor(int page) => {
        'start_date': Fmt.apiDate(_start),
        'end_date': Fmt.apiDate(_end),
        'category_id': _categoryId,
      };

  void setRange(DateTime start, DateTime end) {
    _start = start;
    _end = end;
    load();
  }

  void setCategory(String value) {
    if (value == _categoryId) return;
    _categoryId = value;
    load();
  }
}

final itemReportProvider =
    StateNotifierProvider<ItemReportNotifier, PagedState<ReportItemRow>>(
  (ref) => ItemReportNotifier(ref.watch(apiClientProvider)),
);

/// Kategori untuk dropdown filter menu terlaris.
final reportCategoriesProvider = FutureProvider<List<CategoryModel>>((ref) async {
  final res = await ref
      .watch(apiClientProvider)
      .get('/categories', query: {'all': true});
  final rows = res.asList.isNotEmpty ? res.asList : res.listAt('data');
  return rows.map(CategoryModel.fromJson).toList();
});

// ====================================================================
// LAYAR LAPORAN
// ====================================================================

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  late DateTime _start;
  late DateTime _end;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, now.day);
    _end = _start;
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _tab.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      ref.read(salesReportProvider.notifier).setSearch(value);
    });
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _start, end: _end),
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      helpText: 'Pilih Rentang Tanggal',
      cancelText: 'Batal',
      confirmText: 'Terapkan',
      saveText: 'Terapkan',
    );

    if (picked == null || !mounted) return;

    setState(() {
      _start = picked.start;
      _end = picked.end;
    });

    ref.read(salesReportProvider.notifier).setRange(_start, _end);
    ref.read(itemReportProvider.notifier).setRange(_start, _end);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isSalesTab = _tab.index == 0;

    return Scaffold(
      backgroundColor: p.appBg,
      appBar: AppBar(
        title: const Text('Laporan'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Penjualan'),
            Tab(text: 'Menu Terlaris'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(sp(4), sp(4), sp(4), sp(2)),
            child: AppCard(
              padding: EdgeInsets.all(sp(3.5)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickRange,
                    icon: const Icon(Icons.date_range_rounded, size: 18),
                    label: Text('${Fmt.date(_start)} - ${Fmt.date(_end)}'),
                  ),
                  SizedBox(height: sp(2.5)),
                  if (isSalesTab) const _MethodFilter() else const _CategoryFilter(),
                  if (isSalesTab) ...[
                    SizedBox(height: sp(2.5)),
                    SearchField(
                      controller: _searchCtrl,
                      hint: 'Cari no. nota / pelanggan...',
                      onChanged: _onSearch,
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: const [_SalesTab(), _ItemsTab()],
            ),
          ),
        ],
      ),
    );
  }
}

// ====================================================================
// FILTER
// ====================================================================

class _MethodFilter extends ConsumerWidget {
  const _MethodFilter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Dibaca dari notifier agar nilai filter tetap saat pindah tab.
    ref.watch(salesReportProvider);
    final notifier = ref.read(salesReportProvider.notifier);

    return DropdownButtonFormField<String>(
      initialValue: notifier.method,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Metode Pembayaran', isDense: true),
      items: const [
        DropdownMenuItem(value: 'all', child: Text('Semua Metode')),
        DropdownMenuItem(value: 'cash', child: Text('Tunai (Cash)')),
      ],
      onChanged: (v) => notifier.setMethod(v ?? 'all'),
    );
  }
}

class _CategoryFilter extends ConsumerWidget {
  const _CategoryFilter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(itemReportProvider);
    final notifier = ref.read(itemReportProvider.notifier);
    final categories = ref.watch(reportCategoriesProvider);

    return DropdownButtonFormField<String>(
      initialValue: notifier.categoryId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Kategori Menu', isDense: true),
      items: [
        const DropdownMenuItem(value: 'all', child: Text('Semua Kategori')),
        for (final CategoryModel c in categories.value ?? const [])
          DropdownMenuItem(value: '${c.id}', child: Text(c.name)),
      ],
      onChanged: (v) => notifier.setCategory(v ?? 'all'),
    );
  }
}

// ====================================================================
// TAB PENJUALAN
// ====================================================================

class _SalesTab extends ConsumerWidget {
  const _SalesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final st = ref.watch(salesReportProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(salesReportProvider.notifier).refresh(),
      child: ListView(
        padding: EdgeInsets.fromLTRB(sp(4), sp(2), sp(4), sp(10)),
        children: [
          GridView.count(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: sp(3),
            crossAxisSpacing: sp(3),
            childAspectRatio: 1.75,
            children: [
              StatCard(
                label: 'Total Nota',
                value: '${st.int$('total_orders')} nota',
                tone: 'primary',
                compact: true,
                icon: Icons.receipt_long_outlined,
              ),
              StatCard(
                label: 'Total Diskon',
                value: Fmt.rupiah(st.num$('total_discount')),
                tone: 'danger',
                compact: true,
                icon: Icons.local_offer_outlined,
              ),
              StatCard(
                label: 'Total Modal (HPP)',
                value: Fmt.rupiah(st.num$('total_hpp')),
                tone: 'warning',
                compact: true,
                icon: Icons.inventory_2_outlined,
              ),
              StatCard(
                label: 'Pendapatan Bersih',
                value: Fmt.rupiah(st.num$('total_revenue')),
                tone: 'success',
                compact: true,
                icon: Icons.savings_outlined,
              ),
            ],
          ),
          SizedBox(height: sp(4)),
          const SectionHeader(
            title: 'Rincian Nota',
            subtitle: 'Semua transaksi pada rentang terpilih',
            icon: Icons.list_alt_rounded,
          ),
          SizedBox(height: sp(3)),
          if (st.isLoading && st.items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          else if (st.error != null && st.items.isEmpty)
            ErrorView(
              message: st.error!,
              onRetry: () => ref.read(salesReportProvider.notifier).refresh(),
            )
          else if (st.items.isEmpty)
            const EmptyState(
              message: 'Belum ada data pada rentang ini.',
              icon: Icons.receipt_long_outlined,
            )
          else ...[
            for (final o in st.items)
              Padding(
                padding: EdgeInsets.only(bottom: sp(3)),
                child: AppCard(
                  padding: EdgeInsets.all(sp(4)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '#${o.invoiceNo}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: p.primary,
                              ),
                            ),
                            SizedBox(height: sp(0.5)),
                            Text(
                              Fmt.dateTime(o.createdAt),
                              style: TextStyle(fontSize: 11.5, color: p.textMuted),
                            ),
                            SizedBox(height: sp(1)),
                            Text(
                              '${o.customerName ?? 'Pelanggan'} · ${o.tableNumber ?? 'Walk-in'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: p.gray700,
                              ),
                            ),
                            SizedBox(height: sp(2)),
                            o.paymentMethod == 'cash'
                                ? const StatusBadge(
                                    text: 'CASH',
                                    tone: 'success',
                                    dense: true,
                                  )
                                : StatusBadge(
                                    text: (o.paymentMethod ?? 'belum bayar').toUpperCase(),
                                    tone: 'info',
                                    dense: true,
                                  ),
                          ],
                        ),
                      ),
                      SizedBox(width: sp(2)),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            Fmt.rupiah(o.grandTotal),
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: p.success,
                            ),
                          ),
                          if (o.discountAmount > 0) ...[
                            SizedBox(height: sp(0.5)),
                            Text(
                              '- ${Fmt.rupiah(o.discountAmount)}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: p.danger,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (st.hasMore)
              OutlinedButton.icon(
                onPressed: st.isLoadingMore
                    ? null
                    : () => ref.read(salesReportProvider.notifier).loadMore(),
                icon: st.isLoadingMore
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more_rounded, size: 18),
                label: const Text('Muat lebih banyak'),
              ),
          ],
        ],
      ),
    );
  }
}

// ====================================================================
// TAB MENU TERLARIS
// ====================================================================

class _ItemsTab extends ConsumerWidget {
  const _ItemsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final st = ref.watch(itemReportProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(itemReportProvider.notifier).refresh(),
      child: ListView(
        padding: EdgeInsets.fromLTRB(sp(4), sp(2), sp(4), sp(10)),
        children: [
          GridView.count(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: sp(3),
            crossAxisSpacing: sp(3),
            childAspectRatio: 1.05,
            children: [
              StatCard(
                label: 'Total Porsi',
                value: '${st.int$('total_items_sold')} porsi',
                tone: 'warning',
                compact: true,
              ),
              StatCard(
                label: 'Total Modal (HPP)',
                value: Fmt.rupiah(st.num$('total_hpp')),
                tone: 'danger',
                compact: true,
              ),
              StatCard(
                label: 'Total Omzet',
                value: Fmt.rupiah(st.num$('total_revenue')),
                tone: 'success',
                compact: true,
              ),
            ],
          ),
          SizedBox(height: sp(4)),
          const SectionHeader(
            title: 'Peringkat Menu',
            subtitle: 'Diurutkan dari porsi terbanyak',
            icon: Icons.emoji_events_outlined,
          ),
          SizedBox(height: sp(3)),
          if (st.isLoading && st.items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          else if (st.error != null && st.items.isEmpty)
            ErrorView(
              message: st.error!,
              onRetry: () => ref.read(itemReportProvider.notifier).refresh(),
            )
          else if (st.items.isEmpty)
            const EmptyState(
              message: 'Belum ada data pada rentang ini.',
              icon: Icons.restaurant_menu_outlined,
            )
          else ...[
            for (var i = 0; i < st.items.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: sp(3)),
                child: AppCard(
                  padding: EdgeInsets.all(sp(3.5)),
                  child: Row(
                    children: [
                      Container(
                        height: sp(8),
                        width: sp(8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: p.primaryLight,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: p.primary,
                          ),
                        ),
                      ),
                      SizedBox(width: sp(3)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              st.items[i].menuName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: p.gray900,
                              ),
                            ),
                            SizedBox(height: sp(1)),
                            Wrap(
                              spacing: sp(1.5),
                              runSpacing: sp(1),
                              children: [
                                StatusBadge(
                                  text: st.items[i].categoryName ?? 'Tanpa Kategori',
                                  tone: 'primary',
                                  dense: true,
                                ),
                                if (st.items[i].discountPercent > 0)
                                  StatusBadge(
                                    text: 'Diskon ${st.items[i].discountPercent}%',
                                    tone: 'danger',
                                    dense: true,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: sp(2)),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${st.items[i].totalQty} Porsi',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: p.gray900,
                            ),
                          ),
                          SizedBox(height: sp(0.5)),
                          Text(
                            Fmt.rupiah(st.items[i].totalRevenue),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: p.success,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (st.hasMore)
              OutlinedButton.icon(
                onPressed: st.isLoadingMore
                    ? null
                    : () => ref.read(itemReportProvider.notifier).loadMore(),
                icon: st.isLoadingMore
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more_rounded, size: 18),
                label: const Text('Muat lebih banyak'),
              ),
          ],
        ],
      ),
    );
  }
}
