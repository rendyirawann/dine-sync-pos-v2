import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_controller.dart';
import '../../features/auth/login_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/finance/expense_screen.dart';
import '../../features/finance/stock_screen.dart';
import '../../features/finance/stock_opname_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/kasir/order_builder_screen.dart';
import '../../features/kasir/receipt_screen.dart';
import '../../features/kasir/table_map_screen.dart';
import '../../features/kitchen/kitchen_screen.dart';
import '../../features/master/category_screen.dart';
import '../../features/master/ingredient_screen.dart';
import '../../features/master/menu_screen.dart';
import '../../features/master/promo_screen.dart';
import '../../features/master/supplier_screen.dart';
import '../../features/master/table_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/queue/queue_screen.dart';
import '../../features/report/report_screen.dart';
import '../../features/settings/setting_screen.dart';
import '../../features/shift/shift_screen.dart';

/// Nama route dipakai lewat `context.goNamed(...)` agar tidak salah tulis path.
class Routes {
  static const login = 'login';
  static const home = 'home';
  static const kasirTables = 'kasir-tables';
  static const kasirOrder = 'kasir-order';
  static const kasirReceipt = 'kasir-receipt';
  static const kitchen = 'kitchen';
  static const queue = 'queue';
  static const shift = 'shift';
  static const menus = 'menus';
  static const categories = 'categories';
  static const tables = 'tables';
  static const promos = 'promos';
  static const ingredients = 'ingredients';
  static const suppliers = 'suppliers';
  static const expenses = 'expenses';
  static const stockIn = 'stock-in';
  static const stockOpname = 'stock-opname';
  static const reports = 'reports';
  static const profile = 'profile';
  static const settings = 'settings';
  static const dashboard = 'dashboard';
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ValueNotifier<AuthStatus>(AuthStatus.unknown);

  ref.listen<AuthState>(
    authControllerProvider,
    (_, next) => notifier.value = next.status,
    fireImmediately: true,
  );

  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: (context, state) {
      final status = notifier.value;
      final goingToLogin = state.matchedLocation == '/login';

      // Masih memulihkan sesi → tahan di splash.
      if (status == AuthStatus.unknown) {
        return state.matchedLocation == '/splash' ? null : '/splash';
      }

      if (status == AuthStatus.unauthenticated) {
        return goingToLogin ? null : '/login';
      }

      // Sudah login tapi masih di login/splash → masuk ke aplikasi.
      if (goingToLogin || state.matchedLocation == '/splash') return '/';

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const _SplashScreen()),
      GoRoute(path: '/login', name: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/', name: Routes.home, builder: (_, _) => const HomeShell()),

      GoRoute(path: '/dashboard', name: Routes.dashboard, builder: (_, _) => const DashboardScreen()),

      // Kasir
      GoRoute(path: '/kasir', name: Routes.kasirTables, builder: (_, _) => const TableMapScreen()),
      GoRoute(
        path: '/kasir/order/:tableId',
        name: Routes.kasirOrder,
        builder: (context, state) => OrderBuilderScreen(
          tableId: int.tryParse(state.pathParameters['tableId'] ?? '') ?? 0,
          customerName: state.uri.queryParameters['customer'] ?? '',
          orderType: state.uri.queryParameters['type'] ?? 'dine_in',
        ),
      ),
      GoRoute(
        path: '/kasir/receipt/:orderId',
        name: Routes.kasirReceipt,
        builder: (context, state) => ReceiptScreen(
          orderId: int.tryParse(state.pathParameters['orderId'] ?? '') ?? 0,
        ),
      ),

      GoRoute(path: '/kitchen', name: Routes.kitchen, builder: (_, _) => const KitchenScreen()),
      GoRoute(path: '/queue', name: Routes.queue, builder: (_, _) => const QueueScreen()),
      GoRoute(path: '/shift', name: Routes.shift, builder: (_, _) => const ShiftScreen()),

      // Data master
      GoRoute(path: '/master/menus', name: Routes.menus, builder: (_, _) => const MenuScreen()),
      GoRoute(path: '/master/categories', name: Routes.categories, builder: (_, _) => const CategoryScreen()),
      GoRoute(path: '/master/tables', name: Routes.tables, builder: (_, _) => const TableScreen()),
      GoRoute(path: '/master/promos', name: Routes.promos, builder: (_, _) => const PromoScreen()),
      GoRoute(path: '/master/ingredients', name: Routes.ingredients, builder: (_, _) => const IngredientScreen()),
      GoRoute(path: '/master/suppliers', name: Routes.suppliers, builder: (_, _) => const SupplierScreen()),

      // Finance
      GoRoute(path: '/finance/expenses', name: Routes.expenses, builder: (_, _) => const ExpenseScreen()),
      GoRoute(path: '/finance/stock', name: Routes.stockIn, builder: (_, _) => const StockScreen()),
      GoRoute(path: '/finance/opname', name: Routes.stockOpname, builder: (_, _) => const StockOpnameScreen()),

      // Report & akun
      GoRoute(path: '/reports', name: Routes.reports, builder: (_, _) => const ReportScreen()),
      GoRoute(path: '/profile', name: Routes.profile, builder: (_, _) => const ProfileScreen()),
      GoRoute(path: '/settings', name: Routes.settings, builder: (_, _) => const SettingScreen()),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.help_outline_rounded, size: 48),
              const SizedBox(height: 12),
              Text('Halaman tidak ditemukan:\n${state.uri}', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/'),
                child: const Text('Kembali ke Beranda'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
});

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
    );
  }
}
