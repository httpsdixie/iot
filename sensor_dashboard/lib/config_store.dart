import 'package:shared_preferences/shared_preferences.dart';

class ConfigStore {
  static Future<void> save(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (e) {
      // Safe fallback
    }
  }

  static Future<String?> load(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (e) {
      return null;
    }
  }
}
