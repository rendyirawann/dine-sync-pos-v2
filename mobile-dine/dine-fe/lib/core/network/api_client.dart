import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../storage/auth_storage.dart';
import 'api_exception.dart';

/// Satu-satunya pintu keluar HTTP aplikasi.
///
/// Tugasnya: menempelkan Bearer token, membuka bungkus response
/// `{success, message, data, meta}` dari dine-be, dan mengubah semua
/// kegagalan menjadi [ApiException] dengan pesan Bahasa Indonesia.
class ApiClient {
  ApiClient({required AuthStorage storage, Dio? dio, this.onUnauthorized})
      : _storage = storage,
        _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = AppConfig.apiBaseUrl
      ..connectTimeout = AppConfig.connectTimeout
      ..receiveTimeout = AppConfig.receiveTimeout
      ..headers = {
        'Accept': 'application/json',
        'X-Requested-With': 'XMLHttpRequest',
      }
      // Kita tangani sendiri semua status di _wrap().
      ..validateStatus = (_) => true;

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.readToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          if (kDebugMode) {
            debugPrint('[API] ${options.method} ${options.uri}');
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  final AuthStorage _storage;

  /// Dipanggil bila server membalas 401 (token kedaluwarsa / dicabut).
  final Future<void> Function()? onUnauthorized;

  /// Ganti base URL saat runtime (fitur "ganti server" di layar login).
  void setServerBaseUrl(String serverBaseUrl) {
    final clean = serverBaseUrl.endsWith('/')
        ? serverBaseUrl.substring(0, serverBaseUrl.length - 1)
        : serverBaseUrl;
    _dio.options.baseUrl = '$clean/api/v1';
  }

  String get baseUrl => _dio.options.baseUrl;

  Future<ApiResponse> get(String path, {Map<String, dynamic>? query}) =>
      _wrap(() => _dio.get(path, queryParameters: _clean(query)));

  Future<ApiResponse> post(String path, {Object? data, Map<String, dynamic>? query}) =>
      _wrap(() => _dio.post(path, data: data, queryParameters: _clean(query)));

  Future<ApiResponse> put(String path, {Object? data}) =>
      _wrap(() => _dio.put(path, data: data));

  Future<ApiResponse> delete(String path, {Object? data}) =>
      _wrap(() => _dio.delete(path, data: data));

  /// Unggah file (mis. avatar) memakai multipart.
  Future<ApiResponse> upload(
    String path, {
    required String field,
    required String filePath,
    Map<String, dynamic>? fields,
  }) async {
    final form = FormData.fromMap({
      ...?fields,
      field: await MultipartFile.fromFile(filePath),
    });

    return _wrap(() => _dio.post(path, data: form));
  }

  Map<String, dynamic>? _clean(Map<String, dynamic>? q) {
    if (q == null) return null;
    final out = <String, dynamic>{};
    q.forEach((k, v) {
      if (v == null) return;
      if (v is String && v.isEmpty) return;
      out[k] = v is bool ? (v ? 1 : 0) : v;
    });
    return out.isEmpty ? null : out;
  }

  Future<ApiResponse> _wrap(Future<Response<dynamic>> Function() call) async {
    late Response<dynamic> res;

    try {
      res = await call();
    } on DioException catch (e) {
      throw ApiException(_networkMessage(e), isNetworkIssue: true);
    } catch (_) {
      throw ApiException(
        'Tidak dapat menghubungi server. Periksa koneksi Anda.',
        isNetworkIssue: true,
      );
    }

    final status = res.statusCode ?? 0;
    final body = res.data;
    final map = body is Map<String, dynamic> ? body : <String, dynamic>{};

    if (status >= 200 && status < 300) {
      return ApiResponse(
        data: map.containsKey('data') ? map['data'] : map,
        message: (map['message'] as String?) ?? 'Berhasil.',
        meta: map['meta'] is Map<String, dynamic> ? map['meta'] as Map<String, dynamic> : null,
        statusCode: status,
      );
    }

    if (status == 401) {
      await onUnauthorized?.call();
    }

    throw ApiException(
      (map['message'] as String?) ?? _statusMessage(status),
      statusCode: status,
      errors: _parseErrors(map['errors']),
    );
  }

  Map<String, List<String>>? _parseErrors(dynamic raw) {
    if (raw is! Map) return null;
    final out = <String, List<String>>{};
    raw.forEach((k, v) {
      if (v is List) {
        out['$k'] = v.map((e) => '$e').toList();
      } else if (v != null) {
        out['$k'] = ['$v'];
      }
    });
    return out.isEmpty ? null : out;
  }

  String _statusMessage(int status) => switch (status) {
        400 => 'Permintaan tidak valid.',
        401 => 'Sesi Anda berakhir. Silakan login kembali.',
        403 => 'Anda tidak punya akses untuk tindakan ini.',
        404 => 'Data tidak ditemukan.',
        409 => 'Permintaan bentrok dengan kondisi saat ini.',
        422 => 'Data yang dikirim tidak valid.',
        429 => 'Terlalu banyak permintaan. Coba lagi sebentar.',
        >= 500 => 'Terjadi kesalahan pada server.',
        _ => 'Permintaan gagal diproses.',
      };

  String _networkMessage(DioException e) => switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          'Koneksi ke server timeout. Periksa jaringan Anda.',
        DioExceptionType.connectionError =>
          'Tidak dapat menghubungi server. Pastikan alamat server benar dan perangkat terhubung jaringan.',
        DioExceptionType.badCertificate => 'Sertifikat server tidak valid.',
        DioExceptionType.cancel => 'Permintaan dibatalkan.',
        _ => 'Terjadi gangguan koneksi. Coba lagi.',
      };
}

/// Hasil panggilan API yang sudah dibuka bungkusnya.
class ApiResponse {
  const ApiResponse({
    required this.data,
    required this.message,
    required this.statusCode,
    this.meta,
  });

  final dynamic data;
  final String message;
  final int statusCode;
  final Map<String, dynamic>? meta;

  Map<String, dynamic> get asMap =>
      data is Map<String, dynamic> ? data as Map<String, dynamic> : <String, dynamic>{};

  List<Map<String, dynamic>> get asList => data is List
      ? (data as List).whereType<Map<String, dynamic>>().toList()
      : const <Map<String, dynamic>>[];

  /// Ambil list dari sebuah kunci di dalam data (mis. `tables`, `orders`).
  List<Map<String, dynamic>> listAt(String key) {
    final v = asMap[key];
    return v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];
  }

  bool get hasMore => meta?['has_more'] == true;
  int get currentPage => (meta?['current_page'] as num?)?.toInt() ?? 1;
  int get lastPage => (meta?['last_page'] as num?)?.toInt() ?? 1;
}
