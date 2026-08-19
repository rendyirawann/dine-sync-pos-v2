import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import '../../models/master.dart';
import 'master_providers.dart';

/// Data Master — Promo & Diskon.
class PromoScreen extends ConsumerStatefulWidget {
  const PromoScreen({super.key});

  @override
  ConsumerState<PromoScreen> createState() => _PromoScreenState();
}

class _PromoScreenState extends ConsumerState<PromoScreen> {
  Timer? _debounce;

  /// Promo yang sedang diproses aktif/nonaktif (switch dimatikan sementara).
  final Set<int> _toggling = {};

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      ref.read(promoListProvider.notifier).setSearch(value);
    });
  }

  Future<void> _openForm({PromoModel? item}) async {
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PromoForm(item: item),
    );

    if (message == null) return;
    if (!mounted) return;
    showSnack(context, message);
  }

  Future<void> _loadMore() async {
    final error = await ref.read(promoListProvider.notifier).loadMore();
    if (error == null) return;
    if (!mounted) return;
    showSnack(context, error, error: true);
  }

  Future<void> _toggle(PromoModel item) async {
    setState(() => _toggling.add(item.id));

    try {
      final message = await ref.read(promoListProvider.notifier).postAction('${item.id}/toggle');
      if (!mounted) return;
      showSnack(context, message);
    } on ApiException catch (e) {
      if (!mounted) return;
      showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _toggling.remove(item.id));
    }
  }

  Future<void> _confirmDelete(PromoModel item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Promo?'),
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
      final message = await ref.read(promoListProvider.notifier).remove(item.id);
      if (!mounted) return;
      showSnack(context, message);
    } on ApiException catch (e) {
      // 409 → promo masih dipakai order aktif.
      if (!mounted) return;
      showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = ref.watch(promoListProvider);

    return Scaffold(
      backgroundColor: p.appBg,
      appBar: AppBar(title: const Text('Promo & Diskon')),
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
              hint: 'Cari nama promo...',
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(child: _body(s)),
        ],
      ),
    );
  }

  Widget _body(MasterListState<PromoModel> s) {
    if (s.isLoading && s.items.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }

    if (s.error != null && s.items.isEmpty) {
      return ErrorView(
        message: s.error!,
        onRetry: () => ref.read(promoListProvider.notifier).load(),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(promoListProvider.notifier).refresh(),
      child: s.items.isEmpty
          ? ListView(
              padding: EdgeInsets.symmetric(vertical: sp(8)),
              children: [
                EmptyState(
                  message: 'Belum ada data promo.',
                  icon: Icons.local_offer_outlined,
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

  Widget _card(PromoModel item) {
    final p = context.palette;
    final busy = _toggling.contains(item.id);

    return AppCard(
      onTap: () => _openForm(item: item),
      padding: EdgeInsets.fromLTRB(sp(4), sp(3), sp(2), sp(3)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.gray900),
                ),
                SizedBox(height: sp(1.5)),
                Wrap(
                  spacing: sp(1.5),
                  runSpacing: sp(1),
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusBadge(
                      text: item.isPercentage
                          ? '${item.discountValue}%'
                          : Fmt.rupiah(item.discountValue),
                      tone: item.isPercentage ? 'primary' : 'success',
                      dense: true,
                    ),
                    Text(
                      item.isActive ? 'Aktif' : 'Nonaktif',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: item.isActive ? p.success : p.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          busy
              ? Padding(
                  padding: EdgeInsets.symmetric(horizontal: sp(3)),
                  child: const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Switch(
                  value: item.isActive,
                  onChanged: (_) => _toggle(item),
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
// FORM TAMBAH / EDIT PROMO
// =====================================================================

class _PromoForm extends ConsumerStatefulWidget {
  const _PromoForm({this.item});

  final PromoModel? item;

  @override
  ConsumerState<_PromoForm> createState() => _PromoFormState();
}

class _PromoFormState extends ConsumerState<_PromoForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _value;

  late String _type;
  late bool _active;
  bool _saving = false;

  String? _nameError;
  String? _valueError;
  String? _typeError;

  bool get _isEdit => widget.item != null;
  bool get _isPercentage => _type == 'percentage';

  @override
  void initState() {
    super.initState();
    final item = widget.item;

    _name = TextEditingController(text: item?.name ?? '');
    _value = TextEditingController(text: item == null ? '' : '${item.discountValue}');
    _type = item?.discountType ?? 'percentage';
    _active = item?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _nameError = null;
      _valueError = null;
      _typeError = null;
    });

    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'discount_type': _type,
      'discount_value': int.tryParse(_value.text.trim()) ?? 0,
      'is_active': _active,
    };

    final controller = ref.read(promoListProvider.notifier);

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
        _valueError = e.errorFor('discount_value');
        _typeError = e.errorFor('discount_type');
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
                title: _isEdit ? 'Edit Promo' : 'Tambah Promo',
                subtitle: 'Diskon persentase atau potongan nominal',
                icon: Icons.local_offer_rounded,
              ),
              SizedBox(height: sp(5)),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nama Promo',
                  hintText: 'Mis. Promo Gajian',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Nama Promo wajib diisi.';
                  return _nameError;
                },
              ),
              SizedBox(height: sp(4)),
              DropdownButtonFormField<String>(
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Tipe Diskon'),
                items: const [
                  DropdownMenuItem(value: 'percentage', child: Text('Persentase (%)')),
                  DropdownMenuItem(value: 'nominal', child: Text('Nominal (Rp)')),
                ],
                onChanged: (v) => setState(() => _type = v ?? 'percentage'),
                validator: (_) => _typeError,
              ),
              SizedBox(height: sp(4)),
              TextFormField(
                controller: _value,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Nilai Diskon',
                  hintText: _isPercentage ? '10' : '5000',
                  prefixText: _isPercentage ? null : 'Rp ',
                  suffixText: _isPercentage ? '%' : null,
                ),
                validator: (v) {
                  final raw = (v ?? '').trim();
                  if (raw.isEmpty) return 'Nilai Diskon wajib diisi.';
                  final value = int.tryParse(raw);
                  if (value == null) return 'Nilai Diskon harus berupa angka bulat.';
                  if (value < 1) return 'Nilai Diskon minimal 1.';
                  if (_isPercentage && value > 100) return 'Diskon persentase maksimal 100%.';
                  return _valueError;
                },
              ),
              SizedBox(height: sp(3)),
              SwitchListTile(
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: const Text('Aktifkan Promo'),
                subtitle: Text(
                  _active ? 'Promo bisa dipakai kasir.' : 'Promo disimpan tapi tidak dipakai.',
                  style: TextStyle(fontSize: 11.5, color: p.textMuted),
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              SizedBox(height: sp(5)),
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
