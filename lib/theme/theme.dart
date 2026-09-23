import 'package:flutter/material.dart';

class AppTheme {
  // Light theme colors - Cream and Pink palette
  static const Color lightBackground = Color(0xFFFFF8F0);
  static const Color lightAppBarAndCards = Color(0xFFFFE4E1);
  static const Color lightText = Color(0xFF4A4A4A);
  static const Color lightIcons = Color(0xFFD36C6C);

  // Dark theme colors
  static const Color darkBackground = Color(0xFF1E1E1E);
  static const Color darkAppBar = Color(0xFF2C2C2C);
  static const Color darkText = Color(0xFFF5EAEA);
  static const Color darkIcons = Color(0xFFFFA1B4);

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: lightIcons,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: lightBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: lightAppBarAndCards,
      foregroundColor: lightText,
      elevation: 2,
      shadowColor: Colors.black26,
      iconTheme: IconThemeData(color: lightIcons),
      actionsIconTheme: IconThemeData(color: lightIcons),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: lightAppBarAndCards,
      selectedItemColor: lightIcons,
      unselectedItemColor: lightText,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
    cardTheme: CardThemeData(
      color: lightAppBarAndCards,
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    iconTheme: const IconThemeData(color: lightIcons),
    textTheme: const TextTheme(
      displayLarge: TextStyle(color: lightText),
      displayMedium: TextStyle(color: lightText),
      displaySmall: TextStyle(color: lightText),
      headlineLarge: TextStyle(color: lightText),
      headlineMedium: TextStyle(color: lightText),
      headlineSmall: TextStyle(color: lightText),
      titleLarge: TextStyle(color: lightText),
      titleMedium: TextStyle(color: lightText),
      titleSmall: TextStyle(color: lightText),
      bodyLarge: TextStyle(color: lightText),
      bodyMedium: TextStyle(color: lightText),
      bodySmall: TextStyle(color: lightText),
      labelLarge: TextStyle(color: lightText),
      labelMedium: TextStyle(color: lightText),
      labelSmall: TextStyle(color: lightText),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: darkIcons,
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: darkBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: darkAppBar,
      foregroundColor: darkText,
      elevation: 2,
      shadowColor: Colors.black54,
      iconTheme: IconThemeData(color: darkIcons),
      actionsIconTheme: IconThemeData(color: darkIcons),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: darkAppBar,
      selectedItemColor: darkIcons,
      unselectedItemColor: darkText,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
    cardTheme: CardThemeData(
      color: darkAppBar,
      elevation: 2,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    iconTheme: const IconThemeData(color: darkIcons),
    textTheme: const TextTheme(
      displayLarge: TextStyle(color: darkText),
      displayMedium: TextStyle(color: darkText),
      displaySmall: TextStyle(color: darkText),
      headlineLarge: TextStyle(color: darkText),
      headlineMedium: TextStyle(color: darkText),
      headlineSmall: TextStyle(color: darkText),
      titleLarge: TextStyle(color: darkText),
      titleMedium: TextStyle(color: darkText),
      titleSmall: TextStyle(color: darkText),
      bodyLarge: TextStyle(color: darkText),
      bodyMedium: TextStyle(color: darkText),
      bodySmall: TextStyle(color: darkText),
      labelLarge: TextStyle(color: darkText),
      labelMedium: TextStyle(color: darkText),
      labelSmall: TextStyle(color: darkText),
    ),
  );
}