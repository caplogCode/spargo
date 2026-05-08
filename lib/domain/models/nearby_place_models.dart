import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'deal_models.dart';

@immutable
class NearbySearchArea {
  const NearbySearchArea({
    required this.city,
    required this.district,
    required this.latitude,
    required this.longitude,
  });

  final String city;
  final String district;
  final double latitude;
  final double longitude;

  String get label => district.isEmpty ? city : '$district, $city';
}

@immutable
class NearbyPlace {
  const NearbyPlace({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.primaryType,
    required this.types,
    required this.rating,
    required this.userRatingCount,
    this.openNow,
    this.photoUrl,
    this.googleMapsUri,
    this.websiteUrl,
  });

  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String primaryType;
  final List<String> types;
  final double rating;
  final int userRatingCount;
  final bool? openNow;
  final String? photoUrl;
  final String? googleMapsUri;
  final String? websiteUrl;

  String get initials {
    final parts = name
        .split(' ')
        .where((part) => part.trim().isNotEmpty)
        .take(2)
        .toList();
    if (parts.isEmpty) {
      return 'SP';
    }
    return parts.map((part) => part.substring(0, 1)).join().toUpperCase();
  }

  DealCategory get category {
    final allTypes = <String>{
      primaryType,
      ...types,
    }.where((value) => value.isNotEmpty);
    if (allTypes.contains('bakery') ||
        allTypes.contains('breakfast_restaurant')) {
      return DealCategory.breakfast;
    }
    if (allTypes.contains('cafe')) {
      return DealCategory.cafe;
    }
    if (allTypes.contains('restaurant') ||
        allTypes.contains('meal_takeaway') ||
        allTypes.contains('meal_delivery')) {
      return DealCategory.food;
    }
    if (allTypes.contains('bar') || allTypes.contains('liquor_store')) {
      return DealCategory.drinks;
    }
    if (allTypes.contains('beauty_salon') ||
        allTypes.contains('hair_care') ||
        allTypes.contains('nail_salon')) {
      return DealCategory.beauty;
    }
    if (allTypes.contains('spa') || allTypes.contains('sauna')) {
      return DealCategory.wellness;
    }
    if (allTypes.contains('pharmacy') ||
        allTypes.contains('hospital') ||
        allTypes.contains('doctor') ||
        allTypes.contains('dentist') ||
        allTypes.contains('medical_lab') ||
        allTypes.contains('physiotherapist')) {
      return DealCategory.health;
    }
    if (allTypes.contains('veterinary_care') ||
        allTypes.contains('pet_store')) {
      return DealCategory.pets;
    }
    if (allTypes.contains('shopping_mall') ||
        allTypes.contains('clothing_store') ||
        allTypes.contains('shoe_store') ||
        allTypes.contains('jewelry_store') ||
        allTypes.contains('store')) {
      return DealCategory.shopping;
    }
    if (allTypes.contains('furniture_store') ||
        allTypes.contains('home_goods_store') ||
        allTypes.contains('hardware_store')) {
      return DealCategory.home;
    }
    if (allTypes.contains('gym')) {
      return DealCategory.fitness;
    }
    if (allTypes.contains('car_dealer') ||
        allTypes.contains('car_repair') ||
        allTypes.contains('car_wash') ||
        allTypes.contains('gas_station') ||
        allTypes.contains('electric_vehicle_charging_station')) {
      return DealCategory.automotive;
    }
    if (allTypes.contains('travel_agency') ||
        allTypes.contains('hotel') ||
        allTypes.contains('lodging')) {
      return DealCategory.travel;
    }
    if (allTypes.contains('museum') ||
        allTypes.contains('art_gallery') ||
        allTypes.contains('performing_arts_theater') ||
        allTypes.contains('library')) {
      return DealCategory.culture;
    }
    if (allTypes.contains('tourist_attraction') ||
        allTypes.contains('bowling_alley')) {
      return DealCategory.experiences;
    }
    if (allTypes.contains('park')) {
      return DealCategory.parks;
    }
    if (allTypes.contains('amusement_park') ||
        allTypes.contains('zoo') ||
        allTypes.contains('aquarium') ||
        allTypes.contains('playground')) {
      return DealCategory.family;
    }
    if (allTypes.contains('laundry') ||
        allTypes.contains('dry_cleaning') ||
        allTypes.contains('locksmith') ||
        allTypes.contains('moving_company')) {
      return DealCategory.services;
    }
    if (allTypes.contains('night_club')) {
      return DealCategory.nightlife;
    }
    return DealCategory.leisure;
  }

  List<int> get palette => switch (category) {
    DealCategory.food => const <int>[0xFFDB2149, 0xFFF5987E, 0xFFFFF4EF],
    DealCategory.cafe => const <int>[0xFF7C4A36, 0xFFD29C7A, 0xFFFFF5ED],
    DealCategory.breakfast => const <int>[0xFFB56A1E, 0xFFFFC56B, 0xFFFFF7EE],
    DealCategory.drinks => const <int>[0xFF6F2959, 0xFFEAA2CF, 0xFFFFF4FB],
    DealCategory.beauty => const <int>[0xFF9D315E, 0xFFF3A1BE, 0xFFFFF4F8],
    DealCategory.shopping => const <int>[0xFF35537A, 0xFF8DB5E0, 0xFFF5FAFF],
    DealCategory.online => const <int>[0xFF2A6B6A, 0xFF86D8D2, 0xFFF2FFFD],
    DealCategory.leisure => const <int>[0xFF5D4A8B, 0xFFB49AF1, 0xFFF7F4FF],
    DealCategory.experiences => const <int>[0xFF88492B, 0xFFF3A57D, 0xFFFFF5EF],
    DealCategory.parks => const <int>[0xFF2E6A3B, 0xFF9FD58D, 0xFFF4FFF2],
    DealCategory.fitness => const <int>[0xFF173B45, 0xFF56A6B8, 0xFFF0FCFE],
    DealCategory.nightlife => const <int>[0xFF331B47, 0xFFBC6BE7, 0xFFF8F0FF],
    DealCategory.wellness => const <int>[0xFF26675B, 0xFF94D7C4, 0xFFF0FFF9],
    DealCategory.health => const <int>[0xFF156C8F, 0xFF7BC9E8, 0xFFF2FBFF],
    DealCategory.family => const <int>[0xFFB66219, 0xFFFFC76B, 0xFFFFF7ED],
    DealCategory.travel => const <int>[0xFF1F5D73, 0xFF8ED0E5, 0xFFF1FBFF],
    DealCategory.pets => const <int>[0xFF94612B, 0xFFE9BE81, 0xFFFFF8EF],
    DealCategory.home => const <int>[0xFF6B5B95, 0xFFC7B9E8, 0xFFF8F5FF],
    DealCategory.automotive => const <int>[0xFF354860, 0xFF8EA7C9, 0xFFF5F8FF],
    DealCategory.services => const <int>[0xFF57606B, 0xFFB3BCC6, 0xFFF7F9FB],
    DealCategory.culture => const <int>[0xFF7B3F61, 0xFFD9A8C7, 0xFFFFF5FB],
  };

  double distanceKmFrom(NearbySearchArea area) {
    const earthRadiusKm = 6371.0;
    final lat1 = _degToRad(area.latitude);
    final lat2 = _degToRad(latitude);
    final deltaLat = _degToRad(latitude - area.latitude);
    final deltaLng = _degToRad(longitude - area.longitude);
    final a =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLng / 2) *
            math.sin(deltaLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _degToRad(double degree) => degree * (math.pi / 180);
}
