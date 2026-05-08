abstract class AppLocationService {
  Future<AppLocationResult> requestCurrentLocation();
}

class AppLocationResult {
  const AppLocationResult({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}
