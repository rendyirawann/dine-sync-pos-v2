import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import '../../models/master.dart';
import 'master_providers.dart';

/// Satuan yang diizinkan server (urutan sama dengan dropdown di web).
const _units = <String, String>{
  'gram': 'Gram (g)',
  'kg': 'Kilogram (kg)',
  'ml': 'Mililiter (ml)',
  'liter': 'Liter (L)',
  'pcs': 'Pcs / Butir',
  'slice': 'Slice / Lembar',
  'bungkus': 'Bungkus',
};

/// Data Master — Bahan Makanan (stok dihitung server dari batch).
class IngredientScreen extends ConsumerStatefulWidget {
  const IngredientScreen({super.key});

  @override
  ConsumerState<IngredientScreen> createState() => _IngredientScreenState();
}

class _IngredientScreenState extends ConsumerState<IngredientScreen> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      ref.read(ingredientListProvider.notifier).setSearch(value);
    });
  }

  Future<void> _openForm({IngredientModel? item}) async {
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _IngredientForm(item: item),
    );

    if (message == null) return;
    if (!mounted) return;
    showSnack(context, message);
  }

  Future<void> _loadMore() async {
    final error = await ref.read(ingredientListProvider.notifier).loadMore();
    if (error == null) return;
    if (!mounted) return;
    showSnack(context, error, error: true);
  }

  Future<void> _confirmDelete(IngredientModel item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Bahan?'),
        content: Text("'${item.name}' akan dihapus permanen."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ctx.palette.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Hapus'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    try {
      final message = await ref.read(ingredientListProvider.notifier).remove(item.id);
      if (!mounted) return;
      showSnack(context, message);
    } on ApiException catch (e) {
      // 409 → bahan masih dipakai resep menu / punya stok batch.
      if (!mounted) return;
      showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = ref.watch(ingredientListProvider);
    final onlyLowStock = s.filters['low_stock'] == true;

    return Scaffold(
      backgroundColor: p.appBg,
      appBar: AppBar(title: const Text('Bahan Makanan')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openForm,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tambah'),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(sp(4), sp(3), sp(4), sp(2)),
            child: SearchField(
              hint: 'Cari nama bahan...',
              onChanged: _onSearchChanged,
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(sp(4), 0, sp(4), sp(2)),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Stok Menipis'),
                  avatar: Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: onlyLowStock ? p.danger : p.gray500,
                  ),
                  selected: onlyLowStock,
                  onSelected: (v) => ref
                      .read(ingredientListProvider.notifier)
                      .setFilter('low_stock', v ? true : null),
                ),
              ],
            ),
          ),
          Expanded(child: _body(s)),
        ],
      ),
    );
  }

  Widget _body(MasterListState<IngredientModel> s) {
    if (s.isLoading && s.items.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }

    if (s.error != null && s.items.isEmpty) {
      return ErrorView(
        message: s.error!,
        onRetry: () => ref.read(ingredientListProvider.notifier).load(),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(ingredientListProvider.notifier).refresh(),
      child: s.items.isEmpty
          ? ListView(
              padding: EdgeInsets.symmetric(vertical: sp(8)),
              children: [
                EmptyState(
                  message: s.filters['low_stock'] == true
                      ? 'Tidak ada bahan dengan stok menipis.'
                      : 'Belum ada data bahan.',
                  icon: Icons.inventory_2_outlined,
                  actionLabel: 'Tambah Sekarang',
                  onAction: _openForm,
                ),
              ],
            )
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(sp(4), sp(2), sp(4), sp(24)),
              itemCount: s.items.length + (s.hasMore ? 1 : 0),
              separatorBuilder: (_, _) => SizedBox(height: sp(3)),
              itemBuilder: (context, i) {
                if (i >= s.items.length) {
                  return _MoreButton(busy: s.isLoadingMore, onPressed: _loadMore);
                }
                return _card(s.items[i]);
              },
            ),
    );
  }

  Widget _card(IngredientModel item) {
    final p = context.palette;
    final tone = item.isLowStock ? 'danger' : 'success';

    return AppCard(
      onTap: () => _openForm(item: item),
      padding: EdgeInsets.fromLTRB(sp(4), sp(3), sp(2), sp(3)),
      child: Row(
        children: [
          Container(
            height: sp(10),
            width: sp(10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.softOf(tone),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(Icons.inventory_2_rounded, size: 18, color: p.solidOf(tone)),
          ),
          SizedBox(width: sp(3)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.gray900),
                ),
                SizedBox(height: sp(1)),
                Text(
                  'Min. stok: ${Fmt.qty(item.minimumStock)} ${item.unit}',
                  style: TextStyle(fontSize: 11.5, color: p.textMuted),
                ),
                SizedBox(height: sp(1.5)),
                StatusBadge(
                  text: item.stockLabel ?? '${Fmt.qty(item.currentStock)} ${item.unit}',
                  tone: tone,
                  dense: true,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _confirmDelete(item),
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            color: p.danger,
            tooltip: 'Hapus',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// Tombol paginasi sederhana.
class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: sp(1)),
      child: OutlinedButton.icon(
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.expand_more_rounded, size: 18),
        label: Text(busy ? 'Memuat...' : 'Muat lebih banyak'),
      ),
    );
  }
}

// =====================================================================
// FORM TAMBAH / EDIT BAHAN
// =====================================================================

class _IngredientForm extends ConsumerStatefulWidget {
  const _IngredientForm({this.item});

  final IngredientModel? item;

  @override
  ConsumerState<_IngredientForm> createState() => _IngredientFormState();
}

class _IngredientFormState extends ConsumerState<_IngredientForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _minimumStock;

  late String _unit;
  bool _saving = false;

  String? _nameError;
  String? _unitError;
  String? _minimumStockError;

  bool get _isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;

    _name = TextEditingController(text: item?.name ?? '');
    _minimumStock = TextEditingController(
      text: item == null ? '' : _plain(item.minimumStock),
    );
    _unit = _units.containsKey(item?.unit) ? item!.unit : 'gram';
  }

  @override
  void dispose() {
    _name.dispose();
    _minimumStock.dispose();
    super.dispose();
  }

  /// `500.0` → `500`, `0.5` → `0.5`.
  static String _plain(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }

  static double? _toNumber(String raw) => double.tryParse(raw.trim().replaceAll(',', '.'));

  Future<void> _submit() async {
    setState(() {
      _nameError = null;
      _unitError = null;
      _minimumStockError = null;
    });

    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'unit': _unit,
      'minimum_stock': _toNumber(_minimumStock.text) ?? 0,
    };

    final controller = ref.read(ingredientListProvider.notifier);

    try {
      final message = _isEdit
          ? await controller.update(widget.item!.id, data)
          : await controller.create(data);

      if (!mounted) return;
      Navigator.pop(context, message);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _nameError = e.errorFor('name');
        _unitError = e.errorFor('unit');
        _minimumStockError = e.errorFor('minimum_stock');
      });
      _formKey.currentState?.validate();
      showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Padding(
      padding: EdgeInsets.only(
        left: sp(5),
        right: sp(5),
        bottom: MediaQuery.of(context).viewInsets.bottom + sp(6),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SectionHeader(
                title: _isEdit ? 'Edit Bahan' : 'Tambah Bahan',
                subtitle: 'Satuan & batas stok minimum',
                icon: Icons.inventory_2_rounded,
              ),
              SizedBox(height: sp(5)),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nama Bahan',
                  hintText: 'Mis. Daging Ayam',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Nama Bahan wajib diisi.';
                  return _nameError;
                },
              ),
              SizedBox(height: sp(4)),
              DropdownButtonFormField<String>(
                initialValue: _unit,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Satuan'),
                items: [
                  for (final e in _units.entries)
                    DropdownMenuItem<String>(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _unit = v ?? 'gram'),
                validator: (_) => _unitError,
              ),
              SizedBox(height: sp(4)),
              TextFormField(
                controller: _minimumStock,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Minimum Stok',
                  hintText: '1000',
                  suffixText: _unit,
                  helperText: 'Peringatan stok menipis muncul di bawah angka ini.',
                ),
                validator: (v) {
                  final raw = (v ?? '').trim();
                  if (raw.isEmpty) return 'Minimum Stok wajib diisi.';
                  final value = _toNumber(raw);
                  if (value == null) return 'Minimum Stok harus berupa angka.';
                  if (value < 0) return 'Minimum Stok tidak boleh kurang dari 0.';
                  return _minimumStockError;
                },
              ),
              SizedBox(height: sp(2)),
              Text(
                'Stok berjalan dihitung otomatis dari data stok masuk (batch).',
                style: TextStyle(fontSize: 11.5, color: p.textMuted),
              ),
              SizedBox(height: sp(6)),
              ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                      )
                    : const Text('Simpan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
