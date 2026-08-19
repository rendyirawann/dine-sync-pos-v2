import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/ui.dart';
import '../../models/session_user.dart';
import '../auth/auth_controller.dart';
import 'home_shell.dart';

/// Padanan grid "Menu Utama" di sidebar web + akses modul lain,
/// semuanya disaring sesuai hak akses user.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();

    final operasional = <_Item>[
      if (user.can('view_kasir'))
        _Item('Kasir', Icons.point_of_sale_rounded, 'primary', '/kasir'),
      if (user.can('view_kasir'))
        _Item('Shift', Icons.access_time_rounded, 'warning', '/shift'),
      if (user.can('view_kitchen'))
        _Item('Dapur', Icons.local_fire_department_rounded, 'danger', '/kitchen'),
      if (user.can('view_queue'))
        _Item('Antrian', Icons.people_rounded, 'success', '/queue'),
    ];

    final master = <_Item>[
      if (user.can('view_data_master')) ...[
        _Item('Menu', Icons.restaurant_menu_rounded, 'primary', '/master/menus'),
        _Item('Kategori', Icons.category_rounded, 'info', '/master/categories'),
        _Item('Meja', Icons.table_restaurant_rounded, 'warning', '/master/tables'),
        _Item('Promo', Icons.local_offer_rounded, 'danger', '/master/promos'),
        _Item('Bahan', Icons.inventory_2_rounded, 'primary', '/master/ingredients'),
        _Item('Supplier', Icons.local_shipping_rounded, 'info', '/master/suppliers'),
      ],
    ];

    final keuangan = <_Item>[
      if (user.can('view_finance')) ...[
        _Item('Pengeluaran', Icons.payments_rounded, 'danger', '/finance/expenses'),
        _Item('Stok In', Icons.local_shipping_rounded, 'success', '/finance/stock'),
        _Item('Opname', Icons.fact_check_rounded, 'warning', '/finance/opname'),
      ],
      if (user.can('view_report'))
        _Item('Laporan', Icons.bar_chart_rounded, 'primary', '/reports'),
    ];

    return Scaffold(
      backgroundColor: p.appBg,
      appBar: const TenantAppBar(title: 'Menu Aplikasi'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(sp(4), sp(4), sp(4), sp(10)),
        children: [
          _ProfileCard(user: user),
          if (operasional.isNotEmpty) ...[
            SizedBox(height: sp(6)),
            const SectionHeader(title: 'Operasional', icon: Icons.dashboard_customize_outlined),
            SizedBox(height: sp(3)),
            _Grid(items: operasional),
          ],
          if (master.isNotEmpty) ...[
            SizedBox(height: sp(6)),
            const SectionHeader(title: 'Data Master', icon: Icons.storage_outlined),
            SizedBox(height: sp(3)),
            _Grid(items: master),
          ],
          if (keuangan.isNotEmpty) ...[
            SizedBox(height: sp(6)),
            const SectionHeader(title: 'Keuangan & Laporan', icon: Icons.account_balance_wallet_outlined),
            SizedBox(height: sp(3)),
            _Grid(items: keuangan),
          ],
          SizedBox(height: sp(6)),
          const SectionHeader(title: 'Akun & Aplikasi', icon: Icons.settings_outlined),
          SizedBox(height: sp(3)),
          AppCard(
            padding: EdgeInsets.symmetric(vertical: sp(1)),
            child: Column(
              children: [
                _Row(
                  icon: Icons.person_outline_rounded,
                  label: 'Profil Saya',
                  onTap: () => context.pushNamed('profile'),
                ),
                _Divider(),
                _Row(
                  icon: Icons.storefront_outlined,
                  label: 'Pengaturan Toko & Pajak',
                  onTap: () => context.pushNamed('settings'),
                ),
                _Divider(),
                _ThemeRow(),
                _Divider(),
                _Row(
                  icon: Icons.logout_rounded,
                  label: 'Keluar',
                  tone: 'danger',
                  onTap: () => _confirmLogout(context, ref),
                ),
              ],
            ),
          ),
          SizedBox(height: sp(4)),
          Center(
            child: Text(
              'DineSync POS Mobile · v1.0.0',
              style: TextStyle(fontSize: 11, color: p.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keluar dari Akun?'),
        content: const Text('Sesi Anda akan diakhiri. Sampai jumpa lagi! 👋'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppPalette.light$.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Keluar'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.user});

  final SessionUser user;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return AppCard(
      padding: EdgeInsets.all(sp(4)),
      child: Row(
        children: [
          Container(
            height: sp(13),
            width: sp(13),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.primaryLight,
              shape: BoxShape.circle,
              image: (user.avatarUrl != null && user.avatarUrl!.isNotEmpty)
                  ? DecorationImage(image: NetworkImage(user.avatarUrl!), fit: BoxFit.cover)
                  : null,
            ),
            child: (user.avatarUrl == null || user.avatarUrl!.isEmpty)
                ? Text(
                    user.initials,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: p.primary,
                    ),
                  )
                : null,
          ),
          SizedBox(width: sp(4)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: p.gray900),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: sp(1)),
                Text(
                  user.email,
                  style: TextStyle(fontSize: 12, color: p.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: sp(2)),
                Wrap(
                  spacing: sp(1.5),
                  runSpacing: sp(1.5),
                  children: [
                    StatusBadge(text: user.roleLabel, tone: 'success', dense: true),
                    StatusBadge(
                      text: user.tenantLabel,
                      tone: 'primary',
                      dense: true,
                      icon: Icons.storefront_rounded,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.items});

  final List<_Item> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // Responsif: 4 kolom di HP, lebih banyak di layar lebar/tablet.
        final cols = c.maxWidth > 620 ? 6 : (c.maxWidth > 420 ? 4 : 3);

        return GridView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: sp(3),
            crossAxisSpacing: sp(3),
            childAspectRatio: .95,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => _Tile(item: items[i]),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.item});

  final _Item item;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return AppCard(
      onTap: () => context.push(item.route),
      padding: EdgeInsets.all(sp(2)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(sp(2.5)),
            decoration: BoxDecoration(
              color: p.softOf(item.tone),
              borderRadius: BorderRadius.circular(AppRadius.base),
            ),
            child: Icon(item.icon, size: 22, color: p.solidOf(item.tone)),
          ),
          SizedBox(height: sp(2)),
          Text(
            item.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.gray800),
          ),
        ],
      ),
    );
  }
}

class _Item {
  const _Item(this.label, this.icon, this.tone, this.route);

  final String label;
  final IconData icon;
  final String tone;
  final String route;
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.onTap, this.tone});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = tone == null ? p.gray700 : p.solidOf(tone!);

    return ListTile(
      onTap: onTap,
      leading: Icon(icon, size: 20, color: color),
      title: Text(
        label,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
      ),
      trailing: Icon(Icons.chevron_right_rounded, size: 20, color: p.gray400),
      dense: true,
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, indent: sp(4), endIndent: sp(4), color: context.palette.border);
}

/// Pemilih tema: System / Light / Dark — sama seperti dropdown di sidebar web.
class _ThemeRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final mode = ref.watch(themeModeProvider);

    String label = switch (mode) {
      ThemeMode.light => 'Terang',
      ThemeMode.dark => 'Gelap',
      ThemeMode.system => 'Ikuti Sistem',
    };

    return ListTile(
      dense: true,
      leading: Icon(Icons.brightness_6_outlined, size: 20, color: p.gray700),
      title: Text(
        'Tema Tampilan',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.gray700),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12.5, color: p.textMuted)),
          Icon(Icons.chevron_right_rounded, size: 20, color: p.gray400),
        ],
      ),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: sp(3)),
              const SectionHeader(title: 'Tema Tampilan'),
              SizedBox(height: sp(2)),
              // RadioGroup: API baru Flutter (groupValue/onChanged per-tile sudah deprecated).
              RadioGroup<ThemeMode>(
                groupValue: mode,
                onChanged: (v) {
                  if (v != null) ref.read(themeModeProvider.notifier).set(v);
                  Navigator.pop(ctx);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final m in ThemeMode.values)
                      RadioListTile<ThemeMode>(
                        value: m,
                        title: Text(switch (m) {
                          ThemeMode.light => 'Terang',
                          ThemeMode.dark => 'Gelap',
                          ThemeMode.system => 'Ikuti Sistem',
                        }),
                      ),
                  ],
                ),
              ),
              SizedBox(height: sp(3)),
            ],
          ),
        ),
      ),
    );
  }
}
