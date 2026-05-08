import 'dart:typed_data';

import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/services/device_session_service.dart';
import '../firebase/firebase_mappers.dart';
import '../services/firebase_paths.dart';
import '../services/public_coupon_scanner_service.dart';
import '../../domain/models/business_models.dart';
import '../../domain/models/deal_models.dart';
import '../../domain/models/engagement_models.dart';
import '../../domain/models/feed_models.dart';
import '../../domain/models/notification_models.dart';
import '../../domain/models/story_models.dart';
import '../../domain/models/user_models.dart';
import '../../firebase_options.dart';

enum DeviceLoginStatus { success, approvalRequired }

class DeviceLoginResult {
  const DeviceLoginResult._({
    required this.status,
    this.email = '',
    this.deviceLabel = '',
  });

  const DeviceLoginResult.success() : this._(status: DeviceLoginStatus.success);

  const DeviceLoginResult.approvalRequired({
    required String email,
    required String deviceLabel,
  }) : this._(
         status: DeviceLoginStatus.approvalRequired,
         email: email,
         deviceLabel: deviceLabel,
       );

  final DeviceLoginStatus status;
  final String email;
  final String deviceLabel;

  bool get requiresApproval => status == DeviceLoginStatus.approvalRequired;
}

class FirebaseAppRepository {
  FirebaseAppRepository({
    required this.auth,
    required this.firestore,
    required this.storage,
    required List<Business> businesses,
    required List<DealRecord> dealRecords,
    required List<Story> stories,
    required List<NotificationItem> notifications,
    required List<Redemption> redemptions,
    required List<AppReview> reviews,
    required User currentUser,
  }) : _businesses = List<Business>.unmodifiable(businesses),
       _dealRecords = List<DealRecord>.unmodifiable(dealRecords),
       _stories = List<Story>.unmodifiable(stories),
       _notifications = List<NotificationItem>.unmodifiable(notifications),
       _redemptions = List<Redemption>.unmodifiable(redemptions),
       _reviews = List<AppReview>.unmodifiable(reviews),
       _currentUser = currentUser;

  final firebase_auth.FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FirebaseStorage storage;

  final List<Business> _businesses;
  final List<DealRecord> _dealRecords;
  final List<Story> _stories;
  final List<NotificationItem> _notifications;
  final List<Redemption> _redemptions;
  final List<AppReview> _reviews;
  final User _currentUser;

  List<Business> get businesses => _businesses;
  List<DealRecord> get dealRecords => _dealRecords;
  List<Deal> get deals => _dealRecords
      .where((entry) => !entry.isPaused)
      .map((entry) => entry.deal)
      .toList(growable: false);
  List<Story> get stories => _stories;
  List<NotificationItem> get notifications => _notifications;
  List<Redemption> get redemptions => _redemptions;
  List<AppReview> get reviews => _reviews;
  User get currentUser => _currentUser;

  Set<String> get pausedDealIds => _dealRecords
      .where((entry) => entry.isPaused)
      .map((entry) => entry.deal.id)
      .toSet();

  Business businessById(String id) {
    return _businesses.firstWhere(
      (business) => business.id == id,
      orElse: () => fallbackBusiness(id: id),
    );
  }

  Deal dealById(String id) {
    return _dealRecords
        .map((entry) => entry.deal)
        .firstWhere(
          (deal) => deal.id == id,
          orElse: () => fallbackDeal(id: id),
        );
  }

  Story storyById(String id) {
    return _stories.firstWhere(
      (story) => story.id == id,
      orElse: () => fallbackStory(id: id),
    );
  }

  List<Deal> dealsForBusiness(String businessId, {bool includePaused = false}) {
    return _dealRecords
        .where((entry) => entry.deal.businessId == businessId)
        .where((entry) => includePaused || !entry.isPaused)
        .map((entry) => entry.deal)
        .toList(growable: false);
  }

  List<Story> storiesForBusiness(String businessId) {
    return _stories
        .where((story) => story.businessId == businessId)
        .toList(growable: false);
  }

  List<Deal> similarDeals(String dealId) {
    final current = dealById(dealId);
    return deals
        .where(
          (deal) =>
              deal.id != dealId &&
              (deal.category == current.category || deal.city == current.city),
        )
        .take(6)
        .toList(growable: false);
  }

  List<Business> featuredBusinesses(User user) {
    return _businesses
        .where(
          (business) =>
              user.followingBusinessIds.contains(business.id) ||
              business.isTrending ||
              business.city == user.city,
        )
        .take(6)
        .toList(growable: false);
  }

  Map<DealCategory, int> categoryCounts() {
    return <DealCategory, int>{
      for (final category in DealCategory.values)
        category: deals.where((deal) => deal.category == category).length,
    };
  }

  List<Deal> dealsForFilter(FeedFilter filter, {required User user}) {
    final preferred = user.preferences.interests;

    List<Deal> filtered = switch (filter) {
      FeedFilter.forYou =>
        deals
            .where((deal) => preferred.contains(deal.category))
            .followedBy(
              deals.where((deal) => !preferred.contains(deal.category)),
            )
            .toList(),
      FeedFilter.nearby => deals.toList()..sort(_sortByDistance),
      FeedFilter.trending =>
        deals.toList()..sort(
          (a, b) =>
              b.stats.todayRedemptions.compareTo(a.stats.todayRedemptions),
        ),
      FeedFilter.food =>
        deals
            .where(
              (deal) =>
                  deal.category == DealCategory.food ||
                  deal.category == DealCategory.cafe ||
                  deal.category == DealCategory.breakfast ||
                  deal.category == DealCategory.drinks,
            )
            .toList(),
      FeedFilter.beauty =>
        deals
            .where(
              (deal) =>
                  deal.category == DealCategory.beauty ||
                  deal.category == DealCategory.wellness ||
                  deal.category == DealCategory.health,
            )
            .toList(),
      FeedFilter.shopping =>
        deals
            .where(
              (deal) =>
                  deal.category == DealCategory.shopping ||
                  deal.category == DealCategory.online ||
                  deal.category == DealCategory.home ||
                  deal.category == DealCategory.services,
            )
            .toList(),
      FeedFilter.leisure =>
        deals
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
        deals.where((deal) => deal.tags.contains(OfferTag.fresh)).toList(),
      FeedFilter.today =>
        deals
            .where(
              (deal) =>
                  deal.tags.contains(OfferTag.today) || deal.isExpiringSoon,
            )
            .toList(),
    };

    if (filtered.isEmpty) {
      filtered = deals.toList();
    }

    return filtered;
  }

  List<FeedSection> buildFeedSections(FeedFilter filter, {required User user}) {
    final source = dealsForFilter(filter, user: user);
    if (source.isEmpty) {
      return const <FeedSection>[];
    }

    final heroDeal = source.first;
    final trending = dealsForFilter(FeedFilter.trending, user: user).take(4);
    final nearby = dealsForFilter(FeedFilter.nearby, user: user).take(4);
    final hidden = deals
        .where((deal) => deal.tags.contains(OfferTag.hiddenGem))
        .followedBy(deals.where((deal) => businessById(deal.businessId).isNew))
        .take(4);
    final social = deals
        .where(
          (deal) =>
              user.followingBusinessIds.contains(deal.businessId) ||
              deal.stats.friendCount > 2,
        )
        .take(4);

    return <FeedSection>[
      FeedSection(
        id: 'hero',
        title: 'Heute für dich',
        subtitle: 'Stark gespeichert, nah dran, schnell aktivierbar.',
        type: FeedSectionType.hero,
        items: <FeedItem>[
          FeedItem(
            id: heroDeal.id,
            type: FeedItemType.heroDeal,
            dealId: heroDeal.id,
            businessId: heroDeal.businessId,
            headline: heroDeal.title,
            supportingText: heroDeal.socialProof,
            badge: heroDeal.tags.isEmpty ? 'Live' : heroDeal.tags.first.label,
          ),
        ],
      ),
      FeedSection(
        id: 'trending',
        title: 'Heute beliebt',
        subtitle: 'Was gerade in deiner Nähe zieht.',
        type: FeedSectionType.trending,
        items: trending
            .map(
              (deal) => FeedItem(
                id: deal.id,
                type: FeedItemType.trendingDeal,
                dealId: deal.id,
                businessId: deal.businessId,
                headline: deal.title,
                supportingText:
                    '${deal.stats.todayRedemptions}x heute eingelöst',
                badge: 'Trend',
              ),
            )
            .toList(growable: false),
      ),
      FeedSection(
        id: 'nearby',
        title: 'Gerade in deiner Nähe',
        subtitle: 'Kurzer Weg, schneller Mehrwert.',
        type: FeedSectionType.nearby,
        items: nearby
            .map(
              (deal) => FeedItem(
                id: deal.id,
                type: FeedItemType.nearbyDeal,
                dealId: deal.id,
                businessId: deal.businessId,
                headline: deal.title,
                supportingText:
                    '${deal.distanceKm.toStringAsFixed(1)} km entfernt',
                badge: 'Nearby',
              ),
            )
            .toList(growable: false),
      ),
      FeedSection(
        id: 'social',
        title: 'Freunde nutzen das',
        subtitle: 'Deals mit sichtbar gutem Social Proof.',
        type: FeedSectionType.friendActivity,
        items: social
            .map(
              (deal) => FeedItem(
                id: deal.id,
                type: FeedItemType.friendActivity,
                dealId: deal.id,
                businessId: deal.businessId,
                headline: deal.title,
                supportingText:
                    '${deal.stats.friendCount} Freunde folgen diesem Laden',
                badge: 'Social',
              ),
            )
            .toList(growable: false),
      ),
      FeedSection(
        id: 'hidden',
        title: 'Geheimtipps',
        subtitle: 'Kleine Orte mit großer Wahrscheinlichkeit auf Save.',
        type: FeedSectionType.collection,
        items: hidden
            .map(
              (deal) => FeedItem(
                id: deal.id,
                type: FeedItemType.hiddenGem,
                dealId: deal.id,
                businessId: deal.businessId,
                headline: deal.title,
                supportingText: businessById(deal.businessId).tagline,
                badge: 'Geheimtipp',
              ),
            )
            .toList(growable: false),
      ),
    ];
  }

  List<Deal> searchDeals({
    String query = '',
    DealCategory? category,
    bool onlyToday = false,
    bool onlyExclusive = false,
    bool openNowOnly = false,
    bool popularOnly = false,
    bool freshOnly = false,
    double maxDistanceKm = 30,
    double minRating = 0,
  }) {
    final normalized = query.trim().toLowerCase();

    return deals
        .where((deal) {
          final business = businessById(deal.businessId);
          final matchesQuery =
              normalized.isEmpty ||
              deal.title.toLowerCase().contains(normalized) ||
              deal.subtitle.toLowerCase().contains(normalized) ||
              business.name.toLowerCase().contains(normalized) ||
              business.city.toLowerCase().contains(normalized) ||
              business.district.toLowerCase().contains(normalized) ||
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
      ..sort(_sortByDistance);
  }

  Future<DeviceLoginResult> signInWithEmail({
    required String email,
    required String password,
    required DeviceSessionInfo device,
  }) async {
    await auth.signInWithEmailAndPassword(email: email, password: password);
    await _ensureUserDocument(
      auth.currentUser,
      preferredName: email.split('@').first,
    );
    return _completeAuthenticatedDeviceSession(email: email, device: device);
  }

  Future<DeviceLoginResult> signInWithGoogle({
    required DeviceSessionInfo device,
  }) async {
    firebase_auth.UserCredential credential;

    if (kIsWeb) {
      final provider = firebase_auth.GoogleAuthProvider()
        ..addScope('email')
        ..setCustomParameters(<String, String>{'prompt': 'select_account'});
      try {
        credential = await auth.signInWithPopup(provider);
      } on firebase_auth.FirebaseAuthException catch (error) {
        throw StateError(_friendlyGoogleAuthMessage(error));
      }
    } else {
      final googleSignIn = GoogleSignIn(scopes: const <String>['email']);
      final account = await googleSignIn.signIn();
      if (account == null) {
        throw StateError('Die Google-Anmeldung wurde abgebrochen.');
      }
      final authentication = await account.authentication;
      final googleCredential = firebase_auth.GoogleAuthProvider.credential(
        accessToken: authentication.accessToken,
        idToken: authentication.idToken,
      );
      credential = await auth.signInWithCredential(googleCredential);
    }

    final authUser = credential.user ?? auth.currentUser;
    final fallbackEmail = authUser?.email?.trim() ?? '';
    final displayName = authUser?.displayName?.trim() ?? '';
    final preferredName = displayName.isNotEmpty
        ? displayName
        : (fallbackEmail.contains('@')
              ? fallbackEmail.split('@').first
              : 'sparGO');

    await _ensureUserDocument(authUser, preferredName: preferredName);
    return _completeAuthenticatedDeviceSession(
      email: fallbackEmail,
      device: device,
    );
  }

  String _friendlyGoogleAuthMessage(firebase_auth.FirebaseAuthException error) {
    switch (error.code) {
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
        return 'Die Google-Anmeldung wurde abgebrochen.';
      case 'popup-blocked':
        return 'Der Browser blockiert das Google-Fenster. Bitte Pop-ups für sparGO erlauben und erneut versuchen.';
      case 'unauthorized-domain':
        return 'Diese Domain ist in Firebase Authentication noch nicht für Google freigegeben.';
      case 'operation-not-allowed':
        return 'Google-Anmeldung ist in Firebase Authentication noch nicht aktiviert.';
      case 'network-request-failed':
        return 'Google-Anmeldung konnte wegen eines Netzwerkfehlers nicht starten.';
      case 'account-exists-with-different-credential':
        return 'Für diese E-Mail existiert bereits eine andere Anmeldemethode.';
      default:
        final message = error.message?.trim();
        if (message != null && message.isNotEmpty) {
          return message;
        }
        return 'Google-Anmeldung konnte nicht abgeschlossen werden.';
    }
  }

  Future<DeviceLoginResult> signInWithApple({
    required DeviceSessionInfo device,
  }) async {
    final provider = firebase_auth.OAuthProvider('apple.com')
      ..addScope('email')
      ..addScope('name');

    final credential = kIsWeb
        ? await auth.signInWithPopup(provider)
        : await auth.signInWithProvider(provider);

    final authUser = credential.user ?? auth.currentUser;
    final fallbackEmail = authUser?.email?.trim() ?? '';
    final displayName = authUser?.displayName?.trim() ?? '';
    final preferredName = displayName.isNotEmpty
        ? displayName
        : (fallbackEmail.contains('@')
              ? fallbackEmail.split('@').first
              : 'sparGO');

    await _ensureUserDocument(authUser, preferredName: preferredName);
    return _completeAuthenticatedDeviceSession(
      email: fallbackEmail,
      device: device,
    );
  }

  Future<DeviceLoginResult> registerUser({
    required String email,
    required String password,
    required String name,
    required String handle,
    required String city,
    required AccountType accountType,
    required DeviceSessionInfo device,
  }) async {
    final credential = await auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final authUser = credential.user;
    if (authUser == null) {
      throw StateError('Registration returned no user.');
    }

    final resolvedCity = city.trim().isEmpty ? 'Deutschlandweit' : city.trim();
    final user = User(
      id: authUser.uid,
      accountType: accountType,
      name: name.trim(),
      handle: handle.trim().isEmpty
          ? '@${email.split('@').first}'
          : handle.trim(),
      city: resolvedCity,
      district: 'Dein Viertel',
      avatarInitials: FirebaseMappers.initials(name.trim()),
      favoriteCategories: const <DealCategory>[],
      savedDealIds: const <String>[],
      activeDealIds: const <String>[],
      followingBusinessIds: const <String>[],
      rewards: const <Reward>[],
      points: 0,
      freeCouponCredits: 0,
      inviteCode: _inviteCodeFor(authUser.uid),
      streakDays: 0,
      preferences: UserPreferences(
        interests: const <DealCategory>[],
        city: resolvedCity,
        radiusKm: 35,
        notificationsEnabled: true,
        socialProofEnabled: true,
        openNowOnly: false,
      ),
    );

    try {
      await _userDoc(authUser.uid).set(<String, dynamic>{
        ...FirebaseMappers.userToMap(
          user,
          ownedBusinessId: '',
          businessOnboardingComplete: accountType != AccountType.business,
          hasLocationPermission: false,
        ),
        ..._activeDeviceSessionData(device),
        ..._clearedPendingDeviceSessionData(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      try {
        await authUser.delete();
      } catch (_) {
        // Ignore rollback failures. The original registration error matters more.
      }
      await auth.signOut();
      rethrow;
    }

    if (accountType == AccountType.business && !authUser.emailVerified) {
      await authUser.sendEmailVerification();
    }

    return const DeviceLoginResult.success();
  }

  Future<void> repairOwnedBusinessLink({
    required String userId,
    required String businessId,
  }) async {
    final resolvedUserId = userId.trim();
    final resolvedBusinessId = businessId.trim();
    if (resolvedUserId.isEmpty || resolvedBusinessId.isEmpty) {
      return;
    }

    await _userDoc(resolvedUserId).set(<String, dynamic>{
      'accountType': AccountType.business.name,
      'ownedBusinessId': resolvedBusinessId,
      'businessOnboardingComplete': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> signOut({String? deviceId}) async {
    final authUser = auth.currentUser;
    if (authUser != null && deviceId != null && deviceId.trim().isNotEmpty) {
      try {
        final snapshot = await _userDoc(
          authUser.uid,
        ).get().timeout(const Duration(seconds: 2));
        final data = snapshot.data();
        final activeDeviceId =
            (data?['activeDeviceId'] as String?)?.trim() ?? '';
        if (activeDeviceId == deviceId.trim()) {
          await _userDoc(authUser.uid)
              .set(<String, dynamic>{
                'activeDeviceId': '',
                'activeDeviceLabel': '',
                'activeSessionStartedAt': null,
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true))
              .timeout(const Duration(seconds: 2));
        }
      } catch (_) {
        // Sign-out should still succeed when device cleanup fails.
      }
    }
    await auth.signOut().timeout(const Duration(seconds: 4));
  }

  Future<void> sendPasswordResetEmail(String email) {
    return auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> sendEmailVerification() async {
    final currentUser = auth.currentUser;
    if (currentUser == null) {
      throw StateError('No authenticated user available for verification.');
    }
    if (!currentUser.emailVerified) {
      await currentUser.sendEmailVerification();
    }
  }

  Future<void> reloadCurrentAuthUser() async {
    await auth.currentUser?.reload();
    await auth.currentUser?.getIdToken(true);
  }

  Future<void> updateUserInterests({
    required User user,
    required List<DealCategory> interests,
  }) {
    return _userDoc(user.id).set(<String, dynamic>{
      'favoriteCategories': interests.map((entry) => entry.name).toList(),
      'preferences': <String, dynamic>{
        ...FirebaseMappers.userPreferencesToMap(user.preferences),
        'interests': interests.map((entry) => entry.name).toList(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateLocation({
    required User user,
    required String city,
    required String district,
    double? latitude,
    double? longitude,
  }) {
    return _userDoc(user.id).set(<String, dynamic>{
      'city': city,
      'district': district,
      'latitude': latitude,
      'longitude': longitude,
      'hasLocationPermission': true,
      'preferences': <String, dynamic>{
        ...FirebaseMappers.userPreferencesToMap(user.preferences),
        'city': city,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateUserProfile({
    required User user,
    required String name,
    required String handle,
    required String city,
    required String district,
  }) {
    return _userDoc(user.id).set(<String, dynamic>{
      'name': name.trim(),
      'handle': handle.trim(),
      'city': city.trim(),
      'district': district.trim(),
      'latitude': user.latitude,
      'longitude': user.longitude,
      'avatarInitials': FirebaseMappers.initials(name.trim()),
      'preferences': <String, dynamic>{
        ...FirebaseMappers.userPreferencesToMap(user.preferences),
        'city': city.trim(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateUserSettings({
    required User user,
    double? radiusKm,
    bool? notificationsEnabled,
    bool? openNowOnly,
    String? languageCode,
  }) {
    return _userDoc(user.id).set(<String, dynamic>{
      'preferences': <String, dynamic>{
        ...FirebaseMappers.userPreferencesToMap(user.preferences),
        'radiusKm': radiusKm ?? user.preferences.radiusKm,
        'notificationsEnabled':
            notificationsEnabled ?? user.preferences.notificationsEnabled,
        'openNowOnly': openNowOnly ?? user.preferences.openNowOnly,
        'languageCode': languageCode ?? user.preferences.languageCode,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> completeUserOnboarding({
    required User user,
    required List<DealCategory> interests,
    required String locationPermissionStatus,
    required String? manualLocation,
    required double radiusKm,
  }) {
    if (user.id.trim().isEmpty) {
      return Future<void>.value();
    }

    final normalizedRadius = radiusKm.clamp(5.0, 50.0).toDouble();
    final hasLocation =
        locationPermissionStatus == 'granted' ||
        locationPermissionStatus == 'manual';
    final nextPreferences = user.preferences.copyWith(
      interests: interests,
      radiusKm: normalizedRadius,
    );

    return _userDoc(user.id).set(<String, dynamic>{
      'favoriteCategories': interests.map((entry) => entry.name).toList(),
      'hasLocationPermission': hasLocation,
      'preferences': <String, dynamic>{
        ...FirebaseMappers.userPreferencesToMap(nextPreferences),
        'interests': interests.map((entry) => entry.name).toList(),
        'radiusKm': normalizedRadius,
      },
      'onboardingCompleted': true,
      'onboarding': <String, dynamic>{
        'completed': true,
        'interests': interests.map((entry) => entry.name).toList(),
        'locationPermissionStatus': locationPermissionStatus,
        'manualLocation': manualLocation,
        'radiusKm': normalizedRadius,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> toggleFollowBusiness({
    required User user,
    required String businessId,
  }) async {
    final following = user.followingBusinessIds.toSet();
    final isFollowing = following.contains(businessId);
    if (isFollowing) {
      following.remove(businessId);
    } else {
      following.add(businessId);
    }

    await _userDoc(user.id).set(<String, dynamic>{
      'followingBusinessIds': following.toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final businessDoc = _isPublicCouponBusinessId(businessId)
        ? _publicCouponBusinessDoc(businessId)
        : _businessDoc(businessId);
    await _setIfDocExists(businessDoc, <String, dynamic>{
      'followerCount': FieldValue.increment(isFollowing ? -1 : 1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> toggleSavedDeal({
    required User user,
    required String dealId,
    Deal? dealOverride,
    Business? businessOverride,
  }) async {
    final saved = user.savedDealIds.toSet();
    final isSaved = saved.contains(dealId);
    if (isSaved) {
      saved.remove(dealId);
    } else {
      saved.add(dealId);
    }

    await _userDoc(user.id).set(<String, dynamic>{
      'savedDealIds': saved.toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final deal = dealOverride ?? dealById(dealId);
    await _setIfDocExists(_dealMetricsDoc(deal), <String, dynamic>{
      'stats.saves': FieldValue.increment(isSaved ? -1 : 1),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final business = businessOverride ?? businessById(deal.businessId);
    await _setIfDocExists(_businessMetricsDoc(business), <String, dynamic>{
      'analytics.saves': FieldValue.increment(isSaved ? -1 : 1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addRewardBonus({
    required User user,
    int points = 0,
    int freeCouponCredits = 0,
  }) {
    return _userDoc(user.id).set(<String, dynamic>{
      'points': user.points + points,
      'freeCouponCredits': user.freeCouponCredits + freeCouponCredits,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> markNotificationRead(String id) {
    return _notificationDoc(id).set(<String, dynamic>{
      'isRead': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> markAllNotificationsRead(String userId) async {
    final query = await firestore
        .collection(FirestoreCollections.notifications)
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();

    final batch = firestore.batch();
    for (final doc in query.docs) {
      batch.set(doc.reference, <String, dynamic>{
        'isRead': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<void> pushNotification({
    required String userId,
    required NotificationItem item,
  }) {
    return _notificationDoc(item.id).set(<String, dynamic>{
      ...FirebaseMappers.notificationToMap(item),
      'userId': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Redemption> activateDeal({
    required User user,
    required Deal deal,
    required Business business,
  }) async {
    if (deal.isThirdParty) {
      throw StateError(
        'Öffentliche Drittquellen können nicht als sparGO-Pass aktiviert werden.',
      );
    }
    final existing = _redemptions.where(
      (entry) =>
          entry.dealId == deal.id && entry.status == RedemptionStatus.active,
    );
    if (existing.isNotEmpty) {
      return existing.first;
    }

    final doc = firestore.collection(FirestoreCollections.redemptions).doc();
    final seed = doc.id.replaceAll('-', '').toUpperCase();
    final codeSeed = seed.substring(0, 8);
    final couponSeed = seed.substring(0, 10);
    final redemption = Redemption(
      id: doc.id,
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

    await doc.set(<String, dynamic>{
      ...FirebaseMappers.redemptionToMap(redemption),
      'userId': user.id,
      'businessId': business.id,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final nextActiveDeals = user.activeDealIds.toSet()..add(deal.id);
    await _userDoc(user.id).set(<String, dynamic>{
      'activeDealIds': nextActiveDeals.toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _setIfDocExists(_dealMetricsDoc(deal), <String, dynamic>{
      'stats.activations': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _setIfDocExists(_businessMetricsDoc(business), <String, dynamic>{
      'analytics.activations': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return redemption;
  }

  Future<void> redeemRedemption({
    required User user,
    required Redemption redemption,
    int savedAmountCents = 0,
  }) async {
    await _redemptionDoc(redemption.id).set(<String, dynamic>{
      'status': RedemptionStatus.redeemed.name,
      'savedAmountCents': savedAmountCents.clamp(0, 999999999).toInt(),
      'usedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final nextActiveDeals = user.activeDealIds.toSet()
      ..remove(redemption.dealId);
    await _userDoc(user.id).set(<String, dynamic>{
      'activeDealIds': nextActiveDeals.toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    late final Deal deal;
    late final Business business;
    try {
      deal = dealById(redemption.dealId);
      business = businessById(deal.businessId);
    } catch (_) {
      return;
    }
    await _setIfDocExists(_dealMetricsDoc(deal), <String, dynamic>{
      'stats.redemptions': FieldValue.increment(1),
      'stats.todayRedemptions': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _setIfDocExists(_businessMetricsDoc(business), <String, dynamic>{
      'analytics.redemptions': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> redeemRedemptionFromBusiness({
    required Business business,
    required Redemption redemption,
  }) async {
    final snapshot = await _redemptionDoc(redemption.id).get();
    if (!snapshot.exists) {
      throw StateError('Dieser Gutscheinpass wurde nicht gefunden.');
    }

    final data = snapshot.data() ?? <String, dynamic>{};
    final current = FirebaseMappers.redemptionFromMap(data, id: snapshot.id);
    if (current.status == RedemptionStatus.redeemed) {
      return;
    }

    await _redemptionDoc(current.id).set(<String, dynamic>{
      'status': RedemptionStatus.redeemed.name,
      'usedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final redemptionUserId = (data['userId'] as String?)?.trim() ?? '';
    if (redemptionUserId.isNotEmpty) {
      final userSnapshot = await _userDoc(redemptionUserId).get();
      if (userSnapshot.exists) {
        final userData = userSnapshot.data() ?? <String, dynamic>{};
        final activeDealIds =
            ((userData['activeDealIds'] as List?) ?? const <dynamic>[])
                .map((entry) => entry.toString())
                .where((entry) => entry != current.dealId)
                .toList(growable: false);
        await _userDoc(redemptionUserId).set(<String, dynamic>{
          'activeDealIds': activeDealIds,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }

    late final Deal deal;
    try {
      deal = dealById(current.dealId);
    } catch (_) {
      return;
    }

    await _setIfDocExists(_dealMetricsDoc(deal), <String, dynamic>{
      'stats.redemptions': FieldValue.increment(1),
      'stats.todayRedemptions': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _setIfDocExists(_businessMetricsDoc(business), <String, dynamic>{
      'analytics.redemptions': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> submitReview({
    required User user,
    required int rating,
    required String comment,
    String? dealId,
    String? businessId,
  }) async {
    final doc = firestore.collection(FirestoreCollections.reviews).doc();
    final review = AppReview(
      id: doc.id,
      authorName: user.name,
      authorInitials: user.avatarInitials,
      authorId: user.id,
      rating: rating,
      comment: comment.trim(),
      timeLabel: 'Jetzt',
      helpfulCount: 0,
      city: user.city,
      dealId: dealId,
      businessId: businessId,
    );

    await doc.set(<String, dynamic>{
      ...FirebaseMappers.reviewToMap(review),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _syncReviewAggregates(dealId: dealId, businessId: businessId);
  }

  Future<void> updateReview({
    required User user,
    required AppReview review,
    required int rating,
    required String comment,
  }) async {
    final snapshot = await _reviewDoc(review.id).get();
    if (!snapshot.exists) {
      throw StateError('Diese Bewertung wurde nicht gefunden.');
    }

    final current = FirebaseMappers.reviewFromMap(
      snapshot.data()!,
      id: snapshot.id,
    );
    if (!current.isOwnedBy(user.id)) {
      throw StateError('Du kannst nur deine eigenen Bewertungen bearbeiten.');
    }

    await _reviewDoc(review.id).set(<String, dynamic>{
      'rating': rating,
      'comment': comment.trim(),
      'timeLabel': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _syncReviewAggregates(
      dealId: current.dealId,
      businessId: current.businessId,
    );
  }

  Future<void> deleteReview({
    required User user,
    required AppReview review,
  }) async {
    final snapshot = await _reviewDoc(review.id).get();
    if (!snapshot.exists) {
      return;
    }

    final current = FirebaseMappers.reviewFromMap(
      snapshot.data()!,
      id: snapshot.id,
    );
    if (!current.isOwnedBy(user.id)) {
      throw StateError('Du kannst nur deine eigenen Bewertungen löschen.');
    }
    if (!current.canDelete) {
      throw StateError(
        'Bewertungen können nur innerhalb von 7 Tagen gelöscht werden.',
      );
    }

    await _reviewDoc(review.id).delete();
    await _syncReviewAggregates(
      dealId: current.dealId,
      businessId: current.businessId,
    );
  }

  Future<String> saveBusinessProfile({
    required User user,
    required Business baseBusiness,
    required String businessId,
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
    double? latitude,
    double? longitude,
    Uint8List? imageBytes,
    String imageUrl = '',
    BusinessVerificationMethod verificationMethod =
        BusinessVerificationMethod.googleBusinessProfile,
    BusinessGoogleProfileLink googleProfileLink =
        const BusinessGoogleProfileLink(),
  }) async {
    final currentAuthUser = auth.currentUser;
    if (currentAuthUser == null || currentAuthUser.isAnonymous) {
      throw StateError(
        'Business-Profile können nur aus einer aktiven Business-Session gespeichert werden.',
      );
    }
    if (!currentAuthUser.emailVerified) {
      throw StateError(
        'Bitte bestätige zuerst die E-Mail deines Business-Zugangs. Erst danach darf das Studio freigeschaltet werden.',
      );
    }
    if (user.accountType != AccountType.business) {
      throw StateError(
        'Ein normales Nutzerkonto darf kein Business anlegen oder übernehmen.',
      );
    }
    if (currentAuthUser.uid.trim().isNotEmpty &&
        user.id.trim().isNotEmpty &&
        currentAuthUser.uid.trim() != user.id.trim()) {
      throw StateError(
        'Die Business-Session ist nicht sauber synchronisiert. Bitte neu anmelden und erneut versuchen.',
      );
    }

    var resolvedName = name.trim();
    var resolvedWebsite = _normalizeWebsite(website);
    var resolvedPhone = phone.trim();
    var resolvedContactEmail = contactEmail.trim().toLowerCase();
    var resolvedLegalEntityName = legalEntityName.trim();
    var resolvedImprintInfo = imprintInfo.trim();
    var resolvedAddress = address.trim();
    var resolvedCity = city.trim();
    var resolvedDistrict = district.trim();
    var resolvedClaimedByName = claimedByName.trim();
    var resolvedClaimedByRole = claimedByRole.trim();
    var resolvedVerificationPlaceId = verificationPlaceId.trim();
    var resolvedVerificationWebsite = _normalizeWebsite(verificationWebsite);

    final hasVerifiedGoogleBusinessLink =
        googleProfileLink.grantsDashboardAccess;
    final resolvedVerificationMethod = hasVerifiedGoogleBusinessLink
        ? BusinessVerificationMethod.googleBusinessProfile
        : verificationMethod;
    if (resolvedVerificationMethod ==
        BusinessVerificationMethod.googleBusinessProfile) {
      final resolvedGoogleLink = await _requireGoogleBusinessVerification(
        googleProfileLink,
      );
      resolvedVerificationPlaceId = resolvedGoogleLink.placeId.trim();
      resolvedVerificationWebsite = _normalizeWebsite(
        resolvedGoogleLink.website,
      );
      if (resolvedName.isEmpty) {
        resolvedName = resolvedGoogleLink.locationDisplayName.trim();
      }
      if (resolvedWebsite.isEmpty) {
        resolvedWebsite = _normalizeWebsite(resolvedGoogleLink.website);
      }
      if (resolvedPhone.isEmpty) {
        resolvedPhone = resolvedGoogleLink.phone.trim();
      }
      if (resolvedContactEmail.isEmpty) {
        resolvedContactEmail = resolvedGoogleLink.googleUserEmail
            .trim()
            .toLowerCase();
      }
      if (resolvedAddress.isEmpty) {
        resolvedAddress = resolvedGoogleLink.locationAddress.trim();
      }
      if (resolvedCity.isEmpty) {
        resolvedCity = resolvedGoogleLink.locationCity.trim();
      }
      if (resolvedDistrict.isEmpty) {
        resolvedDistrict = 'In deiner Nähe';
      }
      if (resolvedClaimedByRole.isEmpty) {
        resolvedClaimedByRole = resolvedGoogleLink.roleLabel;
      }
      if (resolvedLegalEntityName.isEmpty) {
        resolvedLegalEntityName = resolvedName;
      }
      if (resolvedImprintInfo.isEmpty) {
        resolvedImprintInfo = <String>[
          resolvedLegalEntityName,
          if (resolvedAddress.isNotEmpty) resolvedAddress,
          if (resolvedCity.isNotEmpty) resolvedCity,
          if (resolvedContactEmail.isNotEmpty) 'Kontakt: $resolvedContactEmail',
          if (resolvedWebsite.isNotEmpty) 'Web: $resolvedWebsite',
        ].join(' | ');
      }
    } else {
      throw StateError(
        'Dieses Business kann nur über eine serverseitig bestätigte Business-Identität freigeschaltet werden.',
      );
    }

    if (resolvedDistrict.isEmpty) {
      resolvedDistrict = 'In deiner Nähe';
    }
    if (resolvedCity.isEmpty) {
      resolvedCity = 'Deutschlandweit';
    }
    if (resolvedAddress.isEmpty) {
      resolvedAddress = 'Adresse folgt';
    }
    if (resolvedClaimedByName.isEmpty) {
      resolvedClaimedByName = user.name.trim();
    }
    if (resolvedLegalEntityName.isEmpty) {
      resolvedLegalEntityName = resolvedName;
    }
    if (resolvedImprintInfo.isEmpty) {
      resolvedImprintInfo = <String>[
        resolvedLegalEntityName,
        if (resolvedAddress.isNotEmpty) resolvedAddress,
        if (resolvedCity.isNotEmpty) resolvedCity,
        if (resolvedContactEmail.isNotEmpty) 'Kontakt: $resolvedContactEmail',
        if (resolvedWebsite.isNotEmpty) 'Web: $resolvedWebsite',
      ].join(' | ');
    }
    if (resolvedClaimedByRole.isEmpty) {
      resolvedClaimedByRole = googleProfileLink.roleLabel;
    }

    _assertBusinessVerificationInputs(
      verificationMethod: resolvedVerificationMethod,
      website: resolvedWebsite,
      verificationPlaceId: resolvedVerificationPlaceId,
      verificationWebsite: resolvedVerificationWebsite,
      contactEmail: resolvedContactEmail,
      legalEntityName: resolvedLegalEntityName,
      imprintInfo: resolvedImprintInfo,
      claimedByName: resolvedClaimedByName,
      claimedByRole: resolvedClaimedByRole,
      ownershipConfirmed: ownershipConfirmed,
      googleProfileLink: googleProfileLink,
      name: resolvedName,
    );

    final verificationNote =
        'Serverseitig bestätigte Business-Identität: ${googleProfileLink.locationDisplayName} (${googleProfileLink.roleLabel}).';
    final effectiveVerificationNote =
        resolvedVerificationMethod == BusinessVerificationMethod.manualReview
        ? 'Zur manuellen Prüfung vorgemerkt. Du kannst dein Studio bereits vorbereiten.'
        : verificationNote;
    final nextVerificationStatus =
        resolvedVerificationMethod == BusinessVerificationMethod.manualReview
        ? BusinessVerificationStatus.pending
        : BusinessVerificationStatus.verified;
    final verificationRequestedAt = DateTime.now();
    final persistedVerificationStatus = nextVerificationStatus;
    final persistedVerificationNote = effectiveVerificationNote;
    final existingClaim = await _findExistingBusinessClaim(
      verificationMethod: resolvedVerificationMethod,
      website: resolvedWebsite,
      verificationPlaceId: resolvedVerificationPlaceId,
      googleProfileLink: googleProfileLink,
    );
    final sourceBusiness = existingClaim == null
        ? baseBusiness
        : FirebaseMappers.businessFromMap(
            existingClaim.data(),
            id: existingClaim.id,
          );
    final resolvedId =
        existingClaim?.id ??
        (businessId.trim().isEmpty
            ? firestore.collection(FirestoreCollections.businesses).doc().id
            : businessId.trim());
    final existingOwnerId =
        (existingClaim?.data()['ownerId'] as String?)?.trim() ?? '';
    final ownerId = existingOwnerId.isEmpty ? user.id : existingOwnerId;
    var resolvedImageUrl = imageUrl.trim().isNotEmpty
        ? imageUrl.trim()
        : sourceBusiness.imageUrl.trim();
    final resolvedLatitude =
        latitude ??
        (sourceBusiness.branches.isEmpty
            ? (user.latitude ?? 52.5200)
            : sourceBusiness.primaryBranch.latitude);
    final resolvedLongitude =
        longitude ??
        (sourceBusiness.branches.isEmpty
            ? (user.longitude ?? 13.4050)
            : sourceBusiness.primaryBranch.longitude);
    final existingBranch = sourceBusiness.branches.isEmpty
        ? Branch(
            id: '${resolvedId}_branch_1',
            name: resolvedName,
            city: resolvedCity,
            district: resolvedDistrict,
            address: resolvedAddress,
            latitude: resolvedLatitude,
            longitude: resolvedLongitude,
            hours: const <BusinessHours>[],
          )
        : sourceBusiness.primaryBranch.copyWith(
            id: sourceBusiness.primaryBranch.id.isEmpty
                ? '${resolvedId}_branch_1'
                : sourceBusiness.primaryBranch.id,
            name: resolvedName,
            city: resolvedCity,
            district: resolvedDistrict,
            address: resolvedAddress,
            latitude: resolvedLatitude,
            longitude: resolvedLongitude,
          );

    final draftBusiness = sourceBusiness.copyWith(
      id: resolvedId,
      name: resolvedName,
      tagline: tagline.trim(),
      description: description.trim(),
      shortDescription: shortDescription.trim(),
      category: category,
      city: resolvedCity,
      district: resolvedDistrict,
      rating: sourceBusiness.reviewCount > 0 ? sourceBusiness.rating : 0,
      reviewCount: sourceBusiness.reviewCount,
      branches: <Branch>[existingBranch],
      website: resolvedWebsite,
      phone: resolvedPhone,
      contactEmail: resolvedContactEmail,
      legalEntityName: resolvedLegalEntityName,
      imprintInfo: resolvedImprintInfo,
      verificationStatus: persistedVerificationStatus,
      verificationMethod: resolvedVerificationMethod,
      verificationRequestedAt: verificationRequestedAt,
      ownershipConfirmed: ownershipConfirmed,
      verificationPlaceId: resolvedVerificationPlaceId,
      verificationWebsite: resolvedVerificationWebsite,
      claimedByName: resolvedClaimedByName,
      claimedByRole: resolvedClaimedByRole,
      verificationNote: persistedVerificationNote,
      imageUrl: resolvedImageUrl,
      isNew: false,
      googleProfileLink: googleProfileLink,
    );

    await _businessDoc(resolvedId).set(<String, dynamic>{
      ...FirebaseMappers.businessToMap(draftBusiness),
      'ownerId': ownerId,
      'assignedUserIds': FieldValue.arrayUnion(<String>[user.id]),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (imageBytes != null) {
      resolvedImageUrl = await uploadBusinessLogo(resolvedId, imageBytes);
    }

    final business = draftBusiness.copyWith(imageUrl: resolvedImageUrl);

    await _businessDoc(resolvedId).set(<String, dynamic>{
      ...FirebaseMappers.businessToMap(business),
      'ownerId': ownerId,
      'assignedUserIds': FieldValue.arrayUnion(<String>[user.id]),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _userDoc(user.id).set(<String, dynamic>{
      'ownedBusinessId': resolvedId,
      'businessOnboardingComplete': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return resolvedId;
  }

  Future<String> upsertDeal({
    required User user,
    required Business business,
    Deal? existingDeal,
    required DealCategory category,
    required int availabilityDays,
    required String title,
    required String description,
    required int savingsPercent,
    Uint8List? imageBytes,
    String? imageUrl,
  }) async {
    _ensureBusinessVerified(business);
    final ownerUserId = (auth.currentUser?.uid ?? user.id).trim();
    if (ownerUserId.isEmpty) {
      throw StateError(
        'Kein angemeldeter Business-User für diesen Deal gefunden.',
      );
    }
    await _ensureBusinessMemberAccess(userId: ownerUserId, business: business);

    final resolvedId =
        existingDeal?.id ??
        firestore.collection(FirestoreCollections.deals).doc().id;
    final now = DateTime.now();
    final normalizedImageUrl = imageUrl?.trim() ?? '';
    final normalizedAvailabilityDays = availabilityDays.clamp(1, 365).toInt();
    final uploadedImageUrl = imageBytes == null
        ? ''
        : await _tryBusinessAssetUpload(
            () => uploadDealAsset(business.id, resolvedId, imageBytes),
            debugLabel: 'deal:$resolvedId',
          );
    final resolvedImageUrl = uploadedImageUrl.isNotEmpty
        ? uploadedImageUrl
        : (normalizedImageUrl.isNotEmpty
              ? normalizedImageUrl
              : (existingDeal?.imageUrl.trim().isNotEmpty ?? false)
              ? existingDeal!.imageUrl
              : business.imageUrl);
    final baseStats = existingDeal == null
        ? const DealStats(
            views: 0,
            saves: 0,
            activations: 0,
            redemptions: 0,
            rating: 0,
            friendCount: 0,
            todayRedemptions: 0,
          )
        : existingDeal.stats.copyWith(
            rating: existingDeal.reviewCount > 0
                ? existingDeal.stats.rating
                : 0,
          );

    final deal = (existingDeal ?? fallbackDeal(id: resolvedId)).copyWith(
      id: resolvedId,
      businessId: business.id,
      title: title.trim(),
      subtitle: existingDeal?.subtitle ?? business.tagline,
      description: description.trim(),
      city: business.city,
      district: business.district,
      category: category,
      type: existingDeal?.type ?? DealType.percentage,
      tags: existingDeal?.tags ?? const <OfferTag>[OfferTag.fresh],
      distanceKm: existingDeal?.distanceKm ?? business.distanceKm,
      reviewCount: existingDeal?.reviewCount ?? 0,
      stats: baseStats,
      validUntil: now.add(Duration(days: normalizedAvailabilityDays)),
      imageUrl: resolvedImageUrl,
      originalPrice: 0,
      discountedPrice: 0,
      savingsPercent: savingsPercent,
      priceHint: existingDeal?.priceHint ?? 'Direkt im Laden',
      redemptionCode: existingDeal?.redemptionCode ?? 'SPARGO$resolvedId',
      highlights:
          existingDeal?.highlights ??
          <String>['Sofort im Feed sichtbar', 'Direkt in Wallet aktivierbar'],
      conditions:
          existingDeal?.conditions ??
          <String>['Einmal pro Person', 'Nur solange live'],
      galleryLabels:
          existingDeal?.galleryLabels ??
          <String>['Coupon', 'Storefront', 'Benefit'],
      palette: existingDeal?.palette ?? business.coverPalette,
      socialProof: existingDeal?.socialProof ?? 'Neu im Feed',
      availabilityLabel: _availabilityLabelForDays(normalizedAvailabilityDays),
      ctaLabel: 'Gutschein aktivieren',
      validDays:
          existingDeal?.validDays ??
          const <String>['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'],
      openNow: existingDeal?.openNow ?? false,
    );

    await _dealDoc(resolvedId).set(<String, dynamic>{
      ...FirebaseMappers.dealToMap(
        deal,
        isPaused: pausedDealIds.contains(resolvedId),
      ),
      'ownerId': ownerUserId,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _notifyFollowersForBusiness(
      business: business,
      title: existingDeal == null
          ? 'Neuer Gutschein live'
          : 'Gutschein aktualisiert',
      body:
          '${business.name} hat ${deal.title} jetzt im Feed. Direkt ansehen und aktivieren.',
      type: NotificationType.liveDeal,
      dealId: resolvedId,
    );

    return resolvedId;
  }

  Future<String> createStory({
    required User user,
    required Business business,
    required StoryType type,
    required String title,
    required String subtitle,
    required String body,
    required String ctaLabel,
    Uint8List? imageBytes,
    String? imageUrl,
    String? dealId,
  }) async {
    _ensureBusinessVerified(business);
    final ownerUserId = (auth.currentUser?.uid ?? user.id).trim();
    if (ownerUserId.isEmpty) {
      throw StateError(
        'Kein angemeldeter Business-User für diese Story gefunden.',
      );
    }
    await _ensureBusinessMemberAccess(userId: ownerUserId, business: business);

    final storyId = firestore.collection(FirestoreCollections.stories).doc().id;
    final normalizedImageUrl = imageUrl?.trim() ?? '';
    final uploadedImageUrl = imageBytes == null
        ? ''
        : await _tryBusinessAssetUpload(
            () => uploadStoryAsset(business.id, storyId, imageBytes),
            debugLabel: 'story:$storyId',
          );
    final resolvedImageUrl = uploadedImageUrl.isNotEmpty
        ? uploadedImageUrl
        : (normalizedImageUrl.isNotEmpty
              ? normalizedImageUrl
              : business.imageUrl);
    final item = StoryItem(
      id: '${storyId}_item_1',
      type: type,
      title: title.trim(),
      subtitle: subtitle.trim(),
      body: body.trim(),
      ctaLabel: ctaLabel.trim(),
      palette: business.coverPalette,
      duration: const Duration(seconds: 4),
      imageUrl: resolvedImageUrl,
      dealId: dealId,
    );

    final story = Story(
      id: storyId,
      businessId: business.id,
      businessName: business.name,
      city: business.city,
      label: subtitle.trim(),
      previewPalette: business.coverPalette,
      items: <StoryItem>[item],
      timeLabel: 'Jetzt',
    );

    await _storyDoc(storyId).set(<String, dynamic>{
      ...FirebaseMappers.storyToMap(story),
      'ownerId': ownerUserId,
      'expiresAt': Timestamp.fromDate(
        DateTime.now().add(const Duration(hours: 24)),
      ),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _notifyFollowersForBusiness(
      business: business,
      title: 'Neue Story live',
      body: '${business.name} hat gerade eine neue Story veröffentlicht.',
      type: NotificationType.followingBusiness,
      dealId: dealId,
    );
    return storyId;
  }

  Future<void> trackStoryView(Story story) async {
    Business? business;
    try {
      business = businessById(story.businessId);
    } catch (_) {
      business = null;
    }

    if (business != null) {
      await _setIfDocExists(_businessMetricsDoc(business), <String, dynamic>{
        'analytics.views': FieldValue.increment(1),
        'analytics.reach': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    final linkedDealIds = story.items
        .map((item) => item.dealId?.trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    for (final dealId in linkedDealIds) {
      late final Deal deal;
      try {
        deal = dealById(dealId);
      } catch (_) {
        continue;
      }
      await _setIfDocExists(_dealMetricsDoc(deal), <String, dynamic>{
        'stats.views': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> markStorySeen(User user, String storyId) async {
    final normalizedStoryId = storyId.trim();
    if (user.id.trim().isEmpty || normalizedStoryId.isEmpty) {
      return;
    }
    await _userDoc(user.id).set(<String, dynamic>{
      'seenStoryIds': FieldValue.arrayUnion(<String>[normalizedStoryId]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setDealPaused({
    required Business business,
    required String dealId,
    required bool paused,
  }) {
    _ensureBusinessVerified(business);
    return _dealDoc(dealId).set(<String, dynamic>{
      'isPaused': paused,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteBusinessDeal({
    required Business business,
    required String dealId,
  }) async {
    _ensureBusinessVerified(business);
    final ownerUserId = (auth.currentUser?.uid ?? currentUser.id).trim();
    await _ensureBusinessMemberAccess(userId: ownerUserId, business: business);
    await _dealDoc(dealId).delete();
  }

  Future<void> deleteBusinessStory({
    required Business business,
    required String storyId,
  }) async {
    _ensureBusinessVerified(business);
    final ownerUserId = (auth.currentUser?.uid ?? currentUser.id).trim();
    await _ensureBusinessMemberAccess(userId: ownerUserId, business: business);
    await _storyDoc(storyId).delete();
  }

  Future<String> uploadBusinessLogo(String businessId, Uint8List bytes) {
    return _uploadBytes(FirebaseStoragePaths.businessLogo(businessId), bytes);
  }

  Future<String> uploadBusinessVerificationDocument({
    required String placeId,
    required String filename,
    required Uint8List bytes,
    String contentType = 'application/octet-stream',
  }) {
    final userId = (auth.currentUser?.uid ?? 'unknown').trim();
    final safeUserId = userId.isEmpty ? 'unknown' : userId;
    final safePlaceId = placeId.trim().isEmpty
        ? 'unknown-place'
        : placeId.trim();
    final safeFilename = filename.trim().replaceAll(
      RegExp(r'[^A-Za-z0-9._-]+'),
      '_',
    );
    final path = FirebaseStoragePaths.businessVerificationDocument(
      safeUserId,
      safePlaceId,
      safeFilename.isEmpty ? 'evidence.bin' : safeFilename,
    );
    final ref = storage.ref(path);
    final metadata = SettableMetadata(contentType: contentType);
    return ref.putData(bytes, metadata).then((_) => path);
  }

  Future<String> uploadBusinessCover(String businessId, Uint8List bytes) {
    return _uploadBytes(
      FirebaseStoragePaths.businessCover(businessId),
      bytes,
      contentType: 'image/jpeg',
    );
  }

  Future<String> uploadDealAsset(
    String businessId,
    String dealId,
    Uint8List bytes,
  ) {
    return _uploadBytes(
      FirebaseStoragePaths.dealAsset(businessId, dealId),
      bytes,
      contentType: 'image/jpeg',
    );
  }

  Future<String> uploadStoryAsset(
    String businessId,
    String storyId,
    Uint8List bytes,
  ) {
    return _uploadBytes(
      FirebaseStoragePaths.storyAsset(businessId, storyId),
      bytes,
      contentType: 'image/jpeg',
    );
  }

  Future<String> uploadCouponQr(
    String userId,
    String redemptionId,
    Uint8List bytes,
  ) {
    return _uploadBytes(
      FirebaseStoragePaths.couponQr(userId, redemptionId),
      bytes,
    );
  }

  Business fallbackBusiness({String id = 'business_placeholder'}) {
    return Business(
      id: id,
      name: 'Dein Business',
      tagline: 'Lokale Vorteile sauber steuern',
      shortDescription: 'Noch kein Business angelegt',
      description:
          'Lege dein Unternehmen an, damit Deals und Stories live gehen.',
      category: DealCategory.food,
      city: 'Deutschlandweit',
      district: 'Dein Viertel',
      rating: 0,
      reviewCount: 0,
      followerCount: 0,
      priceLevel: '€€',
      tags: const <String>['Neu'],
      coverPalette: const <int>[0xFFDB2149, 0xFFF06B84],
      galleryLabels: const <String>['Cover'],
      branches: <Branch>[
        Branch(
          id: '${id}_branch_1',
          name: 'Hauptstandort',
          city: 'Deutschlandweit',
          district: 'Dein Viertel',
          address: 'Adresse folgt',
          latitude: 53.5511,
          longitude: 9.9937,
          hours: const <BusinessHours>[],
        ),
      ],
      phone: '',
      website: '',
      distanceKm: 0,
      isTrending: false,
      isNew: true,
      analytics: const BusinessAnalytics(
        views: 0,
        saves: 0,
        activations: 0,
        redemptions: 0,
        reach: 0,
        trendPoints: <int>[0, 0, 0, 0, 0],
      ),
      contactEmail: '',
      legalEntityName: '',
      imprintInfo: '',
      verificationStatus: BusinessVerificationStatus.draft,
      ownershipConfirmed: false,
      claimedByName: '',
      claimedByRole: '',
      verificationNote:
          'Bitte reiche deine Inhaberschaft zur Verifizierung ein.',
    );
  }

  void _ensureBusinessVerified(Business business) {
    if (_hasBusinessPublishingAccess(business)) {
      return;
    }

    throw StateError(
      'Dieses Business ist noch nicht sicher bestätigt. Deals und Stories gehen erst live, wenn die serverseitige Business-Prüfung abgeschlossen ist.',
    );
  }

  bool _hasBusinessPublishingAccess(Business business) {
    final currentUser = auth.currentUser;
    if (currentUser == null ||
        currentUser.isAnonymous ||
        !currentUser.emailVerified) {
      return false;
    }

    if (business.verificationStatus.isVerified) {
      return true;
    }

    if (business.googleProfileLink.isLinked &&
        business.googleProfileLink.grantsDashboardAccess) {
      final authEmail = (currentUser.email ?? '').trim().toLowerCase();
      final googleEmail = business.googleProfileLink.googleUserEmail
          .trim()
          .toLowerCase();
      return googleEmail.isEmpty ||
          authEmail.isEmpty ||
          authEmail == googleEmail;
    }

    final authEmail = (currentUser.email ?? '').trim().toLowerCase();
    final businessEmail = business.contactEmail.trim().toLowerCase();
    final verificationWebsite = business.verificationWebsite.trim().isNotEmpty
        ? business.verificationWebsite.trim()
        : business.website.trim();
    if (authEmail.isEmpty ||
        businessEmail.isEmpty ||
        authEmail != businessEmail ||
        verificationWebsite.isEmpty) {
      return false;
    }

    return _emailMatchesWebsiteDomain(
      email: authEmail,
      website: verificationWebsite,
    );
  }

  void _assertBusinessVerificationInputs({
    required BusinessVerificationMethod verificationMethod,
    required String website,
    required String verificationPlaceId,
    required String verificationWebsite,
    required String contactEmail,
    required String legalEntityName,
    required String imprintInfo,
    required String claimedByName,
    required String claimedByRole,
    required bool ownershipConfirmed,
    required BusinessGoogleProfileLink googleProfileLink,
    required String name,
  }) {
    if (!ownershipConfirmed) {
      throw StateError(
        'Bitte bestätige, dass dir das Unternehmen gehört oder du dafür bevollmächtigt bist.',
      );
    }
    if (name.trim().isEmpty ||
        legalEntityName.trim().isEmpty ||
        imprintInfo.trim().isEmpty ||
        claimedByName.trim().isEmpty ||
        claimedByRole.trim().isEmpty) {
      throw StateError(
        'Für die Business-Freischaltung brauchen wir Firmenname, rechtlichen Namen, Impressum und eine verantwortliche Person.',
      );
    }
    if (verificationMethod == BusinessVerificationMethod.emailDomain) {
      if (verificationPlaceId.trim().isEmpty) {
        throw StateError(
          'Für die Business-Freischaltung fehlt der ausgewählte Google-Standort.',
        );
      }
      throw StateError(
        'Business-Freischaltung ist nur noch über eine serverseitig bestätigte Business-Identität zulässig.',
      );
    }

    if (verificationMethod == BusinessVerificationMethod.manualReview) {
      if (contactEmail.trim().isEmpty) {
        throw StateError(
          'Für die manuelle Prüfung brauchen wir mindestens eine kontaktierbare Business-E-Mail.',
        );
      }
      return;
    }

    if (!googleProfileLink.isLinked) {
      throw StateError(
        'Bitte bestätige zuerst die passende Business-Identität für diesen Standort.',
      );
    }
    if (!googleProfileLink.grantsDashboardAccess) {
      throw StateError(
        'Dieses Google-Konto hat für diesen Standort keinen bestätigten Google-Business-Zugriff.',
      );
    }
    if (contactEmail.trim().isEmpty &&
        googleProfileLink.googleUserEmail.trim().isEmpty) {
      throw StateError(
        'Für die Business-Freischaltung fehlt eine kontaktierbare E-Mail-Adresse.',
      );
    }
  }

  String _requireAutomaticBusinessVerification({
    required String contactEmail,
    required String website,
  }) {
    final currentUser = auth.currentUser;
    if (currentUser == null || currentUser.isAnonymous) {
      throw StateError(
        'Für die automatische Business-Verifizierung musst du mit deiner Business-E-Mail eingeloggt sein.',
      );
    }

    final authEmail = (currentUser.email ?? '').trim().toLowerCase();
    if (authEmail.isEmpty) {
      throw StateError(
        'Dein Konto hat aktuell keine E-Mail. Bitte nutze ein Business-Konto mit E-Mail-Adresse.',
      );
    }
    if (!currentUser.emailVerified) {
      throw StateError(
        'Bitte bestätige zuerst den Link in deiner Business-E-Mail. Danach wird dein Business automatisch verifiziert.',
      );
    }

    final normalizedContactEmail = contactEmail.trim().toLowerCase();
    final normalizedWebsite = _normalizeWebsite(website);
    if (normalizedContactEmail != authEmail) {
      throw StateError(
        'Die Business-E-Mail muss exakt der verifizierten Login-E-Mail entsprechen.',
      );
    }
    if (normalizedWebsite.isEmpty) {
      throw StateError(
        'Für die automatische Firmenverifizierung fehlt die bestätigte Website-Domain des ausgewählten Unternehmens.',
      );
    }
    if (_isPrivateMailboxDomain(normalizedContactEmail)) {
      throw StateError(
        'Für die automatische Firmenverifizierung brauchst du eine geschäftliche E-Mail auf deiner eigenen Firmen-Domain.',
      );
    }
    if (!_emailMatchesWebsiteDomain(
      email: normalizedContactEmail,
      website: normalizedWebsite,
    )) {
      throw StateError(
        'Die verifizierte Business-E-Mail muss zur Domain deiner Website passen.',
      );
    }

    return normalizedWebsite;
  }

  bool _canUseEmailDomainVerification({
    required String website,
    required String contactEmail,
  }) {
    if (website.trim().isEmpty || contactEmail.trim().isEmpty) {
      return false;
    }
    if (_isPrivateMailboxDomain(contactEmail.trim())) {
      return false;
    }
    return _emailMatchesWebsiteDomain(
      email: contactEmail.trim(),
      website: website.trim(),
    );
  }

  Future<BusinessGoogleProfileLink> _requireGoogleBusinessVerification(
    BusinessGoogleProfileLink googleProfileLink,
  ) async {
    final currentUser = auth.currentUser;
    if (currentUser == null || currentUser.isAnonymous) {
      throw StateError(
        'Für die Business-Freischaltung musst du angemeldet sein.',
      );
    }
    if (!googleProfileLink.isLinked) {
      throw StateError(
        'Bitte bestätige zuerst die passende Business-Identität für diesen Standort.',
      );
    }
    if (!googleProfileLink.grantsDashboardAccess) {
      throw StateError(
        'Für diesen Standort ist nur eine serverseitig bestätigte Business-Identität zugelassen.',
      );
    }
    if (googleProfileLink.verificationSessionId.trim().isEmpty) {
      throw StateError(
        'Für diesen Standort fehlt die serverseitige Google-Business-Bestätigung. Bitte verknüpfe das Profil erneut.',
      );
    }

    final sessionSnapshot = await firestore
        .collection(FirestoreCollections.businessVerificationSessions)
        .doc(googleProfileLink.verificationSessionId.trim())
        .get();
    if (!sessionSnapshot.exists) {
      throw StateError(
        'Die serverseitige Business-Bestätigung ist nicht mehr verfügbar. Bitte verknüpfe deine Business-Identität erneut.',
      );
    }

    final sessionData = sessionSnapshot.data() ?? <String, dynamic>{};
    final verified = sessionData['verified'] == true;
    if (!verified) {
      throw StateError(
        'Diese Business-Bestätigung ist serverseitig noch nicht vollständig freigegeben.',
      );
    }

    final expiresAt = sessionData['expiresAt'];
    if (expiresAt is Timestamp && expiresAt.toDate().isBefore(DateTime.now())) {
      throw StateError(
        'Die Business-Bestätigung ist abgelaufen. Bitte verknüpfe deine Business-Identität erneut.',
      );
    }

    final verifiedPlaceId = (sessionData['placeId'] as String? ?? '').trim();
    if (verifiedPlaceId.isEmpty ||
        verifiedPlaceId != googleProfileLink.placeId.trim()) {
      throw StateError(
        'Die serverseitige Business-Bestätigung passt nicht mehr zu diesem Standort.',
      );
    }

    final verifiedIdentityEmail =
        ((sessionData['identityEmail'] as String?) ??
                (sessionData['googleEmail'] as String?) ??
                '')
            .trim()
            .toLowerCase();
    final authEmail = (currentUser.email ?? '').trim().toLowerCase();
    if (verifiedIdentityEmail.isNotEmpty &&
        authEmail.isNotEmpty &&
        verifiedIdentityEmail != authEmail) {
      throw StateError(
        'Diese Business-Bestätigung gehört zu einer anderen angemeldeten Identität. Bitte melde dich mit dem bestätigten Business-Zugang an.',
      );
    }

    return googleProfileLink.copyWith(
      googleUserEmail: verifiedIdentityEmail.isNotEmpty
          ? verifiedIdentityEmail
          : googleProfileLink.googleUserEmail,
    );
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?>
  _findExistingBusinessClaim({
    required BusinessVerificationMethod verificationMethod,
    required String website,
    required String verificationPlaceId,
    required BusinessGoogleProfileLink googleProfileLink,
  }) async {
    if (verificationMethod ==
            BusinessVerificationMethod.googleBusinessProfile ||
        verificationPlaceId.trim().isNotEmpty) {
      final normalizedPlaceId = verificationPlaceId.trim().isNotEmpty
          ? verificationPlaceId.trim()
          : googleProfileLink.placeId.trim();
      if (normalizedPlaceId.isEmpty) {
        return null;
      }
      final placeSnapshot = await firestore
          .collection(FirestoreCollections.businesses)
          .where('verificationPlaceId', isEqualTo: normalizedPlaceId)
          .limit(1)
          .get();
      if (placeSnapshot.docs.isNotEmpty) {
        return placeSnapshot.docs.first;
      }
      final legacyPlaceSnapshot = await firestore
          .collection(FirestoreCollections.businesses)
          .where('googleProfileLink.placeId', isEqualTo: normalizedPlaceId)
          .limit(1)
          .get();
      if (legacyPlaceSnapshot.docs.isNotEmpty) {
        return legacyPlaceSnapshot.docs.first;
      }
      return null;
    }

    if (verificationMethod == BusinessVerificationMethod.manualReview &&
        website.trim().isNotEmpty) {
      final websiteSnapshot = await firestore
          .collection(FirestoreCollections.businesses)
          .where('website', isEqualTo: website.trim())
          .limit(1)
          .get();
      if (websiteSnapshot.docs.isNotEmpty) {
        return websiteSnapshot.docs.first;
      }
    }
    return null;
  }

  String _normalizeWebsite(String website) {
    final trimmed = website.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final uri = Uri.tryParse(
      trimmed.startsWith('http://') || trimmed.startsWith('https://')
          ? trimmed
          : 'https://$trimmed',
    );
    if (uri == null || uri.host.trim().isEmpty) {
      return trimmed;
    }

    final normalizedHost = uri.host.trim().toLowerCase();
    final normalizedPath = uri.path == '/'
        ? ''
        : uri.path.replaceAll(RegExp(r'/$'), '');
    final normalized = Uri(
      scheme: 'https',
      host: normalizedHost,
      path: normalizedPath,
      query: uri.hasQuery ? uri.query : null,
    ).toString();
    return normalized.endsWith('/') && normalizedPath.isEmpty
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
  }

  bool _emailMatchesWebsiteDomain({
    required String email,
    required String website,
  }) {
    final emailParts = email.split('@');
    if (emailParts.length != 2) {
      return false;
    }
    final emailDomain = emailParts.last.toLowerCase();
    final uri = Uri.tryParse(
      website.startsWith('http://') || website.startsWith('https://')
          ? website
          : 'https://$website',
    );
    final host = uri?.host.toLowerCase() ?? '';
    if (host.isEmpty) {
      return false;
    }
    final normalizedHost = host.startsWith('www.') ? host.substring(4) : host;
    final normalizedEmailDomain = emailDomain.startsWith('www.')
        ? emailDomain.substring(4)
        : emailDomain;
    return normalizedEmailDomain == normalizedHost ||
        normalizedEmailDomain.endsWith('.$normalizedHost') ||
        normalizedHost.endsWith('.$normalizedEmailDomain');
  }

  bool _isPrivateMailboxDomain(String email) {
    final parts = email.split('@');
    if (parts.length != 2) {
      return true;
    }
    const blockedDomains = <String>{
      'gmail.com',
      'googlemail.com',
      'outlook.com',
      'hotmail.com',
      'live.de',
      'live.com',
      'web.de',
      'gmx.de',
      'gmx.net',
      'icloud.com',
      'me.com',
      'yahoo.com',
      'yahoo.de',
      'proton.me',
      'protonmail.com',
    };
    return blockedDomains.contains(parts.last.toLowerCase());
  }

  Deal fallbackDeal({String id = 'deal_placeholder'}) {
    return Deal(
      id: id,
      businessId: 'business_placeholder',
      title: 'Coupon folgt',
      subtitle: 'Sobald ein Deal live ist, erscheint er hier.',
      description: 'Noch kein Deal vorhanden.',
      city: 'Deutschlandweit',
      district: 'Dein Viertel',
      category: DealCategory.food,
      type: DealType.percentage,
      tags: const <OfferTag>[OfferTag.fresh],
      distanceKm: 0,
      reviewCount: 0,
      stats: const DealStats(
        views: 0,
        saves: 0,
        activations: 0,
        redemptions: 0,
        rating: 0,
        friendCount: 0,
        todayRedemptions: 0,
      ),
      validUntil: DateTime.now().add(const Duration(days: 7)),
      originalPrice: 0,
      discountedPrice: 0,
      savingsPercent: 0,
      priceHint: 'Direkt verfügbar',
      redemptionCode: 'SPARGO',
      highlights: const <String>['Noch kein Highlight'],
      conditions: const <String>['Noch keine Bedingungen'],
      galleryLabels: const <String>['Coupon'],
      palette: const <int>[0xFFDB2149, 0xFFF06B84],
      socialProof: 'Neu im Feed',
      availabilityLabel: 'Demnächst',
      ctaLabel: 'Gutschein aktivieren',
      validDays: const <String>['Mo', 'Di', 'Mi', 'Do', 'Fr'],
      openNow: false,
    );
  }

  Story fallbackStory({String id = 'story_placeholder'}) {
    return Story(
      id: id,
      businessId: 'business_placeholder',
      businessName: 'sparGO',
      city: 'Deutschlandweit',
      label: 'Story',
      previewPalette: const <int>[0xFFDB2149, 0xFFF06B84],
      items: const <StoryItem>[
        StoryItem(
          id: 'story_placeholder_item',
          type: StoryType.deal,
          title: 'Noch keine Story',
          subtitle: 'Sobald eine Story live ist, erscheint sie hier.',
          body: 'Business Stories können direkt aus dem Dashboard live gehen.',
          ctaLabel: 'Schließen',
          palette: <int>[0xFFDB2149, 0xFFF06B84],
          duration: Duration(seconds: 4),
          imageUrl: '',
        ),
      ],
      timeLabel: 'Jetzt',
    );
  }

  Future<void> _ensureUserDocument(
    firebase_auth.User? authUser, {
    required String preferredName,
  }) async {
    if (authUser == null) {
      return;
    }

    final snapshot = await _userDoc(authUser.uid).get();
    if (snapshot.exists) {
      return;
    }

    final user = User(
      id: authUser.uid,
      accountType: AccountType.user,
      name: preferredName,
      handle: '@${preferredName.toLowerCase().replaceAll(' ', '')}',
      city: 'Deutschlandweit',
      district: 'Dein Viertel',
      avatarInitials: FirebaseMappers.initials(preferredName),
      favoriteCategories: const <DealCategory>[],
      savedDealIds: const <String>[],
      activeDealIds: const <String>[],
      followingBusinessIds: const <String>[],
      rewards: const <Reward>[],
      points: 0,
      freeCouponCredits: 0,
      inviteCode: _inviteCodeFor(authUser.uid),
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

    await _userDoc(authUser.uid).set(<String, dynamic>{
      ...FirebaseMappers.userToMap(user),
      'activeDeviceId': '',
      'activeDeviceLabel': '',
      'activeSessionStartedAt': null,
      ..._clearedPendingDeviceSessionData(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<DeviceLoginResult> _completeAuthenticatedDeviceSession({
    required String email,
    required DeviceSessionInfo device,
  }) async {
    final authUser = auth.currentUser;
    if (authUser == null) {
      throw StateError('No authenticated user available after sign-in.');
    }

    if (authUser.isAnonymous) {
      await _setActiveDeviceSession(userId: authUser.uid, device: device);
      return const DeviceLoginResult.success();
    }

    final snapshot = await _userDoc(authUser.uid).get();
    final data = snapshot.data() ?? const <String, dynamic>{};
    final activeDeviceId = (data['activeDeviceId'] as String?)?.trim() ?? '';

    if (activeDeviceId.isEmpty || activeDeviceId == device.id) {
      await _setActiveDeviceSession(userId: authUser.uid, device: device);
      return const DeviceLoginResult.success();
    }

    try {
      await _queueDeviceApprovalEmail(
        authUser: authUser,
        userId: authUser.uid,
        device: device,
      );
    } catch (error) {
      await auth.signOut();
      rethrow;
    }

    await auth.signOut();
    return DeviceLoginResult.approvalRequired(
      email: email,
      deviceLabel: device.label,
    );
  }

  Future<void> _queueDeviceApprovalEmail({
    required firebase_auth.User authUser,
    required String userId,
    required DeviceSessionInfo device,
  }) async {
    final token = _generateDeviceApprovalToken();
    final expiresAt = DateTime.now().add(const Duration(minutes: 20));
    final continueUrl = Uri.parse(kDeviceApprovalContinueBaseUrl).replace(
      queryParameters: <String, String>{
        'approveDevice': '1',
        'uid': userId,
        'token': token,
      },
    );

    await _userDoc(userId).set(<String, dynamic>{
      'pendingDeviceId': device.id,
      'pendingDeviceLabel': device.label,
      'pendingDeviceApprovalToken': token,
      'pendingDeviceApprovalRequestedAt': FieldValue.serverTimestamp(),
      'pendingDeviceApprovalExpiresAt': Timestamp.fromDate(expiresAt),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final actionCodeSettings = firebase_auth.ActionCodeSettings(
      url: continueUrl.toString(),
      handleCodeInApp: false,
      androidPackageName: 'com.example.spargo',
      androidInstallApp: true,
      iOSBundleId: DefaultFirebaseOptions.ios.iosBundleId,
    );

    try {
      await authUser.sendEmailVerification(actionCodeSettings);
    } on firebase_auth.FirebaseAuthException {
      final email = authUser.email?.trim() ?? '';
      if (email.isEmpty) {
        rethrow;
      }
      await auth.sendSignInLinkToEmail(
        email: email,
        actionCodeSettings: actionCodeSettings,
      );
    }
  }

  Future<void> _setActiveDeviceSession({
    required String userId,
    required DeviceSessionInfo device,
  }) {
    return _userDoc(userId).set(<String, dynamic>{
      ..._activeDeviceSessionData(device),
      ..._clearedPendingDeviceSessionData(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Map<String, dynamic> _activeDeviceSessionData(DeviceSessionInfo device) {
    return <String, dynamic>{
      'activeDeviceId': device.id,
      'activeDeviceLabel': device.label,
      'activeSessionStartedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> _clearedPendingDeviceSessionData() {
    return <String, dynamic>{
      'pendingDeviceId': '',
      'pendingDeviceLabel': '',
      'pendingDeviceApprovalToken': '',
      'pendingDeviceApprovalRequestedAt': null,
      'pendingDeviceApprovalExpiresAt': null,
    };
  }

  String _generateDeviceApprovalToken() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Future<String> _uploadBytes(
    String path,
    Uint8List bytes, {
    String contentType = 'image/png',
  }) async {
    final currentUser = auth.currentUser;
    if (currentUser != null && !currentUser.isAnonymous) {
      try {
        await currentUser.getIdToken(true);
      } catch (error) {
        debugPrint('Storage auth token refresh failed before upload: $error');
      }
    }
    final ref = storage.ref(path);
    final metadata = SettableMetadata(contentType: contentType);
    await ref.putData(bytes, metadata);
    return ref.getDownloadURL();
  }

  Future<void> _ensureBusinessMemberAccess({
    required String userId,
    required Business business,
  }) async {
    final businessId = business.id.trim();
    final effectiveUserId = (auth.currentUser?.uid ?? userId).trim();
    if (effectiveUserId.isEmpty || businessId.isEmpty) {
      return;
    }

    await repairOwnedBusinessLink(
      userId: effectiveUserId,
      businessId: businessId,
    );

    try {
      await _businessDoc(businessId).set(<String, dynamic>{
        'assignedUserIds': FieldValue.arrayUnion(<String>[effectiveUserId]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('ensureBusinessMemberAccess failed for $businessId: $error');
    }
  }

  Future<String> _tryBusinessAssetUpload(
    Future<String> Function() upload, {
    required String debugLabel,
  }) async {
    try {
      return await upload();
    } catch (error) {
      debugPrint('Business asset upload failed for $debugLabel: $error');
      return '';
    }
  }

  Future<void> _notifyFollowersForBusiness({
    required Business business,
    required String title,
    required String body,
    required NotificationType type,
    String? dealId,
  }) async {
    // Follower fan-out is handled server-side via Cloud Functions.
    // The client must not read other user documents to discover followers.
    return;
  }

  Future<void> cachePublicCouponBundle({
    required String userId,
    required String requestKey,
    required String cacheScopeKey,
    required PublicCouponBundle bundle,
    bool replaceExisting = false,
  }) async {
    final normalizedUserId = userId.trim();
    final normalizedRequestKey = requestKey.trim();
    final normalizedScopeKey = cacheScopeKey.trim();
    if (normalizedUserId.isEmpty || normalizedRequestKey.isEmpty) {
      return;
    }
    final cacheImportedAt = DateTime.now();
    final cacheExpiresAt = cacheImportedAt.add(const Duration(days: 30));
    final requestHash = _stableStringHash(
      normalizedRequestKey,
    ).toRadixString(16);

    final limitedDeals = bundle.deals.take(48).toList(growable: false);
    final referencedBusinessIds = limitedDeals
        .map((deal) => deal.businessId)
        .toSet();
    final bundleBusinessesById = <String, Business>{
      for (final business in bundle.businesses) business.id: business,
    };
    final limitedBusinesses = referencedBusinessIds
        .map(
          (businessId) =>
              bundleBusinessesById[businessId] ?? businessById(businessId),
        )
        .where(
          (business) =>
              business.id.isNotEmpty && business.website.trim().isNotEmpty,
        )
        .take(48)
        .toList(growable: false);
    final scopedBusinesses = <Business>[];
    final businessIdMap = <String, String>{};
    final sourceBusinessIdByScopedId = <String, String>{};
    for (final business in limitedBusinesses) {
      final scopedBusinessId =
          'pcbizapp_${requestHash}_${_stableStringHash(business.id).toRadixString(16)}';
      businessIdMap[business.id] = scopedBusinessId;
      sourceBusinessIdByScopedId[scopedBusinessId] = business.id;
      scopedBusinesses.add(
        business.copyWith(
          id: scopedBusinessId,
          branches: business.branches
              .map(
                (branch) => branch.copyWith(
                  id: '${scopedBusinessId}_${_stableStringHash(branch.id.isEmpty ? branch.address : branch.id).toRadixString(16)}',
                ),
              )
              .toList(growable: false),
        ),
      );
    }
    final scopedDeals = <Deal>[];
    final sourceDealIdByScopedId = <String, String>{};
    for (final deal in limitedDeals) {
      final scopedBusinessId = businessIdMap[deal.businessId];
      if (scopedBusinessId == null) {
        continue;
      }
      final scopedDealId =
          'pcdealapp_${requestHash}_${_stableStringHash('${deal.businessId}|${deal.sourceUrl}|${deal.title}').toRadixString(16)}';
      sourceDealIdByScopedId[scopedDealId] = deal.id;
      scopedDeals.add(
        deal.copyWith(id: scopedDealId, businessId: scopedBusinessId),
      );
    }
    int readInt(Map<String, dynamic>? map, String key, [int fallback = 0]) =>
        (map?[key] as num?)?.toInt() ?? fallback;
    double readDouble(
      Map<String, dynamic>? map,
      String key, [
      double fallback = 0,
    ]) => (map?[key] as num?)?.toDouble() ?? fallback;
    String readString(
      Map<String, dynamic>? map,
      String key, [
      String fallback = '',
    ]) {
      final value = map?[key];
      if (value is String && value.trim().isNotEmpty) {
        return value;
      }
      return fallback;
    }

    Map<String, dynamic> readMap(Map<String, dynamic>? map, String key) {
      final value = map?[key];
      if (value is Map<String, dynamic>) {
        return value;
      }
      if (value is Map) {
        return value.map(
          (dynamic mapKey, dynamic mapValue) =>
              MapEntry(mapKey.toString(), mapValue),
        );
      }
      return <String, dynamic>{};
    }

    final batch = firestore.batch();
    final keptBusinessIds = scopedBusinesses
        .map((business) => business.id)
        .toSet();
    final keptDealIds = scopedDeals.map((deal) => deal.id).toSet();

    if (replaceExisting) {
      await _markMissingPublicCouponCacheItemsStale(
        requestKey: normalizedRequestKey,
        keptBusinessIds: keptBusinessIds,
        keptDealIds: keptDealIds,
      );
    }

    final existingBusinessSnapshots = await Future.wait(
      scopedBusinesses.map(
        (business) => _publicCouponBusinessDoc(business.id).get(),
      ),
    );
    final existingBusinessDataById = <String, Map<String, dynamic>>{};
    for (final snapshot in existingBusinessSnapshots) {
      if (snapshot.exists) {
        existingBusinessDataById[snapshot.id] =
            snapshot.data() ?? <String, dynamic>{};
      }
    }

    final existingDealSnapshots = await Future.wait(
      scopedDeals.map((deal) => _publicCouponDealDoc(deal.id).get()),
    );
    final existingDealDataById = <String, Map<String, dynamic>>{};
    for (final snapshot in existingDealSnapshots) {
      if (snapshot.exists) {
        existingDealDataById[snapshot.id] =
            snapshot.data() ?? <String, dynamic>{};
      }
    }

    for (final business in scopedBusinesses) {
      final existing = existingBusinessDataById[business.id];
      final analyticsMap = readMap(
        FirebaseMappers.businessToMap(business),
        'analytics',
      );
      final existingAnalytics = readMap(existing, 'analytics');
      batch.set(
        firestore
            .collection(FirestoreCollections.publicCouponBusinesses)
            .doc(business.id),
        <String, dynamic>{
          ...FirebaseMappers.businessToMap(business),
          'rating': business.rating,
          'reviewCount': business.reviewCount,
          'followerCount': readInt(
            existing,
            'followerCount',
            business.followerCount,
          ),
          'imageUrl': business.imageUrl.trim().isNotEmpty
              ? business.imageUrl
              : readString(existing, 'imageUrl'),
          'analytics': <String, dynamic>{
            ...analyticsMap,
            'views': readInt(
              existingAnalytics,
              'views',
              readInt(analyticsMap, 'views'),
            ),
            'saves': readInt(
              existingAnalytics,
              'saves',
              readInt(analyticsMap, 'saves'),
            ),
            'activations': readInt(
              existingAnalytics,
              'activations',
              readInt(analyticsMap, 'activations'),
            ),
            'redemptions': readInt(
              existingAnalytics,
              'redemptions',
              readInt(analyticsMap, 'redemptions'),
            ),
            'reach': readInt(
              existingAnalytics,
              'reach',
              readInt(analyticsMap, 'reach'),
            ),
            'trendPoints':
                existingAnalytics['trendPoints'] ??
                analyticsMap['trendPoints'] ??
                const <int>[],
          },
          'cacheSourceBusinessId': sourceBusinessIdByScopedId[business.id],
          'cacheImportedByUserId': normalizedUserId,
          'cacheRequestKey': normalizedRequestKey,
          'cacheScopeKey': normalizedScopeKey,
          'cacheImportedAt': Timestamp.fromDate(cacheImportedAt),
          'cacheExpiresAt': Timestamp.fromDate(cacheExpiresAt),
          'cacheVisibility': 'public',
          'cacheType': 'publicCouponBusiness',
        },
        SetOptions(merge: true),
      );
    }

    for (final deal in scopedDeals) {
      final existing = existingDealDataById[deal.id];
      final dealMap = FirebaseMappers.dealToMap(deal);
      final statsMap = readMap(dealMap, 'stats');
      final existingStats = readMap(existing, 'stats');
      batch.set(
        firestore
            .collection(FirestoreCollections.publicCouponDeals)
            .doc(deal.id),
        <String, dynamic>{
          ...dealMap,
          'reviewCount': deal.reviewCount,
          'imageUrl': deal.imageUrl.trim().isNotEmpty
              ? deal.imageUrl
              : readString(existing, 'imageUrl'),
          'stats': <String, dynamic>{
            ...statsMap,
            'views': readInt(
              existingStats,
              'views',
              readInt(statsMap, 'views'),
            ),
            'saves': readInt(
              existingStats,
              'saves',
              readInt(statsMap, 'saves'),
            ),
            'activations': readInt(
              existingStats,
              'activations',
              readInt(statsMap, 'activations'),
            ),
            'redemptions': readInt(
              existingStats,
              'redemptions',
              readInt(statsMap, 'redemptions'),
            ),
            'rating': readDouble(statsMap, 'rating'),
            'friendCount': readInt(
              existingStats,
              'friendCount',
              readInt(statsMap, 'friendCount'),
            ),
            'todayRedemptions': readInt(
              existingStats,
              'todayRedemptions',
              readInt(statsMap, 'todayRedemptions'),
            ),
          },
          'cacheSourceDealId': sourceDealIdByScopedId[deal.id],
          'cacheImportedByUserId': normalizedUserId,
          'cacheRequestKey': normalizedRequestKey,
          'cacheScopeKey': normalizedScopeKey,
          'cacheImportedAt': Timestamp.fromDate(cacheImportedAt),
          'cacheExpiresAt': Timestamp.fromDate(cacheExpiresAt),
          'cacheVisibility': 'public',
          'cacheType': 'publicCouponDeal',
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();
  }

  Future<void> _markMissingPublicCouponCacheItemsStale({
    required String requestKey,
    required Set<String> keptBusinessIds,
    required Set<String> keptDealIds,
  }) async {
    final staleAt = DateTime.now().add(const Duration(days: 7));
    final staleTimestamp = Timestamp.fromDate(staleAt);
    final batch = firestore.batch();

    final existingBusinessDocs = await firestore
        .collection(FirestoreCollections.publicCouponBusinesses)
        .where('cacheVisibility', isEqualTo: 'public')
        .where('cacheRequestKey', isEqualTo: requestKey)
        .get();
    for (final doc in existingBusinessDocs.docs) {
      if (keptBusinessIds.contains(doc.id)) {
        continue;
      }
      batch.set(doc.reference, <String, dynamic>{
        'cacheExpiresAt': staleTimestamp,
        'cacheLastMissingAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    final existingDealDocs = await firestore
        .collection(FirestoreCollections.publicCouponDeals)
        .where('cacheVisibility', isEqualTo: 'public')
        .where('cacheRequestKey', isEqualTo: requestKey)
        .get();
    for (final doc in existingDealDocs.docs) {
      if (keptDealIds.contains(doc.id)) {
        continue;
      }
      batch.set(doc.reference, <String, dynamic>{
        'cacheExpiresAt': staleTimestamp,
        'cacheLastMissingAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  Future<void> enqueuePublicCouponScanJob({
    required String userId,
    required String jobId,
    required String requestKey,
    required String cacheScopeKey,
    required String city,
    required String district,
    required double latitude,
    required double longitude,
    required double radiusKm,
    bool force = false,
  }) async {
    final normalizedUserId = userId.trim();
    final normalizedJobId = jobId.trim();
    final normalizedRequestKey = requestKey.trim();
    if (normalizedUserId.isEmpty ||
        normalizedJobId.isEmpty ||
        normalizedRequestKey.isEmpty) {
      return;
    }

    final now = Timestamp.now();
    await firestore
        .collection(FirestoreCollections.publicCouponScanJobs)
        .doc(normalizedJobId)
        .set(<String, dynamic>{
          'userId': normalizedUserId,
          'requestKey': normalizedRequestKey,
          'cacheScopeKey': cacheScopeKey.trim(),
          'status': 'queued',
          'force': force,
          'city': city.trim(),
          'district': district.trim(),
          'latitude': latitude,
          'longitude': longitude,
          'radiusKm': radiusKm.clamp(1.0, 100.0),
          'requestedAt': now,
          'updatedAt': now,
          'error': '',
          'requestNonce': FieldValue.increment(1),
        }, SetOptions(merge: true));
  }

  DocumentReference<Map<String, dynamic>> _userDoc(String id) =>
      firestore.collection(FirestoreCollections.users).doc(id);

  DocumentReference<Map<String, dynamic>> _businessDoc(String id) =>
      firestore.collection(FirestoreCollections.businesses).doc(id);

  DocumentReference<Map<String, dynamic>> _dealDoc(String id) =>
      firestore.collection(FirestoreCollections.deals).doc(id);

  DocumentReference<Map<String, dynamic>> _publicCouponDealDoc(String id) =>
      firestore.collection(FirestoreCollections.publicCouponDeals).doc(id);

  DocumentReference<Map<String, dynamic>> _publicCouponBusinessDoc(String id) =>
      firestore.collection(FirestoreCollections.publicCouponBusinesses).doc(id);

  DocumentReference<Map<String, dynamic>> _storyDoc(String id) =>
      firestore.collection(FirestoreCollections.stories).doc(id);

  DocumentReference<Map<String, dynamic>> _redemptionDoc(String id) =>
      firestore.collection(FirestoreCollections.redemptions).doc(id);

  DocumentReference<Map<String, dynamic>> _notificationDoc(String id) =>
      firestore.collection(FirestoreCollections.notifications).doc(id);

  DocumentReference<Map<String, dynamic>> _reviewDoc(String id) =>
      firestore.collection(FirestoreCollections.reviews).doc(id);

  DocumentReference<Map<String, dynamic>> _dealMetricsDoc(Deal deal) =>
      deal.isThirdParty ? _publicCouponDealDoc(deal.id) : _dealDoc(deal.id);

  DocumentReference<Map<String, dynamic>> _businessMetricsDoc(
    Business business,
  ) => _isPublicCouponBusinessId(business.id)
      ? _publicCouponBusinessDoc(business.id)
      : _businessDoc(business.id);

  Future<void> _syncReviewAggregates({
    String? dealId,
    String? businessId,
  }) async {
    if (dealId != null && dealId.trim().isNotEmpty) {
      await _syncDealReviewAggregate(dealId);
    }
    if (businessId != null && businessId.trim().isNotEmpty) {
      await _syncBusinessReviewAggregate(businessId);
    }
  }

  Future<void> _syncDealReviewAggregate(String dealId) async {
    final snapshot = await firestore
        .collection(FirestoreCollections.reviews)
        .where('dealId', isEqualTo: dealId)
        .get();
    final rating = _averageReviewRating(snapshot.docs);
    final reviewCount = snapshot.docs.length;
    final doc = _isPublicCouponDealId(dealId)
        ? _publicCouponDealDoc(dealId)
        : _dealDoc(dealId);
    await _setIfDocExists(doc, <String, dynamic>{
      'reviewCount': reviewCount,
      'stats.rating': rating,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _syncBusinessReviewAggregate(String businessId) async {
    final snapshot = await firestore
        .collection(FirestoreCollections.reviews)
        .where('businessId', isEqualTo: businessId)
        .get();
    final rating = _averageReviewRating(snapshot.docs);
    final reviewCount = snapshot.docs.length;
    final doc = _isPublicCouponBusinessId(businessId)
        ? _publicCouponBusinessDoc(businessId)
        : _businessDoc(businessId);
    await _setIfDocExists(doc, <String, dynamic>{
      'reviewCount': reviewCount,
      'rating': rating,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  double _averageReviewRating(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (docs.isEmpty) {
      return 0;
    }
    final total = docs.fold<double>(
      0,
      (sum, doc) => sum + ((doc.data()['rating'] as num?)?.toDouble() ?? 0),
    );
    return total / docs.length;
  }

  Future<void> _setIfDocExists(
    DocumentReference<Map<String, dynamic>> doc,
    Map<String, dynamic> data,
  ) async {
    final snapshot = await doc.get();
    if (!snapshot.exists) {
      return;
    }
    await doc.set(data, SetOptions(merge: true));
  }

  int _sortByDistance(Deal a, Deal b) => a.distanceKm.compareTo(b.distanceKm);

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

  int _stableStringHash(String value) {
    var hash = 2166136261;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash;
  }

  String _inviteCodeFor(String userId) {
    final seed = userId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    final head = seed.length >= 5
        ? seed.substring(0, 5)
        : seed.padRight(5, 'X');
    return 'SP-$head';
  }

  Map<String, dynamic> _businessAnalyticsToMap(BusinessAnalytics analytics) {
    return <String, dynamic>{
      'views': analytics.views,
      'saves': analytics.saves,
      'activations': analytics.activations,
      'redemptions': analytics.redemptions,
      'reach': analytics.reach,
      'trendPoints': analytics.trendPoints,
    };
  }
}

const List<BusinessHours> _defaultHours = <BusinessHours>[
  BusinessHours(day: 'Mo', opensAt: '09:00', closesAt: '18:00'),
  BusinessHours(day: 'Di', opensAt: '09:00', closesAt: '18:00'),
  BusinessHours(day: 'Mi', opensAt: '09:00', closesAt: '18:00'),
  BusinessHours(day: 'Do', opensAt: '09:00', closesAt: '18:00'),
  BusinessHours(day: 'Fr', opensAt: '09:00', closesAt: '18:00'),
  BusinessHours(day: 'Sa', opensAt: '10:00', closesAt: '16:00'),
  BusinessHours(day: 'So', opensAt: '10:00', closesAt: '14:00', isClosed: true),
];

String _availabilityLabelForDays(int days) {
  final normalized = days.clamp(1, 365).toInt();
  return switch (normalized) {
    1 => 'Heute',
    3 => '3 Tage',
    7 => '1 Woche',
    14 => '2 Wochen',
    30 => '30 Tage',
    60 => '60 Tage',
    90 => '90 Tage',
    _ => '$normalized Tage',
  };
}
