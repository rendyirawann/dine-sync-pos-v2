import '../core/utils/formatters.dart';

class QueueModel {
  const QueueModel({
    required this.id,
    required this.queueNumber,
    required this.customerName,
    required this.pax,
    required this.status,
    required this.statusLabel,
    required this.statusColor,
    this.category,
    this.time,
  });

  final int id;
  final String queueNumber;
  final String customerName;
  final int pax;

  /// waiting | called | seated | cancelled
  final String status;
  final String statusLabel;
  final String statusColor;

  /// A | B | C
  final String? category;
  final String? time;

  bool get isSeated => status == 'seated';

  factory QueueModel.fromJson(Map<String, dynamic> j) => QueueModel(
        id: J.toInt(j['id']),
        queueNumber: J.toStr(j['queue_number']) ?? '-',
        customerName: J.toStr(j['customer_name']) ?? '-',
        pax: J.toInt(j['pax']),
        status: J.toStr(j['status']) ?? 'waiting',
        statusLabel: J.toStr(j['status_label']) ?? 'Menunggu',
        statusColor: J.toStr(j['status_color']) ?? 'warning',
        category: J.toStr(j['category']),
        time: J.toStr(j['time']),
      );
}

class ShiftModel {
  const ShiftModel({
    required this.id,
    required this.status,
    required this.startingCash,
    required this.cashSales,
    this.startTime,
    this.endTime,
    this.expectedCash,
    this.actualCash,
    this.difference,
    this.differenceLabel,
    this.differenceColor,
    this.userName,
  });

  final int id;

  /// open | closed
  final String status;
  final double startingCash;
  final double cashSales;
  final String? startTime;
  final String? endTime;
  final double? expectedCash;
  final double? actualCash;
  final double? difference;
  final String? differenceLabel;
  final String? differenceColor;
  final String? userName;

  bool get isOpen => status == 'open';

  factory ShiftModel.fromJson(Map<String, dynamic> j) => ShiftModel(
        id: J.toInt(j['id']),
        status: J.toStr(j['status']) ?? 'open',
        startingCash: J.toDouble(j['starting_cash']),
        cashSales: J.toDouble(j['cash_sales']),
        startTime: J.toStr(j['start_time']),
        endTime: J.toStr(j['end_time']),
        expectedCash: j['expected_cash'] == null ? null : J.toDouble(j['expected_cash']),
        actualCash: j['actual_cash'] == null ? null : J.toDouble(j['actual_cash']),
        difference: j['difference'] == null ? null : J.toDouble(j['difference']),
        differenceLabel: J.toStr(j['difference_label']),
        differenceColor: J.toStr(j['difference_color']),
        userName: J.toStr(j['user_name']),
      );
}

class ExpenseModel {
  const ExpenseModel({
    required this.id,
    required this.category,
    required this.amount,
    this.date,
    this.notes,
    this.userName,
  });

  final int id;
  final String category;
  final double amount;
  final String? date;
  final String? notes;
  final String? userName;

  factory ExpenseModel.fromJson(Map<String, dynamic> j) => ExpenseModel(
        id: J.toInt(j['id']),
        category: J.toStr(j['category']) ?? '-',
        amount: J.toDouble(j['amount']),
        date: J.toStr(j['date']),
        notes: J.toStr(j['notes']),
        userName: J.toStr(j['user_name']),
      );
}

/// Ringkasan dashboard (bulan ini) — sama dengan 4 kartu di web.
class DashboardSummary {
  const DashboardSummary({
    required this.revenue,
    required this.hpp,
    required this.expense,
    required this.grossProfit,
    required this.netProfit,
    required this.itemsSold,
  });

  final double revenue;
  final double hpp;
  final double expense;
  final double grossProfit;
  final double netProfit;
  final int itemsSold;

  factory DashboardSummary.fromJson(Map<String, dynamic> j) => DashboardSummary(
        revenue: J.toDouble(j['revenue']),
        hpp: J.toDouble(j['hpp']),
        expense: J.toDouble(j['expense']),
        grossProfit: J.toDouble(j['gross_profit']),
        netProfit: J.toDouble(j['net_profit']),
        itemsSold: J.toInt(j['items_sold']),
      );

  static const empty = DashboardSummary(
    revenue: 0,
    hpp: 0,
    expense: 0,
    grossProfit: 0,
    netProfit: 0,
    itemsSold: 0,
  );
}

/// Widget harian (target penjualan, omzet, budget) — identitas sidebar web.
class DailyWidget {
  const DailyWidget({
    required this.salesTarget,
    required this.income,
    required this.salesPercentage,
    required this.salesBarWidth,
    required this.salesColor,
    required this.salesMessage,
    required this.budget,
    required this.spent,
    required this.budgetPercentage,
    required this.budgetColor,
  });

  final double salesTarget;
  final double income;
  final int salesPercentage;
  final int salesBarWidth;
  final String salesColor;
  final String salesMessage;
  final double budget;
  final double spent;
  final int budgetPercentage;
  final String budgetColor;

  factory DailyWidget.fromJson(Map<String, dynamic> j) => DailyWidget(
        salesTarget: J.toDouble(j['sales_target']),
        income: J.toDouble(j['income']),
        salesPercentage: J.toInt(j['sales_percentage']),
        salesBarWidth: J.toInt(j['sales_bar_width']),
        salesColor: J.toStr(j['sales_color']) ?? 'warning',
        salesMessage: J.toStr(j['sales_message']) ?? 'Ayo Semangat! 💪',
        budget: J.toDouble(j['budget']),
        spent: J.toDouble(j['spent']),
        budgetPercentage: J.toInt(j['budget_percentage']),
        budgetColor: J.toStr(j['budget_color']) ?? 'primary',
      );

  static const empty = DailyWidget(
    salesTarget: 0,
    income: 0,
    salesPercentage: 0,
    salesBarWidth: 0,
    salesColor: 'warning',
    salesMessage: 'Ayo Semangat! 💪',
    budget: 0,
    spent: 0,
    budgetPercentage: 0,
    budgetColor: 'primary',
  );
}

/// Satu baris menu terlaris.
class TopMenu {
  const TopMenu({
    required this.menuName,
    required this.totalQty,
    required this.totalRevenue,
    this.categoryName,
  });

  final String menuName;
  final String? categoryName;
  final int totalQty;
  final double totalRevenue;

  factory TopMenu.fromJson(Map<String, dynamic> j) => TopMenu(
        menuName: J.toStr(j['menu_name']) ?? 'Menu Dihapus',
        categoryName: J.toStr(j['category_name']),
        totalQty: J.toInt(j['total_qty']),
        totalRevenue: J.toDouble(j['total_revenue']),
      );
}

/// Data grafik omzet vs target.
class ChartData {
  const ChartData({required this.categories, required this.sales, required this.targets});

  final List<String> categories;
  final List<double> sales;
  final List<double> targets;

  factory ChartData.fromJson(Map<String, dynamic> j) => ChartData(
        categories: (j['categories'] as List? ?? []).map((e) => '$e').toList(),
        sales: (j['sales'] as List? ?? []).map(J.toDouble).toList(),
        targets: (j['targets'] as List? ?? []).map(J.toDouble).toList(),
      );

  static const empty = ChartData(categories: [], sales: [], targets: []);
}
