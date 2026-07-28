import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider with ChangeNotifier {
  ThemeMode get themeMode => ThemeMode.light;
  bool get isDark => false;

  ThemeProvider();

  // Dark theme removed — app is always light.
  Future<void> toggleTheme() async {}

  static ThemeData get lightTheme => ThemeData(
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0A3D91)),
    useMaterial3: true,
  );

  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF121212),
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0A3D91), brightness: Brightness.dark),
    useMaterial3: true,
  );
}
