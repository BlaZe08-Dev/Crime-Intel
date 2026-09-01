import 'package:flutter/material.dart';

class AppColors {
  // Deep space / intelligence background palette
  static const Color background = Color(0xFF0B0F19);
  static const Color surface = Color(0xFF131B2E);
  static const Color surfaceCard = Color(0xFF1A243B);
  static const Color surfaceElevated = Color(0xFF22304E);
  static const Color border = Color(0xFF2A3B5F);
  static const Color borderGlow = Color(0xFF3B82F6);

  // Accents
  static const Color primary = Color(0xFF38BDF8); // Electric cyan
  static const Color primaryDark = Color(0xFF0284C7);
  static const Color accentAmber = Color(0xFFF59E0B); // Caution / hub highlight
  static const Color accentRose = Color(0xFFF43F5E); // High risk / anomaly
  static const Color accentEmerald = Color(0xFF10B981); // Verified chain
  static const Color accentPurple = Color(0xFFA855F7); // AI assistant

  // Text
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
}

/// Application theme.
///
/// Typography comes from fonts bundled in `assets/fonts` and declared in
/// `pubspec.yaml`, not from the `google_fonts` package. That package fetches
/// font files over HTTP on first launch, which violates the offline rule in
/// `docs/Rules.md` §16 and degrades to system fonts during an offline demo.
class AppTheme {
  /// Body and UI text.
  static const String sansFamily = 'Inter';

  /// Headings.
  static const String displayFamily = 'Outfit';

  /// Hashes, ids and log output. Not bundled - these are the monospace faces
  /// Windows already ships, so they cost nothing and cannot fail to load.
  static const List<String> monoFamilyFallback = [
    'Consolas',
    'Cascadia Mono',
    'Courier New',
  ];

  /// Style for hashes and record ids.
  static const TextStyle mono = TextStyle(
    fontFamilyFallback: monoFamilyFallback,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static ThemeData get darkTheme {
    const base =
        TextStyle(fontFamily: sansFamily, color: AppColors.textPrimary);

    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: sansFamily,
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.primary,
      cardColor: AppColors.surfaceCard,
      dividerColor: AppColors.border,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.accentAmber,
        surface: AppColors.surface,
        error: AppColors.accentRose,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: AppColors.textPrimary,
      ),
      textTheme: TextTheme(
        displayLarge: base.copyWith(
          fontFamily: displayFamily,
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        displayMedium: base.copyWith(
          fontFamily: displayFamily,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        titleLarge: base.copyWith(
          fontFamily: displayFamily,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: base.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
        bodyLarge: base.copyWith(fontSize: 14, height: 1.5),
        bodyMedium: base.copyWith(
          fontSize: 13,
          height: 1.4,
          color: AppColors.textSecondary,
        ),
        labelSmall: const TextStyle(
          fontFamilyFallback: monoFamilyFallback,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.textMuted,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface.withValues(alpha: 0.8),
        elevation: 0,
        centerTitle: false,
        titleTextStyle: base.copyWith(
          fontFamily: displayFamily,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceElevated,
        selectedColor: AppColors.primary.withValues(alpha: 0.2),
        labelStyle: base.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }
}
