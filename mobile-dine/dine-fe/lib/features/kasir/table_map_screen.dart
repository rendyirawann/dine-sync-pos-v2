import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import '../../models/master.dart';
import '../../models/order.dart';
import '../home/home_shell.dart';
import 'kasir_providers.dart';

/// Peta meja — layar utama kasir (padanan `kasir/index` di web).
/// [embedded] true bila dipakai sebagai tab di HomeShell (tanpa tombol back).
class TableMapScreen extends ConsumerWidget {
  const TableMapScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final map = ref.watch(tableMapProvider);

    return Scaffold(
      backgroundColor: p.appBg,
      appBar: embedded
          ? const TenantAppBar(title: 'Kasir')
          : AppBar(title: const Text('Peta Meja')),
      body: RefreshIndicator(
        onRefresh: () => refreshKasir(ref),
        child: ListView(
          padding: EdgeInsets.fromLTRB(sp(4), sp(4), sp(4), sp(10)),
          children: [
            AsyncView<TableMapData>(
              value: map,
              onRetry: () => ref.invalidate(tableMapProvider),
              builder: (d) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Shift belum dibuka → peringatkan, TAPI jangan blokir daftar meja.
                  if (!d.hasOpenShift) ...[
                    const _ShiftWarning(),
                    SizedBox(height: sp(4)),
                  ],
                  _SummaryCards(summary: d.summary),
                  SizedBox(height: sp(5)),
                  SectionHeader(
                    title: 'Daftar Meja',
                    subtitle: '${d.summary.total} meja · ketuk meja untuk melayani',
                    icon: Icons.grid_view_rounded,
                  ),
                  SizedBox(height: sp(3)),
                  if (d.tables.isEmpty)
                    const EmptyState(
                      message: 'Belum ada meja terdaftar.\nTambahkan meja lewat menu Data Master.',
                      icon: Icons.table_restaurant_rounded,
                    )
                  else
                    _TableGrid(tables: d.tables),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner peringatan shift belum dibuka.
class _ShiftWarning extends StatelessWidget {
  const _ShiftWarning();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return AppCard(
      color: p.warningLight,
      borderColor: p.warning.withValues(alpha: .45),
      padding: EdgeInsets.all(sp(4)),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: p.warning, size: 26),
          SizedBox(width: sp(3)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Shift belum dibuka. Buka shift dulu untuk mulai transaksi.',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: p.gray800,
                    height: 1.4,
                  ),
                ),
                SizedBox(height: sp(2)),
                SizedBox(
                  height: sp(9),
                  child: ElevatedButton.icon(
                    onPressed: () => context.push('/shift'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: p.warning,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: sp(4)),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    icon: const Icon(Icons.lock_open_rounded, size: 16),
                    label: const Text('Buka Shift'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tiga kartu ringkasan status meja.
class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.summary});

  final TableSummary summary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'Kosong',
            value: '${summary.empty} meja',
            tone: 'success',
            icon: Icons.check_circle_outline_rounded,
            compact: true,
          ),
        ),
        SizedBox(width: sp(3)),
        Expanded(
          child: StatCard(
            label: 'Belum Bayar',
            value: '${summary.unpaid} meja',
            tone: 'warning',
            icon: Icons.hourglass_bottom_rounded,
            compact: true,
          ),
        ),
        SizedBox(width: sp(3)),
        Expanded(
          child: StatCard(
            label: 'Lunas',
            value: '${summary.paid} meja',
            tone: 'danger',
            icon: Icons.task_alt_rounded,
            compact: true,
          ),
        ),
      ],
    );
  }
}

/// Grid meja responsif: 2 kolom di HP sempit, 3 di >420, 4 di >620.
class _TableGrid extends ConsumerWidget {
  const _TableGrid({required this.tables});

  final List<TableModel> tables;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth > 620
            ? 4
            : c.maxWidth > 420
                ? 3
                : 2;

        // Bagian teks ikut membesar bila pengguna memakai font besar.
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;

        return GridView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tables.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: sp(3),
            crossAxisSpacing: sp(3),
            mainAxisExtent: 62 + 78 * scale,
          ),
          itemBuilder: (context, i) => _TableTile(
            table: tables[i],
            onTap: () => _openTable(context, ref, tables[i]),
          ),
        );
      },
    );
  }
}

class _TableTile extends StatelessWidget {
  const _TableTile({required this.table, required this.onTap});

  final TableModel table;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final accent = p.solidOf(table.statusColor);

    return AppCard(
      onTap: onTap,
      color: p.softOf(table.statusColor),
      borderColor: accent,
      padding: EdgeInsets.all(sp(3)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.table_restaurant_rounded, size: 28, color: accent),
          SizedBox(height: sp(2)),
          Text(
            table.tableNumber,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.gray900),
          ),
          SizedBox(height: sp(1)),
          Text(
            table.statusLabel.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: accent,
              height: 1.2,
            ),
          ),
          SizedBox(height: sp(0.5)),
          Text(
            'Kapasitas: ${table.capacity}',
            style: TextStyle(fontSize: 11, color: p.textMuted),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// AKSI KETUK MEJA
// ===========================================================================

Future<void> _openTable(BuildContext context, WidgetRef ref, TableModel table) {
  return table.isAvailable
      ? _openEmptyTableSheet(context, ref, table)
      : _openOccupiedSheet(context, ref, table);
}

/// Meja kosong → tanya nama pelanggan & tipe pesanan, lanjut ke layar pesanan.
Future<void> _openEmptyTableSheet(BuildContext context, WidgetRef ref, TableModel table) async {
  final intent = await showModalBottomSheet<_NewOrderIntent>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _EmptyTableSheet(table: table),
  );

  if (intent == null || !context.mounted) return;

  await context.pushNamed(
    'kasir-order',
    pathParameters: {'tableId': '${table.id}'},
    queryParameters: {'customer': intent.customerName, 'type': intent.orderType},
  );

  // Kembali dari layar pesanan → peta meja bisa saja berubah.
  if (context.mounted) ref.invalidate(tableMapProvider);
}

/// Meja terisi → tampilkan semua invoice aktif + aksi bayar / struk / kosongkan.
Future<void> _openOccupiedSheet(BuildContext context, WidgetRef ref, TableModel table) async {
  final outcome = await showModalBottomSheet<_SheetOutcome>(
    context: context,
    isScrollControlled: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .85),
    builder: (ctx) => _OccupiedSheet(table: table),
  );

  if (!context.mounted) return;

  ref.invalidate(tableMapProvider);
  ref.invalidate(tableDetailProvider(table.id));

  if (outcome == null) return;

  showSnack(context, outcome.message);

  if (outcome.paidOrderId != null) {
    await _offerReceipt(context, orderId: outcome.paidOrderId!, change: outcome.change);
  }
}

/// Tawarkan cetak struk setelah pembayaran berhasil.
Future<void> _offerReceipt(
  BuildContext context, {
  required int orderId,
  double change = 0,
}) async {
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

  if (wantPrint == true && context.mounted) {
    context.pushNamed('kasir-receipt', pathParameters: {'orderId': '$orderId'});
  }
}

/// Hasil yang dibawa keluar dari bottom sheet meja terisi.
class _SheetOutcome {
  const _SheetOutcome({required this.message, this.paidOrderId, this.change = 0});

  final String message;
  final int? paidOrderId;
  final double change;
}

class _NewOrderIntent {
  const _NewOrderIntent({required this.customerName, required this.orderType});

  final String customerName;
  final String orderType;
}

// ===========================================================================
// SHEET: MEJA KOSONG
// ===========================================================================

class _EmptyTableSheet extends StatefulWidget {
  const _EmptyTableSheet({required this.table});

  final TableModel table;

  @override
  State<_EmptyTableSheet> createState() => _EmptyTableSheetState();
}

class _EmptyTableSheetState extends State<_EmptyTableSheet> {
  final _nameCtrl = TextEditingController();
  String _type = kOrderTypes.first.value;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Nama pelanggan wajib diisi.', error: true);
      return;
    }
    Navigator.pop(context, _NewOrderIntent(customerName: name, orderType: _type));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: sp(5),
        right: sp(5),
        top: sp(3),
        bottom: MediaQuery.of(context).viewInsets.bottom + sp(5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SheetHandle(),
          SizedBox(height: sp(2)),
          SectionHeader(
            title: 'Meja Kosong',
            subtitle:
                '${widget.table.tableNumber} · Kapasitas ${widget.table.capacity} orang',
            icon: Icons.table_restaurant_rounded,
          ),
          SizedBox(height: sp(5)),
          _FieldLabel('Nama Pelanggan'),
          SizedBox(height: sp(2)),
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              hintText: 'Contoh: Budi',
              prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
            ),
          ),
          SizedBox(height: sp(4)),
          _FieldLabel('Tipe Pesanan'),
          SizedBox(height: sp(2)),
          DropdownButtonFormField<String>(
            initialValue: _type,
            isExpanded: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.room_service_outlined, size: 20),
            ),
            items: kOrderTypes
                .map((t) => DropdownMenuItem(
                      value: t.value,
                      child: Text(t.label, style: const TextStyle(fontSize: 14)),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          SizedBox(height: sp(6)),
          SizedBox(
            height: sp(13),
            child: ElevatedButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.restaurant_menu_rounded, size: 18),
              label: const Text('Buka Menu Pesanan'),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// SHEET: MEJA TERISI
// ===========================================================================

class _OccupiedSheet extends ConsumerStatefulWidget {
  const _OccupiedSheet({required this.table});

  final TableModel table;

  @override
  ConsumerState<_OccupiedSheet> createState() => _OccupiedSheetState();
}

class _OccupiedSheetState extends ConsumerState<_OccupiedSheet> {
  bool _clearing = false;

  Future<void> _clearTable() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kosongkan Meja?'),
        content: const Text(
          'Pastikan pelanggan sudah selesai. Meja akan kembali tersedia.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ctx.palette.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Kosongkan'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _clearing = true);

    try {
      final res = await ref.read(kasirActionsProvider).clearTable(widget.table.id);
      if (!mounted) return;
      Navigator.pop(context, _SheetOutcome(message: res.message));
    } on ApiException catch (e) {
      // Mis. 400: masih ada item dapur yang belum selesai → pesan dari server.
      if (!mounted) return;
      setState(() => _clearing = false);
      showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final detail = ref.watch(tableDetailProvider(widget.table.id));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(sp(4), sp(3), sp(4), sp(4)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHandle(),
            SizedBox(height: sp(2)),
            Row(
              children: [
                Expanded(
                  child: SectionHeader(
                    title: 'Meja ${widget.table.tableNumber}',
                    subtitle: 'Pesanan aktif di meja ini',
                    icon: Icons.receipt_long_rounded,
                  ),
                ),
                IconButton(
                  tooltip: 'Tutup',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
            SizedBox(height: sp(3)),
            SizedBox(
              height: sp(11),
              child: OutlinedButton.icon(
                onPressed: _clearing ? null : _clearTable,
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.danger,
                  side: BorderSide(color: p.danger.withValues(alpha: .5)),
                  backgroundColor: p.dangerLight,
                ),
                icon: _clearing
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cleaning_services_rounded, size: 18),
                label: Text(_clearing ? 'Memproses...' : 'Kosongkan Meja'),
              ),
            ),
            SizedBox(height: sp(4)),
            Flexible(
              child: AsyncView<TableDetailData>(
                value: detail,
                onRetry: () => ref.invalidate(tableDetailProvider(widget.table.id)),
                builder: (d) {
                  if (d.isAvailable || d.orders.isEmpty) {
                    return const EmptyState(
                      message: 'Tidak ada pesanan aktif. Meja ini sudah kosong.',
                      icon: Icons.check_circle_outline_rounded,
                      compact: true,
                    );
                  }

                  return ListView(
                    padding: EdgeInsets.only(bottom: sp(2)),
                    children: [
                      for (final order in d.orders) _OrderCard(order: order),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Satu invoice aktif di dalam sheet meja terisi.
class _OrderCard extends ConsumerWidget {
  const _OrderCard({required this.order});

  final OrderModel order;

  Future<void> _pay(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_PayResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PayOrderDialog(order: order),
    );

    if (result == null || !context.mounted) return;

    // Tutup sheet & bawa hasilnya ke layar peta meja.
    Navigator.pop(
      context,
      _SheetOutcome(
        message: 'Pembayaran lunas!',
        paidOrderId: order.id,
        change: result.change,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;

    return AppCard(
      margin: EdgeInsets.only(bottom: sp(3)),
      padding: EdgeInsets.all(sp(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '#${order.invoiceNo}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: p.gray900,
                  ),
                ),
              ),
              SizedBox(width: sp(2)),
              StatusBadge(
                text: orderTypeShortLabel(order.orderType).toUpperCase(),
                tone: 'info',
                dense: true,
              ),
            ],
          ),
          SizedBox(height: sp(1)),
          Text(
            'Pelanggan: ${order.customerName ?? '-'}',
            style: TextStyle(fontSize: 12, color: p.textMuted),
          ),
          SizedBox(height: sp(2.5)),
          Row(
            children: [
              StatusBadge(
                text: order.orderStatusLabel,
                tone: orderStatusTone(order.orderStatus),
                icon: Icons.local_fire_department_rounded,
                dense: true,
              ),
              SizedBox(width: sp(2)),
              StatusBadge(
                text: order.isPaid ? 'LUNAS' : 'BELUM BAYAR',
                tone: order.isPaid ? 'success' : 'warning',
                dense: true,
              ),
            ],
          ),
          Divider(height: sp(6), color: p.border),
          for (final item in order.details)
            Padding(
              padding: EdgeInsets.symmetric(vertical: sp(1)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: sp(7),
                    child: Text(
                      '${item.qty}x',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: p.primary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.menuName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: p.gray800,
                          ),
                        ),
                        if (item.notes != null && item.notes!.isNotEmpty)
                          Text(
                            item.notes!,
                            style: TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: p.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(width: sp(2)),
                  StatusBadge(text: item.statusLabel, tone: item.statusColor, dense: true),
                ],
              ),
            ),
          Divider(height: sp(6), color: p.border),
          SummaryRow(
            label: 'Total Tagihan',
            value: Fmt.rupiah(order.grandTotal),
            tone: 'success',
            bold: true,
          ),
          SizedBox(height: sp(3)),
          SizedBox(
            height: sp(11),
            child: order.isUnpaid
                ? ElevatedButton.icon(
                    onPressed: () => _pay(context, ref),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: p.success,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.payments_rounded, size: 18),
                    label: const Text('Lanjutkan Pembayaran'),
                  )
                : OutlinedButton.icon(
                    onPressed: () => context.pushNamed(
                      'kasir-receipt',
                      pathParameters: {'orderId': '${order.id}'},
                    ),
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text('Cetak Struk'),
                  ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// DIALOG PEMBAYARAN (order lama / Pay Later)
// ===========================================================================

class _PayResult {
  const _PayResult({required this.change});

  final double change;
}

class _PayOrderDialog extends ConsumerStatefulWidget {
  const _PayOrderDialog({required this.order});

  final OrderModel order;

  @override
  ConsumerState<_PayOrderDialog> createState() => _PayOrderDialogState();
}

class _PayOrderDialogState extends ConsumerState<_PayOrderDialog> {
  final _cashCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _cashCtrl.dispose();
    super.dispose();
  }

  double get _total => widget.order.grandTotal;
  double get _cash => parseMoneyInput(_cashCtrl.text);
  double get _change => math.max(0, _cash - _total);

  Future<void> _submit() async {
    if (_cash < _total) {
      showSnack(context, 'Nominal uang tidak cukup.', error: true);
      return;
    }

    setState(() => _busy = true);

    try {
      final res = await ref.read(kasirActionsProvider).payOrder(
            orderId: widget.order.id,
            cashReceived: _cash,
          );

      if (!mounted) return;
      Navigator.pop(context, _PayResult(change: J.toDouble(res.asMap['change'])));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return AlertDialog(
      title: const Text('Pembayaran Tunai'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: sp(4), vertical: sp(3)),
              decoration: BoxDecoration(
                color: p.successLight,
                borderRadius: BorderRadius.circular(AppRadius.base),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Tagihan',
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
                      Fmt.rupiah(_total),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: p.gray900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: sp(4)),
            _FieldLabel('Uang Diterima (Rp)'),
            SizedBox(height: sp(2)),
            TextField(
              controller: _cashCtrl,
              enabled: !_busy,
              autofocus: true,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: '0',
                prefixText: 'Rp ',
              ),
            ),
            SizedBox(height: sp(3)),
            SummaryRow(
              label: 'Kembalian',
              value: Fmt.rupiah(_change),
              tone: 'primary',
              bold: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: p.success,
            foregroundColor: Colors.white,
          ),
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                )
              : const Text('Proses Pembayaran'),
        ),
      ],
    );
  }
}

// ===========================================================================
// KOMPONEN KECIL
// ===========================================================================

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

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: context.palette.gray700,
      ),
    );
  }
}
