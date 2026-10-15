import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

abstract final class FanColors {
  static const ink = Color(0xFF151C32);
  static const textSecondary = Color(0xFF68738B);
  static const canvas = Color(0xFFF7F8FC);
  static const surface = Color(0xFFFFFFFF);
  static const line = Color(0xFFE6E8F0);
  static const lavender = Color(0xFF6D5DD3);
  static const lavenderSoft = Color(0xFFEFEBFF);
  static const blueSoft = Color(0xFFE5F0FF);
  static const mint = Color(0xFF37B47E);
  static const coral = Color(0xFFFF785A);
}

abstract final class FanMetrics {
  static const pageInset = 20.0;
  static const sectionGap = 24.0;
  static const cardRadius = 16.0;
  static const controlRadius = 12.0;
  static const sheetRadius = 24.0;
  static const primaryHeight = 48.0;
  static const secondaryHeight = 44.0;
}

abstract final class FanOsTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: FanColors.lavender,
      brightness: Brightness.light,
      primary: FanColors.ink,
      surface: FanColors.surface,
    );
    const fallbackFonts = <String>[
      'PingFang SC',
      'Noto Sans CJK SC',
      'Helvetica Neue',
    ];

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: FanColors.canvas,
      fontFamilyFallback: fallbackFonts,
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontSize: 28,
          height: 1.15,
          fontWeight: FontWeight.w600,
          letterSpacing: -1.2,
          color: FanColors.ink,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          height: 4 / 3,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.6,
          color: FanColors.ink,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          height: 1.5,
          fontWeight: FontWeight.w600,
          color: FanColors.ink,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          height: 1.3,
          fontWeight: FontWeight.w500,
          color: FanColors.ink,
        ),
        bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: FanColors.ink),
        bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: FanColors.ink),
        bodySmall: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: FanColors.textSecondary,
        ),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: FanColors.canvas,
        foregroundColor: FanColors.ink,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: FanColors.ink,
          fontFamilyFallback: fallbackFonts,
        ),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        color: FanColors.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(FanMetrics.cardRadius),
          ),
          side: BorderSide(color: FanColors.line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF0F2F6),
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(FanMetrics.controlRadius),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(FanMetrics.controlRadius),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: FanColors.lavender, width: 1.4),
          borderRadius: BorderRadius.circular(FanMetrics.controlRadius),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: const TextStyle(color: Color(0xFF98A2B3), fontSize: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: FanColors.ink,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FanMetrics.controlRadius),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: FanColors.ink,
          minimumSize: const Size.fromHeight(FanMetrics.secondaryHeight),
          side: const BorderSide(color: FanColors.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FanMetrics.controlRadius),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: Color(0xFFF0F2F6),
        selectedColor: FanColors.lavenderSoft,
        side: BorderSide.none,
        shape: StadiumBorder(),
        labelStyle: TextStyle(fontSize: 12, color: FanColors.textSecondary),
        secondaryLabelStyle: TextStyle(fontSize: 12, color: FanColors.ink),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          iconSize: 22,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: FanColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(FanMetrics.sheetRadius),
          ),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: FanColors.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: FanColors.ink,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(FanMetrics.sheetRadius),
          ),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        height: 66,
        elevation: 0,
        backgroundColor: FanColors.surface,
        indicatorColor: FanColors.lavenderSoft,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: const DividerThemeData(color: FanColors.line, thickness: 1),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
