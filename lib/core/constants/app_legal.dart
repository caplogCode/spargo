abstract final class AppLegal {
  static const appName = 'sparGO';
  static const operatorName = '';
  static const managingDirector = '';
  static const postalAddress = '';
  static const contactEmail = '';
  static const privacyEmail = '';
  static const phone = '';
  static const websiteUrl = '';
  static const vatId = '';
  static const registerCourt = '';
  static const registerNumber = '';
  static const privacyLastUpdated = '16. April 2026';

  static bool get hasCompleteImpressum =>
      operatorName.trim().isNotEmpty &&
      postalAddress.trim().isNotEmpty &&
      contactEmail.trim().isNotEmpty;

  static String valueOrMissing(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'Noch nicht hinterlegt';
    }
    return trimmed;
  }
}
