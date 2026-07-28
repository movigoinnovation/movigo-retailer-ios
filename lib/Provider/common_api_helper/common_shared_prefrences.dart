import 'package:shared_preferences/shared_preferences.dart';

class CacheHelper {
  static Future<void> save(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  static Future<String?> get(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  static Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  // Only clears auth-related keys, preserves language and other settings
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_details');
    await prefs.remove('auth_token');
    await prefs.remove('current_token');
    await prefs.remove('token');
  }
  
}

