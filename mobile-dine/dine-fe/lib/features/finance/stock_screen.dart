import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import '../../models/master.dart';
import 'finance_providers.dart';

/// Stok masuk (FIFO): daftar batch pembelian bahan + input batch baru.
class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});

  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      ref.read(stockBatchListProvider.notifier).setSearch(value);
    });
  }

  Future<void> _openForm() async {
    final msg = await _openSheet<String>(context, const _StockBatchForm());
    if (!mounted || msg == null) return;
    showSnack(context, msg);
    ref.read(stockBatchListProvider.notifier).refresh();
  }

  Future<void> _delete(StockBatch batch) async {
    final ok = await _confirm(
      context,
      title: 'Hapus Batch Stok?',
      message:
          'Batch ${batch.ingredientName} (${Fmt.qty(batch.initialQuantity)} ${batch.unit}) akan dihapus. '
          'Riwayat perhitungan HPP bisa terpengaruh.',
    );
    if (!ok) return;
    if (!mounted) return;

    try {
      final msg = await ref.read(financeRepoProvider).deleteStockBatch(batch.id);
      if (!mounted) return;
      showSnack(context, msg);
      ref.read(stockBatchListProvider.notifier).refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final notifier = ref.read(stockBatchListProvider.notifier);
    final st = ref.watch(stockBatchListProvider);

    return Scaffold(
      backgroundColor: p.appBg,
      appBar: AppBar(title: const Text('Stok Masuk (FIFO)')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openForm,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Input Stok'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(stockBatchListProvider.notifier).refresh(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(sp(4), sp(4), sp(4), sp(24)),
          children: [
            SearchField(
              controller: _searchCtrl,
              hint: 'Cari bahan atau supplier...',
              onChanged: _onSearch,
            ),
            SizedBox(height: sp(3)),
            Row(
              children: [
                FilterChip(
                  label: const Text('Masih Tersedia'),
                  selected: notifier.onlyAvailable,
                  onSelected: notifier.setOnlyAvailable,
                ),
                const Spacer(),
                if (st.items.isNotEmpty)
                  Text(
                    '${st.items.length} batch',
                    style: TextStyle(fontSize: 11.5, color: p.textMuted),
                  ),
              ],
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
                onRetry: () => ref.read(stockBatchListProvider.notifier).refresh(),
              )
            else if (st.items.isEmpty)
              const EmptyState(
                message: 'Belum ada batch stok masuk.',
                icon: Icons.local_shipping_outlined,
              )
            else ...[
              for (final batch in st.items)
                Padding(
                  padding: EdgeInsets.only(bottom: sp(3)),
                  child: _BatchCard(batch: batch, onDelete: () => _delete(batch)),
                ),
              if (st.hasMore)
                OutlinedButton.icon(
                  onPressed: st.isLoadingMore
                      ? null
                      : () => ref.read(stockBatchListProvider.notifier).loadMore(),
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
      ),
    );
  }
}

// ====================================================================
// KARTU BATCH
// ====================================================================

class _BatchCard extends StatelessWidget {
  const _BatchCard({required this.batch, required this.onDelete});

  final StockBatch batch;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final expiryTone = batch.isExpiringSoon ? p.danger : p.gray500;

    return AppCard(
      padding: EdgeInsets.fromLTRB(sp(4), sp(3.5), sp(2), sp(3.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      batch.ingredientName,
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
                      batch.supplierName ?? 'Tanpa Supplier',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.textMuted),
                    ),
                    SizedBox(height: sp(1.5)),
                    Text(
                      'Sisa ${Fmt.qty(batch.remainingQuantity)} / ${Fmt.qty(batch.initialQuantity)} ${batch.unit}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: batch.isAvailable ? p.success : p.gray500,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: sp(2)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Fmt.rupiah(batch.buyPriceTotal),
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: p.gray900,
                    ),
                  ),
                  SizedBox(height: sp(0.5)),
                  Text(
                    '${Fmt.rupiah(batch.buyPrice)} / ${batch.unit}',
                    style: TextStyle(fontSize: 11, color: p.textMuted),
                  ),
                ],
              ),
              IconButton(
                onPressed: onDelete,
                tooltip: 'Hapus',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.delete_outline_rounded, size: 20, color: p.gray500),
              ),
            ],
          ),
          SizedBox(height: sp(2)),
          Wrap(
            spacing: sp(3),
            runSpacing: sp(1),
            children: [
              Text(
                'Masuk: ${Fmt.date(batch.entryDate)}',
                style: TextStyle(fontSize: 11, color: p.gray500),
              ),
              if (batch.expiryDate != null)
                Text(
                  'Exp: ${Fmt.date(batch.expiryDate)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: batch.isExpiringSoon ? FontWeight.w700 : FontWeight.w500,
                    color: expiryTone,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ====================================================================
// FORM INPUT STOK
// ====================================================================

class _StockBatchForm extends ConsumerStatefulWidget {
  const _StockBatchForm();

  @override
  ConsumerState<_StockBatchForm> createState() => _StockBatchFormState();
}

class _StockBatchFormState extends ConsumerState<_StockBatchForm> {
  final _qtyCtrl = TextEditingController();
  final _totalCtrl = TextEditingController();

  int? _ingredientId;
  int? _supplierId;
  DateTime _entryDate = DateTime.now();
  DateTime? _expiryDate;
  bool _saving = false;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _totalCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final qty = _decimal(_qtyCtrl.text);
    final total = _money(_totalCtrl.text);

    if (_ingredientId == null) {
      showSnack(context, 'Pilih bahan terlebih dahulu.', error: true);
      return;
    }
    if (qty <= 0) {
      showSnack(context, 'Jumlah masuk harus lebih dari 0.', error: true);
      return;
    }
    if (_totalCtrl.text.trim().isEmpty) {
      showSnack(context, 'Total harga belanja wajib diisi.', error: true);
      return;
    }

    setState(() => _saving = true);

    try {
      final msg = await ref.read(financeRepoProvider).createStockBatch(
            ingredientId: _ingredientId!,
            initialQuantity: qty,
            buyPriceTotal: total,
            entryDate: _entryDate,
            supplierId: _supplierId,
            expiryDate: _expiryDate,
          );
      if (!mounted) return;
      Navigator.pop(context, msg);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(
        context,
        e.errorFor('initial_quantity') ??
            e.errorFor('buy_price_total') ??
            e.errorFor('ingredient_id') ??
            e.message,
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ingredients = ref.watch(ingredientOptionsProvider);
    final suppliers = ref.watch(supplierOptionsProvider);

    return _SheetBody(
      title: 'Input Stok Masuk',
      subtitle: 'Batch baru dipakai FIFO saat menghitung HPP',
      saving: _saving,
      saveLabel: 'Simpan Batch Stok',
      onSave: _save,
      children: [
        DropdownButtonFormField<int>(
          initialValue: _ingredientId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Bahan'),
          hint: Text(
            ingredients.isLoading ? 'Memuat bahan...' : 'Pilih bahan',
          ),
          items: [
            for (final IngredientModel i in ingredients.value ?? const [])
              DropdownMenuItem(value: i.id, child: Text('${i.name} (${i.unit})')),
          ],
          onChanged: (v) => setState(() => _ingredientId = v),
        ),
        SizedBox(height: sp(3)),
        TextField(
          controller: _qtyCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Jumlah Masuk',
            hintText: 'Contoh: 2,5',
          ),
        ),
        SizedBox(height: sp(3)),
        TextField(
          controller: _totalCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Total Harga Belanja (Rp)',
            hintText: '0',
            helperText: 'Total untuk seluruh jumlah masuk.',
          ),
        ),
        SizedBox(height: sp(3)),
        DropdownButtonFormField<int>(
          initialValue: _supplierId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Supplier (Opsional)'),
          items: [
            const DropdownMenuItem<int>(value: null, child: Text('Tanpa Supplier')),
            for (final SupplierModel s in suppliers.value ?? const [])
              DropdownMenuItem(value: s.id, child: Text(s.name)),
          ],
          onChanged: (v) => setState(() => _supplierId = v),
        ),
        SizedBox(height: sp(3)),
        _DateField(
          label: 'Tanggal Masuk',
          date: _entryDate,
          onTap: () async {
            final picked = await _pickDate(context, _entryDate);
            if (picked == null || !mounted) return;
            setState(() => _entryDate = picked);
          },
        ),
        SizedBox(height: sp(3)),
        _DateField(
          label: 'Tanggal Kadaluarsa (Opsional)',
          date: _expiryDate,
          placeholder: 'Tidak ada',
          onTap: () async {
            final picked = await _pickDate(context, _expiryDate ?? DateTime.now());
            if (picked == null || !mounted) return;
            setState(() => _expiryDate = picked);
          },
          onClear: _expiryDate == null ? null : () => setState(() => _expiryDate = null),
        ),
      ],
    );
  }
}

// ====================================================================
// KOMPONEN & UTILITAS BERSAMA (khusus layar ini)
// ====================================================================

class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.title,
    required this.onSave,
    required this.saving,
    required this.saveLabel,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onSave;
  final bool saving;
  final String saveLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(sp(4)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: title, subtitle: subtitle),
            SizedBox(height: sp(4)),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
            SizedBox(height: sp(4)),
            ElevatedButton(
              onPressed: saving ? null : onSave,
              child: saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(saveLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.date,
    required this.onTap,
    this.placeholder = '-',
    this.onClear,
  });

  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  final String placeholder;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.base),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          children: [
            Icon(Icons.event_rounded, size: 18, color: p.gray600),
            SizedBox(width: sp(2)),
            Expanded(
              child: Text(
                date == null ? placeholder : Fmt.date(date),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: date == null ? p.textMuted : p.gray800,
                ),
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close_rounded, size: 18, color: p.gray500),
              ),
          ],
        ),
      ),
    );
  }
}

Future<T?> _openSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: child,
      ),
    );

Future<DateTime?> _pickDate(BuildContext context, DateTime initial) =>
    showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
      helpText: 'Pilih Tanggal',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Ya, Hapus',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppPalette.light$.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  return ok == true;
}

/// Rupiah dari teks bebas ("50.000" → 50000).
double _money(String raw) =>
    double.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

/// Angka desimal dari teks bebas ("2,5" → 2.5).
double _decimal(String raw) =>
    double.tryParse(raw.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
