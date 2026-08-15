/// سمتا الألوان (فاتحة/داكنة) — منقولتان عن لوحة ألوان نسخة سطح المكتب.
library;

import 'package:flutter/material.dart';

const _brand = Color(0xFF14532D);
const _accent = Color(0xFFB45309);

ThemeData lightTheme() {
  const scheme = ColorScheme.light(
    primary: _brand,
    onPrimary: Colors.white,
    secondary: _accent,
    onSecondary: Colors.white,
    surface: Colors.white,
    onSurface: Color(0xFF1C2733),
    error: Color(0xFFB91C1C),
    onError: Colors.white,
    outline: Color(0xFFDFE6EE),
  );
  return _base(scheme, scaffold: const Color(0xFFF4F6FA));
}

ThemeData darkTheme() {
  const scheme = ColorScheme.dark(
    primary: Color(0xFF6EE7A0),
    onPrimary: Color(0xFF0E1419),
    secondary: Color(0xFFC2600E),
    onSecondary: Colors.white,
    surface: Color(0xFF161E26),
    onSurface: Color(0xFFE4EBF3),
    error: Color(0xFFF08A8A),
    onError: Color(0xFF0E1419),
    outline: Color(0xFF29343F),
  );
  return _base(scheme, scaffold: const Color(0xFF0E1419));
}

ThemeData _base(ColorScheme scheme, {required Color scaffold}) => ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'PlexArabic',
      scaffoldBackgroundColor: scaffold,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outline),
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
