import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/ui.dart';
import '../../models/master.dart';
import '../auth/auth_controller.dart';

/// Pengaturan toko (nama, alamat, telepon, pajak PB1).
final storeSettingProvider = FutureProvider<SettingModel>((ref) async {
  final res = await ref.watch(apiClientProvider).get('/settings');
  return SettingModel.fromJson(res.asMap);
});

class SettingScreen extends ConsumerStatefulWidget {
  const SettingScreen({super.key});

  @override
  ConsumerState<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends ConsumerState<SettingScreen> {
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Bila data sudah ada di cache provider, langsung isi form.
    ref.read(storeSettingProvider).whenData(_fill);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _taxCtrl.dispose();
    super.dispose();
  }

  void _fill(SettingModel s) {
    _nameCtrl.text = s.storeName;
    _addressCtrl.text = s.address ?? '';
    _phoneCtrl.text = s.phone ?? '';
    _taxCtrl.text = '${s.taxRate}';
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final tax = int.tryParse(_taxCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    if (name.isEmpty) {
      showSnack(context, 'Nama toko wajib diisi.', error: true);
      return;
    }
    if (tax < 0 || tax > 100) {
      showSnack(context, 'Pajak harus berada di antara 0 sampai 100.', error: true);
      return;
    }

    setState(() => _saving = true);

    try {
      await ref.read(apiClientProvider).put('/settings', data: {
        'store_name': name,
        'address': _addressCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'tax_rate': tax,
      });
      if (!mounted) return;
      setState(() => _saving = false);
      ref.invalidate(storeSettingProvider);
      showSnack(context, 'Pengaturan toko dan pajak berhasil diperbarui!');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, e.errorFor('tax_rate') ?? e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.can('view_data_master') ?? false;
    final setting = ref.watch(storeSettingProvider);

    // Isi ulang form tiap data baru datang dari server.
    ref.listen<AsyncValue<SettingModel>>(storeSettingProvider, (previous, next) {
      next.whenData(_fill);
    });

    return Scaffold(
      backgroundColor: p.appBg,
      appBar: AppBar(title: const Text('Pengaturan Toko')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(storeSettingProvider);
          try {
            await ref.read(storeSettingProvider.future);
          } on ApiException {
            /* pesan error sudah ditampilkan oleh ErrorView */
          }
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(sp(4), sp(4), sp(4), sp(10)),
          children: [
            if (!canEdit) ...[
              AppCard(
                color: p.infoLight,
                borderColor: Colors.transparent,
                padding: EdgeInsets.all(sp(4)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: p.info),
                    SizedBox(width: sp(2.5)),
                    Expanded(
                      child: Text(
                        'Hanya admin yang dapat mengubah pengaturan toko.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                          color: p.gray800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: sp(4)),
            ],
            AsyncView<SettingModel>(
              value: setting,
              onRetry: () => ref.invalidate(storeSettingProvider),
              loading: const AppCard(
                child: SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
                ),
              ),
              builder: (_) => AppCard(
                padding: EdgeInsets.all(sp(4)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionHeader(
                      title: 'Identitas Toko',
                      subtitle: 'Dipakai pada nota & tampilan pelanggan',
                      icon: Icons.storefront_outlined,
                    ),
                    SizedBox(height: sp(4)),
                    TextField(
                      controller: _nameCtrl,
                      enabled: canEdit,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Nama Toko'),
                    ),
                    SizedBox(height: sp(3)),
                    TextField(
                      controller: _addressCtrl,
                      enabled: canEdit,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Alamat Toko',
                        alignLabelWithHint: true,
                      ),
                    ),
                    SizedBox(height: sp(3)),
                    TextField(
                      controller: _phoneCtrl,
                      enabled: canEdit,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'No. Telepon / WA',
                        hintText: 'Contoh: 081234567890',
                      ),
                    ),
                    SizedBox(height: sp(3)),
                    TextField(
                      controller: _taxCtrl,
                      enabled: canEdit,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Pajak Restoran (PB1)',
                        suffixText: '%',
                        helperText:
                            'Masukkan 0 jika tidak membebankan pajak ke pelanggan.',
                        helperMaxLines: 2,
                      ),
                    ),
                    if (canEdit) ...[
                      SizedBox(height: sp(5)),
                      ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_rounded, size: 18),
                        label: const Text('Simpan Pengaturan'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SizedBox(height: sp(6)),
            const SectionHeader(
              title: 'Tampilan Aplikasi',
              subtitle: 'Tema mengikuti preferensi Anda di perangkat ini',
              icon: Icons.brightness_6_outlined,
            ),
            SizedBox(height: sp(3)),
            const _ThemePicker(),
          ],
        ),
      ),
    );
  }
}

/// Pemilih tema: Ikuti Sistem / Terang / Gelap.
class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);

    return AppCard(
      padding: EdgeInsets.symmetric(vertical: sp(1)),
      child: RadioGroup<ThemeMode>(
        groupValue: mode,
        onChanged: (v) {
          if (v != null) ref.read(themeModeProvider.notifier).set(v);
        },
        child: const Column(
          children: [
            RadioListTile<ThemeMode>(
              value: ThemeMode.system,
              title: Text('Ikuti Sistem'),
              dense: true,
            ),
            RadioListTile<ThemeMode>(
              value: ThemeMode.light,
              title: Text('Terang'),
              dense: true,
            ),
            RadioListTile<ThemeMode>(
              value: ThemeMode.dark,
              title: Text('Gelap'),
              dense: true,
            ),
          ],
        ),
      ),
    );
  }
}
