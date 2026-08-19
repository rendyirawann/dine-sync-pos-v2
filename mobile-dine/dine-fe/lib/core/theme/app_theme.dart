import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Tema aplikasi: warna & bobot huruf mengikuti web (Inter),
/// tetapi ukuran huruf/komponen disetel ulang untuk layar HP.
///
/// Pemetaan bobot dari web (penamaan Bootstrap menipu):
///   fw-semibold -> w500 · fw-bold -> w600 · fw-bolder -> w700
class AppTheme {
  static ThemeData light() => _build(AppPalette.light$, Brightness.light);

  static ThemeData dark() => _build(AppPalette.dark$, Brightness.dark);

  static ThemeData _build(AppPalette p, Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    // Inter — font yang dipakai seluruh dashboard web.
    final base = GoogleFonts.interTextTheme(
      brightness == Brightness.dark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    );

    final text = base.copyWith(
      // Judul halaman (web: h1 fs-2 fw-bold)
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: p.gray900,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: p.gray800,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 15.5,
        fontWeight: FontWeight.w600,
        color: p.gray800,
      ),
      // Body default (web fs-6 = 17.2px; di HP dipakai 15 agar padat & terbaca)
      bodyLarge: base.bodyLarge?.copyWith(fontSize: 15, color: p.gray800),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 14, color: p.gray700),
      bodySmall: base.bodySmall?.copyWith(fontSize: 12.5, color: p.textMuted),
      labelLarge: base.labelLarge?.copyWith(fontSize: 14.5, fontWeight: FontWeight.w600),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: p.textMuted,
        letterSpacing: .3,
      ),
    );

    final scheme = ColorScheme.fromSeed(
      seedColor: p.primary,
      brightness: brightness,
    ).copyWith(
      primary: p.primary,
      secondary: p.info,
      error: p.danger,
      surface: p.surface,
      onSurface: p.bodyColor,
      outline: p.border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.appBg,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: p.gray900,
        elevation: 0,
        scrolledUnderElevation: .5,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: p.gray700, size: 22),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: p.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? p.gray100 : p.gray100,
        contentPadding: EdgeInsets.symmetric(horizontal: sp(4), vertical: sp(3.5)),
        hintStyle: TextStyle(color: p.textMuted, fontSize: 14),
        labelStyle: TextStyle(color: p.gray700, fontSize: 14, fontWeight: FontWeight.w500),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.base),
          borderSide: BorderSide(color: p.gray300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.base),
          borderSide: BorderSide(color: p.gray300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.base),
          borderSide: BorderSide(color: p.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.base),
          borderSide: BorderSide(color: p.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.base),
          borderSide: BorderSide(color: p.danger, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: p.gray300,
          disabledForegroundColor: p.gray500,
          elevation: 0,
          minimumSize: Size(0, sp(12)),
          padding: EdgeInsets.symmetric(horizontal: sp(5)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.base)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.gray800,
          side: BorderSide(color: p.gray300),
          minimumSize: Size(0, sp(12)),
          padding: EdgeInsets.symmetric(horizontal: sp(5)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.base)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.primary,
          textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.gray100,
        selectedColor: p.primaryLight,
        labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.gray700),
        side: BorderSide(color: p.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
        padding: EdgeInsets.symmetric(horizontal: sp(2)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.surface,
        selectedItemColor: p.primary,
        unselectedItemColor: p.gray500,
        selectedLabelStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.primaryLight,
        height: 64,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.gray700),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.gray900,
        contentTextStyle: const TextStyle(fontSize: 14, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.base)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.primary,
        linearTrackColor: p.gray200,
        circularTrackColor: p.gray200,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : p.gray500,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.primary : p.gray300,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.gray600,
        titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        subtitleTextStyle: text.bodySmall,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.primary,
        unselectedLabelColor: p.gray600,
        indicatorColor: p.primary,
        labelStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
        dividerColor: p.border,
      ),
    );
  }
}
