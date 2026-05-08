import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:spargo/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sparGO boots without crashing', (tester) async {
    app.main();

    for (var index = 0; index < 12; index++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(find.byType(MaterialApp), findsWidgets);
  });
}
