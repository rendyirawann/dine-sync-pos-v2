import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import '../../models/master.dart';
import '../../models/order.dart';
import 'kasir_providers.dart';

/// Layar buat pesanan (padanan `kasir/create` di web, versi mobile).
///
/// Badan layar = daftar menu; keranjang selalu terjangkau lewat bottom bar
/// dan dibuka sebagai bottom sheet penuh.
class OrderBuilderScreen extends ConsumerStatefulWidget {
  const OrderBuilderScreen({
    super.key,
    required this.tableId,
    required this.customerName,
    required this.orderType,
  });

  final int tableId;
  final String customerName;
  final String orderType;

  @override
  ConsumerState<OrderBuilderScreen> createState() => _OrderBuilderScreenState();
}

class _OrderBuilderScreenState extends ConsumerState<OrderBuilderScreen> {
  final List<CartLine> _cart = [];
  final Map<int, TextEditingController> _noteCtrls = {};
  final _searchCtrl = TextEditingController();

  String _search = '';
  int? _categoryId;
  int? _promoId;
  bool _submitting = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    for (final c in _noteCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------- keranjang

  int get _itemCount => _cart.fold<int>(0, (sum, l) => sum + l.qty);

  PromoModel? _promoOf(OrderContextData data) {
    if (_promoId == null) return null;
    for (final promo in data.promos) {
      if (promo.id == _promoId) return promo;
    }
    return null;
  }

  CartTotals _totals(OrderContextData data) => computeCartTotals(
        cart: _cart,
        promo: _promoOf(data),
        taxRate: data.setting.taxRate,
      );

  TextEditingController _noteCtrlFor(CartLine line) => _noteCtrls.putIfAbsent(
        line.menu.id,
        () => TextEditingController(text: line.note ?? ''),
      );

  void _addToCart(MenuModel menu) {
    setState(() {
      for (final line in _cart) {
        if (line.menu.id == menu.id) {
          line.qty += 1;
          return;
        }
      }
      _cart.add(CartLine(
        menu: MenuLite(
          id: menu.id,
          name: menu.name,
          finalPrice: menu.finalPrice,
          imageUrl: menu.imageUrl,
        ),
      ));
    });

    showSnack(context, '${menu.name} ditambahkan');
  }

  void _removeLine(CartLine line) {
    setState(() {
      _cart.remove(line);
      _noteCtrls.remove(line.menu.id)?.dispose();
    });
  }

  // ------------------------------------------------------------------- filter

  List<MenuModel> _filteredMenus(OrderContextData data) {
    final q = _search.trim().toLowerCase();

    return data.availableMenus.where((m) {
      final matchCategory = _categoryId == null || m.categoryId == _categoryId;
      final matchQuery = q.isEmpty ||
          m.name.toLowerCase().contains(q) ||
          (m.categoryName ?? '').toLowerCase().contains(q);
      return matchCategory && matchQuery;
    }).toList();
  }

  // ------------------------------------------------------------------- submit

  Future<void> _submit(_PayIntent intent) async {
    if (_submitting) return;
    setState(() => _submitting = true);

    try {
      final res = await ref.read(kasirActionsProvider).createOrder(
            tableId: widget.tableId,
            customerName: widget.customerName,
            orderType: widget.orderType,
            paymentMethod: intent.method,
            promoId: _promoId,
            cashReceived: intent.isCash ? intent.cashReceived : null,
            cart: _cart.map((l) => l.toPayload()).toList(),
          );

      if (!mounted) return;

      ref.invalidate(tableMapProvider);
      ref.invalidate(tableDetailProvider(widget.tableId));

      final map = res.asMap;
      final order = map['order'] is Map<String, dynamic>
          ? map['order'] as Map<String, dynamic>
          : const <String, dynamic>{};

      showSnack(context, res.message);

      if (map['type'] == 'cash') {
        setState(() => _submitting = false);
        await _offerReceipt(
          orderId: J.toInt(order['id']),
          change: J.toDouble(map['change']),
        );
      } else {
        context.go('/kasir');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showSnack(context, e.message, error: true);
    }
  }

  /// Setelah pembayaran tunai berhasil: tawarkan cetak struk, lalu balik ke kasir.
  Future<void> _offerReceipt({required int orderId, double change = 0}) async {
    final wantPrint = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pembayaran Berhasil'),
        content: Text(
          change > 0
              ? 'Kembalian: ${Fmt.rupiah(change)}\n\nCetak struk untuk pelanggan?'
              : 'Cetak struk untuk pelanggan?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Selesai')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cetak Struk'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (wantPrint == true) {
      await context.pushNamed(
        'kasir-receipt',
        pathParameters: {'orderId': '$orderId'},
      );
      if (!mounted) return;
    }

    context.go('/kasir');
  }

  // --------------------------------------------------------------------- view

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final async = ref.watch(orderContextProvider(widget.tableId));
    final data = async.valueOrNull;

    return Scaffold(
      backgroundColor: p.appBg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Pesanan Baru',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.gray900),
            ),
            Text(
              '${data?.table.tableNumber ?? 'Meja'} · ${widget.customerName}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: p.textMuted),
            ),
          ],
        ),
        actions: [
          Center(
            child: StatusBadge(
              text: orderTypeShortLabel(widget.orderType).toUpperCase(),
              tone: 'info',
              dense: true,
            ),
          ),
          SizedBox(width: sp(4)),
        ],
      ),
      body: Stack(
        children: [
          AsyncView<OrderContextData>(
            value: async,
            onRetry: () => ref.invalidate(orderContextProvider(widget.tableId)),
            builder: _menuBrowser,
          ),
          if (_submitting)
            Positioned.fill(
              child: AbsorbPointer(
                child: ColoredBox(
                  color: p.gray900.withValues(alpha: .35),
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 3)),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: data == null ? null : _cartBar(data),
    );
  }

  /// Filter kategori + pencarian + grid menu.
  Widget _menuBrowser(OrderContextData data) {
    final p = context.palette;
    final menus = _filteredMenus(data);

    return Column(
      children: [
        Container(
          color: p.surface,
          padding: EdgeInsets.fromLTRB(sp(4), sp(3), sp(4), sp(3)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SearchField(
                hint: 'Cari menu...',
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _search = v),
              ),
              SizedBox(height: sp(3)),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Semua'),
                      selected: _categoryId == null,
                      onSelected: (_) => setState(() => _categoryId = null),
                    ),
                    for (final cat in data.categories) ...[
                      SizedBox(width: sp(2)),
                      ChoiceChip(
                        label: Text(cat.name),
                        selected: _categoryId == cat.id,
                        onSelected: (_) => setState(() => _categoryId = cat.id),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: menus.isEmpty
              ? const EmptyState(
                  message: 'Menu tidak ditemukan. Coba ubah kata kunci atau kategori.',
                  icon: Icons.restaurant_menu_rounded,
                )
              : LayoutBuilder(
                  builder: (context, c) => GridView.builder(
                    padding: EdgeInsets.fromLTRB(sp(4), sp(4), sp(4), sp(6)),
                    itemCount: menus.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: c.maxWidth > 560 ? 3 : 2,
                      mainAxisSpacing: sp(3),
                      crossAxisSpacing: sp(3),
                      // Gambar tetap 96px, blok teks ikut skala huruf perangkat.
                      mainAxisExtent:
                          96 + 114 * (MediaQuery.textScalerOf(context).scale(14) / 14),
                    ),
                    itemBuilder: (context, i) => _MenuTile(
                      menu: menus[i],
                      onTap: _submitting ? null : () => _addToCart(menus[i]),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  /// Bar bawah: selalu terlihat, menampilkan jumlah item + total.
  Widget _cartBar(OrderContextData data) {
    final p = context.palette;
    final totals = _totals(data);

    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(sp(4), sp(2.5), sp(4), sp(2.5)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$_itemCount item · ${_cart.length} menu',
                      style: TextStyle(fontSize: 11.5, color: p.textMuted),
                    ),
                    SizedBox(height: sp(0.5)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        Fmt.rupiah(totals.grandTotal),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: p.gray900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: sp(3)),
              ElevatedButton.icon(
                onPressed: _submitting ? null : () => _openCartSheet(data),
                icon: const Icon(Icons.shopping_cart_rounded, size: 18),
                label: const Text('Lihat Keranjang'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- sheet: bill

  Future<void> _openCartSheet(OrderContextData data) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final p = ctx.palette;
          final media = MediaQuery.of(ctx);
          final totals = _totals(data);
          final height = math.max(
            260.0,
            media.size.height * .85 - media.viewInsets.bottom,
          );

          return Padding(
            padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
            child: SizedBox(
              height: height,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: sp(3)),
                  const _SheetHandle(),
                  Padding(
                    padding: EdgeInsets.fromLTRB(sp(4), sp(2), sp(2), 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: SectionHeader(
                            title: 'Bill Pesanan',
                            subtitle: '$_itemCount item · ${widget.customerName}',
                            icon: Icons.receipt_long_rounded,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Tutup',
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded, size: 20),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _cart.isEmpty
                        ? const EmptyState(
                            message: 'Keranjang masih kosong.',
                            icon: Icons.shopping_cart_outlined,
                          )
                        : ListView(
                            padding: EdgeInsets.fromLTRB(sp(4), sp(2), sp(4), sp(4)),
                            children: [
                              for (final line in List<CartLine>.of(_cart))
                                _cartLineTile(line, setSheet),
                              Divider(height: sp(8), color: p.border),
                              DropdownButtonFormField<int?>(
                                initialValue: _promoId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Gunakan Promo / Diskon',
                                  prefixIcon: Icon(Icons.local_offer_outlined, size: 20),
                                ),
                                items: [
                                  const DropdownMenuItem<int?>(
                                    value: null,
                                    child: Text(
                                      '-- Tidak Pakai Promo --',
                                      style: TextStyle(fontSize: 14),
                                    ),
                                  ),
                                  for (final promo in data.promos)
                                    DropdownMenuItem<int?>(
                                      value: promo.id,
                                      child: Text(
                                        promo.label ?? promo.name,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                ],
                                onChanged: (v) {
                                  setState(() => _promoId = v);
                                  setSheet(() {});
                                },
                              ),
                              SizedBox(height: sp(4)),
                              SummaryRow(
                                label: 'Subtotal',
                                value: Fmt.rupiah(totals.subtotal),
                                tone: 'primary',
                              ),
                              if (totals.discount > 0)
                                SummaryRow(
                                  label: 'Diskon Promo',
                                  value: '- ${Fmt.rupiah(totals.discount)}',
                                  tone: 'danger',
                                ),
                              SummaryRow(
                                label: 'Pajak (${data.setting.taxRate}%)',
                                value: Fmt.rupiah(totals.tax),
                                tone: 'warning',
                              ),
                              Divider(height: sp(6), color: p.border),
                              SummaryRow(
                                label: 'Grand Total',
                                value: Fmt.rupiah(totals.grandTotal),
                                tone: 'success',
                                bold: true,
                                big: true,
                              ),
                            ],
                          ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: p.surface,
                      border: Border(top: BorderSide(color: p.border)),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(sp(4), sp(3), sp(4), sp(3)),
                        child: SizedBox(
                          height: sp(13),
                          child: ElevatedButton.icon(
                            onPressed: _cart.isEmpty
                                ? null
                                : () {
                                    Navigator.pop(ctx);
                                    _openPaymentSheet(data);
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: p.success,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.payments_rounded, size: 18),
                            label: const Text('Bayar & Proses'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _cartLineTile(CartLine line, StateSetter setSheet) {
    final p = context.palette;

    return Padding(
      padding: EdgeInsets.only(bottom: sp(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _MenuImage(
                url: line.menu.imageUrl,
                height: 44,
                width: 44,
                radius: AppRadius.sm,
                iconSize: 18,
              ),
              SizedBox(width: sp(3)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.menu.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: p.gray800,
                      ),
                    ),
                    Text(
                      '${Fmt.rupiah(line.menu.finalPrice)} / porsi',
                      style: TextStyle(fontSize: 11, color: p.textMuted),
                    ),
                  ],
                ),
              ),
              SizedBox(width: sp(2)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Fmt.rupiah(line.subtotal),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: p.gray900,
                    ),
                  ),
                  SizedBox(height: sp(1.5)),
                  Row(
                    children: [
                      _RoundIconButton(
                        icon: line.qty == 1
                            ? Icons.delete_outline_rounded
                            : Icons.remove_rounded,
                        tone: line.qty == 1 ? 'danger' : 'secondary',
                        onTap: () {
                          if (line.qty == 1) {
                            _removeLine(line);
                          } else {
                            setState(() => line.qty -= 1);
                          }
                          setSheet(() {});
                        },
                      ),
                      SizedBox(width: sp(2.5)),
                      SizedBox(
                        width: sp(6),
                        child: Text(
                          '${line.qty}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: p.gray900,
                          ),
                        ),
                      ),
                      SizedBox(width: sp(2.5)),
                      _RoundIconButton(
                        icon: Icons.add_rounded,
                        tone: 'primary',
                        onTap: () {
                          setState(() => line.qty += 1);
                          setSheet(() {});
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: sp(2)),
          TextField(
            controller: _noteCtrlFor(line),
            style: const TextStyle(fontSize: 12.5),
            textInputAction: TextInputAction.done,
            onChanged: (v) {
              final note = v.trim();
              line.note = note.isEmpty ? null : note;
            },
            decoration: InputDecoration(
              hintText: 'Catatan: pedas, tanpa es...',
              isDense: true,
              hintStyle: TextStyle(fontSize: 12.5, color: p.textMuted),
              prefixIcon: const Icon(Icons.edit_note_rounded, size: 18),
              prefixIconConstraints: BoxConstraints(minWidth: sp(9), minHeight: sp(8)),
              contentPadding: EdgeInsets.symmetric(horizontal: sp(2), vertical: sp(2.5)),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- sheet: bayar

  Future<void> _openPaymentSheet(OrderContextData data) async {
    final intent = await showModalBottomSheet<_PayIntent>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _PaymentSheet(grandTotal: _totals(data).grandTotal),
    );

    if (intent == null || !mounted) return;
    await _submit(intent);
  }
}

// ===========================================================================
// KARTU MENU
// ===========================================================================

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.menu, this.onTap});

  final MenuModel menu;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MenuImage(url: menu.imageUrl, height: 96),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(sp(2.5)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    menu.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: p.gray900,
                      height: 1.25,
                    ),
                  ),
                  const Spacer(),
                  if (menu.categoryName != null)
                    StatusBadge(text: menu.categoryName!, tone: 'info', dense: true),
                  SizedBox(height: sp(1.5)),
                  if (menu.hasDiscount) ...[
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            Fmt.rupiah(menu.price),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: p.textMuted,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ),
                        SizedBox(width: sp(1.5)),
                        StatusBadge(
                          text: '-${menu.discountPercent}%',
                          tone: 'danger',
                          dense: true,
                        ),
                      ],
                    ),
                    Text(
                      Fmt.rupiah(menu.finalPrice),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: p.success,
                      ),
                    ),
                  ] else
                    Text(
                      Fmt.rupiah(menu.price),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: p.success,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuImage extends StatelessWidget {
  const _MenuImage({
    this.url,
    this.height = 96,
    this.width,
    this.radius = 0,
    this.iconSize = 28,
  });

  final String? url;
  final double height;
  final double? width;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    final fallback = Container(
      height: height,
      width: width ?? double.infinity,
      color: p.gray100,
      alignment: Alignment.center,
      child: Icon(Icons.restaurant_rounded, size: iconSize, color: p.gray400),
    );

    final child = (url == null || url!.isEmpty)
        ? fallback
        : CachedNetworkImage(
            imageUrl: url!,
            height: height,
            width: width ?? double.infinity,
            fit: BoxFit.cover,
            placeholder: (_, _) => Container(
              height: height,
              width: width ?? double.infinity,
              color: p.gray100,
            ),
            errorWidget: (_, _, _) => fallback,
          );

    return radius == 0
        ? child
        : ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }
}

// ===========================================================================
// SHEET PEMBAYARAN
// ===========================================================================

class _PayIntent {
  const _PayIntent({required this.method, this.cashReceived});

  /// pay_later | cash
  final String method;
  final double? cashReceived;

  bool get isCash => method == 'cash';
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.grandTotal});

  final double grandTotal;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  final _cashCtrl = TextEditingController();
  String _method = 'pay_later';

  @override
  void dispose() {
    _cashCtrl.dispose();
    super.dispose();
  }

  bool get _isCash => _method == 'cash';
  double get _cash => parseMoneyInput(_cashCtrl.text);
  double get _change => math.max(0, _cash - widget.grandTotal);

  void _submit() {
    if (_isCash && _cash < widget.grandTotal) {
      showSnack(context, 'Nominal uang tidak cukup.', error: true);
      return;
    }

    Navigator.pop(
      context,
      _PayIntent(method: _method, cashReceived: _isCash ? _cash : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Padding(
      padding: EdgeInsets.only(
        left: sp(5),
        right: sp(5),
        top: sp(3),
        bottom: MediaQuery.of(context).viewInsets.bottom + sp(5),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHandle(),
            SizedBox(height: sp(2)),
            const SectionHeader(
              title: 'Proses Pembayaran',
              subtitle: 'Pilih metode pembayaran pelanggan',
              icon: Icons.point_of_sale_rounded,
            ),
            SizedBox(height: sp(4)),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: sp(4), vertical: sp(3.5)),
              decoration: BoxDecoration(
                color: p.successLight,
                borderRadius: BorderRadius.circular(AppRadius.base),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total yang Harus Dibayar',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: p.success,
                    ),
                  ),
                  SizedBox(height: sp(1)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      Fmt.rupiah(widget.grandTotal),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: p.gray900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: sp(4)),
            _MethodOption(
              label: 'Bayar Nanti (Pay Later)',
              caption: 'Pesanan dikirim ke dapur, ditagih saat pelanggan selesai',
              icon: Icons.schedule_rounded,
              selected: _method == 'pay_later',
              onTap: () => setState(() => _method = 'pay_later'),
            ),
            SizedBox(height: sp(2.5)),
            _MethodOption(
              label: 'Tunai (Cash)',
              caption: 'Bayar sekarang, hitung kembalian otomatis',
              icon: Icons.payments_rounded,
              selected: _isCash,
              onTap: () => setState(() => _method = 'cash'),
            ),
            if (_isCash) ...[
              SizedBox(height: sp(4)),
              Text(
                'Nominal Uang Diterima',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: p.gray700,
                ),
              ),
              SizedBox(height: sp(2)),
              TextField(
                controller: _cashCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: '0', prefixText: 'Rp '),
              ),
              SizedBox(height: sp(2)),
              SummaryRow(
                label: 'Kembalian',
                value: Fmt.rupiah(_change),
                tone: 'primary',
                bold: true,
              ),
            ],
            SizedBox(height: sp(5)),
            SizedBox(
              height: sp(13),
              child: ElevatedButton.icon(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: p.success,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: const Text('Proses Pembayaran'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodOption extends StatelessWidget {
  const _MethodOption({
    required this.label,
    required this.caption,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String caption;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return AppCard(
      onTap: onTap,
      color: selected ? p.primaryLight : p.surface,
      borderColor: selected ? p.primary : p.border,
      padding: EdgeInsets.symmetric(horizontal: sp(3.5), vertical: sp(3)),
      child: Row(
        children: [
          Icon(icon, size: 20, color: selected ? p.primary : p.gray500),
          SizedBox(width: sp(3)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? p.primary : p.gray800,
                  ),
                ),
                SizedBox(height: sp(0.5)),
                Text(
                  caption,
                  style: TextStyle(fontSize: 11, color: p.textMuted, height: 1.3),
                ),
              ],
            ),
          ),
          Icon(
            selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
            size: 20,
            color: selected ? p.primary : p.gray400,
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// KOMPONEN KECIL
// ===========================================================================

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap, this.tone = 'primary'});

  final IconData icon;
  final VoidCallback onTap;
  final String tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final accent = p.solidOf(tone);

    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        height: 28,
        width: 28,
        decoration: BoxDecoration(color: p.softOf(tone), shape: BoxShape.circle),
        child: Icon(icon, size: 16, color: accent),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        height: 4,
        width: 44,
        decoration: BoxDecoration(
          color: context.palette.gray300,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
    );
  }
}
