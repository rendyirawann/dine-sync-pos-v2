import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import '../../models/ops.dart';
import '../home/home_shell.dart';
import 'dashboard_providers.dart';

/// Beranda: widget harian + ringkasan bulan ini + grafik + menu terlaris.
/// [embedded] true bila dipakai sebagai tab di HomeShell (tanpa tombol back).
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;

    return Scaffold(
      backgroundColor: p.appBg,
      appBar: embedded
          ? const TenantAppBar(title: 'Beranda')
          : AppBar(title: const Text('Dashboard')),
      body: RefreshIndicator(
        onRefresh: () => refreshDashboard(ref),
        child: ListView(
          padding: EdgeInsets.fromLTRB(sp(4), sp(4), sp(4), sp(10)),
          children: [
            const _DailyWidgets(),
            SizedBox(height: sp(5)),
            const SectionHeader(
              title: 'Ringkasan Bulan Ini',
              subtitle: 'Omzet, modal bahan, dan laba',
              icon: Icons.insights_outlined,
            ),
            SizedBox(height: sp(3)),
            const _SummaryGrid(),
            SizedBox(height: sp(5)),
            const _SalesChart(),
            SizedBox(height: sp(5)),
            const _TopMenus(),
            SizedBox(height: sp(5)),
            const _UnavailableMenus(),
          ],
        ),
      ),
    );
  }
}

/// Kartu target penjualan & pengeluaran harian (padanan widget sidebar web).
class _DailyWidgets extends ConsumerWidget {
  const _DailyWidgets();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final daily = ref.watch(dailyWidgetProvider);

    return AsyncView<DailyWidget>(
      value: daily,
      onRetry: () => ref.invalidate(dailyWidgetProvider),
      loading: const AppCard(
        child: SizedBox(height: 150, child: Center(child: CircularProgressIndicator(strokeWidth: 2.5))),
      ),
      builder: (d) => AppCard(
        padding: EdgeInsets.all(sp(4.5)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- Target penjualan hari ini ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Target Penjualan Hari Ini',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.gray800),
                ),
                Text(
                  Fmt.rupiah(d.salesTarget),
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.gray800),
                ),
              ],
            ),
            SizedBox(height: sp(2.5)),
            ThickProgressBar(percent: d.salesBarWidth, tone: d.salesColor),
            SizedBox(height: sp(2)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tercapai ${d.salesPercentage}%',
                  style: TextStyle(fontSize: 12, color: p.textMuted, fontWeight: FontWeight.w500),
                ),
                Text(
                  d.salesMessage,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: d.salesPercentage >= 100 ? p.success : p.warning,
                  ),
                ),
              ],
            ),

            Divider(height: sp(8), color: p.border),

            // --- Penjualan hari ini ---
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: sp(4), vertical: sp(3)),
              decoration: BoxDecoration(
                color: p.primaryLight,
                borderRadius: BorderRadius.circular(AppRadius.base),
                border: Border.all(color: p.primary.withValues(alpha: .35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Penjualan Hari Ini',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.primary),
                  ),
                  SizedBox(height: sp(1)),
                  Text(
                    Fmt.rupiah(d.income),
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: p.gray900),
                  ),
                ],
              ),
            ),

            SizedBox(height: sp(4)),

            // --- Budget vs terpakai ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Pengeluaran Harian',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.gray800),
                ),
                Text(
                  'Terpakai ${d.budgetPercentage}%',
                  style: TextStyle(fontSize: 12, color: p.textMuted, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            SizedBox(height: sp(2.5)),
            ThickProgressBar(percent: d.budgetPercentage, tone: d.budgetColor),
            SizedBox(height: sp(3)),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(label: 'Budget', value: d.budget, tone: 'success'),
                ),
                SizedBox(width: sp(3)),
                Expanded(
                  child: _MiniStat(label: 'Terpakai', value: d.spent, tone: 'danger'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.tone});

  final String label;
  final double value;
  final String tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: sp(3), vertical: sp(2.5)),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.base),
        border: Border.all(color: p.gray300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.gray500),
          ),
          SizedBox(height: sp(1)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Fmt.rupiah(value),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.solidOf(tone)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryGrid extends ConsumerWidget {
  const _SummaryGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dashboardSummaryProvider);

    return AsyncView<DashboardSummary>(
      value: summary,
      onRetry: () => ref.invalidate(dashboardSummaryProvider),
      loading: const AppCard(
        child: SizedBox(height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2.5))),
      ),
      builder: (s) => LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth > 560 ? 4 : 2;
          final cards = [
            StatCard(
              label: 'Total Omzet',
              value: Fmt.rupiah(s.revenue),
              tone: 'primary',
              icon: Icons.trending_up_rounded,
            ),
            StatCard(
              label: 'Total HPP (Modal Bahan)',
              value: Fmt.rupiah(s.hpp),
              tone: 'danger',
              icon: Icons.inventory_2_outlined,
            ),
            StatCard(
              label: 'Operasional',
              value: Fmt.rupiah(s.expense),
              tone: 'warning',
              icon: Icons.payments_outlined,
            ),
            StatCard(
              label: 'Laba Bersih',
              value: Fmt.rupiah(s.netProfit),
              tone: 'success',
              icon: Icons.savings_outlined,
            ),
          ];

          return GridView.count(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: cols,
            mainAxisSpacing: sp(3),
            crossAxisSpacing: sp(3),
            childAspectRatio: 1.55,
            children: cards,
          );
        },
      ),
    );
  }
}

class _SalesChart extends ConsumerWidget {
  const _SalesChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final chart = ref.watch(dashboardChartProvider);

    return AppCard(
      padding: EdgeInsets.all(sp(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Performa Harian',
            subtitle: 'Omzet aktual vs target (bulan ini)',
            icon: Icons.show_chart_rounded,
          ),
          SizedBox(height: sp(4)),
          SizedBox(
            height: 200,
            child: AsyncView<ChartData>(
              value: chart,
              onRetry: () => ref.invalidate(dashboardChartProvider),
              builder: (d) {
                if (d.categories.isEmpty) {
                  return const EmptyState(
                    message: 'Belum ada data penjualan bulan ini.',
                    icon: Icons.show_chart_rounded,
                    compact: true,
                  );
                }

                final maxY = [
                  ...d.sales,
                  ...d.targets,
                  1.0,
                ].reduce((a, b) => a > b ? a : b);

                return LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: maxY * 1.15,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) =>
                          FlLine(color: p.border, strokeWidth: 1, dashArray: [4, 4]),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 44,
                          getTitlesWidget: (v, meta) => Text(
                            Fmt.rupiahShort(v).replaceAll('Rp ', ''),
                            style: TextStyle(fontSize: 9, color: p.gray500),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 26,
                          interval: (d.categories.length / 5).ceilToDouble().clamp(1, 999),
                          getTitlesWidget: (v, meta) {
                            final i = v.toInt();
                            if (i < 0 || i >= d.categories.length) return const SizedBox.shrink();
                            return Padding(
                              padding: EdgeInsets.only(top: sp(1)),
                              child: Text(
                                d.categories[i],
                                style: TextStyle(fontSize: 9, color: p.gray500),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (spots) => spots
                            .map((s) => LineTooltipItem(
                                  Fmt.rupiah(s.y),
                                  TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: s.barIndex == 0 ? p.primary : p.danger,
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                    lineBarsData: [
                      // Omzet aktual
                      LineChartBarData(
                        spots: [
                          for (var i = 0; i < d.sales.length; i++)
                            FlSpot(i.toDouble(), d.sales[i]),
                        ],
                        isCurved: true,
                        barWidth: 2.5,
                        color: p.primary,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: p.primary.withValues(alpha: .12),
                        ),
                      ),
                      // Target
                      LineChartBarData(
                        spots: [
                          for (var i = 0; i < d.targets.length; i++)
                            FlSpot(i.toDouble(), d.targets[i]),
                        ],
                        isCurved: true,
                        barWidth: 2,
                        color: p.danger,
                        dashArray: [5, 4],
                        dotData: const FlDotData(show: false),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          SizedBox(height: sp(3)),
          Row(
            children: [
              _Legend(color: p.primary, label: 'Omzet Aktual'),
              SizedBox(width: sp(4)),
              _Legend(color: p.danger, label: 'Target'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          height: 8,
          width: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: sp(1.5)),
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: context.palette.textMuted),
        ),
      ],
    );
  }
}

class _TopMenus extends ConsumerWidget {
  const _TopMenus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final top = ref.watch(topMenusProvider);

    return AppCard(
      padding: EdgeInsets.all(sp(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Menu Paling Laku',
            subtitle: 'Top 5 penjualan bulan ini',
            icon: Icons.emoji_events_outlined,
          ),
          SizedBox(height: sp(2)),
          AsyncView<List<TopMenu>>(
            value: top,
            onRetry: () => ref.invalidate(topMenusProvider),
            builder: (items) {
              if (items.isEmpty) {
                return const EmptyState(
                  message: 'Belum ada data pesanan bulan ini.',
                  icon: Icons.receipt_long_outlined,
                  compact: true,
                );
              }

              return Column(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: sp(1.5)),
                      child: Row(
                        children: [
                          Container(
                            height: sp(8),
                            width: sp(8),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: p.primaryLight,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: p.primary,
                              ),
                            ),
                          ),
                          SizedBox(width: sp(3)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  items[i].menuName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: p.gray800,
                                  ),
                                ),
                                Text(
                                  items[i].categoryName ?? '-',
                                  style: TextStyle(fontSize: 11, color: p.textMuted),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${items[i].totalQty} Porsi',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: p.gray900,
                                ),
                              ),
                              Text(
                                Fmt.rupiah(items[i].totalRevenue),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: p.success,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _UnavailableMenus extends ConsumerWidget {
  const _UnavailableMenus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final menus = ref.watch(unavailableMenusProvider);

    return AppCard(
      padding: EdgeInsets.all(sp(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Daftar Menu Habis',
            subtitle: 'Menu yang tidak tersedia untuk dipesan',
            icon: Icons.warning_amber_rounded,
            trailing: menus.maybeWhen(
              data: (m) => m.isEmpty
                  ? null
                  : StatusBadge(text: '${m.length} menu', tone: 'danger', dense: true),
              orElse: () => null,
            ),
          ),
          SizedBox(height: sp(2)),
          AsyncView(
            value: menus,
            onRetry: () => ref.invalidate(unavailableMenusProvider),
            builder: (items) {
              if (items.isEmpty) {
                return const EmptyState(
                  message: 'Semua menu saat ini tersedia! 🎉',
                  icon: Icons.check_circle_outline_rounded,
                  compact: true,
                );
              }

              return Column(
                children: [
                  for (final m in items)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: sp(1.5)),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.name,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: p.gray800,
                                  ),
                                ),
                                Text(
                                  m.categoryName ?? 'Tanpa Kategori',
                                  style: TextStyle(fontSize: 11, color: p.textMuted),
                                ),
                              ],
                            ),
                          ),
                          const StatusBadge(
                            text: 'Habis',
                            tone: 'danger',
                            icon: Icons.cancel_outlined,
                            dense: true,
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
