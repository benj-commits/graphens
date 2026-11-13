import 'package:flutter/material.dart';

// Dark enough to remain legible on the light surfaces used throughout the app.
const gold = Color(0xFF79511E);
const ink = Color(0xFF342018);
const cream = Color(0xFFFBF6EE);
const leather = Color(0xFF5A3526);

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: leather,
        primary: ink,
        onPrimary: Colors.white,
        secondary: gold,
        onSecondary: Colors.white,
        surface: cream,
        onSurface: ink,
      ),
      scaffoldBackgroundColor: cream,
      appBarTheme: const AppBarTheme(backgroundColor: ink, foregroundColor: Colors.white, elevation: 0, centerTitle: true),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFFF1E6D9),
        indicatorColor: const Color(0xFFE1CBB4),
        iconTheme: WidgetStateProperty.all(const IconThemeData(color: ink)),
        labelTextStyle: WidgetStateProperty.all(const TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
