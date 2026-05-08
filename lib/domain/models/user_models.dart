import 'package:flutter/foundation.dart';

import 'deal_models.dart';

const Object _userFieldUnset = Object();

bool _safeBool(dynamic value, {bool fallback = false}) {
  return value is bool ? value : fallback;
}

double _safeDouble(dynamic value, {double fallback = 0}) {
  return value is num ? value.toDouble() : fallback;
}

enum AccountType { user, business }

extension AccountTypeX on AccountType {
  String get label => switch (this) {
    AccountType.user => 'Nutzer',
    AccountType.business => 'Unternehmen',
  };
}

@immutable
class Reward {
  const Reward({
    required this.id,
    required this.title,
    required this.points,
    required this.tier,
    required this.description,
    required this.unlocked,
  });

  final String id;
  final String title;
  final int points;
  final String tier;
  final String description;
  final bool unlocked;
}

@immutable
class UserPreferences {
  const UserPreferences({
    required this.interests,
    required this.city,
    required this.radiusKm,
    required this.notificationsEnabled,
    required this.socialProofEnabled,
    required this.openNowOnly,
    this.languageCode = 'de',
  });

  final List<DealCategory> interests;
  final String city;
  final double radiusKm;
  final bool notificationsEnabled;
  final bool socialProofEnabled;
  final bool openNowOnly;
  final String languageCode;

  UserPreferences copyWith({
    List<DealCategory>? interests,
    String? city,
    double? radiusKm,
    bool? notificationsEnabled,
    bool? socialProofEnabled,
    bool? openNowOnly,
    String? languageCode,
  }) {
    final current = this as dynamic;
    return UserPreferences(
      interests: interests ?? this.interests,
      city: city ?? this.city,
      radiusKm: radiusKm ?? _safeDouble(current.radiusKm, fallback: 35),
      notificationsEnabled:
          notificationsEnabled ??
          _safeBool(current.notificationsEnabled, fallback: true),
      socialProofEnabled:
          socialProofEnabled ??
          _safeBool(current.socialProofEnabled, fallback: true),
      openNowOnly:
          openNowOnly ?? _safeBool(current.openNowOnly, fallback: false),
      languageCode:
          languageCode ??
          (current.languageCode is String
              ? (current.languageCode as String)
              : 'de'),
    );
  }
}

@immutable
class User {
  const User({
    required this.id,
    required this.accountType,
    required this.name,
    required this.handle,
    required this.city,
    required this.district,
    this.latitude,
    this.longitude,
    required this.avatarInitials,
    required this.favoriteCategories,
    required this.savedDealIds,
    required this.activeDealIds,
    required this.followingBusinessIds,
    this.seenStoryIds = const <String>[],
    required this.rewards,
    required this.points,
    required this.freeCouponCredits,
    required this.inviteCode,
    required this.streakDays,
    required this.preferences,
  });

  final String id;
  final AccountType accountType;
  final String name;
  final String handle;
  final String city;
  final String district;
  final double? latitude;
  final double? longitude;
  final String avatarInitials;
  final List<DealCategory> favoriteCategories;
  final List<String> savedDealIds;
  final List<String> activeDealIds;
  final List<String> followingBusinessIds;
  final List<String> seenStoryIds;
  final List<Reward> rewards;
  final int points;
  final int freeCouponCredits;
  final String inviteCode;
  final int streakDays;
  final UserPreferences preferences;

  User copyWith({
    String? id,
    AccountType? accountType,
    String? name,
    String? handle,
    String? city,
    String? district,
    Object? latitude = _userFieldUnset,
    Object? longitude = _userFieldUnset,
    String? avatarInitials,
    List<DealCategory>? favoriteCategories,
    List<String>? savedDealIds,
    List<String>? activeDealIds,
    List<String>? followingBusinessIds,
    List<String>? seenStoryIds,
    List<Reward>? rewards,
    int? points,
    int? freeCouponCredits,
    String? inviteCode,
    int? streakDays,
    UserPreferences? preferences,
  }) {
    return User(
      id: id ?? this.id,
      accountType: accountType ?? this.accountType,
      name: name ?? this.name,
      handle: handle ?? this.handle,
      city: city ?? this.city,
      district: district ?? this.district,
      latitude: identical(latitude, _userFieldUnset)
          ? this.latitude
          : latitude as double?,
      longitude: identical(longitude, _userFieldUnset)
          ? this.longitude
          : longitude as double?,
      avatarInitials: avatarInitials ?? this.avatarInitials,
      favoriteCategories: favoriteCategories ?? this.favoriteCategories,
      savedDealIds: savedDealIds ?? this.savedDealIds,
      activeDealIds: activeDealIds ?? this.activeDealIds,
      followingBusinessIds: followingBusinessIds ?? this.followingBusinessIds,
      seenStoryIds: seenStoryIds ?? this.seenStoryIds,
      rewards: rewards ?? this.rewards,
      points: points ?? this.points,
      freeCouponCredits: freeCouponCredits ?? this.freeCouponCredits,
      inviteCode: inviteCode ?? this.inviteCode,
      streakDays: streakDays ?? this.streakDays,
      preferences: preferences ?? this.preferences,
    );
  }
}
