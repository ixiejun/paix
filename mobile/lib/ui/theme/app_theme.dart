import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'syntax_theme.dart';

class AppTheme {
  static ThemeData light() {
    const syntax = SyntaxTheme.light;

    final scheme = ColorScheme.fromSeed(
      seedColor: syntax.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: syntax.primary,
      onPrimary: Colors.white,
      secondary: syntax.info,
      onSecondary: Colors.white,
      error: syntax.danger,
      onError: Colors.white,
      surface: syntax.surface,
      onSurface: syntax.text,
    );

    return _base(
      colorScheme: scheme,
      syntaxTheme: syntax,
      brightness: Brightness.light,
    );
  }

  static ThemeData dark() {
    const syntax = SyntaxTheme.dark;

    final scheme = ColorScheme.fromSeed(
      seedColor: syntax.primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: syntax.primary,
      onPrimary: Colors.white,
      secondary: syntax.info,
      onSecondary: Colors.black,
      error: syntax.danger,
      onError: Colors.white,
      surface: syntax.background,
      onSurface: syntax.text,
    );

    return _base(
      colorScheme: scheme,
      syntaxTheme: syntax,
      brightness: Brightness.dark,
    );
  }

  static ThemeData _base({
    required ColorScheme colorScheme,
    required SyntaxTheme syntaxTheme,
    required Brightness brightness,
  }) {
    final textTheme = GoogleFonts.dmSansTextTheme().apply(
      bodyColor: syntaxTheme.text,
      displayColor: syntaxTheme.text,
    );

    final heading = GoogleFonts.spaceGroteskTextTheme(textTheme);

    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: syntaxTheme.background,
      textTheme: heading,
      splashFactory: InkSparkle.splashFactory,
      extensions: <ThemeExtension<dynamic>>[
        syntaxTheme,
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: syntaxTheme.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: heading.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: syntaxTheme.text,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: syntaxTheme.border,
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: syntaxTheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: syntaxTheme.border),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xCC0B0B10) : const Color(0xFF0F172A),
        contentTextStyle: heading.bodyMedium?.copyWith(color: const Color(0xFFF1F5F9)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: syntaxTheme.surface,
        hintStyle: heading.bodyMedium?.copyWith(color: syntaxTheme.textMuted),
        labelStyle: heading.bodyMedium?.copyWith(color: syntaxTheme.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: syntaxTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: syntaxTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: syntaxTheme.border.withValues(alpha: 0.30), width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: syntaxTheme.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: heading.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: syntaxTheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: heading.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: syntaxTheme.surface2,
        labelStyle: heading.labelMedium?.copyWith(color: syntaxTheme.text),
        side: BorderSide(color: syntaxTheme.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: syntaxTheme.surface2,
        labelTextStyle: WidgetStatePropertyAll(
          heading.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
