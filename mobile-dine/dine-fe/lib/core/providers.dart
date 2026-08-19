import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network/api_client.dart';
import 'storage/auth_storage.dart';

/// Penyimpanan sesi (token + user + preferensi).
final authStorageProvider = Provider<AuthStorage>((ref) => AuthStorage());

/// Klien HTTP tunggal untuk seluruh aplikasi.
final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(authStorageProvider);

  return ApiClient(
    storage: storage,
    onUnauthorized: () async {
      // Token tidak valid lagi → bersihkan sesi supaya router memindahkan ke login.
      await storage.clearSession();
      ref.invalidate(sessionRestoreProvider);
    },
  );
});

/// Mode tema: system | light | dark (sama seperti pilihan di web).
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._storage) : super(ThemeMode.system) {
    _load();
  }

  final AuthStorage _storage;

  Future<void> _load() async {
    final saved = await _storage.readThemeMode();
    state = _parse(saved);
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await _storage.saveThemeMode(switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }

  static ThemeMode _parse(String v) => switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}

final themeModeProvider = StateNotifierProvider<ThemeModeController, ThemeMode>(
  (ref) => ThemeModeController(ref.watch(authStorageProvider)),
);

/// Dipakai router untuk menunggu proses pemulihan sesi saat aplikasi dibuka.
final sessionRestoreProvider = FutureProvider<void>((ref) async {});
