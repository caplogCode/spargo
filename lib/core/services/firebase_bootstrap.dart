import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import '../../firebase_options.dart';

abstract final class FirebaseBootstrap {
  static Future<void> ensureInitialized() async {
    WidgetsFlutterBinding.ensureInitialized();

    if (Firebase.apps.isNotEmpty) {
      return;
    }

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}
