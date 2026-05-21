import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Status bar / navigation bar styling for map vs light sheets.
class BytzSystemChrome {
  BytzSystemChrome._();

  static const _map = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: BytzGoTheme.background,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static const _lightSheet = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: BytzGoTheme.sheetBg,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  static const _darkHero = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: BytzGoTheme.background,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static void applyMap() => SystemChrome.setSystemUIOverlayStyle(_map);

  static void applyLightSheet() => SystemChrome.setSystemUIOverlayStyle(_lightSheet);

  static void applyDarkHero() => SystemChrome.setSystemUIOverlayStyle(_darkHero);
}
