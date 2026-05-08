import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SecureScreenService {
  SecureScreenService._();

  static final SecureScreenService instance = SecureScreenService._();
  static const MethodChannel _channel = MethodChannel('spargo/secure_screen');

  Future<void> enable() async {
    if (kIsWeb) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('enable');
    } on PlatformException {
      // Ignore unsupported targets.
    }
  }

  Future<void> disable() async {
    if (kIsWeb) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('disable');
    } on PlatformException {
      // Ignore unsupported targets.
    }
  }
}
