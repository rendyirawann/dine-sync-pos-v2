import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/storage/auth_storage.dart';
import '../../models/session_user.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.isSubmitting = false,
    this.error,
  });

  final AuthStatus status;
  final SessionUser? user;
  final bool isSubmitting;
  final String? error;

  bool get isLoggedIn => status == AuthStatus.authenticated && user != null;

  AuthState copyWith({
    AuthStatus? status,
    SessionUser? user,
    bool? isSubmitting,
    String? error,
    bool clearError = false,
    bool clearUser = false,
  }) =>
      AuthState(
        status: status ?? this.status,
        user: clearUser ? null : (user ?? this.user),
        isSubmitting: isSubmitting ?? this.isSubmitting,
        error: clearError ? null : (error ?? this.error),
      );
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._api, this._storage) : super(const AuthState()) {
    restore();
  }

  final ApiClient _api;
  final AuthStorage _storage;

  /// Memulihkan sesi saat aplikasi dibuka: pakai cache user dulu (agar cepat),
  /// lalu segarkan dari server di belakang layar.
  Future<void> restore() async {
    final savedUrl = await _storage.readBaseUrl();
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _api.setServerBaseUrl(savedUrl);
    }

    final token = await _storage.readToken();
    if (token == null || token.isEmpty) {
      state = state.copyWith(status: AuthStatus.unauthenticated, clearUser: true);
      return;
    }

    final cached = await _storage.readUser();
    if (cached != null) {
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: SessionUser.fromJson(cached),
      );
    }

    try {
      final res = await _api.get('/auth/me');
      final user = SessionUser.fromJson(res.asMap);
      await _storage.saveUser(res.asMap);
      state = state.copyWith(status: AuthStatus.authenticated, user: user, clearError: true);
    } on ApiException catch (e) {
      // Token ditolak → paksa login ulang. Gangguan jaringan → tetap pakai cache.
      if (e.isUnauthorized || e.isForbidden) {
        await _storage.clearSession();
        state = state.copyWith(status: AuthStatus.unauthenticated, clearUser: true);
      } else if (cached == null) {
        state = state.copyWith(status: AuthStatus.unauthenticated, clearUser: true);
      }
    }
  }

  /// Ganti alamat server (mis. dari localhost ke IP kantor) lalu simpan.
  Future<void> setServer(String serverBaseUrl) async {
    _api.setServerBaseUrl(serverBaseUrl);
    await _storage.saveBaseUrl(serverBaseUrl);
  }

  Future<bool> login({
    required String login,
    required String password,
    String? deviceName,
  }) async {
    state = state.copyWith(isSubmitting: true, clearError: true);

    try {
      final res = await _api.post('/auth/login', data: {
        'login': login.trim(),
        'password': password,
        if (deviceName != null && deviceName.isNotEmpty) 'device_name': deviceName,
      });

      final map = res.asMap;
      final token = '${map['token'] ?? ''}';
      final userJson = map['user'];

      if (token.isEmpty || userJson is! Map<String, dynamic>) {
        state = state.copyWith(
          isSubmitting: false,
          error: 'Balasan server tidak sesuai. Hubungi administrator.',
        );
        return false;
      }

      await _storage.saveToken(token);
      await _storage.saveUser(userJson);

      state = AuthState(
        status: AuthStatus.authenticated,
        user: SessionUser.fromJson(userJson),
      );
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        error: e.errorFor('login') ?? e.message,
      );
      return false;
    }
  }

  Future<void> logout() async {
    state = state.copyWith(isSubmitting: true);
    try {
      await _api.post('/auth/logout');
    } on ApiException {
      // Walau gagal (mis. offline), sesi lokal tetap dibersihkan.
    }
    await _storage.clearSession();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Menyegarkan data user (dipakai setelah ubah profil/avatar).
  Future<void> refreshUser() async {
    try {
      final res = await _api.get('/auth/me');
      await _storage.saveUser(res.asMap);
      state = state.copyWith(user: SessionUser.fromJson(res.asMap));
    } on ApiException {
      /* diabaikan */
    }
  }

  void clearError() => state = state.copyWith(clearError: true);
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) => AuthController(ref.watch(apiClientProvider), ref.watch(authStorageProvider)),
);

/// Shortcut user aktif.
final currentUserProvider = Provider<SessionUser?>(
  (ref) => ref.watch(authControllerProvider).user,
);
