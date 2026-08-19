import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/ui.dart';
import '../../models/master.dart';
import 'master_providers.dart';

/// Data Master — Kategori Menu.
class CategoryScreen extends ConsumerStatefulWidget {
  const CategoryScreen({super.key});

  @override
  ConsumerState<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends ConsumerState<CategoryScreen> {
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
      ref.read(categoryListProvider.notifier).setSearch(value);
    });
  }

  Future<void> _openForm({CategoryModel? item}) async {
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CategoryForm(item: item),
    );

    if (message == null) return;
    if (!mounted) return;
    showSnack(context, message);
  }

  Future<void> _loadMore() async {
    final error = await ref.read(categoryListProvider.notifier).loadMore();
    if (error == null) return;
    if (!mounted) return;
    showSnack(context, error, error: true);
  }

  Future<void> _confirmDelete(CategoryModel item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Kategori?'),
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
      final message = await ref.read(categoryListProvider.notifier).remove(item.id);
      if (!mounted) return;
      showSnack(context, message);
    } on ApiException catch (e) {
      // 409 → kategori masih dipakai menu. Pesan server ditampilkan apa adanya.
      if (!mounted) return;
      showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = ref.watch(categoryListProvider);

    return Scaffold(
      backgroundColor: p.appBg,
      appBar: AppBar(title: const Text('Kategori Menu')),
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
              hint: 'Cari nama kategori...',
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(child: _body(s)),
        ],
      ),
    );
  }

  Widget _body(MasterListState<CategoryModel> s) {
    if (s.isLoading && s.items.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }

    if (s.error != null && s.items.isEmpty) {
      return ErrorView(
        message: s.error!,
        onRetry: () => ref.read(categoryListProvider.notifier).load(),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(categoryListProvider.notifier).refresh(),
      child: s.items.isEmpty
          ? ListView(
              padding: EdgeInsets.symmetric(vertical: sp(8)),
              children: [
                EmptyState(
                  message: 'Belum ada data kategori.',
                  icon: Icons.category_outlined,
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

  Widget _card(CategoryModel item) {
    final p = context.palette;

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
              color: p.primaryLight,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(Icons.category_rounded, size: 18, color: p.primary),
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
                SizedBox(height: sp(1.5)),
                Wrap(
                  spacing: sp(2),
                  runSpacing: sp(1),
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (item.slug != null)
                      StatusBadge(text: item.slug!, tone: 'primary', dense: true),
                    if (item.menusCount != null)
                      Text(
                        '${item.menusCount} menu',
                        style: TextStyle(fontSize: 11.5, color: p.textMuted),
                      ),
                  ],
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

/// Tombol paginasi sederhana (dipakai semua layar master).
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
// FORM TAMBAH / EDIT KATEGORI
// =====================================================================

class _CategoryForm extends ConsumerStatefulWidget {
  const _CategoryForm({this.item});

  final CategoryModel? item;

  @override
  ConsumerState<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends ConsumerState<_CategoryForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;

  bool _saving = false;
  String? _nameError;

  bool get _isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.item?.name ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _nameError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    final controller = ref.read(categoryListProvider.notifier);
    final data = {'name': _name.text.trim()};

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
                title: _isEdit ? 'Edit Kategori' : 'Tambah Kategori',
                subtitle: 'Pengelompokan menu makanan & minuman',
                icon: Icons.category_rounded,
              ),
              SizedBox(height: sp(5)),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Nama Kategori',
                  hintText: 'Mis. Makanan Utama',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Nama Kategori wajib diisi.';
                  return _nameError;
                },
                onFieldSubmitted: (_) {
                  if (!_saving) _submit();
                },
              ),
              SizedBox(height: sp(2)),
              Text(
                'Slug dibuat otomatis dari nama.',
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
