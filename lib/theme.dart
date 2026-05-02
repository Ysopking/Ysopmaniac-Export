import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:io';

// FindUX Pro Corporate Design Theme
class FindUXProTheme {
  // Color Palette
  static const Color primaryPurple = Color(0xFF2E1A47);
  static const Color secondaryPurple = Color(0xFF6A1B9A);
  static const Color accentPurple = Color(0xFF9C27B0);
  static const Color backgroundWhite = Color(0xFFFFFFFF);
  static const Color surfaceWhite = Color(0xFFF0F0F5);
  static const Color lightGray = Color(0xFFE5E5EA);
  static const Color textPrimary = Color(0xFF1C1C1E);
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color glassWhite = Color(0x33FFFFFF);

  // Dark variants
  static const Color darkBackground = Color(0xFF0F0820);
  static const Color darkSurface = Color(0xFF1A1130);
  static const Color darkTextPrimary = Color(0xFFF5F2FA);
  static const Color darkTextSecondary = Color(0xFFB8B0C8);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [primaryPurple, Color(0xFF120C21)],
  );

  // Shapes
  static const BorderRadius squircleRadius = BorderRadius.all(Radius.circular(20));
  static const BorderRadius largeSquircleRadius = BorderRadius.all(Radius.circular(24));
  static const double squircleBorderRadius = 20.0;
  static const double largeSquircleBorderRadius = 24.0;

  // Shadows
  static const BoxShadow subtleShadow = BoxShadow(
    color: Color(0x0A000000),
    blurRadius: 12,
    offset: Offset(0, 4),
  );
  static const BoxShadow glassShadow = BoxShadow(
    color: Color(0x0D000000),
    blurRadius: 20,
    offset: Offset(0, 8),
  );

  // Typography (Plattform-neutral, ohne nicht eingebundene 'Inter'-Schrift)
  static TextStyle get headlineStyle => Platform.isIOS
      ? const TextStyle(
          fontFamily: '.SF Pro Display',
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.5,
        )
      : const TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.5,
        );

  static TextStyle get titleStyle => Platform.isIOS
      ? const TextStyle(
          fontFamily: '.SF Pro Display',
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: -0.3,
        )
      : const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: -0.3,
        );

  static TextStyle get bodyStyle => Platform.isIOS
      ? const TextStyle(
          fontFamily: '.SF Pro Text',
          fontSize: 17,
          fontWeight: FontWeight.w400,
          color: textPrimary,
        )
      : const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w400,
          color: textPrimary,
        );

  static TextStyle get captionStyle => Platform.isIOS
      ? const TextStyle(
          fontFamily: '.SF Pro Text',
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: textSecondary,
        )
      : const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: textSecondary,
        );

  // Buttons
  static ButtonStyle get primaryButtonStyle => ElevatedButton.styleFrom(
        backgroundColor: primaryPurple,
        foregroundColor: backgroundWhite,
        shape: RoundedRectangleBorder(borderRadius: squircleRadius),
        elevation: 0,
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      );

  static ButtonStyle get secondaryButtonStyle => OutlinedButton.styleFrom(
        foregroundColor: backgroundWhite,
        side: const BorderSide(color: backgroundWhite, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: squircleRadius),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      );

  static ButtonStyle get glassButtonStyle => ElevatedButton.styleFrom(
        backgroundColor: backgroundWhite.withValues(alpha: 0.15),
        foregroundColor: backgroundWhite,
        shape: RoundedRectangleBorder(borderRadius: squircleRadius),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      );

  static ButtonStyle get outlinePurpleButtonStyle => OutlinedButton.styleFrom(
        foregroundColor: primaryPurple,
        side: const BorderSide(color: primaryPurple, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: squircleRadius),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      );

  static ButtonStyle get textPurpleButtonStyle => TextButton.styleFrom(
        foregroundColor: primaryPurple,
      );

  // Cards
  static BoxDecoration get cardDecoration => BoxDecoration(
        color: backgroundWhite,
        borderRadius: squircleRadius,
        boxShadow: const [subtleShadow],
      );

  static BoxDecoration get glassCardDecoration => BoxDecoration(
        color: backgroundWhite.withValues(alpha: 0.85),
        borderRadius: squircleRadius,
        border: Border.all(color: backgroundWhite.withValues(alpha: 0.25)),
        boxShadow: const [glassShadow],
      );

  // Inputs
  static InputDecoration get searchInputDecoration => InputDecoration(
        filled: true,
        fillColor: backgroundWhite.withValues(alpha: 0.95),
        border: OutlineInputBorder(
          borderRadius: largeSquircleRadius,
          borderSide: BorderSide.none,
        ),
        hintStyle: captionStyle.copyWith(color: textSecondary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        prefixIcon: const Icon(Icons.search, color: textSecondary),
      );

  static InputDecoration get purpleSearchInputDecoration => InputDecoration(
        filled: true,
        fillColor: backgroundWhite.withValues(alpha: 0.2),
        border: OutlineInputBorder(
          borderRadius: largeSquircleRadius,
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: backgroundWhite),
        hintText: 'Suchen...',
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        prefixIcon: const Icon(Icons.search, color: backgroundWhite),
      );

  // Cupertino theme
  static CupertinoThemeData get cupertinoTheme => const CupertinoThemeData(
        primaryColor: primaryPurple,
        scaffoldBackgroundColor: backgroundWhite,
        barBackgroundColor: primaryPurple,
        textTheme: CupertinoTextThemeData(
          navLargeTitleTextStyle: TextStyle(
            fontFamily: '.SF Pro Display',
            fontSize: 34,
            fontWeight: FontWeight.w700,
            color: backgroundWhite,
            letterSpacing: -0.5,
          ),
          navTitleTextStyle: TextStyle(
            fontFamily: '.SF Pro Display',
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: backgroundWhite,
          ),
        ),
      );

  // Material light
  static ThemeData get materialTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryPurple,
          primary: primaryPurple,
          secondary: secondaryPurple,
          surface: backgroundWhite,
          onPrimary: backgroundWhite,
          onSecondary: backgroundWhite,
          onSurface: textPrimary,
        ),
        textTheme: TextTheme(
          headlineLarge: headlineStyle,
          headlineMedium: titleStyle,
          bodyLarge: bodyStyle,
          bodyMedium: bodyStyle.copyWith(fontSize: 15),
          labelSmall: captionStyle,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(style: primaryButtonStyle),
        outlinedButtonTheme: OutlinedButtonThemeData(style: secondaryButtonStyle),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: squircleRadius),
          filled: true,
          fillColor: surfaceWhite,
        ),
        cardTheme: CardThemeData(
          color: backgroundWhite,
          shadowColor: subtleShadow.color,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: squircleRadius),
        ),
      );

  // Material dark — passend zur FindUX-Lila-Identitaet
  static ThemeData get materialDarkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: darkBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryPurple,
          brightness: Brightness.dark,
          primary: accentPurple,
          secondary: secondaryPurple,
          surface: darkSurface,
          onPrimary: backgroundWhite,
          onSecondary: backgroundWhite,
          onSurface: darkTextPrimary,
        ),
        textTheme: TextTheme(
          headlineLarge: headlineStyle.copyWith(color: darkTextPrimary),
          headlineMedium: titleStyle.copyWith(color: darkTextPrimary),
          bodyLarge: bodyStyle.copyWith(color: darkTextPrimary),
          bodyMedium: bodyStyle.copyWith(fontSize: 15, color: darkTextPrimary),
          labelSmall: captionStyle.copyWith(color: darkTextSecondary),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: accentPurple,
            foregroundColor: backgroundWhite,
            shape: RoundedRectangleBorder(borderRadius: squircleRadius),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
        cardTheme: CardThemeData(
          color: darkSurface,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: squircleRadius),
        ),
      );

  // Utility
  static BorderRadius getSquircleRadius(double radius) =>
      BorderRadius.all(Radius.circular(radius));
}
