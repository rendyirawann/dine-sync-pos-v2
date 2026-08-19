import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import '../../models/master.dart';
import 'finance_providers.dart';

/// Stock opname: input stok fisik per bahan (sistem menghitung selisih)
/// dan riwayat opname yang pernah dilakukan.
class StockOpnameScreen extends ConsumerStatefulWidget {
  const StockOpnameScreen({super.key});

  @override
  ConsumerState<StockOpnameScreen> createState() => _StockOpnameScreenState();
}

class _StockOpnameScreenState extends ConsumerState<StockOpnameScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  /// Controller input stok fisik per id bahan.
  final _ctrls = <int, TextEditingController>{};
  final _notesCtrl = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _notesCtrl.dispose();
    _tab.dispose();
    super.dispose();
  }

  TextEditingController _ctrlFor(int id) =>
      _ctrls.putIfAbsent(id, TextEditingController.new);

  void _resetForm() {
    for (final c in _ctrls.values) {
      c.clear();
    }
    _notesCtrl.clear();
    setState(() {});
  }

  Future<void> _submit(List<IngredientModel> ingredients) async {
    final items = <Map<String, dynamic>>[];

    for (final ing in ingredients) {
      final raw = _ctrls[ing.id]?.text.trim() ?? '';
      if (raw.isEmpty) continue;
      items.add({'ingredient_id': ing.id, 'physical_qty': _decimal(raw)});
    }

    if (items.isEmpty) {
      showSnack(context, 'Isi minimal satu data stok fisik.', error: true);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Simpan Stock Opname?'),
        content: const Text(
          'Stok sistem akan disesuaikan dengan stok fisik yang Anda input.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Simpan'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    if (!mounted) return;

    setState(() => _saving = true);

    try {
      final msg = await ref.read(financeRepoProvider).submitOpname(
            items: items,
            notes: _notesCtrl.text.trim(),
          );
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, msg);
      _resetForm();
      ref.invalidate(opnamePrepareProvider);
      ref.read(opnameHistoryProvider.notifier).refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Scaffold(
      backgroundColor: p.appBg,
      appBar: AppBar(
        title: const Text('Stock Opname'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Form Opname'),
            Tab(text: 'Riwayat'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildFormTab(),
          const _OpnameHistoryTab(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- tab 1

  Widget _buildFormTab() {
    final p = context.palette;
    final prepare = ref.watch(opnamePrepareProvider);

    return AsyncView<OpnamePrepare>(
      value: prepare,
      onRetry: () => ref.invalidate(opnamePrepareProvider),
      builder: (data) {
        final ingredients = data.ingredients;

        return Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(opnamePrepareProvider);
                },
                child: ListView(
                  padding: EdgeInsets.fromLTRB(sp(4), sp(4), sp(4), sp(6)),
                  children: [
                    AppCard(
                      color: p.warningLight,
                      borderColor: Colors.transparent,
                      padding: EdgeInsets.all(sp(4)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded, size: 18, color: p.warning),
                          SizedBox(width: sp(2.5)),
                          Expanded(
                            child: Text(
                              data.note ??
                                  'Masukkan stok fisik yang benar-benar ada. '
                                      'Sistem menghitung selisih otomatis dan menyesuaikan batch (FEFO).',
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.5,
                                fontWeight: FontWeight.w500,
                                color: p.gray800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: sp(4)),
                    if (ingredients.isEmpty)
                      const EmptyState(
                        message: 'Belum ada bahan yang bisa diopname.',
                        icon: Icons.inventory_2_outlined,
                      )
                    else ...[
                      for (final ing in ingredients)
                        Padding(
                          padding: EdgeInsets.only(bottom: sp(3)),
                          child: _OpnameRow(
                            ingredient: ing,
                            controller: _ctrlFor(ing.id),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      SizedBox(height: sp(1)),
                      TextField(
                        controller: _notesCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Catatan Opname (Opsional)',
                          hintText: 'Contoh: penyesuaian akhir bulan',
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Tombol tetap di bawah agar mudah dijangkau saat menggulir daftar.
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(sp(4), sp(3), sp(4), sp(3)),
              decoration: BoxDecoration(
                color: p.surface,
                border: Border(top: BorderSide(color: p.border)),
              ),
              child: SafeArea(
                top: false,
                child: ElevatedButton.icon(
                  onPressed: _saving || ingredients.isEmpty
                      ? null
                      : () => _submit(ingredients),
                  icon: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_rounded, size: 18),
                  label: const Text('Simpan Hasil Opname'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ====================================================================
// SATU BARIS BAHAN DI FORM OPNAME
// ====================================================================

class _OpnameRow extends StatelessWidget {
  const _OpnameRow({
    required this.ingredient,
    required this.controller,
    required this.onChanged,
  });

  final IngredientModel ingredient;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final raw = controller.text.trim();
    final hasInput = raw.isNotEmpty;
    final diff = hasInput ? _decimal(raw) - ingredient.currentStock : 0.0;

    final tone = !hasInput || diff == 0
        ? p.textMuted
        : (diff > 0 ? p.success : p.danger);

    final label = !hasInput
        ? 'Selisih: -'
        : 'Selisih: ${diff > 0 ? '+' : ''}${Fmt.qty(diff)} ${ingredient.unit}';

    return AppCard(
      padding: EdgeInsets.fromLTRB(sp(4), sp(3), sp(4), sp(3)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ingredient.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: p.gray900,
                  ),
                ),
                SizedBox(height: sp(0.5)),
                Text(
                  'Sistem: ${ingredient.stockLabel ?? '${Fmt.qty(ingredient.currentStock)} ${ingredient.unit}'}',
                  style: TextStyle(fontSize: 12, color: p.textMuted),
                ),
                SizedBox(height: sp(1)),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: tone,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: sp(3)),
          SizedBox(
            width: 96,
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Stok Fisik',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: sp(2.5),
                  vertical: sp(2.5),
                ),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                hintText: '0',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ====================================================================
// TAB RIWAYAT
// ====================================================================

class _OpnameHistoryTab extends ConsumerWidget {
  const _OpnameHistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final st = ref.watch(opnameHistoryProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(opnameHistoryProvider.notifier).refresh(),
      child: ListView(
        padding: EdgeInsets.fromLTRB(sp(4), sp(4), sp(4), sp(10)),
        children: [
          const SectionHeader(
            title: 'Riwayat Opname',
            subtitle: 'Ketuk kartu untuk melihat rincian selisih',
            icon: Icons.history_rounded,
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
              onRetry: () => ref.read(opnameHistoryProvider.notifier).refresh(),
            )
          else if (st.items.isEmpty)
            const EmptyState(
              message: 'Belum ada riwayat stock opname.',
              icon: Icons.fact_check_outlined,
            )
          else ...[
            for (final row in st.items)
              Padding(
                padding: EdgeInsets.only(bottom: sp(3)),
                child: AppCard(
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => _OpnameDetailSheet(id: row.id),
                  ),
                  padding: EdgeInsets.all(sp(4)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              Fmt.date(row.date),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: p.gray900,
                              ),
                            ),
                            if (row.notes != null && row.notes!.isNotEmpty) ...[
                              SizedBox(height: sp(0.5)),
                              Text(
                                row.notes!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12.5, color: p.textMuted),
                              ),
                            ],
                            SizedBox(height: sp(1.5)),
                            Text(
                              row.userName ?? '-',
                              style: TextStyle(fontSize: 11, color: p.gray500),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 20, color: p.gray400),
                    ],
                  ),
                ),
              ),
            if (st.hasMore)
              OutlinedButton.icon(
                onPressed: st.isLoadingMore
                    ? null
                    : () => ref.read(opnameHistoryProvider.notifier).loadMore(),
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
// BOTTOM SHEET RINCIAN OPNAME
// ====================================================================

class _OpnameDetailSheet extends ConsumerWidget {
  const _OpnameDetailSheet({required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final detail = ref.watch(opnameDetailProvider(id));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(sp(4)),
        child: AsyncView<OpnameDetail>(
          value: detail,
          onRetry: () => ref.invalidate(opnameDetailProvider(id)),
          loading: const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
          ),
          builder: (d) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: 'Rincian Opname ${Fmt.date(d.date)}',
                subtitle: [
                  if (d.userName != null) d.userName!,
                  if (d.notes != null && d.notes!.isNotEmpty) d.notes!,
                ].join(' · '),
                icon: Icons.fact_check_outlined,
              ),
              SizedBox(height: sp(4)),
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text('Bahan', style: _head(p)),
                  ),
                  Expanded(
                    child: Text('Sistem', textAlign: TextAlign.right, style: _head(p)),
                  ),
                  Expanded(
                    child: Text('Fisik', textAlign: TextAlign.right, style: _head(p)),
                  ),
                  Expanded(
                    child: Text('Selisih', textAlign: TextAlign.right, style: _head(p)),
                  ),
                ],
              ),
              Divider(height: sp(4), color: p.border),
              Flexible(
                child: d.details.isEmpty
                    ? const EmptyState(
                        message: 'Tidak ada rincian pada opname ini.',
                        compact: true,
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: d.details.length,
                        separatorBuilder: (context, index) =>
                            Divider(height: sp(3), color: p.border),
                        itemBuilder: (context, i) {
                          final row = d.details[i];
                          final diffColor = row.difference > 0
                              ? p.success
                              : (row.difference < 0 ? p.danger : p.textMuted);

                          return Row(
                            children: [
                              Expanded(
                                flex: 4,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      row.ingredientName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: p.gray800,
                                      ),
                                    ),
                                    Text(
                                      row.unit,
                                      style: TextStyle(fontSize: 10.5, color: p.gray500),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  Fmt.qty(row.systemQty),
                                  textAlign: TextAlign.right,
                                  style: TextStyle(fontSize: 12, color: p.gray700),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  Fmt.qty(row.physicalQty),
                                  textAlign: TextAlign.right,
                                  style: TextStyle(fontSize: 12, color: p.gray700),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  '${row.difference > 0 ? '+' : ''}${Fmt.qty(row.difference)}',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: diffColor,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
              SizedBox(height: sp(3)),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tutup'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _head(AppPalette p) => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: p.gray500,
      );
}

/// Angka desimal dari teks bebas ("2,5" → 2.5).
double _decimal(String raw) =>
    double.tryParse(raw.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
