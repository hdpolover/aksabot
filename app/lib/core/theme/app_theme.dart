import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_constants.dart';
import 'app_colors.dart';

/// Central theme configuration for Aksabot.
///
/// Design language: bold, approachable, robot-companion-friendly.
/// - Plus Jakarta Sans for geometric, techy-yet-warm typography
/// - Blue primary for a clear, trustworthy AI-companion identity
/// - Pill-shaped buttons and large radii for a friendly feel
/// - Filled cards (no border outlines) for a modern, clean look
class AppTheme {
  static const _seedColor = Color(0xFF1D6EEA); // Blue — trustworthy, AI-companion identity

  static ThemeData get light => _buildTheme(Brightness.light);
  static ThemeData get dark => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: brightness,
    );

    final baseTextTheme =
        isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(baseTextTheme);

    // Bold, high-contrast heading styles
    final styledTextTheme = textTheme.copyWith(
      headlineLarge: textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      headlineMedium: textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      headlineSmall: textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleLarge: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      titleSmall: textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      labelLarge: textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      textTheme: styledTextTheme,
      extensions: [isDark ? AppColors.dark : AppColors.light],

      // -- Scaffold: base surface (Level 0) --
      scaffoldBackgroundColor: isDark
          ? colorScheme.surface  // darkest in dark mode
          : colorScheme.surface,

      // -- App bar: same as scaffold (Level 0), separates via scrolled elevation --
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: isDark ? 1 : 0.5,
        titleTextStyle: styledTextTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
          fontSize: 18,
        ),
      ),

      // -- Card: raised surface (Level 2 in dark, Level 0 in light) --
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark
            ? colorScheme.surfaceContainerHigh  // visibly raised in dark
            : colorScheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
      ),

      // -- Input: rounded, visible focus border --
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingLg,
          vertical: 14,
        ),
      ),

      // -- Elevated button: pill, bold --
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size(double.infinity, AppConstants.buttonHeight),
          shape: const StadiumBorder(),
          textStyle: styledTextTheme.labelLarge?.copyWith(
            fontSize: 15,
          ),
        ),
      ),

      // -- Filled button: pill --
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, AppConstants.buttonHeight),
          shape: const StadiumBorder(),
          textStyle: styledTextTheme.labelLarge?.copyWith(
            fontSize: 15,
          ),
        ),
      ),

      // -- Outlined button: pill --
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppConstants.buttonHeight),
          shape: const StadiumBorder(),
          side: BorderSide(color: colorScheme.outline),
          textStyle: styledTextTheme.labelLarge?.copyWith(
            fontSize: 15,
          ),
        ),
      ),

      // -- Text button: pill --
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const StadiumBorder(),
        ),
      ),

      // -- Floating action button: extended feel --
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
      ),

      // -- Dialog: overlay surface (Level 3 in dark) --
      dialogTheme: DialogThemeData(
        backgroundColor: isDark
            ? colorScheme.surfaceContainerHighest
            : colorScheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl + 4),
        ),
      ),

      // -- Bottom sheet: overlay surface (Level 3 in dark) --
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surfaceContainerLowest,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusXl + 4),
          ),
        ),
        showDragHandle: true,
      ),

      // -- Snack bar: rounded, bold --
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
      ),

      // -- Navigation bar (bottom nav): raised surface (Level 1), pill indicator --
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark
            ? colorScheme.surfaceContainer
            : null,
        indicatorShape: const StadiumBorder(),
        indicatorColor: colorScheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 72,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colorScheme.onPrimaryContainer);
          }
          return IconThemeData(color: colorScheme.onSurfaceVariant);
        }),
      ),

      // -- Switch: filled track --
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.onPrimary;
          }
          return colorScheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.surfaceContainerHighest;
        }),
      ),

      // -- Chip: rounded, tonal --
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        backgroundColor: isDark
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surfaceContainerLow,
      ),

      // -- Divider --
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        thickness: 1,
        space: 1,
      ),

      // -- List tile --
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
      ),

      // -- Tab bar --
      tabBarTheme: TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: styledTextTheme.labelLarge,
        unselectedLabelStyle: styledTextTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w400,
        ),
      ),

      // -- Progress indicator --
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        circularTrackColor: colorScheme.primaryContainer,
      ),
    );
  }
}
