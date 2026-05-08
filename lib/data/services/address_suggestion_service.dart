import 'package:http/http.dart' as http;
import 'google_maps_proxy_service.dart';

class AddressSuggestion {
  const AddressSuggestion({
    required this.addressLine,
    required this.displayName,
    required this.city,
    required this.district,
    required this.latitude,
    required this.longitude,
  });

  final String addressLine;
  final String displayName;
  final String city;
  final String district;
  final double latitude;
  final double longitude;
}

class AddressSuggestionService {
  AddressSuggestionService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<AddressSuggestion>> search(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 3) {
      return const <AddressSuggestion>[];
    }

    final payload = await GoogleMapsProxyService(client: _client).post(
      'googleMapsAddressSuggestions',
      <String, dynamic>{'query': normalizedQuery},
      timeout: const Duration(seconds: 10),
    );
    final results = payload?['suggestions'];
    if (results is! List) {
      return const <AddressSuggestion>[];
    }

    return results
        .whereType<Map>()
        .map(
          (entry) => _fromMap(
            Map<String, dynamic>.from(entry.cast<String, dynamic>()),
          ),
        )
        .where((entry) => entry.addressLine.isNotEmpty)
        .take(5)
        .toList(growable: false);
  }

  AddressSuggestion _fromMap(Map<String, dynamic> map) {
    return AddressSuggestion(
      addressLine: _read(map, 'addressLine'),
      displayName: _read(map, 'displayName'),
      city: _read(map, 'city'),
      district: _read(map, 'district'),
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0,
    );
  }

  String _read(Map<String, Object?> map, String key) {
    final value = map[key];
    return value is String ? value.trim() : '';
  }
}
