import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Konfigurasi dasar aplikasi.
///
/// Base URL bisa di-override saat build tanpa ubah kode:
///   flutter run --dart-define=API_BASE_URL=http://10.0.22.20/dine-sync-pos-v2/mobile-dine/dine-be/public
class AppConfig {
  static const String _override = String.fromEnvironment('API_BASE_URL');

  /// Root server (tanpa `/api`).
  static String get serverBaseUrl {
    if (_override.isNotEmpty) return _stripTrailingSlash(_override);

    // Default pengembangan: `php artisan serve --port=8001` di dine-be.
    // Emulator Android tidak bisa memakai localhost (itu merujuk ke emulator itu sendiri).
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:8001';

    return 'http://127.0.0.1:8001';
  }

  /// Prefix seluruh endpoint API.
  static String get apiBaseUrl => '$serverBaseUrl/api/v1';

  /// Alamat dokumentasi Swagger (memudahkan cek dari aplikasi).
  static String get swaggerUrl => '$serverBaseUrl/api/documentation';

  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration receiveTimeout = Duration(seconds: 30);

  static const String appName = 'DineSync POS';

  static String _stripTrailingSlash(String v) =>
      v.endsWith('/') ? v.substring(0, v.length - 1) : v;
}
