import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import 'kasir_providers.dart';

/// Struk pembayaran — tampilan nota thermal (monospace, lebar maksimum 420).
class ReceiptScreen extends ConsumerWidget {
  const ReceiptScreen({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final receipt = ref.watch(receiptProvider(orderId));

    return Scaffold(
      backgroundColor: p.appBg,
      appBar: AppBar(
        title: const Text('Struk Pembayaran'),
        actions: [
          IconButton(
            tooltip: 'Cetak / Bagikan',
            onPressed: () => showSnack(context, 'Fitur cetak/bagikan struk akan ditambahkan.'),
            icon: const Icon(Icons.share_outlined),
          ),
          SizedBox(width: sp(1)),
        ],
      ),
      body: AsyncView<ReceiptData>(
        value: receipt,
        onRetry: () => ref.invalidate(receiptProvider(orderId)),
        builder: (d) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(sp(4), sp(4), sp(4), sp(10)),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AppCard(
                padding: EdgeInsets.symmetric(horizontal: sp(5), vertical: sp(6)),
                child: _Ticket(data: d),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Ticket extends StatelessWidget {
  const _Ticket({required this.data});

  final ReceiptData data;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final order = data.order;
    final setting = data.setting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ===== Kepala nota =====
        Text(
          setting.storeName,
          textAlign: TextAlign.center,
          style: _mono(size: 17, weight: FontWeight.w700, color: p.gray900),
        ),
        if (setting.address != null) ...[
          SizedBox(height: sp(1)),
          Text(
            setting.address!,
            textAlign: TextAlign.center,
            style: _mono(size: 11.5, color: p.textMuted),
          ),
        ],
        if (setting.phone != null)
          Text(
            'Telp: ${setting.phone}',
            textAlign: TextAlign.center,
            style: _mono(size: 11.5, color: p.textMuted),
          ),

        SizedBox(height: sp(3)),
        const _DashedLine(),
        SizedBox(height: sp(3)),

        // ===== Info transaksi =====
        _InfoRow(label: 'No', value: order.invoiceNo),
        _InfoRow(label: 'Tanggal', value: Fmt.dateTime(order.createdAt)),
        _InfoRow(label: 'Kasir', value: data.cashierName ?? '-'),
        _InfoRow(label: 'Meja', value: order.tableNumber ?? 'Walk-in'),
        _InfoRow(label: 'Pelanggan', value: order.customerName ?? '-'),
        _InfoRow(label: 'Tipe', value: orderTypeShortLabel(order.orderType)),

        SizedBox(height: sp(3)),
        const _DashedLine(),
        SizedBox(height: sp(3)),

        // ===== Item =====
        if (order.details.isEmpty)
          Text(
            'Tidak ada item pada pesanan ini.',
            style: _mono(size: 12, color: p.textMuted),
          ),
        for (final item in order.details)
          Padding(
            padding: EdgeInsets.only(bottom: sp(2)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${item.qty}x ${item.menuName}',
                        style: _mono(size: 12.5, weight: FontWeight.w600, color: p.gray900),
                      ),
                    ),
                    SizedBox(width: sp(2)),
                    Text(
                      Fmt.rupiah(item.subtotal),
                      style: _mono(size: 12.5, weight: FontWeight.w700, color: p.gray900),
                    ),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.only(left: sp(3)),
                  child: Text(
                    '@ ${Fmt.rupiah(item.price)}',
                    style: _mono(size: 11, color: p.textMuted),
                  ),
                ),
                if (item.notes != null && item.notes!.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(left: sp(3)),
                    child: Text(
                      '* ${item.notes}',
                      style: _mono(size: 11, color: p.textMuted, italic: true),
                    ),
                  ),
              ],
            ),
          ),

        SizedBox(height: sp(2)),
        const _DashedLine(),
        SizedBox(height: sp(3)),

        // ===== Ringkasan =====
        _AmountRow(label: 'Subtotal', value: Fmt.rupiah(order.subtotal)),
        if (order.discountAmount > 0)
          _AmountRow(
            label: 'Diskon${order.promoName != null ? ' (${order.promoName})' : ''}',
            value: '- ${Fmt.rupiah(order.discountAmount)}',
          ),
        _AmountRow(
          label: 'Pajak (${setting.taxRate}%)',
          value: Fmt.rupiah(order.tax),
        ),
        SizedBox(height: sp(1)),
        const _DashedLine(),
        SizedBox(height: sp(1)),
        _AmountRow(
          label: 'TOTAL',
          value: Fmt.rupiah(order.grandTotal),
          size: 15.5,
          bold: true,
        ),
        SizedBox(height: sp(1)),
        _AmountRow(
          label: 'Metode',
          value: order.paymentMethod == null
              ? 'BELUM BAYAR'
              : order.paymentMethod!.toUpperCase(),
        ),
        _AmountRow(
          label: 'Status',
          value: order.isPaid ? 'LUNAS' : 'BELUM BAYAR',
        ),

        SizedBox(height: sp(3)),
        const _DashedLine(),
        SizedBox(height: sp(3)),

        // ===== Kaki nota =====
        Text(
          'Terima kasih atas kunjungan Anda 🙏',
          textAlign: TextAlign.center,
          style: _mono(size: 12, weight: FontWeight.w600, color: p.gray800),
        ),
        SizedBox(height: sp(1)),
        Text(
          'Silakan datang kembali.',
          textAlign: TextAlign.center,
          style: _mono(size: 11, color: p.textMuted),
        ),
        if (data.printedAt != null) ...[
          SizedBox(height: sp(2)),
          Text(
            'Dicetak: ${Fmt.dateTime(data.printedAt)}',
            textAlign: TextAlign.center,
            style: _mono(size: 10.5, color: p.textMuted),
          ),
        ],
      ],
    );
  }
}

/// Baris `Label : Nilai` di kepala nota.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Padding(
      padding: EdgeInsets.only(bottom: sp(0.5)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(label, style: _mono(size: 12, color: p.gray600)),
          ),
          Text(': ', style: _mono(size: 12, color: p.gray600)),
          Expanded(
            child: Text(
              value,
              style: _mono(size: 12, weight: FontWeight.w600, color: p.gray900),
            ),
          ),
        ],
      ),
    );
  }
}

/// Baris nominal (label kiri, angka kanan).
class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.value,
    this.size = 12.5,
    this.bold = false,
  });

  final String label;
  final String value;
  final double size;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final weight = bold ? FontWeight.w700 : FontWeight.w500;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: sp(0.5)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: _mono(size: size, weight: weight, color: bold ? p.gray900 : p.gray700),
            ),
          ),
          SizedBox(width: sp(2)),
          Text(
            value,
            style: _mono(size: size, weight: bold ? FontWeight.w700 : FontWeight.w600, color: p.gray900),
          ),
        ],
      ),
    );
  }
}

/// Garis putus-putus seperti nota thermal.
class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) {
    final color = context.palette.borderDashed;

    return LayoutBuilder(
      builder: (context, c) {
        const dash = 4.0;
        const gap = 3.0;
        final count = (c.maxWidth / (dash + gap)).floor().clamp(1, 200);

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) => Container(width: dash, height: 1, color: color),
          ),
        );
      },
    );
  }
}

/// Gaya huruf nota: monospace agar terasa seperti struk printer thermal.
TextStyle _mono({
  double size = 12.5,
  FontWeight weight = FontWeight.w400,
  Color? color,
  bool italic = false,
}) =>
    TextStyle(
      fontFamily: 'monospace',
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: 1.45,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    );
