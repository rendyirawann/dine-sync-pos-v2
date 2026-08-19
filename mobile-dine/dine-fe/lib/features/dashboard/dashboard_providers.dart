import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/master.dart';
import '../../models/ops.dart';

/// Ringkasan bulan ini (omzet, HPP, operasional, laba bersih).
final dashboardSummaryProvider = FutureProvider<DashboardSummary>((ref) async {
  final res = await ref.watch(apiClientProvider).get('/dashboard/summary');
  return DashboardSummary.fromJson(res.asMap);
});

/// Widget harian: target penjualan & budget (identitas sidebar web).
final dailyWidgetProvider = FutureProvider<DailyWidget>((ref) async {
  final res = await ref.watch(apiClientProvider).get('/dashboard/daily');
  return DailyWidget.fromJson(res.asMap);
});

/// Grafik omzet aktual vs target.
final dashboardChartProvider = FutureProvider<ChartData>((ref) async {
  final res = await ref.watch(apiClientProvider).get('/dashboard/chart');
  return ChartData.fromJson(res.asMap);
});

/// Top 5 menu terlaris bulan ini.
final topMenusProvider = FutureProvider<List<TopMenu>>((ref) async {
  final res = await ref.watch(apiClientProvider).get('/dashboard/top-menus');
  return res.asList.map(TopMenu.fromJson).toList();
});

/// Menu yang sedang habis (is_available = false).
final unavailableMenusProvider = FutureProvider<List<MenuModel>>((ref) async {
  final res = await ref.watch(apiClientProvider).get('/dashboard/unavailable-menus');
  return res.asList.map(MenuModel.fromJson).toList();
});

/// Muat ulang seluruh data dashboard sekaligus (dipakai pull-to-refresh).
Future<void> refreshDashboard(WidgetRef ref) async {
  ref.invalidate(dashboardSummaryProvider);
  ref.invalidate(dailyWidgetProvider);
  ref.invalidate(dashboardChartProvider);
  ref.invalidate(topMenusProvider);
  ref.invalidate(unavailableMenusProvider);

  await Future.wait([
    ref.read(dashboardSummaryProvider.future),
    ref.read(dailyWidgetProvider.future),
  ]);
}
