import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants/app_tokens.dart';
import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData light() {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.secondary,
      onSecondary: Colors.white,
      error: AppColors.error,
      onError: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      tertiary: AppColors.accent,
      onTertiary: Colors.white,
      outline: AppColors.divider,
      shadow: Color(0x14000000),
      scrim: Color(0x61000000),
      inverseSurface: AppColors.ink,
      onInverseSurface: Colors.white,
      inversePrimary: AppColors.secondary,
      surfaceTint: AppColors.primary,
      primaryContainer: Color(0xFFF9D7DF),
      onPrimaryContainer: AppColors.textPrimary,
      secondaryContainer: Color(0xFFFFE4EA),
      onSecondaryContainer: AppColors.textPrimary,
      tertiaryContainer: Color(0xFFF5D4DB),
      onTertiaryContainer: AppColors.textPrimary,
      errorContainer: Color(0xFFFFDFE4),
      onErrorContainer: Color(0xFF410015),
      surfaceContainerHighest: Color(0xFFF4E2E7),
      onSurfaceVariant: AppColors.textSecondary,
      outlineVariant: Color(0xFFEACFD7),
      surfaceContainerHigh: Color(0xFFFFF1F4),
      surfaceContainer: Color(0xFFFFF5F7),
      surfaceContainerLow: Color(0xFFFFFAFB),
      surfaceContainerLowest: Colors.white,
    );

    return _buildTheme(
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffold: AppColors.background,
      cardColor: AppColors.card,
      divider: AppColors.divider,
      textPrimary: AppColors.textPrimary,
      textSecondary: AppColors.textSecondary,
    );
  }

  static ThemeData dark() {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFFFE5EB),
      onPrimary: Color(0xFF2A1116),
      secondary: Color(0xFFFFBAC6),
      onSecondary: Color(0xFF43131D),
      error: Color(0xFFFFA3B0),
      onError: Color(0xFF420013),
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkTextPrimary,
      tertiary: Color(0xFFD6B8BE),
      onTertiary: Color(0xFF281A1F),
      outline: AppColors.darkDivider,
      shadow: Color(0x36000000),
      scrim: Color(0xA0000000),
      inverseSurface: Color(0xFFF6F1F4),
      onInverseSurface: AppColors.ink,
      inversePrimary: AppColors.secondary,
      surfaceTint: Color(0xFFFFE5EB),
      primaryContainer: Color(0xFF4C1623),
      onPrimaryContainer: Color(0xFFF6EEF3),
      secondaryContainer: Color(0xFF5A1A2A),
      onSecondaryContainer: Color(0xFFFFDDE4),
      tertiaryContainer: Color(0xFF402028),
      onTertiaryContainer: Color(0xFFF4E4E8),
      errorContainer: Color(0xFF5C1C2B),
      onErrorContainer: Color(0xFFFFD9E0),
      surfaceContainerHighest: Color(0xFF331C22),
      onSurfaceVariant: AppColors.darkTextSecondary,
      outlineVariant: Color(0xFF50333A),
      surfaceContainerHigh: Color(0xFF28171C),
      surfaceContainer: Color(0xFF231418),
      surfaceContainerLow: Color(0xFF1D1114),
      surfaceContainerLowest: Color(0xFF160C0F),
    );

    return _buildTheme(
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffold: AppColors.darkBackground,
      cardColor: AppColors.darkCard,
      divider: AppColors.darkDivider,
      textPrimary: AppColors.darkTextPrimary,
      textSecondary: AppColors.darkTextSecondary,
    );
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required ColorScheme colorScheme,
    required Color scaffold,
    required Color cardColor,
    required Color divider,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final baseTextTheme = GoogleFonts.urbanistTextTheme(
      _textTheme(textPrimary, textSecondary),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      fontFamily: GoogleFonts.urbanist().fontFamily,
      scaffoldBackgroundColor: scaffold,
      cardColor: cardColor,
      splashFactory: InkRipple.splashFactory,
      dividerColor: divider,
      textTheme: baseTextTheme,
      primaryTextTheme: baseTextTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: baseTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: textPrimary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.light
            ? colorScheme.surface
            : colorScheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          borderSide: BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          borderSide: BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          borderSide: const BorderSide(color: AppColors.secondary, width: 1.4),
        ),
        hintStyle: baseTextTheme.bodyMedium?.copyWith(color: textSecondary),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        side: BorderSide(color: divider),
        labelStyle: baseTextTheme.labelLarge!.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
        secondaryLabelStyle: baseTextTheme.labelLarge!.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
        backgroundColor: colorScheme.surfaceContainerLow,
        selectedColor: colorScheme.primaryContainer,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 10,
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        showCheckmark: false,
      ),
      dividerTheme: DividerThemeData(color: divider, thickness: 1, space: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.xl),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.secondary,
          foregroundColor: colorScheme.onSecondary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          textStyle: baseTextTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          side: BorderSide(color: divider),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.secondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.xl),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: brightness == Brightness.light
            ? Colors.white.withValues(alpha: 0.94)
            : const Color(0xFFF7EEF2),
        contentTextStyle: baseTextTheme.bodyMedium?.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.xl),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        actionTextColor: AppColors.primary,
        closeIconColor: AppColors.ink,
      ),
    );
  }

  static TextTheme _textTheme(Color textPrimary, Color textSecondary) {
    return TextTheme(
      displayLarge: TextStyle(
        fontSize: 42,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
        color: textPrimary,
        height: 1.05,
      ),
      displayMedium: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
        color: textPrimary,
        height: 1.08,
      ),
      headlineLarge: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
        color: textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: textPrimary,
      ),
      headlineSmall: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: textPrimary,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: textPrimary,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        color: textPrimary,
        height: 1.4,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        color: textSecondary,
        height: 1.45,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        color: textSecondary,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: textPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: textPrimary,
      ),
    );
  }
}
