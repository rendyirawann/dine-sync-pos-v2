import 'package:intl/intl.dart';

/// Format angka & tanggal mengikuti web: `Rp 1.234.567` (tanpa desimal),
/// tanggal `dd MMM yyyy` dengan nama bulan Indonesia.
class Fmt {
  static final NumberFormat _rupiah = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  static final NumberFormat _number = NumberFormat.decimalPattern('id_ID');

  /// `Rp 25.000`
  static String rupiah(num? value) => _rupiah.format(value ?? 0);

  /// `25.000` (tanpa prefix)
  static String number(num? value) => _number.format(value ?? 0);

  /// Angka desimal untuk stok: `1.234,50`
  static String qty(num? value, {int decimals = 2}) {
    final f = NumberFormat.decimalPatternDigits(locale: 'id_ID', decimalDigits: decimals);
    return f.format(value ?? 0);
  }

  /// Bentuk ringkas untuk kartu statistik: `Rp 1,2 jt`
  static String rupiahShort(num? value) {
    final v = (value ?? 0).toDouble();
    if (v.abs() >= 1000000000) {
      return 'Rp ${_trim(v / 1000000000)} M';
    }
    if (v.abs() >= 1000000) {
      return 'Rp ${_trim(v / 1000000)} jt';
    }
    if (v.abs() >= 1000) {
      return 'Rp ${_trim(v / 1000)} rb';
    }
    return rupiah(v);
  }

  static String _trim(double v) {
    final s = v.toStringAsFixed(1).replaceAll('.', ',');
    return s.endsWith(',0') ? s.substring(0, s.length - 2) : s;
  }

  static DateTime? parse(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    return DateTime.tryParse(iso)?.toLocal();
  }

  /// `19 Agu 2026`
  static String date(dynamic value) {
    final d = value is DateTime ? value : parse(value as String?);
    if (d == null) return '-';
    return DateFormat('dd MMM yyyy', 'id_ID').format(d);
  }

  /// `19 Agustus 2026`
  static String dateLong(dynamic value) {
    final d = value is DateTime ? value : parse(value as String?);
    if (d == null) return '-';
    return DateFormat('dd MMMM yyyy', 'id_ID').format(d);
  }

  /// `19 Agu 2026 14:35`
  static String dateTime(dynamic value) {
    final d = value is DateTime ? value : parse(value as String?);
    if (d == null) return '-';
    return DateFormat('dd MMM yyyy HH:mm', 'id_ID').format(d);
  }

  /// `14:35`
  static String time(dynamic value) {
    final d = value is DateTime ? value : parse(value as String?);
    if (d == null) return '-';
    return DateFormat('HH:mm').format(d);
  }

  /// `2026-08-19` (untuk query API)
  static String apiDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  /// Jarak waktu singkat: `5 mnt lalu`, `2 jam lalu`.
  static String ago(dynamic value) {
    final d = value is DateTime ? value : parse(value as String?);
    if (d == null) return '-';
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60) return 'baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} mnt lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    if (diff.inDays < 30) return '${diff.inDays} hr lalu';
    return date(d);
  }
}

/// Konversi aman dari JSON (server bisa mengirim int/double/String).
class J {
  static double toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse('$v'.replaceAll(',', '.')) ?? 0;
  }

  static int toInt(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  static bool toBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = '$v'.toLowerCase();
    return s == 'true' || s == '1';
  }

  static String? toStr(dynamic v) {
    if (v == null) return null;
    final s = '$v';
    return s.isEmpty ? null : s;
  }
}
