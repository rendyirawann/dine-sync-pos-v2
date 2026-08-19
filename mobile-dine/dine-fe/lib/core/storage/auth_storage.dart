import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Penyimpanan sesi: token di secure storage (Keystore/Keychain),
/// data user & preferensi ringan di SharedPreferences.
class AuthStorage {
  AuthStorage({FlutterSecureStorage? secure})
      : _secure = secure ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _secure;

  static const _kToken = 'dine_token';
  static const _kUser = 'dine_user';
  static const _kBaseUrl = 'dine_base_url';
  static const _kThemeMode = 'dine_theme_mode';

  Future<String?> readToken() async {
    try {
      return await _secure.read(key: _kToken);
    } catch (_) {
      // Bila secure storage tidak tersedia (mis. beberapa emulator lama),
      // jangan sampai aplikasi gagal jalan.
      return null;
    }
  }

  Future<void> saveToken(String token) async {
    try {
      await _secure.write(key: _kToken, value: token);
    } catch (_) {/* diabaikan */}
  }

  Future<void> clearToken() async {
    try {
      await _secure.delete(key: _kToken);
    } catch (_) {/* diabaikan */}
  }

  Future<Map<String, dynamic>?> readUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kUser);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUser, jsonEncode(user));
  }

  Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUser);
  }

  /// Base URL server yang dipilih user (untuk berpindah server tanpa rebuild).
  Future<String?> readBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kBaseUrl);
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> saveBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, url);
  }

  /// 'system' | 'light' | 'dark' — sama seperti pilihan tema di web.
  Future<String> readThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kThemeMode) ?? 'system';
  }

  Future<void> saveThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, mode);
  }

  Future<void> clearSession() async {
    await clearToken();
    await clearUser();
  }
}
