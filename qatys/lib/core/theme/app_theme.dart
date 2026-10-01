import 'package:flutter/material.dart';

/// Visual rules from FLUTTER_BRIEF.md section 8:
/// readable outdoors (high contrast) and 48 dp minimum tap targets.
abstract final class AppTheme {
  static const Color _seed = Color(0xFF0B3D91);

  static const double minTapTarget = 48;

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
      // Maximum contrast: no light grey on white, readable in sunlight.
      contrastLevel: 1,
    );

    const buttonMinSize = Size(64, minTapTarget);

    return ThemeData(
      colorScheme: colorScheme,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: buttonMinSize),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: buttonMinSize),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: buttonMinSize),
      ),
    );
  }
}
