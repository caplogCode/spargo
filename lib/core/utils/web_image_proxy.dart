import 'package:flutter/foundation.dart';

import '../config/firebase_functions_config.dart';

String? webSafeImageUrl(String? rawUrl) {
  final value = rawUrl?.trim() ?? '';
  if (value.isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(value);
  if (uri == null) {
    return value;
  }

  if (!kIsWeb) {
    return value;
  }

  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return value;
  }

  final host = uri.host.toLowerCase();
  if (host.isEmpty || host == 'localhost' || host == '127.0.0.1') {
    return value;
  }

  final functionsHost =
      '$firebaseFunctionsRegion-$firebaseProjectId.cloudfunctions.net'
          .toLowerCase();
  if (host == functionsHost || host.endsWith('.cloudfunctions.net')) {
    return value;
  }

  return firebaseFunctionUri(
    'publicImageProxy',
    queryParameters: <String, String>{'url': value},
  ).toString();
}
