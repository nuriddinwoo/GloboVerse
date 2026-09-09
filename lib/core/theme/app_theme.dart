import 'package:flutter/material.dart';

abstract class AppColors {
  const AppColors._();

  static const background = Color(0xFF080B18);
  static const surface = Color(0xFF111529);
  static const surfaceHigh = Color(0xFF191E36);
  static const primary = Color(0xFF8B74FF);
  static const primaryBright = Color(0xFFA99AFF);
  static const cyan = Color(0xFF4BD9EC);
  static const coral = Color(0xFFFF7D8D);
  static const amber = Color(0xFFFFC65C);
  static const success = Color(0xFF51D6A3);
  static const text = Color(0xFFF5F3FF);
  static const textMuted = Color(0xFF9CA3C4);
  static const divider = Color(0xFF252B48);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, Color(0xFF6254F3), Color(0xFF2BBED0)],
  );
}

abstract class AppTheme {
  const AppTheme._();

  static ThemeData dark() {
    const colorScheme = ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.cyan,
      onSecondary: AppColors.background,
      error: AppColors.coral,
      onError: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      outline: AppColors.divider,
      outlineVariant: Color(0xFF1E2440),
    );

    final baseTextTheme = ThemeData.dark(useMaterial3: true).textTheme;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
      textTheme: baseTextTheme.copyWith(
        displayLarge: const TextStyle(
          color: AppColors.text,
          fontSize: 44,
          height: 1.04,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.8,
        ),
        displaySmall: const TextStyle(
          color: AppColors.text,
          fontSize: 34,
          height: 1.08,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.2,
        ),
        headlineMedium: const TextStyle(
          color: AppColors.text,
          fontSize: 26,
          height: 1.16,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
        ),
        titleLarge: const TextStyle(
          color: AppColors.text,
          fontSize: 20,
          height: 1.2,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleMedium: const TextStyle(
          color: AppColors.text,
          fontSize: 16,
          height: 1.25,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: const TextStyle(
          color: AppColors.text,
          fontSize: 16,
          height: 1.5,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 14,
          height: 1.45,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: const TextStyle(
          color: AppColors.text,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
      appBarTheme: const AppBarThemeData(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.text,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.divider),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: AppColors.surfaceHigh,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        labelStyle: const TextStyle(color: AppColors.textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.coral),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 54),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.surfaceHigh,
          disabledForegroundColor: AppColors.textMuted,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          foregroundColor: AppColors.text,
          side: const BorderSide(color: AppColors.divider),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: const Color(0xF2111529),
        elevation: 0,
        indicatorColor: AppColors.primary.withValues(alpha: 0.18),
        iconTheme: const WidgetStatePropertyAll(
          IconThemeData(color: AppColors.textMuted, size: 24),
        ),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: const TextStyle(color: AppColors.text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.surface,
        modalBarrierColor: Color(0xB3080B18),
        showDragHandle: true,
        dragHandleColor: AppColors.divider,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.surfaceHigh,
      ),
    );
  }
}
