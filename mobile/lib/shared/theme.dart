import 'package:flutter/material.dart';

/// Bolt / Uber–inspired ride-hail theme for bike delivery.
class BytzGoTheme {
  // Map canvas
  static const Color mapLand = Color(0xFF1A2332);
  static const Color mapRoad = Color(0xFF2D3A4F);
  static const Color mapWater = Color(0xFF15202B);
  static const Color mapGrid = Color(0xFF243044);

  // App chrome
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF141414);
  static const Color surfaceElevated = Color(0xFF1C1C1E);

  // Bottom sheet (Uber-style light card on map)
  static const Color sheetBg = Color(0xFFFFFFFF);
  static const Color sheetText = Color(0xFF111111);
  static const Color sheetMuted = Color(0xFF6B7280);
  static const Color sheetDivider = Color(0xFFE5E7EB);

  // Brand — BytzGO blue + lime (from marketing assets)
  static const Color brandBlue = Color(0xFF1E60C2);
  static const Color brandBlueBright = Color(0xFF2B7FE8);
  static const Color accent = Color(0xFF9AE234);
  static const Color accentDark = Color(0xFF82D91E);
  static const Color accentOn = Color(0xFF0A0A0A);

  static const Color danger = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);

  // Legacy dark text (map overlays, login)
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textMuted = Color(0xFF9CA3AF);
  static const Color border = Color(0xFF2A2A2E);

  static const double sheetRadius = 24;
  static const double buttonHeight = 56;

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      fontFamily: 'Roboto',
      colorScheme: const ColorScheme.dark(
        primary: brandBlue,
        secondary: accent,
        onPrimary: Colors.white,
        onSecondary: accentOn,
        surface: surface,
        onSurface: textPrimary,
        error: danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: sheetText,
          foregroundColor: sheetBg,
          minimumSize: const Size.fromHeight(buttonHeight),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            letterSpacing: 0.2,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceElevated,
        contentTextStyle: const TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: const DividerThemeData(color: border),
    );
  }

  static BoxDecoration sheetDecoration({bool shadow = true}) {
    return BoxDecoration(
      color: sheetBg,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(sheetRadius)),
      boxShadow: shadow
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ]
          : null,
    );
  }

  static TextStyle sheetTitle([double size = 22]) => TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w800,
        color: sheetText,
        letterSpacing: -0.5,
      );

  static TextStyle sheetBody([double size = 15]) => TextStyle(
        fontSize: size,
        color: sheetMuted,
        height: 1.35,
      );

  /// Light theme for white bottom sheets / customer tabs (avoids white-on-white from [dark]).
  static ThemeData sheetTheme() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: sheetBg,
      fontFamily: 'Roboto',
    );
    return base.copyWith(
      colorScheme: const ColorScheme.light(
        primary: brandBlue,
        onPrimary: Colors.white,
        secondary: accentDark,
        onSecondary: accentOn,
        surface: sheetBg,
        onSurface: sheetText,
        error: danger,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: sheetBg,
        foregroundColor: sheetText,
        elevation: 0,
        iconTheme: IconThemeData(color: sheetText),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: sheetText,
        displayColor: sheetText,
      ),
      iconTheme: const IconThemeData(color: sheetText),
      dividerTheme: const DividerThemeData(color: sheetDivider),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: brandBlue),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: sheetText,
          side: const BorderSide(color: sheetDivider),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brandBlue,
          foregroundColor: Colors.white,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: sheetDivider.withValues(alpha: 0.35),
        hintStyle: TextStyle(color: sheetMuted.withValues(alpha: 0.95)),
        labelStyle: const TextStyle(color: sheetMuted),
        floatingLabelStyle: const TextStyle(color: brandBlue),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: brandBlue),
    );
  }
}
