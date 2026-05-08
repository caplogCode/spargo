import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import 'app_location_types.dart';

AppLocationService createAppLocationService() => _IoLocationService();

class _IoLocationService implements AppLocationService {
  @override
  Future<AppLocationResult> requestCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw StateError('Standortdienste sind auf deinem Gerät deaktiviert.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        throw StateError('Standortfreigabe wurde abgelehnt.');
      }

      if (permission == LocationPermission.deniedForever) {
        throw StateError(
          'Standortfreigabe ist dauerhaft blockiert. Bitte aktiviere sie in den Geräteeinstellungen.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );

      return AppLocationResult(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } on MissingPluginException {
      throw StateError(
        'Standort-Plugin ist noch nicht registriert. Bitte starte die App komplett neu.',
      );
    }
  }
}
