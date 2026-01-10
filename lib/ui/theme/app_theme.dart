import 'package:flutter/material.dart';

class AppTheme {
  // Serious colors: Skyblue and Light tones
  static const Color skyBlue = Color(0xFF007BFF);
  static const Color skyBlueLight = Color(0xFFE3F2FD);
  static const Color bgLight = Color(0xFFF8F9FA);
  static const Color bgLightSecondary = Color(0xFFFFFFFF);
  static const Color borderLight = Color(0xFFDEE2E6);
  static const Color textDark = Color(0xFF212529);
  static const Color textGray = Color(0xFF6C757D);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: bgLight,
      colorScheme: const ColorScheme.light(
        primary: skyBlue,
        secondary: skyBlue,
        surface: bgLight,
        surfaceContainer: bgLightSecondary,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textDark,
        onSurfaceVariant: textGray,
        outline: borderLight,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bgLight,
        foregroundColor: textDark,
        elevation: 0,
        centerTitle: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bgLightSecondary,
        indicatorColor: skyBlue.withOpacity(0.1),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(color: textDark, fontSize: 10),
        ),
        iconTheme: WidgetStateProperty.all(
          const IconThemeData(color: textDark),
        ),
      ),
      cardTheme: CardThemeData(
        color: bgLightSecondary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: borderLight),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: skyBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: skyBlue,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgLightSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: skyBlue, width: 2),
        ),
        labelStyle: const TextStyle(color: textGray),
        hintStyle: const TextStyle(color: textGray),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: textDark),
        displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textDark),
        displaySmall: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textDark),
        headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: textDark),
        headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textDark),
        titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textDark),
        titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textDark),
        bodyLarge: TextStyle(fontSize: 14, color: textDark),
        bodyMedium: TextStyle(fontSize: 13, color: textDark),
        bodySmall: TextStyle(fontSize: 12, color: textGray),
      ),
      dividerTheme: const DividerThemeData(
        color: borderLight,
        thickness: 1,
        space: 1,
      ),
    );
  }

  // Legacy for compatibility during transition
  static const Color orangeMain = skyBlue;
  static const Color orangeLight = skyBlueLight;
  static const Color bgDark = bgLight;
  static const Color bgDarkLighter = bgLightSecondary;
  static const Color borderDark = borderLight;
  static const Color textLight = textDark;
  static const Color textDim = textGray;

  static ThemeData get darkTheme => lightTheme; // Default to light as requested
}
