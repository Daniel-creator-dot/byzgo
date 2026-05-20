import 'package:flutter/material.dart';

import '../theme.dart';

/// Applies [BytzGoTheme.sheetTheme] so buttons and fields are readable on white sheets.
class SheetThemeScope extends StatelessWidget {
  const SheetThemeScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: BytzGoTheme.sheetTheme(),
      child: child,
    );
  }
}
