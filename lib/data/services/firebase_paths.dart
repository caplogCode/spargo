abstract final class FirestoreCollections {
  static const users = 'users';
  static const businesses = 'businesses';
  static const deals = 'deals';
  static const stories = 'stories';
  static const redemptions = 'redemptions';
  static const notifications = 'notifications';
  static const reviews = 'reviews';
  static const businessVerificationSessions = '_businessVerificationSessions';
  static const businessDocumentReviews = '_businessDocumentReviews';
  static const publicCouponBusinesses = 'publicCouponBusinesses';
  static const publicCouponDeals = 'publicCouponDeals';
  static const publicCouponScanJobs = 'publicCouponScanJobs';
}

abstract final class FirebaseStoragePaths {
  static String businessVerificationDocument(
    String userId,
    String placeId,
    String filename,
  ) => 'business-verification/$userId/$placeId/$filename';

  static String businessLogo(String businessId) =>
      'businesses/$businessId/logo.png';

  static String businessCover(String businessId) =>
      'businesses/$businessId/cover.jpg';

  static String storyAsset(String businessId, String storyId) =>
      'businesses/$businessId/stories/$storyId.jpg';

  static String dealAsset(String businessId, String dealId) =>
      'businesses/$businessId/deals/$dealId.jpg';

  static String couponQr(String userId, String redemptionId) =>
      'users/$userId/redemptions/$redemptionId/qr.png';
}
