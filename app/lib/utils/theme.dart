import 'package:flutter/material.dart';

class AppTheme {
  // Brand Colors
  static const Color primaryColor = Color(
    0xFF4DA3FF,
  ); // High-contrast accent blue
  static const Color secondaryColor = Color(
    0xFFB8BCC4,
  ); // Brushed Steel / Silver
  static const Color backgroundColor = Color(0xFF1A1A1A); // Dark Charcoal

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: secondaryColor,
        surface: backgroundColor,
      ),
      scaffoldBackgroundColor: backgroundColor,
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundColor,
        foregroundColor: secondaryColor,
        elevation: 0,
      ),
      fontFamily: 'Inter',
      textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Inter'),
    );
  }
}
