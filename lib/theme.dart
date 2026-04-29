import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:io';

// FindUX Pro Corporate Design Theme
class FindUXProTheme {
  // Color Palette - Deep Royal Purple & Vibrant Light Purple
  static const Color primaryPurple = Color(0xFF2E1A47); // Even deeper purple for Premium look
  static const Color secondaryPurple = Color(0xFF6A1B9A); // Vibrant purple
  static const Color accentPurple = Color(0xFF9C27B0); // Light accent
  static const Color backgroundWhite = Color(0xFFFFFFFF); // Reinweiß
  static const Color surfaceWhite = Color(0xFFF0F0F5); // Slightly bluish off-white
  static const Color lightGray = Color(0xFFE5E5EA); // Standard iOS gray
  static const Color textPrimary = Color(0xFF1C1C1E); // Dark für iOS
  static const Color textSecondary = Color(0xFF8E8E93); // Gray für iOS
  static const Color glassWhite = Color(0x33FFFFFF); // Glassmorphism white (20% opacity)

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [primaryPurple, Color(0xFF120C21)], // Deeper gradient as seen in Option 1
  );

  // Shapes - iOS Squircle Aesthetics (strikte abgerundete Ecken)
  static const BorderRadius squircleRadius = BorderRadius.all(Radius.circular(20));
  static const BorderRadius largeSquircleRadius = BorderRadius.all(Radius.circular(24));
  static const double squircleBorderRadius = 20.0;
  static const double largeSquircleBorderRadius = 24.0;

  // Shadows - Subtle weiche Drop-Shadows (Opacity 0.05 - 0.1)
  static const BoxShadow subtleShadow = BoxShadow(
    color: Color(0x0A000000), // 5% opacity - weicher Schatten
    blurRadius: 12,
    offset: Offset(0, 4),
  );

  static const BoxShadow glassShadow = BoxShadow(
    color: Color(0x0D000000), // ~8% opacity
    blurRadius: 20,
    offset: Offset(0, 8),
  );

  // Typography - Cupertino SF Pro / Inter
  static TextStyle get headlineStyle => Platform.isIOS
      ? const TextStyle(
          fontFamily: '.SF Pro Display',
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.5,
        )
      : const TextStyle(
          fontFamily: 'Inter',
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
          fontFamily: 'Inter',
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
          fontFamily: 'Inter',
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
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: textSecondary,
        );

  // Button Styles
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

  // Glassmorphism Button (für Homescreen)
  static ButtonStyle get glassButtonStyle => ElevatedButton.styleFrom(
    backgroundColor: backgroundWhite.withOpacity(0.15),
    foregroundColor: backgroundWhite,
    shape: RoundedRectangleBorder(borderRadius: squircleRadius),
    elevation: 0,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
  );

  // Outline Button (Purple variant für Cards)
  static ButtonStyle get outlinePurpleButtonStyle => OutlinedButton.styleFrom(
    foregroundColor: primaryPurple,
    side: const BorderSide(color: primaryPurple, width: 1.5),
    shape: RoundedRectangleBorder(borderRadius: squircleRadius),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
  );

  // Text Button (Purple)
  static ButtonStyle get textPurpleButtonStyle => TextButton.styleFrom(
    foregroundColor: primaryPurple,
  );

  // Card Styles
  static BoxDecoration get cardDecoration => BoxDecoration(
    color: backgroundWhite,
    borderRadius: squircleRadius,
    boxShadow: [subtleShadow],
  );

  static BoxDecoration get glassCardDecoration => BoxDecoration(
    color: backgroundWhite.withOpacity(0.85),
    borderRadius: squircleRadius,
    border: Border.all(color: backgroundWhite.withOpacity(0.25)),
    boxShadow: [glassShadow],
  );

  // Input Styles
  static InputDecoration get searchInputDecoration => InputDecoration(
    filled: true,
    fillColor: backgroundWhite.withOpacity(0.95),
    border: OutlineInputBorder(
      borderRadius: largeSquircleRadius,
      borderSide: BorderSide.none,
    ),
    hintStyle: captionStyle.copyWith(color: textSecondary),
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    prefixIcon: const Icon(Icons.search, color: textSecondary),
  );

  // Purple AppBar Search Decoration
  static InputDecoration get purpleSearchInputDecoration => InputDecoration(
    filled: true,
    fillColor: backgroundWhite.withOpacity(0.2),
    border: OutlineInputBorder(
      borderRadius: largeSquircleRadius,
      borderSide: BorderSide.none,
    ),
    hintStyle: const TextStyle(color: backgroundWhite),
    hintText: 'Suchen...',
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    prefixIcon: const Icon(Icons.search, color: backgroundWhite),
  );

  // Cupertino Theme Data
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

  // Material Theme Data
  static ThemeData get materialTheme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryPurple,
      primary: primaryPurple,
      secondary: secondaryPurple,
      surface: backgroundWhite,
      onPrimary: backgroundWhite,
      onSecondary: backgroundWhite,
      onSurface: textPrimary,
    ),
    fontFamily: 'Inter',
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

  // Utility methods
  static BorderRadius getSquircleRadius(double radius) => BorderRadius.all(Radius.circular(radius));
}