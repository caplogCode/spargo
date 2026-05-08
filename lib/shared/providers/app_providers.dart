import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/services/app_location_service.dart';
import '../../core/services/device_session_service.dart';
import '../../core/services/location_label_resolver.dart';
import '../../data/firebase/firebase_mappers.dart';
import '../../data/repositories/firebase_app_repository.dart';
import '../../data/services/google_business_profile_service.dart';
import '../../data/services/google_maps_places_service.dart';
import '../../data/services/public_coupon_scanner_service.dart';
import '../../data/services/firebase_paths.dart';
import '../../domain/models/business_models.dart';
import '../../domain/models/deal_models.dart';
import '../../domain/models/engagement_models.dart';
import '../../domain/models/feed_models.dart';
import '../../domain/models/nearby_place_models.dart';
import '../../domain/models/notification_models.dart';
import '../../domain/models/story_models.dart';
import '../../domain/models/user_models.dart';
import 'firebase_providers.dart';

const double minSearchRadiusKm = 5.0;
const double maxSearchRadiusKm = 100.0;

double normalizeSearchRadiusKm(double value) {
  return value.clamp(minSearchRadiusKm, maxSearchRadiusKm).toDouble();
}

bool _isPermissionDeniedError(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('permission-denied') ||
      message.contains('missing or insufficient permissions');
}

DateTime? _readTimestamp(dynamic value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  return null;
}

int _stableStringHash(String value) {
  var hash = 2166136261;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 16777619) & 0x7fffffff;
  }
  return hash;
}

String _publicCouponScanJobId(String userId, String requestKey) {
  return 'scan_${userId}_${_stableStringHash(requestKey).toRadixString(16)}';
}

String _publicCouponGeoBucketKeyForArea(NearbySearchArea area) {
  return 'geo|${area.latitude.toStringAsFixed(1)}|${area.longitude.toStringAsFixed(1)}';
}

String _publicCouponRadiusBucketKey(double radiusKm) {
  final normalizedRadius = normalizeSearchRadiusKm(radiusKm);
  final roundedStep = (normalizedRadius / 5).round() * 5;
  return 'r$roundedStep';
}

bool _isPublicCouponBusinessId(String businessId) =>
    businessId.startsWith('public_') ||
    businessId.startsWith('seed_') ||
    businessId.startsWith('pcbiz_') ||
    businessId.startsWith('pcbizapp_');

bool _isPublicCouponDealId(String dealId) =>
    dealId.startsWith('public_') ||
    dealId.startsWith('seed_') ||
    dealId.startsWith('pcdeal_') ||
    dealId.startsWith('pcdealapp_');

String _publicCouponCacheScopeKeyForArea(NearbySearchArea area) {
  final normalizedCity = _normalizeLocationLabel(area.city);
  if (normalizedCity.isNotEmpty && normalizedCity != 'deutschlandweit') {
    return 'city|$normalizedCity';
  }

  final normalizedDistrict = _normalizeLocationLabel(area.district);
  if (normalizedDistrict.isNotEmpty &&
      !_isGenericLocationLabel(area.district)) {
    return 'district|$normalizedDistrict';
  }

  return _publicCouponGeoBucketKeyForArea(area);
}

@immutable
class PublicCouponScanJobState {
  const PublicCouponScanJobState({
    required this.id,
    required this.requestKey,
    required this.status,
    required this.updatedAt,
    required this.completedAt,
    required this.error,
    required this.foundDealCount,
    required this.foundBusinessCount,
    required this.candidateCount,
    required this.processedCandidateCount,
    required this.progressMessage,
  });

  final String id;
  final String requestKey;
  final String status;
  final DateTime? updatedAt;
  final DateTime? completedAt;
  final String error;
  final int foundDealCount;
  final int foundBusinessCount;
  final int candidateCount;
  final int processedCandidateCount;
  final String progressMessage;

  bool get isQueued => status == 'queued';
  bool get isRunning => status == 'running';
  bool get isActive => isQueued || isRunning;
  bool get isStale {
    final referenceTime = updatedAt ?? completedAt;
    if (!isActive || referenceTime == null) {
      return false;
    }
    final maxAge = isQueued
        ? const Duration(seconds: 30)
        : const Duration(seconds: 45);
    return DateTime.now().difference(referenceTime) > maxAge;
  }

  bool get isEffectivelyActive => isActive && !isStale;
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';

  double get progressValue {
    if (candidateCount > 0) {
      return (processedCandidateCount / candidateCount)
          .clamp(0.0, 1.0)
          .toDouble();
    }
    if (isEffectivelyActive) {
      return 0.08;
    }
    return 0;
  }

  int get progressPercent =>
      ((progressValue * 100).round()).clamp(0, 100).toInt();
}

String _stripHtmlForUi(String value, {int maxLength = 240}) {
  final cleaned = _sanitizeUiCouponValue(value);
  if (cleaned.isEmpty) {
    return '';
  }
  return cleaned.length <= maxLength
      ? cleaned
      : '${cleaned.substring(0, maxLength - 3).trimRight()}...';
}

String _repairUiCouponText(String value) {
  return value
      .replaceAll('Ã¤', 'ä')
      .replaceAll('Ã¶', 'ö')
      .replaceAll('Ã¼', 'ü')
      .replaceAll('Ã„', 'Ä')
      .replaceAll('Ã–', 'Ö')
      .replaceAll('Ãœ', 'Ü')
      .replaceAll('ÃŸ', 'ß')
      .replaceAll('â€“', '–')
      .replaceAll('â€”', '—')
      .replaceAll('â€ž', '„')
      .replaceAll('â€œ', '“')
      .replaceAll('â€"', '”')
      .replaceAll('â€™', "'")
      .replaceAll('â€˜', "'")
      .replaceAll('Â ', ' ')
      .replaceAll('Â', '');
}

String _repairUiCouponTextSafe(String value) {
  var repaired = value;
  for (var attempt = 0; attempt < 2; attempt++) {
    final next = _repairMojibakeOnce(repaired);
    if (next == repaired) {
      break;
    }
    repaired = next;
  }
  return repaired
      .replaceAll('\u00fffd', '')
      .replaceAll('\u00C2 ', ' ')
      .replaceAll('\u00C2', '')
      .replaceAll('\u2019', "'")
      .replaceAll('\u2018', "'");
}

String _repairMojibakeOnce(String value) {
  if (!RegExp(r'[\u00c3\u00c2\u00e2]').hasMatch(value)) {
    return value;
  }
  try {
    return utf8.decode(latin1.encode(value), allowMalformed: true);
  } catch (_) {
    return value;
  }
}

String _truncateTechnicalCouponJunk(String value) {
  final lower = value.toLowerCase();
  final markers = <String>[
    '/*',
    'critical above-the-fold css',
    'font-family',
    'box-sizing',
    'body{',
    'html{',
    '@media',
    '::before',
    '::after',
    ':before',
    ':after',
    'display:flex',
    'display:grid',
    'line-height:',
    'margin:',
    'padding:',
    'viewport',
    'tap-highlight',
  ];

  var cutIndex = value.length;
  for (final marker in markers) {
    final index = lower.indexOf(marker);
    if (index >= 0 && index < cutIndex) {
      cutIndex = index;
    }
  }

  final truncated = cutIndex < value.length
      ? value.substring(0, cutIndex).trim()
      : value.trim();
  return truncated;
}

bool _looksLikeUiJunk(String value) {
  if (value.isEmpty) {
    return true;
  }
  final lower = value.toLowerCase();
  if (lower.contains('critical above-the-fold css') ||
      lower.contains('font-family') ||
      lower.contains('box-sizing') ||
      lower.contains('body{') ||
      lower.contains('html{') ||
      lower.contains('::before') ||
      lower.contains('::after') ||
      lower.contains('@media') ||
      lower.contains('cookie') ||
      lower.contains('datenschutz')) {
    return true;
  }
  final technicalSymbols = RegExp(r'[{}<>;=*]{3,}').hasMatch(value);
  final urlLike = RegExp(
    r'https?://|www\.',
    caseSensitive: false,
  ).hasMatch(value);
  return technicalSymbols || urlLike;
}

String _sanitizeUiCouponValue(String value) {
  var cleaned = _repairUiCouponTextSafe(value)
      .replaceAll(
        RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
        ' ',
      )
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll(RegExp(r'https?://\S+', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'www\.\S+', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  cleaned = _truncateTechnicalCouponJunk(
    cleaned,
  ).replaceAll(RegExp(r'\s+'), ' ').trim();

  if (_looksLikeUiJunk(cleaned)) {
    return '';
  }
  return cleaned;
}

Business _sanitizeBusinessForUi(Business business) {
  final safeWebsite = _repairUiCouponTextSafe(
    business.website,
  ).replaceAll(RegExp(r'\s+'), ' ').trim();
  final safePhone = _repairUiCouponTextSafe(
    business.phone,
  ).replaceAll(RegExp(r'\s+'), ' ').trim();
  final safeEmail = _repairUiCouponTextSafe(
    business.contactEmail,
  ).replaceAll(RegExp(r'\s+'), ' ').trim();
  final sourceBranches = business.branches.isEmpty
      ? <Branch>[business.primaryBranch]
      : business.branches;
  return business.copyWith(
    name: _stripHtmlForUi(business.name, maxLength: 60).isEmpty
        ? 'Laden'
        : _stripHtmlForUi(business.name, maxLength: 60),
    tagline: _stripHtmlForUi(business.tagline, maxLength: 72),
    shortDescription: _stripHtmlForUi(
      business.shortDescription,
      maxLength: 120,
    ),
    description: _stripHtmlForUi(business.description, maxLength: 220),
    city: _stripHtmlForUi(business.city, maxLength: 40),
    district: _stripHtmlForUi(business.district, maxLength: 40),
    priceLevel: _stripHtmlForUi(business.priceLevel, maxLength: 12),
    tags: business.tags
        .map((entry) => _stripHtmlForUi(entry, maxLength: 24))
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false),
    galleryLabels: business.galleryLabels
        .map((entry) => _stripHtmlForUi(entry, maxLength: 32))
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false),
    branches: sourceBranches
        .map(
          (branch) => branch.copyWith(
            name: _stripHtmlForUi(branch.name, maxLength: 60),
            city: _stripHtmlForUi(branch.city, maxLength: 40),
            district: _stripHtmlForUi(branch.district, maxLength: 40),
            address: _stripHtmlForUi(branch.address, maxLength: 120),
          ),
        )
        .toList(growable: false),
    phone: safePhone,
    website: safeWebsite,
    contactEmail: safeEmail,
    legalEntityName: _stripHtmlForUi(business.legalEntityName, maxLength: 80),
    imprintInfo: _stripHtmlForUi(business.imprintInfo, maxLength: 140),
    claimedByName: _stripHtmlForUi(business.claimedByName, maxLength: 60),
    claimedByRole: _stripHtmlForUi(business.claimedByRole, maxLength: 40),
    verificationNote: _stripHtmlForUi(
      business.verificationNote,
      maxLength: 120,
    ),
  );
}

Deal _sanitizeDealForUi(Deal deal) {
  final safeTitle = _stripHtmlForUi(deal.title, maxLength: 72);
  final safeSubtitle = _stripHtmlForUi(deal.subtitle, maxLength: 120);
  final safeDescription = _stripHtmlForUi(deal.description, maxLength: 240);
  return deal.copyWith(
    title: safeTitle.isEmpty
        ? (deal.isThirdParty ? 'Öffentlicher Gutschein' : deal.title)
        : safeTitle,
    subtitle: safeSubtitle.isEmpty
        ? (deal.isThirdParty ? 'Öffentlich verfügbar' : deal.subtitle)
        : safeSubtitle,
    description: safeDescription.isEmpty
        ? (deal.isThirdParty
              ? 'Öffentlich gefundenes Angebot in deiner Nähe.'
              : deal.description)
        : safeDescription,
    priceHint: _stripHtmlForUi(deal.priceHint, maxLength: 64),
    socialProof: _stripHtmlForUi(deal.socialProof, maxLength: 64),
    availabilityLabel: _stripHtmlForUi(deal.availabilityLabel, maxLength: 48),
    sourceLabel: _stripHtmlForUi(deal.sourceLabel, maxLength: 48),
    highlights: deal.highlights
        .map((entry) => _stripHtmlForUi(entry, maxLength: 80))
        .where((entry) => entry.isNotEmpty)
        .take(3)
        .toList(growable: false),
    conditions: deal.conditions
        .map((entry) => _stripHtmlForUi(entry, maxLength: 120))
        .where((entry) => entry.isNotEmpty)
        .take(3)
        .toList(growable: false),
  );
}

Deal _enrichDealStatsForUser(
  Deal deal,
  Set<String> savedDealIds,
  List<Redemption> wallet,
) {
  final savedByUser = savedDealIds.contains(deal.id);
  final activeCount = wallet
      .where(
        (entry) =>
            entry.dealId == deal.id && entry.status == RedemptionStatus.active,
      )
      .length;
  final redeemedCount = wallet
      .where(
        (entry) =>
            entry.dealId == deal.id &&
            entry.status == RedemptionStatus.redeemed,
      )
      .length;
  final redeemedToday = wallet
      .where(
        (entry) =>
            entry.dealId == deal.id &&
            entry.status == RedemptionStatus.redeemed &&
            entry.usedAt != null &&
            DateTime.now().difference(entry.usedAt!).inHours < 24,
      )
      .length;

  return deal.copyWith(
    stats: deal.stats.copyWith(
      saves: savedByUser && deal.stats.saves < 1 ? 1 : deal.stats.saves,
      activations: activeCount > deal.stats.activations
          ? activeCount
          : deal.stats.activations,
      redemptions: redeemedCount > deal.stats.redemptions
          ? redeemedCount
          : deal.stats.redemptions,
      todayRedemptions: redeemedToday > deal.stats.todayRedemptions
          ? redeemedToday
          : deal.stats.todayRedemptions,
    ),
  );
}

DealRecord _sanitizeDealRecordForUi(DealRecord record) {
  return DealRecord(
    deal: _sanitizeDealForUi(record.deal),
    isPaused: record.isPaused,
  );
}

bool _hasPublicCouponRequestKey(Map<String, dynamic> map) {
  final value = map['cacheRequestKey'];
  return value is String && value.trim().isNotEmpty;
}

DealRecord _applyLiveBusinessDistanceToDealRecord(
  DealRecord record, {
  required NearbySearchArea area,
  required Business? business,
}) {
  if (business == null) {
    return record;
  }
  final liveDistanceKm = _distanceBetweenKm(
    area.latitude,
    area.longitude,
    business.primaryBranch.latitude,
    business.primaryBranch.longitude,
  );
  return DealRecord(
    deal: record.deal.copyWith(distanceKm: liveDistanceKm),
    isPaused: record.isPaused,
  );
}

String _relativeTimeLabel(DateTime value) {
  final difference = DateTime.now().difference(value);
  if (difference.inSeconds < 45) {
    return 'gerade eben';
  }
  if (difference.inMinutes < 60) {
    return 'vor ${difference.inMinutes} Min.';
  }
  if (difference.inHours < 24) {
    return 'vor ${difference.inHours} Std.';
  }
  if (difference.inDays < 7) {
    return 'vor ${difference.inDays} Tagen';
  }
  final weeks = (difference.inDays / 7).floor();
  if (weeks < 5) {
    return 'vor $weeks Wochen';
  }
  final months = (difference.inDays / 30).floor();
  if (months < 12) {
    return 'vor $months Mon.';
  }
  final years = (difference.inDays / 365).floor();
  return years == 1 ? 'vor 1 Jahr' : 'vor $years Jahren';
}

String? _publicWebsiteImageFallback(String rawUrl) {
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !(uri.hasScheme && uri.host.isNotEmpty)) {
    return null;
  }
  return 'https://www.google.com/s2/favicons?sz=256&domain_url=${Uri.encodeComponent(uri.toString())}';
}

bool _isPublicCouponCacheAssetId(String value) {
  return value.startsWith('pcbiz_') || value.startsWith('pcdeal_');
}

class _PublicCouponCacheMeta {
  const _PublicCouponCacheMeta({this.dealCount = 0, this.lastUpdatedAt});

  final int dealCount;
  final DateTime? lastUpdatedAt;
}

@immutable
class _PinnedPublicCouponLookup {
  const _PinnedPublicCouponLookup({
    this.dealRecords = const <DealRecord>[],
    this.businesses = const <Business>[],
  });

  final List<DealRecord> dealRecords;
  final List<Business> businesses;
}

@immutable
class _StickyPublicCouponBusinesses {
  const _StickyPublicCouponBusinesses({
    this.requestKey,
    this.items = const <Business>[],
  });

  final String? requestKey;
  final List<Business> items;
}

@immutable
class _StickyPublicCouponDealRecords {
  const _StickyPublicCouponDealRecords({
    this.requestKey,
    this.items = const <DealRecord>[],
  });

  final String? requestKey;
  final List<DealRecord> items;
}

@immutable
class PublicCouponCacheStatus {
  const PublicCouponCacheStatus({
    required this.cacheBlocked,
    required this.cachedDealCount,
    required this.lastUpdatedAt,
    required this.nativeScanInProgress,
    required this.liveDealCount,
    required this.legacyFallbackActive,
    this.processedSourceCount = 0,
    this.sourceCount = 0,
    this.progressMessage = '',
  });

  final bool cacheBlocked;
  final int cachedDealCount;
  final DateTime? lastUpdatedAt;
  final bool nativeScanInProgress;
  final int liveDealCount;
  final bool legacyFallbackActive;
  final int processedSourceCount;
  final int sourceCount;
  final String progressMessage;

  int get visibleDealCount => liveDealCount;

  bool get hasVisibleCoupons => liveDealCount > 0;

  bool get hasCachedCoupons => cachedDealCount > 0;

  bool get hasMeasuredProgress => sourceCount > 0;

  double get syncProgress {
    if (hasMeasuredProgress) {
      return (processedSourceCount / sourceCount).clamp(0.0, 1.0).toDouble();
    }
    if (nativeScanInProgress) {
      return hasVisibleCoupons ? 0.18 : 0.10;
    }
    if (hasVisibleCoupons || hasCachedCoupons) {
      return 1;
    }
    return 0;
  }

  int get syncProgressPercent =>
      ((syncProgress * 100).round()).clamp(0, 100).toInt();

  String get syncLabel {
    if (cacheBlocked) {
      return 'Cache wird neu verbunden';
    }
    if (progressMessage.trim().isNotEmpty) {
      return progressMessage.trim();
    }
    if (nativeScanInProgress && sourceCount > 0) {
      return '$processedSourceCount von $sourceCount Quellen geprüft';
    }
    if (nativeScanInProgress) {
      return 'Scan läuft im Hintergrund';
    }
    if (hasVisibleCoupons) {
      return '$liveDealCount öffentliche Coupons im Radius sichtbar';
    }
    if (hasCachedCoupons) {
      return '$cachedDealCount öffentliche Coupons im Cache';
    }
    return 'Noch keine öffentlichen Coupons im Cache';
  }

  String get headline {
    if (cacheBlocked) {
      return 'Öffentliche Quellen neu verbinden';
    }
    if (nativeScanInProgress && !hasVisibleCoupons) {
      return 'Öffentliche Coupons werden gesammelt';
    }
    if (nativeScanInProgress && hasVisibleCoupons) {
      return '$liveDealCount öffentliche Coupons sichtbar';
    }
    if (hasVisibleCoupons) {
      return '$liveDealCount öffentliche Coupons gefunden';
    }
    if (hasCachedCoupons && lastUpdatedAt != null) {
      return 'Im aktuellen Radius noch nichts sichtbar';
    }
    if (hasCachedCoupons) {
      return 'Öffentliche Coupons liegen im Cache';
    }
    if (kIsWeb) {
      return 'Web wartet auf den öffentlichen Cache';
    }
    return 'Noch keine öffentlichen Coupons gefunden';
  }

  String get detail {
    if (cacheBlocked) {
      return 'Nach einem Neustart liest sparGO den öffentlichen Cache sauber neu ein.';
    }
    if (legacyFallbackActive && nativeScanInProgress) {
      return 'Bestehende Treffer bleiben kurz sichtbar, während sparGO für deinen aktuellen Ort und Radius frisch nachlädt.';
    }
    if (nativeScanInProgress && !hasVisibleCoupons) {
      return 'sparGO prüft gerade frei sichtbare Angebotsseiten in deiner Gegend und zieht passende Gutscheine in den Flow.';
    }
    if (nativeScanInProgress && hasVisibleCoupons) {
      return 'Weitere öffentliche Treffer werden nebenbei geprüft.';
    }
    if (hasVisibleCoupons) {
      return '$liveDealCount öffentliche Gutscheine aus frei sichtbaren Quellen sind gerade verfügbar.';
    }
    if (hasCachedCoupons) {
      return 'Es gibt bereits öffentliche Treffer im Cache, aber für deinen aktuellen Standort und Radius ist gerade nichts sichtbar.';
    }
    if (kIsWeb) {
      return 'Chrome darf fremde Seiten nicht direkt scannen. Sobald sparGO die öffentlichen Gutscheine nativ gesammelt und gecacht hat, erscheinen sie hier.';
    }
    return 'Sobald sparGO in deiner Umgebung frei sichtbare Aktionen findet, tauchen sie hier automatisch auf.';
  }
}

User _placeholderUser([firebase_auth.User? authUser]) {
  final email = authUser?.email;
  final seed = email == null ? 'Nutzer' : email.split('@').first;
  return User(
    id: authUser?.uid ?? '',
    accountType: AccountType.user,
    name: seed,
    handle: '@${seed.toLowerCase().replaceAll(' ', '')}',
    city: 'Deutschlandweit',
    district: 'Dein Viertel',
    latitude: null,
    longitude: null,
    avatarInitials: FirebaseMappers.initials(seed),
    favoriteCategories: const <DealCategory>[],
    savedDealIds: const <String>[],
    activeDealIds: const <String>[],
    followingBusinessIds: const <String>[],
    rewards: const <Reward>[],
    points: 0,
    freeCouponCredits: 0,
    inviteCode: 'SP-START',
    streakDays: 0,
    preferences: const UserPreferences(
      interests: <DealCategory>[],
      city: 'Deutschlandweit',
      radiusKm: 35,
      notificationsEnabled: true,
      socialProofEnabled: true,
      openNowOnly: false,
    ),
  );
}

SessionState _placeholderSessionState([firebase_auth.User? authUser]) {
  return SessionState(
    user: _placeholderUser(authUser),
    isAuthenticated: false,
    isGuest: false,
    userOnboardingComplete: false,
    hasLocationPermission: false,
    businessModeEnabled: false,
    businessOnboardingComplete: true,
    ownedBusinessId: '',
  );
}

final authUserProvider = Provider<firebase_auth.User?>((ref) {
  return ref.watch(firebaseAuthStateChangesProvider).valueOrNull ??
      ref.watch(firebaseAuthProvider).currentUser;
});

final deviceSessionProvider = FutureProvider<DeviceSessionInfo>((ref) async {
  return DeviceSessionService.instance.load();
});

final firebaseSessionUserRecordProvider = StreamProvider<SessionUserRecord?>((
  ref,
) {
  final authUser = ref.watch(authUserProvider);
  if (authUser == null) {
    return Stream.value(null);
  }

  return ref
      .watch(firebaseFirestoreProvider)
      .collection(FirestoreCollections.users)
      .doc(authUser.uid)
      .snapshots()
      .handleError((error, stackTrace) {
        if (_isPermissionDeniedError(error)) {
          debugPrint(
            'firebaseSessionUserRecordProvider permission denied: $error',
          );
          return;
        }
        throw error;
      })
      .map((snapshot) {
        final data = snapshot.data();
        if (!snapshot.exists || data == null) {
          return null;
        }
        return FirebaseMappers.sessionUserRecordFromMap(
          data,
          id: snapshot.id,
          fallbackEmail: authUser.email,
        );
      });
});

final firebaseOwnedBusinessFallbackIdProvider = FutureProvider<String?>((
  ref,
) async {
  final authUser = ref.watch(authUserProvider);
  if (authUser == null || authUser.isAnonymous) {
    return null;
  }

  final firestore = ref.watch(firebaseFirestoreProvider);

  try {
    final assignedSnapshot = await firestore
        .collection(FirestoreCollections.businesses)
        .where('assignedUserIds', arrayContains: authUser.uid)
        .limit(1)
        .get();
    if (assignedSnapshot.docs.isNotEmpty) {
      return assignedSnapshot.docs.first.id;
    }

    final ownedSnapshot = await firestore
        .collection(FirestoreCollections.businesses)
        .where('ownerId', isEqualTo: authUser.uid)
        .limit(1)
        .get();
    if (ownedSnapshot.docs.isNotEmpty) {
      return ownedSnapshot.docs.first.id;
    }
  } catch (error) {
    if (_isPermissionDeniedError(error)) {
      debugPrint(
        'firebaseOwnedBusinessFallbackIdProvider permission denied: $error',
      );
      return null;
    }
    rethrow;
  }

  return null;
});

final firebaseUsersProvider = StreamProvider<List<SessionUserRecord>>((ref) {
  final authUser = ref.watch(authUserProvider);
  if (authUser == null) {
    return Stream.value(const <SessionUserRecord>[]);
  }

  return ref
      .watch(firebaseFirestoreProvider)
      .collection(FirestoreCollections.users)
      .doc(authUser.uid)
      .snapshots()
      .handleError((error, stackTrace) {
        if (_isPermissionDeniedError(error)) {
          debugPrint('firebaseUsersProvider permission denied: $error');
          return;
        }
        throw error;
      })
      .map((snapshot) {
        final data = snapshot.data();
        if (!snapshot.exists || data == null) {
          return const <SessionUserRecord>[];
        }
        return <SessionUserRecord>[
          FirebaseMappers.sessionUserRecordFromMap(
            data,
            id: snapshot.id,
            fallbackEmail: authUser.email,
          ),
        ];
      });
});

final firebaseBusinessesProvider = StreamProvider<List<Business>>((ref) {
  return ref
      .watch(firebaseFirestoreProvider)
      .collection(FirestoreCollections.businesses)
      .snapshots()
      .handleError((error, stackTrace) {
        if (_isPermissionDeniedError(error)) {
          debugPrint('firebaseBusinessesProvider permission denied: $error');
          return;
        }
        throw error;
      })
      .map((snapshot) {
        final items = snapshot.docs
            .map(
              (doc) => FirebaseMappers.businessFromMap(doc.data(), id: doc.id),
            )
            .toList(growable: true);
        items.sort((a, b) => a.name.compareTo(b.name));
        return items;
      });
});

final firebaseBusinessByIdProvider = StreamProvider.family<Business?, String>((
  ref,
  id,
) {
  final normalizedId = id.trim();
  if (normalizedId.isEmpty) {
    return Stream.value(null);
  }

  return ref
      .watch(firebaseFirestoreProvider)
      .collection(FirestoreCollections.businesses)
      .doc(normalizedId)
      .snapshots()
      .handleError((error, stackTrace) {
        if (_isPermissionDeniedError(error)) {
          debugPrint('firebaseBusinessByIdProvider($normalizedId): $error');
          return;
        }
        throw error;
      })
      .map((snapshot) {
        final data = snapshot.data();
        if (!snapshot.exists || data == null) {
          return null;
        }
        return FirebaseMappers.businessFromMap(data, id: snapshot.id);
      });
});

final firebaseDealRecordsProvider = StreamProvider<List<DealRecord>>((ref) {
  return ref
      .watch(firebaseFirestoreProvider)
      .collection(FirestoreCollections.deals)
      .snapshots()
      .handleError((error, stackTrace) {
        if (_isPermissionDeniedError(error)) {
          debugPrint('firebaseDealRecordsProvider permission denied: $error');
          return;
        }
        throw error;
      })
      .map((snapshot) {
        final now = DateTime.now();
        final items = snapshot.docs
            .where((doc) {
              final data = doc.data();
              if (data['archived'] == true) {
                return false;
              }
              final validUntil = _readTimestamp(data['validUntil']);
              return validUntil == null || validUntil.isAfter(now);
            })
            .map(
              (doc) =>
                  FirebaseMappers.dealRecordFromMap(doc.data(), id: doc.id),
            )
            .toList(growable: true);
        items.sort((a, b) => a.deal.distanceKm.compareTo(b.deal.distanceKm));
        return items;
      });
});

final firebaseStoriesProvider = StreamProvider<List<Story>>((ref) {
  return ref
      .watch(firebaseFirestoreProvider)
      .collection(FirestoreCollections.stories)
      .snapshots()
      .handleError((error, stackTrace) {
        if (_isPermissionDeniedError(error)) {
          debugPrint('firebaseStoriesProvider permission denied: $error');
          return;
        }
        throw error;
      })
      .map((snapshot) {
        final now = DateTime.now();
        return snapshot.docs
            .where((doc) {
              final expiresAt = _readTimestamp(doc.data()['expiresAt']);
              return expiresAt == null || expiresAt.isAfter(now);
            })
            .map((doc) => FirebaseMappers.storyFromMap(doc.data(), id: doc.id))
            .toList(growable: false);
      });
});

final firebaseNotificationsProvider = StreamProvider<List<NotificationItem>>((
  ref,
) {
  final authUser = ref.watch(authUserProvider);
  if (authUser == null) {
    return Stream.value(const <NotificationItem>[]);
  }

  return ref
      .watch(firebaseFirestoreProvider)
      .collection(FirestoreCollections.notifications)
      .where('userId', isEqualTo: authUser.uid)
      .snapshots()
      .handleError((error, stackTrace) {
        if (_isPermissionDeniedError(error)) {
          debugPrint('firebaseNotificationsProvider permission denied: $error');
          return;
        }
        throw error;
      })
      .map((snapshot) {
        return snapshot.docs
            .map(
              (doc) =>
                  FirebaseMappers.notificationFromMap(doc.data(), id: doc.id),
            )
            .toList(growable: false);
      });
});

final firebaseRedemptionsProvider = StreamProvider<List<Redemption>>((ref) {
  final authUser = ref.watch(authUserProvider);
  if (authUser == null) {
    return Stream.value(const <Redemption>[]);
  }

  return ref
      .watch(firebaseFirestoreProvider)
      .collection(FirestoreCollections.redemptions)
      .where('userId', isEqualTo: authUser.uid)
      .snapshots()
      .handleError((error, stackTrace) {
        if (_isPermissionDeniedError(error)) {
          debugPrint('firebaseRedemptionsProvider permission denied: $error');
          return;
        }
        throw error;
      })
      .map((snapshot) {
        return snapshot.docs
            .map(
              (doc) =>
                  FirebaseMappers.redemptionFromMap(doc.data(), id: doc.id),
            )
            .toList(growable: false);
      });
});

final firebaseBusinessRedemptionsProvider =
    StreamProvider.family<List<Redemption>, String>((ref, businessId) {
      final authUser = ref.watch(authUserProvider);
      final session = ref.watch(sessionControllerProvider);
      if (authUser == null ||
          businessId.isEmpty ||
          session.user.accountType != AccountType.business) {
        return Stream.value(const <Redemption>[]);
      }

      return ref
          .watch(firebaseFirestoreProvider)
          .collection(FirestoreCollections.redemptions)
          .where('businessId', isEqualTo: businessId)
          .snapshots()
          .handleError((error, stackTrace) {
            if (_isPermissionDeniedError(error)) {
              debugPrint(
                'firebaseBusinessRedemptionsProvider permission denied: $error',
              );
              return;
            }
            throw error;
          })
          .map((snapshot) {
            return snapshot.docs
                .map(
                  (doc) =>
                      FirebaseMappers.redemptionFromMap(doc.data(), id: doc.id),
                )
                .toList(growable: false);
          });
    });

final firebaseReviewsProvider = StreamProvider<List<AppReview>>((ref) {
  return ref
      .watch(firebaseFirestoreProvider)
      .collection(FirestoreCollections.reviews)
      .snapshots()
      .handleError((error, stackTrace) {
        if (_isPermissionDeniedError(error)) {
          debugPrint('firebaseReviewsProvider permission denied: $error');
          return;
        }
        throw error;
      })
      .map((snapshot) {
        return snapshot.docs
            .map((doc) => FirebaseMappers.reviewFromMap(doc.data(), id: doc.id))
            .toList(growable: false);
      });
});

final _publicCouponCacheReadBlockedProvider = StateProvider<bool>((ref) {
  return false;
});

final _lastPublicCouponScanKeyProvider = StateProvider<String?>((ref) {
  return null;
});

final publicCouponCacheScopeKeyProvider = Provider<String>((ref) {
  final area = ref.watch(discoverSearchAreaProvider);
  return _publicCouponCacheScopeKeyForArea(area);
});

final publicCouponRequestKeyProvider = Provider<String>((ref) {
  final area = ref.watch(discoverSearchAreaProvider);
  final distanceKm = ref.watch(settingsControllerProvider).distanceKm;
  final scopeKey = ref.watch(publicCouponCacheScopeKeyProvider);
  return [
    scopeKey,
    _publicCouponGeoBucketKeyForArea(area),
    _publicCouponRadiusBucketKey(distanceKm),
  ].join('|');
});

final publicCouponScanJobIdProvider = Provider<String?>((ref) {
  final authUser = ref.watch(authUserProvider);
  if (authUser == null) {
    return null;
  }
  final requestKey = ref.watch(publicCouponRequestKeyProvider);
  return _publicCouponScanJobId(authUser.uid, requestKey);
});

final firebasePublicCouponScanJobProvider =
    StreamProvider<PublicCouponScanJobState?>((ref) {
      final blocked = ref.watch(_publicCouponCacheReadBlockedProvider);
      final jobId = ref.watch(publicCouponScanJobIdProvider);
      if (blocked || jobId == null || jobId.isEmpty) {
        return Stream.value(null);
      }

      return ref
          .watch(firebaseFirestoreProvider)
          .collection(FirestoreCollections.publicCouponScanJobs)
          .doc(jobId)
          .snapshots()
          .map((snapshot) {
            if (!snapshot.exists) {
              return null;
            }
            final data = snapshot.data();
            if (data == null) {
              return null;
            }
            return PublicCouponScanJobState(
              id: snapshot.id,
              requestKey: data['requestKey']?.toString() ?? '',
              status: data['status']?.toString() ?? '',
              updatedAt: _readTimestamp(data['updatedAt']),
              completedAt: _readTimestamp(data['completedAt']),
              error: data['error']?.toString() ?? '',
              foundDealCount: (data['foundDealCount'] as num?)?.toInt() ?? 0,
              foundBusinessCount:
                  (data['foundBusinessCount'] as num?)?.toInt() ?? 0,
              candidateCount: (data['candidateCount'] as num?)?.toInt() ?? 0,
              processedCandidateCount:
                  (data['processedCandidateCount'] as num?)?.toInt() ?? 0,
              progressMessage: data['progressMessage']?.toString() ?? '',
            );
          });
    });

final _firebasePublicCouponBusinessesRawProvider =
    StreamProvider<List<Business>>((ref) {
      final blocked = ref.watch(_publicCouponCacheReadBlockedProvider);
      if (blocked) {
        return Stream.value(const <Business>[]);
      }
      final scopeKey = ref.watch(publicCouponCacheScopeKeyProvider);

      final query = ref
          .watch(firebaseFirestoreProvider)
          .collection(FirestoreCollections.publicCouponBusinesses)
          .where('cacheScopeKey', isEqualTo: scopeKey);

      return Stream<List<Business>>.multi((controller) {
        final subscription = query.snapshots().listen(
          (snapshot) {
            final now = DateTime.now();
            final items = snapshot.docs
                .where((doc) {
                  final data = doc.data();
                  if (data['cacheGeminiValidationState']?.toString() !=
                      'verified') {
                    return false;
                  }
                  final expiresAt = _readTimestamp(data['cacheExpiresAt']);
                  return expiresAt == null || expiresAt.isAfter(now);
                })
                .map(
                  (doc) =>
                      FirebaseMappers.businessFromMap(doc.data(), id: doc.id),
                )
                .toList(growable: true);
            controller.add(_dedupePublicCouponBusinesses(items));
          },
          onError: (Object error, StackTrace stackTrace) {
            if (_isPermissionDeniedError(error)) {
              ref.read(_publicCouponCacheReadBlockedProvider.notifier).state =
                  true;
              controller.add(const <Business>[]);
              return;
            }
            controller.addError(error, stackTrace);
          },
        );
        controller.onCancel = subscription.cancel;
      });
    });

final firebasePublicCouponBusinessesProvider = Provider<List<Business>>((ref) {
  final area = ref.watch(discoverSearchAreaProvider);
  final radiusKm = ref.watch(settingsControllerProvider).distanceKm;
  final rawBusinesses =
      ref.watch(_firebasePublicCouponBusinessesRawProvider).valueOrNull ??
      const <Business>[];
  return _dedupePublicCouponBusinesses(
    rawBusinesses
        .where(
          (business) => _isPublicCouponBusinessVisibleInArea(
            business,
            area: area,
            radiusKm: radiusKm,
          ),
        )
        .toList(growable: false),
  );
});

final _legacyPublicCouponBusinessesRawProvider = StreamProvider<List<Business>>(
  (ref) {
    final blocked = ref.watch(_publicCouponCacheReadBlockedProvider);
    if (blocked) {
      return Stream.value(const <Business>[]);
    }

    final query = ref
        .watch(firebaseFirestoreProvider)
        .collection(FirestoreCollections.publicCouponBusinesses)
        .where('cacheVisibility', isEqualTo: 'public');

    return Stream<List<Business>>.multi((controller) {
      final subscription = query.snapshots().listen(
        (snapshot) {
          final now = DateTime.now();
          final items = <Business>[];
          for (final doc in snapshot.docs) {
            final data = doc.data();
            if (data['cacheGeminiValidationState']?.toString() != 'verified') {
              continue;
            }
            final expiresAt = _readTimestamp(data['cacheExpiresAt']);
            if (expiresAt != null && expiresAt.isBefore(now)) {
              continue;
            }
            final business = FirebaseMappers.businessFromMap(data, id: doc.id);
            items.add(business);
          }
          controller.add(_dedupePublicCouponBusinesses(items));
        },
        onError: (Object error, StackTrace stackTrace) {
          if (_isPermissionDeniedError(error)) {
            ref.read(_publicCouponCacheReadBlockedProvider.notifier).state =
                true;
            controller.add(const <Business>[]);
            return;
          }
          controller.addError(error, stackTrace);
        },
      );
      controller.onCancel = subscription.cancel;
    });
  },
);

final _legacyPublicCouponBusinessesProvider = Provider<List<Business>>((ref) {
  final area = ref.watch(discoverSearchAreaProvider);
  final radiusKm = ref.watch(settingsControllerProvider).distanceKm;
  final rawBusinesses =
      ref.watch(_legacyPublicCouponBusinessesRawProvider).valueOrNull ??
      const <Business>[];
  return _dedupePublicCouponBusinesses(
    rawBusinesses
        .where(
          (business) => _isPublicCouponBusinessVisibleInArea(
            business,
            area: area,
            radiusKm: radiusKm,
          ),
        )
        .toList(growable: false),
  );
});

final firebasePublicCouponDealRecordsProvider =
    StreamProvider<List<DealRecord>>((ref) {
      final blocked = ref.watch(_publicCouponCacheReadBlockedProvider);
      if (blocked) {
        return Stream.value(const <DealRecord>[]);
      }
      final area = ref.watch(discoverSearchAreaProvider);
      final radiusKm = ref.watch(settingsControllerProvider).distanceKm;
      final scopeKey = ref.watch(publicCouponCacheScopeKeyProvider);
      final businessesById = {
        for (final business in <Business>[
          ...(ref
                  .watch(_firebasePublicCouponBusinessesRawProvider)
                  .valueOrNull ??
              const <Business>[]),
          ...(ref.watch(_legacyPublicCouponBusinessesRawProvider).valueOrNull ??
              const <Business>[]),
        ])
          business.id: business,
      };

      final query = ref
          .watch(firebaseFirestoreProvider)
          .collection(FirestoreCollections.publicCouponDeals)
          .where('cacheScopeKey', isEqualTo: scopeKey);

      return Stream<List<DealRecord>>.multi((controller) {
        final subscription = query.snapshots().listen(
          (snapshot) {
            final now = DateTime.now();
            final items = snapshot.docs
                .where((doc) {
                  final data = doc.data();
                  if (data['cacheGeminiValidationState']?.toString() !=
                      'verified') {
                    return false;
                  }
                  final expiresAt = _readTimestamp(data['cacheExpiresAt']);
                  return expiresAt == null || expiresAt.isAfter(now);
                })
                .map((doc) {
                  final sanitized = _sanitizeDealRecordForUi(
                    FirebaseMappers.dealRecordFromMap(doc.data(), id: doc.id),
                  );
                  return _applyLiveBusinessDistanceToDealRecord(
                    sanitized,
                    area: area,
                    business: businessesById[sanitized.deal.businessId],
                  );
                })
                .where(
                  (entry) => _isPublicCouponDealVisibleInArea(
                    entry.deal,
                    area: area,
                    radiusKm: radiusKm,
                  ),
                )
                .toList(growable: true);
            controller.add(_dedupePublicCouponDealRecords(items));
          },
          onError: (Object error, StackTrace stackTrace) {
            if (_isPermissionDeniedError(error)) {
              ref.read(_publicCouponCacheReadBlockedProvider.notifier).state =
                  true;
              controller.add(const <DealRecord>[]);
              return;
            }
            controller.addError(error, stackTrace);
          },
        );
        controller.onCancel = subscription.cancel;
      });
    });

final _legacyPublicCouponDealRecordsProvider = StreamProvider<List<DealRecord>>(
  (ref) {
    final blocked = ref.watch(_publicCouponCacheReadBlockedProvider);
    if (blocked) {
      return Stream.value(const <DealRecord>[]);
    }
    final area = ref.watch(discoverSearchAreaProvider);
    final radiusKm = ref.watch(settingsControllerProvider).distanceKm;
    final legacyBusinessesById = {
      for (final business
          in ref.watch(_legacyPublicCouponBusinessesRawProvider).valueOrNull ??
              const <Business>[])
        business.id: business,
    };

    final query = ref
        .watch(firebaseFirestoreProvider)
        .collection(FirestoreCollections.publicCouponDeals)
        .where('cacheVisibility', isEqualTo: 'public');

    return Stream<List<DealRecord>>.multi((controller) {
      final subscription = query.snapshots().listen(
        (snapshot) {
          final now = DateTime.now();
          final items = <DealRecord>[];
          for (final doc in snapshot.docs) {
            final data = doc.data();
            if (data['cacheGeminiValidationState']?.toString() != 'verified') {
              continue;
            }
            final expiresAt = _readTimestamp(data['cacheExpiresAt']);
            if (expiresAt != null && expiresAt.isBefore(now)) {
              continue;
            }
            final sanitizedRecord = _sanitizeDealRecordForUi(
              FirebaseMappers.dealRecordFromMap(data, id: doc.id),
            );
            final record = _applyLiveBusinessDistanceToDealRecord(
              sanitizedRecord,
              area: area,
              business: legacyBusinessesById[sanitizedRecord.deal.businessId],
            );
            if (!_isPublicCouponDealVisibleInArea(
              record.deal,
              area: area,
              radiusKm: radiusKm,
            )) {
              continue;
            }
            items.add(record);
          }
          controller.add(_dedupePublicCouponDealRecords(items));
        },
        onError: (Object error, StackTrace stackTrace) {
          if (_isPermissionDeniedError(error)) {
            ref.read(_publicCouponCacheReadBlockedProvider.notifier).state =
                true;
            controller.add(const <DealRecord>[]);
            return;
          }
          controller.addError(error, stackTrace);
        },
      );
      controller.onCancel = subscription.cancel;
    });
  },
);

final firebasePublicCouponCacheMetaProvider =
    StreamProvider<_PublicCouponCacheMeta>((ref) {
      final blocked = ref.watch(_publicCouponCacheReadBlockedProvider);
      if (blocked) {
        return Stream.value(const _PublicCouponCacheMeta());
      }
      final area = ref.watch(discoverSearchAreaProvider);
      final radiusKm = ref.watch(settingsControllerProvider).distanceKm;
      final businessesById = {
        for (final business in <Business>[
          ...(ref
                  .watch(_firebasePublicCouponBusinessesRawProvider)
                  .valueOrNull ??
              const <Business>[]),
          ...(ref.watch(_legacyPublicCouponBusinessesRawProvider).valueOrNull ??
              const <Business>[]),
        ])
          business.id: business,
      };

      final query = ref
          .watch(firebaseFirestoreProvider)
          .collection(FirestoreCollections.publicCouponDeals)
          .where('cacheVisibility', isEqualTo: 'public');

      return Stream<_PublicCouponCacheMeta>.multi((controller) {
        final subscription = query.snapshots().listen(
          (snapshot) {
            final now = DateTime.now();
            final visibleDealKeys = <String>{};
            DateTime? lastUpdatedAt;

            for (final doc in snapshot.docs) {
              final data = doc.data();
              if (data['cacheGeminiValidationState']?.toString() !=
                  'verified') {
                continue;
              }
              final expiresAt = _readTimestamp(data['cacheExpiresAt']);
              if (expiresAt != null && expiresAt.isBefore(now)) {
                continue;
              }
              final sanitized = _sanitizeDealRecordForUi(
                FirebaseMappers.dealRecordFromMap(data, id: doc.id),
              );
              final record = _applyLiveBusinessDistanceToDealRecord(
                sanitized,
                area: area,
                business: businessesById[sanitized.deal.businessId],
              );
              if (!_isPublicCouponDealVisibleInArea(
                record.deal,
                area: area,
                radiusKm: radiusKm,
              )) {
                continue;
              }
              visibleDealKeys.add(_publicDealIdentityKey(record.deal));
              final importedAt = _readTimestamp(data['cacheImportedAt']);
              if (importedAt != null &&
                  (lastUpdatedAt == null ||
                      importedAt.isAfter(lastUpdatedAt))) {
                lastUpdatedAt = importedAt;
              }
            }

            controller.add(
              _PublicCouponCacheMeta(
                dealCount: visibleDealKeys.length,
                lastUpdatedAt: lastUpdatedAt,
              ),
            );
          },
          onError: (Object error, StackTrace stackTrace) {
            if (_isPermissionDeniedError(error)) {
              ref.read(_publicCouponCacheReadBlockedProvider.notifier).state =
                  true;
              controller.add(const _PublicCouponCacheMeta());
              return;
            }
            controller.addError(error, stackTrace);
          },
        );
        controller.onCancel = subscription.cancel;
      });
    });

final publicCouponLegacyFallbackActiveProvider = Provider<bool>((ref) {
  final scopedItems = _dedupePublicCouponDealRecords(
    ref.watch(firebasePublicCouponDealRecordsProvider).valueOrNull ??
        const <DealRecord>[],
  );
  final legacyItems = _dedupePublicCouponDealRecords(
    ref.watch(_legacyPublicCouponDealRecordsProvider).valueOrNull ??
        const <DealRecord>[],
  );
  return scopedItems.isEmpty && legacyItems.isNotEmpty;
});

final _stickyPublicCouponBusinessesProvider =
    StateProvider<_StickyPublicCouponBusinesses>((ref) {
      return const _StickyPublicCouponBusinesses();
    });

final _stickyPublicCouponDealRecordsProvider =
    StateProvider<_StickyPublicCouponDealRecords>((ref) {
      return const _StickyPublicCouponDealRecords();
    });

final _syncStickyPublicCouponBusinessesProvider = Provider<void>((ref) {
  final requestKey = ref.watch(publicCouponRequestKeyProvider);
  ref.listen<List<Business>>(firebasePublicCouponBusinessesProvider, (
    previous,
    next,
  ) {
    final items = _dedupePublicCouponBusinesses(next);
    if (items.isNotEmpty) {
      ref.read(_stickyPublicCouponBusinessesProvider.notifier).state =
          _StickyPublicCouponBusinesses(requestKey: requestKey, items: items);
    }
  });
});

final _syncStickyPublicCouponDealRecordsProvider = Provider<void>((ref) {
  final requestKey = ref.watch(publicCouponRequestKeyProvider);
  ref.listen<AsyncValue<List<DealRecord>>>(
    firebasePublicCouponDealRecordsProvider,
    (previous, next) {
      final items = _dedupePublicCouponDealRecords(
        next.valueOrNull ?? const <DealRecord>[],
      );
      if (items.isNotEmpty) {
        ref
            .read(_stickyPublicCouponDealRecordsProvider.notifier)
            .state = _StickyPublicCouponDealRecords(
          requestKey: requestKey,
          items: items,
        );
      }
    },
  );
});

final publicCouponBusinessesProvider = Provider<List<Business>>((ref) {
  ref.watch(_syncStickyPublicCouponBusinessesProvider);
  final requestKey = ref.watch(publicCouponRequestKeyProvider);
  final scopedCurrent = _dedupePublicCouponBusinesses(
    ref.watch(firebasePublicCouponBusinessesProvider),
  );
  final legacyCurrent = _dedupePublicCouponBusinesses(
    ref.watch(_legacyPublicCouponBusinessesProvider),
  );
  final current = scopedCurrent.isNotEmpty ? scopedCurrent : legacyCurrent;
  if (current.isNotEmpty) {
    final sticky = ref.read(_stickyPublicCouponBusinessesProvider);
    if (sticky.requestKey != requestKey ||
        !_sameBusinessListById(sticky.items, current)) {
      Future<void>.microtask(() {
        ref
            .read(_stickyPublicCouponBusinessesProvider.notifier)
            .state = _StickyPublicCouponBusinesses(
          requestKey: requestKey,
          items: current,
        );
      });
    }
    return current;
  }
  final sticky = ref.watch(_stickyPublicCouponBusinessesProvider);
  final scanActive =
      ref
          .watch(firebasePublicCouponScanJobProvider)
          .valueOrNull
          ?.isEffectivelyActive ??
      false;
  final refreshPending = ref.watch(publicCouponRefreshControllerProvider);
  final cacheMeta =
      ref.watch(firebasePublicCouponCacheMetaProvider).valueOrNull ??
      const _PublicCouponCacheMeta();
  final shouldHoldSticky =
      sticky.items.isNotEmpty &&
      sticky.requestKey == requestKey &&
      (scanActive || refreshPending || cacheMeta.dealCount > 0);
  if (shouldHoldSticky) {
    return sticky.items;
  }
  return const <Business>[];
});

final publicCouponDealRecordsProvider = Provider<List<DealRecord>>((ref) {
  ref.watch(_syncStickyPublicCouponDealRecordsProvider);
  final requestKey = ref.watch(publicCouponRequestKeyProvider);
  final scopedCurrent = _dedupePublicCouponDealRecords(
    ref.watch(firebasePublicCouponDealRecordsProvider).valueOrNull ??
        const <DealRecord>[],
  );
  final legacyCurrent = _dedupePublicCouponDealRecords(
    ref.watch(_legacyPublicCouponDealRecordsProvider).valueOrNull ??
        const <DealRecord>[],
  );
  final current = scopedCurrent.isNotEmpty ? scopedCurrent : legacyCurrent;
  if (current.isNotEmpty) {
    final sticky = ref.read(_stickyPublicCouponDealRecordsProvider);
    if (sticky.requestKey != requestKey ||
        !_sameDealRecordListById(sticky.items, current)) {
      Future<void>.microtask(() {
        ref
            .read(_stickyPublicCouponDealRecordsProvider.notifier)
            .state = _StickyPublicCouponDealRecords(
          requestKey: requestKey,
          items: current,
        );
      });
    }
    return current;
  }
  final sticky = ref.watch(_stickyPublicCouponDealRecordsProvider);
  final scanActive =
      ref
          .watch(firebasePublicCouponScanJobProvider)
          .valueOrNull
          ?.isEffectivelyActive ??
      false;
  final refreshPending = ref.watch(publicCouponRefreshControllerProvider);
  final cacheMeta =
      ref.watch(firebasePublicCouponCacheMetaProvider).valueOrNull ??
      const _PublicCouponCacheMeta();
  final shouldHoldSticky =
      sticky.items.isNotEmpty &&
      sticky.requestKey == requestKey &&
      (scanActive || refreshPending || cacheMeta.dealCount > 0);
  if (shouldHoldSticky) {
    return sticky.items;
  }
  return const <DealRecord>[];
});

final repositoryProvider = Provider<FirebaseAppRepository>((ref) {
  return FirebaseAppRepository(
    auth: ref.watch(firebaseAuthProvider),
    firestore: ref.watch(firebaseFirestoreProvider),
    storage: ref.watch(firebaseStorageProvider),
    businesses:
        ref.watch(firebaseBusinessesProvider).valueOrNull ?? const <Business>[],
    dealRecords:
        ref.watch(firebaseDealRecordsProvider).valueOrNull ??
        const <DealRecord>[],
    stories: ref.watch(firebaseStoriesProvider).valueOrNull ?? const <Story>[],
    notifications:
        ref.watch(firebaseNotificationsProvider).valueOrNull ??
        const <NotificationItem>[],
    redemptions:
        ref.watch(firebaseRedemptionsProvider).valueOrNull ??
        const <Redemption>[],
    reviews:
        ref.watch(firebaseReviewsProvider).valueOrNull ?? const <AppReview>[],
    currentUser:
        ref.watch(firebaseSessionUserRecordProvider).valueOrNull?.user ??
        _placeholderUser(ref.watch(authUserProvider)),
  );
});

final googleBusinessProfileServiceProvider =
    Provider<GoogleBusinessProfileService>((ref) {
      final client = http.Client();
      ref.onDispose(client.close);
      return GoogleBusinessProfileService(client: client);
    });

final googleMapsPlacesServiceProvider = Provider<GoogleMapsPlacesService>((
  ref,
) {
  final client = http.Client();
  ref.onDispose(client.close);
  return GoogleMapsPlacesService(client: client);
});

final dealPresentationImageUrlProvider =
    FutureProvider.family<String?, ({String businessId, String dealId})>((
      ref,
      ids,
    ) async {
      final deal = ref.watch(dealByIdProvider(ids.dealId));
      final directDealImageUrl = deal.imageUrl.trim();
      if (directDealImageUrl.isNotEmpty) {
        return directDealImageUrl;
      }

      final business = ref.watch(businessByIdProvider(ids.businessId));
      final directBusinessImageUrl = business.imageUrl.trim();
      if (directBusinessImageUrl.isNotEmpty) {
        return directBusinessImageUrl;
      }

      final isPublicCouponCacheAsset =
          deal.isThirdParty ||
          _isPublicCouponCacheAssetId(ids.businessId) ||
          _isPublicCouponCacheAssetId(ids.dealId) ||
          _isPublicCouponCacheAssetId(deal.businessId);

      if (isPublicCouponCacheAsset) {
        return _publicWebsiteImageFallback(
          deal.sourceUrl.isNotEmpty ? deal.sourceUrl : business.website,
        );
      }

      final storage = ref.watch(firebaseStorageProvider);

      Future<String?> resolve(String path) async {
        try {
          final url = await storage.ref(path).getDownloadURL();
          final cleaned = url.trim();
          return cleaned.isEmpty ? null : cleaned;
        } catch (_) {
          return null;
        }
      }

      final dealUrl = await resolve(
        FirebaseStoragePaths.dealAsset(ids.businessId, ids.dealId),
      );
      if (dealUrl != null) {
        return dealUrl;
      }

      final businessCoverUrl = await resolve(
        FirebaseStoragePaths.businessCover(ids.businessId),
      );
      if (businessCoverUrl != null) {
        return businessCoverUrl;
      }

      final businessLogoUrl = await resolve(
        FirebaseStoragePaths.businessLogo(ids.businessId),
      );
      if (businessLogoUrl != null) {
        return businessLogoUrl;
      }

      return _publicWebsiteImageFallback(business.website);
    });

class SessionState {
  const SessionState({
    required this.user,
    required this.isAuthenticated,
    required this.isGuest,
    required this.userOnboardingComplete,
    required this.hasLocationPermission,
    required this.businessModeEnabled,
    required this.businessOnboardingComplete,
    required this.ownedBusinessId,
  });

  final User user;
  final bool isAuthenticated;
  final bool isGuest;
  final bool userOnboardingComplete;
  final bool hasLocationPermission;
  final bool businessModeEnabled;
  final bool businessOnboardingComplete;
  final String ownedBusinessId;

  bool get isBusinessAccount => user.accountType == AccountType.business;

  bool get needsBusinessSetup =>
      isBusinessAccount &&
      (!businessOnboardingComplete || ownedBusinessId.isEmpty);

  SessionState copyWith({
    User? user,
    bool? isAuthenticated,
    bool? isGuest,
    bool? userOnboardingComplete,
    bool? hasLocationPermission,
    bool? businessModeEnabled,
    bool? businessOnboardingComplete,
    String? ownedBusinessId,
  }) {
    return SessionState(
      user: user ?? this.user,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isGuest: isGuest ?? this.isGuest,
      userOnboardingComplete:
          userOnboardingComplete ?? this.userOnboardingComplete,
      hasLocationPermission:
          hasLocationPermission ?? this.hasLocationPermission,
      businessModeEnabled: businessModeEnabled ?? this.businessModeEnabled,
      businessOnboardingComplete:
          businessOnboardingComplete ?? this.businessOnboardingComplete,
      ownedBusinessId: ownedBusinessId ?? this.ownedBusinessId,
    );
  }
}

class SessionController extends StateNotifier<SessionState> {
  SessionController(this.ref)
    : super(_placeholderSessionState(ref.read(authUserProvider)));

  final Ref ref;
  bool _refreshingDeviceLocation = false;
  bool _handlingRemoteLogout = false;
  DateTime? _lastDeviceLocationRefreshStartedAt;
  int _asyncEpoch = 0;

  void syncFromBackend({
    required SessionUserRecord? record,
    required firebase_auth.User? authUser,
  }) {
    if (authUser == null) {
      _asyncEpoch += 1;
      state = _placeholderSessionState(authUser);
      return;
    }

    if (record == null) {
      final fallbackUser =
          (state.user.id.isNotEmpty ? state.user : _placeholderUser(authUser))
              .copyWith(id: authUser.uid);
      state = state.copyWith(
        user: fallbackUser,
        isAuthenticated: true,
        isGuest: authUser.isAnonymous,
        userOnboardingComplete: false,
        businessModeEnabled: fallbackUser.accountType == AccountType.business,
      );
      return;
    }

    final resolvedUser =
        record.ownedBusinessId.isNotEmpty &&
            record.user.accountType != AccountType.business
        ? record.user.copyWith(accountType: AccountType.business)
        : record.user;

    state = state.copyWith(
      user: resolvedUser,
      isAuthenticated: true,
      isGuest: authUser.isAnonymous,
      userOnboardingComplete: record.onboardingCompleted,
      hasLocationPermission: record.hasLocationPermission,
      businessModeEnabled: resolvedUser.accountType == AccountType.business,
      businessOnboardingComplete: record.businessOnboardingComplete,
      ownedBusinessId: record.ownedBusinessId,
    );

    final missingCoordinates =
        (record.user.latitude == null || record.user.longitude == null) &&
        record.user.city.trim().isNotEmpty &&
        record.user.city != 'Deutschlandweit';
    if (missingCoordinates) {
      _hydrateCoordinatesFromLocationLabel(
        city: record.user.city,
        district: record.user.district,
      );
    } else if (record.hasLocationPermission) {
      _refreshDeviceLocationSoon();
    }
  }

  void selectInterests(List<DealCategory> interests) {
    final normalizedInterests = interests.toList(growable: false);
    late final User updatedUser;
    try {
      updatedUser = state.user.copyWith(
        favoriteCategories: normalizedInterests,
        preferences: state.user.preferences.copyWith(
          interests: normalizedInterests,
        ),
      );
      state = state.copyWith(user: updatedUser);
    } catch (error, stackTrace) {
      debugPrint('selectInterests local update failed: $error');
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'spargo session',
          context: ErrorDescription('while selecting onboarding interests'),
        ),
      );
      return;
    }

    if (state.isAuthenticated && updatedUser.id.trim().isNotEmpty) {
      try {
        unawaited(
          ref
              .read(repositoryProvider)
              .updateUserInterests(
                user: updatedUser,
                interests: normalizedInterests,
              )
              .catchError((Object error, StackTrace stackTrace) {
                debugPrint('updateUserInterests failed: $error');
              }),
        );
      } catch (error) {
        debugPrint('updateUserInterests start failed: $error');
      }
    }
  }

  void syncPreferencesLocally({
    double? radiusKm,
    bool? notificationsEnabled,
    bool? openNowOnly,
  }) {
    final nextPreferences = state.user.preferences.copyWith(
      radiusKm: radiusKm,
      notificationsEnabled: notificationsEnabled,
      openNowOnly: openNowOnly,
    );
    if (nextPreferences.radiusKm == state.user.preferences.radiusKm &&
        nextPreferences.notificationsEnabled ==
            state.user.preferences.notificationsEnabled &&
        nextPreferences.socialProofEnabled ==
            state.user.preferences.socialProofEnabled &&
        nextPreferences.openNowOnly == state.user.preferences.openNowOnly &&
        nextPreferences.city == state.user.preferences.city &&
        listEquals(
          nextPreferences.interests,
          state.user.preferences.interests,
        )) {
      return;
    }
    state = state.copyWith(
      user: state.user.copyWith(preferences: nextPreferences),
    );
  }

  void grantLocation({
    String city = 'Deutschlandweit',
    String district = 'Dein Viertel',
    double? latitude,
    double? longitude,
    bool clearCoordinates = false,
  }) {
    final normalizedCity = city.trim().isEmpty
        ? 'Deutschlandweit'
        : city.trim();
    final normalizedDistrict = district.trim().isEmpty
        ? 'In deiner Nähe'
        : district.trim();
    final updatedUser = state.user.copyWith(
      city: normalizedCity,
      district: normalizedDistrict,
      latitude: clearCoordinates ? null : latitude ?? state.user.latitude,
      longitude: clearCoordinates ? null : longitude ?? state.user.longitude,
      preferences: state.user.preferences.copyWith(city: normalizedCity),
    );
    state = state.copyWith(user: updatedUser, hasLocationPermission: true);

    if (state.isAuthenticated) {
      ref
          .read(repositoryProvider)
          .updateLocation(
            user: updatedUser,
            city: normalizedCity,
            district: normalizedDistrict,
            latitude: updatedUser.latitude,
            longitude: updatedUser.longitude,
          );
    }

    final needsCoordinates =
        updatedUser.latitude == null &&
        updatedUser.longitude == null &&
        normalizedCity.isNotEmpty &&
        normalizedCity != 'Deutschlandweit';
    if (needsCoordinates) {
      unawaited(
        _hydrateCoordinatesFromLocationLabel(
          city: normalizedCity,
          district: normalizedDistrict,
        ),
      );
      return;
    }
    ref
        .read(publicCouponRefreshControllerProvider.notifier)
        .scheduleRefresh(force: true);
  }

  Future<void> refreshLocationFromDevice() async {
    if (_refreshingDeviceLocation || !state.hasLocationPermission) {
      return;
    }
    final lastStartedAt = _lastDeviceLocationRefreshStartedAt;
    if (lastStartedAt != null &&
        DateTime.now().difference(lastStartedAt) < const Duration(minutes: 2)) {
      return;
    }

    final epoch = _asyncEpoch;
    _refreshingDeviceLocation = true;
    _lastDeviceLocationRefreshStartedAt = DateTime.now();
    try {
      final position = await createAppLocationService()
          .requestCurrentLocation();
      if (epoch != _asyncEpoch || ref.read(authUserProvider) == null) {
        return;
      }
      final resolvedLocation = await resolveLocationLabel(
        latitude: position.latitude,
        longitude: position.longitude,
        businesses: ref.read(businessesProvider),
      );
      if (epoch != _asyncEpoch || ref.read(authUserProvider) == null) {
        return;
      }
      grantLocation(
        city: resolvedLocation.city,
        district: resolvedLocation.district,
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (error) {
      final message = error.toString().toLowerCase();
      if (message.contains('standortfreigabe wurde im browser abgelehnt') ||
          message.contains('permission denied')) {
        state = state.copyWith(hasLocationPermission: false);
        return;
      }
      debugPrint('refreshLocationFromDevice failed: $error');
    } finally {
      _refreshingDeviceLocation = false;
    }
  }

  void _refreshDeviceLocationSoon() {
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 250), () async {
        if (ref.read(authUserProvider) == null) {
          return;
        }
        await refreshLocationFromDevice();
      }),
    );
  }

  void markUserOnboardingComplete({
    required List<DealCategory> interests,
    required bool hasLocationPermission,
    required double radiusKm,
  }) {
    final updatedPreferences = state.user.preferences.copyWith(
      interests: interests,
      radiusKm: radiusKm,
    );
    state = state.copyWith(
      user: state.user.copyWith(
        favoriteCategories: interests,
        preferences: updatedPreferences,
      ),
      userOnboardingComplete: true,
      hasLocationPermission: hasLocationPermission,
    );
  }

  Future<void> _hydrateCoordinatesFromLocationLabel({
    required String city,
    required String district,
  }) async {
    final epoch = _asyncEpoch;
    try {
      final resolved = await resolveLocationCoordinates(
        city: city,
        district: district,
      );
      if (resolved == null) {
        return;
      }
      if (epoch != _asyncEpoch) {
        return;
      }
      if (state.user.city != city) {
        return;
      }

      final hydratedDistrict =
          district == 'Dein Viertel' ||
              district == 'In deiner Nähe' ||
              district == 'Deine Nähe'
          ? resolved.district
          : district;
      final hydratedUser = state.user.copyWith(
        city: resolved.city,
        district: hydratedDistrict,
        latitude: resolved.latitude,
        longitude: resolved.longitude,
        preferences: state.user.preferences.copyWith(city: resolved.city),
      );
      state = state.copyWith(user: hydratedUser, hasLocationPermission: true);

      if (state.isAuthenticated) {
        await ref
            .read(repositoryProvider)
            .updateLocation(
              user: hydratedUser,
              city: hydratedUser.city,
              district: hydratedUser.district,
              latitude: hydratedUser.latitude,
              longitude: hydratedUser.longitude,
            );
      }
      ref
          .read(publicCouponRefreshControllerProvider.notifier)
          .scheduleRefresh(force: true);
    } catch (error) {
      debugPrint('grantLocation geocoding failed: $error');
    }
  }

  Future<void> signOut() async {
    _asyncEpoch += 1;
    _refreshingDeviceLocation = false;
    String? deviceId;
    try {
      deviceId = (await ref.read(deviceSessionProvider.future)).id;
    } catch (_) {
      deviceId = null;
    }
    try {
      await ref.read(repositoryProvider).signOut(deviceId: deviceId);
    } catch (error) {
      debugPrint('signOut fallback after error: $error');
      try {
        await ref.read(firebaseAuthProvider).signOut();
      } catch (_) {}
    } finally {
      ref.read(publicCouponRefreshControllerProvider.notifier).reset();
      ref.read(_lastPublicCouponScanKeyProvider.notifier).state = null;
      ref.read(_publicCouponCacheReadBlockedProvider.notifier).state = false;
      ref.read(_stickyPublicCouponBusinessesProvider.notifier).state =
          const _StickyPublicCouponBusinesses();
      ref.read(_stickyPublicCouponDealRecordsProvider.notifier).state =
          const _StickyPublicCouponDealRecords();
      state = _placeholderSessionState(null);
    }
  }

  Future<DeviceLoginResult> login({
    required String email,
    required String password,
  }) async {
    final device = await ref.read(deviceSessionProvider.future);
    return ref
        .read(repositoryProvider)
        .signInWithEmail(email: email, password: password, device: device);
  }

  Future<DeviceLoginResult> loginWithGoogle() async {
    final device = await ref.read(deviceSessionProvider.future);
    return ref.read(repositoryProvider).signInWithGoogle(device: device);
  }

  Future<DeviceLoginResult> loginWithApple() async {
    final device = await ref.read(deviceSessionProvider.future);
    return ref.read(repositoryProvider).signInWithApple(device: device);
  }

  Future<void> register({
    required String email,
    required String password,
    required String name,
    required String handle,
    required String city,
    required AccountType accountType,
  }) async {
    final device = await ref.read(deviceSessionProvider.future);
    final draftUser = state.user.copyWith(
      name: name,
      handle: handle,
      city: city,
      accountType: accountType,
    );
    final hasLocationPermission = state.hasLocationPermission;

    await ref
        .read(repositoryProvider)
        .registerUser(
          email: email,
          password: password,
          name: name,
          handle: handle,
          city: city,
          accountType: accountType,
          device: device,
        );

    final authUser = ref.read(firebaseAuthProvider).currentUser;
    if (authUser == null) {
      return;
    }

    final persistedUser = draftUser.copyWith(id: authUser.uid);
    state = state.copyWith(
      user: persistedUser,
      isAuthenticated: true,
      isGuest: authUser.isAnonymous,
      userOnboardingComplete: false,
      businessModeEnabled: accountType == AccountType.business,
      businessOnboardingComplete: accountType != AccountType.business,
      ownedBusinessId: '',
    );
    if (persistedUser.favoriteCategories.isNotEmpty) {
      try {
        await ref
            .read(repositoryProvider)
            .updateUserInterests(
              user: persistedUser,
              interests: persistedUser.favoriteCategories,
            );
      } catch (error) {
        debugPrint('register updateUserInterests failed: $error');
      }
    }
    if (hasLocationPermission) {
      try {
        await ref
            .read(repositoryProvider)
            .updateLocation(
              user: persistedUser,
              city: persistedUser.city,
              district: persistedUser.district,
              latitude: persistedUser.latitude,
              longitude: persistedUser.longitude,
            );
      } catch (error) {
        debugPrint('register updateLocation failed: $error');
      }
    }
  }

  Future<void> handleRemoteSessionConflict({
    required SessionUserRecord? record,
    required firebase_auth.User? authUser,
    required DeviceSessionInfo? device,
  }) async {
    if (_handlingRemoteLogout ||
        authUser == null ||
        authUser.isAnonymous ||
        record == null ||
        device == null) {
      return;
    }

    final activeDeviceId = record.activeDeviceId.trim();
    if (activeDeviceId.isEmpty || activeDeviceId == device.id) {
      return;
    }

    _handlingRemoteLogout = true;
    try {
      await signOut();
    } finally {
      _handlingRemoteLogout = false;
    }
  }

  Future<void> toggleFollowBusiness(String businessId) async {
    final currentUser = state.user;
    final following = currentUser.followingBusinessIds.toSet();
    if (following.contains(businessId)) {
      following.remove(businessId);
    } else {
      following.add(businessId);
    }

    final updatedUser = state.user.copyWith(
      followingBusinessIds: following.toList(),
    );
    state = state.copyWith(user: updatedUser);

    if (state.isAuthenticated) {
      await ref
          .read(repositoryProvider)
          .toggleFollowBusiness(user: currentUser, businessId: businessId);
    }
  }

  Future<void> updateProfile({
    required String name,
    required String handle,
    required String city,
    required String district,
  }) async {
    final normalizedName = name.trim();
    final normalizedHandle = handle.trim();
    final normalizedCity = city.trim().isEmpty
        ? 'Deutschlandweit'
        : city.trim();
    final normalizedDistrict = district.trim().isEmpty
        ? 'In deiner Nähe'
        : district.trim();
    final locationChanged =
        normalizedCity != state.user.city ||
        normalizedDistrict != state.user.district;
    final updatedUser = state.user.copyWith(
      name: normalizedName,
      handle: normalizedHandle,
      city: normalizedCity,
      district: normalizedDistrict,
      latitude: locationChanged ? null : state.user.latitude,
      longitude: locationChanged ? null : state.user.longitude,
      preferences: state.user.preferences.copyWith(city: normalizedCity),
    );
    state = state.copyWith(user: updatedUser);

    if (state.isAuthenticated) {
      await ref
          .read(repositoryProvider)
          .updateUserProfile(
            user: updatedUser,
            name: normalizedName,
            handle: normalizedHandle,
            city: normalizedCity,
            district: normalizedDistrict,
          );
    }

    if (!locationChanged) {
      return;
    }

    if (normalizedCity != 'Deutschlandweit') {
      unawaited(
        _hydrateCoordinatesFromLocationLabel(
          city: normalizedCity,
          district: normalizedDistrict,
        ),
      );
      return;
    }
    ref
        .read(publicCouponRefreshControllerProvider.notifier)
        .scheduleRefresh(force: true);
  }

  void toggleBusinessMode(bool enabled) {
    if (state.user.accountType != AccountType.business) {
      return;
    }
    state = state.copyWith(businessModeEnabled: enabled);
  }

  Future<void> addRewardBonus({
    int points = 0,
    int freeCouponCredits = 0,
  }) async {
    final currentUser = state.user;
    final updatedUser = currentUser.copyWith(
      points: currentUser.points + points,
      freeCouponCredits: currentUser.freeCouponCredits + freeCouponCredits,
    );
    state = state.copyWith(user: updatedUser);

    if (state.isAuthenticated) {
      await ref
          .read(repositoryProvider)
          .addRewardBonus(
            user: currentUser,
            points: points,
            freeCouponCredits: freeCouponCredits,
          );
    }
  }

  void finishBusinessOnboarding({String businessId = ''}) {
    final resolvedUser = state.user.accountType == AccountType.business
        ? state.user
        : state.user.copyWith(accountType: AccountType.business);
    state = state.copyWith(
      user: resolvedUser,
      businessOnboardingComplete: true,
      businessModeEnabled: true,
      ownedBusinessId: businessId,
    );
  }
}

class SettingsState {
  const SettingsState({
    required this.themeMode,
    required this.pushEnabled,
    required this.openNowOnly,
    required this.distanceKm,
  });

  final ThemeMode themeMode;
  final bool pushEnabled;
  final bool openNowOnly;
  final double distanceKm;

  SettingsState copyWith({
    ThemeMode? themeMode,
    bool? pushEnabled,
    bool? openNowOnly,
    double? distanceKm,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      pushEnabled: pushEnabled ?? this.pushEnabled,
      openNowOnly: openNowOnly ?? this.openNowOnly,
      distanceKm: distanceKm ?? this.distanceKm,
    );
  }
}

class SettingsController extends StateNotifier<SettingsState> {
  SettingsController(this.ref)
    : super(
        const SettingsState(
          themeMode: ThemeMode.light,
          pushEnabled: true,
          openNowOnly: false,
          distanceKm: 35,
        ),
      );

  final Ref ref;

  void syncFromUser(User user) {
    final nextDistance = normalizeSearchRadiusKm(user.preferences.radiusKm);
    final nextPushEnabled = user.preferences.notificationsEnabled;
    final nextOpenNowOnly = user.preferences.openNowOnly;
    if (state.distanceKm == nextDistance &&
        state.pushEnabled == nextPushEnabled &&
        state.openNowOnly == nextOpenNowOnly) {
      return;
    }
    state = state.copyWith(
      distanceKm: nextDistance,
      pushEnabled: nextPushEnabled,
      openNowOnly: nextOpenNowOnly,
    );
  }

  void toggleTheme() {
    state = state.copyWith(
      themeMode: state.themeMode == ThemeMode.light
          ? ThemeMode.dark
          : ThemeMode.light,
    );
  }

  void togglePush(bool enabled) {
    state = state.copyWith(pushEnabled: enabled);
    ref
        .read(sessionControllerProvider.notifier)
        .syncPreferencesLocally(notificationsEnabled: enabled);
    if (ref.read(sessionControllerProvider).isAuthenticated) {
      ref
          .read(repositoryProvider)
          .updateUserSettings(
            user: ref.read(currentUserProvider),
            notificationsEnabled: enabled,
          );
    }
  }

  void toggleOpenNow(bool enabled) {
    state = state.copyWith(openNowOnly: enabled);
    ref
        .read(sessionControllerProvider.notifier)
        .syncPreferencesLocally(openNowOnly: enabled);
    if (ref.read(sessionControllerProvider).isAuthenticated) {
      ref
          .read(repositoryProvider)
          .updateUserSettings(
            user: ref.read(currentUserProvider),
            openNowOnly: enabled,
          );
    }
  }

  void setDistance(double distanceKm) {
    final normalizedDistanceKm = normalizeSearchRadiusKm(distanceKm);
    if ((state.distanceKm - normalizedDistanceKm).abs() < 0.05) {
      return;
    }
    state = state.copyWith(distanceKm: normalizedDistanceKm);
    ref
        .read(sessionControllerProvider.notifier)
        .syncPreferencesLocally(radiusKm: normalizedDistanceKm);
    if (ref.read(sessionControllerProvider).isAuthenticated) {
      ref
          .read(repositoryProvider)
          .updateUserSettings(
            user: ref.read(currentUserProvider),
            radiusKm: normalizedDistanceKm,
          );
    }
    ref
        .read(publicCouponRefreshControllerProvider.notifier)
        .scheduleRefresh(force: true);
  }
}

class PublicCouponRefreshController extends StateNotifier<bool> {
  PublicCouponRefreshController(this.ref) : super(false);

  final Ref ref;
  String? _activeRequestKey;
  bool _queuedRefresh = false;
  bool _queuedForce = false;

  void reset() {
    _activeRequestKey = null;
    _queuedRefresh = false;
    _queuedForce = false;
    state = false;
  }

  void scheduleRefresh({bool force = false}) {
    final authUser = ref.read(authUserProvider);
    if (authUser == null) {
      return;
    }

    final requestKey = ref.read(publicCouponRequestKeyProvider);
    final scanJob = ref.read(firebasePublicCouponScanJobProvider).valueOrNull;

    final cacheMeta =
        ref.read(firebasePublicCouponCacheMetaProvider).valueOrNull ??
        const _PublicCouponCacheMeta();
    final cacheIsFresh =
        cacheMeta.dealCount > 0 &&
        cacheMeta.lastUpdatedAt != null &&
        DateTime.now().difference(cacheMeta.lastUpdatedAt!).inHours < 18;
    final requestChanged =
        ref.read(_lastPublicCouponScanKeyProvider) != requestKey;
    final jobAlreadyRunning =
        scanJob != null &&
        scanJob.requestKey == requestKey &&
        scanJob.isEffectivelyActive;

    if (!force && !requestChanged && cacheIsFresh) {
      return;
    }
    if (jobAlreadyRunning) {
      return;
    }
    if (state) {
      _queuedRefresh = true;
      _queuedForce = _queuedForce || force;
      return;
    }
    if (_activeRequestKey == requestKey) {
      return;
    }

    _activeRequestKey = requestKey;
    unawaited(_runRefresh(requestKey, force: force));
  }

  Future<void> _runRefresh(String requestKey, {required bool force}) async {
    state = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      final authUser = ref.read(authUserProvider);
      if (authUser == null) {
        return;
      }
      final area = ref.read(discoverSearchAreaProvider);
      final radiusKm = ref.read(settingsControllerProvider).distanceKm;
      final jobId = ref.read(publicCouponScanJobIdProvider);
      final cacheScopeKey = ref.read(publicCouponCacheScopeKeyProvider);
      if (jobId == null || jobId.isEmpty) {
        return;
      }

      await ref
          .read(repositoryProvider)
          .enqueuePublicCouponScanJob(
            userId: authUser.uid,
            jobId: jobId,
            requestKey: requestKey,
            city: area.city,
            district: area.district,
            latitude: area.latitude,
            longitude: area.longitude,
            radiusKm: radiusKm,
            cacheScopeKey: cacheScopeKey,
            force: force,
          );
      ref.read(_lastPublicCouponScanKeyProvider.notifier).state = requestKey;
    } catch (error) {
      debugPrint('PublicCouponRefreshController failed: $error');
    } finally {
      state = false;
      if (_activeRequestKey == requestKey) {
        _activeRequestKey = null;
      }

      if (_queuedRefresh) {
        final queuedForce = _queuedForce;
        _queuedRefresh = false;
        _queuedForce = false;
        scheduleRefresh(force: queuedForce);
      }
    }
  }
}

class SavedDealsController extends StateNotifier<Set<String>> {
  SavedDealsController(this.ref, Set<String> initialState)
    : super(initialState);

  final Ref ref;

  void syncFromRemote(Set<String> dealIds) {
    if (setEquals(state, dealIds)) {
      return;
    }
    state = Set<String>.unmodifiable(dealIds);
  }

  Future<void> toggle(String dealId) async {
    final currentUser = ref.read(currentUserProvider);
    final next = state.toSet();
    if (next.contains(dealId)) {
      next.remove(dealId);
    } else {
      next.add(dealId);
    }
    state = next;

    if (ref.read(sessionControllerProvider).isAuthenticated) {
      final deal = ref.read(dealByIdProvider(dealId));
      final business = ref.read(businessByIdProvider(deal.businessId));
      await ref
          .read(repositoryProvider)
          .toggleSavedDeal(
            user: currentUser,
            dealId: dealId,
            dealOverride: deal,
            businessOverride: business,
          );
    }
  }
}

class LikedDealsController extends StateNotifier<Set<String>> {
  LikedDealsController() : super(<String>{});

  void toggle(String dealId) {
    final next = state.toSet();
    if (next.contains(dealId)) {
      next.remove(dealId);
    } else {
      next.add(dealId);
    }
    state = next;
  }
}

class StorySeenController extends StateNotifier<Set<String>> {
  StorySeenController(this.ref, Set<String> initialState) : super(initialState);

  final Ref ref;

  void syncFromRemote(Set<String> storyIds) {
    if (setEquals(state, storyIds)) {
      return;
    }
    state = Set<String>.unmodifiable(storyIds);
  }

  void markSeen(String storyId) {
    final normalizedStoryId = storyId.trim();
    if (normalizedStoryId.isEmpty || state.contains(normalizedStoryId)) {
      return;
    }
    state = <String>{...state, normalizedStoryId};

    if (ref.read(sessionControllerProvider).isAuthenticated) {
      unawaited(
        ref
            .read(repositoryProvider)
            .markStorySeen(ref.read(currentUserProvider), normalizedStoryId),
      );
    }
  }
}

class NotificationsController extends StateNotifier<List<NotificationItem>> {
  NotificationsController(this.ref) : super(const <NotificationItem>[]);

  final Ref ref;
  List<NotificationItem> _remoteItems = const <NotificationItem>[];

  bool _sameItems(List<NotificationItem> a, List<NotificationItem> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      final left = a[index];
      final right = b[index];
      if (left.id != right.id ||
          left.title != right.title ||
          left.body != right.body ||
          left.timeLabel != right.timeLabel ||
          left.type != right.type ||
          left.isRead != right.isRead ||
          left.dealId != right.dealId ||
          left.businessId != right.businessId) {
        return false;
      }
    }
    return true;
  }

  void _setStateIfChanged(List<NotificationItem> next) {
    if (_sameItems(state, next)) {
      return;
    }
    state = next;
  }

  void syncFromRemote(List<NotificationItem> items) {
    _remoteItems = items;
  }

  Future<void> markRead(String id) async {
    _setStateIfChanged(
      state
          .map((item) => item.id == id ? item.copyWith(isRead: true) : item)
          .toList(growable: false),
    );

    if (ref.read(sessionControllerProvider).isAuthenticated) {
      await ref.read(repositoryProvider).markNotificationRead(id);
    }
  }

  Future<void> markAllRead() async {
    _setStateIfChanged(
      state.map((item) => item.copyWith(isRead: true)).toList(growable: false),
    );

    if (ref.read(sessionControllerProvider).isAuthenticated) {
      await ref
          .read(repositoryProvider)
          .markAllNotificationsRead(ref.read(currentUserProvider).id);
    }
  }

  Future<void> add(NotificationItem item) async {
    final withoutExisting = state
        .where((entry) => entry.id != item.id)
        .toList();
    _setStateIfChanged(<NotificationItem>[item, ...withoutExisting]);

    if (ref.read(sessionControllerProvider).isAuthenticated) {
      await ref
          .read(repositoryProvider)
          .pushNotification(
            userId: ref.read(currentUserProvider).id,
            item: item,
          );
    }
  }

  void syncSmartAlerts({
    required User user,
    required List<Deal> deals,
    required List<Business> businesses,
    required List<Deal> savedDeals,
    required List<Redemption> redemptions,
    required bool pushEnabled,
  }) {
    final stickyItems = _remoteItems
        .where((item) => !item.id.startsWith('smart_'))
        .toList(growable: false);
    final existingById = <String, NotificationItem>{
      for (final item in _remoteItems) item.id: item,
    };
    final businessNames = <String, String>{
      for (final business in businesses) business.id: business.name,
    };
    final smartItems = <NotificationItem>[];

    if (pushEnabled) {
      for (final deal
          in savedDeals.where((deal) => deal.isExpiringSoon).take(3)) {
        final id = 'smart_saved_${deal.id}';
        final previous = existingById[id];
        smartItems.add(
          NotificationItem(
            id: id,
            title: 'Gespeicherter Gutschein endet bald',
            body:
                '${deal.title} ist gespeichert und läuft bald ab. Jetzt aktivieren, solange er noch live ist.',
            timeLabel: 'Heute',
            type: NotificationType.expiring,
            isRead: previous?.isRead ?? false,
            dealId: deal.id,
            businessId: deal.businessId,
          ),
        );
      }

      for (final redemption
          in redemptions
              .where((item) => item.status == RedemptionStatus.active)
              .where(
                (item) =>
                    item.expiresAt.difference(DateTime.now()).inHours <= 36,
              )
              .take(2)) {
        final id = 'smart_wallet_${redemption.id}';
        final previous = existingById[id];
        smartItems.add(
          NotificationItem(
            id: id,
            title: 'Aktiver Gutschein läuft bald aus',
            body:
                'Dein Pass ${redemption.couponId} endet bald. QR und Gutschein-ID sind offline verfügbar.',
            timeLabel: 'Heute',
            type: NotificationType.expiring,
            isRead: previous?.isRead ?? false,
            dealId: redemption.dealId,
          ),
        );
      }

      for (final deal
          in deals
              .where(
                (deal) => user.followingBusinessIds.contains(deal.businessId),
              )
              .where(
                (deal) =>
                    deal.tags.contains(OfferTag.fresh) ||
                    deal.tags.contains(OfferTag.today) ||
                    deal.type == DealType.limitedTime,
              )
              .take(3)) {
        final id = 'smart_follow_${deal.id}';
        final previous = existingById[id];
        smartItems.add(
          NotificationItem(
            id: id,
            title: 'Neuer Gutschein von einem gefolgten Laden',
            body:
                '${businessNames[deal.businessId] ?? 'Ein gefolgter Laden'} hat ${deal.title} live gestellt.',
            timeLabel: 'Neu',
            type: NotificationType.followingBusiness,
            isRead: previous?.isRead ?? false,
            dealId: deal.id,
            businessId: deal.businessId,
          ),
        );
      }

      for (final deal
          in deals
              .where((deal) => deal.city == user.city)
              .where(
                (deal) =>
                    deal.tags.contains(OfferTag.today) ||
                    deal.type == DealType.limitedTime,
              )
              .take(2)) {
        final id = 'smart_live_${deal.id}';
        final previous = existingById[id];
        smartItems.add(
          NotificationItem(
            id: id,
            title: 'Tagesdeal live in ${user.city}',
            body: '${deal.title} ist gerade live und schnell einlösbar.',
            timeLabel: 'Jetzt',
            type: NotificationType.liveDeal,
            isRead: previous?.isRead ?? false,
            dealId: deal.id,
            businessId: deal.businessId,
          ),
        );
      }
    }

    _setStateIfChanged(<NotificationItem>[...smartItems, ...stickyItems]);
  }
}

class WalletController extends StateNotifier<List<Redemption>> {
  WalletController(List<Redemption> initialState) : super(initialState);

  Future<Redemption> activate(Deal deal) async {
    if (deal.isThirdParty) {
      throw StateError(
        'Öffentliche Drittquellen können nicht als sparGO-Pass aktiviert werden.',
      );
    }
    final existing = state.where(
      (item) =>
          item.dealId == deal.id && item.status == RedemptionStatus.active,
    );
    if (existing.isNotEmpty) {
      return existing.first;
    }

    final seed = deal.id
        .replaceFirst('deal_', '')
        .replaceAll('_', '')
        .toUpperCase();
    final codeSeed = seed.length >= 8
        ? seed.substring(0, 8)
        : seed.padRight(8, 'X');
    final couponSeed = seed.length >= 10
        ? seed.substring(0, 10)
        : seed.padRight(10, 'X');
    final redemption = Redemption(
      id: 'runtime_${deal.id}',
      dealId: deal.id,
      code: 'SP-$codeSeed',
      couponId: 'CPN-$couponSeed',
      qrPayload:
          'spargo://coupon/${deal.id}?coupon=CPN-$couponSeed&code=SP-$codeSeed',
      activatedAt: DateTime.now(),
      expiresAt: deal.validUntil,
      status: RedemptionStatus.active,
      offlineReady: true,
      instructions:
          'Beim Einlösen den Code, die Gutschein-ID oder den QR-Screen vorzeigen.',
    );

    state = <Redemption>[redemption, ...state];
    return redemption;
  }

  void markRedeemed(String redemptionId) {
    state = state
        .map(
          (item) => item.id == redemptionId
              ? item.copyWith(
                  status: RedemptionStatus.redeemed,
                  usedAt: DateTime.now(),
                )
              : item,
        )
        .toList();
  }
}

@immutable
class OwnedBusinessDraft {
  const OwnedBusinessDraft({
    required this.businessId,
    required this.category,
    required this.name,
    required this.tagline,
    required this.description,
    required this.shortDescription,
    required this.website,
    required this.phone,
    required this.contactEmail,
    required this.legalEntityName,
    required this.imprintInfo,
    required this.address,
    required this.city,
    required this.district,
    required this.claimedByName,
    required this.claimedByRole,
    required this.ownershipConfirmed,
    this.verificationPlaceId = '',
    this.verificationWebsite = '',
    this.verificationMethod = BusinessVerificationMethod.emailDomain,
    this.googleProfileLink = const BusinessGoogleProfileLink(),
  });

  final String businessId;
  final DealCategory category;
  final String name;
  final String tagline;
  final String description;
  final String shortDescription;
  final String website;
  final String phone;
  final String contactEmail;
  final String legalEntityName;
  final String imprintInfo;
  final String address;
  final String city;
  final String district;
  final String claimedByName;
  final String claimedByRole;
  final bool ownershipConfirmed;
  final String verificationPlaceId;
  final String verificationWebsite;
  final BusinessVerificationMethod verificationMethod;
  final BusinessGoogleProfileLink googleProfileLink;

  factory OwnedBusinessDraft.fromBusiness(Business business) {
    return OwnedBusinessDraft(
      businessId: business.id,
      category: business.category,
      name: business.name,
      tagline: business.tagline,
      description: business.description,
      shortDescription: business.shortDescription,
      website: business.website,
      phone: business.phone,
      contactEmail: business.contactEmail,
      legalEntityName: business.legalEntityName.isEmpty
          ? business.name
          : business.legalEntityName,
      imprintInfo: business.imprintInfo,
      address: business.primaryBranch.address,
      city: business.city,
      district: business.district,
      claimedByName: business.claimedByName,
      claimedByRole: business.claimedByRole,
      ownershipConfirmed: business.ownershipConfirmed,
      verificationPlaceId: business.verificationPlaceId,
      verificationWebsite: business.verificationWebsite,
      verificationMethod: business.verificationMethod,
      googleProfileLink: business.googleProfileLink,
    );
  }

  OwnedBusinessDraft copyWith({
    String? businessId,
    DealCategory? category,
    String? name,
    String? tagline,
    String? description,
    String? shortDescription,
    String? website,
    String? phone,
    String? contactEmail,
    String? legalEntityName,
    String? imprintInfo,
    String? address,
    String? city,
    String? district,
    String? claimedByName,
    String? claimedByRole,
    bool? ownershipConfirmed,
    String? verificationPlaceId,
    String? verificationWebsite,
    BusinessVerificationMethod? verificationMethod,
    BusinessGoogleProfileLink? googleProfileLink,
  }) {
    return OwnedBusinessDraft(
      businessId: businessId ?? this.businessId,
      category: category ?? this.category,
      name: name ?? this.name,
      tagline: tagline ?? this.tagline,
      description: description ?? this.description,
      shortDescription: shortDescription ?? this.shortDescription,
      website: website ?? this.website,
      phone: phone ?? this.phone,
      contactEmail: contactEmail ?? this.contactEmail,
      legalEntityName: legalEntityName ?? this.legalEntityName,
      imprintInfo: imprintInfo ?? this.imprintInfo,
      address: address ?? this.address,
      city: city ?? this.city,
      district: district ?? this.district,
      claimedByName: claimedByName ?? this.claimedByName,
      claimedByRole: claimedByRole ?? this.claimedByRole,
      ownershipConfirmed: ownershipConfirmed ?? this.ownershipConfirmed,
      verificationPlaceId: verificationPlaceId ?? this.verificationPlaceId,
      verificationWebsite: verificationWebsite ?? this.verificationWebsite,
      verificationMethod: verificationMethod ?? this.verificationMethod,
      googleProfileLink: googleProfileLink ?? this.googleProfileLink,
    );
  }
}

class OwnedBusinessDraftController extends StateNotifier<OwnedBusinessDraft?> {
  OwnedBusinessDraftController() : super(null);

  void seedFromBusiness(Business business) {
    state = OwnedBusinessDraft.fromBusiness(business);
  }

  void save({
    required Business business,
    required DealCategory category,
    required String name,
    required String tagline,
    required String description,
    required String shortDescription,
    required String website,
    required String phone,
    required String contactEmail,
    required String legalEntityName,
    required String imprintInfo,
    required String address,
    required String city,
    required String district,
    required String claimedByName,
    required String claimedByRole,
    required bool ownershipConfirmed,
    String verificationPlaceId = '',
    String verificationWebsite = '',
    BusinessVerificationMethod verificationMethod =
        BusinessVerificationMethod.emailDomain,
    BusinessGoogleProfileLink googleProfileLink =
        const BusinessGoogleProfileLink(),
  }) {
    state = OwnedBusinessDraft(
      businessId: business.id,
      category: category,
      name: name.trim(),
      tagline: tagline.trim(),
      description: description.trim(),
      shortDescription: shortDescription.trim(),
      website: website.trim(),
      phone: phone.trim(),
      contactEmail: contactEmail.trim(),
      legalEntityName: legalEntityName.trim(),
      imprintInfo: imprintInfo.trim(),
      address: address.trim(),
      city: city.trim(),
      district: district.trim(),
      claimedByName: claimedByName.trim(),
      claimedByRole: claimedByRole.trim(),
      ownershipConfirmed: ownershipConfirmed,
      verificationPlaceId: verificationPlaceId.trim(),
      verificationWebsite: verificationWebsite.trim(),
      verificationMethod: verificationMethod,
      googleProfileLink: googleProfileLink,
    );
  }

  void clear() {
    state = null;
  }
}

class SearchState {
  const SearchState({
    this.query = '',
    this.category,
    this.onlyToday = false,
    this.onlyExclusive = false,
    this.openNowOnly = false,
    this.popularOnly = false,
    this.freshOnly = false,
    this.maxDistanceKm = maxSearchRadiusKm,
    this.minRating = 0,
  });

  final String query;
  final DealCategory? category;
  final bool onlyToday;
  final bool onlyExclusive;
  final bool openNowOnly;
  final bool popularOnly;
  final bool freshOnly;
  final double maxDistanceKm;
  final double minRating;

  SearchState copyWith({
    String? query,
    DealCategory? category,
    bool clearCategory = false,
    bool? onlyToday,
    bool? onlyExclusive,
    bool? openNowOnly,
    bool? popularOnly,
    bool? freshOnly,
    double? maxDistanceKm,
    double? minRating,
  }) {
    return SearchState(
      query: query ?? this.query,
      category: clearCategory ? null : category ?? this.category,
      onlyToday: onlyToday ?? this.onlyToday,
      onlyExclusive: onlyExclusive ?? this.onlyExclusive,
      openNowOnly: openNowOnly ?? this.openNowOnly,
      popularOnly: popularOnly ?? this.popularOnly,
      freshOnly: freshOnly ?? this.freshOnly,
      maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
      minRating: minRating ?? this.minRating,
    );
  }
}

class SearchController extends StateNotifier<SearchState> {
  SearchController() : super(const SearchState());

  void updateQuery(String query) => state = state.copyWith(query: query);

  void setCategory(DealCategory? category) => state = category == null
      ? state.copyWith(clearCategory: true)
      : state.copyWith(category: category);

  void toggleToday(bool enabled) => state = state.copyWith(onlyToday: enabled);

  void toggleExclusive(bool enabled) =>
      state = state.copyWith(onlyExclusive: enabled);

  void toggleOpenNow(bool enabled) =>
      state = state.copyWith(openNowOnly: enabled);

  void togglePopular(bool enabled) =>
      state = state.copyWith(popularOnly: enabled);

  void toggleFresh(bool enabled) => state = state.copyWith(freshOnly: enabled);

  void setDistance(double value) =>
      state = state.copyWith(maxDistanceKm: normalizeSearchRadiusKm(value));

  void setMinRating(double value) => state = state.copyWith(minRating: value);

  void reset() => state = const SearchState();
}

class ReviewsController extends StateNotifier<List<AppReview>> {
  ReviewsController() : super(const <AppReview>[]);

  void submit({
    required User user,
    required int rating,
    required String comment,
    String? dealId,
    String? businessId,
  }) {
    state = <AppReview>[
      AppReview(
        id: 'review_runtime_${state.length + 1}',
        authorName: user.name,
        authorInitials: user.avatarInitials,
        authorId: user.id,
        rating: rating,
        comment: comment,
        timeLabel: 'Gerade eben',
        helpfulCount: 0,
        city: user.city,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        dealId: dealId,
        businessId: businessId,
      ),
      ...state,
    ];
  }
}

class LiveWalletController extends StateNotifier<List<Redemption>> {
  LiveWalletController(this.ref, List<Redemption> initialState)
    : super(initialState);

  final Ref ref;

  void syncFromRemote(List<Redemption> items) {
    final localFallbacks = state.where((entry) {
      if (!entry.id.startsWith('runtime_')) {
        return false;
      }
      return !items.any(
        (remote) =>
            remote.dealId == entry.dealId && remote.status == entry.status,
      );
    });
    state = _dedupeRedemptions(<Redemption>[...items, ...localFallbacks]);
  }

  Future<Redemption> activate(Deal deal) async {
    final existing = state.where(
      (item) =>
          item.dealId == deal.id && item.status == RedemptionStatus.active,
    );
    if (existing.isNotEmpty) {
      return existing.first;
    }

    final business = ref.read(businessByIdProvider(deal.businessId));
    Redemption redemption;
    try {
      redemption = await ref
          .read(repositoryProvider)
          .activateDeal(
            user: ref.read(currentUserProvider),
            deal: deal,
            business: business,
          );
    } catch (_) {
      final seed = deal.id
          .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
          .toUpperCase();
      final codeSeed = seed.length >= 8
          ? seed.substring(0, 8)
          : seed.padRight(8, 'X');
      final couponSeed = seed.length >= 10
          ? seed.substring(0, 10)
          : seed.padRight(10, 'X');
      redemption = Redemption(
        id: 'runtime_${deal.id}',
        dealId: deal.id,
        code: 'SP-$codeSeed',
        couponId: 'CPN-$couponSeed',
        qrPayload:
            'spargo://coupon/${deal.id}?coupon=CPN-$couponSeed&code=SP-$codeSeed',
        activatedAt: DateTime.now(),
        expiresAt: deal.validUntil,
        status: RedemptionStatus.active,
        offlineReady: true,
        instructions:
            'Beim Einlösen den Code, die Gutschein-ID oder den QR-Screen vorzeigen.',
      );
    }

    state = _dedupeRedemptions(<Redemption>[redemption, ...state]);
    return redemption;
  }

  Future<void> markRedeemed(
    String redemptionId, {
    int savedAmountCents = 0,
  }) async {
    final repository = ref.read(repositoryProvider);
    final user = ref.read(currentUserProvider);
    final redemption = state.firstWhere(
      (item) => item.id == redemptionId,
      orElse: () => throw StateError('Redemption not found: $redemptionId'),
    );
    state = state
        .map(
          (item) => item.id == redemptionId
              ? item.copyWith(
                  status: RedemptionStatus.redeemed,
                  savedAmountCents: savedAmountCents.clamp(0, 999999999),
                  usedAt: DateTime.now(),
                )
              : item,
        )
        .toList(growable: false);

    try {
      await Future<void>.delayed(Duration.zero);
      await repository.redeemRedemption(
        user: user,
        redemption: redemption,
        savedAmountCents: savedAmountCents,
      );
    } catch (_) {}
  }

  List<Redemption> _dedupeRedemptions(List<Redemption> items) {
    final ordered = items.toList(growable: false)
      ..sort((a, b) {
        final aTime = a.usedAt ?? a.activatedAt;
        final bTime = b.usedAt ?? b.activatedAt;
        return bTime.compareTo(aTime);
      });

    final deduped = <String, Redemption>{};
    for (final item in ordered) {
      final key = item.status == RedemptionStatus.active
          ? 'active|${item.dealId}'
          : '${item.status.name}|${item.id}';
      final existing = deduped[key];
      if (existing == null) {
        deduped[key] = item;
        continue;
      }
      final preferCurrent =
          existing.id.startsWith('runtime_') && !item.id.startsWith('runtime_');
      if (preferCurrent) {
        deduped[key] = item;
      }
    }
    return deduped.values.toList(growable: false);
  }
}

class LiveReviewsController extends StateNotifier<List<AppReview>> {
  LiveReviewsController(this.ref, List<AppReview> initialState)
    : super(initialState);

  final Ref ref;

  void syncFromRemote(List<AppReview> reviews) {
    state = reviews;
  }

  Future<void> submit({
    required User user,
    required int rating,
    required String comment,
    String? dealId,
    String? businessId,
  }) {
    return ref
        .read(repositoryProvider)
        .submitReview(
          user: user,
          rating: rating,
          comment: comment,
          dealId: dealId,
          businessId: businessId,
        );
  }

  Future<void> updateReview({
    required User user,
    required AppReview review,
    required int rating,
    required String comment,
  }) {
    return ref
        .read(repositoryProvider)
        .updateReview(
          user: user,
          review: review,
          rating: rating,
          comment: comment,
        );
  }

  Future<void> deleteReview({required User user, required AppReview review}) {
    return ref
        .read(repositoryProvider)
        .deleteReview(user: user, review: review);
  }
}

final sessionControllerProvider =
    StateNotifierProvider<SessionController, SessionState>((ref) {
      final controller = SessionController(ref);

      ref.listen<firebase_auth.User?>(authUserProvider, (previous, next) {
        if (next == null) {
          controller.syncFromBackend(record: null, authUser: null);
        }
      });

      ref.listen<AsyncValue<SessionUserRecord?>>(
        firebaseSessionUserRecordProvider,
        (previous, next) {
          controller.syncFromBackend(
            record: next.valueOrNull,
            authUser: ref.read(authUserProvider),
          );
          unawaited(
            controller.handleRemoteSessionConflict(
              record: next.valueOrNull,
              authUser: ref.read(authUserProvider),
              device: ref.read(deviceSessionProvider).valueOrNull,
            ),
          );
        },
      );

      ref.listen<AsyncValue<DeviceSessionInfo>>(deviceSessionProvider, (
        previous,
        next,
      ) {
        unawaited(
          controller.handleRemoteSessionConflict(
            record: ref.read(firebaseSessionUserRecordProvider).valueOrNull,
            authUser: ref.read(authUserProvider),
            device: next.valueOrNull,
          ),
        );
      });

      ref.listen<AsyncValue<String?>>(firebaseOwnedBusinessFallbackIdProvider, (
        previous,
        next,
      ) {
        final businessId = next.valueOrNull?.trim() ?? '';
        final authUser = ref.read(authUserProvider);
        if (authUser == null || businessId.isEmpty) {
          return;
        }
        if (controller.state.ownedBusinessId == businessId) {
          return;
        }

        controller.finishBusinessOnboarding(businessId: businessId);
        unawaited(
          ref
              .read(repositoryProvider)
              .repairOwnedBusinessLink(
                userId: authUser.uid,
                businessId: businessId,
              ),
        );
      });

      return controller;
    });

final settingsControllerProvider =
    StateNotifierProvider<SettingsController, SettingsState>((ref) {
      final controller = SettingsController(ref);
      controller.syncFromUser(ref.read(currentUserProvider));
      ref.listen<User>(currentUserProvider, (previous, next) {
        controller.syncFromUser(next);
      });
      return controller;
    });

final publicCouponRefreshControllerProvider =
    StateNotifierProvider<PublicCouponRefreshController, bool>((ref) {
      return PublicCouponRefreshController(ref);
    });

final savedDealsProvider =
    StateNotifierProvider<SavedDealsController, Set<String>>((ref) {
      final controller = SavedDealsController(
        ref,
        ref.read(currentUserProvider).savedDealIds.toSet(),
      );

      ref.listen<User>(currentUserProvider, (previous, next) {
        unawaited(
          Future<void>.microtask(
            () => controller.syncFromRemote(next.savedDealIds.toSet()),
          ),
        );
      });

      return controller;
    });

final likedDealsProvider =
    StateNotifierProvider<LikedDealsController, Set<String>>((ref) {
      return LikedDealsController();
    });

final storySeenProvider =
    StateNotifierProvider<StorySeenController, Set<String>>((ref) {
      final controller = StorySeenController(
        ref,
        ref.read(currentUserProvider).seenStoryIds.toSet(),
      );
      ref.listen<User>(currentUserProvider, (previous, next) {
        unawaited(
          Future<void>.microtask(
            () => controller.syncFromRemote(next.seenStoryIds.toSet()),
          ),
        );
      });
      return controller;
    });

final walletProvider =
    StateNotifierProvider<LiveWalletController, List<Redemption>>((ref) {
      final controller = LiveWalletController(
        ref,
        ref.read(firebaseRedemptionsProvider).valueOrNull ??
            const <Redemption>[],
      );

      ref.listen<AsyncValue<List<Redemption>>>(firebaseRedemptionsProvider, (
        previous,
        next,
      ) {
        unawaited(
          Future<void>.microtask(
            () => controller.syncFromRemote(
              next.valueOrNull ?? const <Redemption>[],
            ),
          ),
        );
      });

      return controller;
    });

final ownedBusinessDraftProvider =
    StateNotifierProvider<OwnedBusinessDraftController, OwnedBusinessDraft?>(
      (ref) => OwnedBusinessDraftController(),
    );

final searchControllerProvider =
    StateNotifierProvider<SearchController, SearchState>((ref) {
      return SearchController();
    });

final reviewsProvider =
    StateNotifierProvider<LiveReviewsController, List<AppReview>>((ref) {
      final controller = LiveReviewsController(
        ref,
        ref.read(firebaseReviewsProvider).valueOrNull ?? const <AppReview>[],
      );

      ref.listen<AsyncValue<List<AppReview>>>(firebaseReviewsProvider, (
        previous,
        next,
      ) {
        unawaited(
          Future<void>.microtask(
            () => controller.syncFromRemote(
              next.valueOrNull ?? const <AppReview>[],
            ),
          ),
        );
      });

      return controller;
    });

final currentUserProvider = Provider<User>((ref) {
  return ref.watch(sessionControllerProvider).user;
});

final feedFilterProvider = StateProvider<FeedFilter>((ref) {
  return FeedFilter.forYou;
});

final _pinnedPublicCouponDealIdsProvider = Provider<List<String>>((ref) {
  final savedDealIds = ref.watch(savedDealsProvider);
  final wallet = ref.watch(walletProvider);
  final pinnedIds = <String>{
    for (final dealId in savedDealIds)
      if (_isPublicCouponDealId(dealId)) dealId,
    for (final redemption in wallet)
      if (_isPublicCouponDealId(redemption.dealId)) redemption.dealId,
  };
  return pinnedIds.toList(growable: false);
});

final pinnedPublicCouponLookupProvider =
    FutureProvider<_PinnedPublicCouponLookup>((ref) async {
      final dealIds = ref.watch(_pinnedPublicCouponDealIdsProvider);
      if (dealIds.isEmpty) {
        return const _PinnedPublicCouponLookup();
      }

      final firestore = ref.watch(firebaseFirestoreProvider);
      final area = ref.watch(discoverSearchAreaProvider);
      final now = DateTime.now();

      try {
        final dealSnapshots = await Future.wait(
          dealIds.map(
            (dealId) => firestore
                .collection(FirestoreCollections.publicCouponDeals)
                .doc(dealId)
                .get(),
          ),
        );

        final rawRecords = <DealRecord>[];
        final businessIds = <String>{};

        for (final snapshot in dealSnapshots) {
          final data = snapshot.data();
          if (data == null ||
              data['cacheGeminiValidationState']?.toString() != 'verified') {
            continue;
          }
          final expiresAt = _readTimestamp(data['cacheExpiresAt']);
          if (expiresAt != null && expiresAt.isBefore(now)) {
            continue;
          }
          final record = _sanitizeDealRecordForUi(
            FirebaseMappers.dealRecordFromMap(data, id: snapshot.id),
          );
          rawRecords.add(record);
          businessIds.add(record.deal.businessId);
        }

        if (rawRecords.isEmpty) {
          return const _PinnedPublicCouponLookup();
        }

        final businessSnapshots = await Future.wait(
          businessIds.map(
            (businessId) => firestore
                .collection(FirestoreCollections.publicCouponBusinesses)
                .doc(businessId)
                .get(),
          ),
        );

        final businesses = <Business>[];
        for (final snapshot in businessSnapshots) {
          final data = snapshot.data();
          if (data == null ||
              data['cacheGeminiValidationState']?.toString() != 'verified') {
            continue;
          }
          final expiresAt = _readTimestamp(data['cacheExpiresAt']);
          if (expiresAt != null && expiresAt.isBefore(now)) {
            continue;
          }
          businesses.add(
            FirebaseMappers.businessFromMap(data, id: snapshot.id),
          );
        }

        final businessesById = <String, Business>{
          for (final business in businesses) business.id: business,
        };
        final dealRecords = rawRecords
            .map(
              (record) => _applyLiveBusinessDistanceToDealRecord(
                record,
                area: area,
                business: businessesById[record.deal.businessId],
              ),
            )
            .toList(growable: false);

        return _PinnedPublicCouponLookup(
          dealRecords: _dedupePublicCouponDealRecords(dealRecords),
          businesses: _dedupePublicCouponBusinesses(businesses),
        );
      } catch (error) {
        debugPrint('pinnedPublicCouponLookupProvider failed: $error');
        return const _PinnedPublicCouponLookup();
      }
    });

final dealsProvider = Provider<List<Deal>>((ref) {
  final nativeDeals = ref.watch(repositoryProvider).deals;
  final savedDealIds = ref.watch(savedDealsProvider);
  final wallet = ref.watch(walletProvider);
  final area = ref.watch(discoverSearchAreaProvider);
  final radiusKm = ref.watch(settingsControllerProvider).distanceKm;
  final businesses = ref.watch(businessesProvider);
  final cachedPublicDeals = ref
      .watch(publicCouponDealRecordsProvider)
      .map((entry) => entry.deal)
      .toList(growable: false);
  return _withLiveDealDistances(
        _mergeDeals(nativeDeals, cachedPublicDeals),
        businesses: businesses,
        area: area,
      )
      .where((deal) => _isDealVisibleInArea(deal, radiusKm: radiusKm))
      .map((deal) => _enrichDealStatsForUser(deal, savedDealIds, wallet))
      .toList(growable: false);
});

final visiblePublicCouponDealsProvider = Provider<List<Deal>>((ref) {
  return ref
      .watch(publicCouponDealRecordsProvider)
      .map((entry) => entry.deal)
      .toList(growable: false);
});

final businessesProvider = Provider<List<Business>>((ref) {
  final nativeBusinesses = ref.watch(repositoryProvider).businesses;
  final cachedPublicBusinesses = ref.watch(publicCouponBusinessesProvider);
  final area = ref.watch(discoverSearchAreaProvider);
  final radiusKm = ref.watch(settingsControllerProvider).distanceKm;
  final ownedBusinessId = ref
      .watch(sessionControllerProvider)
      .ownedBusinessId
      .trim();
  return _withLiveBusinessDistances(
        _mergeBusinesses(nativeBusinesses, cachedPublicBusinesses),
        area: area,
      )
      .where(
        (business) =>
            business.id == ownedBusinessId ||
            _isBusinessVisibleInArea(business, area: area, radiusKm: radiusKm),
      )
      .map(_sanitizeBusinessForUi)
      .toList(growable: false);
});

final notificationsProvider =
    StateNotifierProvider<NotificationsController, List<NotificationItem>>((
      ref,
    ) {
      final controller = NotificationsController(ref);

      void syncAll() {
        controller.syncFromRemote(
          ref.read(firebaseNotificationsProvider).valueOrNull ??
              const <NotificationItem>[],
        );

        controller.syncSmartAlerts(
          user: ref.read(currentUserProvider),
          deals: ref.read(dealsProvider),
          businesses: ref.read(businessesProvider),
          savedDeals: ref.read(savedDealListProvider),
          redemptions: ref.read(walletProvider),
          pushEnabled: ref.read(settingsControllerProvider).pushEnabled,
        );
      }

      void syncAllLater() => unawaited(Future<void>.microtask(syncAll));

      syncAllLater();
      ref.listen<AsyncValue<List<NotificationItem>>>(
        firebaseNotificationsProvider,
        (previous, next) {
          syncAllLater();
        },
      );
      ref.listen<Set<String>>(
        savedDealsProvider,
        (previous, next) => syncAllLater(),
      );
      ref.listen<SessionState>(
        sessionControllerProvider,
        (previous, next) => syncAllLater(),
      );
      ref.listen<List<Redemption>>(
        walletProvider,
        (previous, next) => syncAllLater(),
      );
      ref.listen<SettingsState>(
        settingsControllerProvider,
        (previous, next) => syncAllLater(),
      );
      ref.listen<List<Business>>(
        businessesProvider,
        (previous, next) => syncAllLater(),
      );
      ref.listen<List<Deal>>(dealsProvider, (previous, next) => syncAllLater());

      return controller;
    });

final discoverSearchAreaProvider = Provider<NearbySearchArea>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user.latitude != null && user.longitude != null) {
    return NearbySearchArea(
      city: user.city,
      district: user.district,
      latitude: user.latitude!,
      longitude: user.longitude!,
    );
  }
  final fallbackCoordinates = resolveLocationCoordinatesFallbackSync(
    city: user.city,
    district: user.district,
  );
  if (fallbackCoordinates != null) {
    return NearbySearchArea(
      city: fallbackCoordinates.city,
      district: fallbackCoordinates.district,
      latitude: fallbackCoordinates.latitude,
      longitude: fallbackCoordinates.longitude,
    );
  }
  return NearbySearchArea(
    city: user.city.trim().isEmpty ? 'Deutschlandweit' : user.city,
    district: user.district.trim().isEmpty ? 'In deiner Nähe' : user.district,
    latitude: 52.5200,
    longitude: 13.4050,
  );
});

final nearbyPlacesProvider = FutureProvider<List<NearbyPlace>>((ref) async {
  final area = ref.watch(discoverSearchAreaProvider);
  final radiusKm = ref.watch(settingsControllerProvider).distanceKm;
  final client = http.Client();
  ref.onDispose(client.close);

  try {
    return await GoogleMapsPlacesService(
      client: client,
    ).fetchNearbyPlaces(area: area, radiusKm: radiusKm);
  } catch (error) {
    if (error is! TimeoutException) {
      debugPrint('nearbyPlacesProvider failed: $error');
    }
    return const <NearbyPlace>[];
  }
});

final publicCouponBundleProvider = FutureProvider<PublicCouponBundle>((
  ref,
) async {
  if (kIsWeb) {
    return const PublicCouponBundle();
  }

  final authUser = ref.watch(authUserProvider);
  final area = ref.watch(discoverSearchAreaProvider);
  final distanceKm = ref.watch(settingsControllerProvider).distanceKm;
  final requestKey = ref.watch(publicCouponRequestKeyProvider);
  final cacheScopeKey = ref.watch(publicCouponCacheScopeKeyProvider);
  final lastScanKey = ref.read(_lastPublicCouponScanKeyProvider);
  final cacheMeta =
      ref.read(firebasePublicCouponCacheMetaProvider).valueOrNull ??
      const _PublicCouponCacheMeta();
  final cacheIsFresh =
      cacheMeta.dealCount > 0 &&
      cacheMeta.lastUpdatedAt != null &&
      DateTime.now().difference(cacheMeta.lastUpdatedAt!).inHours < 6;
  final requestChanged = lastScanKey != requestKey;
  if (authUser == null || (cacheIsFresh && !requestChanged)) {
    return const PublicCouponBundle();
  }
  final repository = ref.read(repositoryProvider);
  final nativeBusinesses = repository.businesses;
  final client = http.Client();
  ref.onDispose(client.close);
  var lastPersistedPublicDealCount = 0;
  var latestPartialBundle = const PublicCouponBundle();

  try {
    Future<void> persistPartialBundle(
      PublicCouponBundle bundle, {
      bool finalFlush = false,
    }) async {
      final currentAuthUser = ref.read(authUserProvider);
      if (currentAuthUser == null || (!finalFlush && bundle.deals.isEmpty)) {
        return;
      }
      final persistedCount = math.min(bundle.deals.length, 48);
      if (!finalFlush && persistedCount <= lastPersistedPublicDealCount) {
        return;
      }
      lastPersistedPublicDealCount = persistedCount;
      if (bundle.deals.isNotEmpty) {
        latestPartialBundle = bundle;
      }
      try {
        await repository.cachePublicCouponBundle(
          userId: currentAuthUser.uid,
          requestKey: requestKey,
          cacheScopeKey: cacheScopeKey,
          bundle: bundle,
          replaceExisting: finalFlush,
        );
      } catch (error) {
        debugPrint('cachePublicCouponBundle failed: $error');
      }
    }

    final scanRadiusKm = normalizeSearchRadiusKm(distanceKm);
    final nearbyPlaces = await GoogleMapsPlacesService(client: client)
        .fetchNearbyPlaces(area: area, radiusKm: scanRadiusKm)
        .timeout(
          const Duration(seconds: 24),
          onTimeout: () {
            debugPrint(
              'publicCouponBundleProvider nearby place lookup timed out',
            );
            return const <NearbyPlace>[];
          },
        );
    final bundle = await PublicCouponScannerService(client: client)
        .scan(
          area: area,
          businesses: nativeBusinesses,
          nearbyPlaces: nearbyPlaces,
          onProgress: (partialBundle) async {
            await persistPartialBundle(partialBundle);
          },
        )
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            debugPrint('publicCouponBundleProvider scan timed out');
            return const PublicCouponBundle();
          },
        );
    final bundleToPersist =
        bundle.deals.isEmpty && latestPartialBundle.deals.isNotEmpty
        ? latestPartialBundle
        : bundle;
    await persistPartialBundle(bundleToPersist, finalFlush: true);
    ref.read(_lastPublicCouponScanKeyProvider.notifier).state = requestKey;
    return bundleToPersist;
  } catch (error) {
    debugPrint('publicCouponBundleProvider failed: $error');
    ref.read(_lastPublicCouponScanKeyProvider.notifier).state = requestKey;
    return const PublicCouponBundle();
  }
});

final publicCouponCacheStatusProvider = Provider<PublicCouponCacheStatus>((
  ref,
) {
  final blocked = ref.watch(_publicCouponCacheReadBlockedProvider);
  final meta =
      ref.watch(firebasePublicCouponCacheMetaProvider).valueOrNull ??
      const _PublicCouponCacheMeta();
  final visibleDeals = ref.watch(publicCouponDealRecordsProvider);
  final scanJob = ref.watch(firebasePublicCouponScanJobProvider).valueOrNull;
  final legacyFallbackActive = ref.watch(
    publicCouponLegacyFallbackActiveProvider,
  );
  final scanStillDrivingUi = scanJob != null && scanJob.isEffectivelyActive;

  return PublicCouponCacheStatus(
    cacheBlocked: blocked,
    cachedDealCount: math.max(meta.dealCount, visibleDeals.length),
    lastUpdatedAt: meta.lastUpdatedAt ?? scanJob?.completedAt,
    nativeScanInProgress: scanStillDrivingUi,
    liveDealCount: visibleDeals.length,
    legacyFallbackActive: legacyFallbackActive,
    processedSourceCount: scanJob?.processedCandidateCount ?? 0,
    sourceCount: scanJob?.candidateCount ?? 0,
    progressMessage: scanJob?.progressMessage ?? '',
  );
});

final storiesProvider = Provider<List<Story>>((ref) {
  final user = ref.watch(currentUserProvider);
  final area = ref.watch(discoverSearchAreaProvider);
  final radiusKm = ref.watch(settingsControllerProvider).distanceKm;
  final businessesById = <String, Business>{
    for (final business in ref.watch(businessesProvider)) business.id: business,
  };
  return ref
      .watch(repositoryProvider)
      .stories
      .where(
        (story) => _isStoryVisibleInArea(
          story,
          user: user,
          area: area,
          radiusKm: radiusKm,
          business: businessesById[story.businessId],
        ),
      )
      .toList(growable: false);
});

final categoryCountsProvider = Provider<Map<DealCategory, int>>((ref) {
  final deals = ref.watch(dealsProvider);
  return <DealCategory, int>{
    for (final category in DealCategory.values)
      category: deals.where((deal) => deal.category == category).length,
  };
});

final dealByIdProvider = Provider.family<Deal, String>((ref, id) {
  final deals = ref.watch(dealsProvider);
  for (final deal in deals) {
    if (deal.id == id) {
      return deal;
    }
  }
  final pinnedLookup =
      ref.watch(pinnedPublicCouponLookupProvider).valueOrNull ??
      const _PinnedPublicCouponLookup();
  for (final record in pinnedLookup.dealRecords) {
    if (record.deal.id == id) {
      return _sanitizeDealForUi(record.deal);
    }
  }
  return _sanitizeDealForUi(ref.watch(repositoryProvider).dealById(id));
});

final businessByIdProvider = Provider.family<Business, String>((ref, id) {
  final directBusiness = ref
      .watch(firebaseBusinessByIdProvider(id))
      .valueOrNull;
  final mergedBusinesses = ref.watch(businessesProvider);
  final repository = ref.watch(repositoryProvider);
  Business? mergedBusiness;
  for (final business in mergedBusinesses) {
    if (business.id == id) {
      mergedBusiness = business;
      break;
    }
  }
  if (mergedBusiness == null) {
    final pinnedLookup =
        ref.watch(pinnedPublicCouponLookupProvider).valueOrNull ??
        const _PinnedPublicCouponLookup();
    for (final business in pinnedLookup.businesses) {
      if (business.id == id) {
        mergedBusiness = business;
        break;
      }
    }
  }
  final baseBusiness =
      directBusiness ?? mergedBusiness ?? repository.businessById(id);
  final session = ref.watch(sessionControllerProvider);
  final draft = ref.watch(ownedBusinessDraftProvider);

  if (session.ownedBusinessId == id &&
      draft != null &&
      draft.businessId == id) {
    final updatedBranch = baseBusiness.primaryBranch.copyWith(
      name: draft.name,
      city: draft.city,
      district: draft.district,
      address: draft.address,
    );

    return _sanitizeBusinessForUi(
      baseBusiness.copyWith(
        name: draft.name,
        tagline: draft.tagline,
        shortDescription: draft.shortDescription,
        description: draft.description,
        city: draft.city,
        district: draft.district,
        branches: <Branch>[updatedBranch, ...baseBusiness.branches.skip(1)],
        website: draft.website,
        phone: draft.phone,
        contactEmail: draft.contactEmail,
        legalEntityName: draft.legalEntityName,
        imprintInfo: draft.imprintInfo,
      ),
    );
  }

  return _sanitizeBusinessForUi(baseBusiness);
});

final storyByIdProvider = Provider.family<Story, String>((ref, id) {
  return ref.watch(repositoryProvider).storyById(id);
});

final businessDealsProvider = Provider.family<List<Deal>, String>((
  ref,
  businessId,
) {
  final session = ref.watch(sessionControllerProvider);
  final includePaused =
      session.businessModeEnabled && session.ownedBusinessId == businessId;
  final nativeDeals = ref
      .watch(repositoryProvider)
      .dealsForBusiness(businessId, includePaused: includePaused);
  final publicDeals = ref
      .watch(publicCouponDealRecordsProvider)
      .map((entry) => entry.deal)
      .where((deal) => deal.businessId == businessId)
      .toList(growable: false);
  final pinnedPublicDeals =
      (ref.watch(pinnedPublicCouponLookupProvider).valueOrNull?.dealRecords ??
              const <DealRecord>[])
          .map((entry) => entry.deal)
          .where((deal) => deal.businessId == businessId)
          .toList(growable: false);
  return _mergeDeals(nativeDeals, _mergeDeals(publicDeals, pinnedPublicDeals));
});

final similarDealsProvider = Provider.family<List<Deal>, String>((ref, dealId) {
  final deals = ref.watch(dealsProvider);
  final current = ref.watch(dealByIdProvider(dealId));
  return deals
      .where(
        (deal) =>
            deal.id != dealId &&
            (deal.category == current.category || deal.city == current.city),
      )
      .take(6)
      .toList(growable: false);
});

final homeFeedSectionsProvider = FutureProvider<List<FeedSection>>((ref) async {
  return const <FeedSection>[];
});

final feedDealsProvider = Provider<List<Deal>>((ref) {
  final filter = ref.watch(feedFilterProvider);
  final user = ref.watch(currentUserProvider);
  final deals = ref.watch(dealsProvider);
  return _filterDeals(deals, filter: filter, user: user);
});

final featuredBusinessesProvider = Provider<List<Business>>((ref) {
  final user = ref.watch(currentUserProvider);
  return ref
      .watch(businessesProvider)
      .where(
        (business) =>
            user.followingBusinessIds.contains(business.id) ||
            business.isTrending ||
            business.city == user.city,
      )
      .take(6)
      .toList(growable: false);
});

final savedDealListProvider = Provider<List<Deal>>((ref) {
  final saved = ref.watch(savedDealsProvider);
  final wallet = ref.watch(walletProvider);
  final deals = ref.watch(dealsProvider);
  final pinnedDeals =
      (ref.watch(pinnedPublicCouponLookupProvider).valueOrNull?.dealRecords ??
              const <DealRecord>[])
          .map((entry) => entry.deal)
          .toList(growable: false);
  return _mergeDeals(deals, pinnedDeals)
      .where((deal) => saved.contains(deal.id))
      .map((deal) => _enrichDealStatsForUser(deal, saved, wallet))
      .toList()
    ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
});

final activeWalletProvider = Provider<List<Redemption>>((ref) {
  return ref
      .watch(walletProvider)
      .where((item) => item.status == RedemptionStatus.active)
      .toList();
});

final offlineWalletProvider = Provider<List<Redemption>>((ref) {
  return ref
      .watch(activeWalletProvider)
      .where((item) => item.offlineReady)
      .toList(growable: false);
});

final walletHistoryProvider = Provider<List<Redemption>>((ref) {
  return ref
      .watch(walletProvider)
      .where((item) => item.status != RedemptionStatus.active)
      .toList();
});

final totalSavedAmountCentsProvider = Provider<int>((ref) {
  return ref
      .watch(walletProvider)
      .where((item) => item.status == RedemptionStatus.redeemed)
      .fold<int>(0, (sum, item) => sum + item.savedAmountCents);
});

final businessRedemptionsProvider = Provider<List<Redemption>>((ref) {
  if (ref.watch(currentUserProvider).accountType != AccountType.business) {
    return const <Redemption>[];
  }
  final businessId = ref.watch(ownedBusinessProvider).id;
  return ref
          .watch(firebaseBusinessRedemptionsProvider(businessId))
          .valueOrNull ??
      const <Redemption>[];
});

final unreadNotificationCountProvider = Provider<int>((ref) {
  return ref.watch(notificationsProvider).where((item) => !item.isRead).length;
});

final userLevelProvider = Provider<int>((ref) {
  final points = ref.watch(currentUserProvider).points;
  return (points ~/ 250) + 1;
});

final nextLevelTargetProvider = Provider<int>((ref) {
  final level = ref.watch(userLevelProvider);
  return level * 250;
});

final cityLeaderboardProvider = Provider<List<LeaderboardEntry>>((ref) {
  final user = ref.watch(currentUserProvider);
  final reviewEntriesById = <String, LeaderboardEntry>{};
  for (final review in ref.watch(reviewsProvider)) {
    if (review.city != user.city || review.authorId.trim().isEmpty) {
      continue;
    }
    final previous = reviewEntriesById[review.authorId];
    final points = review.rating * 12 + review.helpfulCount * 8 + 20;
    reviewEntriesById[review.authorId] = LeaderboardEntry(
      id: review.authorId,
      name: review.authorName,
      city: review.city,
      points: (previous?.points ?? 0) + points,
      rank: 0,
      freeCouponCredits: previous?.freeCouponCredits ?? 0,
      isCurrentUser: review.authorId == user.id,
    );
  }
  final entries =
      ref
          .watch(firebaseUsersProvider)
          .valueOrNull
          ?.where((entry) => entry.user.city == user.city)
          .map(
            (entry) => LeaderboardEntry(
              id: entry.user.id,
              name: entry.user.name,
              city: entry.user.city,
              points: entry.user.points,
              rank: 0,
              freeCouponCredits: entry.user.freeCouponCredits,
              isCurrentUser: entry.user.id == user.id,
            ),
          )
          .toList(growable: true) ??
      <LeaderboardEntry>[];
  for (final reviewEntry in reviewEntriesById.values) {
    final existingIndex = entries.indexWhere(
      (entry) => entry.id == reviewEntry.id,
    );
    if (existingIndex >= 0) {
      final existing = entries[existingIndex];
      entries[existingIndex] = existing.copyWith(
        points: existing.points + reviewEntry.points,
      );
    } else {
      entries.add(reviewEntry);
    }
  }
  final existingIndex = entries.indexWhere((entry) => entry.id == user.id);
  final currentUserEntry = LeaderboardEntry(
    id: user.id,
    name: user.name,
    city: user.city,
    points: user.points,
    rank: 0,
    freeCouponCredits: user.freeCouponCredits,
    isCurrentUser: true,
  );

  if (existingIndex >= 0) {
    entries[existingIndex] = currentUserEntry;
  } else {
    entries.add(currentUserEntry);
  }

  entries.sort((a, b) => b.points.compareTo(a.points));
  return List<LeaderboardEntry>.generate(entries.length, (index) {
    final entry = entries[index];
    return entry.copyWith(rank: index + 1);
  });
});

final recommendedDealsProvider = Provider<List<Deal>>((ref) {
  final user = ref.watch(currentUserProvider);
  final savedIds = ref.watch(savedDealsProvider);
  final deals = ref.watch(dealsProvider).toList(growable: true);

  int score(Deal deal) {
    var value = 0;
    if (user.favoriteCategories.contains(deal.category)) {
      value += 5;
    }
    if (user.followingBusinessIds.contains(deal.businessId)) {
      value += 4;
    }
    if (deal.city == user.city) {
      value += 3;
    }
    if (deal.tags.contains(OfferTag.popular)) {
      value += 2;
    }
    if (deal.tags.contains(OfferTag.fresh)) {
      value += 2;
    }
    if (deal.isExpiringSoon) {
      value += 1;
    }
    if (savedIds.contains(deal.id)) {
      value -= 2;
    }
    return value;
  }

  deals.sort((a, b) {
    final scoreResult = score(b).compareTo(score(a));
    if (scoreResult != 0) {
      return scoreResult;
    }
    return a.distanceKm.compareTo(b.distanceKm);
  });

  return deals.take(6).toList(growable: false);
});

final influencerDealsProvider = Provider<List<Deal>>((ref) {
  final deals = ref
      .watch(dealsProvider)
      .where(
        (deal) =>
            deal.tags.contains(OfferTag.popular) ||
            deal.tags.contains(OfferTag.exclusive) ||
            deal.tags.contains(OfferTag.topRated),
      )
      .toList(growable: true);

  int score(Deal deal) {
    return (deal.tags.contains(OfferTag.popular) ? 3 : 0) +
        (deal.tags.contains(OfferTag.exclusive) ? 2 : 0) +
        (deal.tags.contains(OfferTag.topRated) ? 1 : 0) +
        deal.stats.friendCount;
  }

  deals.sort((a, b) => score(b).compareTo(score(a)));
  return deals.take(4).toList(growable: false);
});

final dealReviewsProvider = Provider.family<List<AppReview>, String>((
  ref,
  dealId,
) {
  final reviews = ref.watch(reviewsProvider);
  return reviews
      .where((review) => review.dealId == dealId)
      .toList(growable: true)
    ..sort((a, b) {
      final aDate =
          a.updatedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate =
          b.updatedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final dateCompare = bDate.compareTo(aDate);
      if (dateCompare != 0) {
        return dateCompare;
      }
      return b.helpfulCount.compareTo(a.helpfulCount);
    });
});

final businessReviewsProvider = Provider.family<List<AppReview>, String>((
  ref,
  businessId,
) {
  final reviews = ref.watch(reviewsProvider);
  return reviews
      .where((review) => review.businessId == businessId)
      .toList(growable: true)
    ..sort((a, b) {
      final aDate =
          a.updatedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate =
          b.updatedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final dateCompare = bDate.compareTo(aDate);
      if (dateCompare != 0) {
        return dateCompare;
      }
      return b.helpfulCount.compareTo(a.helpfulCount);
    });
});

final searchResultsProvider = Provider<List<Deal>>((ref) {
  final state = ref.watch(searchControllerProvider);
  final settingsDistanceKm = ref.watch(settingsControllerProvider).distanceKm;
  final deals = ref.watch(dealsProvider);
  final businesses = ref.watch(businessesProvider);
  return _searchDeals(
    deals,
    businesses: businesses,
    query: state.query,
    category: state.category,
    onlyToday: state.onlyToday,
    onlyExclusive: state.onlyExclusive,
    openNowOnly: state.openNowOnly,
    popularOnly: state.popularOnly,
    freshOnly: state.freshOnly,
    maxDistanceKm: math.min(state.maxDistanceKm, settingsDistanceKm),
    minRating: state.minRating,
  );
});

List<Deal> _mergeDeals(List<Deal> nativeDeals, List<Deal> publicDeals) {
  final merged = <String, Deal>{};
  for (final deal in nativeDeals) {
    merged[_dealIdentityKey(deal)] = deal;
  }
  for (final deal in publicDeals) {
    merged.putIfAbsent(_dealIdentityKey(deal), () => deal);
  }
  final values = merged.values.toList(growable: false);
  values.sort((a, b) {
    final priorityResult = _dealPriorityScore(
      b,
    ).compareTo(_dealPriorityScore(a));
    if (priorityResult != 0) {
      return priorityResult;
    }
    return a.distanceKm.compareTo(b.distanceKm);
  });
  return values;
}

List<Deal> _withLiveDealDistances(
  List<Deal> deals, {
  required List<Business> businesses,
  required NearbySearchArea area,
}) {
  final businessesById = <String, Business>{
    for (final business in businesses) business.id: business,
  };
  return deals
      .map((deal) {
        final business = businessesById[deal.businessId];
        if (business == null) {
          return deal;
        }
        final distanceKm = _distanceBetweenKm(
          area.latitude,
          area.longitude,
          business.primaryBranch.latitude,
          business.primaryBranch.longitude,
        );
        if (!distanceKm.isFinite) {
          return deal;
        }
        return deal.copyWith(distanceKm: distanceKm);
      })
      .toList(growable: false);
}

List<Business> _withLiveBusinessDistances(
  List<Business> businesses, {
  required NearbySearchArea area,
}) {
  return businesses
      .map((business) {
        final branch = business.primaryBranch;
        final distanceKm = _distanceBetweenKm(
          area.latitude,
          area.longitude,
          branch.latitude,
          branch.longitude,
        );
        if (!distanceKm.isFinite) {
          return business;
        }
        return business.copyWith(distanceKm: distanceKm);
      })
      .toList(growable: false);
}

bool _isDealVisibleInArea(Deal deal, {required double radiusKm}) {
  if (!deal.validUntil.isAfter(DateTime.now())) {
    return false;
  }
  final maxRadiusKm = radiusKm <= 0
      ? maxSearchRadiusKm
      : radiusKm.clamp(1.0, maxSearchRadiusKm).toDouble();
  return deal.distanceKm.isFinite &&
      deal.distanceKm >= 0 &&
      deal.distanceKm <= maxRadiusKm;
}

bool _isBusinessVisibleInArea(
  Business business, {
  required NearbySearchArea area,
  required double radiusKm,
}) {
  final maxRadiusKm = radiusKm <= 0
      ? maxSearchRadiusKm
      : radiusKm.clamp(1.0, maxSearchRadiusKm).toDouble();
  final distanceKm = business.distanceKm.isFinite
      ? business.distanceKm
      : _distanceBetweenKm(
          area.latitude,
          area.longitude,
          business.primaryBranch.latitude,
          business.primaryBranch.longitude,
        );
  return distanceKm.isFinite && distanceKm >= 0 && distanceKm <= maxRadiusKm;
}

bool _isPublicCouponDealVisibleInArea(
  Deal deal, {
  required NearbySearchArea area,
  required double radiusKm,
}) {
  final maxRadiusKm = radiusKm <= 0
      ? maxSearchRadiusKm
      : radiusKm.clamp(1.0, maxSearchRadiusKm).toDouble();
  if (deal.distanceKm.isFinite && deal.distanceKm <= maxRadiusKm) {
    return true;
  }
  return false;
}

bool _isPublicCouponBusinessVisibleInArea(
  Business business, {
  required NearbySearchArea area,
  required double radiusKm,
}) {
  final maxRadiusKm = radiusKm <= 0
      ? maxSearchRadiusKm
      : radiusKm.clamp(1.0, maxSearchRadiusKm).toDouble();
  final distanceKm = _distanceBetweenKm(
    area.latitude,
    area.longitude,
    business.primaryBranch.latitude,
    business.primaryBranch.longitude,
  );
  if (distanceKm.isFinite && distanceKm <= maxRadiusKm) {
    return true;
  }
  return false;
}

bool _isStoryVisibleInArea(
  Story story, {
  required User user,
  required NearbySearchArea area,
  required double radiusKm,
  Business? business,
}) {
  final maxRadiusKm = radiusKm <= 0
      ? maxSearchRadiusKm
      : radiusKm.clamp(1.0, maxSearchRadiusKm).toDouble();
  if (business != null) {
    final distanceKm = _distanceBetweenKm(
      area.latitude,
      area.longitude,
      business.primaryBranch.latitude,
      business.primaryBranch.longitude,
    );
    if (distanceKm.isFinite) {
      return distanceKm <= maxRadiusKm;
    }
    return false;
  }
  return false;
}

bool _isGenericLocationLabel(String value) {
  final normalized = _normalizeLocationLabel(value);
  return normalized.isEmpty ||
      normalized == 'dein viertel' ||
      normalized == 'in deiner naehe' ||
      normalized == 'deine naehe' ||
      normalized == 'deutschlandweit';
}

String _normalizeLocationLabel(String value) {
  return _repairUiCouponTextSafe(value)
      .toLowerCase()
      .replaceAll('\u00e4', 'ae')
      .replaceAll('\u00f6', 'oe')
      .replaceAll('\u00fc', 'ue')
      .replaceAll('\u00df', 'ss')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}

double _distanceBetweenKm(
  double startLat,
  double startLng,
  double endLat,
  double endLng,
) {
  const earthRadiusKm = 6371.0;
  final deltaLat = _degToRad(endLat - startLat);
  final deltaLng = _degToRad(endLng - startLng);
  final a =
      math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
      math.cos(_degToRad(startLat)) *
          math.cos(_degToRad(endLat)) *
          math.sin(deltaLng / 2) *
          math.sin(deltaLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusKm * c;
}

double _degToRad(double degrees) => degrees * 0.017453292519943295;

List<Business> _mergeBusinesses(
  List<Business> nativeBusinesses,
  List<Business> publicBusinesses,
) {
  final merged = <String, Business>{};
  for (final business in nativeBusinesses) {
    merged[business.id] = business;
  }
  for (final business in publicBusinesses) {
    merged.putIfAbsent(business.id, () => business);
  }
  return merged.values.toList(growable: false);
}

List<Business> _dedupePublicCouponBusinesses(List<Business> items) {
  final unique = <String, Business>{};
  for (final business in items) {
    unique.putIfAbsent(_businessIdentityKey(business), () => business);
  }
  final values = unique.values.toList(growable: false)
    ..sort((a, b) => a.name.compareTo(b.name));
  return values;
}

List<DealRecord> _dedupePublicCouponDealRecords(List<DealRecord> items) {
  final ordered = items.toList(growable: false)
    ..sort((a, b) => a.deal.distanceKm.compareTo(b.deal.distanceKm));
  final unique = <String, DealRecord>{};
  for (final record in ordered) {
    unique.putIfAbsent(_publicDealIdentityKey(record.deal), () => record);
  }
  return unique.values.toList(growable: false)
    ..sort((a, b) => a.deal.distanceKm.compareTo(b.deal.distanceKm));
}

bool _sameBusinessListById(List<Business> a, List<Business> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index++) {
    if (a[index].id != b[index].id) {
      return false;
    }
  }
  return true;
}

bool _sameDealRecordListById(List<DealRecord> a, List<DealRecord> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index++) {
    if (a[index].deal.id != b[index].deal.id) {
      return false;
    }
  }
  return true;
}

String _businessIdentityKey(Business business) {
  final normalizedWebsite = _normalizeLocationLabel(business.website);
  if (normalizedWebsite.isNotEmpty) {
    return 'website|$normalizedWebsite';
  }
  return [
    _normalizeLocationLabel(business.name),
    _normalizeLocationLabel(business.primaryBranch.address),
    business.primaryBranch.latitude.toStringAsFixed(4),
    business.primaryBranch.longitude.toStringAsFixed(4),
  ].join('|');
}

String _publicDealIdentityKey(Deal deal) {
  if (!deal.isThirdParty) {
    return _dealIdentityKey(deal);
  }
  final sourceUri = Uri.tryParse(deal.sourceUrl);
  final source = _normalizeLocationLabel(
    sourceUri != null && sourceUri.host.isNotEmpty
        ? sourceUri.host
        : (deal.sourceUrl.isNotEmpty ? deal.sourceUrl : deal.sourceLabel),
  );
  final title = _normalizeLocationLabel(
    _stripHtmlForUi(deal.title, maxLength: 72),
  );
  final description = _normalizeLocationLabel(
    _stripHtmlForUi(deal.description, maxLength: 180),
  );
  final summary = description
      .split(' ')
      .where((token) => token.isNotEmpty)
      .take(10)
      .join(' ');
  return [
    source,
    _normalizeLocationLabel(deal.city),
    title.isNotEmpty ? title : summary,
    deal.savingsPercent.toString(),
  ].join('|');
}

String _dealIdentityKey(Deal deal) {
  if (deal.source == DealSource.thirdParty) {
    return _publicDealIdentityKey(deal);
  }
  if (deal.sourceUrl.isNotEmpty) {
    return '${deal.businessId}|${deal.sourceUrl}|${deal.title}'.toLowerCase();
  }
  return deal.id;
}

int _dealPriorityScore(Deal deal) {
  var score = 0;
  if (deal.tags.contains(OfferTag.today)) {
    score += 5;
  }
  if (deal.tags.contains(OfferTag.fresh)) {
    score += 4;
  }
  if (deal.tags.contains(OfferTag.almostGone)) {
    score += 3;
  }
  if (deal.type == DealType.happyHour || deal.type == DealType.twoForOne) {
    score += 2;
  }
  if (deal.source == DealSource.thirdParty) {
    score += 1;
  }
  return score;
}

List<Deal> _filterDeals(
  List<Deal> deals, {
  required FeedFilter filter,
  required User user,
}) {
  final preferred = user.preferences.interests;
  final maxDistanceKm = user.preferences.radiusKm <= 0
      ? maxSearchRadiusKm
      : user.preferences.radiusKm.clamp(1.0, maxSearchRadiusKm).toDouble();
  final visibleDeals = deals
      .where(
        (deal) =>
            deal.distanceKm.isFinite &&
            deal.distanceKm >= 0 &&
            deal.distanceKm <= maxDistanceKm &&
            deal.validUntil.isAfter(DateTime.now()),
      )
      .toList(growable: false);

  List<Deal> filtered = switch (filter) {
    FeedFilter.forYou =>
      visibleDeals
          .where((deal) => preferred.contains(deal.category))
          .followedBy(
            visibleDeals.where((deal) => !preferred.contains(deal.category)),
          )
          .toList(),
    FeedFilter.nearby =>
      visibleDeals.toList()
        ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm)),
    FeedFilter.trending =>
      visibleDeals.toList()..sort(
        (a, b) => b.stats.todayRedemptions.compareTo(a.stats.todayRedemptions),
      ),
    FeedFilter.food =>
      visibleDeals
          .where(
            (deal) =>
                deal.category == DealCategory.food ||
                deal.category == DealCategory.cafe ||
                deal.category == DealCategory.breakfast ||
                deal.category == DealCategory.drinks,
          )
          .toList(),
    FeedFilter.beauty =>
      visibleDeals
          .where(
            (deal) =>
                deal.category == DealCategory.beauty ||
                deal.category == DealCategory.wellness ||
                deal.category == DealCategory.health,
          )
          .toList(),
    FeedFilter.shopping =>
      visibleDeals
          .where(
            (deal) =>
                deal.category == DealCategory.shopping ||
                deal.category == DealCategory.online ||
                deal.category == DealCategory.home ||
                deal.category == DealCategory.services,
          )
          .toList(),
    FeedFilter.leisure =>
      visibleDeals
          .where(
            (deal) =>
                deal.category == DealCategory.leisure ||
                deal.category == DealCategory.experiences ||
                deal.category == DealCategory.parks ||
                deal.category == DealCategory.nightlife ||
                deal.category == DealCategory.wellness ||
                deal.category == DealCategory.culture ||
                deal.category == DealCategory.family ||
                deal.category == DealCategory.travel,
          )
          .toList(),
    FeedFilter.fresh =>
      visibleDeals.where((deal) => deal.tags.contains(OfferTag.fresh)).toList(),
    FeedFilter.today =>
      visibleDeals
          .where(
            (deal) => deal.tags.contains(OfferTag.today) || deal.isExpiringSoon,
          )
          .toList(),
  };

  if (filtered.isEmpty) {
    filtered = visibleDeals.toList();
  }

  return filtered;
}

List<Deal> _searchDeals(
  List<Deal> deals, {
  required List<Business> businesses,
  String query = '',
  DealCategory? category,
  bool onlyToday = false,
  bool onlyExclusive = false,
  bool openNowOnly = false,
  bool popularOnly = false,
  bool freshOnly = false,
  double maxDistanceKm = maxSearchRadiusKm,
  double minRating = 0,
}) {
  final normalized = query.trim().toLowerCase();
  final businessesById = <String, Business>{
    for (final business in businesses) business.id: business,
  };

  return deals
      .where((deal) {
        final business = businessesById[deal.businessId];
        final matchesQuery =
            normalized.isEmpty ||
            deal.title.toLowerCase().contains(normalized) ||
            deal.subtitle.toLowerCase().contains(normalized) ||
            (business?.name.toLowerCase().contains(normalized) ?? false) ||
            (business?.city.toLowerCase().contains(normalized) ?? false) ||
            (business?.district.toLowerCase().contains(normalized) ?? false) ||
            deal.category.label.toLowerCase().contains(normalized) ||
            deal.type.label.toLowerCase().contains(normalized);

        final matchesCategory = category == null || deal.category == category;
        final matchesToday =
            !onlyToday ||
            deal.tags.contains(OfferTag.today) ||
            deal.isExpiringSoon;
        final matchesExclusive =
            !onlyExclusive || deal.tags.contains(OfferTag.exclusive);
        final matchesOpen = !openNowOnly || deal.openNow;
        final matchesPopular =
            !popularOnly || deal.tags.contains(OfferTag.popular);
        final matchesFresh = !freshOnly || deal.tags.contains(OfferTag.fresh);
        final matchesDistance = deal.distanceKm <= maxDistanceKm;
        final matchesRating = deal.stats.rating >= minRating;

        return matchesQuery &&
            matchesCategory &&
            matchesToday &&
            matchesExclusive &&
            matchesOpen &&
            matchesPopular &&
            matchesFresh &&
            matchesDistance &&
            matchesRating;
      })
      .toList(growable: false)
    ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
}

final ownedBusinessProvider = Provider<Business>((ref) {
  final session = ref.watch(sessionControllerProvider);
  final authUser = ref.watch(authUserProvider);
  final fallbackOwnedBusinessId =
      ref.watch(firebaseOwnedBusinessFallbackIdProvider).valueOrNull?.trim() ??
      '';
  final inferredOwnedBusinessId = authUser != null && !authUser.isAnonymous
      ? 'business_${authUser.uid}'
      : '';

  final candidateBusinessIds = <String>[
    session.ownedBusinessId.trim(),
    fallbackOwnedBusinessId,
    inferredOwnedBusinessId,
  ].where((entry) => entry.isNotEmpty).toSet().toList(growable: false);

  if (candidateBusinessIds.isEmpty) {
    return ref
        .watch(repositoryProvider)
        .fallbackBusiness(
          id: inferredOwnedBusinessId.isNotEmpty
              ? inferredOwnedBusinessId
              : 'business_${session.user.id.isEmpty ? 'draft' : session.user.id}',
        );
  }

  for (final businessId in candidateBusinessIds) {
    final directBusiness = ref
        .watch(firebaseBusinessByIdProvider(businessId))
        .valueOrNull;
    if (directBusiness != null) {
      return ref.watch(businessByIdProvider(businessId));
    }
  }

  return ref.watch(businessByIdProvider(candidateBusinessIds.first));
});

final ownedBusinessCanPublishProvider = Provider<bool>((ref) {
  final business = ref.watch(ownedBusinessProvider);
  final authUser = ref.watch(authUserProvider);
  return _businessCanPublishContent(business, authUser);
});

bool _businessCanPublishContent(
  Business business,
  firebase_auth.User? authUser,
) {
  if (authUser == null || authUser.isAnonymous || !authUser.emailVerified) {
    return false;
  }

  if (business.verificationStatus.isVerified) {
    return true;
  }

  if (business.googleProfileLink.isLinked &&
      business.googleProfileLink.grantsDashboardAccess) {
    final authEmail = (authUser.email ?? '').trim().toLowerCase();
    final googleEmail = business.googleProfileLink.googleUserEmail
        .trim()
        .toLowerCase();
    return googleEmail.isEmpty || authEmail.isEmpty || authEmail == googleEmail;
  }

  final authEmail = (authUser.email ?? '').trim().toLowerCase();
  final businessEmail = business.contactEmail.trim().toLowerCase();
  if (authEmail.isEmpty ||
      businessEmail.isEmpty ||
      authEmail != businessEmail) {
    return false;
  }

  final uri = Uri.tryParse(
    business.website.startsWith('http://') ||
            business.website.startsWith('https://')
        ? business.website
        : 'https://${business.website}',
  );
  final host = (uri?.host ?? '').trim().toLowerCase();
  if (host.isEmpty) {
    return false;
  }

  final normalizedHost = host.startsWith('www.') ? host.substring(4) : host;
  final emailDomain = authEmail.split('@').last;
  return emailDomain == normalizedHost ||
      emailDomain.endsWith('.$normalizedHost') ||
      normalizedHost.endsWith('.$emailDomain');
}
