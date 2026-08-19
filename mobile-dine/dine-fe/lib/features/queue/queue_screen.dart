import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/ui.dart';
import '../../models/ops.dart';
import '../home/home_shell.dart';
import 'queue_providers.dart';

/// Antrian pelanggan hari ini: ringkasan status, panggil ke TV (dengan cooldown),
/// dan menandai pelanggan sudah duduk.
class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  /// Hitung mundur cooldown panggilan suara (detik).
  int _cooldown = 0;
  Timer? _ticker;

  /// Antrian yang aksinya sedang dikirim ke server.
  final Set<String> _busy = <String>{};

  @override
  void initState() {
    super.initState();

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _cooldown <= 0) return;
      setState(() => _cooldown--);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }

  // ---------------------------------------------------------------- data

  void _refresh() => ref.invalidate(queueBoardProvider);

  Future<void> _reload() async {
    ref.invalidate(queueBoardProvider);
    try {
      await ref.read(queueBoardProvider.future);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  // ---------------------------------------------------------------- aksi

  Future<void> _guard(String key, Future<void> Function() body) async {
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));

    try {
      await body();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _call(QueueModel q) => _guard('call-${q.id}', () async {
        final r = await ref.read(queueRepoProvider).call(q.id);
        if (!mounted) return;

        setState(() => _cooldown = r.cooldownLeft);
        showSnack(context, r.message);
        _refresh();
      });

  Future<void> _seat(QueueModel q) => _guard('seat-${q.id}', () async {
        final message = await ref.read(queueRepoProvider).setStatus(q.id, 'seated');
        if (!mounted) return;

        showSnack(context, message);
        _refresh();
      });

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    // Sinkronkan cooldown dengan server setiap kali data antrian dimuat ulang.
    ref.listen<AsyncValue<QueueBoard>>(queueBoardProvider, (_, next) {
      next.whenData((b) {
        if (!mounted || b.cooldownLeft <= _cooldown) return;
        setState(() => _cooldown = b.cooldownLeft);
      });
    });

    final board = ref.watch(queueBoardProvider);

    final refreshButton = IconButton(
      tooltip: 'Muat Ulang',
      onPressed: _refresh,
      icon: const Icon(Icons.refresh_rounded),
    );

    return Scaffold(
      backgroundColor: p.appBg,
      appBar: widget.embedded
          ? TenantAppBar(title: 'Antrian', actions: [refreshButton])
          : AppBar(title: const Text('Antrian'), actions: [refreshButton]),
      body: AsyncView<QueueBoard>(
        value: board,
        onRetry: _refresh,
        builder: (b) => RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: EdgeInsets.fromLTRB(sp(4), sp(4), sp(4), sp(10)),
            children: [
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      label: 'Menunggu',
                      value: '${b.waiting}',
                      tone: 'warning',
                      icon: Icons.hourglass_bottom_rounded,
                      compact: true,
                    ),
                  ),
                  SizedBox(width: sp(3)),
                  Expanded(
                    child: StatCard(
                      label: 'Dipanggil',
                      value: '${b.called}',
                      tone: 'primary',
                      icon: Icons.campaign_rounded,
                      compact: true,
                    ),
                  ),
                  SizedBox(width: sp(3)),
                  Expanded(
                    child: StatCard(
                      label: 'Sudah Duduk',
                      value: '${b.seated}',
                      tone: 'success',
                      icon: Icons.chair_alt_rounded,
                      compact: true,
                    ),
                  ),
                ],
              ),
              SizedBox(height: sp(5)),
              SectionHeader(
                title: 'Daftar Antrian Hari Ini',
                subtitle: _cooldown > 0
                    ? 'Tunggu $_cooldown detik sebelum memanggil lagi'
                    : 'Panggil pelanggan ke TV display',
                icon: Icons.confirmation_number_outlined,
              ),
              SizedBox(height: sp(3)),
              if (b.queues.isEmpty)
                const EmptyState(
                  message: 'Belum ada antrian hari ini.',
                  icon: Icons.people_outline_rounded,
                )
              else
                for (final q in b.queues)
                  Padding(
                    padding: EdgeInsets.only(bottom: sp(3)),
                    child: _queueCard(q),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _queueCard(QueueModel q) {
    final p = context.palette;

    return AppCard(
      padding: EdgeInsets.all(sp(3.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Nomor antrian besar
              Container(
                height: sp(12),
                width: sp(12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.softOf(q.statusColor),
                  borderRadius: BorderRadius.circular(AppRadius.base),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: sp(1)),
                    child: Text(
                      q.queueNumber,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: p.solidOf(q.statusColor),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: sp(3.5)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      q.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: p.gray900,
                      ),
                    ),
                    SizedBox(height: sp(0.5)),
                    Text(
                      '${q.pax} orang · ${q.time ?? '-'}',
                      style: TextStyle(fontSize: 11.5, color: p.textMuted),
                    ),
                  ],
                ),
              ),
              SizedBox(width: sp(2)),
              StatusBadge(text: q.statusLabel, tone: q.statusColor, dense: true),
            ],
          ),
          if (!q.isSeated) ...[
            SizedBox(height: sp(3)),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _callButton(q),
                SizedBox(width: sp(2.5)),
                _seatButton(q),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Tombol panggil: berubah menjadi hitung mundur non-aktif selama cooldown.
  Widget _callButton(QueueModel q) {
    final p = context.palette;
    final locked = _busy.contains('call-${q.id}');

    if (_cooldown > 0) {
      return SizedBox(
        height: sp(9),
        child: OutlinedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.hourglass_top_rounded, size: 15),
          label: Text('${_cooldown}s'),
          style: OutlinedButton.styleFrom(
            minimumSize: Size(0, sp(9)),
            padding: EdgeInsets.symmetric(horizontal: sp(3)),
            textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            side: BorderSide(color: p.gray300),
          ),
        ),
      );
    }

    return IconButton(
      tooltip: 'Panggil ke TV',
      onPressed: locked ? null : () => _call(q),
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.campaign_rounded, size: 18),
      style: IconButton.styleFrom(
        backgroundColor: p.primaryLight,
        foregroundColor: p.primary,
        disabledBackgroundColor: p.gray200,
        disabledForegroundColor: p.gray500,
        shape: const CircleBorder(),
        minimumSize: Size(sp(9), sp(9)),
        padding: EdgeInsets.all(sp(2)),
      ),
    );
  }

  Widget _seatButton(QueueModel q) {
    final p = context.palette;
    final locked = _busy.contains('seat-${q.id}');

    return ElevatedButton.icon(
      onPressed: locked ? null : () => _seat(q),
      icon: const Icon(Icons.chair_alt_rounded, size: 15),
      label: const Text('Duduk'),
      style: ElevatedButton.styleFrom(
        backgroundColor: p.successLight,
        foregroundColor: p.success,
        disabledBackgroundColor: p.gray200,
        disabledForegroundColor: p.gray500,
        elevation: 0,
        minimumSize: Size(0, sp(9)),
        padding: EdgeInsets.symmetric(horizontal: sp(3.5)),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}
