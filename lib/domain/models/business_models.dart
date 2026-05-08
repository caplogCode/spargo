import 'package:flutter/foundation.dart';

import 'deal_models.dart';

enum BusinessVerificationStatus { draft, pending, verified, rejected }

enum BusinessVerificationMethod {
  emailDomain,
  googleBusinessProfile,
  manualReview,
}

extension BusinessVerificationStatusX on BusinessVerificationStatus {
  String get label => switch (this) {
    BusinessVerificationStatus.draft => 'Nicht verifiziert',
    BusinessVerificationStatus.pending => 'Prüfung läuft',
    BusinessVerificationStatus.verified => 'Verifiziert',
    BusinessVerificationStatus.rejected => 'Daten korrigieren',
  };

  bool get isVerified => this == BusinessVerificationStatus.verified;
  bool get needsReview => this == BusinessVerificationStatus.pending;
}

extension BusinessVerificationMethodX on BusinessVerificationMethod {
  String get label => switch (this) {
    BusinessVerificationMethod.emailDomain => 'Website + Business-E-Mail',
    BusinessVerificationMethod.googleBusinessProfile =>
      'Google Business Profil',
    BusinessVerificationMethod.manualReview => 'Prüfung',
  };

  String get subtitle => switch (this) {
    BusinessVerificationMethod.emailDomain =>
      'Am schnellsten, wenn Website und Firmen-E-Mail schon zusammenpassen.',
    BusinessVerificationMethod.googleBusinessProfile =>
      'Für Betriebe ohne eigene Domain oder wenn das Profil schon bei Google verwaltet wird.',
    BusinessVerificationMethod.manualReview =>
      'Du kannst dein Studio sofort vorbereiten. Die Freigabe folgt separat.',
  };
}

@immutable
class BusinessGoogleProfileLink {
  const BusinessGoogleProfileLink({
    this.googleUserEmail = '',
    this.accountName = '',
    this.accountDisplayName = '',
    this.verificationSessionId = '',
    this.placeId = '',
    this.locationName = '',
    this.locationDisplayName = '',
    this.locationAddress = '',
    this.locationCity = '',
    this.website = '',
    this.phone = '',
    this.role = '',
  });

  final String googleUserEmail;
  final String accountName;
  final String accountDisplayName;
  final String verificationSessionId;
  final String placeId;
  final String locationName;
  final String locationDisplayName;
  final String locationAddress;
  final String locationCity;
  final String website;
  final String phone;
  final String role;

  static const Set<String> _acceptedRoles = <String>{
    'PRIMARY_OWNER',
    'OWNER',
    'CO_OWNER',
    'VERIFIED_COMPANY_IDENTITY',
    'VERIFIED_REGISTRY_DOCUMENT',
  };

  bool get isLinked => locationName.trim().isNotEmpty;

  String get normalizedRole => role.trim().toUpperCase();

  bool get grantsDashboardAccess => _acceptedRoles.contains(normalizedRole);

  bool get isPendingVerification =>
      normalizedRole == 'PENDING_GOOGLE_VERIFICATION';

  String get locationId {
    final parts = locationName.split('/');
    return parts.isEmpty ? '' : parts.last.trim();
  }

  String get roleLabel => switch (normalizedRole) {
    'PRIMARY_OWNER' => 'Primärer Inhaber',
    'OWNER' => 'Inhaber',
    'CO_OWNER' => 'Mitinhaber',
    'MANAGER' => 'Manager',
    'SITE_MANAGER' => 'Standortmanager',
    'COMMUNITY_MANAGER' => 'Community-Manager',
    'AUTHORIZED_GBP_USER' => 'Google-Business-Zugriff',
    'VERIFIED_COMPANY_IDENTITY' => 'Bestätigte Unternehmens-Identität',
    'VERIFIED_REGISTRY_DOCUMENT' => 'Register- und Dokumentenprüfung',
    'PENDING_GOOGLE_VERIFICATION' => 'Google-Prüfung läuft',
    'ADMIN' => 'Administrator',
    _ => role.trim().isEmpty ? 'Unbekannt' : role.trim(),
  };

  BusinessGoogleProfileLink copyWith({
    String? googleUserEmail,
    String? accountName,
    String? accountDisplayName,
    String? verificationSessionId,
    String? placeId,
    String? locationName,
    String? locationDisplayName,
    String? locationAddress,
    String? locationCity,
    String? website,
    String? phone,
    String? role,
  }) {
    return BusinessGoogleProfileLink(
      googleUserEmail: googleUserEmail ?? this.googleUserEmail,
      accountName: accountName ?? this.accountName,
      accountDisplayName: accountDisplayName ?? this.accountDisplayName,
      verificationSessionId:
          verificationSessionId ?? this.verificationSessionId,
      placeId: placeId ?? this.placeId,
      locationName: locationName ?? this.locationName,
      locationDisplayName: locationDisplayName ?? this.locationDisplayName,
      locationAddress: locationAddress ?? this.locationAddress,
      locationCity: locationCity ?? this.locationCity,
      website: website ?? this.website,
      phone: phone ?? this.phone,
      role: role ?? this.role,
    );
  }
}

@immutable
class BusinessHours {
  const BusinessHours({
    required this.day,
    required this.opensAt,
    required this.closesAt,
    this.isClosed = false,
  });

  final String day;
  final String opensAt;
  final String closesAt;
  final bool isClosed;
}

@immutable
class Branch {
  const Branch({
    required this.id,
    required this.name,
    required this.city,
    required this.district,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.hours,
  });

  final String id;
  final String name;
  final String city;
  final String district;
  final String address;
  final double latitude;
  final double longitude;
  final List<BusinessHours> hours;

  Branch copyWith({
    String? id,
    String? name,
    String? city,
    String? district,
    String? address,
    double? latitude,
    double? longitude,
    List<BusinessHours>? hours,
  }) {
    return Branch(
      id: id ?? this.id,
      name: name ?? this.name,
      city: city ?? this.city,
      district: district ?? this.district,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      hours: hours ?? this.hours,
    );
  }
}

@immutable
class BusinessAnalytics {
  const BusinessAnalytics({
    required this.views,
    required this.saves,
    required this.activations,
    required this.redemptions,
    required this.reach,
    required this.trendPoints,
  });

  final int views;
  final int saves;
  final int activations;
  final int redemptions;
  final int reach;
  final List<int> trendPoints;
}

@immutable
class Business {
  const Business({
    required this.id,
    required this.name,
    required this.tagline,
    required this.shortDescription,
    required this.description,
    required this.category,
    required this.city,
    required this.district,
    required this.rating,
    required this.reviewCount,
    required this.followerCount,
    required this.priceLevel,
    required this.tags,
    required this.coverPalette,
    required this.galleryLabels,
    required this.branches,
    required this.phone,
    required this.website,
    required this.distanceKm,
    required this.isTrending,
    required this.isNew,
    required this.analytics,
    this.contactEmail = '',
    this.legalEntityName = '',
    this.imprintInfo = '',
    this.verificationStatus = BusinessVerificationStatus.verified,
    this.verificationMethod = BusinessVerificationMethod.emailDomain,
    this.verificationRequestedAt,
    this.ownershipConfirmed = false,
    this.verificationPlaceId = '',
    this.verificationWebsite = '',
    this.claimedByName = '',
    this.claimedByRole = '',
    this.verificationNote = '',
    this.imageUrl = '',
    this.googleProfileLink = const BusinessGoogleProfileLink(),
  });

  final String id;
  final String name;
  final String tagline;
  final String shortDescription;
  final String description;
  final DealCategory category;
  final String city;
  final String district;
  final double rating;
  final int reviewCount;
  final int followerCount;
  final String priceLevel;
  final List<String> tags;
  final List<int> coverPalette;
  final List<String> galleryLabels;
  final List<Branch> branches;
  final String phone;
  final String website;
  final double distanceKm;
  final bool isTrending;
  final bool isNew;
  final BusinessAnalytics analytics;
  final String contactEmail;
  final String legalEntityName;
  final String imprintInfo;
  final BusinessVerificationStatus verificationStatus;
  final BusinessVerificationMethod verificationMethod;
  final DateTime? verificationRequestedAt;
  final bool ownershipConfirmed;
  final String verificationPlaceId;
  final String verificationWebsite;
  final String claimedByName;
  final String claimedByRole;
  final String verificationNote;
  final String imageUrl;
  final BusinessGoogleProfileLink googleProfileLink;

  Branch get primaryBranch {
    if (branches.isNotEmpty) {
      return branches.first;
    }

    final fallbackCity = city.trim().isEmpty ? 'Deutschlandweit' : city.trim();
    final fallbackDistrict = district.trim().isEmpty
        ? 'In deiner N\u00e4he'
        : district.trim();
    final fallbackAddress = <String>[
      fallbackDistrict,
      fallbackCity,
    ].where((entry) => entry.isNotEmpty).join(', ');

    return Branch(
      id: '${id}_branch_fallback',
      name: name.trim().isEmpty ? 'Standort' : name.trim(),
      city: fallbackCity,
      district: fallbackDistrict,
      address: fallbackAddress.isEmpty ? 'Adresse folgt' : fallbackAddress,
      latitude: 52.5200,
      longitude: 13.4050,
      hours: const <BusinessHours>[],
    );
  }

  bool get isVerified => verificationStatus.isVerified;

  Business copyWith({
    String? id,
    String? name,
    String? tagline,
    String? shortDescription,
    String? description,
    DealCategory? category,
    String? city,
    String? district,
    double? rating,
    int? reviewCount,
    int? followerCount,
    String? priceLevel,
    List<String>? tags,
    List<int>? coverPalette,
    List<String>? galleryLabels,
    List<Branch>? branches,
    String? phone,
    String? website,
    double? distanceKm,
    bool? isTrending,
    bool? isNew,
    BusinessAnalytics? analytics,
    String? contactEmail,
    String? legalEntityName,
    String? imprintInfo,
    BusinessVerificationStatus? verificationStatus,
    BusinessVerificationMethod? verificationMethod,
    DateTime? verificationRequestedAt,
    bool? ownershipConfirmed,
    String? verificationPlaceId,
    String? verificationWebsite,
    String? claimedByName,
    String? claimedByRole,
    String? verificationNote,
    String? imageUrl,
    BusinessGoogleProfileLink? googleProfileLink,
  }) {
    return Business(
      id: id ?? this.id,
      name: name ?? this.name,
      tagline: tagline ?? this.tagline,
      shortDescription: shortDescription ?? this.shortDescription,
      description: description ?? this.description,
      category: category ?? this.category,
      city: city ?? this.city,
      district: district ?? this.district,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      followerCount: followerCount ?? this.followerCount,
      priceLevel: priceLevel ?? this.priceLevel,
      tags: tags ?? this.tags,
      coverPalette: coverPalette ?? this.coverPalette,
      galleryLabels: galleryLabels ?? this.galleryLabels,
      branches: branches ?? this.branches,
      phone: phone ?? this.phone,
      website: website ?? this.website,
      distanceKm: distanceKm ?? this.distanceKm,
      isTrending: isTrending ?? this.isTrending,
      isNew: isNew ?? this.isNew,
      analytics: analytics ?? this.analytics,
      contactEmail: contactEmail ?? this.contactEmail,
      legalEntityName: legalEntityName ?? this.legalEntityName,
      imprintInfo: imprintInfo ?? this.imprintInfo,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      verificationMethod: verificationMethod ?? this.verificationMethod,
      verificationRequestedAt:
          verificationRequestedAt ?? this.verificationRequestedAt,
      ownershipConfirmed: ownershipConfirmed ?? this.ownershipConfirmed,
      verificationPlaceId: verificationPlaceId ?? this.verificationPlaceId,
      verificationWebsite: verificationWebsite ?? this.verificationWebsite,
      claimedByName: claimedByName ?? this.claimedByName,
      claimedByRole: claimedByRole ?? this.claimedByRole,
      verificationNote: verificationNote ?? this.verificationNote,
      imageUrl: imageUrl ?? this.imageUrl,
      googleProfileLink: googleProfileLink ?? this.googleProfileLink,
    );
  }
}



