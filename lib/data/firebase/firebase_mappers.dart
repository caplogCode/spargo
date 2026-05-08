import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/business_models.dart';
import '../../domain/models/deal_models.dart';
import '../../domain/models/engagement_models.dart';
import '../../domain/models/notification_models.dart';
import '../../domain/models/story_models.dart';
import '../../domain/models/user_models.dart';

@immutable
class SessionUserRecord {
  const SessionUserRecord({
    required this.user,
    required this.ownedBusinessId,
    required this.onboardingCompleted,
    required this.businessOnboardingComplete,
    required this.hasLocationPermission,
    required this.activeDeviceId,
    required this.activeDeviceLabel,
    required this.pendingDeviceId,
    required this.pendingDeviceLabel,
  });

  final User user;
  final String ownedBusinessId;
  final bool onboardingCompleted;
  final bool businessOnboardingComplete;
  final bool hasLocationPermission;
  final String activeDeviceId;
  final String activeDeviceLabel;
  final String pendingDeviceId;
  final String pendingDeviceLabel;
}

@immutable
class DealRecord {
  const DealRecord({required this.deal, required this.isPaused});

  final Deal deal;
  final bool isPaused;
}

abstract final class FirebaseMappers {
  static SessionUserRecord sessionUserRecordFromMap(
    Map<String, dynamic> map, {
    required String id,
    String? fallbackEmail,
  }) {
    final name = _string(
      map['name'],
      fallbackEmail?.split('@').first ?? 'Nutzer',
    );
    final accountType = _enumFromName(
      AccountType.values,
      _string(map['accountType'], AccountType.user.name),
      AccountType.user,
    );
    final city = _string(map['city'], 'Deutschlandweit');
    final district = _string(map['district'], 'Dein Viertel');
    final ownedBusinessId = _string(map['ownedBusinessId']);
    final resolvedAccountType = ownedBusinessId.isNotEmpty
        ? AccountType.business
        : accountType;
    final preferences = userPreferencesFromMap(
      _map(map['preferences']),
      fallbackCity: city,
    );
    final rewards = _list(
      map['rewards'],
    ).map((entry) => rewardFromMap(_map(entry))).toList(growable: false);

    final user = User(
      id: id,
      accountType: resolvedAccountType,
      name: name,
      handle: _string(
        map['handle'],
        fallbackEmail == null
            ? '@nutzer'
            : '@${fallbackEmail.split('@').first.toLowerCase()}',
      ),
      city: city,
      district: district,
      latitude: _nullableDouble(map['latitude']),
      longitude: _nullableDouble(map['longitude']),
      avatarInitials: _string(map['avatarInitials'], _initials(name)),
      favoriteCategories: _enumList(
        DealCategory.values,
        _list(map['favoriteCategories']),
      ),
      savedDealIds: _stringList(map['savedDealIds']),
      activeDealIds: _stringList(map['activeDealIds']),
      followingBusinessIds: _stringList(map['followingBusinessIds']),
      seenStoryIds: _stringList(map['seenStoryIds']),
      rewards: rewards,
      points: _int(map['points']),
      freeCouponCredits: _int(map['freeCouponCredits']),
      inviteCode: _string(map['inviteCode'], _defaultInviteCode(id)),
      streakDays: _int(map['streakDays']),
      preferences: preferences,
    );

    final fallbackOnboardingCompleted =
        _bool(map['hasLocationPermission'], city != 'Deutschlandweit') ||
        user.favoriteCategories.isNotEmpty;

    return SessionUserRecord(
      user: user,
      ownedBusinessId: ownedBusinessId,
      onboardingCompleted: _bool(
        map['onboardingCompleted'],
        _bool(
          _map(map['onboarding'])['completed'],
          fallbackOnboardingCompleted,
        ),
      ),
      businessOnboardingComplete: _bool(
        map['businessOnboardingComplete'],
        resolvedAccountType != AccountType.business ||
            ownedBusinessId.isNotEmpty,
      ),
      hasLocationPermission: _bool(
        map['hasLocationPermission'],
        city != 'Deutschlandweit',
      ),
      activeDeviceId: _string(map['activeDeviceId']),
      activeDeviceLabel: _string(map['activeDeviceLabel']),
      pendingDeviceId: _string(map['pendingDeviceId']),
      pendingDeviceLabel: _string(map['pendingDeviceLabel']),
    );
  }

  static Map<String, dynamic> userToMap(
    User user, {
    String ownedBusinessId = '',
    bool? businessOnboardingComplete,
    bool? hasLocationPermission,
  }) {
    return <String, dynamic>{
      'accountType': user.accountType.name,
      'name': user.name,
      'handle': user.handle,
      'city': user.city,
      'district': user.district,
      'latitude': user.latitude,
      'longitude': user.longitude,
      'avatarInitials': user.avatarInitials,
      'favoriteCategories': user.favoriteCategories.map((e) => e.name).toList(),
      'savedDealIds': user.savedDealIds,
      'activeDealIds': user.activeDealIds,
      'followingBusinessIds': user.followingBusinessIds,
      'seenStoryIds': user.seenStoryIds,
      'rewards': user.rewards.map(rewardToMap).toList(),
      'points': user.points,
      'freeCouponCredits': user.freeCouponCredits,
      'inviteCode': user.inviteCode,
      'streakDays': user.streakDays,
      'preferences': userPreferencesToMap(user.preferences),
      'ownedBusinessId': ownedBusinessId,
      'businessOnboardingComplete':
          businessOnboardingComplete ??
          (user.accountType != AccountType.business ||
              ownedBusinessId.isNotEmpty),
      'hasLocationPermission':
          hasLocationPermission ?? user.city != 'Deutschlandweit',
    };
  }

  static Reward rewardFromMap(Map<String, dynamic> map) {
    return Reward(
      id: _string(map['id']),
      title: _string(map['title']),
      points: _int(map['points']),
      tier: _string(map['tier']),
      description: _string(map['description']),
      unlocked: _bool(map['unlocked']),
    );
  }

  static Map<String, dynamic> rewardToMap(Reward reward) {
    return <String, dynamic>{
      'id': reward.id,
      'title': reward.title,
      'points': reward.points,
      'tier': reward.tier,
      'description': reward.description,
      'unlocked': reward.unlocked,
    };
  }

  static UserPreferences userPreferencesFromMap(
    Map<String, dynamic> map, {
    String fallbackCity = 'Deutschlandweit',
  }) {
    return UserPreferences(
      interests: _enumList(DealCategory.values, _list(map['interests'])),
      city: _string(map['city'], fallbackCity),
      radiusKm: _double(map['radiusKm'], 8),
      notificationsEnabled: _bool(map['notificationsEnabled'], true),
      socialProofEnabled: _bool(map['socialProofEnabled'], true),
      openNowOnly: _bool(map['openNowOnly']),
      languageCode: _languageCode(map['languageCode']),
    );
  }

  static Map<String, dynamic> userPreferencesToMap(
    UserPreferences preferences,
  ) {
    final raw = preferences as dynamic;
    return <String, dynamic>{
      'interests': preferences.interests.map((e) => e.name).toList(),
      'city': preferences.city,
      'radiusKm': _double(raw.radiusKm, 35),
      'notificationsEnabled': _bool(raw.notificationsEnabled, true),
      'socialProofEnabled': _bool(raw.socialProofEnabled, true),
      'openNowOnly': _bool(raw.openNowOnly),
      'languageCode': _languageCode(raw.languageCode),
    };
  }

  static Business businessFromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    final name = _string(map['name']);
    final city = _string(map['city'], 'Deutschlandweit');
    final district = _string(map['district'], 'Dein Viertel');
    final parsedBranches = _list(
      map['branches'],
    ).map((entry) => branchFromMap(_map(entry))).toList(growable: false);
    final branches = parsedBranches.isEmpty
        ? <Branch>[
            Branch(
              id: '${id}_branch_fallback',
              name: name.isEmpty ? 'Standort' : name,
              city: city,
              district: district,
              address:
                  [district, city]
                      .where((entry) => entry.trim().isNotEmpty)
                      .join(', ')
                      .trim()
                      .isEmpty
                  ? 'Adresse folgt'
                  : [
                      district,
                      city,
                    ].where((entry) => entry.trim().isNotEmpty).join(', '),
              latitude: 52.5200,
              longitude: 13.4050,
              hours: const <BusinessHours>[],
            ),
          ]
        : parsedBranches
              .map(
                (branch) => _looksLikePlaceholderHours(branch.hours)
                    ? branch.copyWith(hours: const <BusinessHours>[])
                    : branch,
              )
              .toList(growable: false);
    final reviewCount = _int(map['reviewCount']);

    return Business(
      id: id,
      name: name,
      tagline: _string(map['tagline']),
      shortDescription: _string(map['shortDescription']),
      description: _string(map['description']),
      category: _enumFromName(
        DealCategory.values,
        _string(map['category'], DealCategory.food.name),
        DealCategory.food,
      ),
      city: city,
      district: district,
      rating: reviewCount > 0 ? _double(map['rating']) : 0,
      reviewCount: reviewCount,
      followerCount: _int(map['followerCount']),
      priceLevel: _string(map['priceLevel'], '€€'),
      tags: _stringList(map['tags']),
      coverPalette: _intList(
        map['coverPalette'],
        fallback: const <int>[0xFFDB2149, 0xFFF06B84],
      ),
      galleryLabels: _stringList(map['galleryLabels']),
      branches: branches,
      phone: _string(map['phone']),
      website: _string(map['website']),
      distanceKm: _double(map['distanceKm']),
      isTrending: _bool(map['isTrending']),
      isNew: _bool(map['isNew']),
      analytics: businessAnalyticsFromMap(_map(map['analytics'])),
      contactEmail: _string(map['contactEmail']),
      legalEntityName: _string(map['legalEntityName']),
      imprintInfo: _string(map['imprintInfo']),
      verificationStatus: _enumFromName(
        BusinessVerificationStatus.values,
        _string(
          map['verificationStatus'],
          BusinessVerificationStatus.draft.name,
        ),
        BusinessVerificationStatus.draft,
      ),
      verificationMethod: _enumFromName(
        BusinessVerificationMethod.values,
        _string(
          map['verificationMethod'],
          BusinessVerificationMethod.emailDomain.name,
        ),
        BusinessVerificationMethod.emailDomain,
      ),
      verificationRequestedAt: map['verificationRequestedAt'] == null
          ? null
          : _date(map['verificationRequestedAt'], fallback: DateTime.now()),
      ownershipConfirmed: _bool(map['ownershipConfirmed']),
      verificationPlaceId: _string(map['verificationPlaceId']),
      verificationWebsite: _string(map['verificationWebsite']),
      claimedByName: _string(map['claimedByName']),
      claimedByRole: _string(map['claimedByRole']),
      verificationNote: _string(map['verificationNote']),
      imageUrl: _string(map['imageUrl']),
      googleProfileLink: businessGoogleProfileLinkFromMap(
        _map(map['googleProfileLink']),
      ),
    );
  }

  static Map<String, dynamic> businessToMap(Business business) {
    return <String, dynamic>{
      'name': business.name,
      'tagline': business.tagline,
      'shortDescription': business.shortDescription,
      'description': business.description,
      'category': business.category.name,
      'city': business.city,
      'district': business.district,
      'rating': business.rating,
      'reviewCount': business.reviewCount,
      'followerCount': business.followerCount,
      'priceLevel': business.priceLevel,
      'tags': business.tags,
      'coverPalette': business.coverPalette,
      'galleryLabels': business.galleryLabels,
      'branches': business.branches.map(branchToMap).toList(),
      'phone': business.phone,
      'website': business.website,
      'distanceKm': business.distanceKm,
      'isTrending': business.isTrending,
      'isNew': business.isNew,
      'analytics': businessAnalyticsToMap(business.analytics),
      'contactEmail': business.contactEmail,
      'legalEntityName': business.legalEntityName,
      'imprintInfo': business.imprintInfo,
      'verificationStatus': business.verificationStatus.name,
      'verificationMethod': business.verificationMethod.name,
      'verificationRequestedAt': business.verificationRequestedAt == null
          ? null
          : Timestamp.fromDate(business.verificationRequestedAt!),
      'ownershipConfirmed': business.ownershipConfirmed,
      'verificationPlaceId': business.verificationPlaceId,
      'verificationWebsite': business.verificationWebsite,
      'claimedByName': business.claimedByName,
      'claimedByRole': business.claimedByRole,
      'verificationNote': business.verificationNote,
      'imageUrl': business.imageUrl,
      'googleProfileLink': businessGoogleProfileLinkToMap(
        business.googleProfileLink,
      ),
    };
  }

  static BusinessGoogleProfileLink businessGoogleProfileLinkFromMap(
    Map<String, dynamic> map,
  ) {
    return BusinessGoogleProfileLink(
      googleUserEmail: _string(map['googleUserEmail']),
      accountName: _string(map['accountName']),
      accountDisplayName: _string(map['accountDisplayName']),
      verificationSessionId: _string(map['verificationSessionId']),
      placeId: _string(map['placeId']),
      locationName: _string(map['locationName']),
      locationDisplayName: _string(map['locationDisplayName']),
      locationAddress: _string(map['locationAddress']),
      locationCity: _string(map['locationCity']),
      website: _string(map['website']),
      phone: _string(map['phone']),
      role: _string(map['role']),
    );
  }

  static Map<String, dynamic> businessGoogleProfileLinkToMap(
    BusinessGoogleProfileLink link,
  ) {
    return <String, dynamic>{
      'googleUserEmail': link.googleUserEmail,
      'accountName': link.accountName,
      'accountDisplayName': link.accountDisplayName,
      'verificationSessionId': link.verificationSessionId,
      'placeId': link.placeId,
      'locationName': link.locationName,
      'locationDisplayName': link.locationDisplayName,
      'locationAddress': link.locationAddress,
      'locationCity': link.locationCity,
      'website': link.website,
      'phone': link.phone,
      'role': link.role,
    };
  }

  static Branch branchFromMap(Map<String, dynamic> map) {
    return Branch(
      id: _string(map['id']),
      name: _string(map['name']),
      city: _string(map['city']),
      district: _string(map['district']),
      address: _string(map['address']),
      latitude: _double(map['latitude']),
      longitude: _double(map['longitude']),
      hours: _list(map['hours'])
          .map((entry) => businessHoursFromMap(_map(entry)))
          .toList(growable: false),
    );
  }

  static Map<String, dynamic> branchToMap(Branch branch) {
    return <String, dynamic>{
      'id': branch.id,
      'name': branch.name,
      'city': branch.city,
      'district': branch.district,
      'address': branch.address,
      'latitude': branch.latitude,
      'longitude': branch.longitude,
      'hours': branch.hours.map(businessHoursToMap).toList(),
    };
  }

  static BusinessHours businessHoursFromMap(Map<String, dynamic> map) {
    return BusinessHours(
      day: _string(map['day']),
      opensAt: _string(map['opensAt'], '09:00'),
      closesAt: _string(map['closesAt'], '18:00'),
      isClosed: _bool(map['isClosed']),
    );
  }

  static Map<String, dynamic> businessHoursToMap(BusinessHours hours) {
    return <String, dynamic>{
      'day': hours.day,
      'opensAt': hours.opensAt,
      'closesAt': hours.closesAt,
      'isClosed': hours.isClosed,
    };
  }

  static BusinessAnalytics businessAnalyticsFromMap(Map<String, dynamic> map) {
    return BusinessAnalytics(
      views: _int(map['views']),
      saves: _int(map['saves']),
      activations: _int(map['activations']),
      redemptions: _int(map['redemptions']),
      reach: _int(map['reach']),
      trendPoints: _intList(map['trendPoints']),
    );
  }

  static Map<String, dynamic> businessAnalyticsToMap(
    BusinessAnalytics analytics,
  ) {
    return <String, dynamic>{
      'views': analytics.views,
      'saves': analytics.saves,
      'activations': analytics.activations,
      'redemptions': analytics.redemptions,
      'reach': analytics.reach,
      'trendPoints': analytics.trendPoints,
    };
  }

  static DealRecord dealRecordFromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    final reviewCount = _int(map['reviewCount']);
    final stats = dealStatsFromMap(_map(map['stats']));
    final deal = Deal(
      id: id,
      businessId: _string(map['businessId']),
      title: _string(map['title']),
      subtitle: _string(map['subtitle']),
      description: _string(map['description']),
      city: _string(map['city'], 'Deutschlandweit'),
      district: _string(map['district'], 'Dein Viertel'),
      category: _enumFromName(
        DealCategory.values,
        _string(map['category'], DealCategory.food.name),
        DealCategory.food,
      ),
      type: _enumFromName(
        DealType.values,
        _string(map['type'], DealType.percentage.name),
        DealType.percentage,
      ),
      tags: _enumList(OfferTag.values, _list(map['tags'])),
      distanceKm: _double(map['distanceKm']),
      reviewCount: reviewCount,
      stats: reviewCount > 0 ? stats : stats.copyWith(rating: 0),
      validUntil: _date(
        map['validUntil'],
        fallback: DateTime.now().add(const Duration(days: 7)),
      ),
      originalPrice: _double(map['originalPrice']),
      discountedPrice: _double(map['discountedPrice']),
      savingsPercent: _int(map['savingsPercent']),
      priceHint: _string(map['priceHint']),
      redemptionCode: _string(map['redemptionCode']),
      highlights: _stringList(map['highlights']),
      conditions: _stringList(map['conditions']),
      galleryLabels: _stringList(map['galleryLabels']),
      palette: _intList(
        map['palette'],
        fallback: const <int>[0xFFDB2149, 0xFFF06B84],
      ),
      socialProof: _string(map['socialProof']),
      availabilityLabel: _string(map['availabilityLabel']),
      ctaLabel: _string(map['ctaLabel'], 'Gutschein aktivieren'),
      validDays: _stringList(map['validDays']),
      openNow: _bool(map['openNow']),
      source: _enumFromName(
        DealSource.values,
        _string(map['source'], DealSource.native.name),
        DealSource.native,
      ),
      sourceLabel: _string(map['sourceLabel']),
      sourceUrl: _string(map['sourceUrl']),
      imageUrl: _string(map['imageUrl']),
    );

    return DealRecord(deal: deal, isPaused: _bool(map['isPaused']));
  }

  static Map<String, dynamic> dealToMap(Deal deal, {bool isPaused = false}) {
    return <String, dynamic>{
      'businessId': deal.businessId,
      'title': deal.title,
      'subtitle': deal.subtitle,
      'description': deal.description,
      'city': deal.city,
      'district': deal.district,
      'category': deal.category.name,
      'type': deal.type.name,
      'tags': deal.tags.map((e) => e.name).toList(),
      'distanceKm': deal.distanceKm,
      'reviewCount': deal.reviewCount,
      'stats': deal.stats.toJson(),
      'validUntil': Timestamp.fromDate(deal.validUntil),
      'originalPrice': deal.originalPrice,
      'discountedPrice': deal.discountedPrice,
      'savingsPercent': deal.savingsPercent,
      'priceHint': deal.priceHint,
      'redemptionCode': deal.redemptionCode,
      'highlights': deal.highlights,
      'conditions': deal.conditions,
      'galleryLabels': deal.galleryLabels,
      'palette': deal.palette,
      'socialProof': deal.socialProof,
      'availabilityLabel': deal.availabilityLabel,
      'ctaLabel': deal.ctaLabel,
      'validDays': deal.validDays,
      'openNow': deal.openNow,
      'source': deal.source.name,
      'sourceLabel': deal.sourceLabel,
      'sourceUrl': deal.sourceUrl,
      'imageUrl': deal.imageUrl,
      'isPaused': isPaused,
    };
  }

  static DealStats dealStatsFromMap(Map<String, dynamic> map) {
    return DealStats(
      views: _int(map['views']),
      saves: _int(map['saves']),
      activations: _int(map['activations']),
      redemptions: _int(map['redemptions']),
      rating: _double(map['rating']),
      friendCount: _int(map['friendCount']),
      todayRedemptions: _int(map['todayRedemptions']),
    );
  }

  static bool _looksLikePlaceholderHours(List<BusinessHours> hours) {
    if (hours.isEmpty) {
      return false;
    }

    final normalized = hours
        .map(
          (entry) =>
              '${entry.day}|${entry.opensAt}|${entry.closesAt}|${entry.isClosed}',
        )
        .join(',');

    return normalized ==
            'Mo|09:00|18:00|false,Di|09:00|18:00|false,Mi|09:00|18:00|false,Do|09:00|18:00|false,Fr|09:00|18:00|false,Sa|10:00|16:00|false,So|10:00|14:00|true' ||
        normalized == 'Mo-So|09:00|18:00|false';
  }

  static Story storyFromMap(Map<String, dynamic> map, {required String id}) {
    return Story(
      id: id,
      businessId: _string(map['businessId']),
      businessName: _string(map['businessName']),
      city: _string(map['city'], 'Deutschlandweit'),
      label: _string(map['label']),
      previewPalette: _intList(
        map['previewPalette'],
        fallback: const <int>[0xFFDB2149, 0xFFF06B84],
      ),
      items: _list(
        map['items'],
      ).map((entry) => storyItemFromMap(_map(entry))).toList(growable: false),
      timeLabel: _string(
        map['timeLabel'],
        _relativeLabel(_date(map['createdAt'], fallback: DateTime.now())),
      ),
    );
  }

  static Map<String, dynamic> storyToMap(Story story) {
    return <String, dynamic>{
      'businessId': story.businessId,
      'businessName': story.businessName,
      'city': story.city,
      'label': story.label,
      'previewPalette': story.previewPalette,
      'items': story.items.map(storyItemToMap).toList(),
      'timeLabel': story.timeLabel,
    };
  }

  static StoryItem storyItemFromMap(Map<String, dynamic> map) {
    return StoryItem(
      id: _string(map['id']),
      type: _enumFromName(
        StoryType.values,
        _string(map['type'], StoryType.deal.name),
        StoryType.deal,
      ),
      title: _string(map['title']),
      subtitle: _string(map['subtitle']),
      body: _string(map['body']),
      ctaLabel: _string(map['ctaLabel'], 'Zum Deal'),
      palette: _intList(
        map['palette'],
        fallback: const <int>[0xFFDB2149, 0xFFF06B84],
      ),
      duration: Duration(milliseconds: _int(map['durationMs'], 3200)),
      imageUrl: _string(map['imageUrl']),
      dealId: _nullableString(map['dealId']),
    );
  }

  static Map<String, dynamic> storyItemToMap(StoryItem item) {
    return <String, dynamic>{
      'id': item.id,
      'type': item.type.name,
      'title': item.title,
      'subtitle': item.subtitle,
      'body': item.body,
      'ctaLabel': item.ctaLabel,
      'palette': item.palette,
      'durationMs': item.duration.inMilliseconds,
      'imageUrl': item.imageUrl,
      'dealId': item.dealId,
    };
  }

  static NotificationItem notificationFromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    final createdAt = _date(map['createdAt'], fallback: DateTime.now());
    return NotificationItem(
      id: id,
      title: _string(map['title']),
      body: _string(map['body']),
      timeLabel: _string(map['timeLabel'], _relativeLabel(createdAt)),
      type: _enumFromName(
        NotificationType.values,
        _string(map['type'], NotificationType.trending.name),
        NotificationType.trending,
      ),
      isRead: _bool(map['isRead']),
      dealId: _nullableString(map['dealId']),
      businessId: _nullableString(map['businessId']),
    );
  }

  static Map<String, dynamic> notificationToMap(NotificationItem item) {
    return <String, dynamic>{
      'title': item.title,
      'body': item.body,
      'timeLabel': item.timeLabel,
      'type': item.type.name,
      'isRead': item.isRead,
      'dealId': item.dealId,
      'businessId': item.businessId,
    };
  }

  static Redemption redemptionFromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    return Redemption(
      id: id,
      dealId: _string(map['dealId']),
      code: _string(map['code']),
      couponId: _string(map['couponId']),
      qrPayload: _string(map['qrPayload']),
      activatedAt: _date(map['activatedAt'], fallback: DateTime.now()),
      expiresAt: _date(
        map['expiresAt'],
        fallback: DateTime.now().add(const Duration(days: 7)),
      ),
      status: _enumFromName(
        RedemptionStatus.values,
        _string(map['status'], RedemptionStatus.active.name),
        RedemptionStatus.active,
      ),
      offlineReady: _bool(map['offlineReady'], true),
      instructions: _string(map['instructions']),
      savedAmountCents: _int(map['savedAmountCents']),
      usedAt: map['usedAt'] == null
          ? null
          : _date(map['usedAt'], fallback: DateTime.now()),
    );
  }

  static Map<String, dynamic> redemptionToMap(Redemption redemption) {
    return <String, dynamic>{
      'dealId': redemption.dealId,
      'code': redemption.code,
      'couponId': redemption.couponId,
      'qrPayload': redemption.qrPayload,
      'activatedAt': Timestamp.fromDate(redemption.activatedAt),
      'expiresAt': Timestamp.fromDate(redemption.expiresAt),
      'status': redemption.status.name,
      'offlineReady': redemption.offlineReady,
      'instructions': redemption.instructions,
      'savedAmountCents': redemption.savedAmountCents,
      'usedAt': redemption.usedAt == null
          ? null
          : Timestamp.fromDate(redemption.usedAt!),
    };
  }

  static AppReview reviewFromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    final createdAt = _nullableDate(map['createdAt']);
    final updatedAt = _nullableDate(map['updatedAt']);
    final labelDate = updatedAt ?? createdAt ?? DateTime.now();
    return AppReview(
      id: id,
      authorName: _string(map['authorName']),
      authorInitials: _string(map['authorInitials']),
      authorId: _string(map['authorId']),
      rating: _int(map['rating'], 5),
      comment: _string(map['comment']),
      timeLabel: _string(map['timeLabel'], _relativeLabel(labelDate)),
      helpfulCount: _int(map['helpfulCount']),
      city: _string(map['city'], 'Deutschlandweit'),
      createdAt: createdAt,
      updatedAt: updatedAt,
      dealId: _nullableString(map['dealId']),
      businessId: _nullableString(map['businessId']),
    );
  }

  static Map<String, dynamic> reviewToMap(AppReview review) {
    return <String, dynamic>{
      'authorName': review.authorName,
      'authorInitials': review.authorInitials,
      'authorId': review.authorId,
      'rating': review.rating,
      'comment': review.comment,
      'timeLabel': review.timeLabel,
      'helpfulCount': review.helpfulCount,
      'city': review.city,
      'dealId': review.dealId,
      'businessId': review.businessId,
    };
  }

  static String initials(String value) => _initials(value);

  static String relativeLabel(DateTime value) => _relativeLabel(value);

  static DateTime toDateTime(dynamic value, {DateTime? fallback}) =>
      _date(value, fallback: fallback ?? DateTime.now());

  static List<String> toStringList(dynamic value) => _stringList(value);
}

String _defaultInviteCode(String id) {
  final seed = id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  final head = seed.length >= 5 ? seed.substring(0, 5) : seed.padRight(5, 'X');
  return 'SP-$head';
}

String _initials(String value) {
  final parts = value
      .split(' ')
      .where((entry) => entry.trim().isNotEmpty)
      .take(2)
      .toList(growable: false);
  if (parts.isEmpty) {
    return 'SP';
  }
  return parts.map((entry) => entry.substring(0, 1)).join().toUpperCase();
}

String _relativeLabel(DateTime value) {
  final delta = DateTime.now().difference(value);
  if (delta.inMinutes < 1) {
    return 'Jetzt';
  }
  if (delta.inMinutes < 60) {
    return 'vor ${delta.inMinutes} min';
  }
  if (delta.inHours < 24) {
    return 'vor ${delta.inHours} h';
  }
  if (delta.inDays == 1) {
    return 'Gestern';
  }
  return 'vor ${delta.inDays} Tagen';
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, entry) => MapEntry(key.toString(), entry));
  }
  return const <String, dynamic>{};
}

List<dynamic> _list(dynamic value) {
  if (value is List) {
    return value;
  }
  return const <dynamic>[];
}

String _string(dynamic value, [String fallback = '']) {
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  return fallback;
}

String _languageCode(dynamic value) {
  final normalized = _string(value, 'de').trim().toLowerCase();
  return normalized == 'en' ? 'en' : 'de';
}

String? _nullableString(dynamic value) {
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  return null;
}

bool _bool(dynamic value, [bool fallback = false]) {
  if (value is bool) {
    return value;
  }
  return fallback;
}

int _int(dynamic value, [int fallback = 0]) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return fallback;
}

double _double(dynamic value, [double fallback = 0]) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  return fallback;
}

double? _nullableDouble(dynamic value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  return null;
}

DateTime _date(dynamic value, {required DateTime fallback}) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value) ?? fallback;
  }
  return fallback;
}

DateTime? _nullableDate(dynamic value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}

List<String> _stringList(dynamic value) {
  return _list(value)
      .map((entry) => entry?.toString() ?? '')
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}

List<int> _intList(dynamic value, {List<int> fallback = const <int>[]}) {
  final items = _list(value)
      .map((entry) => entry is num ? entry.toInt() : null)
      .whereType<int>()
      .toList(growable: false);
  return items.isEmpty ? fallback : items;
}

List<T> _enumList<T extends Enum>(List<T> values, List<dynamic> raw) {
  return raw
      .map(
        (entry) => _enumFromName(values, entry?.toString() ?? '', values.first),
      )
      .toList(growable: false);
}

T _enumFromName<T extends Enum>(List<T> values, String raw, T fallback) {
  for (final value in values) {
    if (value.name == raw) {
      return value;
    }
  }
  return fallback;
}
