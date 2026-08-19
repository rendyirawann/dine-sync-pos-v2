import '../core/utils/formatters.dart';

class OrderDetailModel {
  const OrderDetailModel({
    required this.id,
    required this.menuId,
    required this.menuName,
    required this.qty,
    required this.price,
    required this.subtotal,
    required this.status,
    required this.statusLabel,
    required this.statusColor,
    this.notes,
    this.hpp = 0,
    this.isStockDeducted = false,
    this.menuImageUrl,
  });

  final int id;
  final int menuId;
  final String menuName;
  final int qty;
  final double price;
  final double subtotal;
  final double hpp;
  final String? notes;

  /// pending | cooking | done
  final String status;
  final String statusLabel;
  final String statusColor;
  final bool isStockDeducted;
  final String? menuImageUrl;

  bool get isDone => status == 'done';
  bool get isPending => status == 'pending';
  bool get isCooking => status == 'cooking';

  factory OrderDetailModel.fromJson(Map<String, dynamic> j) => OrderDetailModel(
        id: J.toInt(j['id']),
        menuId: J.toInt(j['menu_id']),
        menuName: J.toStr(j['menu_name']) ?? 'Menu Dihapus',
        qty: J.toInt(j['qty']),
        price: J.toDouble(j['price']),
        subtotal: J.toDouble(j['subtotal']),
        hpp: J.toDouble(j['hpp']),
        notes: J.toStr(j['notes']),
        status: J.toStr(j['status']) ?? 'pending',
        statusLabel: J.toStr(j['status_label']) ?? 'Antre',
        statusColor: J.toStr(j['status_color']) ?? 'warning',
        isStockDeducted: J.toBool(j['is_stock_deducted']),
        menuImageUrl: J.toStr(j['menu_image_url']),
      );
}

class OrderModel {
  const OrderModel({
    required this.id,
    required this.invoiceNo,
    required this.grandTotal,
    required this.paymentStatus,
    required this.orderStatus,
    required this.orderStatusLabel,
    this.uuid,
    this.tableId,
    this.tableNumber,
    this.customerName,
    this.orderType,
    this.orderTypeLabel,
    this.subtotal = 0,
    this.discountAmount = 0,
    this.tax = 0,
    this.promoName,
    this.paymentMethod,
    this.totalHpp,
    this.details = const [],
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String? uuid;
  final String invoiceNo;
  final int? tableId;
  final String? tableNumber;
  final String? customerName;
  final String? orderType;
  final String? orderTypeLabel;
  final double subtotal;
  final double discountAmount;
  final double tax;
  final double grandTotal;
  final String? promoName;

  /// cash | null (pay later)
  final String? paymentMethod;

  /// unpaid | paid | failed
  final String paymentStatus;

  /// pending | cooking | served | completed
  final String orderStatus;
  final String orderStatusLabel;
  final double? totalHpp;
  final List<OrderDetailModel> details;
  final String? createdAt;
  final String? updatedAt;

  bool get isPaid => paymentStatus == 'paid';
  bool get isUnpaid => paymentStatus == 'unpaid';
  bool get hasPendingItems => details.any((d) => d.isPending);
  bool get allItemsDone => details.isNotEmpty && details.every((d) => d.isDone);

  /// Nomor pendek untuk layar dapur/TV: `#193045`
  String get shortNumber {
    final parts = invoiceNo.split('-');
    return parts.length > 1 ? '#${parts.last}' : '#$invoiceNo';
  }

  factory OrderModel.fromJson(Map<String, dynamic> j) => OrderModel(
        id: J.toInt(j['id']),
        uuid: J.toStr(j['uuid']),
        invoiceNo: J.toStr(j['invoice_no']) ?? '-',
        tableId: j['table_id'] == null ? null : J.toInt(j['table_id']),
        tableNumber: J.toStr(j['table_number']),
        customerName: J.toStr(j['customer_name']),
        orderType: J.toStr(j['order_type']),
        orderTypeLabel: J.toStr(j['order_type_label']),
        subtotal: J.toDouble(j['subtotal']),
        discountAmount: J.toDouble(j['discount_amount']),
        tax: J.toDouble(j['tax']),
        grandTotal: J.toDouble(j['grand_total']),
        promoName: J.toStr(j['promo_name']),
        paymentMethod: J.toStr(j['payment_method']),
        paymentStatus: J.toStr(j['payment_status']) ?? 'unpaid',
        orderStatus: J.toStr(j['order_status']) ?? 'pending',
        orderStatusLabel: J.toStr(j['order_status_label']) ?? 'Menunggu Dibuat',
        totalHpp: j['total_hpp'] == null ? null : J.toDouble(j['total_hpp']),
        details: (j['details'] is List)
            ? (j['details'] as List)
                .whereType<Map<String, dynamic>>()
                .map(OrderDetailModel.fromJson)
                .toList()
            : const [],
        createdAt: J.toStr(j['created_at']),
        updatedAt: J.toStr(j['updated_at']),
      );
}

/// Satu baris keranjang di layar kasir (state lokal sebelum dikirim ke server).
class CartLine {
  CartLine({
    required this.menu,
    this.qty = 1,
    this.note,
  });

  final MenuLite menu;
  int qty;
  String? note;

  double get subtotal => menu.finalPrice * qty;

  Map<String, dynamic> toPayload() => {
        'id': menu.id,
        'qty': qty,
        if (note != null && note!.isNotEmpty) 'note': note,
      };
}

/// Data menu minimal yang dibutuhkan keranjang.
class MenuLite {
  const MenuLite({
    required this.id,
    required this.name,
    required this.finalPrice,
    this.imageUrl,
  });

  final int id;
  final String name;
  final double finalPrice;
  final String? imageUrl;
}
