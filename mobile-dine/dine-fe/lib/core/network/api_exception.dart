/// Error API yang sudah diterjemahkan ke pesan Bahasa Indonesia yang siap tampil.
class ApiException implements Exception {
  ApiException(
    this.message, {
    this.statusCode,
    this.errors,
    this.isNetworkIssue = false,
  });

  final String message;
  final int? statusCode;

  /// Error validasi dari Laravel: { field: [pesan, ...] }
  final Map<String, List<String>>? errors;

  /// True bila masalahnya koneksi (bukan balasan server).
  final bool isNetworkIssue;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isValidation => statusCode == 422;
  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;
  bool get isTooManyRequests => statusCode == 429;

  /// Pesan error pertama untuk sebuah field (dipakai di form).
  String? errorFor(String field) {
    final list = errors?[field];
    return (list == null || list.isEmpty) ? null : list.first;
  }

  @override
  String toString() => message;
}
