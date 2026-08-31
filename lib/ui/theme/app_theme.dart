import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Deep space / intelligence background palette
  static const Color background = Color(0xFF0B0F19);
  static const Color surface = Color(0xFF131B2E);
  static const Color surfaceCard = Color(0xFF1A243B);
  static const Color surfaceElevated = Color(0xFF22304E);
  static const Color border = Color(0xFF2A3B5F);
  static const Color borderGlow = Color(0xFF3B82F6);

  // Accent Colors
  static const Color primary = Color(0xFF38BDF8); // Electric Cyan
  static const Color primaryDark = Color(0xFF0284C7);
  static const Color accentAmber = Color(0xFFF59E0B); // Caution / Hub Highlight
  static const Color accentRose = Color(0xFFF43F5E); // High Risk / Anomaly
  static const Color accentEmerald = Color(0xFF10B981); // Verified Chain / Custody
  static const Color accentPurple = Color(0xFFA855F7); // AI Assistant

  // Text Colors
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
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
      textTheme: GoogleFonts.interTextTheme(
        ThemeData.dark().textTheme,
      ).copyWith(
        displayLarge: GoogleFonts.outfit(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
          letterSpacing: -0.5,
        ),
        displayMedium: GoogleFonts.outfit(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.5,
        ),
        titleLarge: GoogleFonts.outfit(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 14,
          color: AppColors.textPrimary,
          height: 1.5,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 13,
          color: AppColors.textSecondary,
          height: 1.4,
        ),
        labelSmall: GoogleFonts.jetBrainsMono(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.textMuted,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface.withOpacity(0.8),
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
      ),
      cardTheme: CardTheme(
        color: AppColors.surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceElevated,
        selectedColor: AppColors.primary.withOpacity(0.2),
        labelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
    );
  }
}
