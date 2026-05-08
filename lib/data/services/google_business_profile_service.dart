import 'dart:convert';

import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../../core/config/firebase_functions_config.dart';
import '../../domain/models/business_models.dart';
import '../../domain/models/nearby_place_models.dart';

class GoogleBusinessProfileService {
  GoogleBusinessProfileService({
    firebase_auth.FirebaseAuth? auth,
    http.Client? client,
  }) : _auth = auth ?? firebase_auth.FirebaseAuth.instance,
       _client = client ?? http.Client();

  static const String _scopeBusinessManage =
      'https://www.googleapis.com/auth/business.manage';
  static const String _businessQuotaMessage =
      'Google Business API Limit gerade erreicht. Bitte warte kurz und versuche es erneut.';

  final firebase_auth.FirebaseAuth _auth;
  final http.Client _client;

  _GoogleBusinessAuthorization? _cachedAuthorization;
  String _cachedAuthorizationEmail = '';
  List<BusinessGoogleProfileLink>? _cachedAccessibleLocations;
  final Map<String, List<BusinessGoogleProfileLink>>
  _cachedMatchingLinksByPlace = <String, List<BusinessGoogleProfileLink>>{};

  Future<List<BusinessGoogleProfileLink>> fetchOwnedOrManagedLocations() async {
    final authorization = await _authorizeGoogleBusinessAccess();
    final cachedLocations = _cachedAccessibleLocations;
    if (cachedLocations != null && cachedLocations.isNotEmpty) {
      return cachedLocations;
    }

    final links = await _fetchAccessibleLocations(
      accessToken: authorization.accessToken,
      googleEmail: authorization.email,
    );

    if (links.isEmpty) {
      throw StateError(
        'In diesem Google-Konto wurde kein Google-Business-Standort mit Verwaltungszugriff gefunden.',
      );
    }

    _cachedAccessibleLocations = links;
    return links;
  }

  Future<String> authorizeGoogleBusinessIdentity() async {
    final authorization = await _authorizeGoogleBusinessAccess();
    return authorization.email.trim();
  }

  Future<List<BusinessGoogleProfileLink>> fetchMatchingOwnedOrManagedLocations(
    NearbyPlace place,
  ) async {
    final authorization = await _authorizeGoogleBusinessAccess();
    final normalizedPlaceId = place.id.trim();
    if (normalizedPlaceId.isEmpty) {
      throw StateError(
        'Der ausgewählte Ort hat keine gültige Google-Place-ID.',
      );
    }

    final cacheKey = _matchingPlaceCacheKey(
      googleEmail: authorization.email,
      placeId: normalizedPlaceId,
    );
    final cachedLinks = _cachedMatchingLinksByPlace[cacheKey];
    if (cachedLinks != null && cachedLinks.isNotEmpty) {
      return cachedLinks;
    }

    final links = await _fetchAccessibleLocations(
      accessToken: authorization.accessToken,
      googleEmail: authorization.email,
      placeId: normalizedPlaceId,
    );

    if (links.isEmpty) {
      throw StateError(
        'Dieses Google-Konto hat keinen Google-Business-Zugriff auf den ausgewählten Standort.',
      );
    }

    _cachedMatchingLinksByPlace[cacheKey] = links;
    return links;
  }

  Future<BusinessGoogleProfileLink> verifySelectedLocationAccess(
    BusinessGoogleProfileLink link,
  ) async {
    if (!link.isLinked) {
      throw StateError('Bitte wähle zuerst einen Google-Standort aus.');
    }
    if (link.placeId.trim().isEmpty) {
      throw StateError(
        'Dieser Google-Business-Standort hat keine gültige Google-Place-ID.',
      );
    }

    final authorization = await _authorizeGoogleBusinessAccess();
    final matchingCacheKey = _matchingPlaceCacheKey(
      googleEmail: authorization.email,
      placeId: link.placeId.trim(),
    );
    final accessibleLocations =
        _cachedMatchingLinksByPlace[matchingCacheKey] ??
        await _fetchAccessibleLocations(
          accessToken: authorization.accessToken,
          googleEmail: authorization.email,
          placeId: link.placeId.trim(),
        );
    if (accessibleLocations.isNotEmpty) {
      _cachedMatchingLinksByPlace[matchingCacheKey] = accessibleLocations;
    }
    BusinessGoogleProfileLink? verifiedLocation;
    for (final entry in accessibleLocations) {
      if (entry.placeId.trim() == link.placeId.trim() &&
          entry.locationName.trim() == link.locationName.trim()) {
        verifiedLocation = entry;
        break;
      }
    }
    if (verifiedLocation == null) {
      throw StateError(
        'Dieses Google-Konto hat keinen Google-Business-Zugriff auf den ausgewählten Standort.',
      );
    }

    return verifiedLocation.copyWith(
      googleUserEmail: authorization.email,
    );
  }

  Future<BusinessGoogleProfileLink> verifyCompanyIdentityForPlace(
    NearbyPlace place,
  ) async {
    final authorization = await _authorizeGoogleBusinessAccess();
    final normalizedPlaceId = place.id.trim();
    final normalizedWebsite = place.websiteUrl?.trim() ?? '';
    if (normalizedPlaceId.isEmpty) {
      throw StateError(
        'Der ausgewählte Ort hat keine gültige Google-Place-ID.',
      );
    }
    if (normalizedWebsite.isEmpty) {
      throw StateError(
        'Für diesen Standort fehlt eine offizielle Website. Die automatische Business-Prüfung ist deshalb gerade nicht möglich.',
      );
    }

    final response = await _client
        .post(
          firebaseFunctionUri('googleBusinessVerifyCompanyIdentity'),
          headers: const <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(<String, String>{
            'accessToken': authorization.accessToken,
            'googleEmail': authorization.email,
            'placeId': normalizedPlaceId,
            'placeName': place.name.trim(),
            'website': normalizedWebsite,
          }),
        )
        .timeout(const Duration(seconds: 25));

    final payload = _decode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final link = _linkFromProxyPayload(payload['link']);
      if (link == null || !link.isLinked) {
        throw StateError(
          'Die bestätigte Unternehmens-Identität konnte für diesen Standort gerade nicht aufgebaut werden.',
        );
      }
      return link.copyWith(googleUserEmail: authorization.email);
    }

    final message = _string(payload['error']).trim();
    throw StateError(
      message.isNotEmpty
          ? message
          : 'Die bestätigte Unternehmens-Identität konnte gerade nicht geprüft werden.',
    );
  }

  Future<BusinessGoogleProfileLink> verifyBusinessEvidenceDocument({
    required NearbyPlace place,
    required String fileName,
    required String mimeType,
    required String claimantName,
    required String claimedBusinessEmail,
    required Uint8List fileBytes,
  }) async {
    final normalizedClaimantName = claimantName.trim();
    final normalizedClaimedBusinessEmail =
        claimedBusinessEmail.trim().toLowerCase();
    if (normalizedClaimantName.isEmpty) {
      throw StateError(
        'Bitte gib zuerst die verantwortliche Person an, die auf der Unterlage genannt ist.',
      );
    }
    if (normalizedClaimedBusinessEmail.isEmpty) {
      throw StateError(
        'Bitte gib zuerst die Business-E-Mail ein, die später den Studio-Zugang bekommen soll.',
      );
    }

    final currentUser = _auth.currentUser;
    var sessionEmail = '';
    var firebaseIdToken = '';
    if (currentUser != null &&
        !currentUser.isAnonymous &&
        currentUser.emailVerified) {
      final currentEmail = currentUser.email?.trim().toLowerCase() ?? '';
      if (currentEmail.isNotEmpty &&
          currentEmail == normalizedClaimedBusinessEmail) {
        sessionEmail = currentEmail;
        firebaseIdToken = ((await currentUser.getIdToken()) ?? '').trim();
      }
    }
    final normalizedPlaceId = place.id.trim();
    if (normalizedPlaceId.isEmpty) {
      throw StateError(
        'Der ausgewählte Ort hat keine gültige Google-Place-ID.',
      );
    }
    if (fileBytes.isEmpty) {
      throw StateError(
        'Für die Dokumenten-Prüfung fehlt das hochgeladene offizielle Dokument.',
      );
    }
    final cachedAuthorization =
        _cachedAuthorizationEmail == normalizedClaimedBusinessEmail
            ? _cachedAuthorization
            : null;

    final response = await _client
        .post(
          firebaseFunctionUri('verifyBusinessEvidenceDocument'),
          headers: const <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(<String, String>{
            if (firebaseIdToken.isNotEmpty) 'firebaseIdToken': firebaseIdToken,
            if (sessionEmail.isNotEmpty) 'sessionEmail': sessionEmail,
            'claimedBusinessEmail': normalizedClaimedBusinessEmail,
            if (cachedAuthorization != null)
              'accessToken': cachedAuthorization.accessToken,
            if (cachedAuthorization != null)
              'googleEmail': cachedAuthorization.email,
            'claimantName': normalizedClaimantName,
            'placeId': normalizedPlaceId,
            'placeName': place.name.trim(),
            'placeAddress': place.address.trim(),
            'fileName': fileName.trim(),
            'mimeType': mimeType.trim(),
            'fileBase64': base64Encode(fileBytes),
          }),
        )
        .timeout(const Duration(seconds: 55));

    final payload = _decode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final link = _linkFromProxyPayload(payload['link']);
      if (link == null || !link.isLinked) {
        throw StateError(
          'Die Register- und Dokumentenprüfung konnte für diesen Standort gerade nicht aufgebaut werden.',
        );
      }
      return link.copyWith(
        googleUserEmail: normalizedClaimedBusinessEmail,
      );
    }

    final message = _string(payload['error']).trim();
    throw StateError(
      message.isNotEmpty
          ? message
          : 'Die Register- und Dokumentenprüfung konnte gerade nicht abgeschlossen werden.',
    );
  }

  Future<_GoogleBusinessAuthorization> _authorizeGoogleBusinessAccess({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedAuthorization != null) {
      return _cachedAuthorization!;
    }

    if (kIsWeb) {
      final hadCurrentUser = _auth.currentUser != null;
      final provider = firebase_auth.GoogleAuthProvider()
        ..addScope('email')
        ..addScope(_scopeBusinessManage)
        ..setCustomParameters(<String, String>{'prompt': 'select_account'});

      try {
        final credential = await _auth.signInWithPopup(provider);
        final authUser = credential.user ?? _auth.currentUser;
        final googleEmail = authUser?.email?.trim() ?? '';
        final oauthCredential =
            credential.credential as firebase_auth.OAuthCredential?;
        final accessToken = oauthCredential?.accessToken?.trim() ?? '';

        if (googleEmail.isEmpty) {
          throw StateError(
            'Google hat keine Business-E-Mail geliefert. Bitte versuche es erneut.',
          );
        }
        if (accessToken.isEmpty) {
          throw StateError(
            'Google hat kein Zugriffstoken für Google Business geliefert. Prüfe in Firebase Authentication den Google-Provider und versuche es erneut.',
          );
        }

        final authorization = _GoogleBusinessAuthorization(
          email: googleEmail,
          accessToken: accessToken,
        );
        return _cacheAuthorization(authorization);
      } on Object catch (error) {
        throw StateError(_friendlyWebBusinessAuthError(error));
      } finally {
        if (!hadCurrentUser && _auth.currentUser != null) {
          await _auth.signOut();
        }
      }
    }

    final signIn = GoogleSignIn(
      scopes: const <String>['email', _scopeBusinessManage],
    );
    final account = await signIn.signInSilently() ?? await signIn.signIn();
    if (account == null) {
      throw StateError('Die Google-Anmeldung wurde abgebrochen.');
    }

    final authentication = await account.authentication;
    final accessToken = authentication.accessToken?.trim() ?? '';
    if (accessToken.isEmpty) {
      throw StateError(
        'Google hat kein Zugriffstoken geliefert. Bitte versuche es erneut.',
      );
    }

    final authorization = _GoogleBusinessAuthorization(
      email: account.email,
      accessToken: accessToken,
    );
    return _cacheAuthorization(authorization);
  }

  String _friendlyWebBusinessAuthError(Object error) {
    if (error is firebase_auth.FirebaseAuthException) {
      switch (error.code) {
        case 'popup-blocked':
          return 'Das Google-Popup wurde blockiert. Bitte erlaube Popups für sparGO und versuche es erneut.';
        case 'popup-closed-by-user':
          return 'Die Google-Anmeldung wurde geschlossen, bevor sie abgeschlossen war.';
        case 'cancelled-popup-request':
          return 'Die Google-Anmeldung wurde durch eine andere Popup-Anfrage unterbrochen. Bitte versuche es erneut.';
        case 'operation-not-allowed':
          return 'Google-Login ist im Firebase-Projekt noch deaktiviert. Aktiviere in Firebase Console > Authentication > Sign-in method > Google den Provider, wähle eine Support-E-Mail und speichere.';
        case 'unauthorized-domain':
          return 'Diese Domain ist für die Google-Anmeldung noch nicht autorisiert. Trage spargo-app.web.app in Firebase Authentication als erlaubte Domain ein.';
        case 'account-exists-with-different-credential':
          return 'Für diese E-Mail existiert bereits eine andere Anmeldemethode.';
        case 'network-request-failed':
          return 'Netzwerkfehler bei der Google-Anmeldung. Bitte versuche es erneut.';
      }

      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) {
        final normalizedMessage = message.toLowerCase();
        if (_looksLikeQuotaProblem(normalizedMessage)) {
          return _businessQuotaMessage;
        }
        return 'Google Business Verbindung fehlgeschlagen: $message';
      }
    }

    final message = error.toString().replaceFirst('Exception: ', '').trim();
    if (message.isNotEmpty) {
      final normalizedMessage = message.toLowerCase();
      if (_looksLikeQuotaProblem(normalizedMessage)) {
        return _businessQuotaMessage;
      }
      return 'Google Business Verbindung fehlgeschlagen: $message';
    }
    return 'Google Business Verbindung fehlgeschlagen. Bitte versuche es erneut.';
  }

  Future<List<BusinessGoogleProfileLink>> _fetchAccessibleLocations({
    required String accessToken,
    required String googleEmail,
    String placeId = '',
  }) async {
    final delays = <Duration>[
      Duration.zero,
      const Duration(seconds: 2),
      const Duration(seconds: 6),
    ];
    StateError? lastQuotaError;

    for (var index = 0; index < delays.length; index += 1) {
      if (delays[index] > Duration.zero) {
        await Future<void>.delayed(delays[index]);
      }
      final response = await _client
          .post(
            firebaseFunctionUri('googleBusinessAccessibleLocations'),
            headers: const <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(<String, String>{
              'accessToken': accessToken,
              'googleEmail': googleEmail,
              if (placeId.trim().isNotEmpty) 'placeId': placeId.trim(),
            }),
          )
          .timeout(const Duration(seconds: 35));

      final payload = _decode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final locations = _list(payload['locations']);
        final links = locations
            .map(_linkFromProxyPayload)
            .whereType<BusinessGoogleProfileLink>()
            .toList(growable: false)
          ..sort(
            (a, b) => a.locationDisplayName.toLowerCase().compareTo(
              b.locationDisplayName.toLowerCase(),
            ),
          );
        return links;
      }

      final message = _string(payload['error']).trim();
      final isQuota = _looksLikeQuotaProblem(message.toLowerCase());
      if (isQuota) {
        lastQuotaError = StateError(_businessQuotaMessage);
        continue;
      }
      throw StateError(
        message.isNotEmpty
            ? message
            : 'Google Business Profile konnte nicht geladen werden (${response.statusCode}).',
      );
    }

    throw lastQuotaError ?? StateError(_businessQuotaMessage);
  }

  _GoogleBusinessAuthorization _cacheAuthorization(
    _GoogleBusinessAuthorization authorization,
  ) {
    final normalizedEmail = authorization.email.trim().toLowerCase();
    if (_cachedAuthorizationEmail != normalizedEmail) {
      _resetLookupCaches();
      _cachedAuthorizationEmail = normalizedEmail;
    }
    _cachedAuthorization = authorization;
    return authorization;
  }

  void _resetLookupCaches() {
    _cachedAccessibleLocations = null;
    _cachedMatchingLinksByPlace.clear();
  }

  String _matchingPlaceCacheKey({
    required String googleEmail,
    required String placeId,
  }) {
    return '${googleEmail.trim().toLowerCase()}|${placeId.trim()}';
  }

  bool _looksLikeQuotaProblem(String normalizedMessage) {
    return normalizedMessage.contains('quota exceeded') ||
        normalizedMessage.contains('requests per minute') ||
        normalizedMessage.contains('resource_exhausted') ||
        normalizedMessage.contains('quota') ||
        normalizedMessage.contains('limit');
  }

  BusinessGoogleProfileLink? _linkFromProxyPayload(dynamic rawLocation) {
    final map = _map(rawLocation);
    final locationName = _string(map['locationName']).trim();
    final placeId = _string(map['placeId']).trim();
    if (locationName.isEmpty || placeId.isEmpty) {
      return null;
    }

    return BusinessGoogleProfileLink(
      googleUserEmail: _string(map['googleUserEmail']).trim(),
      accountName: _string(map['accountName']).trim(),
      accountDisplayName: _string(map['accountDisplayName']).trim(),
      verificationSessionId: _string(map['verificationSessionId']).trim(),
      placeId: placeId,
      locationName: locationName,
      locationDisplayName: _string(map['locationDisplayName']).trim(),
      locationAddress: _string(map['locationAddress']).trim(),
      locationCity: _string(map['locationCity']).trim(),
      website: _string(map['website']).trim(),
      phone: _string(map['phone']).trim(),
      role: _string(map['role']).trim(),
    );
  }

  Map<String, dynamic> _decode(String body) {
    if (body.trim().isEmpty) {
      return const <String, dynamic>{};
    }
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }
}

class _GoogleBusinessAuthorization {
  const _GoogleBusinessAuthorization({
    required this.email,
    required this.accessToken,
  });

  final String email;
  final String accessToken;
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, entry) => MapEntry(key.toString(), entry));
  }
  return const <String, dynamic>{};
}

List<dynamic> _list(dynamic value) {
  if (value is List) {
    return value;
  }
  return const <dynamic>[];
}

String _string(dynamic value) {
  if (value is String) {
    return value;
  }
  return '';
}

List<String> _stringList(dynamic value) {
  return _list(value)
      .map((entry) => entry?.toString() ?? '')
      .where((entry) => entry.trim().isNotEmpty)
      .toList(growable: false);
}

