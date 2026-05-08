import 'app_location_types.dart';

AppLocationService createAppLocationService() => _UnsupportedLocationService();

class _UnsupportedLocationService implements AppLocationService {
  @override
  Future<AppLocationResult> requestCurrentLocation() {
    throw StateError(
      'Standort wird auf dieser Plattform gerade nicht unterstützt.',
    );
  }
}
