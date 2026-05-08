// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

Future<bool> ensureGoogleMapsScriptLoaded(String apiKey) {
  if (apiKey.isEmpty) {
    return Future<bool>.value(false);
  }

  final existing = html.document.querySelector(
    'script[data-google-maps-loader="spargo"]',
  );
  if (existing != null) {
    return Future<bool>.value(true);
  }

  final script = html.ScriptElement()
    ..src =
        'https://maps.googleapis.com/maps/api/js?key=$apiKey&libraries=places'
    ..async = true
    ..defer = true
    ..dataset['googleMapsLoader'] = 'spargo';

  final completer = Completer<bool>();
  script.onLoad.first.then((_) {
    completer.complete(true);
  });
  script.onError.first.then((_) {
    completer.complete(false);
  });
  html.document.head?.append(script);
  return completer.future;
}
