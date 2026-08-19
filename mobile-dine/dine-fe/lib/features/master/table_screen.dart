import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/ui.dart';
import '../../models/master.dart';
import 'master_providers.dart';

/// Data Master — Manajemen Meja (+ QR meja untuk self-order pelanggan).
class TableScreen extends ConsumerStatefulWidget {
  const TableScreen({super.key});

  @override
  ConsumerState<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends ConsumerState<TableScreen> {
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
      ref.read(tableListProvider.notifier).setSearch(value);
    });
  }

  Future<void> _openForm({TableModel? item}) async {
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TableForm(item: item),
    );

    if (message == null) return;
    if (!mounted) return;
    showSnack(context, message);
  }

  Future<void> _loadMore() async {
    final error = await ref.read(tableListProvider.notifier).loadMore();
    if (error == null) return;
    if (!mounted) return;
    showSnack(context, error, error: true);
  }

  void _showQr(TableModel item) {
    final payload = item.qrPayload;

    if (payload == null || payload.isEmpty) {
      showSnack(context, 'QR belum tersedia untuk meja ini.', error: true);
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final p = ctx.palette;

        return AlertDialog(
          title: const Text('QR Meja'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.tableNumber,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: p.gray900),
              ),
              SizedBox(height: sp(3)),
              // Latar putih wajib agar QR tetap terbaca di mode gelap.
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.base),
                ),
                padding: EdgeInsets.all(sp(2)),
                child: QrImageView(
                  data: payload,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
              SizedBox(height: sp(3)),
              Text(
                payload,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: p.textMuted),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(TableModel item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Meja?'),
        content: Text("'${item.tableNumber}' akan dihapus permanen."),
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
      final message = await ref.read(tableListProvider.notifier).remove(item.id);
      if (!mounted) return;
      showSnack(context, message);
    } on ApiException catch (e) {
      // 409 → meja sedang terisi / punya order aktif.
      if (!mounted) return;
      showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = ref.watch(tableListProvider);

    return Scaffold(
      backgroundColor: p.appBg,
      appBar: AppBar(title: const Text('Manajemen Meja')),
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
              hint: 'Cari nomor/nama meja...',
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(child: _body(s)),
        ],
      ),
    );
  }

  Widget _body(MasterListState<TableModel> s) {
    if (s.isLoading && s.items.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }

    if (s.error != null && s.items.isEmpty) {
      return ErrorView(
        message: s.error!,
        onRetry: () => ref.read(tableListProvider.notifier).load(),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(tableListProvider.notifier).refresh(),
      child: s.items.isEmpty
          ? ListView(
              padding: EdgeInsets.symmetric(vertical: sp(8)),
              children: [
                EmptyState(
                  message: 'Belum ada data meja.',
                  icon: Icons.table_restaurant_outlined,
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

  Widget _card(TableModel item) {
    final p = context.palette;
    final accent = p.solidOf(item.statusColor);

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
              color: p.softOf(item.statusColor),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(Icons.table_restaurant_rounded, size: 18, color: accent),
          ),
          SizedBox(width: sp(3)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.tableNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.gray900),
                ),
                SizedBox(height: sp(1)),
                Text(
                  'Kapasitas: ${item.capacity} orang',
                  style: TextStyle(fontSize: 11.5, color: p.textMuted),
                ),
                SizedBox(height: sp(1.5)),
                StatusBadge(text: item.statusLabel, tone: item.statusColor, dense: true),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _showQr(item),
            icon: const Icon(Icons.qr_code_2_rounded, size: 20),
            color: p.gray600,
            tooltip: 'QR Meja',
            visualDensity: VisualDensity.compact,
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
// FORM TAMBAH / EDIT MEJA
// =====================================================================

class _TableForm extends ConsumerStatefulWidget {
  const _TableForm({this.item});

  final TableModel? item;

  @override
  ConsumerState<_TableForm> createState() => _TableFormState();
}

class _TableFormState extends ConsumerState<_TableForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _number;
  late final TextEditingController _capacity;

  late String _status;
  bool _saving = false;

  String? _numberError;
  String? _capacityError;

  bool get _isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;

    _number = TextEditingController(text: item?.tableNumber ?? '');
    _capacity = TextEditingController(text: '${item?.capacity ?? 2}');
    _status = item?.status ?? 'available';
  }

  @override
  void dispose() {
    _number.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _numberError = null;
      _capacityError = null;
    });

    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    final data = <String, dynamic>{
      'table_number': _number.text.trim(),
      'capacity': int.tryParse(_capacity.text.trim()) ?? 1,
      // Status hanya boleh dikirim saat mengubah data.
      if (_isEdit) 'status': _status,
    };

    final controller = ref.read(tableListProvider.notifier);

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
        _numberError = e.errorFor('table_number');
        _capacityError = e.errorFor('capacity');
      });
      _formKey.currentState?.validate();
      showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                title: _isEdit ? 'Edit Meja' : 'Tambah Meja',
                subtitle: 'Nomor meja, kapasitas, dan status',
                icon: Icons.table_restaurant_rounded,
              ),
              SizedBox(height: sp(5)),
              TextFormField(
                controller: _number,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Nomor/Nama Meja',
                  hintText: 'Mis. A1 / Meja 12',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Nomor/Nama Meja wajib diisi.';
                  return _numberError;
                },
              ),
              SizedBox(height: sp(4)),
              TextFormField(
                controller: _capacity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Kapasitas (Orang)',
                  hintText: '2',
                ),
                validator: (v) {
                  final raw = (v ?? '').trim();
                  if (raw.isEmpty) return 'Kapasitas wajib diisi.';
                  final value = int.tryParse(raw);
                  if (value == null) return 'Kapasitas harus berupa angka bulat.';
                  if (value < 1) return 'Kapasitas minimal 1 orang.';
                  return _capacityError;
                },
              ),
              if (_isEdit) ...[
                SizedBox(height: sp(4)),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Status Meja'),
                  items: const [
                    DropdownMenuItem(value: 'available', child: Text('Tersedia (Kosong)')),
                    DropdownMenuItem(value: 'occupied', child: Text('Terisi (Ada Pelanggan)')),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? 'available'),
                ),
              ],
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
