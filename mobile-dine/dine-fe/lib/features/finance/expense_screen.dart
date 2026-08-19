import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import '../../models/ops.dart';
import 'finance_providers.dart';

/// Operasional harian: target & budget hari ini, daftar pengeluaran,
/// dan riwayat pencapaian target/budget per tanggal.
class ExpenseScreen extends ConsumerStatefulWidget {
  const ExpenseScreen({super.key});

  @override
  ConsumerState<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends ConsumerState<ExpenseScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _tab.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      ref.read(expenseListProvider.notifier).setSearch(value);
    });
  }

  void _refreshAll() {
    ref.invalidate(dailySettingProvider(todayKey()));
    ref.read(expenseListProvider.notifier).refresh();
    ref.read(budgetHistoryProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Scaffold(
      backgroundColor: p.appBg,
      appBar: AppBar(
        title: const Text('Operasional Harian'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Pengeluaran'),
            Tab(text: 'Riwayat Budget'),
          ],
        ),
      ),
      floatingActionButton: _tab.index == 0
          ? FloatingActionButton.extended(
              onPressed: _openExpenseForm,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Catat Pengeluaran'),
            )
          : null,
      body: TabBarView(
        controller: _tab,
        children: [
          _buildExpenseTab(),
          const _BudgetHistoryTab(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- tab 1

  Widget _buildExpenseTab() {
    final st = ref.watch(expenseListProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(dailySettingProvider(todayKey()));
        await ref.read(expenseListProvider.notifier).refresh();
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(sp(4), sp(4), sp(4), sp(24)),
        children: [
          _DailySettingCard(onEdit: _openDailySettingForm),
          SizedBox(height: sp(5)),
          const SectionHeader(
            title: 'Daftar Pengeluaran',
            subtitle: 'Semua biaya operasional yang tercatat',
            icon: Icons.receipt_long_outlined,
          ),
          SizedBox(height: sp(3)),
          SearchField(
            controller: _searchCtrl,
            hint: 'Cari pengeluaran...',
            onChanged: _onSearch,
          ),
          SizedBox(height: sp(3)),
          if (st.isLoading && st.items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          else if (st.error != null && st.items.isEmpty)
            ErrorView(
              message: st.error!,
              onRetry: () => ref.read(expenseListProvider.notifier).refresh(),
            )
          else if (st.items.isEmpty)
            const EmptyState(
              message: 'Belum ada pengeluaran tercatat.',
              icon: Icons.payments_outlined,
            )
          else ...[
            for (final e in st.items)
              Padding(
                padding: EdgeInsets.only(bottom: sp(3)),
                child: _ExpenseCard(
                  expense: e,
                  onTap: () => _openExpenseForm(initial: e),
                  onDelete: () => _deleteExpense(e),
                ),
              ),
            if (st.hasMore)
              Padding(
                padding: EdgeInsets.only(top: sp(1)),
                child: OutlinedButton.icon(
                  onPressed: st.isLoadingMore
                      ? null
                      : () => ref.read(expenseListProvider.notifier).loadMore(),
                  icon: st.isLoadingMore
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more_rounded, size: 18),
                  label: const Text('Muat lebih banyak'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ aksi

  Future<void> _openDailySettingForm() async {
    final msg = await _openSheet<String>(context, const _DailySettingForm());
    if (!mounted || msg == null) return;
    showSnack(context, msg);
    _refreshAll();
  }

  Future<void> _openExpenseForm({ExpenseModel? initial}) async {
    final msg = await _openSheet<String>(context, _ExpenseForm(initial: initial));
    if (!mounted || msg == null) return;
    showSnack(context, msg);
    _refreshAll();
  }

  Future<void> _deleteExpense(ExpenseModel e) async {
    final ok = await _confirm(
      context,
      title: 'Hapus Pengeluaran?',
      message:
          '${e.category} sebesar ${Fmt.rupiah(e.amount)} akan dihapus permanen.',
    );
    if (!ok) return;
    if (!mounted) return;

    try {
      final msg = await ref.read(financeRepoProvider).deleteExpense(e.id);
      if (!mounted) return;
      showSnack(context, msg);
      _refreshAll();
    } on ApiException catch (err) {
      if (!mounted) return;
      showSnack(context, err.message, error: true);
    }
  }
}

// ====================================================================
// KARTU PENGATURAN HARI INI
// ====================================================================

class _DailySettingCard extends ConsumerWidget {
  const _DailySettingCard({required this.onEdit});

  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = todayKey();
    final setting = ref.watch(dailySettingProvider(key));

    return AppCard(
      padding: EdgeInsets.all(sp(4.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Pengaturan Hari Ini',
            subtitle: Fmt.dateLong(DateTime.now()),
            icon: Icons.flag_outlined,
          ),
          SizedBox(height: sp(4)),
          AsyncView<DailySetting>(
            value: setting,
            onRetry: () => ref.invalidate(dailySettingProvider(key)),
            loading: const SizedBox(
              height: 110,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
            ),
            builder: (d) => IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: StatCard(
                      label: 'Target Penjualan',
                      value: Fmt.rupiah(d.target),
                      tone: 'success',
                      caption: 'Tercapai: ${Fmt.rupiah(d.income)}',
                      icon: Icons.trending_up_rounded,
                    ),
                  ),
                  SizedBox(width: sp(3)),
                  Expanded(
                    child: StatCard(
                      label: 'Budget Pengeluaran',
                      value: Fmt.rupiah(d.budget),
                      tone: 'primary',
                      caption: 'Terpakai: ${Fmt.rupiah(d.spent)}',
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: sp(4)),
          OutlinedButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('Atur Target & Budget'),
          ),
        ],
      ),
    );
  }
}

// ====================================================================
// KARTU SATU PENGELUARAN
// ====================================================================

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({
    required this.expense,
    required this.onTap,
    required this.onDelete,
  });

  final ExpenseModel expense;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.fromLTRB(sp(4), sp(3.5), sp(2), sp(3.5)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: p.gray900,
                  ),
                ),
                if (expense.notes != null && expense.notes!.isNotEmpty) ...[
                  SizedBox(height: sp(0.5)),
                  Text(
                    expense.notes!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: p.textMuted),
                  ),
                ],
                SizedBox(height: sp(1.5)),
                Text(
                  '${Fmt.date(expense.date)} · ${expense.userName ?? '-'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: p.gray500),
                ),
              ],
            ),
          ),
          SizedBox(width: sp(2)),
          Text(
            Fmt.rupiah(expense.amount),
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: p.danger,
            ),
          ),
          IconButton(
            onPressed: onDelete,
            tooltip: 'Hapus',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline_rounded, size: 20, color: p.gray500),
          ),
        ],
      ),
    );
  }
}

// ====================================================================
// TAB RIWAYAT BUDGET
// ====================================================================

class _BudgetHistoryTab extends ConsumerWidget {
  const _BudgetHistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final st = ref.watch(budgetHistoryProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(budgetHistoryProvider.notifier).refresh(),
      child: ListView(
        padding: EdgeInsets.fromLTRB(sp(4), sp(4), sp(4), sp(10)),
        children: [
          const SectionHeader(
            title: 'Riwayat Target & Budget',
            subtitle: 'Pencapaian penjualan vs batas pengeluaran',
            icon: Icons.history_rounded,
          ),
          SizedBox(height: sp(3)),
          if (st.isLoading && st.items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          else if (st.error != null && st.items.isEmpty)
            ErrorView(
              message: st.error!,
              onRetry: () => ref.read(budgetHistoryProvider.notifier).refresh(),
            )
          else if (st.items.isEmpty)
            const EmptyState(
              message: 'Belum ada riwayat target & budget.',
              icon: Icons.history_rounded,
            )
          else ...[
            for (final row in st.items)
              Padding(
                padding: EdgeInsets.only(bottom: sp(3)),
                child: AppCard(
                  padding: EdgeInsets.all(sp(4)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        Fmt.date(row.date),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: p.gray900,
                        ),
                      ),
                      Divider(height: sp(5), color: p.border),
                      _HistoryLine(
                        leftLabel: 'Target',
                        leftValue: Fmt.rupiah(row.target),
                        rightLabel: 'Pemasukan',
                        rightValue: Fmt.rupiah(row.income),
                        badge: '${row.targetPercentage}%',
                        badgeTone: row.targetPercentage >= 100 ? 'success' : 'warning',
                      ),
                      SizedBox(height: sp(3)),
                      _HistoryLine(
                        leftLabel: 'Budget',
                        leftValue: Fmt.rupiah(row.budget),
                        rightLabel: 'Terpakai',
                        rightValue: Fmt.rupiah(row.spent),
                        badge: '${row.budgetPercentage}%',
                        badgeTone: row.budgetPercentage >= 100 ? 'danger' : 'primary',
                      ),
                    ],
                  ),
                ),
              ),
            if (st.hasMore)
              OutlinedButton.icon(
                onPressed: st.isLoadingMore
                    ? null
                    : () => ref.read(budgetHistoryProvider.notifier).loadMore(),
                icon: st.isLoadingMore
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more_rounded, size: 18),
                label: const Text('Muat lebih banyak'),
              ),
          ],
        ],
      ),
    );
  }
}

class _HistoryLine extends StatelessWidget {
  const _HistoryLine({
    required this.leftLabel,
    required this.leftValue,
    required this.rightLabel,
    required this.rightValue,
    required this.badge,
    required this.badgeTone,
  });

  final String leftLabel;
  final String leftValue;
  final String rightLabel;
  final String rightValue;
  final String badge;
  final String badgeTone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                leftLabel,
                style: TextStyle(fontSize: 11.5, color: p.textMuted),
              ),
              Text(
                leftValue,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: p.gray800,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                rightLabel,
                style: TextStyle(fontSize: 11.5, color: p.textMuted),
              ),
              Text(
                rightValue,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: p.gray800,
                ),
              ),
            ],
          ),
        ),
        StatusBadge(text: badge, tone: badgeTone, dense: true),
      ],
    );
  }
}

// ====================================================================
// FORM TARGET & BUDGET HARIAN
// ====================================================================

class _DailySettingForm extends ConsumerStatefulWidget {
  const _DailySettingForm();

  @override
  ConsumerState<_DailySettingForm> createState() => _DailySettingFormState();
}

class _DailySettingFormState extends ConsumerState<_DailySettingForm> {
  final _targetCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();

  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Isi otomatis dengan nilai yang sudah tersimpan untuk tanggal ini.
    final cached = ref.read(dailySettingProvider(Fmt.apiDate(_date)));
    cached.whenData(_fill);
  }

  @override
  void dispose() {
    _targetCtrl.dispose();
    _budgetCtrl.dispose();
    super.dispose();
  }

  void _fill(DailySetting d) {
    _targetCtrl.text = d.target > 0 ? d.target.toStringAsFixed(0) : '';
    _budgetCtrl.text = d.budget > 0 ? d.budget.toStringAsFixed(0) : '';
  }

  Future<void> _pick() async {
    final picked = await _pickDate(context, _date);
    if (picked == null || !mounted) return;

    setState(() => _date = picked);

    // Muat nilai yang tersimpan untuk tanggal yang baru dipilih.
    try {
      final d = await ref.read(dailySettingProvider(Fmt.apiDate(picked)).future);
      if (!mounted) return;
      setState(() => _fill(d));
    } on ApiException {
      /* diabaikan — biarkan kasir mengisi manual */
    }
  }

  Future<void> _save() async {
    final target = _money(_targetCtrl.text);
    final budget = _money(_budgetCtrl.text);

    setState(() => _saving = true);

    try {
      final msg = await ref.read(financeRepoProvider).saveDailySetting(
            date: _date,
            target: target,
            budget: budget,
          );
      if (!mounted) return;
      Navigator.pop(context, msg.isEmpty ? 'Pengaturan Harian berhasil disimpan!' : msg);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetBody(
      title: 'Atur Target & Budget',
      subtitle: 'Berlaku untuk satu tanggal',
      saving: _saving,
      saveLabel: 'Simpan Pengaturan',
      onSave: _save,
      children: [
        _DateField(label: 'Tanggal', date: _date, onTap: _pick),
        SizedBox(height: sp(3)),
        TextField(
          controller: _targetCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Target Penjualan (Rp)',
            hintText: '0',
          ),
        ),
        SizedBox(height: sp(3)),
        TextField(
          controller: _budgetCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Batas Pengeluaran/Budget (Rp)',
            hintText: '0',
          ),
        ),
      ],
    );
  }
}

// ====================================================================
// FORM PENGELUARAN (tambah / ubah)
// ====================================================================

class _ExpenseForm extends ConsumerStatefulWidget {
  const _ExpenseForm({this.initial});

  final ExpenseModel? initial;

  @override
  ConsumerState<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends ConsumerState<_ExpenseForm> {
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _notesCtrl;

  late DateTime _date;
  bool _saving = false;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _categoryCtrl = TextEditingController(text: e?.category ?? '');
    _amountCtrl = TextEditingController(
      text: e == null ? '' : e.amount.toStringAsFixed(0),
    );
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _date = Fmt.parse(e?.date) ?? DateTime.now();
  }

  @override
  void dispose() {
    _categoryCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final category = _categoryCtrl.text.trim();
    final amount = _money(_amountCtrl.text);

    if (category.isEmpty) {
      showSnack(context, 'Kategori pengeluaran wajib diisi.', error: true);
      return;
    }
    if (amount <= 0) {
      showSnack(context, 'Nominal pengeluaran harus lebih dari 0.', error: true);
      return;
    }

    setState(() => _saving = true);
    final repo = ref.read(financeRepoProvider);
    final notes = _notesCtrl.text.trim();

    try {
      final msg = _isEdit
          ? await repo.updateExpense(
              id: widget.initial!.id,
              date: _date,
              category: category,
              amount: amount,
              notes: notes,
            )
          : await repo.createExpense(
              date: _date,
              category: category,
              amount: amount,
              notes: notes,
            );
      if (!mounted) return;
      Navigator.pop(context, msg);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(
        context,
        e.errorFor('amount') ?? e.errorFor('category') ?? e.message,
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetBody(
      title: _isEdit ? 'Ubah Pengeluaran' : 'Catat Pengeluaran',
      subtitle: 'Biaya operasional di luar bahan baku juga dicatat di sini',
      saving: _saving,
      saveLabel: _isEdit ? 'Simpan Perubahan' : 'Simpan Pengeluaran',
      onSave: _save,
      children: [
        _DateField(
          label: 'Tanggal',
          date: _date,
          onTap: () async {
            final picked = await _pickDate(context, _date);
            if (picked == null || !mounted) return;
            setState(() => _date = picked);
          },
        ),
        SizedBox(height: sp(3)),
        TextField(
          controller: _categoryCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Kategori Pengeluaran',
            hintText: 'Contoh: Bahan Baku, Listrik, Gaji',
          ),
        ),
        SizedBox(height: sp(3)),
        TextField(
          controller: _amountCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Nominal (Rp)',
            hintText: '0',
          ),
        ),
        SizedBox(height: sp(3)),
        TextField(
          controller: _notesCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Keterangan',
            hintText: 'Opsional — rincian singkat pengeluaran',
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}

// ====================================================================
// KOMPONEN & UTILITAS BERSAMA (khusus layar ini)
// ====================================================================

/// Kerangka isi bottom sheet form: judul, isi yang bisa digulir, tombol simpan.
class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.title,
    required this.children,
    required this.onSave,
    required this.saving,
    required this.saveLabel,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final VoidCallback onSave;
  final bool saving;
  final String saveLabel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(sp(4), sp(4), sp(4), sp(4)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: title, subtitle: subtitle),
            SizedBox(height: sp(4)),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
            SizedBox(height: sp(4)),
            ElevatedButton(
              onPressed: saving ? null : onSave,
              child: saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(saveLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// Field tanggal yang membuka date picker.
class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.date, required this.onTap});

  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.base),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          children: [
            Icon(Icons.event_rounded, size: 18, color: p.gray600),
            SizedBox(width: sp(2)),
            Text(
              Fmt.date(date),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: p.gray800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<T?> _openSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: child,
      ),
    );

Future<DateTime?> _pickDate(BuildContext context, DateTime initial) =>
    showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
      helpText: 'Pilih Tanggal',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Ya, Hapus',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppPalette.light$.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  return ok == true;
}

/// Ambil angka rupiah dari teks bebas ("50.000" / "Rp 50.000" → 50000).
double _money(String raw) =>
    double.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
