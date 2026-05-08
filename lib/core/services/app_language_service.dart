import 'package:shared_preferences/shared_preferences.dart';

class AppLanguageService {
  const AppLanguageService();

  static const String _languageCodeKey = 'app.language.code.v1';

  Future<String?> loadLanguageCode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_languageCodeKey)?.trim().toLowerCase();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> saveLanguageCode(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageCodeKey, languageCode.trim().toLowerCase());
  }
}
