import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('Flutter widget harness renders sparGO shell text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('sparGO'))),
      ),
    );

    expect(find.text('sparGO'), findsOneWidget);
  });
}
