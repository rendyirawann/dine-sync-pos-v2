import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import '../../models/session_user.dart';
import '../auth/auth_controller.dart';
import '../finance/finance_providers.dart';

// ====================================================================
// MODEL & PROVIDER LOKAL PROFIL
// ====================================================================

/// Satu baris log aktivitas akun.
class ActivityRow {
  const ActivityRow({
    required this.id,
    required this.description,
    this.logName,
    this.ip,
    this.device,
    this.os,
    this.createdAt,
  });

  final int id;
  final String description;
  final String? logName;
  final String? ip;
  final String? device;
  final String? os;
  final String? createdAt;

  factory ActivityRow.fromJson(Map<String, dynamic> j) => ActivityRow(
        id: J.toInt(j['id']),
        description: J.toStr(j['description']) ?? 'Aktivitas',
        logName: J.toStr(j['log_name']),
        ip: J.toStr(j['ip']),
        device: J.toStr(j['device']),
        os: J.toStr(j['os']),
        createdAt: J.toStr(j['created_at']),
      );
}

/// Data profil lengkap dari server (lebih detail dari cache sesi).
final profileProvider = FutureProvider<SessionUser>((ref) async {
  final res = await ref.watch(apiClientProvider).get('/profile');
  return SessionUser.fromJson(res.asMap);
});

/// Riwayat aktivitas akun (berpaginasi).
class ProfileActivityNotifier extends PagedNotifier<ActivityRow> {
  ProfileActivityNotifier(super.api);

  @override
  String get path => '/profile/activities';

  @override
  int get perPage => 10;

  @override
  ActivityRow parse(Map<String, dynamic> json) => ActivityRow.fromJson(json);
}

final profileActivityProvider =
    StateNotifierProvider<ProfileActivityNotifier, PagedState<ActivityRow>>(
  (ref) => ProfileActivityNotifier(ref.watch(apiClientProvider)),
);

// ====================================================================
// LAYAR PROFIL
// ====================================================================

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _loggingOutAll = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final profile = ref.watch(profileProvider);
    final cached = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: p.appBg,
      appBar: AppBar(title: const Text('Profil Saya')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(profileProvider);
          await ref.read(profileActivityProvider.notifier).refresh();
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(sp(4), sp(4), sp(4), sp(10)),
          children: [
            AsyncView<SessionUser>(
              value: profile,
              onRetry: () => ref.invalidate(profileProvider),
              loading: cached == null
                  ? null
                  : _AccountBlock(user: cached, onEdit: _openEditForm),
              builder: (user) => _AccountBlock(user: user, onEdit: _openEditForm),
            ),
            SizedBox(height: sp(6)),

            // --- Keamanan ---
            const SectionHeader(
              title: 'Keamanan',
              subtitle: 'Kata sandi & perangkat yang login',
              icon: Icons.shield_outlined,
            ),
            SizedBox(height: sp(3)),
            AppCard(
              padding: EdgeInsets.all(sp(4)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: _openPasswordForm,
                    icon: const Icon(Icons.lock_reset_rounded, size: 18),
                    label: const Text('Ganti Password'),
                  ),
                  SizedBox(height: sp(3)),
                  OutlinedButton.icon(
                    onPressed: _loggingOutAll ? null : _logoutAll,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.danger,
                      side: BorderSide(color: p.danger),
                    ),
                    icon: _loggingOutAll
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.devices_other_rounded, size: 18),
                    label: const Text('Keluar dari Semua Perangkat'),
                  ),
                ],
              ),
            ),
            SizedBox(height: sp(6)),

            // --- Aktivitas ---
            const SectionHeader(
              title: 'Aktivitas Terakhir',
              subtitle: 'Jejak login & perubahan data akun',
              icon: Icons.history_rounded,
            ),
            SizedBox(height: sp(3)),
            const _ActivityList(),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ aksi

  Future<void> _openEditForm() async {
    final user = ref.read(profileProvider).value ?? ref.read(currentUserProvider);
    if (user == null) {
      showSnack(context, 'Data profil belum siap. Coba lagi.', error: true);
      return;
    }

    final msg = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _EditProfileForm(user: user),
      ),
    );

    if (!mounted || msg == null) return;

    await ref.read(authControllerProvider.notifier).refreshUser();
    ref.invalidate(profileProvider);
    ref.read(profileActivityProvider.notifier).refresh();
    if (!mounted) return;
    showSnack(context, msg);
  }

  Future<void> _openPasswordForm() async {
    final msg = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: const _ChangePasswordForm(),
      ),
    );

    if (!mounted || msg == null) return;
    showSnack(context, msg);
    ref.read(profileActivityProvider.notifier).refresh();
  }

  Future<void> _logoutAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keluar dari Semua Perangkat?'),
        content: const Text(
          'Semua sesi login (termasuk di perangkat lain) akan diakhiri.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppPalette.light$.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Keluarkan'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    if (!mounted) return;

    setState(() => _loggingOutAll = true);

    try {
      final res = await ref.read(apiClientProvider).post('/auth/logout-all');
      if (!mounted) return;
      setState(() => _loggingOutAll = false);
      showSnack(context, res.message);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loggingOutAll = false);
      showSnack(context, e.message, error: true);
    }
  }
}

// ====================================================================
// HEADER + DATA AKUN
// ====================================================================

class _AccountBlock extends StatelessWidget {
  const _AccountBlock({required this.user, required this.onEdit});

  final SessionUser user;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hasAvatar = user.avatarUrl != null && user.avatarUrl!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: EdgeInsets.all(sp(4.5)),
          child: Column(
            children: [
              Container(
                height: sp(20),
                width: sp(20),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.primaryLight,
                  shape: BoxShape.circle,
                  image: hasAvatar
                      ? DecorationImage(
                          image: NetworkImage(user.avatarUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: hasAvatar
                    ? null
                    : Text(
                        user.initials,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: p.primary,
                        ),
                      ),
              ),
              SizedBox(height: sp(3)),
              Text(
                user.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: p.gray900,
                ),
              ),
              SizedBox(height: sp(1)),
              Text(
                user.email,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: p.textMuted),
              ),
              SizedBox(height: sp(3)),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: sp(2),
                runSpacing: sp(1.5),
                children: [
                  StatusBadge(text: user.roleLabel, tone: 'success'),
                  StatusBadge(
                    text: user.tenantLabel,
                    tone: 'primary',
                    icon: Icons.storefront_rounded,
                  ),
                ],
              ),
              SizedBox(height: sp(3)),
              Text(
                'Ubah foto profil lewat aplikasi web.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: p.textMuted),
              ),
            ],
          ),
        ),
        SizedBox(height: sp(6)),
        const SectionHeader(
          title: 'Data Akun',
          subtitle: 'Informasi identitas & login',
          icon: Icons.badge_outlined,
        ),
        SizedBox(height: sp(3)),
        AppCard(
          padding: EdgeInsets.all(sp(4)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SummaryRow(label: 'Username', value: user.username ?? '-'),
              SummaryRow(label: 'No. WhatsApp', value: user.noWa ?? '-'),
              SummaryRow(
                label: 'Login Terakhir',
                value: user.lastLogin == null ? '-' : Fmt.dateTime(user.lastLogin),
              ),
              SizedBox(height: sp(3)),
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit Profil'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ====================================================================
// DAFTAR AKTIVITAS
// ====================================================================

class _ActivityList extends ConsumerWidget {
  const _ActivityList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final st = ref.watch(profileActivityProvider);

    if (st.isLoading && st.items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }

    if (st.error != null && st.items.isEmpty) {
      return ErrorView(
        message: st.error!,
        onRetry: () => ref.read(profileActivityProvider.notifier).refresh(),
      );
    }

    if (st.items.isEmpty) {
      return const EmptyState(
        message: 'Belum ada aktivitas tercatat.',
        icon: Icons.history_toggle_off_rounded,
        compact: true,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: EdgeInsets.symmetric(horizontal: sp(4), vertical: sp(3)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < st.items.length; i++) ...[
                if (i > 0) Divider(height: sp(5), color: p.border),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      st.items[i].description,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: p.gray800,
                      ),
                    ),
                    SizedBox(height: sp(1)),
                    Text(
                      '${Fmt.dateTime(st.items[i].createdAt)} · '
                      '${st.items[i].device ?? '-'} · ${st.items[i].ip ?? '-'}',
                      style: TextStyle(fontSize: 11, color: p.textMuted),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (st.hasMore) ...[
          SizedBox(height: sp(3)),
          OutlinedButton.icon(
            onPressed: st.isLoadingMore
                ? null
                : () => ref.read(profileActivityProvider.notifier).loadMore(),
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
    );
  }
}

// ====================================================================
// FORM EDIT PROFIL
// ====================================================================

class _EditProfileForm extends ConsumerStatefulWidget {
  const _EditProfileForm({required this.user});

  final SessionUser user;

  @override
  ConsumerState<_EditProfileForm> createState() => _EditProfileFormState();
}

class _EditProfileFormState extends ConsumerState<_EditProfileForm> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _waCtrl;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.user.name);
    _emailCtrl = TextEditingController(text: widget.user.email);
    _waCtrl = TextEditingController(text: widget.user.noWa ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _waCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final wa = _waCtrl.text.trim();

    if (name.isEmpty) {
      showSnack(context, 'Nama lengkap wajib diisi.', error: true);
      return;
    }
    if (email.isEmpty) {
      showSnack(context, 'Email wajib diisi.', error: true);
      return;
    }

    setState(() => _saving = true);

    try {
      final res = await ref.read(apiClientProvider).put('/profile', data: {
        'name': name,
        'email': email,
        'no_wa': wa,
        'phone': wa,
      });
      if (!mounted) return;
      Navigator.pop(context, res.message);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(
        context,
        e.errorFor('email') ?? e.errorFor('name') ?? e.message,
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetBody(
      title: 'Edit Profil',
      subtitle: 'Perubahan langsung berlaku di semua perangkat',
      saving: _saving,
      saveLabel: 'Simpan Perubahan',
      onSave: _save,
      children: [
        TextField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nama Lengkap'),
        ),
        SizedBox(height: sp(3)),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        SizedBox(height: sp(3)),
        TextField(
          controller: _waCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'No. WhatsApp',
            hintText: 'Contoh: 081234567890',
          ),
        ),
      ],
    );
  }
}

// ====================================================================
// FORM GANTI PASSWORD
// ====================================================================

class _ChangePasswordForm extends ConsumerStatefulWidget {
  const _ChangePasswordForm();

  @override
  ConsumerState<_ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends ConsumerState<_ChangePasswordForm> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _logoutOthers = false;
  bool _saving = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final current = _currentCtrl.text;
    final next = _newCtrl.text;
    final confirm = _confirmCtrl.text;

    if (current.isEmpty) {
      showSnack(context, 'Password saat ini wajib diisi.', error: true);
      return;
    }
    if (next.length < 8) {
      showSnack(context, 'Password baru minimal 8 karakter.', error: true);
      return;
    }
    if (next != confirm) {
      showSnack(context, 'Konfirmasi password baru tidak sama.', error: true);
      return;
    }

    setState(() => _saving = true);

    try {
      final res = await ref.read(apiClientProvider).post(
        '/auth/change-password',
        data: {
          'current_password': current,
          'password': next,
          'password_confirmation': confirm,
          'logout_other_devices': _logoutOthers,
        },
      );
      if (!mounted) return;
      Navigator.pop(context, res.message);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(
        context,
        e.errorFor('current_password') ?? e.errorFor('password') ?? e.message,
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return _SheetBody(
      title: 'Ganti Password',
      subtitle: 'Gunakan kombinasi yang sulit ditebak',
      saving: _saving,
      saveLabel: 'Simpan Password Baru',
      onSave: _save,
      children: [
        TextField(
          controller: _currentCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password Saat Ini'),
        ),
        SizedBox(height: sp(3)),
        TextField(
          controller: _newCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password Baru',
            helperText: 'Minimal 8 karakter.',
          ),
        ),
        SizedBox(height: sp(3)),
        TextField(
          controller: _confirmCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Konfirmasi Password Baru'),
        ),
        SizedBox(height: sp(2)),
        SwitchListTile(
          value: _logoutOthers,
          onChanged: (v) => setState(() => _logoutOthers = v),
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Keluarkan dari perangkat lain',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: p.gray800,
            ),
          ),
          subtitle: Text(
            'Sesi di perangkat lain akan diakhiri.',
            style: TextStyle(fontSize: 11.5, color: p.textMuted),
          ),
        ),
      ],
    );
  }
}

// ====================================================================
// KERANGKA BOTTOM SHEET FORM (khusus layar ini)
// ====================================================================

class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.title,
    required this.onSave,
    required this.saving,
    required this.saveLabel,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onSave;
  final bool saving;
  final String saveLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(sp(4)),
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
