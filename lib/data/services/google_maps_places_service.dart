import 'package:http/http.dart' as http;

import '../../domain/models/nearby_place_models.dart';
import 'google_maps_proxy_service.dart';

class GoogleMapsPlacesService {
  GoogleMapsPlacesService({required http.Client client}) : _client = client;

  final http.Client _client;

  Future<List<NearbyPlace>> searchBusinesses({required String query}) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 2) {
      return const <NearbyPlace>[];
    }

    final payload = await GoogleMapsProxyService(client: _client).post(
      'googleMapsBusinessSearch',
      <String, dynamic>{'query': normalizedQuery},
      timeout: const Duration(seconds: 18),
    );
    final results = payload?['places'];
    if (results is! List) {
      return const <NearbyPlace>[];
    }

    return results
        .whereType<Map>()
        .map(
          (entry) => _fromMap(
            Map<String, dynamic>.from(entry.cast<String, dynamic>()),
          ),
        )
        .whereType<NearbyPlace>()
        .toList(growable: false);
  }

  Future<List<NearbyPlace>> fetchNearbyPlaces({
    required NearbySearchArea area,
    required double radiusKm,
  }) async {
    final payload = await GoogleMapsProxyService(client: _client).post(
      'googleMapsNearbyPlaces',
      <String, dynamic>{
        'area': <String, dynamic>{
          'city': area.city,
          'district': area.district,
          'latitude': area.latitude,
          'longitude': area.longitude,
        },
        'radiusKm': radiusKm,
      },
      timeout: const Duration(seconds: 24),
    );
    final results = payload?['places'];
    if (results is! List) {
      return const <NearbyPlace>[];
    }

    return results
        .whereType<Map>()
        .map(
          (entry) => _fromMap(
            Map<String, dynamic>.from(entry.cast<String, dynamic>()),
          ),
        )
        .whereType<NearbyPlace>()
        .toList(growable: false);
  }

  NearbyPlace? _fromMap(Map<String, dynamic> map) {
    final id = map['id']?.toString().trim() ?? '';
    final name = map['name']?.toString().trim() ?? '';
    final address = map['address']?.toString().trim() ?? '';
    final latitude = (map['latitude'] as num?)?.toDouble();
    final longitude = (map['longitude'] as num?)?.toDouble();
    final primaryType = map['primaryType']?.toString().trim() ?? '';
    if (id.isEmpty ||
        name.isEmpty ||
        latitude == null ||
        longitude == null ||
        primaryType.isEmpty) {
      return null;
    }

    return NearbyPlace(
      id: id,
      name: name,
      address: address,
      latitude: latitude,
      longitude: longitude,
      primaryType: primaryType,
      types: _stringList(map['types']),
      rating: (map['rating'] as num?)?.toDouble() ?? 0,
      userRatingCount: (map['userRatingCount'] as num?)?.toInt() ?? 0,
      openNow: map['openNow'] as bool?,
      photoUrl: _stringOrNull(map['photoUrl']),
      googleMapsUri: _stringOrNull(map['googleMapsUri']),
      websiteUrl: _stringOrNull(map['websiteUrl']),
    );
  }

  List<String> _stringList(dynamic raw) {
    if (raw is! List) {
      return const <String>[];
    }
    return raw
        .map((entry) => entry?.toString().trim() ?? '')
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  String? _stringOrNull(dynamic raw) {
    final value = raw?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }
}
