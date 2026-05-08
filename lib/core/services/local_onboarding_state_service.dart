import 'package:shared_preferences/shared_preferences.dart';

class LocalOnboardingStateService {
  const LocalOnboardingStateService();

  static const String _cookieConsentKey = 'onboarding.cookie.accepted.v1';
  static const String _termsAcceptedPrefix = 'onboarding.terms.accepted.v1';
  static const String _userFlowCompletedPrefix = 'onboarding.user.completed.v2';

  Future<bool> isCookieAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_cookieConsentKey) ?? false;
  }

  Future<void> markCookieAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cookieConsentKey, true);
  }

  Future<bool> hasAcceptedTerms(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_termsKey(userId)) ?? false;
  }

  Future<void> markTermsAccepted(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_termsKey(userId), true);
  }

  Future<bool> hasCompletedUserOnboarding(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_completedKey(userId)) ?? false;
  }

  Future<void> markUserOnboardingCompleted(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedKey(userId), true);
  }

  String _termsKey(String userId) => '$_termsAcceptedPrefix.$userId';

  String _completedKey(String userId) => '$_userFlowCompletedPrefix.$userId';
}
