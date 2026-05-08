import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kDeviceApprovalContinueBaseUrl = 'https://spargo-app.web.app/';

@immutable
class DeviceSessionInfo {
  const DeviceSessionInfo({
    required this.id,
    required this.label,
    required this.platformKey,
  });

  final String id;
  final String label;
  final String platformKey;
}

class DeviceSessionService {
  DeviceSessionService._();

  static final DeviceSessionService instance = DeviceSessionService._();
  static const String _deviceIdKey = 'device_session.id';
  String? _volatileDeviceId;

  Future<DeviceSessionInfo> load() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 3),
      );
      var id = prefs.getString(_deviceIdKey)?.trim() ?? '';
      if (id.isEmpty) {
        id = _nextDeviceId();
        await prefs
            .setString(_deviceIdKey, id)
            .timeout(const Duration(seconds: 2));
      }

      _volatileDeviceId = id;
      return _buildSession(id);
    } on Object catch (error) {
      debugPrint('DeviceSessionService.load fallback: $error');
      return _buildSession(_nextDeviceId());
    }
  }

  DeviceSessionInfo _buildSession(String id) {
    return DeviceSessionInfo(
      id: id,
      label: _deviceLabel(),
      platformKey: _platformKey(),
    );
  }

  String _nextDeviceId() {
    final existing = _volatileDeviceId?.trim() ?? '';
    if (existing.isNotEmpty) {
      return existing;
    }
    final generated = _generateDeviceId();
    _volatileDeviceId = generated;
    return generated;
  }

  String _platformKey() {
    if (kIsWeb) {
      return 'web';
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  String _deviceLabel() {
    if (kIsWeb) {
      return 'Browser';
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android-Gerät',
      TargetPlatform.iOS => 'iPhone oder iPad',
      TargetPlatform.macOS => 'Mac',
      TargetPlatform.windows => 'Windows-PC',
      TargetPlatform.linux => 'Linux-Gerät',
      TargetPlatform.fuchsia => 'Fuchsia-Gerät',
    };
  }

  String _generateDeviceId() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(18, (_) => random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }
}
