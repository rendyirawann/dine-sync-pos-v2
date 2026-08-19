import 'package:flutter/material.dart';

/// Token warna diambil PERSIS dari tema web (Metronic 8.2 — `style.bundle.css`),
/// supaya aplikasi mobile terasa satu keluarga dengan dashboard web.
class AppPalette {
  const AppPalette({
    required this.primary,
    required this.primaryActive,
    required this.primaryLight,
    required this.success,
    required this.successLight,
    required this.info,
    required this.infoLight,
    required this.warning,
    required this.warningLight,
    required this.danger,
    required this.dangerLight,
    required this.dark,
    required this.light,
    required this.secondary,
    required this.gray100,
    required this.gray200,
    required this.gray300,
    required this.gray400,
    required this.gray500,
    required this.gray600,
    required this.gray700,
    required this.gray800,
    required this.gray900,
    required this.surface,
    required this.appBg,
    required this.bodyColor,
    required this.textMuted,
    required this.border,
    required this.borderDashed,
  });

  final Color primary;
  final Color primaryActive;
  final Color primaryLight;
  final Color success;
  final Color successLight;
  final Color info;
  final Color infoLight;
  final Color warning;
  final Color warningLight;
  final Color danger;
  final Color dangerLight;
  final Color dark;
  final Color light;
  final Color secondary;
  final Color gray100;
  final Color gray200;
  final Color gray300;
  final Color gray400;
  final Color gray500;
  final Color gray600;
  final Color gray700;
  final Color gray800;
  final Color gray900;

  /// Warna kartu / permukaan (web: --bs-body-bg)
  final Color surface;

  /// Latar halaman (web: --bs-app-bg-color)
  final Color appBg;
  final Color bodyColor;
  final Color textMuted;
  final Color border;
  final Color borderDashed;

  /// Padanan kelas `bg-light-{color}` / `badge-light-{color}` di web.
  Color softOf(String name) => switch (name) {
        'primary' => primaryLight,
        'success' => successLight,
        'warning' => warningLight,
        'danger' => dangerLight,
        'info' => infoLight,
        _ => gray100,
      };

  /// Padanan kelas `text-{color}` / `badge-{color}` di web.
  Color solidOf(String name) => switch (name) {
        'primary' => primary,
        'success' => success,
        'warning' => warning,
        'danger' => danger,
        'info' => info,
        'dark' => dark,
        _ => gray600,
      };

  static const light$ = AppPalette(
    primary: Color(0xFF1B84FF),
    primaryActive: Color(0xFF056EE9),
    primaryLight: Color(0xFFE9F3FF),
    success: Color(0xFF17C653),
    successLight: Color(0xFFDFFFEA),
    info: Color(0xFF7239EA),
    infoLight: Color(0xFFF8F5FF),
    warning: Color(0xFFF6C000),
    warningLight: Color(0xFFFFF8DD),
    danger: Color(0xFFF8285A),
    dangerLight: Color(0xFFFFEEF3),
    dark: Color(0xFF1E2129),
    light: Color(0xFFF9F9F9),
    secondary: Color(0xFFF1F1F4),
    gray100: Color(0xFFF9F9F9),
    gray200: Color(0xFFF1F1F4),
    gray300: Color(0xFFDBDFE9),
    gray400: Color(0xFFC4CADA),
    gray500: Color(0xFF99A1B7),
    gray600: Color(0xFF78829D),
    gray700: Color(0xFF4B5675),
    gray800: Color(0xFF252F4A),
    gray900: Color(0xFF071437),
    surface: Color(0xFFFFFFFF),
    appBg: Color(0xFFF6F6F6),
    bodyColor: Color(0xFF071437),
    textMuted: Color(0xFF99A1B7),
    border: Color(0xFFF1F1F4),
    borderDashed: Color(0xFFDBDFE9),
  );

  /// Skala gray DIBALIK di dark mode (persis seperti web).
  static const dark$ = AppPalette(
    primary: Color(0xFF006AE6),
    primaryActive: Color(0xFF107EFF),
    primaryLight: Color(0xFF172331),
    success: Color(0xFF00A261),
    successLight: Color(0xFF1F212A),
    info: Color(0xFF883FFF),
    infoLight: Color(0xFF272134),
    warning: Color(0xFFC59A00),
    warningLight: Color(0xFF242320),
    danger: Color(0xFFE42855),
    dangerLight: Color(0xFF302024),
    dark: Color(0xFF272A34),
    light: Color(0xFF1B1C22),
    secondary: Color(0xFF363843),
    gray100: Color(0xFF1B1C22),
    gray200: Color(0xFF26272F),
    gray300: Color(0xFF363843),
    gray400: Color(0xFF464852),
    gray500: Color(0xFF636674),
    gray600: Color(0xFF808290),
    gray700: Color(0xFF9A9CAE),
    gray800: Color(0xFFB5B7C8),
    gray900: Color(0xFFF5F5F5),
    surface: Color(0xFF15171C),
    appBg: Color(0xFF0F1014),
    bodyColor: Color(0xFFF5F5F5),
    textMuted: Color(0xFF636674),
    border: Color(0xFF26272F),
    borderDashed: Color(0xFF363843),
  );
}

/// Akses palet dari widget: `context.palette.primary`
extension PaletteX on BuildContext {
  AppPalette get palette => Theme.of(this).brightness == Brightness.dark
      ? AppPalette.dark$
      : AppPalette.light$;
}

/// Radius & shadow mengikuti web (card 24, input/button 13.6, badge 8.8).
class AppRadius {
  static const double sm = 8.8;
  static const double base = 13.6;
  static const double card = 20; // web 24; sedikit diperkecil agar pas di layar HP
  static const double xl = 36;
  static const double pill = 999;
}

class AppShadow {
  /// Padanan `--bs-card-box-shadow`: blur & spread besar, opacity sangat rendah.
  static List<BoxShadow> card(Brightness b) => b == Brightness.dark
      ? const []
      : const [
          BoxShadow(
            offset: Offset(0, 3),
            blurRadius: 10,
            spreadRadius: 0,
            color: Color(0x0A000000),
          ),
        ];
}

/// Skala spacing web: n * 4px.
double sp(double n) => n * 4;
