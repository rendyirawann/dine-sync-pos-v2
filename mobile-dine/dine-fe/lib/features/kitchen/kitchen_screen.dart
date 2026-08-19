import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import '../../models/order.dart';
import '../home/home_shell.dart';
import 'kitchen_providers.dart';

/// Kitchen Display versi mobile: dua tab (sedang dibuat / sudah selesai),
/// aksi per item maupun per pesanan, dan pemilihan batch bahan sebelum memasak.
class KitchenScreen extends ConsumerStatefulWidget {
  const KitchenScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends ConsumerState<KitchenScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  /// Auto-refresh 30 detik (dapur harus selalu menampilkan data terbaru).
  Timer? _timer;

  /// Jangan pernah refresh saat dialog/bottom sheet terbuka — data di bawahnya
  /// bisa berubah dan membuat pilihan juru masak jadi tidak valid.
  bool _dialogOpen = false;

  /// Kunci aksi yang sedang dikirim ke server (tombolnya dinonaktifkan).
  final Set<String> _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);

    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || _dialogOpen || _busy.isNotEmpty) return;
      ref.invalidate(kitchenBoardProvider);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _tab.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- data

  void _refresh() => ref.invalidate(kitchenBoardProvider);

  Future<void> _reload() async {
    ref.invalidate(kitchenBoardProvider);
    try {
      await ref.read(kitchenBoardProvider.future);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  // ---------------------------------------------------------------- aksi

  /// Bungkus aksi tulis: kunci tombol, tangani ApiException, buka kunci lagi.
  Future<void> _guard(String key, Future<void> Function() body) async {
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));

    try {
      await body();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  /// Tahan auto-refresh selama dialog/sheet terbuka.
  Future<T?> _shield<T>(Future<T?> Function() open) async {
    _dialogOpen = true;
    try {
      return await open();
    } finally {
      _dialogOpen = false;
    }
  }

  void _announce(KitchenActionResult r) {
    if (!mounted) return;

    // Snackbar saling menimpa, jadi kabar "semua selesai" yang lebih penting
    // dipakai menggantikan pesan biasa dari server.
    showSnack(
      context,
      r.isFinished
          ? 'Semua pesanan untuk ${r.tableName} telah selesai! 🎉'
          : r.message,
    );

    _refresh();
  }

  Future<bool> _confirmProcess() async {
    final ok = await _shield<bool>(
      () => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Yakin?'),
          content: const Text('Pesanan akan diproses dan stok dipotong otomatis (FEFO).'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ya, Lanjut'),
            ),
          ],
        ),
      ),
    );

    return ok == true;
  }

  /// Item `pending` → buka sheet resep, pilih batch, lalu mulai masak.
  Future<void> _startItem(OrderDetailModel item) async {
    final selections = await _shield<Map<int, int>>(
      () => showModalBottomSheet<Map<int, int>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _RecipeSheet(itemId: item.id),
      ),
    );

    if (selections == null || !mounted) return;

    await _guard('item-${item.id}', () async {
      final r = await ref.read(kitchenRepoProvider).setItemStatus(
            item.id,
            'cooking',
            selections: selections,
          );
      _announce(r);
    });
  }

  /// Item `cooking` → tandai siap disajikan.
  Future<void> _finishItem(OrderDetailModel item) => _guard('item-${item.id}', () async {
        final r = await ref.read(kitchenRepoProvider).setItemStatus(item.id, 'done');
        _announce(r);
      });

  /// Aksi massal satu pesanan: `cooking` (Masak Semua) atau `done` (Selesai Semua).
  Future<void> _bulk(OrderModel order, String status) async {
    if (!await _confirmProcess() || !mounted) return;

    await _guard('order-${order.id}', () async {
      final r = await ref.read(kitchenRepoProvider).setOrderStatus(order.id, status);
      _announce(r);
    });
  }

  Future<void> _recall(OrderModel order) => _guard('recall-${order.id}', () async {
        final message = await ref.read(kitchenRepoProvider).recall(order.id);
        if (!mounted) return;
        showSnack(context, message);
      });

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final board = ref.watch(kitchenBoardProvider);

    final activeCount = board.maybeWhen(data: (b) => b.activeCount, orElse: () => 0);
    final doneCount = board.maybeWhen(data: (b) => b.completedCount, orElse: () => 0);

    final refreshButton = IconButton(
      tooltip: 'Muat Ulang',
      onPressed: _refresh,
      icon: const Icon(Icons.refresh_rounded),
    );

    return Scaffold(
      backgroundColor: p.appBg,
      appBar: widget.embedded
          ? TenantAppBar(title: 'Dapur', actions: [refreshButton])
          : AppBar(title: const Text('Dapur'), actions: [refreshButton]),
      body: Column(
        children: [
          Material(
            color: p.surface,
            child: TabBar(
              controller: _tab,
              tabs: [
                _countTab('Sedang Dibuat', activeCount, 'danger'),
                _countTab('Sudah Selesai', doneCount, 'success'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _boardView(board, completed: false),
                _boardView(board, completed: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _countTab(String label, int count, String tone) => Tab(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            SizedBox(width: sp(1.5)),
            StatusBadge(text: '$count', tone: tone, dense: true),
          ],
        ),
      );

  Widget _boardView(AsyncValue<KitchenBoard> board, {required bool completed}) {
    return AsyncView<KitchenBoard>(
      value: board,
      onRetry: _refresh,
      builder: (b) {
        final orders = completed ? b.completed : b.active;

        return RefreshIndicator(
          onRefresh: _reload,
          child: orders.isEmpty
              ? ListView(
                  padding: EdgeInsets.fromLTRB(sp(4), sp(8), sp(4), sp(10)),
                  children: [
                    EmptyState(
                      message: completed
                          ? 'Belum ada pesanan yang disiapkan.'
                          : 'Dapur sedang santai. Belum ada antrian pesanan.',
                      icon: completed ? Icons.room_service_outlined : Icons.coffee_rounded,
                    ),
                  ],
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(sp(4), sp(4), sp(4), sp(10)),
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => SizedBox(height: sp(3)),
                  itemBuilder: (_, i) => _orderCard(orders[i], completed: completed),
                ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- kartu

  Widget _orderCard(OrderModel order, {required bool completed}) {
    final p = context.palette;
    final tone = completed ? 'success' : (order.orderStatus == 'cooking' ? 'primary' : 'warning');

    return AppCard(
      padding: EdgeInsets.zero,
      borderColor: completed ? p.success.withValues(alpha: .35) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- Kepala: meja, pelanggan, dan umur pesanan ---
          Container(
            color: p.softOf(tone),
            padding: EdgeInsets.symmetric(horizontal: sp(4), vertical: sp(3)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.tableNumber ?? 'Walk-in',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: p.gray900,
                        ),
                      ),
                      SizedBox(height: sp(0.5)),
                      Text(
                        '${order.customerName ?? 'Tanpa Nama'} • #${order.invoiceNo}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: p.textMuted),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: sp(2)),
                StatusBadge(
                  text: Fmt.ago(order.createdAt),
                  tone: tone,
                  dense: true,
                  icon: Icons.schedule_rounded,
                ),
              ],
            ),
          ),

          // --- Isi: daftar item + aksi ---
          Padding(
            padding: EdgeInsets.fromLTRB(sp(4), sp(3), sp(4), sp(3.5)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in order.details) _itemRow(item, completed: completed),
                SizedBox(height: sp(1.5)),
                Divider(height: sp(4), color: p.border),
                _footer(order, completed: completed),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemRow(OrderDetailModel item, {required bool completed}) {
    final p = context.palette;
    final struck = completed || item.isDone;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: sp(1)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.qty}x ${item.menuName}',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    color: struck ? p.textMuted : p.gray900,
                    decoration: struck ? TextDecoration.lineThrough : null,
                    decorationColor: p.textMuted,
                  ),
                ),
                if (item.notes != null && item.notes!.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: sp(0.5)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.sticky_note_2_outlined, size: 11, color: p.danger),
                        SizedBox(width: sp(1)),
                        Expanded(
                          child: Text(
                            item.notes!,
                            style: TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: p.danger,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(width: sp(2)),
          _itemAction(item, completed: completed),
        ],
      ),
    );
  }

  Widget _itemAction(OrderDetailModel item, {required bool completed}) {
    if (completed || item.isDone) {
      return const StatusBadge(
        text: 'Siap',
        tone: 'success',
        dense: true,
        icon: Icons.check_circle_rounded,
      );
    }

    final locked = _busy.contains('item-${item.id}');

    if (item.isCooking) {
      return _roundButton(
        icon: Icons.check_rounded,
        tone: 'primary',
        tooltip: 'Selesai & Sajikan',
        onPressed: locked ? null : () => _finishItem(item),
      );
    }

    // status pending
    return _roundButton(
      icon: Icons.local_fire_department_rounded,
      tone: 'warning',
      tooltip: 'Mulai Masak',
      onPressed: locked ? null : () => _startItem(item),
    );
  }

  Widget _roundButton({
    required IconData icon,
    required String tone,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    final p = context.palette;

    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        backgroundColor: p.softOf(tone),
        foregroundColor: p.solidOf(tone),
        disabledBackgroundColor: p.gray200,
        disabledForegroundColor: p.gray500,
        shape: const CircleBorder(),
        minimumSize: Size(sp(9), sp(9)),
        padding: EdgeInsets.all(sp(2)),
      ),
    );
  }

  Widget _footer(OrderModel order, {required bool completed}) {
    if (completed) {
      final locked = _busy.contains('recall-${order.id}');

      return _lightButton(
        label: 'Panggil Ulang ke TV',
        icon: Icons.campaign_rounded,
        tone: 'info',
        onPressed: locked ? null : () => _recall(order),
      );
    }

    final locked = _busy.contains('order-${order.id}');
    final hasPending = order.hasPendingItems;

    return _lightButton(
      label: hasPending ? 'Masak Semua' : 'Selesai Semua',
      icon: hasPending ? Icons.local_fire_department_rounded : Icons.done_all_rounded,
      tone: hasPending ? 'warning' : 'primary',
      onPressed: locked ? null : () => _bulk(order, hasPending ? 'cooking' : 'done'),
    );
  }

  Widget _lightButton({
    required String label,
    required IconData icon,
    required String tone,
    required VoidCallback? onPressed,
  }) {
    final p = context.palette;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: p.softOf(tone),
          foregroundColor: p.solidOf(tone),
          disabledBackgroundColor: p.gray200,
          disabledForegroundColor: p.gray500,
          elevation: 0,
          minimumSize: Size(0, sp(10.5)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// Sheet "Konfirmasi Bahan & Batch" — dibuka sebelum item mulai dimasak.
/// Ditutup dengan `Navigator.pop(map)` berisi {ingredient_id: batch_id};
/// `null` berarti juru masak membatalkan.
class _RecipeSheet extends ConsumerStatefulWidget {
  const _RecipeSheet({required this.itemId});

  final int itemId;

  @override
  ConsumerState<_RecipeSheet> createState() => _RecipeSheetState();
}

class _RecipeSheetState extends ConsumerState<_RecipeSheet> {
  /// Pilihan batch juru masak: ingredient_id -> batch_id.
  /// Bahan yang tidak diubah manual memakai saran FEFO dari server.
  final Map<int, int> _selected = <int, int>{};

  Map<int, int> _payload(ItemRecipe r) {
    final out = <int, int>{};

    for (final ing in r.recipes) {
      final chosen = _selected[ing.ingredientId] ?? ing.defaultBatchId;
      if (chosen != null) out[ing.ingredientId] = chosen;
    }

    return out;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final recipe = ref.watch(itemRecipeProvider(widget.itemId));

    return Padding(
      padding: EdgeInsets.fromLTRB(sp(5), sp(3), sp(5), sp(5)),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                height: 4,
                width: sp(12),
                decoration: BoxDecoration(
                  color: p.gray300,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            SizedBox(height: sp(4)),
            AsyncView<ItemRecipe>(
              value: recipe,
              onRetry: () => ref.invalidate(itemRecipeProvider(widget.itemId)),
              builder: (r) {
                if (r.isStockDeducted) return _alreadyDeducted(r);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionHeader(
                      title: 'Konfirmasi Bahan & Batch',
                      subtitle: '${r.menuName} · ${r.qty}x',
                      icon: Icons.inventory_2_outlined,
                    ),
                    SizedBox(height: sp(4)),
                    if (r.recipes.isEmpty)
                      const EmptyState(
                        message: 'Menu ini tidak punya resep bahan. Stok tidak akan dipotong.',
                        icon: Icons.no_food_outlined,
                        compact: true,
                      )
                    else
                      for (final ing in r.recipes) _ingredientField(ing),
                    SizedBox(height: sp(4)),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Batal'),
                          ),
                        ),
                        SizedBox(width: sp(3)),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.pop(context, _payload(r)),
                            icon: const Icon(Icons.local_fire_department_rounded, size: 18),
                            label: const Text('Mulai Masak & Potong Stok'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: p.warning,
                              foregroundColor: Colors.white,
                              textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _alreadyDeducted(ItemRecipe r) {
    final p = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          color: p.successLight,
          borderColor: Colors.transparent,
          child: Row(
            children: [
              Icon(Icons.verified_rounded, size: 22, color: p.success),
              SizedBox(width: sp(3)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Stok untuk menu ini sudah dipotong.',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: p.success,
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: sp(0.5)),
                    Text(
                      '${r.menuName} · ${r.qty}x',
                      style: TextStyle(fontSize: 11.5, color: p.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: sp(4)),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    );
  }

  Widget _ingredientField(RecipeIngredient ing) {
    final p = context.palette;

    return Padding(
      padding: EdgeInsets.only(bottom: sp(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${ing.name} (Butuh: ${Fmt.qty(ing.needed)} ${ing.unit})',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.gray800),
          ),
          SizedBox(height: sp(1.5)),
          if (ing.isOutOfStock)
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: sp(3.5), vertical: sp(3)),
              decoration: BoxDecoration(
                color: p.dangerLight,
                borderRadius: BorderRadius.circular(AppRadius.base),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, size: 16, color: p.danger),
                  SizedBox(width: sp(2)),
                  Expanded(
                    child: Text(
                      'STOK HABIS!',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: p.danger,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            DropdownButtonFormField<int>(
              initialValue: ing.defaultBatchId,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true),
              style: TextStyle(fontSize: 12.5, color: p.gray800),
              items: [
                for (final b in ing.batches)
                  DropdownMenuItem<int>(
                    value: b.id,
                    child: Text(
                      b.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _selected[ing.ingredientId] = v);
              },
            ),
        ],
      ),
    );
  }
}
