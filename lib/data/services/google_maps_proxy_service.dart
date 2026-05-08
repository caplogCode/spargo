import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:http/http.dart' as http;

import '../../core/config/firebase_functions_config.dart';

class GoogleMapsProxyService {
  GoogleMapsProxyService({
    http.Client? client,
    firebase_auth.FirebaseAuth? auth,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _auth = auth ?? firebase_auth.FirebaseAuth.instance;

  final http.Client _client;
  final bool _ownsClient;
  final firebase_auth.FirebaseAuth _auth;

  Future<Map<String, dynamic>?> post(
    String functionName,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };

    try {
      final token = await _auth.currentUser?.getIdToken();
      if (token != null && token.trim().isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    } catch (_) {}

    try {
      final response = await _client
          .post(
            firebaseFunctionUri(functionName),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        return null;
      }

      return Map<String, dynamic>.from(decoded.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
