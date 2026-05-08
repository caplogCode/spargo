import 'package:flutter/foundation.dart';

const String googleMapsApiKey = String.fromEnvironment(
  'GOOGLE_MAPS_API_KEY',
  defaultValue: '',
);

bool get hasGoogleMapsApiKey {
  if (!kIsWeb) {
    return true;
  }
  final normalized = googleMapsApiKey.trim();
  return normalized.isNotEmpty && normalized != 'YOUR_GOOGLE_MAPS_API_KEY';
}
