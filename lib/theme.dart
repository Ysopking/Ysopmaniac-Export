import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:io';

// FindUX Pro Corporate Design Theme (Material 3 + Apple Polished)
class FindUXProTheme {
  // Primary Seed Color (Apple-like Violet/Purple)
  static const Color primaryPurple = Color(0xFF2E1A47);
  static const Color backgroundWhite = Color(0xFFFFFFFF);
  static const Color surfaceWhite = Color(0xFFF0F0F5);
  static const Color lightGray = Color(0xFFE5E5EA);
  static const Color glassWhite = Color(0x33FFFFFF);

  // Material 3 ColorScheme (auto Light/Dark)
  static ColorScheme get lightColorScheme {
    return ColorScheme.fromSeed(
      seedColor: primaryPurple,
      brightness: Brightness.light,
    );
  }

  static ColorScheme get darkColorScheme {
    return ColorScheme.fromSeed(
      seedColor: primaryPurple,
      brightness: Brightness.dark,
    );
  }

  // Apple-like Gradients (softer, translucency hint)
  static LinearGradient get primaryGradient {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        primaryPurple,
        primaryPurple.withValues(alpha: 0.7),
      ],
    );
  }

  // Shapes
  static const BorderRadius squircleRadius = BorderRadius.all(Radius.circular(20));
  static const BorderRadius largeSquircleRadius = BorderRadius.all(Radius.circular(24));

  // Shadows (iOS style)
  static const BoxShadow subtleShadow = BoxShadow(
    color: Color(0x0A000000),
    blurRadius: 12,
    offset: Offset(0, 4),
  );

  // Typography - SF Pro (iOS) / Roboto (Android)
  static TextStyle get headlineStyle => Platform.isIOS
      ? const TextStyle(
          fontFamily: '.SF Pro Display',
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        )
      : const TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
        );

  static TextStyle get titleStyle => Platform.isIOS
      ? const TextStyle(
          fontFamily: '.SF Pro Display',
          fontSize: 28,
          fontWeight: FontWeight.w600,
        )
      : const TextStyle(fontSize: 28, fontWeight: FontWeight.w600);

  static TextStyle get bodyStyle => Platform.isIOS
      ? const TextStyle(fontFamily: '.SF Pro Text', fontSize: 17)
      : const TextStyle(fontSize: 17);

  static TextStyle get captionStyle => Platform.isIOS
      ? const TextStyle(fontFamily: '.SF Pro Text', fontSize: 13, color: Color(0xFF8E8E93))
      : const TextStyle(fontSize: 13, color: Color(0xFF8E8E93));

  // Buttons
  static ButtonStyle get primaryButtonStyle => ElevatedButton.styleFrom(
        backgroundColor: primaryPurple,
        foregroundColor: backgroundWhite,
        shape: RoundedRectangleBorder(borderRadius: squircleRadius),
        elevation: 0,
      );

  static ButtonStyle get outlinePurpleButtonStyle => OutlinedButton.styleFrom(
        foregroundColor: primaryPurple,
        side: const BorderSide(color: primaryPurple, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: squircleRadius),
      );

  // Cards
  static BoxDecoration get cardDecoration => BoxDecoration(
        color: backgroundWhite,
        borderRadius: squircleRadius,
        boxShadow: const [subtleShadow],
      );
}
