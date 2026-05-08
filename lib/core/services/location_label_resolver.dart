import 'dart:math' as math;

import '../../data/services/google_maps_proxy_service.dart';
import '../../domain/models/business_models.dart';

class ResolvedLocationLabel {
  const ResolvedLocationLabel({required this.city, required this.district});

  final String city;
  final String district;
}

class ResolvedLocationCoordinates {
  const ResolvedLocationCoordinates({
    required this.city,
    required this.district,
    required this.latitude,
    required this.longitude,
  });

  final String city;
  final String district;
  final double latitude;
  final double longitude;
}

Future<ResolvedLocationLabel> resolveLocationLabel({
  required double latitude,
  required double longitude,
  required List<Business> businesses,
}) async {
  final liveLabel = await _reverseGeocodeGoogleMaps(
    latitude: latitude,
    longitude: longitude,
  );
  if (liveLabel != null) {
    return liveLabel;
  }

  final nearestBranch = _nearestBranch(
    latitude: latitude,
    longitude: longitude,
    businesses: businesses,
  );

  if (nearestBranch != null && nearestBranch.distanceKm <= 12) {
    return ResolvedLocationLabel(
      city: nearestBranch.branch.city,
      district: nearestBranch.branch.district.trim().isEmpty
          ? 'In deiner Naehe'
          : nearestBranch.branch.district,
    );
  }

  final nearestAnchor = _nearestAnchor(
    latitude: latitude,
    longitude: longitude,
  );
  if (nearestAnchor.distanceKm <= 6) {
    return ResolvedLocationLabel(
      city: nearestAnchor.anchor.city,
      district: nearestAnchor.anchor.district,
    );
  }

  return const ResolvedLocationLabel(
    city: 'Deutschlandweit',
    district: 'In deiner Naehe',
  );
}

Future<ResolvedLocationCoordinates?> resolveLocationCoordinates({
  required String city,
  required String district,
}) async {
  final normalizedCity = city.trim();
  if (normalizedCity.isEmpty || normalizedCity == 'Deutschlandweit') {
    return null;
  }

  final normalizedDistrict = district.trim();
  final fallback = resolveLocationCoordinatesFallbackSync(
    city: normalizedCity,
    district: normalizedDistrict,
  );
  final liveCoordinates = await _forwardGeocodeGoogleMaps(
    city: normalizedCity,
    district: normalizedDistrict,
  );
  return liveCoordinates ?? fallback;
}

ResolvedLocationCoordinates? resolveLocationCoordinatesFallbackSync({
  required String city,
  required String district,
}) {
  final normalizedCity = city.trim();
  if (normalizedCity.isEmpty || normalizedCity == 'Deutschlandweit') {
    return null;
  }

  final normalizedDistrict = district.trim();
  final anchor = _anchorForLocationLabel(
    city: normalizedCity,
    district: normalizedDistrict,
  );
  if (anchor == null) {
    return null;
  }

  final resolvedDistrict =
      normalizedDistrict.isEmpty ||
          normalizedDistrict == 'Dein Viertel' ||
          normalizedDistrict == 'In deiner Naehe' ||
          normalizedDistrict == 'Deine Naehe'
      ? anchor.district
      : normalizedDistrict;

  return ResolvedLocationCoordinates(
    city: anchor.city,
    district: resolvedDistrict,
    latitude: anchor.latitude,
    longitude: anchor.longitude,
  );
}

Future<ResolvedLocationLabel?> _reverseGeocodeGoogleMaps({
  required double latitude,
  required double longitude,
}) async {
  final service = GoogleMapsProxyService();
  try {
    final payload = await service.post(
      'googleMapsResolveLocation',
      <String, dynamic>{
        'mode': 'reverse',
        'latitude': latitude,
        'longitude': longitude,
      },
    );
    final city = payload?['city']?.toString().trim() ?? '';
    if (city.isEmpty) {
      return null;
    }
    final district = payload?['district']?.toString().trim();
    return ResolvedLocationLabel(
      city: city,
      district: district == null || district.isEmpty
          ? 'In deiner Naehe'
          : district,
    );
  } finally {
    service.close();
  }
}

Future<ResolvedLocationCoordinates?> _forwardGeocodeGoogleMaps({
  required String city,
  required String district,
}) async {
  final service = GoogleMapsProxyService();
  try {
    final payload = await service.post(
      'googleMapsResolveLocation',
      <String, dynamic>{'mode': 'forward', 'city': city, 'district': district},
    );
    final resolvedCity = payload?['city']?.toString().trim() ?? '';
    final resolvedDistrict = payload?['district']?.toString().trim() ?? '';
    final latitude = payload?['latitude'];
    final longitude = payload?['longitude'];
    if (resolvedCity.isEmpty ||
        resolvedDistrict.isEmpty ||
        latitude is! num ||
        longitude is! num) {
      return null;
    }

    return ResolvedLocationCoordinates(
      city: resolvedCity,
      district: resolvedDistrict,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
    );
  } finally {
    service.close();
  }
}

_NearestBranch? _nearestBranch({
  required double latitude,
  required double longitude,
  required List<Business> businesses,
}) {
  _NearestBranch? best;

  for (final business in businesses) {
    for (final branch in business.branches) {
      final distanceKm = _distanceBetweenKm(
        latitude,
        longitude,
        branch.latitude,
        branch.longitude,
      );
      if (best == null || distanceKm < best.distanceKm) {
        best = _NearestBranch(branch: branch, distanceKm: distanceKm);
      }
    }
  }

  return best;
}

_NearestAnchor _nearestAnchor({
  required double latitude,
  required double longitude,
}) {
  _LocationAnchor best = _anchors.first;
  var bestDistance = double.infinity;

  for (final anchor in _anchors) {
    final distance = _distanceBetweenKm(
      latitude,
      longitude,
      anchor.latitude,
      anchor.longitude,
    );
    if (distance < bestDistance) {
      bestDistance = distance;
      best = anchor;
    }
  }

  return _NearestAnchor(anchor: best, distanceKm: bestDistance);
}

_LocationAnchor? _anchorForLocationLabel({
  required String city,
  required String district,
}) {
  final normalizedCity = _normalizeLocationToken(city);
  final normalizedDistrict = _normalizeLocationToken(district);

  _LocationAnchor? cityMatch;
  for (final anchor in _anchors) {
    final anchorCity = _normalizeLocationToken(anchor.city);
    final anchorDistrict = _normalizeLocationToken(anchor.district);
    if (anchorCity != normalizedCity) {
      continue;
    }
    if (normalizedDistrict.isNotEmpty &&
        normalizedDistrict != 'dein viertel' &&
        normalizedDistrict != 'in deiner naehe' &&
        normalizedDistrict != 'deine naehe' &&
        anchorDistrict == normalizedDistrict) {
      return anchor;
    }
    cityMatch ??= anchor;
  }
  return cityMatch;
}

String _normalizeLocationToken(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss')
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

class _NearestBranch {
  const _NearestBranch({required this.branch, required this.distanceKm});

  final Branch branch;
  final double distanceKm;
}

class _NearestAnchor {
  const _NearestAnchor({required this.anchor, required this.distanceKm});

  final _LocationAnchor anchor;
  final double distanceKm;
}

class _LocationAnchor {
  const _LocationAnchor({
    required this.city,
    required this.district,
    required this.latitude,
    required this.longitude,
  });

  final String city;
  final String district;
  final double latitude;
  final double longitude;
}

const List<_LocationAnchor> _anchors = <_LocationAnchor>[
  _LocationAnchor(
    city: 'Berlin',
    district: 'Mitte',
    latitude: 52.5200,
    longitude: 13.4050,
  ),
  _LocationAnchor(
    city: 'Hamburg',
    district: 'Altstadt',
    latitude: 53.5511,
    longitude: 9.9937,
  ),
  _LocationAnchor(
    city: 'Muenchen',
    district: 'Maxvorstadt',
    latitude: 48.1374,
    longitude: 11.5755,
  ),
  _LocationAnchor(
    city: 'Koeln',
    district: 'Innenstadt',
    latitude: 50.9375,
    longitude: 6.9603,
  ),
  _LocationAnchor(
    city: 'Frankfurt am Main',
    district: 'Innenstadt',
    latitude: 50.1109,
    longitude: 8.6821,
  ),
  _LocationAnchor(
    city: 'Stuttgart',
    district: 'Mitte',
    latitude: 48.7758,
    longitude: 9.1829,
  ),
  _LocationAnchor(
    city: 'Duesseldorf',
    district: 'Stadtmitte',
    latitude: 51.2277,
    longitude: 6.7735,
  ),
  _LocationAnchor(
    city: 'Leipzig',
    district: 'Zentrum',
    latitude: 51.3397,
    longitude: 12.3731,
  ),
  _LocationAnchor(
    city: 'Bremen',
    district: 'Mitte',
    latitude: 53.0793,
    longitude: 8.8017,
  ),
  _LocationAnchor(
    city: 'Hannover',
    district: 'Mitte',
    latitude: 52.3759,
    longitude: 9.7320,
  ),
  _LocationAnchor(
    city: 'Dresden',
    district: 'Altstadt',
    latitude: 51.0504,
    longitude: 13.7373,
  ),
  _LocationAnchor(
    city: 'Oldenburg',
    district: 'Zentrum',
    latitude: 53.1435,
    longitude: 8.2146,
  ),
];
