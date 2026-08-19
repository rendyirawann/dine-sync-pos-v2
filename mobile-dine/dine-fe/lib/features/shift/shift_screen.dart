import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import '../../models/ops.dart';
import 'shift_providers.dart';

/// Shift kasir: buka shift (modal laci + setup harian), pantau harapan uang di
/// laci, tutup shift dengan uang fisik, dan lihat riwayatnya.
class ShiftScreen extends ConsumerStatefulWidget {
  const ShiftScreen({super.key});

  @override
  ConsumerState<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends ConsumerState<ShiftScreen> {
  final _startingCash = TextEditingController();
  final _target = TextEditingController();
  final _budget = TextEditingController();
  final _actualCash = TextEditingController();

  bool _submitting = false;

  @override
  void dispose() {
    _startingCash.dispose();
    _target.dispose();
    _budget.dispose();
    _actualCash.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- data

  void _refresh() {
    ref.invalidate(currentShiftProvider);
    ref.invalidate(shiftHistoryProvider);
  }

  Future<void> _reload() async {
    _refresh();
    try {
      await ref.read(currentShiftProvider.future);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  /// Ambil angka dari field (pengguna boleh mengetik titik/spasi).
  double? _amount(TextEditingController c) {
    final digits = c.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return double.tryParse(digits);
  }

  // ---------------------------------------------------------------- aksi

  Future<void> _guard(Future<void> Function() body) async {
    if (_submitting) return;
    setState(() => _submitting = true);

    try {
      await body();
    } on ApiException catch (e) {
      // Termasuk 409 (masih ada pesanan menggantung) — cukup tampilkan pesannya.
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openShift(ShiftStatus status) async {
    final modal = _amount(_startingCash);
    if (modal == null) {
      showSnack(context, 'Modal uang kembalian laci wajib diisi.', error: true);
      return;
    }

    double? target;
    double? budget;

    if (status.isFirstShiftOfDay) {
      target = _amount(_target);
      budget = _amount(_budget);

      if (target == null || budget == null) {
        showSnack(
          context,
          'Target penjualan dan daily budget wajib diisi untuk shift pertama hari ini.',
          error: true,
        );
        return;
      }
    }

    await _guard(() async {
      final message = await ref.read(shiftRepoProvider).open(
            startingCash: modal,
            targetPenjualan: target,
            dailyBudget: budget,
          );

      if (!mounted) return;

      _startingCash.clear();
      _target.clear();
      _budget.clear();

      showSnack(context, message);
      _refresh();
    });
  }

  Future<void> _closeShift(ShiftModel shift) async {
    final actual = _amount(_actualCash);
    if (actual == null) {
      showSnack(context, 'Uang fisik aktual di laci wajib diisi.', error: true);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yakin tutup shift?'),
        content: const Text(
          'Pastikan uang fisik sudah dihitung benar. Aksi ini tidak dapat dibatalkan.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppPalette.light$.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Tutup'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    await _guard(() async {
      final message = await ref.read(shiftRepoProvider).close(
            id: shift.id,
            actualCash: actual,
          );

      if (!mounted) return;

      _actualCash.clear();
      showSnack(context, message);
      _refresh();
    });
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final status = ref.watch(currentShiftProvider);

    return Scaffold(
      backgroundColor: p.appBg,
      appBar: AppBar(
        title: const Text('Shift Kasir'),
        actions: [
          IconButton(
            tooltip: 'Muat Ulang',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: AsyncView<ShiftStatus>(
        value: status,
        onRetry: () => ref.invalidate(currentShiftProvider),
        builder: (s) => RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: EdgeInsets.fromLTRB(sp(4), sp(4), sp(4), sp(10)),
            children: [
              if (s.isOpen) _runningCard(s) else _closedCard(s),
              SizedBox(height: sp(6)),
              const SectionHeader(
                title: 'Riwayat Shift',
                subtitle: 'Shift yang sudah ditutup',
                icon: Icons.history_rounded,
              ),
              SizedBox(height: sp(3)),
              const _History(),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------- STATE A: belum dibuka

  Widget _closedCard(ShiftStatus s) {
    final p = context.palette;

    return AppCard(
      padding: EdgeInsets.all(sp(5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              padding: EdgeInsets.all(sp(4)),
              decoration: BoxDecoration(color: p.primaryLight, shape: BoxShape.circle),
              child: Icon(Icons.lock_clock_rounded, size: 40, color: p.primary),
            ),
          ),
          SizedBox(height: sp(4)),
          Text(
            'Shift Belum Dibuka',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.gray900),
          ),
          SizedBox(height: sp(2)),
          Text(
            'Anda harus membuka shift dan memasukkan modal kasir sebelum '
            'menggunakan menu Kasir.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: p.textMuted, height: 1.5),
          ),

          // Setup target & budget — hanya untuk shift pertama hari ini.
          if (s.isFirstShiftOfDay) ...[
            SizedBox(height: sp(5)),
            Container(
              padding: EdgeInsets.all(sp(4)),
              decoration: BoxDecoration(
                color: p.softOf('primary'),
                borderRadius: BorderRadius.circular(AppRadius.base),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.flag_rounded, size: 16, color: p.primary),
                      SizedBox(width: sp(2)),
                      Expanded(
                        child: Text(
                          'Setup Harian (Shift Pertama)',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: p.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: sp(1.5)),
                  Text(
                    'Karena Anda membuka shift pertama hari ini, tentukan target dan '
                    'budget harian.',
                    style: TextStyle(fontSize: 12, color: p.gray700, height: 1.5),
                  ),
                  SizedBox(height: sp(3.5)),
                  _moneyField(
                    controller: _target,
                    label: 'Target Penjualan Hari Ini (Rp)',
                  ),
                  SizedBox(height: sp(3)),
                  _moneyField(
                    controller: _budget,
                    label: 'Daily Budget (Rp)',
                  ),
                ],
              ),
            ),
          ],

          SizedBox(height: sp(5)),
          _moneyField(
            controller: _startingCash,
            label: 'Modal Uang Kembalian Laci (Rp)',
            big: true,
          ),
          SizedBox(height: sp(4)),
          ElevatedButton.icon(
            onPressed: _submitting ? null : () => _openShift(s),
            icon: const Icon(Icons.lock_open_rounded, size: 18),
            label: const Text('Buka Shift Sekarang'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------- STATE B: sedang jalan

  Widget _runningCard(ShiftStatus s) {
    final p = context.palette;
    final shift = s.shift!;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: p.softOf('primary'),
            padding: EdgeInsets.symmetric(horizontal: sp(4.5), vertical: sp(3.5)),
            child: Row(
              children: [
                Icon(Icons.play_circle_fill_rounded, size: 22, color: p.primary),
                SizedBox(width: sp(3)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Shift Sedang Berjalan',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: p.gray900,
                        ),
                      ),
                      SizedBox(height: sp(0.5)),
                      Text(
                        'Dimulai: ${Fmt.dateTime(shift.startTime)}',
                        style: TextStyle(fontSize: 11.5, color: p.textMuted),
                      ),
                    ],
                  ),
                ),
                if (shift.userName != null)
                  StatusBadge(text: shift.userName!, tone: 'primary', dense: true),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(sp(4.5)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SummaryRow(
                  label: 'Modal Awal Laci',
                  value: Fmt.rupiah(shift.startingCash),
                ),
                SummaryRow(
                  label: 'Total Penjualan Tunai',
                  value: '+ ${Fmt.rupiah(s.cashSales)}',
                  tone: 'success',
                ),
                Divider(height: sp(5), color: p.border),
                SummaryRow(
                  label: 'Harapan Uang di Laci',
                  value: Fmt.rupiah(s.expectedCash),
                  tone: 'primary',
                  bold: true,
                  big: true,
                ),
                SizedBox(height: sp(4)),

                // --- Panel tutup shift ---
                Container(
                  padding: EdgeInsets.all(sp(4)),
                  decoration: BoxDecoration(
                    color: p.softOf('warning'),
                    borderRadius: BorderRadius.circular(AppRadius.base),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.savings_rounded, size: 16, color: p.warning),
                          SizedBox(width: sp(2)),
                          Expanded(
                            child: Text(
                              'Hitung uang fisik di laci lalu masukkan totalnya untuk '
                              'menutup shift.',
                              style: TextStyle(fontSize: 12, color: p.gray700, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: sp(3.5)),
                      _moneyField(
                        controller: _actualCash,
                        label: 'Uang Fisik Aktual di Laci (Rp)',
                        big: true,
                      ),
                      SizedBox(height: sp(3.5)),
                      ElevatedButton.icon(
                        onPressed: _submitting ? null : () => _closeShift(shift),
                        icon: const Icon(Icons.lock_rounded, size: 18),
                        label: const Text('Tutup Shift'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: p.danger,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- field

  Widget _moneyField({
    required TextEditingController controller,
    required String label,
    bool big = false,
  }) {
    final p = context.palette;

    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: big ? TextAlign.center : TextAlign.start,
      style: TextStyle(
        fontSize: big ? 22 : 15,
        fontWeight: big ? FontWeight.w700 : FontWeight.w600,
        color: p.gray900,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: '0',
        floatingLabelAlignment:
            big ? FloatingLabelAlignment.center : FloatingLabelAlignment.start,
        fillColor: p.surface,
      ),
    );
  }
}

/// Riwayat shift yang sudah ditutup (halaman pertama).
class _History extends ConsumerWidget {
  const _History();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final history = ref.watch(shiftHistoryProvider);

    return AsyncView<List<ShiftModel>>(
      value: history,
      onRetry: () => ref.invalidate(shiftHistoryProvider),
      builder: (items) {
        if (items.isEmpty) {
          return const EmptyState(
            message: 'Belum ada riwayat shift.',
            icon: Icons.history_toggle_off_rounded,
            compact: true,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final s in items)
              Padding(
                padding: EdgeInsets.only(bottom: sp(3)),
                child: AppCard(
                  padding: EdgeInsets.all(sp(4)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.event_available_rounded, size: 15, color: p.gray500),
                          SizedBox(width: sp(2)),
                          Expanded(
                            child: Text(
                              '${Fmt.dateTime(s.startTime)} s/d ${Fmt.time(s.endTime)}',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: p.gray800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: sp(2.5)),
                      Row(
                        children: [
                          Expanded(
                            child: _MiniAmount(label: 'Modal', value: s.startingCash),
                          ),
                          SizedBox(width: sp(3)),
                          Expanded(
                            child: _MiniAmount(label: 'Aktual', value: s.actualCash),
                          ),
                        ],
                      ),
                      if (s.differenceLabel != null) ...[
                        SizedBox(height: sp(2.5)),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: StatusBadge(
                            text: s.differenceLabel!,
                            tone: s.differenceColor ?? 'secondary',
                            dense: true,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MiniAmount extends StatelessWidget {
  const _MiniAmount({required this.label, required this.value});

  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.gray500),
        ),
        SizedBox(height: sp(0.5)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            Fmt.rupiah(value),
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.gray900),
          ),
        ),
      ],
    );
  }
}
