import '../core/utils/formatters.dart';

/// User yang login + hak aksesnya (dipakai untuk menyembunyikan menu,
/// meniru `@can(...)` di web).
class SessionUser {
  const SessionUser({
    required this.id,
    required this.name,
    required this.email,
    this.username,
    this.noWa,
    this.avatarUrl,
    this.tenantId,
    this.tenantName,
    this.roles = const [],
    this.permissions = const [],
    this.isSuperadmin = false,
    this.lastLogin,
  });

  final String id;
  final String name;
  final String email;
  final String? username;
  final String? noWa;
  final String? avatarUrl;
  final String? tenantId;
  final String? tenantName;
  final List<String> roles;
  final List<String> permissions;
  final bool isSuperadmin;
  final String? lastLogin;

  factory SessionUser.fromJson(Map<String, dynamic> j) => SessionUser(
        id: '${j['id'] ?? ''}',
        name: J.toStr(j['name']) ?? 'Pengguna',
        email: J.toStr(j['email']) ?? '',
        username: J.toStr(j['username']),
        noWa: J.toStr(j['no_wa']),
        avatarUrl: J.toStr(j['avatar_url']),
        tenantId: J.toStr(j['tenant_id']),
        tenantName: J.toStr(j['tenant_name']),
        roles: _strings(j['roles']),
        permissions: _strings(j['permissions']),
        isSuperadmin: J.toBool(j['is_superadmin']),
        lastLogin: J.toStr(j['last_login']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'username': username,
        'no_wa': noWa,
        'avatar_url': avatarUrl,
        'tenant_id': tenantId,
        'tenant_name': tenantName,
        'roles': roles,
        'permissions': permissions,
        'is_superadmin': isSuperadmin,
        'last_login': lastLogin,
      };

  static List<String> _strings(dynamic v) =>
      v is List ? v.map((e) => '$e').toList() : const <String>[];

  /// Nama role utama untuk ditampilkan (mis. "Admin", "Kasir").
  String get roleLabel {
    if (roles.isEmpty) return 'Staff';
    final r = roles.first;
    return r.isEmpty ? 'Staff' : r[0].toUpperCase() + r.substring(1);
  }

  /// Label tenant di header — meniru badge navbar web.
  String get tenantLabel => tenantName ?? (isSuperadmin ? 'Semua UMKM (Superadmin)' : '-');

  /// Inisial untuk avatar fallback.
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  /// Cek hak akses. Superadmin selalu true (sama seperti `Gate::before` di web).
  bool can(String permission) => isSuperadmin || permissions.contains(permission);

  bool canAny(List<String> perms) => isSuperadmin || perms.any(permissions.contains);
}
