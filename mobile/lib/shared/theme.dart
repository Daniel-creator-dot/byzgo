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

  // Brand — Bolt green
  static const Color accent = Color(0xFF00D170);
  static const Color accentDark = Color(0xFF00B35C);
  static const Color accentOn = Color(0xFF000000);

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
        primary: accent,
        onPrimary: accentOn,
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
}
