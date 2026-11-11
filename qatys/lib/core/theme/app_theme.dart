import 'package:flutter/material.dart';

/// Visual rules from FLUTTER_BRIEF.md section 8: readable outdoors (high
/// contrast), 48 dp minimum tap targets. The look follows the app icon: deep
/// KBTU blue with an amber accent (the notification dot of the icon).
abstract final class AppTheme {
  static const Color brand = Color(0xFF0B3D91);
  static const Color brandLight = Color(0xFF164FB0);
  static const Color accent = Color(0xFFFFB020);

  /// Urgent deadlines and full events: a red that stays readable in sunlight.
  static const Color urgent = Color(0xFFC62828);

  static const double minTapTarget = 48;
  static const double radius = 16;

  /// Gradient of the icon, for headers.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandLight, Color(0xFF072A66)],
  );

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    var colorScheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: brightness,
      // High contrast: no light grey on white, readable in sunlight.
      contrastLevel: 0.5,
    );
    if (isLight) {
      colorScheme = colorScheme.copyWith(
        primary: brand,
        onPrimary: Colors.white,
        surface: const Color(0xFFF6F8FC),
        surfaceContainerLowest: Colors.white,
      );
    }

    const buttonMinSize = Size(64, 52);
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    const buttonText = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);

    final base = ThemeData(colorScheme: colorScheme, useMaterial3: true);
    final text = base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: colorScheme.surface,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLowest,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonMinSize,
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonMinSize,
          shape: buttonShape,
          textStyle: buttonText,
          side: BorderSide(color: colorScheme.outline, width: 1.5),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(64, minTapTarget),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant),
    );
  }
}

/// A stable colour per community, so each club is recognisable at a glance.
Color communityColor(int communityId) {
  const palette = [
    Color(0xFF0B3D91), // brand blue
    Color(0xFF00796B), // teal
    Color(0xFF6A1B9A), // purple
    Color(0xFFC2410C), // burnt orange
    Color(0xFF2E7D32), // green
    Color(0xFFAD1457), // magenta
    Color(0xFF455A64), // slate
  ];
  return palette[communityId.abs() % palette.length];
}

/// `IT Club` → `IC`, `Career Center` → `CC`, `Qatys` → `QA`.
String initials(String name) {
  final words = name
      .split(RegExp(r'\s+'))
      .where(
        (w) =>
            w.isNotEmpty &&
            RegExp('[A-Za-zА-Яа-яӘәҒғҚқҢңӨөҰұҮүІі0-9]').hasMatch(w[0]),
      )
      .toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    final w = words.first;
    return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
  }
  return (words[0][0] + words[1][0]).toUpperCase();
}
