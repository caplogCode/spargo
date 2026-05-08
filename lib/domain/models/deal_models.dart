import 'package:flutter/foundation.dart';

enum DealCategory {
  food,
  cafe,
  breakfast,
  drinks,
  beauty,
  shopping,
  online,
  leisure,
  experiences,
  parks,
  fitness,
  nightlife,
  wellness,
  health,
  family,
  travel,
  pets,
  home,
  automotive,
  services,
  culture,
}

extension DealCategoryX on DealCategory {
  String get label => switch (this) {
    DealCategory.food => 'Essen',
    DealCategory.cafe => 'Cafés',
    DealCategory.breakfast => 'Frühstück',
    DealCategory.drinks => 'Drinks',
    DealCategory.beauty => 'Beauty',
    DealCategory.shopping => 'Shopping',
    DealCategory.online => 'Online',
    DealCategory.leisure => 'Freizeit',
    DealCategory.experiences => 'Erlebnisse',
    DealCategory.parks => 'Parks',
    DealCategory.fitness => 'Fitness',
    DealCategory.nightlife => 'Nachtleben',
    DealCategory.wellness => 'Wellness',
    DealCategory.health => 'Gesundheit',
    DealCategory.family => 'Familie',
    DealCategory.travel => 'Reisen',
    DealCategory.pets => 'Haustiere',
    DealCategory.home => 'Zuhause',
    DealCategory.automotive => 'Auto',
    DealCategory.services => 'Service',
    DealCategory.culture => 'Kultur',
  };
}

enum DealType {
  percentage,
  exclusive,
  limitedTime,
  twoForOne,
  happyHour,
  event,
  newcomer,
}

extension DealTypeX on DealType {
  String get label => switch (this) {
    DealType.percentage => 'Rabatt',
    DealType.exclusive => 'Exklusiv',
    DealType.limitedTime => 'Zeitfenster',
    DealType.twoForOne => '2-für-1',
    DealType.happyHour => 'Happy Hour',
    DealType.event => 'Event Deal',
    DealType.newcomer => 'Neukundenaktion',
  };
}

enum DealSource { native, thirdParty }

extension DealSourceX on DealSource {
  String get label => switch (this) {
    DealSource.native => 'Direkt',
    DealSource.thirdParty => 'Drittquelle',
  };
}

enum OfferTag {
  exclusive,
  fresh,
  popular,
  today,
  almostGone,
  hiddenGem,
  topRated,
}

extension OfferTagX on OfferTag {
  String get label => switch (this) {
    OfferTag.exclusive => 'Exklusiv',
    OfferTag.fresh => 'Neu',
    OfferTag.popular => 'Beliebt',
    OfferTag.today => 'Nur heute',
    OfferTag.almostGone => 'Fast weg',
    OfferTag.hiddenGem => 'Geheimtipp',
    OfferTag.topRated => 'Top bewertet',
  };
}

@immutable
class DealStats {
  const DealStats({
    required this.views,
    required this.saves,
    required this.activations,
    required this.redemptions,
    required this.rating,
    required this.friendCount,
    required this.todayRedemptions,
  });

  final int views;
  final int saves;
  final int activations;
  final int redemptions;
  final double rating;
  final int friendCount;
  final int todayRedemptions;

  DealStats copyWith({
    int? views,
    int? saves,
    int? activations,
    int? redemptions,
    double? rating,
    int? friendCount,
    int? todayRedemptions,
  }) {
    return DealStats(
      views: views ?? this.views,
      saves: saves ?? this.saves,
      activations: activations ?? this.activations,
      redemptions: redemptions ?? this.redemptions,
      rating: rating ?? this.rating,
      friendCount: friendCount ?? this.friendCount,
      todayRedemptions: todayRedemptions ?? this.todayRedemptions,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'views': views,
    'saves': saves,
    'activations': activations,
    'redemptions': redemptions,
    'rating': rating,
    'friendCount': friendCount,
    'todayRedemptions': todayRedemptions,
  };

  factory DealStats.fromJson(Map<String, dynamic> json) {
    return DealStats(
      views: json['views'] as int,
      saves: json['saves'] as int,
      activations: json['activations'] as int,
      redemptions: json['redemptions'] as int,
      rating: (json['rating'] as num).toDouble(),
      friendCount: json['friendCount'] as int,
      todayRedemptions: json['todayRedemptions'] as int,
    );
  }
}

@immutable
class Deal {
  const Deal({
    required this.id,
    required this.businessId,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.city,
    required this.district,
    required this.category,
    required this.type,
    required this.tags,
    required this.distanceKm,
    required this.reviewCount,
    required this.stats,
    required this.validUntil,
    required this.originalPrice,
    required this.discountedPrice,
    required this.savingsPercent,
    required this.priceHint,
    required this.redemptionCode,
    required this.highlights,
    required this.conditions,
    required this.galleryLabels,
    required this.palette,
    required this.socialProof,
    required this.availabilityLabel,
    required this.ctaLabel,
    required this.validDays,
    required this.openNow,
    this.source = DealSource.native,
    this.sourceLabel = '',
    this.sourceUrl = '',
    this.imageUrl = '',
  });

  final String id;
  final String businessId;
  final String title;
  final String subtitle;
  final String description;
  final String city;
  final String district;
  final DealCategory category;
  final DealType type;
  final List<OfferTag> tags;
  final double distanceKm;
  final int reviewCount;
  final DealStats stats;
  final DateTime validUntil;
  final double originalPrice;
  final double discountedPrice;
  final int savingsPercent;
  final String priceHint;
  final String redemptionCode;
  final List<String> highlights;
  final List<String> conditions;
  final List<String> galleryLabels;
  final List<int> palette;
  final String socialProof;
  final String availabilityLabel;
  final String ctaLabel;
  final List<String> validDays;
  final bool openNow;
  final DealSource source;
  final String sourceLabel;
  final String sourceUrl;
  final String imageUrl;

  bool get isExpiringSoon => validUntil.difference(DateTime.now()).inHours < 36;
  bool get isThirdParty => source == DealSource.thirdParty;
  bool get hasMeasuredSavings => savingsPercent > 0;
  String get savingsBadgeLabel =>
      hasMeasuredSavings ? '$savingsPercent%' : (isThirdParty ? 'Deal' : '0%');
  String get savingsHighlightLabel => hasMeasuredSavings
      ? '$savingsPercent% Vorteil'
      : (isThirdParty ? 'Vorteil prüfen' : 'Vorteil');
  String get ratingLabel =>
      stats.rating > 0 ? stats.rating.toStringAsFixed(1) : 'Neu';

  Deal copyWith({
    String? id,
    String? businessId,
    String? title,
    String? subtitle,
    String? description,
    String? city,
    String? district,
    DealCategory? category,
    DealType? type,
    List<OfferTag>? tags,
    double? distanceKm,
    int? reviewCount,
    DealStats? stats,
    DateTime? validUntil,
    double? originalPrice,
    double? discountedPrice,
    int? savingsPercent,
    String? priceHint,
    String? redemptionCode,
    List<String>? highlights,
    List<String>? conditions,
    List<String>? galleryLabels,
    List<int>? palette,
    String? socialProof,
    String? availabilityLabel,
    String? ctaLabel,
    List<String>? validDays,
    bool? openNow,
    DealSource? source,
    String? sourceLabel,
    String? sourceUrl,
    String? imageUrl,
  }) {
    return Deal(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      description: description ?? this.description,
      city: city ?? this.city,
      district: district ?? this.district,
      category: category ?? this.category,
      type: type ?? this.type,
      tags: tags ?? this.tags,
      distanceKm: distanceKm ?? this.distanceKm,
      reviewCount: reviewCount ?? this.reviewCount,
      stats: stats ?? this.stats,
      validUntil: validUntil ?? this.validUntil,
      originalPrice: originalPrice ?? this.originalPrice,
      discountedPrice: discountedPrice ?? this.discountedPrice,
      savingsPercent: savingsPercent ?? this.savingsPercent,
      priceHint: priceHint ?? this.priceHint,
      redemptionCode: redemptionCode ?? this.redemptionCode,
      highlights: highlights ?? this.highlights,
      conditions: conditions ?? this.conditions,
      galleryLabels: galleryLabels ?? this.galleryLabels,
      palette: palette ?? this.palette,
      socialProof: socialProof ?? this.socialProof,
      availabilityLabel: availabilityLabel ?? this.availabilityLabel,
      ctaLabel: ctaLabel ?? this.ctaLabel,
      validDays: validDays ?? this.validDays,
      openNow: openNow ?? this.openNow,
      source: source ?? this.source,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }
}

@immutable
class SavedDeal {
  const SavedDeal({
    required this.id,
    required this.dealId,
    required this.savedAt,
    required this.collectionName,
  });

  final String id;
  final String dealId;
  final DateTime savedAt;
  final String collectionName;
}

enum RedemptionStatus { active, redeemed, expired }

extension RedemptionStatusX on RedemptionStatus {
  String get label => switch (this) {
    RedemptionStatus.active => 'Aktiv',
    RedemptionStatus.redeemed => 'Eingelöst',
    RedemptionStatus.expired => 'Abgelaufen',
  };
}

@immutable
class Redemption {
  const Redemption({
    required this.id,
    required this.dealId,
    required this.code,
    required this.couponId,
    required this.qrPayload,
    required this.activatedAt,
    required this.expiresAt,
    required this.status,
    required this.offlineReady,
    required this.instructions,
    this.savedAmountCents = 0,
    this.usedAt,
  });

  final String id;
  final String dealId;
  final String code;
  final String couponId;
  final String qrPayload;
  final DateTime activatedAt;
  final DateTime expiresAt;
  final RedemptionStatus status;
  final bool offlineReady;
  final String instructions;
  final int savedAmountCents;
  final DateTime? usedAt;

  double get savedAmount => savedAmountCents / 100;

  Redemption copyWith({
    String? id,
    String? dealId,
    String? code,
    String? couponId,
    String? qrPayload,
    DateTime? activatedAt,
    DateTime? expiresAt,
    RedemptionStatus? status,
    bool? offlineReady,
    String? instructions,
    int? savedAmountCents,
    DateTime? usedAt,
  }) {
    return Redemption(
      id: id ?? this.id,
      dealId: dealId ?? this.dealId,
      code: code ?? this.code,
      couponId: couponId ?? this.couponId,
      qrPayload: qrPayload ?? this.qrPayload,
      activatedAt: activatedAt ?? this.activatedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      status: status ?? this.status,
      offlineReady: offlineReady ?? this.offlineReady,
      instructions: instructions ?? this.instructions,
      savedAmountCents: savedAmountCents ?? this.savedAmountCents,
      usedAt: usedAt ?? this.usedAt,
    );
  }
}
