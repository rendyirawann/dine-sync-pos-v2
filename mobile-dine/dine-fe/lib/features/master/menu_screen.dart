import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import '../../models/master.dart';
import 'master_providers.dart';

/// Data Master — Menu Makanan & Minuman (+ pengaturan resep/bahan per menu).
class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
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
      ref.read(menuListProvider.notifier).setSearch(value);
    });
  }

  Future<void> _openForm({MenuModel? item}) async {
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MenuForm(item: item),
    );

    if (message == null) return;
    if (!mounted) return;
    showSnack(context, message);
  }

  Future<void> _openRecipes(MenuModel item) async {
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RecipeSheet(menu: item),
    );

    if (message == null) return;
    if (!mounted) return;
    showSnack(context, message);
  }

  Future<void> _loadMore() async {
    final error = await ref.read(menuListProvider.notifier).loadMore();
    if (error == null) return;
    if (!mounted) return;
    showSnack(context, error, error: true);
  }

  Future<void> _confirmDelete(MenuModel item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Menu?'),
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
      final message = await ref.read(menuListProvider.notifier).remove(item.id);
      if (!mounted) return;
      showSnack(context, message);
    } on ApiException catch (e) {
      // 409 → menu masih dipakai order aktif. Pesan server ditampilkan apa adanya.
      if (!mounted) return;
      showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = ref.watch(menuListProvider);

    return Scaffold(
      backgroundColor: p.appBg,
      appBar: AppBar(title: const Text('Menu Makanan & Minuman')),
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
              hint: 'Cari nama menu...',
              onChanged: _onSearchChanged,
            ),
          ),
          _categoryFilter(s),
          Expanded(child: _body(s)),
        ],
      ),
    );
  }

  /// Baris chip kategori (chip pertama selalu "Semua").
  Widget _categoryFilter(MasterListState<MenuModel> s) {
    final categories = ref.watch(categoryOptionsProvider).valueOrNull ?? const <CategoryModel>[];
    if (categories.isEmpty) return const SizedBox.shrink();

    final selected = s.filters['category_id'];

    void pick(int? id) => ref.read(menuListProvider.notifier).setFilter('category_id', id);

    return SizedBox(
      height: sp(11),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: sp(4)),
        children: [
          Padding(
            padding: EdgeInsets.only(right: sp(2)),
            child: ChoiceChip(
              label: const Text('Semua'),
              selected: selected == null,
              onSelected: (_) => pick(null),
            ),
          ),
          for (final c in categories)
            Padding(
              padding: EdgeInsets.only(right: sp(2)),
              child: ChoiceChip(
                label: Text(c.name),
                selected: selected == c.id,
                onSelected: (_) => pick(c.id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body(MasterListState<MenuModel> s) {
    if (s.isLoading && s.items.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }

    if (s.error != null && s.items.isEmpty) {
      return ErrorView(
        message: s.error!,
        onRetry: () => ref.read(menuListProvider.notifier).load(),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(menuListProvider.notifier).refresh(),
      child: s.items.isEmpty
          ? ListView(
              padding: EdgeInsets.symmetric(vertical: sp(8)),
              children: [
                EmptyState(
                  message: 'Belum ada data menu.',
                  icon: Icons.restaurant_menu_outlined,
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

  Widget _card(MenuModel item) {
    final p = context.palette;

    return AppCard(
      onTap: () => _openForm(item: item),
      padding: EdgeInsets.fromLTRB(sp(3.5), sp(3), sp(2), sp(3)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Thumbnail(url: item.imageUrl),
          SizedBox(width: sp(3)),
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
                      text: item.categoryName ?? 'Tanpa Kategori',
                      tone: 'info',
                      dense: true,
                    ),
                    StatusBadge(
                      text: item.isAvailable ? 'Tersedia' : 'Habis',
                      tone: item.isAvailable ? 'success' : 'danger',
                      dense: true,
                    ),
                  ],
                ),
                SizedBox(height: sp(2)),
                _priceRow(item),
              ],
            ),
          ),
          Column(
            children: [
              IconButton(
                onPressed: () => _openRecipes(item),
                icon: const Icon(Icons.blender_outlined, size: 20),
                color: p.gray600,
                tooltip: 'Resep / Bahan',
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
        ],
      ),
    );
  }

  Widget _priceRow(MenuModel item) {
    final p = context.palette;

    if (!item.hasDiscount) {
      return Text(
        Fmt.rupiah(item.price),
        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.success),
      );
    }

    return Wrap(
      spacing: sp(1.5),
      runSpacing: sp(1),
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          Fmt.rupiah(item.price),
          style: TextStyle(
            fontSize: 11,
            color: p.textMuted,
            decoration: TextDecoration.lineThrough,
          ),
        ),
        Text(
          Fmt.rupiah(item.finalPrice),
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.success),
        ),
        StatusBadge(text: '-${item.discountPercent}%', tone: 'danger', dense: true),
      ],
    );
  }
}

/// Foto menu 56px dengan fallback ikon bila belum ada gambar.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    final placeholder = Container(
      height: 56,
      width: 56,
      alignment: Alignment.center,
      color: p.gray100,
      child: Icon(Icons.restaurant_rounded, size: 22, color: p.gray500),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: url == null
          ? placeholder
          : CachedNetworkImage(
              imageUrl: url!,
              height: 56,
              width: 56,
              fit: BoxFit.cover,
              placeholder: (_, _) => placeholder,
              errorWidget: (_, _, _) => placeholder,
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
// FORM TAMBAH / EDIT MENU
// =====================================================================

class _MenuForm extends ConsumerStatefulWidget {
  const _MenuForm({this.item});

  final MenuModel? item;

  @override
  ConsumerState<_MenuForm> createState() => _MenuFormState();
}

class _MenuFormState extends ConsumerState<_MenuForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _discount;
  late final TextEditingController _description;

  int? _categoryId;
  late bool _available;
  bool _saving = false;

  String? _nameError;
  String? _priceError;
  String? _discountError;
  String? _categoryError;

  bool get _isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;

    _name = TextEditingController(text: item?.name ?? '');
    _price = TextEditingController(text: item == null ? '' : _plain(item.price));
    _discount = TextEditingController(
      text: item == null || item.discountPercent == 0 ? '' : '${item.discountPercent}',
    );
    _description = TextEditingController(text: item?.description ?? '');
    _categoryId = item?.categoryId;
    _available = item?.isAvailable ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _discount.dispose();
    _description.dispose();
    super.dispose();
  }

  /// `25000.0` → `25000` (agar field angka tidak menampilkan `.0`).
  static String _plain(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }

  static double? _toNumber(String raw) => double.tryParse(raw.trim().replaceAll(',', '.'));

  Future<void> _submit() async {
    setState(() {
      _nameError = null;
      _priceError = null;
      _discountError = null;
      _categoryError = null;
    });

    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    final description = _description.text.trim();
    final data = <String, dynamic>{
      'category_id': _categoryId,
      'name': _name.text.trim(),
      'price': _toNumber(_price.text) ?? 0,
      'discount_percent': int.tryParse(_discount.text.trim()) ?? 0,
      'description': description.isEmpty ? null : description,
      'is_available': _available,
    };

    final controller = ref.read(menuListProvider.notifier);

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
        _priceError = e.errorFor('price');
        _discountError = e.errorFor('discount_percent');
        _categoryError = e.errorFor('category_id');
      });
      _formKey.currentState?.validate();
      showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final categories = ref.watch(categoryOptionsProvider).valueOrNull ?? const <CategoryModel>[];

    // Dropdown hanya boleh dimuati nilai yang ada di daftar item.
    final hasCategory = categories.any((c) => c.id == _categoryId);

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
                title: _isEdit ? 'Edit Menu' : 'Tambah Menu',
                subtitle: 'Harga, diskon, dan ketersediaan menu',
                icon: Icons.restaurant_menu_rounded,
              ),
              SizedBox(height: sp(5)),
              DropdownButtonFormField<int>(
                initialValue: hasCategory ? _categoryId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Kategori'),
                hint: Text(categories.isEmpty ? 'Memuat kategori...' : 'Pilih kategori'),
                items: [
                  for (final c in categories)
                    DropdownMenuItem<int>(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
                validator: (v) {
                  if (v == null) return 'Kategori wajib dipilih.';
                  return _categoryError;
                },
              ),
              SizedBox(height: sp(4)),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nama Menu',
                  hintText: 'Mis. Nasi Goreng Spesial',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Nama Menu wajib diisi.';
                  return _nameError;
                },
              ),
              SizedBox(height: sp(4)),
              TextFormField(
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Harga (Rp)', hintText: '25000'),
                validator: (v) {
                  final raw = (v ?? '').trim();
                  if (raw.isEmpty) return 'Harga wajib diisi.';
                  final value = _toNumber(raw);
                  if (value == null) return 'Harga harus berupa angka.';
                  if (value < 0) return 'Harga tidak boleh kurang dari 0.';
                  return _priceError;
                },
              ),
              SizedBox(height: sp(4)),
              TextFormField(
                controller: _discount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Diskon (%)',
                  hintText: '0',
                  helperText: 'Kosongkan bila menu tidak berdiskon.',
                ),
                validator: (v) {
                  final raw = (v ?? '').trim();
                  if (raw.isNotEmpty) {
                    final value = int.tryParse(raw);
                    if (value == null) return 'Diskon harus berupa angka bulat.';
                    if (value < 0 || value > 100) return 'Diskon hanya boleh 0 sampai 100.';
                  }
                  return _discountError;
                },
              ),
              SizedBox(height: sp(4)),
              TextFormField(
                controller: _description,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Deskripsi',
                  hintText: 'Keterangan singkat menu (opsional)',
                  alignLabelWithHint: true,
                ),
              ),
              SizedBox(height: sp(3)),
              SwitchListTile(
                value: _available,
                onChanged: (v) => setState(() => _available = v),
                title: const Text('Tersedia'),
                subtitle: Text(
                  _available ? 'Menu bisa dipesan pelanggan.' : 'Menu ditandai habis.',
                  style: TextStyle(fontSize: 11.5, color: p.textMuted),
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              SizedBox(height: sp(1)),
              Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 13, color: p.textMuted),
                  SizedBox(width: sp(1.5)),
                  Expanded(
                    child: Text(
                      'Ubah foto menu lewat aplikasi web.',
                      style: TextStyle(fontSize: 11.5, color: p.textMuted),
                    ),
                  ),
                ],
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

// =====================================================================
// SHEET RESEP / BAHAN MENU
// =====================================================================

/// Satu baris resep yang sedang disunting.
class _RecipeDraft {
  _RecipeDraft({this.ingredientId, double? qty})
      : quantity = TextEditingController(text: qty == null || qty == 0 ? '' : _plain(qty));

  int? ingredientId;
  final TextEditingController quantity;

  static String _plain(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }
}

class _RecipeSheet extends ConsumerStatefulWidget {
  const _RecipeSheet({required this.menu});

  final MenuModel menu;

  @override
  ConsumerState<_RecipeSheet> createState() => _RecipeSheetState();
}

class _RecipeSheetState extends ConsumerState<_RecipeSheet> {
  final List<_RecipeDraft> _rows = [];

  /// Baris yang sudah dihapus dari tampilan — controller-nya baru dibuang
  /// saat sheet ditutup agar tidak dipakai TextField yang belum sempat lepas.
  final List<_RecipeDraft> _retired = [];

  List<IngredientModel> _ingredients = const [];

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final row in [..._rows, ..._retired]) {
      row.quantity.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await fetchMenuRecipes(ref.read(apiClientProvider), widget.menu.id);
      if (!mounted) return;

      setState(() {
        _ingredients = data.ingredients;
        _retired.addAll(_rows);
        _rows
          ..clear()
          ..addAll(data.recipes.map(
            (r) => _RecipeDraft(ingredientId: r.ingredientId, qty: r.quantity),
          ));
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _addRow() => setState(() => _rows.add(_RecipeDraft()));

  void _removeRow(int index) => setState(() => _retired.add(_rows.removeAt(index)));

  String? _unitOf(int? ingredientId) {
    if (ingredientId == null) return null;
    for (final i in _ingredients) {
      if (i.id == ingredientId) return i.unit;
    }
    return null;
  }

  Future<void> _submit() async {
    final payload = <Map<String, dynamic>>[];
    final picked = <int>{};

    for (final row in _rows) {
      if (row.ingredientId == null) {
        showSnack(context, 'Masih ada baris yang belum dipilih bahannya.', error: true);
        return;
      }
      if (!picked.add(row.ingredientId!)) {
        showSnack(context, 'Bahan yang sama tidak boleh dipakai dua kali.', error: true);
        return;
      }

      final qty = double.tryParse(row.quantity.text.trim().replaceAll(',', '.'));
      if (qty == null || qty <= 0) {
        showSnack(context, 'Jumlah pemakaian bahan harus lebih dari 0.', error: true);
        return;
      }

      payload.add({'ingredient_id': row.ingredientId, 'quantity': qty});
    }

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    try {
      final message = await saveMenuRecipes(
        ref.read(apiClientProvider),
        widget.menu.id,
        payload,
      );

      if (!mounted) return;
      Navigator.pop(context, message);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SectionHeader(
              title: 'Resep / Bahan',
              subtitle: widget.menu.name,
              icon: Icons.blender_outlined,
            ),
            SizedBox(height: sp(4)),
            if (_loading)
              Padding(
                padding: EdgeInsets.symmetric(vertical: sp(10)),
                child: const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
              )
            else if (_error != null)
              ErrorView(message: _error!, onRetry: _load)
            else ...[
              if (_rows.isEmpty)
                const EmptyState(
                  message: 'Belum ada bahan pada resep ini.',
                  icon: Icons.blender_outlined,
                  compact: true,
                )
              else
                for (var i = 0; i < _rows.length; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: sp(3)),
                    child: _row(i),
                  ),
              SizedBox(height: sp(1)),
              OutlinedButton.icon(
                onPressed: _saving ? null : _addRow,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Tambah Bahan'),
              ),
              SizedBox(height: sp(2)),
              Text(
                'Jumlah dihitung untuk satu porsi. Bahan ini yang dipotong otomatis saat menu dimasak.',
                style: TextStyle(fontSize: 11.5, color: p.textMuted, height: 1.4),
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
                    : const Text('Simpan Resep'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(int index) {
    final p = context.palette;
    final row = _rows[index];
    final unit = _unitOf(row.ingredientId);
    final valid = _ingredients.any((i) => i.id == row.ingredientId);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: DropdownButtonFormField<int>(
            initialValue: valid ? row.ingredientId : null,
            isExpanded: true,
            isDense: true,
            decoration: const InputDecoration(labelText: 'Bahan'),
            hint: const Text('Pilih bahan'),
            items: [
              for (final i in _ingredients)
                DropdownMenuItem<int>(value: i.id, child: Text(i.name)),
            ],
            onChanged: (v) => setState(() => row.ingredientId = v),
          ),
        ),
        SizedBox(width: sp(2)),
        Expanded(
          flex: 3,
          child: TextField(
            controller: row.quantity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Jumlah',
              isDense: true,
              suffixText: unit,
              suffixStyle: TextStyle(fontSize: 11.5, color: p.textMuted),
            ),
          ),
        ),
        IconButton(
          onPressed: _saving ? null : () => _removeRow(index),
          icon: const Icon(Icons.delete_outline_rounded, size: 20),
          color: p.danger,
          tooltip: 'Hapus baris',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}
