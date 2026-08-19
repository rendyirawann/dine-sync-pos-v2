import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../models/session_user.dart';
import '../auth/auth_controller.dart';
import '../dashboard/dashboard_screen.dart';
import '../kasir/table_map_screen.dart';
import '../kitchen/kitchen_screen.dart';
import '../queue/queue_screen.dart';
import 'more_screen.dart';

/// Kerangka utama aplikasi: bottom navigation yang menyesuaikan hak akses user.
/// Kasir tidak melihat tab yang tidak boleh diaksesnya (meniru `@can` di web).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 2.5)));
    }

    final tabs = _tabsFor(user);
    final safeIndex = _index.clamp(0, tabs.length - 1);

    return Scaffold(
      body: IndexedStack(
        index: safeIndex,
        children: tabs.map((t) => t.child).toList(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: tabs
            .map((t) => NavigationDestination(
                  icon: Icon(t.icon),
                  selectedIcon: Icon(t.activeIcon),
                  label: t.label,
                ))
            .toList(),
      ),
    );
  }

  List<_Tab> _tabsFor(SessionUser u) {
    final tabs = <_Tab>[
      const _Tab(
        label: 'Beranda',
        icon: Icons.space_dashboard_outlined,
        activeIcon: Icons.space_dashboard_rounded,
        child: DashboardScreen(embedded: true),
      ),
    ];

    if (u.can('view_kasir')) {
      tabs.add(const _Tab(
        label: 'Kasir',
        icon: Icons.point_of_sale_outlined,
        activeIcon: Icons.point_of_sale_rounded,
        child: TableMapScreen(embedded: true),
      ));
    }

    if (u.can('view_kitchen')) {
      tabs.add(const _Tab(
        label: 'Dapur',
        icon: Icons.local_fire_department_outlined,
        activeIcon: Icons.local_fire_department_rounded,
        child: KitchenScreen(embedded: true),
      ));
    }

    if (u.can('view_queue')) {
      tabs.add(const _Tab(
        label: 'Antrian',
        icon: Icons.people_outline_rounded,
        activeIcon: Icons.people_rounded,
        child: QueueScreen(embedded: true),
      ));
    }

    tabs.add(const _Tab(
      label: 'Lainnya',
      icon: Icons.grid_view_outlined,
      activeIcon: Icons.grid_view_rounded,
      child: MoreScreen(),
    ));

    return tabs;
  }
}

class _Tab {
  const _Tab({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.child,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget child;
}

/// AppBar seragam untuk tab: menampilkan judul + badge tenant (seperti navbar web).
class TenantAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const TenantAppBar({super.key, required this.title, this.actions});

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final user = ref.watch(currentUserProvider);

    return AppBar(
      titleSpacing: sp(4),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.gray900),
          ),
          if (user != null)
            Row(
              children: [
                Icon(Icons.storefront_rounded, size: 11, color: p.primary),
                SizedBox(width: sp(1)),
                Flexible(
                  child: Text(
                    '${user.tenantLabel} · ${user.roleLabel}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: p.textMuted,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      actions: [
        ...?actions,
        IconButton(
          tooltip: 'Profil',
          onPressed: () => context.pushNamed('profile'),
          icon: _Avatar(user: user),
        ),
        SizedBox(width: sp(2)),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.user});

  final SessionUser? user;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final url = user?.avatarUrl;

    if (url != null && url.isNotEmpty) {
      return CircleAvatar(radius: 15, backgroundImage: NetworkImage(url));
    }

    return Container(
      height: 30,
      width: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: p.primaryLight, shape: BoxShape.circle),
      child: Text(
        user?.initials ?? '?',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.primary),
      ),
    );
  }
}
