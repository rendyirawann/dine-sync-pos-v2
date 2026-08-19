import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/utils/formatters.dart';
import '../../models/master.dart';
import '../../models/ops.dart';
import '../../models/order.dart';

// ===========================================================================
// MODEL TAMPILAN (bentuknya mengikuti response `data` dari dine-be)
// ===========================================================================

/// Ringkasan jumlah meja per status (`summary` di `GET /kasir/tables`).
class TableSummary {
  const TableSummary({
    required this.empty,
    required this.unpaid,
    required this.paid,
    required this.total,
  });

  final int empty;
  final int unpaid;
  final int paid;
  final int total;

  factory TableSummary.fromJson(Map<String, dynamic> j) => TableSummary(
        empty: J.toInt(j['empty']),
        unpaid: J.toInt(j['unpaid']),
        paid: J.toInt(j['paid']),
        total: J.toInt(j['total']),
      );

  static const empty$ = TableSummary(empty: 0, unpaid: 0, paid: 0, total: 0);
}

/// Peta meja: daftar meja + ringkasan + shift aktif kasir (bisa null).
class TableMapData {
  const TableMapData({
    required this.tables,
    required this.summary,
    this.activeShift,
  });

  final List<TableModel> tables;
  final TableSummary summary;
  final ShiftModel? activeShift;

  bool get hasOpenShift => activeShift != null;

  factory TableMapData.fromJson(Map<String, dynamic> j) => TableMapData(
        tables: (j['tables'] is List)
            ? (j['tables'] as List)
                .whereType<Map<String, dynamic>>()
                .map(TableModel.fromJson)
                .toList()
            : const [],
        summary: j['summary'] is Map<String, dynamic>
            ? TableSummary.fromJson(j['summary'] as Map<String, dynamic>)
            : TableSummary.empty$,
        activeShift: j['active_shift'] is Map<String, dynamic>
            ? ShiftModel.fromJson(j['active_shift'] as Map<String, dynamic>)
            : null,
      );
}

/// Detail satu meja: bila `available` daftar order kosong.
class TableDetailData {
  const TableDetailData({
    required this.status,
    required this.table,
    this.orders = const [],
  });

  /// available | occupied
  final String status;
  final TableModel table;
  final List<OrderModel> orders;

  bool get isAvailable => status == 'available';

  factory TableDetailData.fromJson(Map<String, dynamic> j) => TableDetailData(
        status: J.toStr(j['status']) ?? 'available',
        table: TableModel.fromJson(
          j['table'] is Map<String, dynamic> ? j['table'] as Map<String, dynamic> : const {},
        ),
        orders: (j['orders'] is List)
            ? (j['orders'] as List)
                .whereType<Map<String, dynamic>>()
                .map(OrderModel.fromJson)
                .toList()
            : const [],
      );
}

/// Pilihan tipe pesanan (`order_types` dari server / meta lokal).
class OrderTypeOption {
  const OrderTypeOption({required this.value, required this.label});

  final String value;
  final String label;

  factory OrderTypeOption.fromJson(Map<String, dynamic> j) => OrderTypeOption(
        value: J.toStr(j['value']) ?? 'dine_in',
        label: J.toStr(j['label']) ?? '-',
      );
}

/// Semua data pendukung layar "Buat Pesanan" (sekali panggil).
class OrderContextData {
  const OrderContextData({
    required this.table,
    required this.categories,
    required this.menus,
    required this.promos,
    required this.setting,
    required this.orderTypes,
  });

  final TableModel table;
  final List<CategoryModel> categories;
  final List<MenuModel> menus;
  final List<PromoModel> promos;
  final SettingModel setting;
  final List<OrderTypeOption> orderTypes;

  /// Hanya menu yang benar-benar bisa dipesan (server sudah memfilter, ini jaga-jaga).
  List<MenuModel> get availableMenus => menus.where((m) => m.isAvailable).toList();

  factory OrderContextData.fromJson(Map<String, dynamic> j) => OrderContextData(
        table: TableModel.fromJson(
          j['table'] is Map<String, dynamic> ? j['table'] as Map<String, dynamic> : const {},
        ),
        categories: _mapList(j['categories'], CategoryModel.fromJson),
        menus: _mapList(j['menus'], MenuModel.fromJson),
        promos: _mapList(j['promos'], PromoModel.fromJson),
        setting: SettingModel.fromJson(
          j['setting'] is Map<String, dynamic> ? j['setting'] as Map<String, dynamic> : const {},
        ),
        orderTypes: _mapList(j['order_types'], OrderTypeOption.fromJson),
      );
}

/// Data struk siap tampil/cetak.
class ReceiptData {
  const ReceiptData({
    required this.order,
    required this.setting,
    this.printedAt,
    this.cashierName,
  });

  final OrderModel order;
  final SettingModel setting;
  final String? printedAt;
  final String? cashierName;

  factory ReceiptData.fromJson(Map<String, dynamic> j) => ReceiptData(
        order: OrderModel.fromJson(
          j['order'] is Map<String, dynamic> ? j['order'] as Map<String, dynamic> : const {},
        ),
        setting: SettingModel.fromJson(
          j['setting'] is Map<String, dynamic> ? j['setting'] as Map<String, dynamic> : const {},
        ),
        printedAt: J.toStr(j['printed_at']),
        cashierName: J.toStr(j['cashier_name']),
      );
}

List<T> _mapList<T>(dynamic raw, T Function(Map<String, dynamic>) fromJson) =>
    raw is List ? raw.whereType<Map<String, dynamic>>().map(fromJson).toList() : <T>[];

// ===========================================================================
// PROVIDER
// ===========================================================================

/// Peta meja + ringkasan + shift aktif.
final tableMapProvider = FutureProvider<TableMapData>((ref) async {
  final res = await ref.watch(apiClientProvider).get('/kasir/tables');
  return TableMapData.fromJson(res.asMap);
});

/// Detail satu meja beserta seluruh invoice aktifnya.
final tableDetailProvider = FutureProvider.family<TableDetailData, int>((ref, tableId) async {
  final res = await ref.watch(apiClientProvider).get('/kasir/tables/$tableId/detail');
  return TableDetailData.fromJson(res.asMap);
});

/// Konteks pembuatan pesanan untuk sebuah meja (menu, promo, pajak, dll).
final orderContextProvider = FutureProvider.family<OrderContextData, int>((ref, tableId) async {
  final res = await ref.watch(apiClientProvider).get('/kasir/order-context/$tableId');
  return OrderContextData.fromJson(res.asMap);
});

/// Data struk sebuah pesanan.
final receiptProvider = FutureProvider.family<ReceiptData, int>((ref, orderId) async {
  final res = await ref.watch(apiClientProvider).get('/kasir/orders/$orderId/receipt');
  return ReceiptData.fromJson(res.asMap);
});

/// Status shift kasir saat ini (`GET /shifts/current`).
final kasirShiftStatusProvider = FutureProvider<ShiftModel?>((ref) async {
  final res = await ref.watch(apiClientProvider).get('/shifts/current');
  final shift = res.asMap['shift'];
  return shift is Map<String, dynamic> ? ShiftModel.fromJson(shift) : null;
});

// ===========================================================================
// AKSI (POST) — kontrak payload dikumpulkan di satu tempat
// ===========================================================================

class KasirActions {
  const KasirActions(this._api);

  final ApiClient _api;

  /// `POST /kasir/orders` — buat pesanan baru (tunai atau bayar nanti).
  Future<ApiResponse> createOrder({
    required int tableId,
    required String customerName,
    required String orderType,
    required String paymentMethod,
    required List<Map<String, dynamic>> cart,
    int? promoId,
    double? cashReceived,
  }) =>
      _api.post('/kasir/orders', data: {
        'table_id': tableId,
        'customer_name': customerName,
        'order_type': orderType,
        'payment_method': paymentMethod,
        'promo_id': ?promoId,
        'cash_received': ?cashReceived,
        'cart': cart,
      });

  /// `POST /kasir/orders/{id}/pay` — lunasi pesanan Pay Later secara tunai.
  Future<ApiResponse> payOrder({required int orderId, double? cashReceived}) =>
      _api.post('/kasir/orders/$orderId/pay', data: {
        'payment_method': 'cash',
        'cash_received': ?cashReceived,
      });

  /// `POST /kasir/tables/{id}/clear` — tutup semua invoice & kembalikan meja.
  Future<ApiResponse> clearTable(int tableId) => _api.post('/kasir/tables/$tableId/clear');
}

final kasirActionsProvider = Provider<KasirActions>(
  (ref) => KasirActions(ref.watch(apiClientProvider)),
);

// ===========================================================================
// HELPER
// ===========================================================================

/// Muat ulang peta meja (dipakai pull-to-refresh & sesudah transaksi).
Future<void> refreshKasir(WidgetRef ref) async {
  ref.invalidate(tableMapProvider);
  await ref.read(tableMapProvider.future);
}

/// Pilihan tipe pesanan versi lokal (label sama dengan `order_types` server).
const kOrderTypes = <OrderTypeOption>[
  OrderTypeOption(value: 'dine_in', label: 'Dine In (Makan di Tempat)'),
  OrderTypeOption(value: 'take_away', label: 'Take Away (Bawa Pulang)'),
  OrderTypeOption(value: 'reservation', label: 'Reservasi (Booking)'),
];

/// Label pendek tipe pesanan untuk badge: `Dine In`, `Take Away`, `Reservasi`.
String orderTypeShortLabel(String? value) => switch (value) {
      'take_away' => 'Take Away',
      'reservation' => 'Reservasi',
      'dine_in' => 'Dine In',
      _ => 'Dine In',
    };

/// Warna badge status dapur — sama dengan badge di web.
String orderStatusTone(String status) => switch (status) {
      'pending' => 'warning',
      'cooking' => 'primary',
      'served' => 'success',
      'completed' => 'secondary',
      _ => 'secondary',
    };

/// Nominal uang dari input bebas (`50.000`, `Rp 50000`, dst).
double parseMoneyInput(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return 0;
  return double.tryParse(digits) ?? 0;
}

/// Hasil hitung keranjang — rumus & urutannya PERSIS seperti server
/// (`KasirController@storeOrder`): diskon promo dulu, pajak setelah diskon.
class CartTotals {
  const CartTotals({
    required this.subtotal,
    required this.discount,
    required this.netSubtotal,
    required this.tax,
    required this.grandTotal,
  });

  final double subtotal;
  final double discount;
  final double netSubtotal;
  final double tax;
  final double grandTotal;

  static const zero = CartTotals(
    subtotal: 0,
    discount: 0,
    netSubtotal: 0,
    tax: 0,
    grandTotal: 0,
  );
}

CartTotals computeCartTotals({
  required List<CartLine> cart,
  PromoModel? promo,
  required int taxRate,
}) {
  final subtotal = cart.fold<double>(0, (sum, line) => sum + line.subtotal);
  final discount = promo == null ? 0.0 : promo.discountFor(subtotal);
  final netSubtotal = math.max(0.0, subtotal - discount);
  final tax = (netSubtotal * taxRate / 100).roundToDouble();

  return CartTotals(
    subtotal: subtotal,
    discount: discount,
    netSubtotal: netSubtotal,
    tax: tax,
    grandTotal: netSubtotal + tax,
  );
}
