import '../core/utils/formatters.dart';

class CategoryModel {
  const CategoryModel({required this.id, required this.name, this.slug, this.menusCount});

  final int id;
  final String name;
  final String? slug;
  final int? menusCount;

  factory CategoryModel.fromJson(Map<String, dynamic> j) => CategoryModel(
        id: J.toInt(j['id']),
        name: J.toStr(j['name']) ?? '-',
        slug: J.toStr(j['slug']),
        menusCount: j['menus_count'] == null ? null : J.toInt(j['menus_count']),
      );
}

class MenuModel {
  const MenuModel({
    required this.id,
    required this.name,
    required this.price,
    required this.finalPrice,
    required this.isAvailable,
    this.uuid,
    this.description,
    this.discountPercent = 0,
    this.imageUrl,
    this.categoryId,
    this.categoryName,
  });

  final int id;
  final String? uuid;
  final String name;
  final String? description;
  final double price;
  final int discountPercent;
  final double finalPrice;
  final bool isAvailable;
  final String? imageUrl;
  final int? categoryId;
  final String? categoryName;

  bool get hasDiscount => discountPercent > 0;

  factory MenuModel.fromJson(Map<String, dynamic> j) => MenuModel(
        id: J.toInt(j['id']),
        uuid: J.toStr(j['uuid']),
        name: J.toStr(j['name']) ?? '-',
        description: J.toStr(j['description']),
        price: J.toDouble(j['price']),
        discountPercent: J.toInt(j['discount_percent']),
        finalPrice: J.toDouble(j['final_price'] ?? j['price']),
        isAvailable: J.toBool(j['is_available']),
        imageUrl: J.toStr(j['image_url']),
        categoryId: j['category_id'] == null ? null : J.toInt(j['category_id']),
        categoryName: J.toStr(j['category_name']),
      );
}

class TableModel {
  const TableModel({
    required this.id,
    required this.tableNumber,
    required this.capacity,
    required this.status,
    required this.statusLabel,
    required this.statusColor,
    this.uuid,
    this.paymentStatus,
    this.qrPayload,
  });

  final int id;
  final String? uuid;
  final String tableNumber;
  final int capacity;

  /// available | occupied
  final String status;

  /// unpaid | paid | null — dihitung server dari order aktif
  final String? paymentStatus;

  /// KOSONG | BELUM BAYAR | TERISI (LUNAS)
  final String statusLabel;

  /// success | warning | danger
  final String statusColor;
  final String? qrPayload;

  bool get isAvailable => status == 'available';
  bool get isUnpaid => paymentStatus == 'unpaid';

  factory TableModel.fromJson(Map<String, dynamic> j) => TableModel(
        id: J.toInt(j['id']),
        uuid: J.toStr(j['uuid']),
        tableNumber: J.toStr(j['table_number']) ?? '-',
        capacity: J.toInt(j['capacity']),
        status: J.toStr(j['status']) ?? 'available',
        paymentStatus: J.toStr(j['payment_status']),
        statusLabel: J.toStr(j['status_label']) ?? 'KOSONG',
        statusColor: J.toStr(j['status_color']) ?? 'success',
        qrPayload: J.toStr(j['qr_payload']),
      );
}

class PromoModel {
  const PromoModel({
    required this.id,
    required this.name,
    required this.discountType,
    required this.discountValue,
    required this.isActive,
    this.label,
  });

  final int id;
  final String name;

  /// percentage | nominal
  final String discountType;
  final int discountValue;
  final bool isActive;
  final String? label;

  bool get isPercentage => discountType == 'percentage';

  factory PromoModel.fromJson(Map<String, dynamic> j) => PromoModel(
        id: J.toInt(j['id']),
        name: J.toStr(j['name']) ?? '-',
        discountType: J.toStr(j['discount_type']) ?? 'percentage',
        discountValue: J.toInt(j['discount_value']),
        isActive: J.toBool(j['is_active']),
        label: J.toStr(j['label']),
      );

  /// Hitung nominal diskon dari subtotal (mengikuti rumus server).
  double discountFor(double subtotal) => isPercentage
      ? (subtotal * discountValue / 100).roundToDouble()
      : discountValue.toDouble();
}

class SupplierModel {
  const SupplierModel({
    required this.id,
    required this.name,
    this.contactPerson,
    this.phone,
    this.address,
  });

  final int id;
  final String name;
  final String? contactPerson;
  final String? phone;
  final String? address;

  factory SupplierModel.fromJson(Map<String, dynamic> j) => SupplierModel(
        id: J.toInt(j['id']),
        name: J.toStr(j['name']) ?? '-',
        contactPerson: J.toStr(j['contact_person']),
        phone: J.toStr(j['phone']),
        address: J.toStr(j['address']),
      );
}

class IngredientModel {
  const IngredientModel({
    required this.id,
    required this.name,
    required this.unit,
    required this.minimumStock,
    required this.currentStock,
    required this.isLowStock,
    this.stockLabel,
  });

  final int id;
  final String name;
  final String unit;
  final double minimumStock;
  final double currentStock;
  final bool isLowStock;
  final String? stockLabel;

  factory IngredientModel.fromJson(Map<String, dynamic> j) => IngredientModel(
        id: J.toInt(j['id']),
        name: J.toStr(j['name']) ?? '-',
        unit: J.toStr(j['unit']) ?? '',
        minimumStock: J.toDouble(j['minimum_stock']),
        currentStock: J.toDouble(j['current_stock']),
        isLowStock: J.toBool(j['is_low_stock']),
        stockLabel: J.toStr(j['stock_label']),
      );
}

class SettingModel {
  const SettingModel({
    required this.storeName,
    required this.taxRate,
    this.address,
    this.phone,
  });

  final String storeName;
  final int taxRate;
  final String? address;
  final String? phone;

  factory SettingModel.fromJson(Map<String, dynamic> j) => SettingModel(
        storeName: J.toStr(j['store_name']) ?? 'DineSync POS',
        taxRate: J.toInt(j['tax_rate']),
        address: J.toStr(j['address']),
        phone: J.toStr(j['phone']),
      );
}
