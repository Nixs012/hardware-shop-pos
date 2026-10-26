import 'package:flutter/material.dart';

class AppTheme {
  static const Color appBackground = Color(0xFF0B1120);
  static const Color secondaryBackground = Color(0xFF0F172A);
  static const Color cardBackground = Color(0xFF151E30);
  static const Color elevatedBackground = Color(0xFF1C2940);
  static const Color primaryColor = Color(0xFF3B82F6);
  static const Color highlightColor = Color(0xFF22D3EE);
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color borderColor = Color(0xFF29364B);
  static const Color successColor = Color(0xFF22C55E);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color backgroundColor = appBackground;
  static const Color surfaceColor = cardBackground;
  static const Color secondaryColor = textSecondary;
  static const double sp4 = 4;
  static const double sp8 = 8;
  static const double sp12 = 12;
  static const double sp16 = 16;
  static const double sp20 = 20;
  static const double sp24 = 24;
  static const double radiusSm = 12;
  static const double radiusMd = 14;
  static const double radiusLg = 16;

  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: highlightColor,
        surface: appBackground,
        error: errorColor,
        onPrimary: textPrimary,
        onSecondary: appBackground,
        onSurface: textPrimary,
        onError: textPrimary,
      ),
      scaffoldBackgroundColor: appBackground,
      canvasColor: appBackground,
      cardColor: cardBackground,
      dividerColor: borderColor,
      appBarTheme: const AppBarTheme(
        backgroundColor: appBackground,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
    );
  }
}



