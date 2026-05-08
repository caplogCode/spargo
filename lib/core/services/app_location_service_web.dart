import 'dart:html' as html;

import 'app_location_types.dart';

AppLocationService createAppLocationService() => _WebLocationService();

class _WebLocationService implements AppLocationService {
  @override
  Future<AppLocationResult> requestCurrentLocation() async {
    final geolocation = html.window.navigator.geolocation;
    if (geolocation == null) {
      throw StateError('Dieser Browser unterstützt keine Standortfreigabe.');
    }

    try {
      final position = await geolocation.getCurrentPosition(
        enableHighAccuracy: true,
        timeout: const Duration(seconds: 12),
        maximumAge: Duration.zero,
      );
      final coords = position.coords;
      if (coords == null ||
          coords.latitude == null ||
          coords.longitude == null) {
        throw StateError('Standort konnte nicht gelesen werden.');
      }
      return AppLocationResult(
        latitude: coords.latitude!.toDouble(),
        longitude: coords.longitude!.toDouble(),
      );
    } on html.PositionError catch (error) {
      if (error.code == html.PositionError.PERMISSION_DENIED) {
        throw StateError('Standortfreigabe wurde im Browser abgelehnt.');
      }
      if (error.code == html.PositionError.TIMEOUT) {
        throw StateError('Standortabfrage hat zu lange gedauert.');
      }
      throw StateError(
        error.message ?? 'Standort konnte im Browser nicht geladen werden.',
      );
    }
  }
}
