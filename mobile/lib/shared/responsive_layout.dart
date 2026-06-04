import 'package:flutter/material.dart';

import 'theme.dart';

/// Breakpoints and layout helpers for phone vs iPad / tablet.
abstract final class BytzLayout {
  static const double tabletBreakpoint = 600;
  static const double splitMinWidth = 840;
  static const double phoneContentMaxWidth = 480;
  static const double tabletContentMaxWidth = 640;
  static const double rideSheetMaxWidth = 520;

  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).shortestSide >= tabletBreakpoint;

  static bool useTabletSplit(BuildContext context) {
    if (!isTablet(context)) return false;
    final size = MediaQuery.sizeOf(context);
    return size.width >= splitMinWidth && size.width >= size.height * 0.92;
  }

  static double contentMaxWidth(BuildContext context) {
    if (!isTablet(context)) return double.infinity;
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 1100) return 720;
    return tabletContentMaxWidth;
  }

  static double rideSheetWidth(BuildContext context) {
    if (!isTablet(context)) return double.infinity;
    final w = MediaQuery.sizeOf(context).width;
    return w.clamp(rideSheetMaxWidth, 600).toDouble();
  }

  static EdgeInsets horizontalGutter(BuildContext context) {
    if (!isTablet(context)) return EdgeInsets.zero;
    final size = MediaQuery.sizeOf(context);
    final excess = size.width - contentMaxWidth(context);
    if (excess <= 0) return EdgeInsets.zero;
    final pad = excess / 2;
    return EdgeInsets.symmetric(horizontal: pad);
  }

  /// Centers [child] with a max width on tablet (forms, lists, chrome).
  static Widget constrainContent(
    BuildContext context, {
    required Widget child,
    double? maxWidth,
    bool fillHeight = false,
  }) {
    if (!isTablet(context)) return child;
    final box = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth ?? contentMaxWidth(context),
      ),
      child: child,
    );
    if (fillHeight) {
      return Center(child: SizedBox(width: double.infinity, child: box));
    }
    return Center(child: box);
  }

  /// Bottom sheets / ride panels: peek width on portrait tablet.
  static Widget constrainBottomSheet(BuildContext context, Widget sheet) {
    if (useTabletSplit(context)) return sheet;
    if (!isTablet(context)) return sheet;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: rideSheetWidth(context)),
        child: sheet,
      ),
    );
  }

  /// Letterboxed shell for non-map tablet screens.
  static Widget tabletFrame(
    BuildContext context, {
    required Widget child,
    Color? backgroundColor,
  }) {
    if (!isTablet(context)) return child;
    return ColoredBox(
      color: backgroundColor ?? BytzGoTheme.background,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
          child: child,
        ),
      ),
    );
  }
}

/// Ride sheet lays out as a side panel when [BytzLayout.useTabletSplit] is true.
enum RideSheetLayout { auto, bottom, side }
